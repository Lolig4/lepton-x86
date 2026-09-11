#!/bin/bash

set -euo pipefail

TESTS_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $TESTS_DIR/test-common.sh

monitor_logcat dev &
LOGCAT_PID="$!"

test_log "Testing lepton network."

(./lepton start dev || test_log "container dev failed to start, test will timeout.") &

wait_for_boot dev

if ! ./lepton run dev ping -c 1 -W 10 example.com > /dev/null 2>&1; then
    test_log "ping failed!"
    test_failure
fi

./lepton stop dev

kill "${LOGCAT_PID}"

test_log "Testing host connection via ping."

monitor_logcat dev &
LOGCAT_PID="$!"

(./lepton start dev || test_log "container dev failed to start, test will timeout.") &

wait_for_boot dev

if ! ./lepton run dev ping -c 1 -W 10 host.containers.internal > /dev/null 2>&1; then
    test_log "host.containers.internal ping failed!"
    test_failure
fi

./lepton stop dev

kill "${LOGCAT_PID}"

test_log "Testing host connection through Steam3Master."

monitor_logcat dev &
LOGCAT_PID="$!"

(./lepton start dev || test_log "container dev failed to start, test will timeout.") &

wait_for_boot dev

Steam3Master="$(./lepton run dev cat /system/etc/init/hw/init.zygote64.rc | grep Steam3Master | sed "s/.*setenv Steam3Master \(.*\)/\1/g")"

if ./lepton run dev /system/bin/sh -c "nc -w 3 ${Steam3Master%:*} ${Steam3Master##*:}" < /dev/null > /dev/null 2>&1; then
    test_log "port was open before nc listen!"
    test_failure
fi

busybox nc -l -p "${Steam3Master##*:}" &

sleep 3

if ! ./lepton run dev /system/bin/sh -c "nc -w 3 ${Steam3Master%:*} ${Steam3Master##*:}" < /dev/null > /dev/null 2>&1; then
    test_log "port was not open after nc listen ${Steam3Master}!"
    test_failure
fi

./lepton stop dev

kill "${LOGCAT_PID}"

