#!/bin/bash

set -euo pipefail

IMAGE_DIR="$(dirname "$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )" )"
OUTPUT_DIR="$(dirname "${IMAGE_DIR}")/compat_tool/images"

for IMG_FILE in system.img vendor.img; do
    if [[ ! -f "${IMAGE_DIR}/${IMG_FILE}" ]]; then
        echo "ERROR: Cannot find ${IMG_FILE!}" >&2
        exit 1
    fi
done

TMP_DIR="$(mktemp -d)"

function cleanup()
{
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

# Slurp this up into a tarball:
echo -n "Copying rootfs to ${OUTPUT_DIR}..."

# Convert using sqfs2tar (avoids using root to mount) to tar and combine
# system
sqfs2tar "${IMAGE_DIR}/system.img" > "${TMP_DIR}/rootfs.tar"
# vendor
sqfs2tar -r vendor "${IMAGE_DIR}/vendor.img" > "${TMP_DIR}/vendor.tar"
# combine
tar -A --file="${TMP_DIR}/rootfs.tar" "${TMP_DIR}/vendor.tar"

rm -rf "${OUTPUT_DIR}/rootfs"
mkdir -p "${OUTPUT_DIR}/rootfs"
tar -xf "${TMP_DIR}/rootfs.tar" -C "${OUTPUT_DIR}/rootfs"
cp "${IMAGE_DIR}/NOTICE.txt" "${OUTPUT_DIR}"

echo "Done!"
