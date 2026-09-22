#!/bin/bash
# Host packages the x86_64 build and the container need.
#
#   .x86_scripts/install-dependencies.sh
#
# The AOSP build itself runs inside the lepton-builder container and brings its
# own toolchain; what is needed here is podman, the squashfs tools the rootfs
# packaging uses, cargo for apk-info-extractor, attr for the bake's extended
# attributes and adb/inotify-tools for running the container.

set -euo pipefail

if command -v dnf >/dev/null; then
    sudo dnf install -y \
        podman catatonit \
        squashfs-tools-ng zstd rsync attr \
        android-tools inotify-tools \
        cargo rust \
        git git-lfs python3 \
        checkpolicy policycoreutils \
        weston
elif command -v apt-get >/dev/null; then
    sudo apt-get update
    sudo apt-get install -y \
        podman catatonit \
        squashfs-tools-ng zstd rsync attr \
        adb inotify-tools \
        cargo rustc \
        git git-lfs python3 weston
elif command -v pacman >/dev/null; then
    sudo pacman -Sy --noconfirm \
        podman catatonit \
        squashfs-tools-ng zstd rsync attr \
        android-tools inotify-tools \
        rust \
        git git-lfs python weston
else
    echo "unknown package manager -- see the list in this script" >&2
    exit 1
fi

echo "==> Host packages installed"
