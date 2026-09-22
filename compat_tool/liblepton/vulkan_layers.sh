# Android does not have the nice vulkan loader that desktop Linux has.  It does not parse manifests and
# use environment variables to turn on and off layers defined in those manifests; instead it has global
# search paths that it uses to load "global layers" (which are always loaded), and it has values that
# can be set through `settings` to load "implicit layers".
#
# The global layers are loaded from:
#
#  - /data/local/debug/vulkan
#  - /{vendor,system}/lib64
#  - /data/app/xyz/foo-xyz/lib/<abi>
#
# The implicit layers are loaded from APKs pointed to by the settings, which you set up via commands
# such as the folloing:
#
#      settings put global gpu_debug_layer_app com.AppThatContains.VulkanLayer
#      settings put global gpu_debug_layers VK_LAYER_AwesomeLayer
#      settings put global gpu_debug_app com.ApplicationToAttach.LayerTo
#      settings put global enable_gpu_debug_layers 1
#
# To avoid needing to deal with all this `settings` nonsense, we opt to instead parse everything in
# Lepton, using environment variables to turn on/off vulkan layers.  Because we support a very
# limited set of vulkan layers (fossilize, validation, renderdoc, soon FDM) this is not too onerous,
# but in the future it'd be really nice to have the actual Linux loader's semantics available, so
# we can just drop a bunch of manifests and libraries into the system image, then set environment
# variables or properties to trigger them.

# We know about a bunch of layers and store their information here:
VULKAN_VALIDATION_LAYER_NAME="libVkLayer_khronos_validation.so"
RPO_LAYER_NAME="libVkLayer_VALVE_rpo.so"
FDM_INJECTION_LAYER_NAME="libVkLayer_VALVE_fdm_injection.so"
FOSSILIZE_LAYER_NAME="libVkLayer_fossilize.so"

RENDERDOC_APP_ID="org.renderdoc.renderdoccmd.$(lepton_app_abi_dir)"
RENDERDOC_LAYER_NAME="libVkLayer_GLES_RenderDoc.so"

# This layer doesn't have a json, so we special case it
RENDERDOC_LAYER_ID="VK_LAYER_RENDERDOC_Capture"

# We store all the layers we can enable within our `vulkan_layers` directory, and selectively mount
# in each layer depending on whether it's enabled or not.  We control this by setting the names of
# the layers to be mounted in within a bash array, then just do a containment check:
ENABLED_VULKAN_LAYER_PATHS=()
ENABLED_VULKAN_LAYER_IDS=()
ENABLED_VULKAN_LAYER_GLES_NAMES=()
ENABLED_VULKAN_LAYER_APP_IDS=()

# Given a layer filename (or just the layer-specific portion, like `fdm_injection`
# print out its full path in our `vulkan_layers` directory.
function find_vulkan_layer()
{
    local LAYER_NAME="$(lepton_basename "${1}")"
    local LAYER_DIR="/usr/share/guestos/android/vendor/vulkan_layers"

    local POSSIBLE_FILENAMES=(
        # First, check if `LAYER_NAME` is the actual basename of the file:
        "${LAYER_NAME}"

        # Next, check if this needs a `libVkLayer_` prefix:
        "libVkLayer_${LAYER_NAME}.so"

        # I don't remember which layer needed this, but we check for a capitalization mismatch too
        "libVkLayer_${LAYER_NAME,,}.so"
    )

    for LAYER_FILENAME in "${POSSIBLE_FILENAMES[@]}"; do
        # First, check if `LAYER_NAME` is the actual basename of the file:
        if [[ -f "${LAYER_DIR}/${LAYER_FILENAME}" ]]; then
            println "${LAYER_DIR}/${LAYER_FILENAME}"
            return
        fi
    done
}

