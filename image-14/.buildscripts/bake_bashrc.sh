#!/bin/bash

set -eo pipefail

REPO_DIR="$(dirname "$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )" )"

# First, capture current `.bashrc` file.  Don't pass this through the STDOUT of
# `container.sh` because `podman -t` converts `LF` to `CRLF` because of TTY-ness.
rm -f "${REPO_DIR}/.buildscripts/.bashrc"
"${REPO_DIR}/.buildscripts/container.sh" "cat ~/.bashrc > .buildscripts/.bashrc_temp"

# Then, prepend `.valve_bashrc.preamble`
cat "${REPO_DIR}/.buildscripts/valve_bashrc.preamble" > "${REPO_DIR}/.buildscripts/.bashrc"
echo >> "${REPO_DIR}/.buildscripts/.bashrc"
cat "${REPO_DIR}/.buildscripts/.bashrc_temp" >> "${REPO_DIR}/.buildscripts/.bashrc"
rm -f "${REPO_DIR}/.buildscripts/.bashrc_temp"
