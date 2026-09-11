#!/bin/bash

set -euo pipefail

TESTS_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $TESTS_DIR/test-common.sh

cp tests/test-apk.apk .

monitor_logcat dev &
LOGCAT_PID="$!"

# Set up two testapps needed for some of the tests.
export STEAM_COMPAT_INSTALL_PATH_1="/home/steamos/.local/share/Steam/steamapps/common/testapp"
export STEAM_COMPAT_CLIENT_INSTALL_PATH_1=/home/steamos/.local/share/Steam
export STEAM_COMPAT_DATA_PATH_1=/home/steamos/.local/share/Steam/steamapps/compatdata/testapp
export STEAM_COMPAT_SHADER_PATH_1=/home/steamos/.local/share/Steam/steamapps/shadercache/testapp
export STEAM_FOSSILIZE_DUMP_PATH_1=/home/steamos/.local/share/Steam/steamapps/shadercache/testapp/fozpipelinesv6/steamapp_pipeline_cache
export SteamAppId_1=testapp

mkdir -p "${STEAM_COMPAT_INSTALL_PATH_1}"
mkdir -p "${STEAM_COMPAT_CLIENT_INSTALL_PATH_1}"
mkdir -p "${STEAM_COMPAT_DATA_PATH_1}"
mkdir -p "${STEAM_COMPAT_SHADER_PATH_1}"
mkdir -p "${STEAM_FOSSILIZE_DUMP_PATH_1}"

cp tests/test-apk.apk "${STEAM_COMPAT_INSTALL_PATH_1}"

tee /home/steamos/.local/share/Steam/steamapps/appmanifest_testapp.acf <<EOF
"AppState"
{
	"appid"     		"testapp"
	"name"		        "testapp"
	"installdir"		"testapp"
}
EOF

export STEAM_COMPAT_INSTALL_PATH_2="/home/steamos/.local/share/Steam/steamapps/common/testapp2"
export STEAM_COMPAT_CLIENT_INSTALL_PATH_2=/home/steamos/.local/share/Steam
export STEAM_COMPAT_DATA_PATH_2=/home/steamos/.local/share/Steam/steamapps/compatdata/testapp2
export STEAM_COMPAT_SHADER_PATH_2=/home/steamos/.local/share/Steam/steamapps/shadercache/testapp2
export STEAM_FOSSILIZE_DUMP_PATH_2=/home/steamos/.local/share/Steam/steamapps/shadercache/testapp2/fozpipelinesv6/steamapp_pipeline_cache
export SteamAppId_2=testapp2

mkdir -p "${STEAM_COMPAT_INSTALL_PATH_2}"
mkdir -p "${STEAM_COMPAT_CLIENT_INSTALL_PATH_2}"
mkdir -p "${STEAM_COMPAT_DATA_PATH_2}"
mkdir -p "${STEAM_COMPAT_SHADER_PATH_2}"
mkdir -p "${STEAM_FOSSILIZE_DUMP_PATH_2}"

cp tests/test-apk.apk "${STEAM_COMPAT_INSTALL_PATH_2}"

tee /home/steamos/.local/share/Steam/steamapps/appmanifest_testapp2.acf <<EOF
"AppState"
{
	"appid"     		"testapp2"
	"name"		        "testapp2"
	"installdir"		"testapp2"
}
EOF

(./lepton start dev || test_log "container dev failed to start, test will timeout.") &

wait_for_boot dev

test_log "testing run/exec"

if [[ "$(./lepton run dev ls /init.environ.rc)" != "/init.environ.rc" ]]; then
    test_log "lepton run command failed!"
    test_failure
fi

if [[ "$(./lepton exec dev ls /init.environ.rc)" != "/init.environ.rc" ]]; then
    test_log "lepton exec command failed!"
    test_failure
fi

test_log "Testing attach/shell"

./lepton extract dev /data/test.txt || true

if [[ -e test.txt ]]; then
    test_log "test.txt existed before test!"
    test_failure
fi

echo "touch /data/test.txt; exit" | ./lepton attach dev

./lepton extract dev /data/test.txt || true

if [[ ! -e test.txt ]]; then
    test_log "test failed, test.txt missing!"
    test_failure
fi

./lepton extract dev /data/test2.txt || true

if [[ -e test2.txt ]]; then
    test_log "test2.txt existed before test!"
    test_failure
fi

echo "touch /data/test2.txt; exit" | ./lepton shell dev

./lepton extract dev /data/test2.txt || true

