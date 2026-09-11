#!/bin/bash

set -euo pipefail

_RED="RED: "
_GREEN="GREEN: "
_PLAIN="PLAIN: "

sed -i "s/_RED=\".*\"/_RED=\"RED: \"/g" lepton
sed -i "s/_GREEN=\".*\"/_GREEN=\"GREEN: \"/g" lepton
sed -i "s/_PLAIN=\".*\"/_PLAIN=\"PLAIN: \"/g" lepton

function test_log()
{
    echo "${TEST_PREFIX}$@"
    echo "${TEST_PREFIX}$@" >> ${TEST_LOGFILE}
}

function monitor_logcat()
{
    while true; do
        sleep 1
        ./lepton logcat "$1" --full | sed "s/^/[$1] /" | while IFS= read -r line; do
                echo "${line}" >> "${TEST_LOGFILE}"
            done
    done || true
}

function test_failure()
{
    ./lepton ps >> "${TEST_LOGFILE}"
    ps fax >> "${TEST_LOGFILE}"
    dmesg >> "${TEST_LOGFILE}"
    test_log "TEST FAILED, CHECK ARTIFACTS FOR DETAILED LOGS!"
    exit 1
}

function print_screen()
{
    ./lepton run "$1" screencap -p > screen.png
    test_log "$(chafa -s 640 --symbols all screen.png)"
}

function wait_for_boot()
{
    end=$((SECONDS + 30))
    while [[ "$(./lepton ps | grep "$1 " | grep "${_GREEN}")" == "" ]]; do
        if (( SECONDS >= end )); then
            test_log "container $1 failed to spin up within 30 seconds."
            test_failure
        fi
        test_log "Waiting for container $1 to start"
        sleep 1
    done

    end=$((SECONDS + 30))
    while [[ "$(./lepton run "$1" getprop sys.boot_completed 2>/dev/null || true)" != "1" ]]; do
        if (( SECONDS >= end )); then
            test_log "container $1 failed to reach boot complete within 30 seconds."
            test_failure
            break
        fi
        if [[ "$(./lepton ps | grep "$1 " | grep "${_RED}")" != "" ]]; then
            test_log "container $1 failed to reach boot completed state."
            test_failure
        fi
        test_log "Waiting for "$1" container to boot."
        sleep 1
    done
}

function wait_for_app()
{
    end=$((SECONDS + 30))
    while [[ "$(./lepton run "$1" pidof "$2" 2>/dev/null || true)" == "" ]]; do
        if (( SECONDS >= end )); then
            test_log "app $1 failed to start within 30 seconds."
            ./lepton run "$1" getprop
            ./lepton run "$1" dumpsys
            print_screen "$1"
            test_failure
            break
        fi
        test_log "Waiting for app $2"
        sleep 1
    done
}

function get_ns_pids()
{
    awk '/^NSpid:/ {for (i=2; i<=NF; i++) print $i}' /proc/$(pidof $1)/status
}

