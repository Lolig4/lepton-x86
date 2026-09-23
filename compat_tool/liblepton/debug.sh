function collect_debug_logs()
{
    local LEPTON_BASE_ID=3029110
    #local LEPTON_ROOTFS_ID=3029111
    #local LEPTON_TOOL_ID=3029112
    local STEAM_BASE_FOLDER="${STEAM_BASE_FOLDER:-$(realpath -e ~/.steam/steam || echo ~/.local/share/Steam)}"
    local LOG_PATH="${STEAMVR_LOGS_DIR}"
    local CONSOLE_LOG="${LOG_PATH}/console_log.txt"

    local LEPTON_COMPAT_VERSION="$(pacman -Q | grep -E lepton-compat)"
    local STEAMOS_VERSION=$(source /etc/os-release; echo $BUILD_ID)
    local STEAMVR_VERSION="$(pacman -Q | grep -E 'deckard-steamvr-(main|rel)')"
    local STEAM_VERSION="$(cat ${HOME}/.steam/steam/package/steam_client_$(cat ${HOME}/.steam/steam/package/beta)_$(case "$(lepton_arch)" in aarch64) echo linuxarm64;; *) echo ubuntu12;; esac).manifest | grep version | awk '{ print $2 }' | xargs)"
    local LEPTON_VERSION="$(lepton_version)"
    local LEPTON_ROOTFS_VERSION="$(lepton_rootfs_version)"

    local LEPTON_BUILD_ID="$(cat ${STEAM_BASE_FOLDER}/steamapps/appmanifest_${LEPTON_BASE_ID}.acf | grep buildid | awk '{ print $2 }' | xargs)"

    local TIMESTAMP="$(date +%s)"
    local DATE="$(date +%Y-%m-%d_%H-%M-%S -d @${TIMESTAMP})"

    local TMP_DIR="$(mktemp -d)"

    mkdir -p "$TMP_DIR/logs"
    cp -fr "${LOG_PATH}/lepton"* "$TMP_DIR/logs" || true
    cp -f "${LOG_PATH}/xrclient"* "$TMP_DIR/logs" || true
    cp "${CONSOLE_LOG}" "$TMP_DIR/logs" || true
    echo "Date: ${DATE}" > "$TMP_DIR/info.txt"
    echo "lepton-compat Version: ${LEPTON_COMPAT_VERSION}" >> "$TMP_DIR/info.txt"
    echo "SteamOS Version: ${STEAMOS_VERSION}" >> "$TMP_DIR/info.txt"
    echo "SteamVR Version: ${STEAMVR_VERSION}" >> "$TMP_DIR/info.txt"
    echo "Steam Version: ${STEAM_VERSION}" >> "$TMP_DIR/info.txt"
    echo "Lepton Version: ${LEPTON_VERSION}" >> "$TMP_DIR/info.txt"
    echo "Lepton Rootfs Version: ${LEPTON_ROOTFS_VERSION}" >> "$TMP_DIR/info.txt"
    echo "Lepton Build ID: ${LEPTON_BUILD_ID}" >> "$TMP_DIR/info.txt"

    tar --zstd -cf "lepton-logs-${TIMESTAMP}.tar.zst" -C "${TMP_DIR}" .
    rm -rf "${TMP_DIR}"

    echo "Here you go: lepton-logs-${TIMESTAMP}.tar.zst"
}

function logsetup()
{
    tail -f -n +1 "$(lepton_log_file)"
}
