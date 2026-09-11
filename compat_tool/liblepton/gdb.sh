function debugger_wait_enabled()
{
    [[ "${LEPTON_DEBUG_LAUNCH:-false}" != "false" ]]
}

function debugger_wait_commands()
{
    echo -n "setprop ro.lepton.wait_for_debugger true; am set-debug-app -w $(get_app_id)"
}

function map_pid()
{
    local PID="${1}"
    # Check to see if PID is already in the container:
    if ! podman_attach sh -c "[ -f /proc/${PID}/status ]"; then
        # Try to map it
        if [[ ! -f /proc/${PID}/status ]]; then
            die "PID '${PID}' does not exist inside or outside the container!"
        fi
        local APP_CONTAINER_PID=$(grep NSpid /proc/${PID}/status 2>/dev/null | awk '{ print $3 }')
        if [[ -z "${APP_CONTAINER_PID}" ]]; then
            die "PID '${PID}' Exists outside but not inside the container!"
        fi
        echo -n "${APP_CONTAINER_PID}"
    else
        echo -n "${PID}"
    fi
}

function start_gdb_server()
{
    local PID="${1}"
    local PORT="$(gdb_port)"
    local PREFIX="$(prefix)"

    if [[ -z "${PID}" ]]; then
        die "No application pid to attach to!"
    fi

    local APP_CONTAINER_PID="$(map_pid "${PID}")"
    if [[ "${PID}" != "${APP_CONTAINER_PID}" ]]; then
        echo "PID automapped from ${PID} -> ${APP_CONTAINER_PID} within the container"
    fi

    local GDB_PID="$(podman_attach pidof gdbserver64)"
    if [[ -n "${GDB_PID}" ]]; then
        echo "gdbserver already running on localhost:${PORT}"
        return
    fi

    echo "Starting gdbserver on localhost:${PORT}"
    (
        uninherit_lepton_lock

        podman_attach /system/bin/gdbserver64 --multi "localhost:${PORT}" --attach "${APP_CONTAINER_PID}"
    ) &
    GDBSERVER_PID="$!"
    # Some time to settle...
    sleep 3
}

function start_lldb_server()
{
    local PID="${1}"
    local PORT="$(lldb_port)"
    local PREFIX="$(prefix)"

    if [[ -z "${PID}" ]]; then
        die "No application pid to attach to!"
    fi

    local APP_CONTAINER_PID="$(map_pid "${PID}")"
    if [[ "${PID}" != "${APP_CONTAINER_PID}" ]]; then
        echo "PID automapped from ${PID} -> ${APP_CONTAINER_PID} within the container"
    fi

    if [[ ! -e "/usr/share/guestos/android/vendor/bin/lldb-server" ]]; then
        die "lldb-server is not present, try: \"pacman -S lldb-server-android\" then restart the container"
    fi

    local LLDB_PID="$(podman_attach pidof lldb-server)"
    if [[ -n "${LLDB_PID}" ]]; then
        echo "lldbserver already running on localhost:${PORT}"
        return
    fi

    echo "Starting lldbserver on localhost:${PORT}"
    LEPTON_PID="$(podman inspect -f '{{.State.Pid}}' "lepton-${LEPTON_CONTEXT}")"
    # Need host root user to allow accessing /sys
    (
        uninherit_lepton_lock

        sudo nsenter -t "${LEPTON_PID}" -p -n -u -i -C -m \
            /vendor/bin/lldb-server g :${PORT} --attach ${APP_CONTAINER_PID} >/dev/null 2>/dev/null
    ) & >/dev/null 2>/dev/null
    # Some time to settle...
    sleep 1
}


function kill_gdb_server()
{
    local PREFIX="$(prefix "${1:-${LEPTON_CONTEXT}}")"
    podman_attach sh -c "killall gdbserver64 2>/dev/null" || true
}
function kill_lldb_server()
{
    local PREFIX="$(prefix "${1:-${LEPTON_CONTEXT}}")"
    LEPTON_PID="$(podman inspect -f '{{.State.Pid}}' "lepton-${LEPTON_CONTEXT}")"
    # Need host root user since it was started as root
    sudo nsenter -t "${LEPTON_PID}" -p -n -u -i -C -m \
         /system/bin/killall lldb-server 2>/dev/null || true
}


function gdb_attach_to_server()
{
    local PORT="${1:-$(gdb_port)}"
    while [[ "$(podman_attach sh -c "getprop ro.lepton.ready_for_debugger")" == "" ]]; do
        echo "Waiting for lepton.ready_for_debugger."
    done
    unlock_lepton
    "gdb" -q -ex "set pagination off" \
           -x "${LEPTON_DIR}/../images/rootfs_overlay/vendor/etc/gdb/gdb.init" \
           -ex "target remote localhost:${PORT}"
    lock_lepton
}


function lldb_attach_to_server()
{
    local PORT="${1:-$(lldb_port)}"
    local APP_CONTAINER_PID="$(map_pid "${PID}")"
    if [[ "${PID}" != "${APP_CONTAINER_PID}" ]]; then
        echo "PID automapped from ${PID} -> ${APP_CONTAINER_PID} within the container"
    fi
    unlock_lepton
    lldb --one-line "gdb-remote localhost:${PORT}"
    lock_lepton
}
