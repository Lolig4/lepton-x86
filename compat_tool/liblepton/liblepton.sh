#!/bin/bash

if [[ "${LIBLEPTON_STRICT:-true}" == "true" ]]; then
    set -euo pipefail
fi
LEPTON_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Global storage locations
LEPTON_ENTRYPOINT="${LEPTON_DIR}/../lepton"
LEPTON_DATA_DIR="${HOME}/.local/share/lepton/contexts"

STEAM_PATH="${HOME}/.local/share/Steam"
STEAMAPPS_PATH="${STEAM_PATH}/steamapps"

APK_AUTO_INSTALL_DIR="${HOME}/lepton_auto_install_apks"

# SteamOS ships adb at the Arch path; fall back to whatever is in PATH
# (Fedora/Debian install it as /usr/bin/adb via android-tools).
ADB="/usr/lib/android-sdk/platform-tools/adb"
if [[ ! -x "${ADB}" ]]; then
    ADB="$(command -v adb || true)"
fi

# Include our libraries of functionality
source "${LEPTON_DIR}/utils.sh"
source "${LEPTON_DIR}/networking.sh"
source "${LEPTON_DIR}/mounting.sh"
source "${LEPTON_DIR}/app_metadata.sh"
source "${LEPTON_DIR}/properties.sh"
source "${LEPTON_DIR}/baking.sh"
source "${LEPTON_DIR}/vulkan_layers.sh"
source "${LEPTON_DIR}/perfetto.sh"
source "${LEPTON_DIR}/performance_debugging.sh"
source "${LEPTON_DIR}/gdb.sh"
source "${LEPTON_DIR}/strace.sh"
source "${LEPTON_DIR}/debug.sh"

function steamos_devmode_enabled()
{
    [[ -e "/etc/steamos-devkit-enabled" ]]
}

function create_prefix()
{
    if [[ -z "${LEPTON_PREFIX:-}" ]]; then
        export LEPTON_PREFIX=$(mktemp -d -t lepton-context.XXXXXXXXXX)
    fi
}

function prepare_baked_data_for_removal()
{
    # Clear workdirs first
    if is_app; then
        local APP_WORKDIR="$(app_workdir $@)"
        if [[ -d "${APP_WORKDIR}" ]]; then
            chmod -R 700 "${APP_WORKDIR}"
            rm -rf "${APP_WORKDIR}"
        fi
    fi

    local DATA_WORKDIR="$(data_workdir $@)"
    if [[ -d "${DATA_WORKDIR}" ]]; then
        chmod -R 700 "${DATA_WORKDIR}"
        rm -rf "${DATA_WORKDIR}"
    fi

    local DATA_DIR="$(data_mount_path $@)"
    if [[ -d "${DATA_DIR}" ]]; then
        chmod -R 700 "${DATA_DIR}"
        rm -rf "${DATA_DIR}"
    fi

    local APPDATA_DIR="$(app_datadir $@)"
    if [[ -d "${APPDATA_DIR}" ]]; then
        chmod -R 700 "${APPDATA_DIR}"
        rm -rf "${APPDATA_DIR}"
    fi
}


function clear_baked_app_data()
{
    REASON="$1"
    shift

    if [[ "${LEPTON_NO_CLEANUP:-false}" != "false" ]]; then
        println "Skipping clearing baked app data due to env LEPTON_NO_CLEANUP"
    else
        println "Clearing baked app data due to ${REASON}"

        prepare_baked_data_for_removal $@
        rm -rf "$(get_baked_app_data_dir $@)"
    fi
}

function remove_prefix()
{
    if [[ -n "${LEPTON_PREFIX:-}" ]]; then
        # NOTE: upstream also calls prepare_baked_data_for_removal() here.  That
        # deletes the baked /data overlay -- the very thing is_app_baked() looks
        # for -- on every teardown, so the app is reinstalled on every single
        # start.  The prefix is its own temp directory; clear_baked_app_data()
        # still prepares the baked dirs when they really are meant to go.
        rm -rf "${LEPTON_PREFIX}"
    fi
}

function prefix()
{
    if [[ -z "${LEPTON_PREFIX:-}" ]]; then
        export LEPTON_PREFIX="$(podman inspect -f '{{ index .Config.Labels "PREFIX" }}' "lepton-${1:-${LEPTON_CONTEXT}}" 2>/dev/null || true)"
    fi

    if [[ -z "${LEPTON_PREFIX:-}" ]]; then
        die "${1:-${LEPTON_CONTEXT}}: no prefix!"
    fi

    print "${LEPTON_PREFIX}"
}

function data_mount_path()
{
    print "$(get_baked_app_data_dir $@)/data_overlay"
}

# The workdir must be in the same filesystem as the upperdir
function data_workdir()
{
    print "$(get_baked_app_data_dir $@)/data_workdir"
}

function app_workdir()
{
    print "$(get_baked_app_data_dir $@)/app_workdir"
}

function app_datadir()
{
    print "$(get_baked_app_data_dir $@)/app_overlay"
}

