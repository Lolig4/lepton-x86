#!/bin/bash

PROJECT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

"${PROJECT_DIR}/../image/.buildscripts/build_image.sh" --ci

LEPTON_ROOTFS_VERSION="$(git describe --tags --always)"

echo "${LEPTON_ROOTFS_VERSION}" > image/version.txt
