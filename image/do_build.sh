#!/bin/bash

ROOT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

if ! podman image exists lepton-builder; then
    podman build -t lepton-builder builder_image -v ${ROOT_DIR}/../:/workdir
fi

if [[ ! -f "${ROOT_DIR}/.buildscripts/.bashrc" ]]; then
    echo "Baking .bashrc..."
    "${ROOT_DIR}/.buildscripts/bake_bashrc.sh"
fi

if [[ " $@ " == *" --update "* ]]; then
    "${ROOT_DIR}/.buildscripts/container.sh" "./.buildscripts/update_repositories.sh"
fi

"${ROOT_DIR}/.buildscripts/container.sh" "./.buildscripts/build_image.sh" && \
"${ROOT_DIR}/.buildscripts/package_rootfs.sh"
