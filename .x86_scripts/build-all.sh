#!/bin/bash
# Everything a build machine can do: from a fresh checkout to a tarball.
#
#   .x86_scripts/build-all.sh
#   CLEAN=1 .x86_scripts/build-all.sh                     redo the expensive steps
#   IMAGES_FROM=host:/path/image .x86_scripts/build-all.sh  use images from a build machine
#
# Result: lepton-x86_64-<version>.tar.zst.  Nothing here runs Lepton, so this
# works on a headless build machine.  The system bake and the installation into
# Steam happen on the machine that runs the container, with
#   TARBALL=<file> .x86_scripts/install-steam-tool.sh
#
# The Android image is built once and then reused: it is the only step that
# takes hours, and nothing below it depends on the machine it was built on.
# CLEAN=1 is what asks for it to be made again.
#
# Steps, each also runnable on its own:
#   install-dependencies.sh        host packages (needs root)
#   apply-patches.sh               the x86_64 patch set, as commits
#   build-rootfs-x86_64.sh         sync + AOSP build  -> image/system.img
#   prepare-rootfs-x86_64.sh       unpack + ARM bridge -> compat_tool/images/rootfs
#   build-compat_tool-x86_64.sh    assemble            -> install-x86_64/
#   package-compat_tool-x86_64.sh  pack                -> lepton-x86_64-*.tar.zst
#
# To rebuild just the hwcomposer after changing it, use build-hwcomposer.sh and
# then build-compat_tool-x86_64.sh + package-compat_tool-x86_64.sh.

set -euo pipefail

X86_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${X86_DIR}/lepton_x86_lib.sh"

# Only fetch submodules that are not there yet: an update would check out the
# revision the superproject records and throw away their patch commits.
for sub in image/android_device_waydroid_waydroid \
           image/android_hardware_waydroid \
           image/android_vendor_waydroid; do
    if [[ "$(git -C "${PROJECT_DIR}" submodule status -- "${sub}")" == -* ]]; then
        git -C "${PROJECT_DIR}" submodule update --init --recursive -- "${sub}"
    fi
done

"${X86_DIR}/apply-patches.sh"
"${X86_DIR}/build-rootfs-x86_64.sh"
"${X86_DIR}/prepare-rootfs-x86_64.sh"
"${X86_DIR}/build-compat_tool-x86_64.sh"
"${X86_DIR}/build-sysbake-x86_64.sh"
"${X86_DIR}/package-compat_tool-x86_64.sh"

msg "Done"
