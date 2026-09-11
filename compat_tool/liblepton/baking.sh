#!/bin/bash


function is_sysbake() { [[ "${LEPTON_CONTEXT}" == "sysbake" ]]; }
function is_system_baked() {
    local PACKAGES_XML_PATH="${BAKED_SYSTEM_DATA_DIR}/system/packages.xml"

    # System is not baked if `packages.xml` does not exist
    [[ -f "${PACKAGES_XML_PATH}" ]]
}


# Run startup once, to get a `data` directory that we can overlay in the future
BAKED_SYSTEM_DATA_DIR="${LEPTON_DIR}/../sysbake"
function update_baked_system_data()
{
    if [[ ! -f "$(data_mount_path)/system/packages.xml" ]]; then
        die "ERROR! System data bake failed!"
    fi

    # Skip ipconfig.txt as it is container specific and has 000 chmod.
    rm -f "$(data_mount_path)/misc/ethernet/ipconfig.txt"
    cp -Ra "$(data_mount_path)" "${BAKED_SYSTEM_DATA_DIR}"
}

function wipe_baked_system_data()
{
    # Might not exist yet:
    chmod 700 -R "${BAKED_SYSTEM_DATA_DIR}" 2>/dev/null || true
    # Now wipe it
    rm -rf "${BAKED_SYSTEM_DATA_DIR}"
}

# These are the files we track for app pre-baking
function get_baked_app_data_dir()
{
    local CONTEXT="${1:-${LEPTON_CONTEXT}}"
    local DATA_PATH="${2:-${STEAM_COMPAT_DATA_PATH:-}}"

    if [[ -n "${DATA_PATH:-}" ]]; then
        print "${DATA_PATH:-}/baked"
    else
        print "${LEPTON_DATA_DIR}/${CONTEXT}/baked"
    fi
}

function update_baked_app_metadata()
{
    if is_steamlaunch; then
        # Save out app metadata
        save_app_metadata
    fi
}

function is_app_baked()
{
    is_app &&
    [[ "$(get_baked_app_data_dir)/data_overlay/system/packages.xml" -nt "$(get_apk_path)" ]] &&
    [[ -n "$(grep "$(get_app_id)" "$(get_baked_app_data_dir)/data_overlay/system/packages.xml" 2>/dev/null)" ]]
}

function autobake()
{
    if ! is_system_baked; then
        echo "Lepton system is not baked. Please verify the files of Lepton in Settings->Properties->Installed files"
        exit 1
    else
        # The depot does not contain xattrs, so we need to restore them from a
        # file. We perform this always in case someone interrupted the process.
        pushd "${LEPTON_DIR}"/.. >/dev/null
        setfattr --restore "${LEPTON_DIR}"/../sysbake.xattrs
        popd >/dev/null
    fi
}
