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

if [[ -d "${COMPAT_TOOL_DIR}/sysbake" ]] && [[ -f "${COMPAT_TOOL_DIR}/sysbake.xattrs" ]] && ! want_clean; then
    msg "install-x86_64/sysbake is already there, keeping it (CLEAN=1 to redo)"
    exit 0
fi

rm -rf "${COMPAT_TOOL_DIR}/sysbake" "${COMPAT_TOOL_DIR}/sysbake.xattrs"

# Lepton mounts Steam's socket into the container and podman refuses to start
# when the path does not exist.  A build machine has no Steam, and the bake does
# not talk to it, so an empty placeholder is enough.
if [[ ! -e "${HOME}/.steam/steam.pipe" ]]; then
    msg "Creating a placeholder for Steam's socket (no Steam on this machine)"
    mkdir -p "${HOME}/.steam"
    mkfifo "${HOME}/.steam/steam.pipe" 2>/dev/null || touch "${HOME}/.steam/steam.pipe"
fi

# Baking boots Android for real, and its hwcomposer is a Wayland client: on a
# build machine without a session there is nothing to connect to.  A headless
# weston is enough -- nothing is ever shown, the frames are thrown away.
BAKE_COMPOSITOR_PID=""
cleanup_compositor() {
    if [[ -n "${BAKE_COMPOSITOR_PID}" ]]; then
        kill "${BAKE_COMPOSITOR_PID}" 2>/dev/null || true
        wait "${BAKE_COMPOSITOR_PID}" 2>/dev/null || true
    fi
}
trap cleanup_compositor EXIT

if [[ -z "${WAYLAND_DISPLAY:-}" ]] || [[ ! -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/${WAYLAND_DISPLAY:-}" ]]; then
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    mkdir -p "${XDG_RUNTIME_DIR}"
    chmod 700 "${XDG_RUNTIME_DIR}"
    require_cmd weston

    export WAYLAND_DISPLAY="lepton-bake"
    rm -f "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}.lock"
    msg "Starting a headless compositor for the bake"
    # Weston 13 dropped the .so suffix from backend names, older ones need it.
    ( weston --backend=headless --socket="${WAYLAND_DISPLAY}" --width=1920 --height=1080 \
        || weston --backend=headless-backend.so --socket="${WAYLAND_DISPLAY}" --width=1920 --height=1080 \
    ) >"${PROJECT_DIR}/weston-bake.log" 2>&1 &
    BAKE_COMPOSITOR_PID="$!"

    for _ in $(seq 1 50); do
        [[ -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]] && break
        sleep 0.2
    done
    [[ -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]] \
        || die "the headless compositor did not come up (see weston-bake.log)"
fi

msg "Baking Android userspace state"
# Lepton only bakes when it believes it runs in CI; there is nothing else
# CI-specific about it.
# No Steam Frame here: no Adreno/turnip, no SteamVR runtime, so the software
# path is what the bake has to be made with.
# Upper bound for the whole thing: Lepton waits for a file Android writes and
# would wait for ever if it never appears.
timeout "${BAKE_TIMEOUT:-600}" env GITLAB_CI=1 \
LEPTON_FORCE_SOFTWARE="${LEPTON_FORCE_SOFTWARE:-true}" \
LEPTON_ALLOW_KMSG="${LEPTON_ALLOW_KMSG:-false}" \
    "${COMPAT_TOOL_DIR}/lepton" sysbake &
BAKE_PID="$!"

# Lepton waits for Android to write a profile file and has no timeout of its
# own: if the container dies on the way there it waits for ever.  Watch the
# container instead and fail loudly.
( 
    for _ in $(seq 1 120); do
        podman ps --format '{{.Names}}' | grep -q '^lepton-sysbake$' && break
        sleep 1
    done
    gone=0
    while kill -0 "${BAKE_PID}" 2>/dev/null; do
        if podman ps --format '{{.Names}}' | grep -q '^lepton-sysbake$'; then
            gone=0
        else
            gone=$((gone + 1))
            if (( gone > 10 )); then
                warn "the bake container is gone but the bake is still waiting -- stopping it"
                kill "${BAKE_PID}" 2>/dev/null || true
                break
            fi
        fi
        sleep 1
    done
) &
WATCHDOG_PID="$!"

BAKE_RESULT=0
wait "${BAKE_PID}" || BAKE_RESULT=$?
kill "${WATCHDOG_PID}" 2>/dev/null || true
wait "${WATCHDOG_PID}" 2>/dev/null || true
(( BAKE_RESULT == 0 )) || die "the bake failed (exit ${BAKE_RESULT}); see the log above"

# Host specific leftovers of the baking run; they would be shipped to every
# machine otherwise.
rm -f "${COMPAT_TOOL_DIR}/sysbake/lepton-onboot" "${COMPAT_TOOL_DIR}/sysbake/lepton-on-app-exit"
rm -rf "${COMPAT_TOOL_DIR}/sysbake/ssh"

# Android marks the storage a package actually uses with a `user.default`
# extended attribute, and keeps per-app state in more of them.  Transports lose
# those -- a Steam depot has no xattrs at all, and tar only keeps them when
# asked -- and installd then takes the baked /data/user_de for stale, deletes
# it and tries to rename /data/data over it.  On the overlay that rename fails
# with EXDEV, the app data is gone and system_server dies on the next boot.
# Lepton restores them from this file on every start (liblepton/baking.sh).
# Only `user.*`: SELinux labels describe the machine, not the bake.
msg "Saving the bake's extended attributes"
require_cmd getfattr
( cd "${COMPAT_TOOL_DIR}" && getfattr -R -h -d -m '^user\.' sysbake ) \
    > "${COMPAT_TOOL_DIR}/sysbake.xattrs"

msg "System bake stored in ${COMPAT_TOOL_DIR}/sysbake"
