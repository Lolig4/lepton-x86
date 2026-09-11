function perfetto_installed()
{
    [[ -f /usr/share/guestos/android/perfetto/tracebox ]]
}

PERFETTO_DIR="${LEPTON_DIR}/perfetto"
function start_traced_probes()
{
    if ! perfetto_installed; then
        echo "Skipping perfetto setup due to missing tracebox binary (install perfetto-android if you need to use perfetto)."
        return
    fi

    unlock_lepton

    (
        uninherit_lepton_lock

        podman_attach sh -c "/perfetto/tracebox traced_probes" > /tmp/lepton_traced_probes.log &
    )

    lock_lepton
}

function perfetto_capture()
{
    local CONTEXT="${1:-${LEPTON_CONTEXT}}"
    local PERFETTO_CONFIG="${2:-${PERFETTO_DIR}/system.cfg}"

    if ! perfetto_installed; then
        echo "perfetto is not installed. In order to perform a capture install perfetto-android and restart the container."
        return
    fi

    # Run perfetto to connect to our preexisting traced daemon
    local PERFETTO_CONFIG_NAME="$(lepton_basename "${PERFETTO_CONFIG}")"
    PERFETTO_CONFIG_NAME="${PERFETTO_CONFIG_NAME%.*cfg}"
    local TRACE_PATH="/tmp/lepton-${CONTEXT}-${PERFETTO_CONFIG_NAME}-$(date '+%s').pftrace"
    echo "Running perfetto with ${PERFETTO_CONFIG_NAME} config, use CTRL-C to early-exit..."

    podman_attach sh -c "/system/bin/atrace --async_start --only_userspace -a \*"

    unlock_lepton
    tracebox perfetto --txt -c "${PERFETTO_CONFIG}" -o "${TRACE_PATH}"
    lock_lepton

    podman_attach sh -c "/system/bin/atrace --async_stop --only_userspace"
    
    echo -n "perfetto trace available: "; du -lh "${TRACE_PATH}"
}