if [[ ! -e test2.txt ]]; then
    test_log "test failed, test2.txt missing!"
    test_failure
fi

test_log "Testing extract"

if [[ -f "init.environ.rc" ]] || [[ -e "init.environ.rc" ]]; then
    test_log "init.environ.rc existed before the test!"
    test_failure
fi

./lepton extract dev /init.environ.rc

if [[ ! -f "init.environ.rc" ]]; then
    test_log "lepton extract command failed!"
    test_failure
fi

./lepton stop dev

kill "${LOGCAT_PID}"

test_log "testing ps"

monitor_logcat testapp &
LOGCAT_PID="$!"

(./lepton start testapp || test_log "container testapp failed to start, test will timeout.") &

wait_for_boot testapp

if [[ "$(./lepton ps | grep "testapp")" == "" ]]; then
    test_log "lepton ps command failed!"
    test_failure
fi

if [[ "$(./lepton ps | wc -l)" != "1" ]]; then
    test_log "lepton ps command has wrong number of output lines (1)!"
    test_failure
fi

if [[ "$(./lepton ps | grep "testapp" | grep "${_RED}")" != "" ]]; then
    test_log "lepton ps command failed due to color (1)!"
    test_failure
fi

if [[ "$(./lepton ps | grep "testapp" | grep "${_GREEN}")" == "" ]]; then
    test_log "lepton ps command failed due to color (2)!"
    test_failure
fi

./lepton stop testapp

if [[ "$(./lepton ps | grep "testapp" | grep "${_RED}")" == "" ]]; then
    test_log "lepton ps command failed due to color (3)!"
    test_failure
fi

if [[ "$(./lepton ps | grep "testapp" | grep "${_GREEN}")" != "" ]]; then
    test_log "lepton ps command failed due to color (4)!"
    test_failure
fi

if [[ "$(./lepton ps | wc -l)" != "1" ]]; then
    test_log "lepton ps command has wrong number of output lines (2)!"
    test_failure
fi

kill "${LOGCAT_PID}"

./lepton cleanup_all

monitor_logcat dev &
LOGCAT_PID="$!"

(./lepton start dev || test_log "container dev failed to start, test will timeout.") &

wait_for_boot dev

if [[ "$(./lepton ps | grep "dev")" == "" ]]; then
    test_log "lepton ps command failed!"
    test_failure
fi

if [[ "$(./lepton ps | wc -l)" != "1" ]]; then
    test_log "lepton ps command has wrong number of output lines (3)!"
    test_failure
fi

if [[ "$(./lepton ps | grep "dev" | grep "${_RED}")" != "" ]]; then
    test_log "lepton ps command failed due to color (1.1)!"
    test_failure
fi

if [[ "$(./lepton ps | grep "dev" | grep "${_GREEN}")" == "" ]]; then
    test_log "lepton ps command failed due to color (2.1)!"
    test_failure
fi

./lepton stop dev

# dev context doesn't stick around
if [[ "$(./lepton ps | grep "dev" | grep "${_RED}")" != "" ]]; then
    test_log "lepton ps command failed due to color (3.1)!"
    test_failure
fi

if [[ "$(./lepton ps | grep "dev" | grep "${_GREEN}")" != "" ]]; then
    test_log "lepton ps command failed due to color (4.1)!"
    test_failure
fi

if [[ "$(./lepton ps | wc -l)" != "0" ]]; then
    test_log "lepton ps command has wrong number of output lines (4)!"
    test_failure
fi

kill "${LOGCAT_PID}"

./lepton cleanup_all

monitor_logcat dev &
LOGCAT_PID1="$!"
monitor_logcat testapp &
LOGCAT_PID2="$!"

(./lepton start dev || test_log "container dev failed to start, test will timeout.") &
wait_for_boot dev

(./lepton start testapp || test_log "container testapp failed to start, test will timeout.") &
wait_for_boot testapp

if [[ "$(./lepton ps | wc -l)" != "2" ]]; then
    test_log "lepton ps command has wrong number of output lines with two containers!"
    test_failure
fi

if [[ "$(./lepton ps | grep "dev" | grep "${_GREEN}")" == "" ]]; then
    test_log "lepton ps command failed due to color (5)!"
    test_failure
fi

if [[ "$(./lepton ps | grep "testapp" | grep "${_GREEN}")" == "" ]]; then
    test_log "lepton ps command failed due to color (6)!"
    test_failure
fi

./lepton stop dev

# dev context doesn't stick around
if [[ "$(./lepton ps | grep "dev" | grep "${_RED}")" != "" ]]; then
    test_log "lepton ps command failed due to color (7)!"
    test_failure
