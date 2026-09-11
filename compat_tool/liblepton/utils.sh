#!/bin/bash

function println()
{
    printf '%s\n' "$@"
}

function print()
{
    printf '%s' "$@"
}

function die()
{
    printf '%s\n' "$@" >&2
    exit 1
}

function container_pid()
{
    print "$(podman inspect -f '{{.State.Pid}}' "lepton-${LEPTON_CONTEXT}" 2>/dev/null || true)"
}

function gdb_port()
{
    if [[ -n "${LEPTON_GDB_PORT:-}" ]]; then
        print "${LEPTON_GDB_PORT}"
        return
    fi
    podman inspect -f '{{ index .Config.Labels "gdb_port" }}' "lepton-${1:-${LEPTON_CONTEXT}}" 2>/dev/null || true
}

function lldb_port()
{
    if [[ -n "${LEPTON_LLDB_PORT:-}" ]]; then
        print "${LEPTON_LLDB_PORT}"
        return
    fi
    podman inspect -f '{{ index .Config.Labels "lldb_port" }}' "lepton-${1:-${LEPTON_CONTEXT}}" 2>/dev/null || true
}

function adb_port()
{
    if [[ -n "${LEPTON_ADB_PORT:-}" ]]; then
        print "${LEPTON_ADB_PORT}"
        return
    fi
    podman inspect -f '{{ index .Config.Labels "adb_port" }}' "lepton-${1:-${LEPTON_CONTEXT}}" 2>/dev/null || true
}

# Faster alternative to invoking $(basename foo)
function lepton_basename()
{
    print "${1##*/}"
}

function wait_for_file()
{
    local FILE="$(lepton_basename "${1}")"
    local DIR="$(dirname "${1}")"
    local ALLOW_PREEXIST="${2:-}"
    mkdir -p "${DIR}"
    (
        uninherit_lepton_lock

        inotifywait -qq -e modify -e moved_to -e create -e delete_self --include="^${DIR}/(${FILE})?\$" "${DIR}"
    ) 2>/dev/null >/dev/null &
    local INOTIFY_PID="$!"

    if [[ "${ALLOW_PREEXIST}" != "--allow-preexist" ]] && [[ -e "${1}" ]]; then
        kill "${INOTIFY_PID}" 2>/dev/null >/dev/null || true
    fi
    wait "${INOTIFY_PID}" 2>/dev/null >/dev/null || true
}

function wait_for_container_file()
{
    if [[ "${1}" == "/data/"* ]]; then
        wait_for_file "$(data_mount_path)/${1#/data/}" "${2:-}"
    else
        die "Can't wait for file outside of /data: \"${1}\"."
    fi
}

STEAMVR_LOGS_DIR="$(steamvr logpath || true)"

function lepton_version()
{
    cat "$(dirname "${LEPTON_DIR}")/version.txt" 2>/dev/null ||
    git -C "${LEPTON_DIR}" describe HEAD 2>/dev/null ||
    echo "<unknown version>"
}

function lepton_rootfs_version()
{
    cat $(dirname "${LEPTON_DIR}")/images/version.txt 2>/dev/null ||
    echo "<unknown version>"
}

function lepton_log_file()
{
    local CONTEXT="${1:-${LEPTON_CONTEXT}}"
    print "${1:-/${STEAMVR_LOGS_DIR}/lepton-${CONTEXT}.log}"
}


function log_to_file()
{
    local LEPTON_LOG_FILE="$(lepton_log_file)"

    exec 1> >(uninherit_lepton_lock; grep --line-buffered -v "skipping destruction (fork without exec?)" | grep --line-buffered -v "from LD_PRELOAD cannot be preloaded" | tee -a "${LEPTON_LOG_FILE}" || true) 2>&1

    # When we start logging to file, we want to make it easy to differentiate different runs, so let's print empty lines, the date, and the PID:
    printf "\n\nLepton %s (rootfs %s) starting up at %s\n" "$(lepton_version)" "$(lepton_rootfs_version)" "$(date)"
}

function prepend_subsys()
{
    local SUBSYS="${1}"
    local COLOR="${_RED}"
    # Special-case sysbake
    if [[ "${SUBSYS}" == "sysbake" ]]; then
        COLOR="${_GREEN}"
    fi

    exec 1> >(sed -u "s/^/[${COLOR}${1}${_PLAIN}]: /")
    exec 2>&1
}

# Reads the value of a current setting and appends a new value onto
# the end of it, (colon-separated) but not including an empty entry
# at the beginning of the list.
function settings_path_insert()
{
    local VAR_NAME="${1}"
    local VALUE="${2}"

    cat <<-EOF
${VAR_NAME}=\$(settings get global ${VAR_NAME});
if [ "\${${VAR_NAME}}" = "null" ]; then
settings put global ${VAR_NAME} ${VALUE};
else
settings put global ${VAR_NAME} \${${VAR_NAME}}:${VALUE};
fi;
EOF
}

function colon_path_list()
{
    local IFS=:
    println "$*"
}

function lock_lepton()
{
    if ! flock --timeout 10 "${LEPTON_LOCKFD}"; then
        echo "WARNING: Failed to acquire the lepton lock."
    fi
}

function unlock_lepton()
{
    flock -u "${LEPTON_LOCKFD}"
}

function uninherit_lepton_lock()
{
    exec {LEPTON_LOCKFD}>&-
}

