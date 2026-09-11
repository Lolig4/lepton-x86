#pragma once
/*
 * ubpf_syscall.h — Userspace dummy bpf(2) syscall implementation
 *
 * Drop-in shim that intercepts calls to bpf() (or the wrapper below) and
 * services them entirely in userspace without requiring CAP_BPF / root or
 * a kernel that supports eBPF.  All state lives in the process address
 * space; nothing is loaded into the kernel.
 *
 * Usage
 * -----
 *   #include "ubpf_syscall.h"
 *
 *   // Either call ubpf_syscall() directly ...
 *   int fd = ubpf_syscall(BPF_MAP_CREATE, &attr, sizeof(attr));
 *
 *   // ... or install the LD_PRELOAD-style override so that existing code
 *   // calling the real bpf() libc wrapper is redirected automatically:
 *   ubpf_install_override();   // must be called once at program start
 *
 * Thread safety
 * -------------
 * All internal tables are protected by a single mutex.  The implementation
 * is therefore safe to use from multiple threads, though not optimised for
 * high concurrency.
 */

#ifndef _UBPF_SYSCALL_H
#define _UBPF_SYSCALL_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stddef.h>
#include <errno.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/file.h>

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-value"

#include <fcntl.h>
#ifdef __linux__
# include <sys/syscall.h>
# ifndef MFD_CLOEXEC
#  define MFD_CLOEXEC 1U
# endif
#endif

#define UBPF_ROOT_DEFAULT "/sys/fs/bpf/.ubpf"

static const char *ubpf_root(void) {
    const char *e = getenv("UBPF_ROOT");
    return (e && e[0]) ? e : UBPF_ROOT_DEFAULT;
}

/* Build a path under the ubpf root.  dst must be at least 256 bytes. */
static void ubpf_path(char *dst, size_t dstsz,
                      const char *subdir, const char *name) {
    snprintf(dst, dstsz, "%s/%s/%s", ubpf_root(), subdir, name);
}

static void ensure_dirs(void) {
    char p[256];
    const char *r = ubpf_root();
    mkdir(r, 0700);
    snprintf(p, sizeof(p), "%s/maps",   r); mkdir(p, 0700);
    snprintf(p, sizeof(p), "%s/progs",  r); mkdir(p, 0700);
    snprintf(p, sizeof(p), "%s/attach", r); mkdir(p, 0700);
}

/* =========================================================================
 * On-disk header — written at offset 0 of every backing file
 * ========================================================================= */

#define UBPF_MAGIC    0x55425046u  /* "UBPF" */
#define UBPF_VERSION  1u

typedef struct {
    __u32 magic;
    __u32 version;
    __u32 obj_type;      /* OBJ_MAP or OBJ_PROG */
    __u32 map_type;      /* BPF_MAP_TYPE_* (maps only) */
    __u32 key_size;
    __u32 value_size;
    __u32 max_entries;
    __u32 map_flags;
    __u32 n_entries;     /* live KV count (maps only) */
    __u32 prog_type;     /* BPF_PROG_TYPE_* (progs only) */
    __u32 insn_cnt;      /* number of 8-byte instructions (progs only) */
    char  name[16];
    __u32 _pad[1];       /* reserved, keeps header 64 bytes */
} ubpf_file_hdr_t;

/* Map file layout after the header:
 *   slot[i].key   at hdr_size + i*(key_size+value_size)
 *   slot[i].value at hdr_size + i*(key_size+value_size) + key_size
 *   valid[i] bit  at bitmap_off + i/8, bit i%8
 */
static size_t map_slot_size(const ubpf_file_hdr_t *h) {
    return (size_t)h->key_size + (size_t)h->value_size;
}
static size_t map_data_offset(void) {
    return sizeof(ubpf_file_hdr_t);
}
static size_t map_bitmap_offset(const ubpf_file_hdr_t *h) {
    return map_data_offset() + (size_t)h->max_entries * map_slot_size(h);
}
static size_t map_file_size(const ubpf_file_hdr_t *h) {
    size_t bm = ((size_t)h->max_entries + 7u) / 8u;
    return map_bitmap_offset(h) + bm;
}
static size_t prog_file_size(const ubpf_file_hdr_t *h) {
    return sizeof(ubpf_file_hdr_t) + (size_t)h->insn_cnt * 8u;
}

/* =========================================================================
 * Debug helper
 * ========================================================================= */

static void dbg(const char *fmt, ...) {
#ifdef UBPF_DEBUG
    va_list ap;
    va_start(ap, fmt);
    fprintf(stderr, "[ubpf] ");
    vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);
    va_end(ap);
#else
    (void)fmt;
#endif
}

/* =========================================================================
 * Object types (in-memory)
 * ========================================================================= */

typedef enum {
    OBJ_NONE = 0,
    OBJ_MAP  = 1,
    OBJ_PROG = 2,
    OBJ_PIN  = 3
} obj_type_t;