function setup_container()
{
    cleanup_container

    # Mount in vulkan layers, if requested by certain environment variables
    enable_vulkan_layers

    setup_mounts

    # SteamOS runs apps under gamescope, whose socket is gamescope-0.  On a
    # regular desktop session (KDE, GNOME, ...) there is no gamescope; fall back
    # to the session's own compositor instead of failing to mount the socket.
    local HOST_WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}"
    export WAYLAND_DISPLAY="${GAMESCOPE_WAYLAND_DISPLAY:-gamescope-0}"
    if [[ ! -e "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" && -n "${HOST_WAYLAND_DISPLAY}" \
          && -e "${XDG_RUNTIME_DIR}/${HOST_WAYLAND_DISPLAY}" ]]; then
        export WAYLAND_DISPLAY="${HOST_WAYLAND_DISPLAY}"
    fi
    export PULSE_RUNTIME_PATH="$XDG_RUNTIME_DIR/pulse"

    # Workaround for users who are stuck on older OS versions; drop this
    # once everyone is post https://swarm.valve.org/changes/9821351
    # Once that is true, also drop explicit `PULSE_RUNTIME_PATH` and just
    # assume it'll always be relative to `XDG_RUNTIME_DIR`.  This will require
    # a change to `mounting.sh` as well.
    if [[ ! -e "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]]; then
        if [[ -e "/home/$(id -u -n)/xdg/${WAYLAND_DISPLAY}" ]]; then
            export XDG_RUNTIME_DIR="/home/$(id -u -n)/xdg"
        fi
    fi
    if [[ ! -e "${PULSE_RUNTIME_PATH}" ]]; then
        if [[ -e "/run/user/$(id -u)/pulse" ]]; then
            export PULSE_RUNTIME_PATH="/run/user/$(id -u)/pulse"
        fi
    fi

    setup_podman_base
    setup_podman_mounts
    setup_podman_network
    setup_props
}

function onexit_path()
{
    print "$(data_mount_path)/lepton-on-app-exit"
}

# Marks that the app actually had a window on screen.  Tells a session the user
# ended from an app that died on startup.
function saw_window_path()
{
    print "$(data_mount_path)/lepton-saw-window"
}

function start_container()
{
    local CONTEXT="${1:-${LEPTON_CONTEXT}}"
    println "Launching lepton-${CONTEXT}"

    rm -f "$(onexit_path)"

    ROOTFS="$(readlink -f "${LEPTON_DIR}"/../images/rootfs)"
    # --init=false is used to make sure our container init runs as PID=1,
    # and to avoid spawning multiple "init" processes.
    # --read-only and --rootfs with the :O option make sure that we don't
    # accidentally modify the rootfs storage itself.
    USERNS_ARGS=(--userns=keep-id:uid=0,gid=0 --user 0:0 --group-add keep-groups)
    LOG_LEVEL_ARGS=()
    if [[ "${LEPTON_DEBUG:-false}" != "false" ]]; then
        LOG_LEVEL_ARGS=(--log-level=debug)
    fi

    (
        uninherit_lepton_lock

        exec stdbuf -o0 podman events \
            --filter container="lepton-${CONTEXT}" \
            --filter event=create | head -n0 >/dev/null 2>/dev/null || true
    ) &
    WAIT_CONTAINER_CREATION_PID="$!"

    # We need to remove the container now, before starting the new one
    # otherwise our podman commands running simultaneously would get
    # the wrong state
    podman rm -fi "lepton-${CONTEXT}" 2>/dev/null || true

    (
        uninherit_lepton_lock

        podman run \
            "${LOG_LEVEL_ARGS[@]}" \
            --replace \
            --read-only \
            --env-host=false \
            --init=false \
            --name "lepton-${CONTEXT}" \
            "${USERNS_ARGS[@]}" \
            "${PODMAN_CMDLINE[@]}" \
            --label lepton=true \
            --label lepton_pid="$$" \
            --label gdb_port=$(gdb_port) \
            --label lldb_port=$(lldb_port) \
            --label adb_port=$(adb_port) \
            --label STEAM_COMPAT_DATA_PATH="${STEAM_COMPAT_DATA_PATH:-}" \
            --label PREFIX="${LEPTON_PREFIX:-}" \
            --label IP="$(podman_ip)" \
            --rootfs "${ROOTFS}":O \
                /init
    ) &

    # Fallback for when the above podman events was executed after podman run.
    (
        uninherit_lepton_lock

        while ! podman container exists "lepton-${CONTEXT}"; do
            sleep 0.1
        done

        kill "${WAIT_CONTAINER_CREATION_PID}" 2>/dev/null >/dev/null || true
    ) &

    wait "${WAIT_CONTAINER_CREATION_PID}" 2>/dev/null >/dev/null || true

    # When the container has been created, we can safely unlock, since the
    # labels will be inspectable.
    unlock_lepton

    ONBOOT_PATH="/data/lepton-onboot"

    # This waits for our `lepton_onboot.rc` to trigger, then deletes the file
    println "Waiting for boot..."
    (
        uninherit_lepton_lock

        wait_for_container_file "${ONBOOT_PATH}"
    ) &
    WAIT_FILE_PID="$!"

    (
        # Check if CryptKeeper failed to start (bug!)
        if logcat_container "${CONTEXT}" | grep -q "Killing.*CryptKeeper.*start timeout"; then
            # If we ever reach here, the start timeout for CryptKeeper was hit
            podman_attach am start -n com.android.settings/.CryptKeeper
        fi
    ) &
    START_WORKAROUND_PID="$!"

    (
        # Check if a service failed to start (bug!)
        if logcat_container "${CONTEXT}" | grep -q "Forcing bringing down service"; then
            FAILED_SERVICE="$(logcat_container "${CONTEXT}" | stdbuf -o0 grep "Forcing bringing down service" | grep -o "ServiceRecord{.*}" | awk '{print $3}' | sed "s/}//g" | head -n0 >/dev/null 2>/dev/null || true)"
            # If we ever reach here, the start timeout for a service was hit
            podman_attach am start -n "${FAILED_SERVICE}"
        fi
    ) &
    START_WORKAROUND2_PID="$!"

    # If the container exits before the file lepton-onboot has been created
    # it may have been stopped before it finished booting and we need to
    # handle that
    (
        uninherit_lepton_lock

        podman wait "lepton-${CONTEXT}" 2>/dev/null >/dev/null || true
        pkill -P "${WAIT_FILE_PID}" 2>/dev/null || true
    ) &
    WAIT_PID="$!"

    wait "${WAIT_FILE_PID}" 2>/dev/null >/dev/null
    kill "${WAIT_PID}" 2>/dev/null || true
    kill "${START_WORKAROUND_PID}" 2>/dev/null || true
    kill "${START_WORKAROUND2_PID}" 2>/dev/null || true

    rm -f "$(data_mount_path)/${ONBOOT_PATH#/data/}"
    println "Boot complete!"

    (
        # Wait 10s for app to start up, so that we can filter to only our PID's messages, if possible.
        local T_START=$(date "+%s")
        while [[ -z "$(guess_app_pid)" ]] && (( $(date "+%s") < ${T_START} + 10)); do
            sleep 0.1
        done
        logcat_container | tee -a "$(lepton_log_file)"
    ) &

    if ! is_sysbake; then
        (
            uninherit_lepton_lock

            exec avahi-publish-service "lepton-${CONTEXT}" _adb._tcp "$(adb_port)" device="Lepton" model="Valve" version="30" >/dev/null 2>/dev/null
        ) &
    fi
}