function get_vulkan_layer_id()
{
    local LAYER_PATH="${1}"

    local -a CANDIDATES
    # 1) See if we can get the layer name from vulkan layer json's
    mapfile -t CANDIDATES < <(
        find /usr/share/vulkan -name '*.json' -type f -print0 2>/dev/null |
            xargs -0 jq -r --arg LAYER_PATH "${LAYER_PATH##*/}" '
                .. | objects
                | select(.library_path? | type == "string" and endswith($LAYER_PATH))
                | .name?
            ' |
            grep -v '^null$'
    )

    # Special-case renderdoc to have its correct layer ID; it doesn't have a JSON file yet
    if [[ "${#CANDIDATES[@]}" == "0" ]] && [[ "${LAYER_PATH##*/}" == "${RENDERDOC_LAYER_NAME}" ]]; then
        CANDIDATES=( "${RENDERDOC_LAYER_ID}" )
    fi

    # Special-case FDM layer; if the actual .so is old enough that it doesn't have
    # the correct layer ID, override what the `.json` says.  Remove this workaround
    # once SteamOS stable has shipped vulkan layers 20260827.1 or later.
    local LAYER_DIR="/usr/share/guestos/android/vendor/vulkan_layers"
    if [[ "${LAYER_PATH##*/}" == "${FDM_INJECTION_LAYER_NAME}" ]]; then
        local OLD_FDM_LAYER_ID="VK_LAYER_fdm_injection"
        if grep -qa "${OLD_FDM_LAYER_ID}" "${LAYER_DIR}/${FDM_INJECTION_LAYER_NAME}"; then
            CANDIDATES=( "${OLD_FDM_LAYER_ID}" )
        fi
    fi

    if [[ "${#CANDIDATES[@]}" == "1" ]]; then
        println "${CANDIDATES[0]}"
        return 0
    fi

    echo "ERROR: Unable to determine Layer ID for '${LAYER_PATH}'" >&2
    return 1
}

function vulkan_layer_enabled()
{
    local LAYER_FILENAME="$(find_vulkan_layer "$1")"
    [[ " ${ENABLED_VULKAN_LAYER_PATHS[*]} " == *" ${LAYER_FILENAME} "* ]]
}


function enable_vulkan_layer()
{
    local LAYER_FILENAME="$(find_vulkan_layer "${1}")"

    if [[ ! -f "${LAYER_FILENAME}" ]]; then
        echo "ERROR: Unable to find layer for '${1}'" >&2
        return 1
    fi

    if ! vulkan_layer_enabled "${LAYER_FILENAME}"; then
        # Recording the library path in this array will cause it to be mounted into the app's libdir
        ENABLED_VULKAN_LAYER_PATHS+=( "${LAYER_FILENAME}" )

        # Recording the library ID in this array will cause it to be inserted into settings in this order.
        ENABLED_VULKAN_LAYER_IDS+=( "$(get_vulkan_layer_id "${LAYER_FILENAME}" )" )
    else
        println "WARNING: '$(lepton_basename "${LAYER_FILENAME}")' enabled multiple times, skipping!"
    fi
    println "Enabled vulkan layer '$(lepton_basename "${LAYER_FILENAME}")'"
}

