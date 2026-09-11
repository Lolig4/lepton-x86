function logcat_debug_dir()
{
    print "${STEAMVR_LOGS_DIR}/lepton-logcats/${LEPTON_CONTEXT}"
}

function logcat_debug_clear()
{
    rm -rf "$(logcat_debug_dir)"
}

function logcat_debug_clear_all()
{
    rm -rf "${STEAMVR_LOGS_DIR}/lepton-logcats"
}

function logcat_debug()
{
    if [[ -n "${LEPTON_DUMP_LOGCAT:-}" ]]; then
        local LOGCAT_DIR="$(logcat_debug_dir)"
        if [[ ! -d "${LOGCAT_DIR}" ]]; then
            mkdir -p "${LOGCAT_DIR}"
        fi
        local DATE_STR="$(date "+%m-%d %H:%M:%S.%N")"
        # Chop off everything except nanoseconds
        DATE_STR="${DATE_STR::-6}"
        echo "${DATE_STR}     0     0 D Lepton: ${1}" >>"${LOGCAT_DIR}/logcat-lepton.log"
    fi
}