function wait_for_container()
{
    local CONTEXT="${1:-${LEPTON_CONTEXT}}"
    local WAIT_FILE_PID=""

    unlock_lepton

    if is_app; then
        println "Waiting for app $(get_app_id) to exit..."

        (
            uninherit_lepton_lock

            wait_for_file "$(onexit_path)"
        ) &

        WAIT_FILE_PID="$!"
    else
        println "Waiting for ${CONTEXT} to exit..."
    fi

    local WAIT_WINDOW_PID=""
    if is_app && [[ "${LEPTON_APP_ONLY:-false}" == "true" ]]; then
        # In app-only mode the app owns the only window on the desktop.
        # Closing it ends the Android task, but Android keeps the process
        # cached, so the process observer never reports an exit and we would
        # wait forever.  "Had a window, has none" is the app being closed.
        (
            uninherit_lepton_lock

            SAW_WINDOW=false

            GONE=0
            while true; do
                WINDOWS="$(podman_attach --no-term sh -c 'getprop waydroid.open_windows' 2>/dev/null | tr -cd '0-9')"
                if [[ -n "${WINDOWS}" ]]; then
                    if (( WINDOWS > 0 )); then
                        if [[ "${SAW_WINDOW}" != "true" ]]; then
                            touch "$(saw_window_path)" 2>/dev/null || true
                        fi
                        SAW_WINDOW=true
                        GONE=0
                    elif [[ "${SAW_WINDOW}" == "true" ]]; then
                        # The window can disappear for a moment while Android
                        # rebuilds it, for instance when it is resized, so only
                        # a window that stays gone means the app is done.
                        GONE=$((GONE + 1))
                        if (( GONE >= 3 )); then
                            touch "$(onexit_path)"
                            break
                        fi
                    fi
                fi
                sleep 2
            done
        ) &
        WAIT_WINDOW_PID="$!"
    fi

    # NOTE: We intentionally do this `background-then-wait` pattern to ensure that SIGINT still works.
    (
        uninherit_lepton_lock

        podman wait "lepton-${CONTEXT}" 2>/dev/null >/dev/null || true
        touch "$(onexit_path)"
    ) &
    WAIT_PID="$!"

    if [[ -n "${WAIT_FILE_PID}" ]]; then
        wait "${WAIT_FILE_PID}" 2>/dev/null >/dev/null

        pkill -P "${WAIT_PID}" 2>/dev/null || true
        if [[ -n "${WAIT_WINDOW_PID}" ]]; then
            pkill -P "${WAIT_WINDOW_PID}" 2>/dev/null || true
            kill "${WAIT_WINDOW_PID}" 2>/dev/null || true
        fi
    else
        wait "${WAIT_PID}" 2>/dev/null >/dev/null
    fi

    # After the container has stopped, grab the lock
    lock_lepton

    println "Exited!"
}

