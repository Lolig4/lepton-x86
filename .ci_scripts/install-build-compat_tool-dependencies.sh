#!/bin/bash

apt-get -qq update && \
      apt-get install -y gcc-aarch64-linux-gnu rustup build-essential git tar zstd

rustup default stable
rustup target add aarch64-unknown-linux-gnu
