#!/bin/bash

set -euo pipefail

TESTS_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $TESTS_DIR/test-common.sh

monitor_logcat dev &
LOGCAT_PID="$!"

(./lepton start dev || test_log "container dev failed to start, test will timeout.") &

wait_for_boot dev

test_log "dev container has started"

print_screen dev

./lepton stop dev
test_log "dev container has stopped"

test_log "dev container test finished"

kill ${LOGCAT_PID} || true
