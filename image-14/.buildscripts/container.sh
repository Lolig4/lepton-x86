#!/bin/bash

ROOT_DIR="$(dirname "$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )" )"

PODMAN_ARGS=(
    # Consistent hostname helps avoid invalidating build artifacts from container to container
    --hostname=lepton-build

    # Throw away any modifications to the container image itself, only volume mounts are persisted
    --rm

    # Interactive
    -it

    # Mount this directory in and start in that directory
    -v ${ROOT_DIR}:/workspace
    -w /workspace
)

# Make sure we can use the host ssh keys for "repo sync":
if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
    echo "Using host ssh agent during repo sync!"
    mkdir -p "${ROOT_DIR}/.buildscripts/root"

    # The github config is here because sometimes github ratelimits unauthenticated users
    cat <<'EOF' > "${ROOT_DIR}/.buildscripts/root/.gitconfig"
    [url "git@gitlab.steamos.cloud:"]
        insteadOf = https://gitlab.steamos.cloud/
    [url "git@github.com:"]
        insteadOf = https://github.com/
    [url "git@gitlab.com:"]
        insteadOf = https://gitlab.com/
EOF
    mkdir -p "${ROOT_DIR}/.buildscripts/root/.ssh"
    ssh-keyscan -H gitlab.steamos.cloud > "${ROOT_DIR}/.buildscripts/root/.ssh/known_hosts"
    ssh-keyscan -H gitlab.com >> "${ROOT_DIR}/.buildscripts/root/.ssh/known_hosts"
    ssh-keyscan -H github.com >> "${ROOT_DIR}/.buildscripts/root/.ssh/known_hosts"
    chmod 0600 ${ROOT_DIR}/.buildscripts/root/.ssh/known_hosts
    chmod 0700 "${ROOT_DIR}/.buildscripts/root/.ssh"

    # Not sure if this is useful
    cat "${HOME}/.gitconfig" >> "${ROOT_DIR}/.buildscripts/root/.gitconfig"

    # .gitconfig needs to be writeable and mounting the file itself results in EBUSY
    PODMAN_ARGS+=( -v ${ROOT_DIR}/.buildscripts/root:/root:rw,U )
    PODMAN_ARGS+=( -v $SSH_AUTH_SOCK:/root/ssh-agent )
    PODMAN_ARGS+=( --env SSH_AUTH_SOCK=/root/ssh-agent )
    PODMAN_ARGS+=( -v ${HOME}/.ssh:/root/.ssh:ro )
fi

if [[ -f "${ROOT_DIR}/.buildscripts/.bashrc" ]]; then
    # Mount our `.bashrc` file in as `~/.bashrc`, if it exists
    # This doesn't exist at first and must be baked.
    PODMAN_ARGS+=( -v ${ROOT_DIR}/.buildscripts/.bashrc:/root/.bashrc:ro )
fi

PODMAN_ARGS+=( 
    # Use this image to build
    lepton-builder:latest

    # Start bash
    /bin/bash -l
)

if [ "$#" -gt 0 ]; then
    PODMAN_ARGS+=( -c "$@" )
fi

podman run "${PODMAN_ARGS[@]}"
