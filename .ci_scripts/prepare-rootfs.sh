#!/bin/bash

CI_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_DIR="${CI_DIR}/../"

"${PROJECT_DIR}/image/.buildscripts/package_rootfs.sh"

mkdir -p install-rootfs/images/rootfs
cp -ra "${PROJECT_DIR}"/compat_tool/images/rootfs/* install-rootfs/images/rootfs
cp -ra "${PROJECT_DIR}"/compat_tool/images/NOTICE.txt install-rootfs/images
cp -ra "${PROJECT_DIR}"/image/version.txt install-rootfs/images

tar --zstd -cf "${PROJECT_DIR}"/rootfs.tar.zst -C install-rootfs .
