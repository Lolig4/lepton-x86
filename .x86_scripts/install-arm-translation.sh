#!/bin/bash
# Add arm64 support to the x86_64 Android image via Google's ndk_translation.
#
# Android runs ARM app code on x86 through a "native bridge": ART loads the
# translator instead of the app's .so, and the translator executes the ARM
# code.  The translator itself is a proprietary Google blob taken from
# ChromeOS; it is not redistributable, which is why it is not part of the image
# build and gets added here, on the machine that uses it.
#
# Only arm64-v8a is enabled: this image is 64-bit only (Lepton's own design),
# so a 32-bit ARM ABI could be advertised but never loaded.
#
#   ./install-arm-translation.sh [rootfs]      install (default: the dev rootfs)
#   ./install-arm-translation.sh --check       show what an image currently has
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ROOTFS="${1:-${ROOT}/../compat_tool/images/rootfs}"
# Pinned to the commit waydroid_script uses for Android 11, with its checksum.
URL="https://github.com/supremegamers/vendor_google_proprietary_ndk_translation-prebuilt/archive/9324a8914b649b885dad6f2bfd14a67e5d1520bf.zip"
MD5="c9572672d1045594448068079b34c350"
WORK="${ROOT}/.ndk-translation"

if [[ "${1:-}" == "--check" ]]; then
    ROOTFS="${2:-${ROOT}/../compat_tool/images/rootfs}"
    echo "rootfs: ${ROOTFS}"
    [[ -f "${ROOTFS}/system/lib64/libndk_translation.so" ]] \
        && echo "  translator: installed" || echo "  translator: not installed"
    grep -E "^ro.product.cpu.abilist|^ro.dalvik.vm.native.bridge" "${ROOTFS}/system/build.prop" \
        | sed 's/^/  /'
    exit 0
fi

[[ -d "${ROOTFS}/system" ]] || { echo "no rootfs at ${ROOTFS}" >&2; exit 1; }

mkdir -p "${WORK}"
if [[ ! -f "${WORK}/ndk.zip" ]] || [[ "$(md5sum "${WORK}/ndk.zip" | cut -d' ' -f1)" != "${MD5}" ]]; then
    echo "==> Downloading ndk_translation"
    curl -fL --progress-bar -o "${WORK}/ndk.zip" "${URL}"
fi
[[ "$(md5sum "${WORK}/ndk.zip" | cut -d' ' -f1)" == "${MD5}" ]] || { echo "checksum mismatch" >&2; exit 1; }
echo "==> Checksum ok"

rm -rf "${WORK}/unpack"; mkdir -p "${WORK}/unpack"
unzip -q "${WORK}/ndk.zip" -d "${WORK}/unpack"
SRC="$(find "${WORK}/unpack" -maxdepth 2 -type d -name prebuilts | head -1)"

echo "==> Installing the 64-bit parts into ${ROOTFS}/system"
install -d "${ROOTFS}/system/bin" "${ROOTFS}/system/lib64" "${ROOTFS}/system/etc/init"
cp -a "${SRC}/lib64/." "${ROOTFS}/system/lib64/"
cp -a "${SRC}/bin/arm64" "${SRC}/bin/ndk_translation_program_runner_binfmt_misc_arm64" "${ROOTFS}/system/bin/"
cp -a "${SRC}/etc/binfmt_misc" "${SRC}/etc/cpuinfo.arm64.txt" "${SRC}/etc/ld.config.arm64.txt" "${ROOTFS}/system/etc/"
cp -a "${SRC}/etc/init/ndk_translation.rc" "${ROOTFS}/system/etc/init/"

echo "==> Announcing arm64-v8a in build.prop"
P="${ROOTFS}/system/build.prop"
cp -n "${P}" "${P}.pre-arm" 2>/dev/null || true
sed -i -e 's/^ro\.product\.cpu\.abilist=.*/ro.product.cpu.abilist=x86_64,arm64-v8a/' \
       -e 's/^ro\.product\.cpu\.abilist64=.*/ro.product.cpu.abilist64=x86_64,arm64-v8a/' "${P}"
grep -q '^ro.dalvik.vm.native.bridge=' "${P}" || cat >> "${P}" <<'PROPS'

# ARM translation (ndk_translation), added by install-arm-translation.sh.
# abilist32 stays empty on purpose: this image has no 32-bit runtime.
ro.dalvik.vm.native.bridge=libndk_translation.so
ro.enable.native.bridge.exec=1
ro.vendor.enable.native.bridge.exec=1
ro.vendor.enable.native.bridge.exec64=1
ro.ndk_translation.version=0.2.3
ro.dalvik.vm.isa.arm64=x86_64
PROPS

echo "==> Done"
grep -E "^ro.product.cpu.abilist|^ro.dalvik.vm.native.bridge" "${P}" | sed 's/^/  /'
