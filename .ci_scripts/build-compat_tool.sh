#!/bin/bash

set -euo pipefail

CI_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_DIR="${CI_DIR}/../"

LEPTON_VERSION="$(git describe --tags --always)"

ARCH=aarch64

pushd compat_tool/liblepton/apk_extractor
make
popd

mkdir -p install
pushd install

cp ${PROJECT_DIR}/compat_tool/lepton .

# temp symlink
ln -sf lepton fauxdroid

cp -ra ${PROJECT_DIR}/compat_tool/toolmanifest.vdf .
cp -ra ${PROJECT_DIR}/README.md .
cp -ra ${PROJECT_DIR}/LICENSE.md .
cp -ra ${PROJECT_DIR}/LICENSES .
mkdir -p liblepton
cp -a ${PROJECT_DIR}/compat_tool/liblepton/*.sh liblepton
cp -a ${PROJECT_DIR}/compat_tool/liblepton/lepton.seccomp.json liblepton
cp -a ${PROJECT_DIR}/compat_tool/liblepton/openvrpaths.vrpath liblepton
cp -ra ${PROJECT_DIR}/compat_tool/liblepton/perfetto liblepton
mkdir -p images
cp -ra ${PROJECT_DIR}/compat_tool/images/rootfs_overlay images

mkdir -p liblepton/apk_extractor/bin
cp -a ${PROJECT_DIR}/compat_tool/liblepton/apk_extractor/bin/apk-info-extractor liblepton/apk_extractor/bin/apk-info-extractor

echo "${LEPTON_VERSION}" > version.txt

tar --zstd -cf "${PROJECT_DIR}"/compat_tool.tar.zst .

popd