fi

if [[ "$(./lepton ps | grep "testapp" | grep "${_GREEN}")" == "" ]]; then
    test_log "lepton ps command failed due to color (8)!"
    test_failure
fi

./lepton kill testapp

# dev context doesn't stick around
if [[ "$(./lepton ps | grep "dev" | grep "${_RED}")" != "" ]]; then
    test_log "lepton ps command failed due to color (9)!"
    test_failure
fi

if [[ "$(./lepton ps | grep "testapp" | grep "${_RED}")" == "" ]]; then
    test_log "lepton ps command failed due to color (10)!"
    test_failure
fi

kill "${LOGCAT_PID1}"
kill "${LOGCAT_PID2}"

test_log "testing kill_all/cleanup/cleanup_all"

monitor_logcat dev &
LOGCAT_PID1="$!"
monitor_logcat testapp &
LOGCAT_PID2="$!"
monitor_logcat testapp2 &
LOGCAT_PID3="$!"

(./lepton start dev || test_log "container dev failed to start, test will timeout.") &
wait_for_boot dev

(./lepton start testapp || test_log "container testapp failed to start, test will timeout.") &
wait_for_boot testapp

(./lepton start testapp2 || test_log "container testapp2 failed to start, test will timeout.") &
wait_for_boot testapp2

if [[ "$(./lepton ps | wc -l)" != "3" ]]; then
    test_log "lepton ps command has wrong number of output lines after starting 3 containers!"
    test_failure
fi

if [[ "$(./lepton ps | grep "dev" | grep "${_GREEN}")" == "" ]]; then
    test_log "lepton ps command failed due to color (11)!"
    test_failure
fi

if [[ "$(./lepton ps | grep "testapp" | grep "${_GREEN}")" == "" ]]; then
    test_log "lepton ps command failed due to color (12)!"
    test_failure
fi

if [[ "$(./lepton ps | grep "testapp2" | grep "${_GREEN}")" == "" ]]; then
    test_log "lepton ps command failed due to color (13)!"
    test_failure
fi

./lepton kill_all

# dev contexts don't stick around
if [[ "$(./lepton ps | wc -l)" != "2" ]]; then
    test_log "lepton ps command has wrong number of output lines after kill_all!"
    test_failure
fi

# dev context doesn't stick around
if [[ "$(./lepton ps | grep "dev" | grep "${_RED}")" != "" ]]; then
    test_log "lepton ps command failed due to color (14)!"
    test_failure
fi

if [[ "$(./lepton ps | grep "testapp" | grep "${_RED}")" == "" ]]; then
    test_log "lepton ps command failed due to color (15)!"
    test_failure
fi

if [[ "$(./lepton ps | grep "testapp2" | grep "${_RED}")" == "" ]]; then
    test_log "lepton ps command failed due to color (16)!"
    test_failure
fi

./lepton cleanup dev

# cleanup doesn't remove the container, only "cleans" it

# dev context doesn't stick around
if [[ "$(./lepton ps | grep "dev" | grep "${_RED}")" != "" ]]; then
    test_log "lepton ps command failed due to color (17)!"
    test_failure
fi

if [[ "$(./lepton ps | grep "testapp" | grep "${_RED}")" == "" ]]; then
    test_log "lepton ps command failed due to color (18)!"
    test_failure
fi

if [[ "$(./lepton ps | grep "testapp2" | grep "${_RED}")" == "" ]]; then
    test_log "lepton ps command failed due to color (19)!"
    test_failure
fi

# dev context doesn't stick around
if [[ "$(./lepton ps | wc -l)" != "2" ]]; then
    test_log "lepton ps command has wrong number of output lines after cleanup!"
    test_failure
fi

./lepton cleanup_all

# cleanup_all cleans all the containers AND removes them.
if [[ "$(./lepton ps | wc -l)" != "0" ]]; then
    test_log "lepton ps command has wrong number of output lines after cleanup_all!"
    test_failure
fi

kill "${LOGCAT_PID1}"
kill "${LOGCAT_PID2}"
kill "${LOGCAT_PID3}"

test_log "testing logcat"

(./lepton start testapp || test_log "container dev failed to start, test will timeout.") &

wait_for_boot testapp

wait_for_app testapp com.example.neon42

# The command doesn't exit by itself.
(
    sleep 5
    killall logcat
) &

