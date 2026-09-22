#!/bin/bash
# Unpack system.img/vendor.img into compat_tool/images/rootfs and, unless asked
# not to, add the ARM translator.
#
#   .x86_scripts/prepare-rootfs-x86_64.sh          unpack (skips if already there)
#   CLEAN=1 .x86_scripts/prepare-rootfs-x86_64.sh  unpack again
#   ARM_TRANSLATION=false .x86_scripts/...         x86_64 only, no ARM apps

set -euo pipefail

X86_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${X86_DIR}/lepton_x86_lib.sh"

ROOTFS="${PROJECT_DIR}/compat_tool/images/rootfs"

require_cmd sqfs2tar
[[ -f "${PROJECT_DIR}/image/system.img" ]] || die "no system.img (run: .x86_scripts/build-rootfs-x86_64.sh)"

if [[ -d "${ROOTFS}/system" ]] && ! want_clean; then
    msg "compat_tool/images/rootfs is already unpacked, keeping it (CLEAN=1 to redo)"
else
    msg "Unpacking system.img/vendor.img into the compat tool rootfs"
    "${PROJECT_DIR}/image/.buildscripts/package_rootfs.sh"
fi

# Two system apps have nothing to talk to in a container and say so loudly:
# com.android.phone restarts about 25 times a second without Valve's removed
# TelephonyProvider, and com.android.bluetooth aborts in bt_stack_manager
# without a Bluetooth HAL, which puts a "Bluetooth keeps stopping" dialog on
# the desktop.  Neither is a device this runs on, so both go.
for APP in priv-app/TeleService app/Bluetooth; do
    if [[ -d "${ROOTFS}/system/${APP}" ]]; then
        msg "Removing system/${APP} (it crash-loops without its hardware)"
        rm -rf "${ROOTFS}/system/${APP}"
    fi
done

# Most Android apps ship ARM code only.  Google's ndk_translation runs their
# arm64 code on x86_64; without it such an .apk fails to install with
# INSTALL_FAILED_NO_MATCHING_ABIS.  It is proprietary code from ChromeOS and is
# downloaded, not built, so it can be left out.
if [[ "${ARM_TRANSLATION:-true}" == "true" ]]; then
    "${X86_DIR}/install-arm-translation.sh" "${ROOTFS}"
else
    msg "Skipping the ARM translator (ARM_TRANSLATION=false)"
fi
