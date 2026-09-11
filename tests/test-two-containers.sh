#!/bin/bash

set -euo pipefail

TESTS_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $TESTS_DIR/test-common.sh

monitor_logcat dev &
LOGCAT_PID1="$!"
monitor_logcat test-apk.apk &
LOGCAT_PID2="$!"

cp tests/test-apk.apk .

(./lepton start dev || test_log "container dev failed to start, test will timeout.") &
wait_for_boot dev

(./lepton start test-apk.apk || test_log "container test-apk.apk failed to start, test will timeout.") &
wait_for_boot test-apk.apk

wait_for_app test-apk.apk com.example.neon42

print_screen dev

while [[ "$(./lepton run test-apk.apk pidof com.example.neon42 2>/dev/null || true)" == "" ]]; do
    test_log "Waiting for test-apk.apk to start."
done

# Wait for the app to display something.
sleep 3

print_screen test-apk.apk

./lepton stop dev
./lepton stop test-apk.apk

test_log "dev and test-apk.apk container stopped."

test_log "dev and test-apk.apk container test finished."

kill $LOGCAT_PID1 || true
kill $LOGCAT_PID2 || true
