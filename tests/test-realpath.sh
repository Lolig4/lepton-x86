#!/bin/bash

set -euo pipefail

TESTS_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $TESTS_DIR/test-common.sh

sed -i "s/_RED=\"\"/_RED=\"RED: \"/g" lepton
sed -i "s/_GREEN=\"\"/_GREEN=\"GREEN: \"/g" lepton
sed -i "s/_PLAIN=\"\"/_PLAIN=\"PLAIN: \"/g" lepton

monitor_logcat testapp &
LOGCAT_PID="$!"

export STEAM_COMPAT_INSTALL_PATH="/home/steamos/.local/share/Steam/steamapps/common/testapp"
export STEAM_COMPAT_CLIENT_INSTALL_PATH=/home/steamos/.local/share/Steam
export STEAM_COMPAT_DATA_PATH=/home/steamos/.local/share/Steam/steamapps/compatdata/testapp
export STEAM_COMPAT_SHADER_PATH=/home/steamos/.local/share/Steam/steamapps/shadercache/testapp
export STEAM_FOSSILIZE_DUMP_PATH=/home/steamos/.local/share/Steam/steamapps/shadercache/testapp/fozpipelinesv6/steamapp_pipeline_cache
export SteamAppId=testapp

mkdir -p "${STEAM_COMPAT_INSTALL_PATH}"
mkdir -p "${STEAM_COMPAT_CLIENT_INSTALL_PATH}"
mkdir -p "${STEAM_COMPAT_DATA_PATH}"
mkdir -p "${STEAM_COMPAT_SHADER_PATH}"
mkdir -p "${STEAM_FOSSILIZE_DUMP_PATH}"

cp tests/test-apk.apk "${STEAM_COMPAT_INSTALL_PATH}"

tee /home/steamos/.local/share/Steam/steamapps/appmanifest_testapp.acf <<EOF
"AppState"
{
	"appid"     		"testapp"
	"name"		        "testapp"
	"installdir"		"testapp"
}
EOF

test_log "Testing internal/external realpath."

mkdir -p "${HOME}/Videos"
mkdir -p "${HOME}/Documents"
mkdir -p "${HOME}/Downloads"

(./lepton start || test_log "container failed to start, test will timeout.") &

wait_for_boot testapp

wait_for_app testapp com.example.neon42

if [[ "$(./lepton run testapp realpath /data/data/com.example.neon42)" != "${STEAM_COMPAT_DATA_PATH}/internal/com.example.neon42" ]]; then
    test_log "realpath test failed due to inconsistent internal path"
    test_failure
fi

if [[ "$(./lepton run testapp realpath /storage/emulated/0)" != "${STEAM_COMPAT_DATA_PATH}/external" ]]; then
    test_log "realpath test failed due to inconsistent external path"
    test_failure
fi

if [[ "$(./lepton run testapp realpath /storage/emulated/0/Movies)" != "${HOME}/Videos" ]]; then
    test_log "realpath test failed due to inconsistent external Videos path $(./lepton run testapp realpath /storage/emulated/0/Movies) != ${HOME}/Videos"
    test_failure
fi

if [[ "$(./lepton run testapp realpath /storage/emulated/0/Documents)" != "${HOME}/Documents" ]]; then
    test_log "realpath test failed due to inconsistent external Documents path"
    test_failure
fi

if [[ "$(./lepton run testapp realpath /storage/emulated/0/Download)" != "${HOME}/Downloads" ]]; then
    test_log "realpath test failed due to inconsistent external Download path"
    test_failure
fi

sleep 60

./lepton stop testapp

test_log "Testing internal/external realpath with app already baked (nobake)."

(./lepton start || test_log "container failed to start, test will timeout.") &

wait_for_boot testapp

wait_for_app testapp com.example.neon42

if [[ "$(./lepton run testapp realpath /data/data/com.example.neon42)" != "${STEAM_COMPAT_DATA_PATH}/internal/com.example.neon42" ]]; then
    test_log "realpath test failed due to inconsistent internal path (nobake)"
    test_failure
fi

if [[ "$(./lepton run testapp realpath /storage/emulated/0)" != "${STEAM_COMPAT_DATA_PATH}/external" ]]; then
    test_log "realpath test failed due to inconsistent external path (nobake)"
    test_failure
fi

if [[ "$(./lepton run testapp realpath /storage/emulated/0/Movies)" != "${HOME}/Videos" ]]; then
    test_log "realpath test failed due to inconsistent external Videos path (nobake)"
    test_failure
fi

if [[ "$(./lepton run testapp realpath /storage/emulated/0/Documents)" != "${HOME}/Documents" ]]; then
    test_log "realpath test failed due to inconsistent external Documents path (nobake)"
    test_failure
fi

if [[ "$(./lepton run testapp realpath /storage/emulated/0/Download)" != "${HOME}/Downloads" ]]; then
    test_log "realpath test failed due to inconsistent external Downloads path (nobake)"
    test_failure
fi

sleep 60

./lepton stop testapp


test_log "testapp realpath test finished"

