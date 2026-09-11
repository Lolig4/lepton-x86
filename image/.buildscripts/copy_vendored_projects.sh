#!/bin/bash

set -eo pipefail

ROOT_DIR="$(dirname "$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )" )"
ANDROID_ROOT="${ROOT_DIR}/output"

# Force-copy over the contents of our vendored projects, so that local changes
# are reflected without needing to push changes up to the actual repositories.
rsync -Pa --delete "${ROOT_DIR}/android_device_valve_waydroid/" "${ANDROID_ROOT}/device/waydroid/waydroid"
rsync -Pa --delete "${ROOT_DIR}/android_hardware_waydroid/" "${ANDROID_ROOT}/hardware/waydroid"
rsync -Pa "${ROOT_DIR}/android_vendor_valve/" "${ANDROID_ROOT}/vendor/extra"