function start_early_debug_container()
{
    local ROOTFS="$(readlink -f "${LEPTON_DIR}"/../images/rootfs)"
    # Manually symlink com.android.runtime so that `sh` can startup
    ln -vs "../system/apex/com.android.runtime" "${ROOTFS}/apex/com.android.runtime"
    trap "rm -f ${ROOTFS}/apex/com.android.runtime 2>/dev/null" INT TERM ERR EXIT

    unlock_lepton
    podman run \
        --replace \
        --env-host=false \
        --init=false \
        --name "lepton-${LEPTON_CONTEXT}" \
        --userns=keep-id:uid=0,gid=0 \
        --user 0:0 \
        --group-add keep-groups \
        --label lepton=true \
        --label lepton_pid="$$" \
        --label PREFIX="${LEPTON_PREFIX:-}" \
        "${PODMAN_CMDLINE[@]}" \
        -it \
        --rootfs ${ROOTFS}\
            /system/bin/sh
}

function podman_attach_no_context_check()
{
    ANDROID_PATH=(
        /product/bin
        /apex/com.android.runtime/bin
        /apex/com.android.art/bin
        /system_ext/bin
        /system/bin
        /system/xbin
        /odm/bin
        /vendor/bin
        /vendor/xbin
    )

    # --no-term prevents extra \r to be appended to the output
    if [[ "$1" == "--no-term" ]]; then
        TERM_ARGS="-i"
        shift
    else
        TERM_ARGS="-it"
    fi

    function join_by { local IFS="$1"; shift; println "$*"; }
    env -i PATH="$(join_by ":" "${ANDROID_PATH[@]}")" $(which podman) exec "${TERM_ARGS}" "lepton-${LEPTON_CONTEXT}" "$@"
}

function podman_attach()
{
    if ! is_context_live "${LEPTON_CONTEXT}"; then
        println "ERROR: '${LEPTON_CONTEXT}' is not a running context, use 'lepton ps' to list them, like this:" >&2
        println >&2
        list_containers >&2
        exit 1
    fi
    podman_attach_no_context_check "$@"
}

function guess_app_pid()
{
    local APP_ID="$(podman_attach --no-term sh -c "getprop lepton.active_app_id" 2>/dev/null)"
    if [[ -n "${APP_ID}" ]]; then
         local PID=$(podman_attach --no-term sh -c "ps -A -oPID,NAME" | grep "${APP_ID}" | head -1 | awk '{ print $1 }')
         echo -n "${PID}"
    fi
}

function attach_container()
{
    println "Attaching to lepton-${LEPTON_CONTEXT}"
    # During long running commands, we cannot hold the lock
    unlock_lepton
    podman_attach sh
}

function run_in_container()
{
    # Even if this is not a long running command, unlock, as the user might run
    # sh or logcat through the run/exec command.
    unlock_lepton
    podman_attach --no-term "$@"
}

function auto_install_apps()
{
    # Only auto-install apps if this is a dev context
    if is_app; then
        return;
    fi

    shopt -s globstar
    local APK_PATHS=( $(compgen -G "${APK_AUTO_INSTALL_DIR}/**/*.apk") )
    shopt -u globstar

    for APK_PATH in "${APK_PATHS[@]}"; do
        if ! test -r "${APK_PATH}"; then
            println "ERROR: ${APK_PATH} is not readable!  Skipping..." >&2
        else
            println "Installing $(lepton_basename "${APK_PATH}")"
            install_app "${APK_PATH}"
        fi
    done
}

