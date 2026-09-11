#!/bin/bash

apt-get -qq update && \
    apt-get install -y squashfs-tools-ng curl unzip zstd tar rsync e2fsprogs
