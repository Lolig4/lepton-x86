#!/bin/bash

set -euo pipefail

TESTS_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $TESTS_DIR/test-common.sh

monitor_logcat test-apk.apk &
LOGCAT_PID="$!"

cp tests/test-apk.apk .

sed -i "/am start/d" liblepton/app_metadata.sh

(./lepton start test-apk.apk || test_log "container test-apk.apk failed to start, test will timeout.") &
wait_for_boot test-apk.apk

# on gitlab the container startup itself takes a while
# so use 80s to be on the safe side
sleep 80

if [[ "$(./lepton ps | grep "test-apk.apk" | grep "${_GREEN}")" != "" ]]; then
    test_log "test failed because the container was still active after the launch timeout"
    test_failure
fi

./lepton stop test-apk.apk

test_log "test-apk.apk container test finished."

kill $LOGCAT_PID || true
