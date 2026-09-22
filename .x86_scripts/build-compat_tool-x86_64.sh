#!/bin/bash
# Assemble a runnable compat tool from this checkout, the x86_64 counterpart of
# .ci_scripts/build-compat_tool.sh (which builds the aarch64 tarball for CI).
#
#   .x86_scripts/build-compat_tool-x86_64.sh
#
# Result: install-x86_64/, a directory Lepton can run straight out of.  An
# already baked install-x86_64/sysbake, and the sysbake.xattrs beside it, are
# kept: they are expensive to make and independent of the scripts.

set -euo pipefail

X86_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${X86_DIR}/lepton_x86_lib.sh"

require_cmd cargo

msg "Building apk-info-extractor for the host"
make -C "${PROJECT_DIR}/compat_tool/liblepton/apk_extractor"

msg "Assembling the compat tool in ${COMPAT_TOOL_DIR}"
mkdir -p "${COMPAT_TOOL_DIR}"
find "${COMPAT_TOOL_DIR}" -mindepth 1 -maxdepth 1 \
    ! -name sysbake ! -name sysbake.xattrs -exec rm -rf {} +
mkdir -p "${COMPAT_TOOL_DIR}/liblepton/apk_extractor/bin" "${COMPAT_TOOL_DIR}/images"

cp "${PROJECT_DIR}/compat_tool/lepton" "${COMPAT_TOOL_DIR}/"
ln -sf lepton "${COMPAT_TOOL_DIR}/fauxdroid"
cp -a "${PROJECT_DIR}/compat_tool/toolmanifest.vdf" "${COMPAT_TOOL_DIR}/"
cp -a "${PROJECT_DIR}/LICENSE.md" "${PROJECT_DIR}/LICENSES" "${COMPAT_TOOL_DIR}/"
cp -a "${PROJECT_DIR}"/compat_tool/liblepton/*.sh "${COMPAT_TOOL_DIR}/liblepton/"
cp -a "${PROJECT_DIR}/compat_tool/liblepton/lepton.seccomp.json" "${COMPAT_TOOL_DIR}/liblepton/"
cp -a "${PROJECT_DIR}/compat_tool/liblepton/openvrpaths.vrpath" "${COMPAT_TOOL_DIR}/liblepton/"
cp -ra "${PROJECT_DIR}/compat_tool/liblepton/perfetto" "${COMPAT_TOOL_DIR}/liblepton/"
cp -a "${PROJECT_DIR}/compat_tool/liblepton/apk_extractor/bin/apk-info-extractor" \
      "${COMPAT_TOOL_DIR}/liblepton/apk_extractor/bin/"
cp -ra "${PROJECT_DIR}/compat_tool/images/rootfs_overlay" "${COMPAT_TOOL_DIR}/images/"

if [[ -d "${PROJECT_DIR}/compat_tool/images/rootfs" ]]; then
    # reflink: free on btrfs/xfs, plain copy elsewhere
    cp -a --reflink=auto "${PROJECT_DIR}/compat_tool/images/rootfs" "${COMPAT_TOOL_DIR}/images/"
    cp -a "${PROJECT_DIR}/compat_tool/images/NOTICE.txt" "${COMPAT_TOOL_DIR}/images/" 2>/dev/null || true
else
    warn "no rootfs yet -- run .x86_scripts/prepare-rootfs-x86_64.sh"
fi

git -C "${PROJECT_DIR}" describe --tags --always > "${COMPAT_TOOL_DIR}/version.txt"

# The container runs straight from this tree (podman --rootfs), which SELinux
# only allows for container_file_t.
if command -v getenforce >/dev/null && [[ "$(getenforce)" == "Enforcing" ]]; then
    chcon -R -t container_file_t "${COMPAT_TOOL_DIR}"
fi

msg "Compat tool ready: ${COMPAT_TOOL_DIR}/lepton"