function enable_vulkan_layers()
{
    # The ordering of vulkan layers matters; we conceptually think of layers
    # being applied to render commands flowing from the application to the driver.
    # In general we want to preserve the following properties:
    #   * RPO should be before FDM
    #   * Fossilize should be after all non-debugging layers, in order to properly
    #     capture all relevant information for caching.
    #   * Renderdoc (and other debugging layers) should be inserted at the end
    
    # If you want to debug the app, vulkan validation layers inserted here makes sense
    if [[ "${ENABLE_VULKAN_VALIDATION_LAYER:-0}" != "0" ]]; then
        enable_vulkan_layer "${VULKAN_VALIDATION_LAYER_NAME}"
        unset ENABLE_VULKAN_VALIDATION_LAYER
    fi

    # Load layers defined in VK_INSTANCE_LAYERS.  This is also a way to override ordering if you really need to.
    if [[ "${VK_INSTANCE_LAYERS+isset}" == "isset" ]]; then
        for LAYER in ${VK_INSTANCE_LAYERS//:/ }; do
            echo "VK_INSTANCE_LAYERS requests: '${LAYER/#VK_LAYER_}'"
            if ! enable_vulkan_layer "${LAYER/#VK_LAYER_}"; then
                println " -> Continuing on, as that was requested via VK_INSTANCE_LAYERS..."
            fi
        done
        unset VK_INSTANCE_LAYERS
    fi

    # Renderpass Optimizer goes before FDM
    if [[ "${ENABLE_VULKAN_RPO_LAYER:-0}" != "0" ]]; then
        enable_vulkan_layer "${RPO_LAYER_NAME}"
        unset ENABLE_VULKAN_RPO_LAYER
    fi
    if [[ "${ENABLE_VULKAN_FDM_INJECTION_LAYER:-0}" != "0" ]]; then
        enable_vulkan_layer "${FDM_INJECTION_LAYER_NAME}"
        unset ENABLE_VULKAN_FDM_INJECTION_LAYER
    fi

    # Fossilize goes after any other normal layers.  It records pipelines for
    # Steam's shader cache and ships in SteamOS' Android layer package under
    # /usr/share/guestos; hosts without that package run fine without it.
    if ! enable_vulkan_layer "${FOSSILIZE_LAYER_NAME}"; then
        println " -> Continuing without fossilize (no Steam shader pipeline capture)"
    fi

    # If you want to debug the app + layers, vulkan validation layers inserted here makes sense
    if [[ "${ENABLE_VULKAN_VALIDATION_LAYER_LATE:-0}" != "0" ]]; then
        enable_vulkan_layer "${VULKAN_VALIDATION_LAYER_NAME}"
        unset ENABLE_VULKAN_VALIDATION_LAYER_LATE
    fi

    # Quick and easy way to enable the gfxreconstruct capture layer
    if [[ "${ENABLE_VULKAN_GFXRECONSTRUCT_LAYER:-0}" != "0" ]]; then
        enable_vulkan_layer "gfxreconstruct"
        unset ENABLE_VULKAN_GFXRECONSTRUCT_LAYER
    fi

    # Renderdoc goes at the very end, and is a bit of a special snowflake;
    # we have to enable both the Vulkan and GLES layers.  Most annoyingly,
    # the Vulkan layer isn't shipped in our vulkan_layers directory, it is
    # instead shipped within the 
    if [[ "${ENABLE_VULKAN_RENDERDOC_CAPTURE:-0}" != "0" ]]; then
        enable_vulkan_layer "${RENDERDOC_LAYER_NAME}"
        unset ENABLE_VULKAN_RENDERDOC_CAPTURE

        # Renderdoc needs its `.apk` loaded, and its layer registered as a GLES layer as well
        ENABLED_VULKAN_LAYER_APP_IDS+=( "${RENDERDOC_APP_ID}" )
        ENABLED_VULKAN_LAYER_GLES_NAMES+=( "${RENDERDOC_LAYER_NAME}" )
    fi
}

function generate_vulkan_settings_script()
{
    # Do nothing if we have no layers enabled (super rare; fossilize at least should be enabled)
    if (( "${#ENABLED_VULKAN_LAYER_IDS[@]}" <= 0 )); then
        return
    fi

    # If renderdoc is enabled, install the renderdoc app:
    if vulkan_layer_enabled "${RENDERDOC_LAYER_NAME}"; then
        cat <<-EOF
pm install -g /vendor/apps_to_install/${RENDERDOC_APP_ID}.apk;
pm grant ${RENDERDOC_APP_ID} android.permission.MANAGE_EXTERNAL_STORAGE;
EOF
    fi

    # Set the target application as the "GPU debug app", which enables our vulkan
    # layers for only that application.  Then emit our concatenated list of layer IDs to load.
    if [[ "${#ENABLED_VULKAN_LAYER_IDS[@]}" -gt 0 ]]; then
        cat <<-EOF
settings put global gpu_debug_app \$(getprop lepton.active_app_id);
settings put global enable_gpu_debug_layers 1;
settings put global gpu_debug_layers $(colon_path_list "${ENABLED_VULKAN_LAYER_IDS[@]}")
EOF
    fi

    if [[ "${#ENABLED_VULKAN_LAYER_GLES_NAMES[@]}" -gt 0 ]]; then
        cat <<-EOF
settings put global gpu_debug_layers_gles $(colon_path_list "${ENABLED_VULKAN_LAYER_GLES_NAMES[@]}")
EOF
    fi

    if [[ "${#ENABLED_VULKAN_LAYER_APP_IDS[@]}" -gt 0 ]]; then
        cat <<-EOF
settings put global gpu_debug_layer_app $(colon_path_list "${ENABLED_VULKAN_LAYER_APP_IDS[@]}")
EOF
    fi
}
