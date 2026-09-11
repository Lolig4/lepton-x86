#!/bin/bash

CI_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
IMAGE_ROOT_DIR="${CI_DIR}/../image"

mv ~/.bashrc ~/.bashrc-original
echo "export USER_NAME=\"SteamOS Lepton Builder\"" > ~/.bashrc
echo "export USER_MAIL=\"lepton-builder@steamos.cloud\"" >> ~/.bashrc

cat "${IMAGE_ROOT_DIR}/.buildscripts/valve_bashrc.preamble" >> ~/.bashrc
cat ~/.bashrc-original >> ~/.bashrc

apt-get -qq update && \
      apt-get install -y bc bison bsdmainutils build-essential ccache cgpt clang \
      cron curl flex g++-multilib gcc-multilib git git-lfs gnupg gperf imagemagick \
      kmod lib32ncurses5-dev lib32readline-dev lib32z1-dev liblz4-tool \
      libncurses5 libncurses5-dev libsdl1.2-dev libssl-dev libxml2 \
      libxml2-utils lsof lzop maven openjdk-8-jdk pngcrush procps python3 python3-pip \
      python-is-python3 rsync schedtool squashfs-tools wget xdelta3 xsltproc yasm zip \
      zlib1g-dev lua5.4 ca-certificates vim

apt-get -qq update && \
    apt-get install -y tar

apt-get -qq update && \
      apt-get install -y clang-format clang-tidy clang-tools clang clangd libc++-dev libc++1 libc++abi-dev libc++abi1 libclang-dev libclang1 liblldb-dev libllvm-ocaml-dev libomp-dev libomp5 lld llvm-dev llvm-runtime llvm python3-clang ninja-build

# Mesa Dependencies
apt-get -qq update && \
      apt-get install -y python3-mako directx-headers-dev glslang-tools quilt libdrm-dev libx11-dev libxxf86vm-dev libexpat1-dev libsensors-dev libxfixes-dev libxext-dev libva-dev libvdpau-dev libvulkan-dev x11proto-dev linux-libc-dev libx11-xcb-dev libxcb-dri2-0-dev libxcb-glx0-dev libxcb-xfixes0-dev libxcb-dri3-dev libxcb-present-dev libxcb-randr0-dev libxcb-shm0-dev libxcb-sync-dev libxrandr-dev libxshmfence-dev libzstd-dev python3 python3-mako python3-ply python3-setuptools flex bison libelf-dev libwayland-dev libwayland-egl-backend-dev wayland-protocols zlib1g-dev libglvnd-core-dev valgrind rustc bindgen
pip3 install meson

# Image tool dependencies
apt-get -qq update && \
      apt-get install -y simg2img

# Symbol file tarball dependencies
apt-get -qq update && \
      apt-get install -y zstd

rm -rf /vr/lib/apt/lists/*

curl https://storage.googleapis.com/git-repo-downloads/repo > /usr/local/bin/repo && \
      chmod a+x /usr/local/bin/repo

# Install Git LFS
git lfs install
