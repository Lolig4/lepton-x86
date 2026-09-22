#!/bin/bash
# Shared helpers for the x86_64 build scripts.  Source, do not execute.

X86_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_DIR="$( cd -- "${X86_DIR}/.." &> /dev/null && pwd )"

LUNCH_TARGET="${LUNCH_TARGET:-lineage_lepton_x86_64_only-userdebug}"
JOBS="${JOBS:-$(nproc)}"
CCACHE_SIZE="${CCACHE_SIZE:-40G}"
STEAM_ROOT="${STEAM_ROOT:-${HOME}/.local/share/Steam}"
STEAM_TOOL_DIR="${STEAM_TOOL_DIR:-${STEAM_ROOT}/compatibilitytools.d/lepton-x86_64}"
COMPAT_TOOL_DIR="${COMPAT_TOOL_DIR:-${PROJECT_DIR}/install-x86_64}"

msg()  { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

require_cmd() { command -v "$1" >/dev/null || die "missing command: $1 (run: .x86_scripts/install-dependencies.sh)"; }

# Upstream container.sh refers to the builder image by its short name, which
# podman refuses to resolve unless a registry list allows it.
export CONTAINERS_REGISTRIES_CONF="${X86_DIR}/registries.conf"
# Optional, project scoped podman config for hosts whose default bridge network
# has no outbound connectivity (see .x86_scripts/containers.conf.example).
[[ -f "${X86_DIR}/containers.conf" ]] && export CONTAINERS_CONF="${X86_DIR}/containers.conf"

# SSH_AUTH_SOCK makes container.sh rewrite every https:// git URL to git@ via
# insteadOf.  Valve's developers have keys for gitlab.steamos.cloud; the public
# mirrors we sync from need plain HTTPS, so the agent is kept out.
#
# GitHub's edge protection answers 401 to the git shipped with Ubuntu 22.04 when
# it negotiates HTTP/2, while curl and newer clients from the same host get 200.
# Forcing HTTP/1.1 changes the ALPN handshake and gets through.  Passed as
# environment so it covers every git subprocess repo spawns.
GIT_HTTP11="GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.version GIT_CONFIG_VALUE_0=HTTP/1.1"

# Fedora runs SELinux in enforcing mode; upstream's container.sh bind-mounts the
# source tree without a :z/:Z label option, so the container would be denied even
# read access to it.  Relabel instead of patching container.sh.
# Undo with: restorecon -R <dir>
ensure_selinux_label() {
    local dir="${1}"
    command -v getenforce >/dev/null || return 0
    [[ "$(getenforce)" == "Enforcing" ]] || return 0
    local ctx
    ctx="$(ls -Zd "${dir}" | awk '{print $1}')"
    if [[ "${ctx}" != *container_file_t* ]]; then
        msg "Relabelling ${dir} for container access (SELinux)"
        chcon -R -t container_file_t "${dir}"
    fi
}

builder_image() {
    require_cmd podman
    ensure_selinux_label "${PROJECT_DIR}"
    # Always run the build: layer caching makes an unchanged Containerfile a
    # no-op, and a changed one (patch 0004) must actually take effect.
    msg "Building/refreshing the lepton-builder image"
    # --network=host: the builder only needs outbound apt/git access, and the
    # default bridge has proven fragile across hosts.
    podman build --network=host -t lepton-builder \
        "${PROJECT_DIR}/image/builder_image" -v "${PROJECT_DIR}:/workdir"
    if [[ ! -f "${PROJECT_DIR}/image/.buildscripts/.bashrc" ]]; then
        msg "Baking the builder .bashrc"
        env -u SSH_AUTH_SOCK "${PROJECT_DIR}/image/.buildscripts/bake_bashrc.sh"
    fi
}

in_builder() {
    env -u SSH_AUTH_SOCK "${PROJECT_DIR}/image/.buildscripts/container.sh" "$@" 2>&1 | stdbuf -oL tr -d '\r'
}

# CLEAN=1 (or --clean) means: redo the expensive step even though its output is
# already there.
want_clean() {
    [[ "${CLEAN:-0}" == "1" ]] || [[ "${CLEAN:-}" == "true" ]]
}
