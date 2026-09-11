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

for i in {1..250}; do
    test_log "PASS$i"
    (./lepton start || test_log "container failed to start, test will timeout.") &

    wait_for_boot testapp

    wait_for_app testapp com.example.neon42

    if [[ "$(./lepton ps | grep "testapp" | grep "${_GREEN}")" == "" ]]; then
        test_log "repeated start test failed, lepton ps inconsistent (1)!"
        test_failure
    fi

    ./lepton stop testapp

    # Run cleanup all every now and then
    if (( i % 5 == 0 )); then
        ./lepton cleanup_all
    fi
done

test_log "testapp repeated start test finished"

