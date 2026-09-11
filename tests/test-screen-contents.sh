#!/bin/bash

set -euo pipefail

TESTS_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $TESTS_DIR/test-common.sh

test_log "Testing screen contents"

cp tests/test-apk.apk .

monitor_logcat test-apk.apk &
LOGCAT_PID="$!"

(./lepton start test-apk.apk || test_log "container test-apk.apk failed to start, test will timeout.") &

wait_for_boot test-apk.apk

wait_for_app test-apk.apk com.example.neon42

sleep 3

./lepton run test-apk.apk screencap -p > screen.png

convert screen.png -colorspace RGB -fx "(r > 0.5 && g < 0.2 && b < 0.2) ? 1 : 0" screen_filtered.png
convert screen_filtered.png -negate screen_filtered_negated.png

if [[ "$(tesseract screen_filtered_negated.png stdout --psm 7 -c tessedit_char_whitelist=0123456789)" != "42" ]]; then
    test_log "screen contents not as expected! $(tesseract screen_filtered_negated.png stdout --psm 7 -c tessedit_char_whitelist=0123456789)"
    print_screen test-apk.apk
    test_failure
fi

./lepton stop test-apk.apk

kill "${LOGCAT_PID}"