function install_app()
{
    local APK_PATH="${1:-$(get_apk_path)}"
    APK_PATH="$(realpath "${APK_PATH}")"
    local APP_ID_FILE="$(dirname ${APK_PATH})/steam_appid.txt"
    local UE_COMMANDLINE_FILE="$(dirname ${APK_PATH})/UECommandLine.txt"
    local OBB_DIR="$(dirname ${APK_PATH})/obb"
    local OBB_DIR_IS_APK_DIR=false

    if [[ ! -d "${OBB_DIR}" ]]; then
        OBB_DIR="$(dirname ${APK_PATH})"
        OBB_DIR_IS_APK_DIR=true
    fi

    println "Installing ${APK_PATH}..."

    podman_attach sh -c "setprop lepton.active_app_id $(extract_app_id "${APK_PATH}")" 2>/dev/null

    (
        uninherit_lepton_lock

        ret=0

        # Deliberately using a different port as to not mess with the users
        # adb server.
        local ADB_PORT="$(adb_port)"
        local TEMP_PORT=$((ADB_PORT - 500))
        # Kill first to remove old connections
        "$ADB" -P "${TEMP_PORT}" kill-server 2>/dev/null
        # adbd starts listening shortly after boot completes, and pasta's
        # `-t auto` forwarding only picks the port up on its next scan, so a
        # single connect right after boot can lose that race (it does with a
        # fast, baked boot).  Retry until the device reports as `device`.
        local ADB_TRIES
        for ADB_TRIES in $(seq 1 30); do
            "$ADB" -P "${TEMP_PORT}" connect localhost:"${ADB_PORT}" >/dev/null 2>/dev/null || true
            if [[ "$("$ADB" -P "${TEMP_PORT}" -s localhost:"${ADB_PORT}" get-state 2>/dev/null)" == "device" ]]; then
                break
            fi
            sleep 1
        done
        if ! is_steamlaunch; then
            if [[ -f "${APP_ID_FILE}" ]]; then
                "$ADB" -P "${TEMP_PORT}" -s localhost:"${ADB_PORT}" push "${APP_ID_FILE}" /data/steam_app
            fi
            if [[ -f "${UE_COMMANDLINE_FILE}" ]]; then
                "$ADB" -P "${TEMP_PORT}" -s localhost:"${ADB_PORT}" push "${UE_COMMANDLINE_FILE}" /data/steam_app
            fi
            if [[ -z "${LEPTON_MOUNT_OBB_DIR:-}" ]]; then
                if [[ -n "${OBB_DIR_IS_APK_DIR}" ]]; then
                    "$ADB" -P "${TEMP_PORT}" -s localhost:"${ADB_PORT}" push "${OBB_DIR}/"*.obb /data/steam_app 2>/dev/null || true
                else
                    "$ADB" -P "${TEMP_PORT}" -s localhost:"${ADB_PORT}" shell mkdir /data/steam_app/obb
                    "$ADB" -P "${TEMP_PORT}" -s localhost:"${ADB_PORT}" push "${OBB_DIR}/"*.obb /data/steam_app/obb 2>/dev/null || true
                fi
            fi
        fi
        if ! "$ADB" -P "${TEMP_PORT}" -s localhost:"${ADB_PORT}" install -g "${APK_PATH}"; then
            println "App installation failed!"
            # We dump logcat if the container exits in less than <30s but just to
            # be safe (in case the startup took longer for some reason), we set
            # LEPTON_DUMP_LOGCAT here, to make sure the logcat is dumped in this
            # error situation.
            export LEPTON_DUMP_LOGCAT=1
            kill_container "${LEPTON_CONTEXT}"

            # Also clear the baked app data, since we need to appbake
            # again if we want to try again.
            clear_baked_app_data "app installation failure"
            ret=1
        fi
        # Can't leave processes around, otherwise we'd break closing the app.
        "$ADB" -P "${TEMP_PORT}" kill-server 2>/dev/null

        return $ret
    )

    return $?
}

function logcat_container()
{
    local filtered=()

    FULL_LOGCAT=false
    for arg in "$@"; do
        if [[ "$arg" != "--full" ]]; then
            filtered+=("$arg")
        else
            FULL_LOGCAT=true
        fi
    done

    APP_PID="$(guess_app_pid)"

    unlock_lepton
    if [[ "${FULL_LOGCAT}" == "true" ]] || [[ -z "${APP_PID}" ]]; then
        podman_attach logcat -v threadtime,color "${filtered[@]}"
    else
        podman_attach logcat -v threadtime,color --pid="${APP_PID}" "${filtered[@]}"
    fi
}


function parent_pid()
{
    awk '/PPid:/ {print $2}' "/proc/${1}/status" 2>/dev/null
}

function is_ancestor_of()
{
    local PARENT="$1"
    local CHILD="$2"

    if [[ -z "${PARENT}" ]] || [[ ! -d "/proc/${PARENT}" ]] || [[ -z "${CHILD}" ]] || [[ ! -d "/proc/${CHILD}" ]]; then
        return 1
    fi

    while [[ -n "${CHILD}" ]] && [[ "${CHILD}" -gt 1 ]]; do
        if [[ "${CHILD}" == "${PARENT}" ]]; then
            return 0
        fi
        CHILD="$(parent_pid "${CHILD}" || true)"
    done
    return 1
}


function kill_container()
{
    local CONTEXT="${1:-${LEPTON_CONTEXT}}"

    local LEPTON_PID=$(podman inspect -f '{{ index .Config.Labels "lepton_pid" }}' "lepton-${CONTEXT}" 2>/dev/null || true)

    podman exec -i "lepton-${CONTEXT}" /system/bin/reboot -p 2>/dev/null || true
    podman stop -t 0 "lepton-${CONTEXT}" 2>/dev/null >/dev/null || true

    # Can't wait for ourselves:
    if ! is_ancestor_of "${LEPTON_PID}" "$$"; then
        unlock_lepton

        while kill -0 "${LEPTON_PID}" 2>/dev/null; do
            println "Waiting for "${CONTEXT}" (PID '${LEPTON_PID}') to exit..."
            sleep 1
        done

        lock_lepton
    fi

    systemctl --user stop "lepton-${CONTEXT}.slice" 2>/dev/null || true
}

function kill_all()
{
    for CONTEXT in $(list_live_contexts); do
        kill_container "${CONTEXT}"
    done
}

function dump_logcat()
{
    # If the context isn't live, we can't dump logcat.
    if is_context_live; then
        local OUTPUT_DIR="${1}"
        mkdir -p "${OUTPUT_DIR}"

        # Dump logcat buffers in parallel
        LOGCAT_PIDS=()
        for BUFFER_NAME in main system kernel crash radio; do
            (podman_attach /bin/logcat -b ${BUFFER_NAME} -d | tee "${OUTPUT_DIR}/logcat-${BUFFER_NAME}.log" >/dev/null) &
            LOGCAT_PIDS+=( $! )
        done
        for PID in "${LOGCAT_PIDS[@]}"; do
            wait "${PID}" 2>/dev/null >/dev/null
        done
    fi
}

