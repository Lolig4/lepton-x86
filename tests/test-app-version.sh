#!/bin/bash

set -euo pipefail

TESTS_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $TESTS_DIR/test-common.sh

sed -i "s/_RED=\"\"/_RED=\"RED: \"/g" lepton
sed -i "s/_GREEN=\"\"/_GREEN=\"GREEN: \"/g" lepton
sed -i "s/_PLAIN=\"\"/_PLAIN=\"PLAIN: \"/g" lepton

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

monitor_logcat testapp &
LOGCAT_PID="$!"

(./lepton start || test_log "container failed to start, test will timeout.") &

wait_for_boot testapp

wait_for_app testapp com.example.neon42

if [[ -z "$(./lepton ps | grep "testapp" | grep "${_GREEN}")" ]]; then
    test_log "version test failed, lepton ps inconsistent (1)!"
    test_failure
fi

sleep 60

./lepton stop testapp

kill "${LOGCAT_PID}"

if [[ "$(sha256sum tests/test-apk.apk | awk '{print $1}')" != "$(cat ${STEAM_COMPAT_DATA_PATH}/baked/app_hash)" ]]; then
    test_log "app_depot_version was stored improperly."
    test_failure
fi

cp tests/test-apk2.apk "${STEAM_COMPAT_INSTALL_PATH}"/test-apk.apk

monitor_logcat testapp &
LOGCAT_PID="$!"

(./lepton start || test_log "container failed to start, test will timeout.") &

wait_for_boot testapp

wait_for_app testapp com.example.neon42

if [[ -z "$(./lepton ps | grep "testapp" | grep "${_GREEN}")" ]]; then
    test_log "version test failed, lepton ps inconsistent (1)!"
    test_failure
fi

sleep 60

./lepton stop testapp

if [[ "$(sha256sum tests/test-apk2.apk | awk '{print $1}')" != "$(cat ${STEAM_COMPAT_DATA_PATH}/baked/app_hash)" ]]; then
    test_log "app_depot_version was stored improperly."
    test_failure
fi

if [[ "$(sha256sum tests/test-apk.apk | awk '{print $1}')" != "$(cat ${STEAM_COMPAT_DATA_PATH}/baked/app_hash)" ]]; then
    test_log "stored app_depot_version did not change."
    test_failure
fi

kill "${LOGCAT_PID}"

unset STEAM_COMPAT_INSTALL_PATH
unset STEAM_COMPAT_CLIENT_INSTALL_PATH
unset STEAM_COMPAT_DATA_PATH
unset STEAM_COMPAT_SHADER_PATH
unset STEAM_FOSSILIZE_DUMP_PATH
unset SteamAppId

test_log "Testing too high sdk version."

monitor_logcat dev &
LOGCAT_PID="$!"

(./lepton start dev || test_log "container failed to start, test will timeout.") &

wait_for_boot dev

/usr/lib/android-sdk/platform-tools/adb connect localhost:5555
if /usr/lib/android-sdk/platform-tools/adb -s localhost:5555 install tests/test-apk3.apk; then
    test_log "adb install with too high sdk version failed since adb install succeeded."
    test_failure
fi

./lepton stop dev

kill "${LOGCAT_PID}"

export STEAM_COMPAT_INSTALL_PATH="/home/steamos/.local/share/Steam/steamapps/common/testapp"
export STEAM_COMPAT_CLIENT_INSTALL_PATH=/home/steamos/.local/share/Steam
export STEAM_COMPAT_DATA_PATH=/home/steamos/.local/share/Steam/steamapps/compatdata/testapp
export STEAM_COMPAT_SHADER_PATH=/home/steamos/.local/share/Steam/steamapps/shadercache/testapp
export STEAM_FOSSILIZE_DUMP_PATH=/home/steamos/.local/share/Steam/steamapps/shadercache/testapp/fozpipelinesv6/steamapp_pipeline_cache
export SteamAppId=testapp

monitor_logcat testapp &
LOGCAT_PID="$!"

echo "Testing different lepton depot version."

(./lepton start || test_log "container failed to start, test will timeout.") &

wait_for_boot testapp

wait_for_app testapp com.example.neon42

if [[ -z "$(./lepton ps | grep "testapp" | grep "${_GREEN}")" ]]; then
    test_log "version test failed, lepton ps inconsistent (1)!"
    test_failure
fi

sleep 60

./lepton stop testapp

kill "${LOGCAT_PID}"

FIRST_DEPOT_VERSION="$(cat ${STEAM_COMPAT_DATA_PATH}/baked/app_last_depot_version)"

echo "DIFFERENT_VERSION_TEST_ROOTFS" > images/version.txt
echo "DIFFERENT_VERSION_TEST_COMPAT_TOOL" > version.txt

monitor_logcat testapp &
LOGCAT_PID="$!"

(./lepton start || test_log "container failed to start, test will timeout.") &

wait_for_boot testapp

wait_for_app testapp com.example.neon42

if [[ -z "$(./lepton ps | grep "testapp" | grep "${_GREEN}")" ]]; then
    test_log "version test failed, lepton ps inconsistent (1)!"
    test_failure
fi

sleep 60

./lepton stop testapp

SECOND_DEPOT_VERSION="$(cat ${STEAM_COMPAT_DATA_PATH}/baked/app_last_depot_version)"

if [[ "${FIRST_DEPOT_VERSION}" == "${SECOND_DEPOT_VERSION}" ]] || [[ -z "${FIRST_DEPOT_VERSION}" ]] || [[ -z "${SECOND_DEPOT_VERSION}" ]]; then
    test_log "app/depot version test failed due to empty depot version or match: \"${FIRST_DEPOT_VERSION}\", \"${SECOND_DEPOT_VERSION}\""
fi

kill "${LOGCAT_PID}"

test_log "testapp app version test finished"

