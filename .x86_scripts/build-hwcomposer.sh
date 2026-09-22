#!/bin/bash
# Rebuild only the waydroid hwcomposer and put it into the unpacked rootfs.
#
#   .x86_scripts/build-hwcomposer.sh
#
# The hwcomposer is the part of the image that gets changed most often (it is
# what turns Android's layers into Wayland windows), and it is a single .so.
# Rebuilding it takes a couple of minutes against the existing AOSP tree,
# instead of rebuilding the whole image.
#
# Needs a synced tree from build-rootfs-x86_64.sh.  Sources are taken from the
# android_hardware_waydroid submodule, which is where the patch set changes
# them, and copied into the tree the build actually reads.

set -euo pipefail

X86_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${X86_DIR}/lepton_x86_lib.sh"

SRC="${PROJECT_DIR}/image/android_hardware_waydroid/hwcomposer"
TREE="${PROJECT_DIR}/image/output/hardware/waydroid/hwcomposer"
BUILT="${PROJECT_DIR}/image/output/out/target/product/lepton_x86_64_only/vendor/lib64/hw/hwcomposer.waydroid.so"
ROOTFS="${PROJECT_DIR}/compat_tool/images/rootfs"

[[ -d "${TREE}" ]] || die "no AOSP tree yet (run: .x86_scripts/build-rootfs-x86_64.sh)"

builder_image

msg "Copying the hwcomposer sources into the build tree"
rsync -a --delete "${SRC}/" "${TREE}/"

msg "Building hwcomposer.waydroid with -j${JOBS}"
in_builder "cd output && source build/envsetup.sh >/dev/null && \
    lunch ${LUNCH_TARGET} >/dev/null && \
    USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache CCACHE_DIR=/workspace/.ccache \
    m hwcomposer.waydroid -j${JOBS}"
# Same ccache settings as the image build on purpose: ccache is wired into the
# compiler command line, so switching it on and off between runs changes every
# rule and makes ninja redo half the tree.

[[ -f "${BUILT}" ]] || die "the build produced no hwcomposer.waydroid.so"

if [[ -d "${ROOTFS}" ]]; then
    # Replace by rename: the file may be mapped by a running container, and
    # overwriting it in place would corrupt that process.
    install -D "${BUILT}" "${ROOTFS}/vendor/lib64/hw/hwcomposer.waydroid.so.new"
    mv "${ROOTFS}/vendor/lib64/hw/hwcomposer.waydroid.so.new" \
       "${ROOTFS}/vendor/lib64/hw/hwcomposer.waydroid.so"
    msg "Installed into compat_tool/images/rootfs"
    echo "  next: .x86_scripts/build-compat_tool-x86_64.sh && .x86_scripts/package-compat_tool-x86_64.sh"
else
    warn "no unpacked rootfs yet -- run .x86_scripts/prepare-rootfs-x86_64.sh"
fi