function list_android_games()
{
    STEAMAPPS_PATH="${HOME}/.local/share/Steam/steamapps"
    for GAME in ${STEAMAPPS_PATH}/appmanifest_*.acf; do
        # No Steam on this machine: the pattern stays unexpanded and the body
        # would run grep on a file that does not exist, whose failure trips the
        # ERR trap and tears the container down.
        [[ -e "${GAME}" ]] || continue
        INSTALLDIR="$(grep installdir ${GAME} | cut -d'"' -f4)"
        if compgen -G "${STEAMAPPS_PATH}/common/${INSTALLDIR}/*.apk" >/dev/null; then
            println "\"$(grep name ${GAME} | cut -d'"' -f4)\""
        fi
    done
}

function list_live_android_games()
{
    STEAMAPPS_PATH="${HOME}/.local/share/Steam/steamapps"
    for GAME in ${STEAMAPPS_PATH}/appmanifest_*.acf; do
        # No Steam on this machine: the pattern stays unexpanded and the body
        # would run grep on a file that does not exist, whose failure trips the
        # ERR trap and tears the container down.
        [[ -e "${GAME}" ]] || continue
        GAMENAME="$(grep name ${GAME} | cut -d'"' -f4)"
        if [[ "${GAMENAME}" == "${1:-}"* ]]; then
            INSTALLDIR="$(grep installdir ${GAME} | cut -d'"' -f4)"
            APPID="$(grep appid ${GAME} | cut -d'"' -f4)"
            if is_context_live steamlaunch-"${APPID}" && compgen -G "${STEAMAPPS_PATH}/common/${INSTALLDIR}/*.apk" >/dev/null; then
                println "\"${GAMENAME}\""
            fi
        fi
    done
}

function list_contexts()
{
    podman ps -a \
        --filter label=lepton=true \
        --format "{{.Names}}" | sed "s/lepton-//g"
}

function list_live_contexts()
{
    podman ps -a \
      --filter label=lepton=true \
      --format "{{.Names}} {{.Status}}" | grep "Up" | awk '{print $1}' | sed "s/lepton-//g" || true
}