typedef struct {
    obj_type_t  type;
    int         fd;          /* real OS fd (open of backing file) */
    void       *mapping;     /* mmap base, MAP_SHARED on the backing file */
    size_t      mapping_size;
    char        backing[256];/* path of the backing file */
    union {
        struct {
            __u32 map_type;
            __u32 key_size;
            __u32 value_size;
            __u32 max_entries;
            __u32 map_flags;
            char  name[16];
        } map;
        struct {
            __u32 prog_type;
            char  name[16];
            __u32 insn_cnt;
        } prog;
        struct {
            int real_fd; /* fd of the resolved object */
        } pin;
    } u;
} obj_t;

/* =========================================================================
 * mmap helpers
 * ========================================================================= */

static void *map_file_mmap(int fd, size_t sz) {
    void *p = mmap(NULL, sz, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (p == MAP_FAILED) return NULL;
    return p;
}

static void *map_file_mmap_ro(int fd, size_t sz) {
    void *p = mmap(NULL, sz, PROT_READ, MAP_SHARED, fd, 0);
    if (p == MAP_FAILED) return NULL;
    return p;
}

static ubpf_file_hdr_t *obj_hdr(const obj_t *o) {
    return (ubpf_file_hdr_t *)o->mapping;
}

/* Slot accessors for map files */
static void *slot_key(const obj_t *o, __u32 i) {
    char *base = (char *)o->mapping + map_data_offset();
    return base + (size_t)i * map_slot_size(obj_hdr(o));
}
static void *slot_val(const obj_t *o, __u32 i) {
    return (char *)slot_key(o, i) + obj_hdr(o)->key_size;
}
static int slot_valid(const obj_t *o, __u32 i) {
    unsigned char *bm = (unsigned char *)o->mapping + map_bitmap_offset(obj_hdr(o));
    return (bm[i / 8u] >> (i % 8u)) & 1;
}
static void slot_set_valid(const obj_t *o, __u32 i, int v) {
    unsigned char *bm = (unsigned char *)o->mapping + map_bitmap_offset(obj_hdr(o));
    if (v) bm[i / 8u] |=  (unsigned char)(1u << (i % 8u));
    else   bm[i / 8u] &= (unsigned char)~(1u << (i % 8u));
}

/* =========================================================================
 * fd -> obj_t open-addressing hash table (in-process only)
 * ========================================================================= */

#define FD_HT_INIT_CAP 64

typedef struct { int fd; obj_t *obj; } ht_slot_t;

static ht_slot_t      *ht_slots = NULL;
static size_t          ht_cap   = 0;
static size_t          ht_used  = 0;
static pthread_mutex_t fd_table_lock = PTHREAD_MUTEX_INITIALIZER;

static void ht_init(void) {
    size_t i;
    if (ht_slots) return;
    ht_slots = (ht_slot_t *)calloc(FD_HT_INIT_CAP, sizeof(ht_slot_t));
    if (!ht_slots) { perror("ubpf: ht_init"); abort(); }
    ht_cap = FD_HT_INIT_CAP;
    for (i = 0; i < ht_cap; i++) ht_slots[i].fd = -1;
}
static void ht_grow(void) {
    size_t nc = ht_cap * 2, i, j;
    ht_slot_t *ns = (ht_slot_t *)calloc(nc, sizeof(ht_slot_t));
    if (!ns) { perror("ubpf: ht_grow"); abort(); }
    for (i = 0; i < nc; i++) ns[i].fd = -1;
    for (i = 0; i < ht_cap; i++) {
        if (ht_slots[i].fd == -1) continue;
        j = ((unsigned)ht_slots[i].fd) & (nc - 1);
        while (ns[j].fd != -1) j = (j + 1) & (nc - 1);
        ns[j] = ht_slots[i];
    }
    free(ht_slots); ht_slots = ns; ht_cap = nc;
}
static void ht_put(int fd, obj_t *obj) {
    size_t i;
    ht_init();
    if (ht_used * 4 >= ht_cap * 3) ht_grow();
    i = ((unsigned)fd) & (ht_cap - 1);
    while (ht_slots[i].fd != -1 && ht_slots[i].fd != fd)
        i = (i + 1) & (ht_cap - 1);
    ht_slots[i].fd = fd; ht_slots[i].obj = obj; ht_used++;
}
static obj_t *ht_get(int fd) {
    size_t i;
    if (!ht_slots || fd < 0) return NULL;
    i = ((unsigned)fd) & (ht_cap - 1);
    while (ht_slots[i].fd != -1) {
        if (ht_slots[i].fd == fd) return ht_slots[i].obj;
        i = (i + 1) & (ht_cap - 1);
    }
    return NULL;
}
#if 0
static void ht_remove(int fd) {
    size_t i, j, k;
    if (!ht_slots) return;
    i = ((unsigned)fd) & (ht_cap - 1);
    while (ht_slots[i].fd != -1 && ht_slots[i].fd != fd)
        i = (i + 1) & (ht_cap - 1);
    if (ht_slots[i].fd == -1) return;
    ht_slots[i].fd = -1; ht_used--;
    j = (i + 1) & (ht_cap - 1);
    while (ht_slots[j].fd != -1) {
        ht_slot_t tmp = ht_slots[j];
        ht_slots[j].fd = -1; ht_used--;
        k = ((unsigned)tmp.fd) & (ht_cap - 1);
        while (ht_slots[k].fd != -1) k = (k + 1) & (ht_cap - 1);
        ht_slots[k] = tmp; ht_used++;
        j = (j + 1) & (ht_cap - 1);
    }
}
#endif

/* =========================================================================
 * Object lifecycle
 * ========================================================================= */

static obj_t *get_obj(int fd, obj_type_t expected) {
    obj_t *o = ht_get(fd);
    if (!o) { errno = EBADF; return NULL; }
    if (expected != OBJ_NONE && o->type != expected) { errno = EINVAL; return NULL; }
    return o;
}

#if 0
static void obj_destroy(obj_t *o) {
    if (o->mapping && o->mapping != MAP_FAILED)
        munmap(o->mapping, o->mapping_size);
    free(o);
}
#endif

#if 0 // unused, we leak stuff...
static int free_fd(int fd) {
    obj_t *o = ht_get(fd);
    if (!o) { errno = EBADF; return -1; }
    ht_remove(fd);
    obj_destroy(o);
    return close(fd);
}
#endif

/*
 * Init an obj_t from an already-open fd whose backing file was written
 * by this library.  Used when another process receives an fd via SCM_RIGHTS
 * or opens a pinned path with BPF_OBJ_GET.
 */
static obj_t *obj_init_from_fd(int fd, const char *backing_path) {
    struct stat st;
    ubpf_file_hdr_t hdr;
    obj_t *o;
    ssize_t n;

    if (fstat(fd, &st) < 0) return NULL;

    /* read header */
    n = pread(fd, &hdr, sizeof(hdr), 0);
    if (n != (ssize_t)sizeof(hdr) || hdr.magic != UBPF_MAGIC) {
        errno = EBADF; return NULL;
    }

    o = (obj_t *)calloc(1, sizeof(*o));
    if (!o) return NULL;

    o->fd   = fd;
    o->type = (obj_type_t)hdr.obj_type;
    if (backing_path)
        snprintf(o->backing, sizeof(o->backing), "%s", backing_path);

    if (o->type == OBJ_MAP) {
        o->u.map.map_type    = hdr.map_type;
        o->u.map.key_size    = hdr.key_size;
        o->u.map.value_size  = hdr.value_size;
        o->u.map.max_entries = hdr.max_entries;
        o->u.map.map_flags   = hdr.map_flags;
        memcpy(o->u.map.name, hdr.name, sizeof(o->u.map.name));
        o->mapping_size = map_file_size(&hdr);
    } else if (o->type == OBJ_PROG) {
        o->u.prog.prog_type = hdr.prog_type;
        o->u.prog.insn_cnt  = hdr.insn_cnt;
        memcpy(o->u.prog.name, hdr.name, sizeof(o->u.prog.name));
        o->mapping_size = prog_file_size(&hdr);
    } else {
        free(o); errno = EINVAL; return NULL;
    }

    if ((o->mapping = map_file_mmap(fd, o->mapping_size)) == 0) {
        o->mapping = map_file_mmap_ro(fd, o->mapping_size);
    }
    if (!o->mapping) { free(o); return NULL; }

    return o;
}

/* =========================================================================
 * Command handlers
 * ========================================================================= */

/* ---- BPF_MAP_CREATE ---------------------------------------------------- */
static int cmd_map_create(union bpf_attr *attr) {
    ubpf_file_hdr_t hdr;
    char path[256];
    int fd;
    size_t fsz;
    obj_t *o;

    if (!attr) { errno = EINVAL; return -1; }

    ensure_dirs();

    /* Build a safe filename: name, or "map_<type>" if name is empty */
    if (attr->map_name[0])
        ubpf_path(path, sizeof(path), "maps", attr->map_name);
    else {
        char tmp[32];
        snprintf(tmp, sizeof(tmp), "map_%u", attr->map_type);
        ubpf_path(path, sizeof(path), "maps", tmp);
    }

    fchmodat(AT_FDCWD, path, 0700, 0);
    fd = open(path, O_RDWR | O_CREAT | O_TRUNC | O_CLOEXEC, 0700);
    if (fd < 0) return -1;
    fprintf(stderr,
        "CREATE: name=%s attr.flags=%u\n",
        attr->map_name,
        attr->map_flags);

    memset(&hdr, 0, sizeof(hdr));
    hdr.magic       = UBPF_MAGIC;
    hdr.version     = UBPF_VERSION;
    hdr.obj_type    = (unsigned)OBJ_MAP;
    hdr.map_type    = attr->map_type;
    hdr.key_size    = attr->key_size;
    hdr.value_size  = attr->value_size;
    hdr.max_entries = attr->max_entries;
    hdr.map_flags   = attr->map_flags;

    if (attr->map_type == BPF_MAP_TYPE_DEVMAP ||
        attr->map_type == BPF_MAP_TYPE_DEVMAP_HASH) {
        hdr.map_flags |= BPF_F_RDONLY_PROG;
    }

    hdr.n_entries   = 0;
    memcpy(hdr.name, attr->map_name, sizeof(hdr.name));

    fsz = map_file_size(&hdr);
    if (ftruncate(fd, (off_t)fsz) < 0) { close(fd); return -1; }
    if (pwrite(fd, &hdr, sizeof(hdr), 0) != (ssize_t)sizeof(hdr)) {
        close(fd); return -1;
    }

    o = (obj_t *)calloc(1, sizeof(*o));
    if (!o) { close(fd); errno = ENOMEM; return -1; }

    o->type              = OBJ_MAP;
    o->fd                = fd;
    o->u.map.map_type    = hdr.map_type;
    o->u.map.key_size    = hdr.key_size;
    o->u.map.value_size  = hdr.value_size;
    o->u.map.max_entries = hdr.max_entries;
    o->u.map.map_flags   = hdr.map_flags;
    o->mapping_size      = fsz;
    memcpy(o->u.map.name, hdr.name, sizeof(o->u.map.name));
    snprintf(o->backing, sizeof(o->backing), "%s", path);

    if ((o->mapping = map_file_mmap(fd, fsz)) == 0) {
        o->mapping = map_file_mmap_ro(fd, fsz);
    }
    if (!o->mapping) { free(o); close(fd); return -1; }

    ht_put(fd, o);
    dbg("BPF_MAP_CREATE type=%u key=%u val=%u max=%u -> fd=%d path=%s",
        hdr.map_type, hdr.key_size, hdr.value_size, hdr.max_entries,
        fd, path);
    return fd;
}

/* ---- BPF_MAP_UPDATE_ELEM ----------------------------------------------- */
static int cmd_map_update(union bpf_attr *attr) {
    obj_t *o;
    ubpf_file_hdr_t *hdr;
    const void *key, *value;
    __u64 flags;
    __u32 i, free_slot;

    if (!attr) { errno = EINVAL; return -1; }
    o = get_obj((int)attr->map_fd, OBJ_MAP);
    if (!o) return -1;

    key   = (const void *)(uintptr_t)attr->key;
    value = (const void *)(uintptr_t)attr->value;
    flags = attr->flags;
    if (!key || !value) { errno = EFAULT; return -1; }

    flock(o->fd, LOCK_EX);
    hdr = obj_hdr(o);

    /* scan for existing key */
    for (i = 0; i < hdr->max_entries; i++) {
        if (!slot_valid(o, i)) continue;
        if (memcmp(slot_key(o, i), key, hdr->key_size) == 0) {
            if (flags == BPF_NOEXIST) { flock(o->fd, LOCK_UN); errno = EEXIST; return -1; }
            memcpy(slot_val(o, i), value, hdr->value_size);
            flock(o->fd, LOCK_UN);
            dbg("BPF_MAP_UPDATE_ELEM fd=%d -> updated slot %u", o->fd, i);
            return 0;
        }
    }

    if (flags == BPF_EXIST) { flock(o->fd, LOCK_UN); errno = ENOENT; return -1; }
    if (hdr->n_entries >= hdr->max_entries) { flock(o->fd, LOCK_UN); errno = E2BIG; return -1; }

    /* find a free slot */
    free_slot = hdr->max_entries; /* sentinel */
    for (i = 0; i < hdr->max_entries; i++) {
        if (!slot_valid(o, i)) { free_slot = i; break; }
    }
    if (free_slot == hdr->max_entries) { flock(o->fd, LOCK_UN); errno = E2BIG; return -1; }

    memcpy(slot_key(o, free_slot), key,   hdr->key_size);
    memcpy(slot_val(o, free_slot), value, hdr->value_size);
    slot_set_valid(o, free_slot, 1);
    hdr->n_entries++;

    flock(o->fd, LOCK_UN);
    dbg("BPF_MAP_UPDATE_ELEM fd=%d -> inserted slot %u (total=%u)",
        o->fd, free_slot, hdr->n_entries);
    return 0;
}

/* ---- BPF_MAP_LOOKUP_ELEM ----------------------------------------------- */
static int cmd_map_lookup(union bpf_attr *attr) {
    obj_t *o;
    ubpf_file_hdr_t *hdr;
    const void *key;
    void *value_out;
    __u32 i;

    if (!attr) { errno = EINVAL; return -1; }
    o = get_obj((int)attr->map_fd, OBJ_MAP);
    if (!o) return -1;

    key       = (const void *)(uintptr_t)attr->key;
    value_out = (void *)(uintptr_t)attr->value;
    if (!key || !value_out) { errno = EFAULT; return -1; }

    flock(o->fd, LOCK_SH);
    hdr = obj_hdr(o);

    for (i = 0; i < hdr->max_entries; i++) {
        if (!slot_valid(o, i)) continue;
        if (memcmp(slot_key(o, i), key, hdr->key_size) == 0) {
            memcpy(value_out, slot_val(o, i), hdr->value_size);
            flock(o->fd, LOCK_UN);
            return 0;
        }
    }

    flock(o->fd, LOCK_UN);
    errno = ENOENT;
    return -1;
}

/* ---- BPF_MAP_DELETE_ELEM ----------------------------------------------- */
static int cmd_map_delete(union bpf_attr *attr) {
    obj_t *o;
    ubpf_file_hdr_t *hdr;
    const void *key;
    __u32 i;

    if (!attr) { errno = EINVAL; return -1; }
    o = get_obj((int)attr->map_fd, OBJ_MAP);
    if (!o) return -1;

    key = (const void *)(uintptr_t)attr->key;
    if (!key) { errno = EFAULT; return -1; }

    flock(o->fd, LOCK_EX);
    hdr = obj_hdr(o);

    for (i = 0; i < hdr->max_entries; i++) {
        if (!slot_valid(o, i)) continue;
        if (memcmp(slot_key(o, i), key, hdr->key_size) == 0) {
            slot_set_valid(o, i, 0);
            hdr->n_entries--;
            flock(o->fd, LOCK_UN);
            return 0;
        }
    }

    flock(o->fd, LOCK_UN);
    errno = ENOENT;
    return -1;
}

/* ---- BPF_MAP_GET_NEXT_KEY ---------------------------------------------- */
static int cmd_map_get_next_key(union bpf_attr *attr) {
    obj_t *o;
    ubpf_file_hdr_t *hdr;
    const void *key;
    void *next_out;
    __u32 i;

    if (!attr) { errno = EINVAL; return -1; }
    o = get_obj((int)attr->map_fd, OBJ_MAP);
    if (!o) return -1;

    key      = (const void *)(uintptr_t)attr->key;
    next_out = (void *)(uintptr_t)attr->next_key;
    if (!next_out) { errno = EFAULT; return -1; }

    flock(o->fd, LOCK_SH);
    hdr = obj_hdr(o);

    if (!key) {
        /* NULL key -> first occupied slot */
        for (i = 0; i < hdr->max_entries; i++) {
            if (slot_valid(o, i)) {
                memcpy(next_out, slot_key(o, i), hdr->key_size);
                flock(o->fd, LOCK_UN);
                return 0;
            }
        }
        flock(o->fd, LOCK_UN);
        errno = ENOENT;
        return -1;
    }

    /* find current key's slot, then return the next occupied slot after it */
    for (i = 0; i < hdr->max_entries; i++) {
        if (!slot_valid(o, i)) continue;
        if (memcmp(slot_key(o, i), key, hdr->key_size) == 0) {
            __u32 j;
            for (j = i + 1; j < hdr->max_entries; j++) {
                if (slot_valid(o, j)) {
                    memcpy(next_out, slot_key(o, j), hdr->key_size);
                    flock(o->fd, LOCK_UN);
                    return 0;
                }
            }
            flock(o->fd, LOCK_UN);
            errno = ENOENT;
            return -1;
        }
    }

    flock(o->fd, LOCK_UN);
    errno = ENOENT;
    return -1;
}

static int next_prog_counter = 0;

/* ---- BPF_PROG_LOAD ----------------------------------------------------- */
static int cmd_prog_load(union bpf_attr *attr) {
    ubpf_file_hdr_t hdr;
    char path[256];
    int fd;
    size_t fsz;
    obj_t *o;

    if (!attr) { errno = EINVAL; return -1; }
    ensure_dirs();

    char tmp[32];
    snprintf(tmp, sizeof(tmp), "prog_%u_%d", attr->prog_type, next_prog_counter++);
    ubpf_path(path, sizeof(path), "progs", tmp);

    memset(&hdr, 0, sizeof(hdr));
    hdr.magic     = UBPF_MAGIC;
    hdr.version   = UBPF_VERSION;
    hdr.obj_type  = (unsigned)OBJ_PROG;
    hdr.prog_type = attr->prog_type;
    hdr.insn_cnt  = attr->insn_cnt;
    memcpy(hdr.name, attr->prog_name, sizeof(hdr.name));

    fsz = prog_file_size(&hdr);

    fd = open(path, O_RDWR | O_CREAT | O_TRUNC | O_CLOEXEC, 0700);
    if (fd < 0) return -1;
    if (ftruncate(fd, (off_t)fsz) < 0) { close(fd); return -1; }
    if (pwrite(fd, &hdr, sizeof(hdr), 0) != (ssize_t)sizeof(hdr)) {
        close(fd);
        return -1;
    }

    /* write insn blob if provided */
    if (hdr.insn_cnt > 0 && attr->insns) {
        size_t sz = (size_t)hdr.insn_cnt * 8u;
        if (pwrite(fd, (const void *)(uintptr_t)attr->insns,
                   sz, sizeof(hdr)) != (ssize_t)sz) {
            close(fd);
            return -1;
        }
    }

    o = (obj_t *)calloc(1, sizeof(*o));
    if (!o) { close(fd); errno = ENOMEM; return -1; }

    o->type             = OBJ_PROG;
    o->fd               = fd;
    o->u.prog.prog_type = hdr.prog_type;
    o->u.prog.insn_cnt  = hdr.insn_cnt;
    o->mapping_size     = fsz;
    memcpy(o->u.prog.name, hdr.name, sizeof(o->u.prog.name));
    snprintf(o->backing, sizeof(o->backing), "%s", path);

    if ((o->mapping = map_file_mmap(fd, fsz)) == 0) {
        o->mapping = map_file_mmap_ro(fd, fsz);
    }
    if (!o->mapping) { free(o); close(fd); return -1; }

    ht_put(fd, o);
    dbg("BPF_PROG_LOAD type=%u insns=%u name='%s' -> fd=%d path=%s",
        hdr.prog_type, hdr.insn_cnt, hdr.name, fd, path);
    return fd;
}

/* ---- BPF_OBJ_PIN ------------------------------------------------------- */
static int cmd_obj_pin(union bpf_attr *attr) {
    const char *pin_path;
    int bpf_fd;
    obj_t *o;

    if (!attr) { errno = EINVAL; return -1; }
    pin_path = (const char *)(uintptr_t)attr->pathname;
    bpf_fd   = (int)attr->bpf_fd;
    if (!pin_path) { errno = EFAULT; return -1; }

    o = get_obj(bpf_fd, OBJ_NONE);
    if (!o) return -1;
    if (o->type == OBJ_PIN) { errno = EINVAL; return -1; }
    if (!o->backing[0]) { errno = EINVAL; return -1; }

    /* Check for existing pin before creating */
    struct stat _st;
    if (lstat(pin_path, &_st) == 0) { errno = EEXIST; return -1; }

    if (symlink(o->backing, pin_path) < 0) return -1;

    dbg("BPF_OBJ_PIN path='%s' -> %s", pin_path, o->backing);
    return 0;
}

/* ---- BPF_OBJ_GET ------------------------------------------------------- */
static int cmd_obj_get(union bpf_attr *attr) {
    const char *pin_path;
    char real_path[256];
    ssize_t n;
    int fd;
    obj_t *o;

    if (!attr) { errno = EINVAL; return -1; }
    pin_path = (const char *)(uintptr_t)attr->pathname;
    if (!pin_path) { errno = EFAULT; return -1; }

    /* Resolve symlink to backing file path */
    n = readlink(pin_path, real_path, sizeof(real_path) - 1);
    if (n < 0) {
        /* Not a symlink — maybe caller passed the backing path directly */
        snprintf(real_path, sizeof(real_path), "%s", pin_path);
    } else {
        real_path[n] = '\0';
    }

    fchmodat(AT_FDCWD, real_path, 0700, 0);
    fd = open(real_path, O_RDWR | O_CLOEXEC);
    if (fd < 0) return -1;

    o = obj_init_from_fd(fd, real_path);
    if (!o) { close(fd); return -1; }

    ht_put(fd, o);
    dbg("BPF_OBJ_GET path='%s' -> fd=%d (backing=%s)", pin_path, fd, real_path);
    return fd;
}

/* ---- BPF_PROG_ATTACH --------------------------------------------------- */
/*
 * Attachment records are stored as lines in a file named
 *   UBPF_ATTACH/<target_inode>_<attach_type>
 * Each line is the backing-file path of the attached prog.
 * This makes attachments visible across processes.
 */
static void attach_record_path(char *buf, size_t bufsz,
                                int target_fd, __u32 attach_type) {
    struct stat st;
    char name[64];
    if (fstat(target_fd, &st) == 0)
        snprintf(name, sizeof(name), "%llu_%u",
                 (unsigned long long)st.st_ino, attach_type);
    else
        snprintf(name, sizeof(name), "fd%d_%u", target_fd, attach_type);
    ubpf_path(buf, bufsz, "attach", name);
}

static int cmd_prog_attach(union bpf_attr *attr) {
    int target_fd, prog_fd;
    __u32 atype;
    obj_t *prog_obj;
    char rec_path[256];
    FILE *f;

    if (!attr) { errno = EINVAL; return -1; }
    target_fd = (int)attr->target_fd;
    prog_fd   = (int)attr->attach_bpf_fd;
    atype     = attr->attach_type;

    if (prog_fd > 0) {
        prog_obj = get_obj(prog_fd, OBJ_PROG);
        if (!prog_obj) return -1;
    } else {
        prog_obj = NULL;
    }

    ensure_dirs();
    attach_record_path(rec_path, sizeof(rec_path), target_fd, atype);

    f = fopen(rec_path, "a");
    if (!f) return -1;
    fprintf(f, "%s\n", prog_obj ? prog_obj->backing : "(none)");
    fclose(f);

    dbg("BPF_PROG_ATTACH target=%d prog=%d type=%u -> %s",
        target_fd, prog_fd, atype, rec_path);
    return 0;
}

/* ---- BPF_PROG_DETACH --------------------------------------------------- */
static int cmd_prog_detach(union bpf_attr *attr) {
    int target_fd;
    __u32 atype;
    char rec_path[256];

    if (!attr) { errno = EINVAL; return -1; }
    target_fd = (int)attr->target_fd;
    atype     = attr->attach_type;

    attach_record_path(rec_path, sizeof(rec_path), target_fd, atype);
    unlink(rec_path); /* remove the whole record file; all progs detached */

    dbg("BPF_PROG_DETACH target=%d type=%u", target_fd, atype);
    return 0;
}

/* ---- BPF_PROG_QUERY ---------------------------------------------------- */
static int cmd_prog_query(union bpf_attr *attr) {
    int target_fd;
    __u32 atype, ids_cap, count;
    __u32 *ids_out;
    char rec_path[256];
    FILE *f;
    char line[256];

    if (!attr) { errno = EINVAL; return -1; }
    target_fd = (int)attr->query.target_fd;
    atype     = attr->query.attach_type;
    ids_out   = (__u32 *)(uintptr_t)attr->query.prog_ids;
    ids_cap   = attr->query.prog_cnt;
    count     = 0;

    attach_record_path(rec_path, sizeof(rec_path), target_fd, atype);
    f = fopen(rec_path, "r");
    if (f) {
        while (fgets(line, sizeof(line), f)) {
            /* strip newline */
            line[strcspn(line, "\n")] = '\0';
            if (ids_out && count < ids_cap) {
                /* Return the fd of the locally-open prog if we have it,
                 * otherwise open it. */
                __u32 k;
                ids_out[count] = 0;
                if (ht_slots) {
                    for (k = 0; k < (unsigned)ht_cap; k++) {
                        if (ht_slots[k].fd == -1) continue;
                        if (ht_slots[k].obj->type == OBJ_PROG &&
                            strcmp(ht_slots[k].obj->backing, line) == 0) {
                            ids_out[count] = (__u32)ht_slots[k].fd;
                            break;
                        }
                    }
                }
                if (ids_out[count] == 0) {
                    fchmodat(AT_FDCWD, line, 0700, 0);
                    int pfd = open(line, O_RDWR | O_CLOEXEC);
                    if (pfd >= 0) {
                        obj_t *po = obj_init_from_fd(pfd, line);
                        if (po) {
                            ht_put(pfd, po);
                            ids_out[count] = (__u32)pfd;
                        } else {
                            close(pfd);
                        }
                    }
                }
            }
            count++;
        }
        fclose(f);
    }

    attr->query.prog_cnt = count;
    fprintf(stderr, "BPF_PROG_QUERY target=%d type=%u -> %u progs", target_fd, atype, count);
    return 0;
}

/* ---- BPF_PROG_RUN ------------------------------------------------------ */
static int cmd_prog_run(union bpf_attr *attr) {
    int prog_fd;
    void *data_in, *data_out;
    __u32 in_sz, out_cap;

    if (!attr) { errno = EINVAL; return -1; }
    prog_fd = (int)attr->test.prog_fd;
    if (!get_obj(prog_fd, OBJ_PROG)) return -1;

    data_in  = (void *)(uintptr_t)attr->test.data_in;
    data_out = (void *)(uintptr_t)attr->test.data_out;
    in_sz    = attr->test.data_size_in;
    out_cap  = attr->test.data_size_out;

    if (data_out && data_in && in_sz > 0) {
        __u32 cp = in_sz < out_cap ? in_sz : out_cap;
        memcpy(data_out, data_in, cp);
        attr->test.data_size_out = cp;
    } else {
        attr->test.data_size_out = 0;
    }
    attr->test.retval   = 0;
    attr->test.duration = 1;
    return 0;
}

/* ---- BPF_OBJ_GET_INFO_BY_FD ------------------------------------------- */

typedef struct {
    __u32 type; __u32 id;
    __u32 key_size; __u32 value_size; __u32 max_entries; __u32 map_flags;
    char  name[16];
    __u32 ifindex; __u32 btf_vmlinux_value_type_id;
    __u64 netns_dev; __u64 netns_ino;
    __u32 btf_id; __u32 btf_key_type_id; __u32 btf_value_type_id;
    __u32 pad; __u64 map_extra;
} ubpf_map_info_t;

typedef struct {
    __u32 type; __u32 id; __u32 tag[2];
    __u32 jited_prog_len; __u32 xlated_prog_len;
    __u64 jited_prog_insns; __u64 xlated_prog_insns;
    __u64 load_time; __u32 created_by_uid; __u32 nr_map_ids;
    __u64 map_ids; char name[16];
    __u32 ifindex; __u32 gpl_compatible;
    __u64 netns_dev; __u64 netns_ino;
    __u32 nr_jited_ksyms; __u32 nr_jited_func_lens;
    __u64 jited_ksyms; __u64 jited_func_lens;
    __u32 btf_id; __u32 func_info_rec_size; __u64 func_info;
    __u32 nr_func_info; __u32 nr_line_info;
    __u64 line_info; __u64 jited_line_info;
    __u32 nr_jited_line_info; __u32 line_info_rec_size;
    __u32 jited_line_info_rec_size; __u32 nr_prog_tags;
    __u64 prog_tags; __u64 run_time_ns; __u64 run_cnt;
    __u64 recursion_misses; __u32 verified_insns;
    __u32 attach_btf_obj_id; __u32 attach_btf_id;
} ubpf_prog_info_t;

static __u32 next_obj_id = 1u;

static int cmd_obj_get_info(union bpf_attr *attr) {
    int bpf_fd;
    void *info;
    __u32 info_sz, copy;
    obj_t *o;
    ubpf_file_hdr_t *hdr;

    if (!attr) { errno = EINVAL; return -1; }
    bpf_fd  = (int)attr->info.bpf_fd;
    info    = (void *)(uintptr_t)attr->info.info;
    info_sz = attr->info.info_len;
    if (!info) { errno = EFAULT; return -1; }

    o = get_obj(bpf_fd, OBJ_NONE);
    if (!o) return -1;
    if (o->type == OBJ_PIN) {
        o = get_obj(o->u.pin.real_fd, OBJ_NONE);
        if (!o) return -1;
    }

    hdr = obj_hdr(o);

    if (o->type == OBJ_MAP) {
        ubpf_map_info_t mi;
        memset(&mi, 0, sizeof(mi));
        mi.type        = hdr->map_type;
        mi.id          = next_obj_id++;
        mi.key_size    = hdr->key_size;
        mi.value_size  = hdr->value_size;
        mi.max_entries = hdr->max_entries;
        mi.map_flags   = hdr->map_flags;
        memcpy(mi.name, hdr->name, sizeof(mi.name));
        copy = (info_sz < (__u32)sizeof(mi)) ? info_sz : (__u32)sizeof(mi);
        memcpy(info, &mi, copy);
        attr->info.info_len = (__u32)sizeof(mi);
    } else if (o->type == OBJ_PROG) {
        ubpf_prog_info_t pi;
        memset(&pi, 0, sizeof(pi));
        pi.type = hdr->prog_type;
        pi.id   = next_obj_id++;
        memcpy(pi.name, hdr->name, sizeof(pi.name));
        copy = (info_sz < (__u32)sizeof(pi)) ? info_sz : (__u32)sizeof(pi);
        memcpy(info, &pi, copy);
        attr->info.info_len = (__u32)sizeof(pi);
    } else {
        errno = EINVAL; return -1;
    }
    return 0;
}

/* =========================================================================
 * Main dispatch
 * ========================================================================= */

static int ubpf_syscall(int cmd, union bpf_attr *attr, unsigned int size) {
    int ret;
    (void)size;

char buf[256];
int n = snprintf(buf, sizeof(buf),
                 "BPF CMD: %u\n", cmd);
write(2, buf, (size_t)n);

    pthread_mutex_lock(&fd_table_lock);
    switch (cmd) {
    case BPF_MAP_CREATE:         ret = cmd_map_create(attr);       break;
    case BPF_MAP_UPDATE_ELEM:    ret = cmd_map_update(attr);       break;
    case BPF_MAP_LOOKUP_ELEM:    ret = cmd_map_lookup(attr);       break;
    case BPF_MAP_DELETE_ELEM:    ret = cmd_map_delete(attr);       break;
    case BPF_MAP_GET_NEXT_KEY:   ret = cmd_map_get_next_key(attr); break;
    case BPF_PROG_LOAD:          ret = cmd_prog_load(attr);        break;
    case BPF_OBJ_PIN:            ret = cmd_obj_pin(attr);          break;
    case BPF_OBJ_GET:            ret = cmd_obj_get(attr);          break;
    case BPF_PROG_ATTACH:        ret = cmd_prog_attach(attr);      break;
    case BPF_PROG_DETACH:        ret = cmd_prog_detach(attr);      break;
    case BPF_PROG_QUERY:         ret = cmd_prog_query(attr);       break;
    case BPF_PROG_RUN:           ret = cmd_prog_run(attr);         break;
    case BPF_OBJ_GET_INFO_BY_FD: ret = cmd_obj_get_info(attr);    break;
    default:
        errno = EINVAL; ret = -1;
        dbg("unknown cmd=%d", cmd);
        break;
    }
    pthread_mutex_unlock(&fd_table_lock);
    return ret;
}

/* =========================================================================
 * Public helpers
 * ========================================================================= */
#if 0
static int ubpf_close(int fd) {
    int ret;
    pthread_mutex_lock(&fd_table_lock);
    ret = ht_get(fd) ? free_fd(fd) : close(fd);
    pthread_mutex_unlock(&fd_table_lock);
    return ret;
}
#endif

#pragma GCC diagnostic pop

#ifdef __cplusplus
}
#endif
#endif /* _UBPF_SYSCALL_H */
