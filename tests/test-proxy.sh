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

python -m venv proxy-venv
source proxy-venv/bin/activate

pip install pproxy

(
    sudo touch /tmp/proxy.log
    sudo chown steamos:steamos /tmp/proxy.log
    script -q -c "sudo pproxy -vv -l http://:8080 > /tmp/proxy.log 2>&1" /dev/null
) &

sleep 3

(
    HTTP_PROXY=host.containers.internal:8080 ./lepton start || test_log "container failed to start, test will timeout."
) &

wait_for_boot testapp

wait_for_app testapp com.example.neon42

./lepton run testapp /system/bin/am start -a com.example.neon42.OPEN_WEBVIEW -p com.example.neon42 --es launch_webview https://example.com

sleep 3

if [[ "$(cat /tmp/proxy.log |grep -o " -> example.com")" != " -> example.com" ]]; then
    test_log "Android did not use the proxy as expected."
    test_failure
fi

cat /tmp/proxy.log

./lepton stop testapp
kill "${LOGCAT_PID}"
sudo killall pproxy

test_log "proxy test finished"

