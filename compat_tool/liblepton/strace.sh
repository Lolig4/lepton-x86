function strace_enabled()
{
    [[ "${LEPTON_STRACE:-false}" != "false" ]]
}

function strace_zygote_commands()
{
    echo -n "exec >>/data/strace-$(get_app_id).debug 2>>/data/strace-$(get_app_id).debug; "
    echo -n "strace ${LEPTON_STRACE_ARGS:-} -v -s 1024 -f -p \"\${ro.lepton.application_pid}\" -o /data/strace-$(get_app_id).log;"
}

function extract_strace()
{
    local TARGET_DIR="$1"
    mkdir -p "${TARGET_DIR}"
    ls -la "$(data_mount_path)"
    extract_file "${LEPTON_CONTEXT}" "/data/strace-$(get_app_id).log" "${TARGET_DIR}" || true
    extract_file "${LEPTON_CONTEXT}" "/data/strace-$(get_app_id).debug" "${TARGET_DIR}" || true
}
