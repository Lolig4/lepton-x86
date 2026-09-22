#!/bin/bash
# Pack the assembled tool for transport, the x86_64 counterpart of the tarball
# .ci_scripts/build-compat_tool.sh produces.
#
#   .x86_scripts/package-compat_tool-x86_64.sh
#
# Result: lepton-x86_64-<version>.tar.zst in the project root -- the tool plus
# the Android rootfs, everything the target machine needs.  It does not contain
# a system bake: that is made on the machine that will run the container.

set -euo pipefail

X86_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${X86_DIR}/lepton_x86_lib.sh"

require_cmd zstd
[[ -x "${COMPAT_TOOL_DIR}/lepton" ]] || die "no compat tool yet (run: .x86_scripts/build-compat_tool-x86_64.sh)"
[[ -d "${COMPAT_TOOL_DIR}/images/rootfs" ]] || die "no rootfs in the compat tool (run: .x86_scripts/prepare-rootfs-x86_64.sh)"

OUT="${PROJECT_DIR}/lepton-x86_64-$(cat "${COMPAT_TOOL_DIR}/version.txt").tar.zst"

msg "Packing ${OUT}"
rm -f "${OUT}"
tar --zstd -cf "${OUT}" -C "${COMPAT_TOOL_DIR}" \
    --exclude sysbake .

echo "  $(du -sh "${OUT}" | cut -f1)"
echo "  copy it over and unpack it with:"
echo "    TARBALL=<file> .x86_scripts/install-steam-tool.sh"
