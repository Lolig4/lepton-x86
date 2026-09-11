#!/bin/bash

set -euo pipefail

TESTS_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $TESTS_DIR/test-common.sh

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

# Pass 1, test if files get persisted after stop.
test_log "PASS1"
(./lepton start || test_log "container failed to start, test will timeout.") &

wait_for_boot testapp

wait_for_app testapp com.example.neon42

./lepton run testapp touch /data/data/com.example.neon42/persistence-test-file-1
./lepton run testapp touch /sdcard/persistence-test-file-2

if [[ "$(./lepton ps | grep "testapp" | grep "${_GREEN}")" == "" ]]; then
    test_log "Persistence test failed, lepton ps inconsistent (1)!"
    test_failure
fi

./lepton stop testapp

if [[ "$(./lepton ps | grep "testapp" | grep "${_RED}")" == "" ]]; then
    test_log "Persistence test failed, lepton ps inconsistent (2)!"
    test_failure
fi

if [[ ! -f "${STEAM_COMPAT_DATA_PATH}/internal/com.example.neon42/persistence-test-file-1" ]]; then
    test_log "Persistence test failed, internal dir not persistent!."
    test_failure
fi

if [[ ! -f "${STEAM_COMPAT_DATA_PATH}/external/persistence-test-file-2" ]]; then
    test_log "Persistence test failed, external dir not persistent!."
    test_failure
fi

./lepton cleanup_all

# Pass 2, check if files still inside the container after another start.
test_log "PASS2"
(./lepton start || test_log "container failed to start, test will timeout.") &

wait_for_boot testapp

wait_for_app testapp com.example.neon42

./lepton extract testapp /data/data/com.example.neon42/persistence-test-file-1
./lepton extract testapp /sdcard/persistence-test-file-2

if [[ ! -f "persistence-test-file-1" ]]; then
    test_log "Persistence test failed, internal dir not persistent after restart!."
    test_failure
fi

if [[ ! -f "persistence-test-file-2" ]]; then
    test_log "Persistence test failed, external dir not persistent after restart!."
    test_failure
fi

./lepton stop testapp

if [[ ! -f "${STEAM_COMPAT_DATA_PATH}/internal/com.example.neon42/persistence-test-file-1" ]]; then
    test_log "Persistence test failed, internal dir not persistent after restart and stop!."
    test_failure
fi

if [[ ! -f "${STEAM_COMPAT_DATA_PATH}/external/persistence-test-file-2" ]]; then
    test_log "Persistence test failed, external dir not persistent after restart and stop!."
    test_failure
fi

./lepton cleanup_all

# Pass 3, check if files go away when removed.
test_log "PASS3"
(./lepton start || test_log "container failed to start, test will timeout.") &

wait_for_boot testapp

wait_for_app testapp com.example.neon42

./lepton run testapp rm /data/data/com.example.neon42/persistence-test-file-1
./lepton run testapp rm /sdcard/persistence-test-file-2

./lepton stop testapp

if [[ -f "${STEAM_COMPAT_DATA_PATH}/internal/com.example.neon42/persistence-test-file-1" ]]; then
    test_log "Persistence test failed, internal dir not persistent after delete!."
    test_failure
fi

if [[ -f "${STEAM_COMPAT_DATA_PATH}/external/persistence-test-file-2" ]]; then
    test_log "Persistence test failed, external dir not persistent after delete!."
    test_failure
fi

kill ${LOGCAT_PID} || true

test_log "testapp persistence test finished"

