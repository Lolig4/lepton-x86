#!/bin/bash

function props_file()
{
    print "$(prefix)/lepton.prop"
}

function setup_props()
{
    local CONTEXT="${1:-${LEPTON_CONTEXT}}"
    PROPS_FILE="$(props_file)"
    PROPERTIES=""
    function props_echo()
    {
        PROPERTIES+="$@"$'\n'
    }
    rm -f "${PROPS_FILE}"
    
    # If we don't have `ashmem`, tell android to use `memfd` instead.
    if [[ ! -e /dev/ashmem ]]; then
        props_echo "sys.use_memfd=true"
    fi

    if steamos_devmode_enabled; then
        props_echo "ro.lepton.devmode=true"
    else
        props_echo "ro.lepton.devmode=false"
    fi

    local VAR
    for VAR in $(compgen -A variable LEPTON_GFXRECON_); do
        local OPTION="${VAR#LEPTON_GFXRECON_}"
        local VALUE="${!VAR}"
        props_echo "debug.gfxrecon.${OPTION,,}=${VALUE}"
    done

    # Unpriv single user mode
    # bpfloader is disabled
    props_echo "bpf.progs_loaded=1"
    # ueventd is disabled
    props_echo "ro.cold_boot_done=true"

    # We have to use dex2oat64 as we are 64-bit only.
    props_echo "dalvik.vm.dex2oat64.enabled=true"
    props_echo "dalvik.vm.usejit=true"

    # Video/Rendering props
    props_echo "debug.stagefright.ccodec=0"
    props_echo "ro.opengles.version=196609"
    props_echo "ro.hardware.camera=v4l2"

    if [[ "${LEPTON_FORCE_SOFTWARE:-}" == "true" ]]; then
        # sysbake on gitlab
        if [[ "$(android_sdk_version)" == "30" ]]; then
            props_echo "ro.hardware.egl=swiftshader"
        else
            props_echo "ro.hardware.egl=angle"
            props_echo "ro.hardware.vulkan=pastel"
        fi
        props_echo "ro.hardware.gralloc=default"
        # tests on gitlab
        props_echo "ro.hardware.vulkan=pastel"
    else
        # Default to using turnip as our driver, but allow using the qcom driver
        if [[ "${LEPTON_USE_QCOM_DRIVER:-false}" == "true" ]]; then
            props_echo "ro.hardware.egl=angle"
            props_echo "ro.hardware.vulkan=adreno"
            props_echo "ro.hardware.gralloc=qti-display"
            props_echo "vendor.gralloc.disable_ubwc=1"
        else
            props_echo "ro.hardware.egl=mesa"
            props_echo "ro.hardware.vulkan=freedreno"
            props_echo "ro.hardware.gralloc=minigbm_msm"
        fi

        # Zink + disable kopper to work with mesa
        props_echo "mesa.loader.driver.override=zink"
        props_echo "mesa.libgl.kopper.disable=true"

        # Tell Fossilize to write out shaders to this directory
        if is_app && [[ -n "${STEAM_FOSSILIZE_DUMP_PATH:-}" ]]; then
            local DUMP_SUBPATH="${STEAM_FOSSILIZE_DUMP_PATH#${STEAM_COMPAT_SHADER_PATH}/}"
            props_echo "debug.fossilize.dump_path=/data/shaders/${DUMP_SUBPATH}"
            props_echo "mesa.shader.cache.disable=false"
            props_echo "mesa.shader.cache.dir=/data/shaders"
        fi
    fi

    props_echo "ro.vndk.lite=true"
    props_echo "ro.product.model=Lepton"
    props_echo "ro.product.manufacturer=Valve"

    props_echo "ro.steam.running_in_app_container=true"

    # Set logcat to use a specific buffer size (useful when debugging)
    props_echo "ro.logd.size=${LEPTON_LOGCAT_BUFFER_SIZE:-256K}"
    props_echo "ro.logd.filter=disable"

    # Perhaps someday enable iorapd for I/O prefetching on apps
    # NOTE: In my testing, iorapd is so slow to start, we have to wait an extra 400ms
    # for it to be ready, which is a non-starter for us, as we always start from boot!
    #props_echo "ro.iorapd.enable=true"
    #props_echo "ro.iorapd.dexopt.enable=true"
    #props_echo "ro.iorapd.perfetto.enable=true"
    #props_echo "ro.iorapd.readahead.enable=true"

    # This is queried by the Android Vulkan loader at startup time
    # and is set by SurfaceFlinger. Our SurfaceFlinger is run using Zink.
    # Thus, set this ourselves to avoid a deadlock.
    props_echo "service.sf.present_timestamp=0"

    # Disable services we don't actually need
    # android/frameworks/base/services/java/com/android/server/SystemServer.java
    # prevents "connecting to camera service" spam
    props_echo "config.disable_cameraservice=true"
    props_echo "config.disable_otadexopt=true"
    props_echo "config.disable_systemtextclassifier=true"
    props_echo "config.disable_networktime=true"

    # Disable boot animation
    props_echo "debug.sf.nobootanimation=1"

    props_echo "waydroid.host.user=$(id -u -n)"
    props_echo "waydroid.host.uid=1000"
    props_echo "waydroid.host.gid=1000"
    props_echo "waydroid.xdg_runtime_dir=/waydroid/xdg"
    props_echo "waydroid.pulse_runtime_path=/waydroid/xdg/pulse"
    props_echo "waydroid.stub_sensors_hal=1"

    # Only show the 2d screen if we're not baking and our app requests it.
    if ! is_sysbake && app_wants_flatscreen; then
        props_echo "waydroid.wayland_display=wayland-0"
        props_echo "waydroid.background_start=false"
        props_echo "lepton.headless=false"
    else
        props_echo "lepton.headless=true"
    fi

    props_echo "lepton.active_app_launch_timeout=60"

    # Tell `libsteam_api.so` where to find `libsteamclient.so`
    props_echo "lepton.steamclient.path=/system/lib64/libsteamclient.so"

    # Tell renderdoc to flip certain behavioral switches for us:
    props_echo "debug.renderdoc.autograntpermissions=1"

    # Enable traced
    props_echo "persist.traced.enable=1"
    if is_app; then
        props_echo "debug.atrace.app_0=$(get_app_id)"
    fi

    # We have a system service that watches for a process exit matching
    # this package name, and then shuts down the container.
    if is_app; then
        props_echo "lepton.app_id=$(get_app_id)"

        # This one isn't watched by the process observer, but it is
        # used by other tools like the perfetto and renderdoc integrations
        props_echo "lepton.active_app_id=$(get_app_id)"
    fi

    if is_app_baked; then
        props_echo "ro.lepton.app_baked=1"
    fi

    # Set correct timezone
    local TIMEZONE_STR="$(readlink /etc/localtime)"
    TIMEZONE_STR="${TIMEZONE_STR#/usr/share/zoneinfo/}"
    props_echo "persist.sys.timezone=${TIMEZONE_STR}"

    if [[ -n "${LEPTON_ADB_PORT:-}" ]]; then
        props_echo "service.adb.tcp.port=${LEPTON_ADB_PORT}"
    fi

    println "${PROPERTIES}" >"${PROPS_FILE}"

    # Android `init` refuses to load a file with group-writable permissions
    chmod 0644 "${PROPS_FILE}"
}
