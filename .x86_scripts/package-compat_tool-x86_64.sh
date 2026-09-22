#!/bin/bash
# Pack the assembled tool for transport, the x86_64 counterpart of the tarball
# .ci_scripts/build-compat_tool.sh produces.
#
#   .x86_scripts/package-compat_tool-x86_64.sh
#
# Result: lepton-x86_64-<version>.tar.zst in the project root -- the tool, the
# Android rootfs and the system bake, everything the target machine needs.  The
# bake is 8 MB and machine independent (it is Android's /data after its first
# boot), and Lepton refuses to start without one, so it travels along.

set -euo pipefail

X86_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${X86_DIR}/lepton_x86_lib.sh"

require_cmd zstd
[[ -x "${COMPAT_TOOL_DIR}/lepton" ]] || die "no compat tool yet (run: .x86_scripts/build-compat_tool-x86_64.sh)"
[[ -d "${COMPAT_TOOL_DIR}/images/rootfs" ]] || die "no rootfs in the compat tool (run: .x86_scripts/prepare-rootfs-x86_64.sh)"

[[ -d "${COMPAT_TOOL_DIR}/sysbake" ]] || die "no system bake (run: .x86_scripts/build-sysbake-x86_64.sh)"
[[ -f "${COMPAT_TOOL_DIR}/sysbake.xattrs" ]] \
    || die "the bake has no sysbake.xattrs (run: CLEAN=1 .x86_scripts/build-sysbake-x86_64.sh)"

OUT="${PROJECT_DIR}/lepton-x86_64-$(cat "${COMPAT_TOOL_DIR}/version.txt").tar.zst"
STAGE="${PROJECT_DIR}/.package"

# Pack what Steam actually needs: the same directory install-steam-tool.sh
# builds, wrapper, compatibilitytool.vdf, setup-host.sh and SELinux policy
# included.  The bare compat tool alone has no .vdf, and Steam then does not
# offer it in the compatibility list at all.
msg "Assembling the Steam tool for packing"
rm -rf "${STAGE}"
mkdir -p "${STAGE}"
STEAM_TOOL_DIR="${STAGE}/lepton-x86_64" "${X86_DIR}/install-steam-tool.sh" >/dev/null

msg "Packing ${OUT}"
rm -f "${OUT}"
# One directory at the top, so unpacking into compatibilitytools.d lands in
# lepton-x86_64/ no matter what the file is called.
# --xattrs: Android marks the active storage of every package with a
# `user.default` extended attribute.  Without it installd believes the baked
# /data/user_de is stale, deletes it and tries to rename /data/data over it --
# which fails with EXDEV on the overlay, takes the app data with it and brings
# system_server down.  Only Android's own `user.*` are packed: SELinux labels
# belong to the machine that unpacks, and setup-host.sh sets them there.
tar --zstd --xattrs --xattrs-include='user.*' -cf "${OUT}" -C "${STAGE}" lepton-x86_64
rm -rf "${STAGE}"

echo "  $(du -sh "${OUT}" | cut -f1)"
echo "  install it on the target machine with:"
echo "    tar --zstd --xattrs -xf $(basename "${OUT}") -C ~/.local/share/Steam/compatibilitytools.d/"
echo "    ~/.local/share/Steam/compatibilitytools.d/lepton-x86_64/setup-host.sh"
