#!/bin/bash

APP_DIR="${STEAM_COMPAT_INSTALL_PATH:-/foo}"

APP_PATH=""
function get_apk_path()
{
    if [[ -z "${APP_PATH}" ]]; then
        APP_PATH="$(compgen -G "${APP_DIR}/*.apk")"
    fi
    print "${APP_PATH}"
}

function is_app()
{
    [[ -n "$(get_apk_path)" ]]
}

function is_steamlaunch()
{
    [[ "${1:-${LEPTON_CONTEXT:-}}" == "steamlaunch-"* ]]
}

APK_INFO_EXTRACTOR_PATH="${LEPTON_DIR}/apk_extractor/bin/apk-info-extractor"
function cached_app_metadata()
{
    local VARNAME="${1}"
    local FILENAME="$(tr '[:upper:]' '[:lower:]' <<<"${VARNAME}")"
    local EXTRACT_FUNC="${2}"

    if [[ -z "${!VARNAME}" ]]; then
        local CACHE_PATH="$(get_baked_app_data_dir)/${FILENAME}"
        if [[ -f "${CACHE_PATH}" ]]; then
            eval "${VARNAME}=\"$(cat "${CACHE_PATH}")\""
        else
            eval "${VARNAME}=\"\$(${EXTRACT_FUNC})\""
        fi
    fi
    print "${!VARNAME}"
}

function extract_app_id()
{
    "${APK_INFO_EXTRACTOR_PATH}" --print-app-id "${1:-$(get_apk_path)}"
}

function extract_app_last_depot_version()
{
    println "compat_tool:$(lepton_version),rootfs:$(lepton_rootfs_version),sdk:$(android_sdk_version)"
}

APP_PACKAGE_ID=""
function get_app_id()
{
    if is_app; then
        if [[ -z "${APP_PACKAGE_ID}" ]]; then
            APP_PACKAGE_ID="$(extract_app_id "$(get_apk_path)")"
            if [[ -z "${APP_PACKAGE_ID}" ]]; then
                println "APP_PACKAGE_ID is empty?!  Check .apk metadata!" >&2
            fi
        fi
    fi
    print "${APP_PACKAGE_ID}"
}

function extract_app_activity()
{
    "${APK_INFO_EXTRACTOR_PATH}" --print-activity-name "${1:-$(get_apk_path)}"
}

function extract_app_hash()
{
    sha256sum "${1:-$(get_apk_path)}" | awk '{print $1}'
}

APP_ACTIVITY=""
function get_app_activity()
{
    if [[ -z "${APP_ACTIVITY}" ]]; then
        APP_ACTIVITY="$(extract_app_activity "$(get_apk_path)")"
        if [[ -z "${APP_ACTIVITY}" ]]; then
            println "ERROR: APP_ACTIVITY is empty, check APK metadata?" >&2
        fi
    fi
    print "${APP_ACTIVITY}"
}

# Returns something like `/data/app/abc/xyz`
function extract_app_mount_dir()
{
    local PACKAGES_XML_DIR="${1:-$(get_baked_app_data_dir)/data_overlay/system}"
    grep "$(get_app_id).*codePath" "${PACKAGES_XML_DIR}/packages.xml" 2>/dev/null | \
        sed -E -e 's/.*codePath="([^"]+)".*/\1/g'
}
APP_MOUNT_DIR=""
function get_app_mount_dir()
{
    cached_app_metadata APP_MOUNT_DIR extract_app_mount_dir
}

APP_HASH=""
function get_app_hash()
{
    cached_app_metadata APP_HASH extract_app_hash
}

APP_LAST_DEPOT_VERSION=""
function get_app_last_depot_version()
{
    cached_app_metadata APP_LAST_DEPOT_VERSION extract_app_last_depot_version
}

function save_app_metadata()
{
    # Purposefully run `get_xxx` before starting the `tee` process so we don't
    # accidentally read in from the file that `tee` itself created.
    function _write_val()
    {
        local BAKED_APP_DATA_DIR="$(get_baked_app_data_dir)"
        local VAL="$("get_${1}")"
        tee "${BAKED_APP_DATA_DIR}/${1}" <<<"${VAL}" >/dev/null
    }
    #_write_val "app_id"
    #_write_val "app_activity"
    _write_val "app_mount_dir"
    _write_val "app_hash"
    _write_val "app_last_depot_version"
}

# I'm not convinced this actually helps, so disabled for now
function preload_app_resources()
{
    function load_into_cache()
    {
        println "Loading $(lepton_basename "${1}") into file cache..."
        cat "${1}" >/dev/null 2>/dev/null &
    }

    local APK_PATH="$(get_apk_path)"
    if [[ -f "${APK_PATH}" ]]; then
        # Load into file cache
        load_into_cache "${APK_PATH}"

        local OBBS=(
            $(compgen -G "$(dirname "${APK_PATH}")/*.obb")
            $(compgen -G "$(dirname "${APK_PATH}")/obb/*.obb")
        )
        for OBB_PATH in "${OBBS[@]}"; do
            load_into_cache "${OBB_PATH}"
        done
    fi
}

APP_FLATSCREEN_FILE="${APP_DIR}/lepton-show-flatscreen"

function app_wants_flatscreen()
{
    if ! is_steamlaunch && ! is_app; then
        APP_WANTS_FLATSCREEN="true"
    fi

    # Allow certain dev workloads (such as `gfxreconstruct`) to explicitly request
    # headless operation through their context name, and make that override any
    # other logic we've got above, except for `APP_FLATSCREEN_FILE`.
    if [[ "${LEPTON_CONTEXT:-}" == headless-* ]]; then
        APP_WANTS_FLATSCREEN="false"
    fi

    [[ "${APP_WANTS_FLATSCREEN:-false}" == "true" ]] || [[ -f "${APP_FLATSCREEN_FILE}" ]]
}

function run_app_commands()
{
    local APP_ID="${1:-$(get_app_id)}"
    local APP_ACTIVITY="${2:-$(get_app_activity)}"
    print "am start -S ${APP_ID}/${APP_ACTIVITY}"
}
