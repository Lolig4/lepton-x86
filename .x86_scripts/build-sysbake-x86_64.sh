#!/bin/bash
# Pre-boot Android once and keep the resulting /data, the x86_64 counterpart of
# .ci_scripts/build-sysbake.sh.
#
#   .x86_scripts/build-sysbake-x86_64.sh          bake if install-x86_64/sysbake is missing
#   CLEAN=1 .x86_scripts/build-sysbake-x86_64.sh  bake again
#
# Without a bake every first start runs Android's whole first boot (package
# scanning, dexopt); with it a container is up in a few seconds.

set -euo pipefail

X86_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${X86_DIR}/lepton_x86_lib.sh"

[[ -x "${COMPAT_TOOL_DIR}/lepton" ]] || die "no compat tool yet (run: .x86_scripts/build-compat_tool-x86_64.sh)"

if [[ -d "${COMPAT_TOOL_DIR}/sysbake" ]] && ! want_clean; then
    msg "install-x86_64/sysbake is already there, keeping it (CLEAN=1 to redo)"
    exit 0
fi

rm -rf "${COMPAT_TOOL_DIR}/sysbake"

msg "Baking Android userspace state"
# Lepton only bakes when it believes it runs in CI; there is nothing else
# CI-specific about it.
# No Steam Frame here: no Adreno/turnip, no SteamVR runtime, so the software
# path is what the bake has to be made with.
GITLAB_CI=1 \
LEPTON_FORCE_SOFTWARE="${LEPTON_FORCE_SOFTWARE:-true}" \
LEPTON_ALLOW_KMSG="${LEPTON_ALLOW_KMSG:-false}" \
    "${COMPAT_TOOL_DIR}/lepton" sysbake

# Host specific leftovers of the baking run; they would be shipped to every
# machine otherwise.
rm -f "${COMPAT_TOOL_DIR}/sysbake/lepton-onboot" "${COMPAT_TOOL_DIR}/sysbake/lepton-on-app-exit"
rm -rf "${COMPAT_TOOL_DIR}/sysbake/ssh"

msg "System bake stored in ${COMPAT_TOOL_DIR}/sysbake"
