#!/bin/bash

CI_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

${CI_DIR}/install-build-rootfs-dependencies.sh
