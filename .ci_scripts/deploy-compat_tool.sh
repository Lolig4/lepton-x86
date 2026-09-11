#!/bin/bash

set -euo pipefail

CI_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_DIR="${CI_DIR}/../"
TARGET="${1}"

LEPTON_TARBALL="${PROJECT_DIR}/compat_tool.tar.zst"
if [[ ! -f "${LEPTON_TARBALL}" ]]; then
    echo "Build the compat tool first!" >&2
    exit 1
fi

LEPTON_DIR=/home/steamos/.local/share/Steam/steamapps/common/Lepton
if ! ssh steamos@${TARGET} "[ -d ${LEPTON_DIR} ]" ; then
    echo "Lepton not installed on ${TARGET}!" >&2
    exit 1
fi

rsync -Pav "${LEPTON_TARBALL}" "steamos@${TARGET}:/tmp/compat_tool.tar.zst"
ssh steamos@${TARGET} "tar -C ${LEPTON_DIR} -xf /tmp/compat_tool.tar.zst; ${LEPTON_DIR}/lepton cleanup_all"
