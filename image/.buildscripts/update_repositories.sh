#!/bin/bash

set -eo pipefail

ROOT_DIR="$(dirname "$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )" )"

IS_CI=false
if [[ "$1" == "--ci" ]]; then
    IS_CI=true
fi

if [ ! -f /run/.containerenv ] && [ ! -f /.dockerenv ]; then
    echo "You must run me inside podman or docker! I do things to git config --global and such, you REALLY don't want me touching your stuff."
    exit 1
fi


# Initialize/Update repositories with `repo`
mkdir -p "${ROOT_DIR}/output"
pushd "${ROOT_DIR}/output" >/dev/null
    REPO_INIT_ARGS=
    if [[ "$IS_CI" == "true" ]]; then
        REPO_INIT_ARGS="--partial-clone --depth=1"
    fi
    if [[ -f .repo/manifest.xml ]]; then
        repo forall -c 'git reset --hard ; git clean -ffdx' || true
    else
        repo init $REPO_INIT_ARGS -u https://github.com/LineageOS/android.git -b lineage-18.1 --git-lfs
    fi

    # From here on out, use the repo that it itself downloads
    REPO=${ROOT_DIR}/output/.repo/repo/repo

    REPO_SYNC_ARGS=
    if [[ "$IS_CI" == "true" ]]; then
        REPO_SYNC_ARGS="-c"
    fi

    # Sync just `build/make` because we need it for `copy_vendored_manifests.sh`
    ${REPO} sync $REPO_SYNC_ARGS build/make

    # Generate the `.repo/manifest.xml` file, then sync all projects down
    # We can use a very high parallelism here, because our `--reference` above
    # turns the vast majority of our network I/O into disk I/O.
    "${ROOT_DIR}/.buildscripts/copy_vendored_manifests.sh"
    if ! ${REPO} sync $REPO_SYNC_ARGS --force-sync --force-checkout --force-remove-dirty -j4; then
        ${REPO} sync $REPO_SYNC_ARGS --force-sync --force-checkout --force-remove-dirty -j1
    fi

    # Copy in vendored projects
    "${ROOT_DIR}/.buildscripts/copy_vendored_projects.sh"
popd >/dev/null