function is_context_live()
{
    local CONTEXT="${1:-${LEPTON_CONTEXT}}"
    local STATE="$(podman inspect -f '{{ .State.Status }}' "lepton-${CONTEXT}" 2>/dev/null || true)"
    if [[ "${STATE}" == "running" ]]; then
        return 0
    fi

    if ! is_steamlaunch "${CONTEXT}"; then
        for GAME in ${STEAMAPPS_PATH}/appmanifest_*.acf; do
            # No Steam on this machine: the pattern stays unexpanded and the body
            # would run grep on a file that does not exist, whose failure trips the
            # ERR trap and tears the container down.
            [[ -e "${GAME}" ]] || continue
            if [[ "$(grep name ${GAME} | cut -d'"' -f4)" == "${CONTEXT}" ]]; then
                STEAMLAUNCH_CONTEXT="steamlaunch-$(grep appid ${GAME} | cut -d'"' -f4)"
                local STATE="$(podman inspect -f '{{ .State.Status }}' "lepton-${STEAMLAUNCH_CONTEXT}" 2>/dev/null || true)"
                [[ "${STATE}" == "running" ]]
                return $?
            fi
        done
    fi

    return 1
}

function list_containers()
{
    for CONTEXT in $(list_contexts); do
        if is_context_live "${CONTEXT}"; then
            IP=$(podman_ip "${CONTEXT}" || print "<?>")
            PACKAGES="$(LEPTON_CONTEXT="${CONTEXT}" podman_attach_no_context_check pm list packages -3 2>/dev/null |grep -o "package:.*" || true)"
            if [[ -n "${PACKAGES}" ]]; then
                APP_STR="packages: $(println ${PACKAGES} | sed "s/package://g" | sed -z 's/\r/,/g' | sed "s/,$//g")"
            else
                APP_STR=""
            fi
            ADB_PORT="$(adb_port "${CONTEXT}")"
            GDB_PORT="$(gdb_port "${CONTEXT}")"
            LLDB_PORT="$(lldb_port "${CONTEXT}")"
            IP_STR="(${IP}, "
            if [[ -n "${ADB_PORT}" ]]; then
                IP_STR+="adb on ${ADB_PORT}, "
            fi
            if [[ -n "${GDB_PORT}" ]]; then
                IP_STR+="gdb on ${GDB_PORT}, "
            fi
            if [[ -n "${LLDB_PORT}" ]]; then
                IP_STR+="lldb on ${LLDB_PORT}, "
            fi
            IP_STR+="${APP_STR})"
            println "${_GREEN}${CONTEXT} ${IP_STR}${_PLAIN}"
        else
            println "${_RED}${CONTEXT}${_PLAIN}"
        fi
    done
}

function cleanup_container()
{
    local CONTEXT="${1:-${LEPTON_CONTEXT}}"

    # Need to do this before cleaning the container, otherwise the variable
    # won't be available anymore.
    OTHER_STEAM_COMPAT_DATA_PATH="$(podman inspect -f '{{ index .Config.Labels "STEAM_COMPAT_DATA_PATH" }}' "lepton-${CONTEXT}" 2>/dev/null || true)"

    # Kill the container
    kill_container "${CONTEXT}"

    if [[ -n "${OTHER_STEAM_COMPAT_DATA_PATH}" ]]; then
        rm -f ${OTHER_STEAM_COMPAT_DATA_PATH}/baked/data_overlay/system/users/0/settings_global.xml || true
        rm -f ${OTHER_STEAM_COMPAT_DATA_PATH}/baked/data_overlay/system/users/0/settings_system.xml || true
        rm -f ${OTHER_STEAM_COMPAT_DATA_PATH}/baked/data_overlay/system/users/0/settings_secure.xml || true
    fi
}

function cleanup_all()
{
    echo "Cleaning up all contexts and stored state..."

    # In case there are legacy workdirs, we need to also chmod them.
    chmod -R 700 "${LEPTON_DATA_DIR}" || true

    # Stop/cleanup all contexts
    for CONTEXT in $(list_contexts); do
        cleanup_container "${CONTEXT}"

        STEAM_COMPAT_DATA_PATH="$(podman inspect -f '{{ index .Config.Labels "STEAM_COMPAT_DATA_PATH" }}' "lepton-${CONTEXT}" 2>/dev/null || true)"
        if [[ -n "${STEAM_COMPAT_DATA_PATH}" ]] && [[ -d "${STEAM_COMPAT_DATA_PATH}" ]]; then
            clear_baked_app_data "cleanup all" "${CONTEXT}" "${STEAM_COMPAT_DATA_PATH}"
        fi

        podman rm -fi "lepton-${CONTEXT}" || true
    done

    for CONTEXT in "${LEPTON_DATA_DIR}"/*; do
        [[ -e "$CONTEXT" ]] || break

        CONTEXT="$(lepton_basename ${CONTEXT})"
        cleanup_container "${CONTEXT}"

        STEAM_COMPAT_DATA_PATH="${LEPTON_DATA_DIR}/${CONTEXT}"
        if [[ -n "${STEAM_COMPAT_DATA_PATH}" ]] && [[ -d "${STEAM_COMPAT_DATA_PATH}" ]]; then
            clear_baked_app_data "cleanup all for non steamlaunch container" "${CONTEXT}" "${STEAM_COMPAT_DATA_PATH}"
        fi

        # This may already have been removed
        podman rm -fi "lepton-${CONTEXT}" 2>/dev/null >/dev/null || true
    done

    # Now that the contexts dir does not contain any contexts anymore
    # and thus no files that can't be rm'd due to chmod 0000, we can finally
    # remove all temporary contexts.
    rm -rf "${LEPTON_DATA_DIR}"/*

    if [[ " $@ " != " --keep-logcats " ]]; then
        logcat_debug_clear_all
    fi
}

function extract_file()
{
    local CONTEXT="${1}"
    local FILE_PATH="${2}"
    local DEST_DIR="${3}"

    local DATA_DIR="$(data_mount_path "${CONTEXT}")"

    if [[ "${FILE_PATH}" == "/data/"* ]] && [[ -e "${DATA_DIR}/${FILE_PATH#/data/}" ]]; then
        # File already in `/data`? Copy it out now
        cp -r "${DATA_DIR}/${FILE_PATH#/data/}" "${DEST_DIR}/"
    else
        # Otherwise, get it into `/data`, then copy it out
        podman_attach sh -c "mkdir -p /data/extracted; cp -r '${FILE_PATH}' /data/extracted/"
        cp -r "${DATA_DIR}/extracted/$(lepton_basename "${FILE_PATH}")" "${DEST_DIR}/"
    fi
}

function determine_app()
{
    IS_START=false
    if [[ "$1" == "--start" ]]; then
        IS_START=true
        shift
    fi

    local APP="${1}"

    # If STEAM_COMPAT_CLIENT_INSTALL_PATH is still unset, "guess" it now, to
    # make sure we mount libsteamclient.so if the guessed path is right.
    if [[ -z "${STEAM_COMPAT_CLIENT_INSTALL_PATH:-}" ]]; then
        export STEAM_COMPAT_CLIENT_INSTALL_PATH="${STEAM_PATH}"
    fi

    if ! is_sysbake && [[ "${LEPTON_CONTEXT}" != "dev" ]] && ! is_steamlaunch "${LEPTON_CONTEXT}" && [[ "${LEPTON_CONTEXT}" != *".apk" ]]; then
        # Might be the name of a game, let's see.
        # This might be slow when there's a ton of games, but it's kind of a debug option anyways.
        for GAME in ${STEAMAPPS_PATH}/appmanifest_*.acf; do
            # No Steam on this machine: the pattern stays unexpanded and the body
            # would run grep on a file that does not exist, whose failure trips the
            # ERR trap and tears the container down.
            [[ -e "${GAME}" ]] || continue
            if [[ "$(grep name ${GAME} | cut -d'"' -f4)" == "${LEPTON_CONTEXT}" ]]; then
                export SteamAppId="$(grep appid ${GAME} | cut -d'"' -f4)"
                export STEAM_COMPAT_INSTALL_PATH="${STEAMAPPS_PATH}/common/$(grep installdir ${GAME} | cut -d'"' -f4)"
                export STEAM_COMPAT_DATA_PATH="${STEAMAPPS_PATH}/compatdata/${SteamAppId}"
                # We don't know what the library paths would be, so just make sure we mount everything
                export STEAM_COMPAT_LIBRARY_PATHS="${STEAMAPPS_PATH}"
                export STEAM_COMPAT_SHADER_PATH="${STEAMAPPS_PATH}/shadercache/${SteamAppId}"
                export STEAM_FOSSILIZE_DUMP_PATH="${STEAMAPPS_PATH}/shadercache/${SteamAppId}/fozpipelinesv6/steamapp_pipeline_cache"
                if [[ -n "${APP}" ]]; then
                    export APP_PATH="${STEAM_COMPAT_INSTALL_PATH}/${APP}"
                else
                    APK_FILES=("${STEAM_COMPAT_INSTALL_PATH}"/*.apk)
                    export APP_PATH="$(println "${APK_FILES[0]}")"
                fi
                LEPTON_CONTEXT="steamlaunch-${SteamAppId}"
                break
            fi
        done
    elif [[ "${LEPTON_CONTEXT}" == *".apk" ]]; then
        local APK_FULL_PATH="${LEPTON_CONTEXT}"
        export LEPTON_CONTEXT="$(basename ${APK_FULL_PATH})"

        if [[ "${IS_START}" == "true" ]]; then
            create_prefix
            local LEPTON_APK_TMPDIR="${LEPTON_PREFIX}/tmp"
            mkdir -p "${LEPTON_APK_TMPDIR}"
            cp "${APK_FULL_PATH}" "${LEPTON_APK_TMPDIR}/"
            cp "$(dirname "${APK_FULL_PATH}")"/steam_appid.txt "${LEPTON_APK_TMPDIR}/" 2>/dev/null || true
            cp "$(dirname "${APK_FULL_PATH}")"/UECommandLine.txt "${LEPTON_APK_TMPDIR}/" 2>/dev/null || true

            if [[ ! -d "$(dirname "${APK_FULL_PATH}")/obb" ]]; then
                echo "WARNING: lepton start foo.apk cannot mount obbs from the same directory as the apk due to overlayfs limitations."
                echo "If you need any obb files, put them into "$(dirname "${APK_FULL_PATH}")/obb", otherwise ignore this message."
            else
                export LEPTON_MOUNT_OBB_DIR="$(cd "$(dirname "${APK_FULL_PATH}")/obb" && pwd)"
            fi

            export APP_PATH="${LEPTON_APK_TMPDIR}/$(basename ${LEPTON_CONTEXT})"
            export STEAM_COMPAT_DATA_PATH="${LEPTON_DATA_DIR}/${1:-${LEPTON_CONTEXT}}/compatdata/${LEPTON_CONTEXT}"
            export STEAM_COMPAT_LIBRARY_PATHS="${LEPTON_DATA_DIR}/${1:-${LEPTON_CONTEXT}}/compatdata/${LEPTON_CONTEXT}"
            export STEAM_COMPAT_SHADER_PATH="${LEPTON_DATA_DIR}/${1:-${LEPTON_CONTEXT}}/shadercache/${LEPTON_CONTEXT}"
            export STEAM_FOSSILIZE_DUMP_PATH="${LEPTON_DATA_DIR}/${1:-${LEPTON_CONTEXT}}/shadercache/${LEPTON_CONTEXT}/fozpipelinesv6/steamapp_pipeline_cache"
            mkdir -p "${STEAM_COMPAT_DATA_PATH}"
            mkdir -p "${STEAM_COMPAT_SHADER_PATH}"
        elif is_context_live; then
            export STEAM_COMPAT_DATA_PATH="$(podman inspect -f '{{ index .Config.Labels "STEAM_COMPAT_DATA_PATH" }}' "lepton-${LEPTON_CONTEXT}" 2>/dev/null || true)"
            export STEAM_COMPAT_SHADER_PATH="$(readlink -f "${STEAM_COMPAT_DATA_PATH:-}/../shadercache/${LEPTON_CONTEXT}")"
        fi
    fi

    if is_context_live; then
        export LEPTON_PREFIX="$(podman inspect -f '{{ index .Config.Labels "PREFIX" }}' "lepton-${LEPTON_CONTEXT}" 2>/dev/null || true)"
    elif [[ "${IS_START}" == "true" ]]; then
        create_prefix
    fi
}

function remove_context()
{
    local CONTEXT="${1:-${LEPTON_CONTEXT}}"
    podman rm -fi "lepton-${CONTEXT}" || true
}

function print_apk_info()
{
    if [[ -n "${APP_PACKAGE_ID:-}" ]]; then
        echo "APP ID: ${APP_PACKAGE_ID}"
    else
        echo "APP ID: $("${APK_INFO_EXTRACTOR_PATH}" --print-app-id "$1")"
    fi
    echo "ACTIVITY NAME: $("${APK_INFO_EXTRACTOR_PATH}" --print-activity-name "$1")"
    echo "APP VERSION: $("${APK_INFO_EXTRACTOR_PATH}" --print-app-version "$1")"
    echo "MIN SDK VERSION: $("${APK_INFO_EXTRACTOR_PATH}" --print-min-sdk-version "$1")"
}
