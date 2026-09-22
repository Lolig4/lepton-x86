#!/bin/bash
# Build the Android 11 x86_64 system/vendor images.
#
#   .x86_scripts/build-rootfs-x86_64.sh              build if image/system.img is missing
#   CLEAN=1 .x86_scripts/build-rootfs-x86_64.sh      build again even if it is there
#   IMAGES_FROM=<dir|host:dir> .x86_scripts/...      take images from an earlier build
#
# This is the expensive step: it syncs the LineageOS 18.1 tree (tens of GB) and
# compiles it (hours).  Everything after it is minutes at most, so the result is
# kept and reused until CLEAN=1 asks for a new one.
#
# IMAGES_FROM points at a directory (local or host:path) that holds system.img,
# vendor.img and NOTICE.txt from a previous run -- typically a build machine
# with more cores and disk than the machine the container will run on.

set -euo pipefail

X86_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${X86_DIR}/lepton_x86_lib.sh"

IMAGE_DIR="${PROJECT_DIR}/image"

if [[ -n "${IMAGES_FROM:-}" ]]; then
    msg "Importing images from ${IMAGES_FROM}"
    require_cmd rsync
    # --partial: the link to a build host can drop mid-transfer and the next
    # attempt then only fetches the rest.
    for attempt in 1 2 3 4 5 6; do
        if rsync -a --partial --info=progress2 \
                -e "ssh -o BatchMode=yes -o ServerAliveInterval=15" \
                "${IMAGES_FROM%/}/system.img" \
                "${IMAGES_FROM%/}/vendor.img" \
                "${IMAGES_FROM%/}/NOTICE.txt" \
                "${IMAGE_DIR}/"; then
            break
        fi
        (( attempt < 6 )) || die "transfer failed ${attempt} times"
        warn "transfer interrupted (attempt ${attempt}), resuming in 10 s"
        sleep 10
    done
    msg "Images imported"
    exit 0
fi

if [[ -f "${IMAGE_DIR}/system.img" ]] && ! want_clean; then
    msg "image/system.img is already there, keeping it (CLEAN=1 to rebuild)"
    exit 0
fi

builder_image

if [[ ! -f "${IMAGE_DIR}/output/.repo/manifest.xml" ]]; then
    avail="$(df --output=avail -BG "${PROJECT_DIR}" | tail -1 | tr -dc '0-9')"
    (( avail > 120 )) || warn "only ${avail} GB free -- the AOSP tree plus out/ wants well over 100 GB"
    msg "Syncing LineageOS 18.1 (shallow). This downloads tens of GB."
    in_builder "${GIT_HTTP11} ./.buildscripts/update_repositories.sh --ci"
fi

# ccache lives inside the bind-mounted image/ directory so it survives the
# throwaway build container.  It only accelerates the C/C++ half of AOSP -- the
# java/dex/metalava steps are unaffected -- but a from-scratch rebuild benefits
# a lot.  Incremental rebuilds are ninja's job anyway.
CCACHE_ENV="USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache CCACHE_DIR=/workspace/.ccache"

if [[ -d "${IMAGE_DIR}/output/out" ]]; then
    # The tree was built here before.  build_image.sh always re-applies the
    # waydroid patch set (which fails on an already patched tree) and runs
    # `make installclean`, so go straight to make and let ninja work out what
    # actually changed.
    msg "Rebuilding ${LUNCH_TARGET} in the existing tree with -j${JOBS}"
    in_builder "mkdir -p /workspace/.ccache && \
        CCACHE_DIR=/workspace/.ccache ccache -M ${CCACHE_SIZE} >/dev/null && \
        cd output && source build/envsetup.sh >/dev/null && \
        lunch ${LUNCH_TARGET} >/dev/null && \
        ${CCACHE_ENV} make systemimage vendorimage -j${JOBS}"

    # The tail of build_image.sh: the NOTICE and dense copies of the sparse
    # images, which is what package_rootfs.sh consumes.  (The symbols tarball
    # is skipped, it is only needed for crash symbolication.)
    msg "Converting the images and generating the NOTICE"
    in_builder "set -e; cd output && source build/envsetup.sh >/dev/null && \
        lunch ${LUNCH_TARGET} >/dev/null && \
        ./prebuilts/python/linux-x86/2.7.5/bin/python build/tools/generate-notice-files.py \
            -s \"\${OUT}/obj/NOTICE_FILES/src\" --title 'Lepton Android Licenses' \
            --text \"\${OUT}/NOTICE.txt\" && \
        rm -f /workspace/system.img /workspace/vendor.img && \
        simg2img \"\${OUT}/system.img\" /workspace/system.img && \
        simg2img \"\${OUT}/vendor.img\" /workspace/vendor.img && \
        cp \"\${OUT}/NOTICE.txt\" /workspace/NOTICE.txt"
else
    msg "Building ${LUNCH_TARGET} with -j${JOBS}"
    in_builder "mkdir -p /workspace/.ccache && \
        CCACHE_DIR=/workspace/.ccache ccache -M ${CCACHE_SIZE} >/dev/null && \
        ${GIT_HTTP11} LEPTON_JOBS=${JOBS} ${CCACHE_ENV} \
        ./.buildscripts/build_image.sh ${LUNCH_TARGET}"
fi

[[ -f "${IMAGE_DIR}/system.img" ]] || die "the build produced no system.img"
echo "$(git -C "${PROJECT_DIR}" describe --tags --always)" > "${IMAGE_DIR}/version.txt"
msg "Images built"