# Grep a random message from logcat that should always be there.
if [[ "$(./lepton logcat testapp --full | grep "hwservicemanager is ready now.")" == "" ]]; then
    test_log "lepton logcat command does not produce expected output!"
    test_failure
fi

(
    sleep 5
    killall logcat
) &

# But it should be absent without --full:
if [[ "$(./lepton logcat testapp | grep "hwservicemanager is ready now.")" != "" ]]; then
    test_log "lepton logcat command does not produce expected output! (2)"
    test_failure
fi

./lepton stop testapp

test_log "Testing install_completions"
./lepton install_completions
# TODO: Test if completions work, not just the installation of them

test_log "Testing bootchart"

if [[ "$(ls -1 /home/steamos/.local/share/Steam/logs/lepton-logcats/bootchart 2>/dev/null)" != "" ]]; then
    test_log "bootchart test failed due to bootchart folder being non-emtpy!"
    test_failure
fi

monitor_logcat bootchart &
LOGCAT_PID="$!"

./lepton bootchart

BOOTCHART_FILE_LIST="$(ls -1 /home/steamos/.local/share/Steam/logs/lepton-logcats/bootchart 2>/dev/null | sort)"
BOOTCHART_FILE_LIST="${BOOTCHART_FILE_LIST//$'\n'/ }"

if [[ "${BOOTCHART_FILE_LIST}" != "header logcat-crash.log logcat-kernel.log logcat-lepton.log logcat-main.log logcat-radio.log logcat-system.log proc_diskstats.log proc_ps.log proc_stat.log" ]]; then
    test_log "bootchart test failed due to missing bootchart files!"
    test_failure
fi

kill "${LOGCAT_PID}"

mkdir -p /home/steamos/.local/share/Steam/steamapps/Unreal\ VR\ Test\ 🐸

# TODO: put the actual apk here?
cp test-apk.apk /home/steamos/.local/share/Steam/steamapps/Unreal\ VR\ Test\ 🐸

test_log "Testing unreal_vr_test"
./lepton unreal_vr_test &

wait_for_boot steamlaunch-3418470

wait_for_app steamlaunch-3418470 com.example.neon42

sleep 3

if [[ "$(./lepton run steamlaunch-3418470 pidof com.example.neon42 2>/dev/null || true)" == "" ]]; then
    test_log "unreal_vr_test test failed."
    test_failure
fi

./lepton kill steamlaunch-3418470

test_log "Testing collect_logs"

FILE_NAME=$(./lepton collect_logs | grep "Here you go:" | sed "s/^Here you go: //g")

if [[ ! -f "${FILE_NAME}" ]]; then
    test_log "lepton collect_logs failed"
    test_failure
fi

mkdir tmp.collect_logs
pushd tmp.collect_logs
tar xvf "../${FILE_NAME}"
if [[ "$(cat info |grep "Lepton Version: " | sed "s/^Lepton Version: //g")" != "$(git describe --tags --always)" ]]; then
    test_log "lepton collect_logs reports incorrect lepton version!"
    test_failure
fi
popd
rm -rf tmp.collect_logs

test_log "Testing adb port"

(./lepton start dev || test_log "container dev failed to start, test will timeout.") &

wait_for_boot dev

if [[ "$(./lepton ps | grep -o "adb on 5555,")" != "adb on 5555," ]]; then
    test_log "Adb port not as expected!"
    test_failure
fi

./lepton stop dev

(./lepton start dev || test_log "container dev failed to start, test will timeout.") &

wait_for_boot dev

if [[ "$(./lepton ps | grep -o "adb on 5555,")" != "adb on 5555," ]]; then
    test_log "Adb port not as expected after restart!"
    test_failure
fi

./lepton stop dev

test_log "Testing LEPTON_ENV_*"

(LEPTON_ENV_FOOVAR=foo LEPTON_ENV_BARVAR=bar ./lepton start test-apk.apk || test_log "container test-apk.apk failed to start, test will timeout.") &

wait_for_app test-apk.apk com.example.neon42

if ! grep -q FOOVAR /proc/$(pidof com.example.neon42)/environ; then
    test_log "FOOVAR was not set in target process."
    test_failure
fi

if ! grep -q BARVAR /proc/$(pidof com.example.neon42)/environ; then
    test_log "BARVAR was not set in target process."
    test_failure
fi

if grep -q LEPTON_ENV_ /proc/$(pidof com.example.neon42)/environ; then
    test_log "LEPTON_ENV_ was most likely not stripped from the variable name."
    test_failure
fi

./lepton stop test-apk.apk

test_log "test finished."
