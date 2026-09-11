#!/bin/bash

set -eo pipefail

ROOT_DIR="$(dirname "$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )" )"
MANIFESTS_DIR="${ROOT_DIR}/output/.repo/local_manifests"

# Auto-detect SDK version
sdkv=$(cat ${ROOT_DIR}/output/build/make/core/version_defaults.mk | grep "PLATFORM_SDK_VERSION :=" | grep -o "[[:digit:]]\+")

# Copy in xml fragments from waydroid and valve vendor directories
mkdir -p "${MANIFESTS_DIR}"
cp -fpr ${ROOT_DIR}/android_vendor_waydroid/manifest_scripts/manifests-${sdkv}/*.xml "${MANIFESTS_DIR}/"
cp -fpr ${ROOT_DIR}/android_vendor_valve/manifest_scripts/manifests-${sdkv}/*.xml "${MANIFESTS_DIR}/"

# Generate cohesive manifests.xml file
pushd "${ROOT_DIR}/output" 2>/dev/null
    "${ROOT_DIR}/android_vendor_waydroid/manifest_scripts/generate-manifest.sh"
popd >/dev/null