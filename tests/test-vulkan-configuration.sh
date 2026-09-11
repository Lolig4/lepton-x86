#!/bin/bash

set -euo pipefail

TESTS_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $TESTS_DIR/test-common.sh

test_log "Testing vulkan layers"

cp tests/test-apk.apk .

test_log "Testing khronos_validation"

monitor_logcat test-apk.apk &

(ENABLE_VULKAN_VALIDATION_LAYER=true ./lepton start test-apk.apk || test_log "container test-apk.apk failed to start, test will timeout.") &

wait_for_boot test-apk.apk

wait_for_app test-apk.apk com.example.neon42

# The command doesn't exit by itself.
(
    sleep 5
    killall logcat
) &

if [[ "$(./lepton logcat test-apk.apk --full |grep "GraphicsEnvironment: Vulkan debug layer list: VK_LAYER_KHRONOS_validation:VK_LAYER_fossilize")" == "" ]]; then
    test_log "KHRONOS_validation was not enabled!"
    test_failure
fi

./lepton stop test-apk.apk

test_log "Testing VALVE_fdm_injection"

monitor_logcat test-apk.apk &

(ENABLE_VULKAN_FDM_INJECTION_LAYER=true ./lepton start test-apk.apk || test_log "container test-apk.apk failed to start, test will timeout.") &

wait_for_boot test-apk.apk

wait_for_app test-apk.apk com.example.neon42

# The command doesn't exit by itself.
(
    sleep 5
    killall logcat
) &

if [[ "$(./lepton logcat test-apk.apk --full |grep "GraphicsEnvironment: Vulkan debug layer list: VK_LAYER_VALVE_fdm_injection:VK_LAYER_fossilize")" == "" ]]; then
    test_log "VALVE_fdm_injection was not enabled!"
    test_failure
fi

./lepton stop test-apk.apk

test_log "Testing VALVE_rpo"

monitor_logcat test-apk.apk &

RPO_LAYER_PATH="/usr/share/guestos/android/vendor/vulkan_layers/libVkLayer_VALVE_rpo.so"
RPO_LAYER_CREATED=false
if [[ ! -e "${RPO_LAYER_PATH}" ]]; then
    sudo touch "${RPO_LAYER_PATH}"
    RPO_LAYER_CREATED=true
fi

# This container will crash since the libVkLayer_VALVE_rpo.so file is a dummy, but we only care about whether the logcat reports the layer to be loaded
(ENABLE_VULKAN_RPO_LAYER=true ./lepton start test-apk.apk) &

wait_for_boot test-apk.apk

# wait_for_app test-apk.apk com.example.neon42

# The command doesn't exit by itself.
(
    sleep 5
    killall logcat
) &

if [[ "$(./lepton logcat test-apk.apk --full |grep "GraphicsEnvironment: Vulkan debug layer list: VK_LAYER_VALVE_rpo:VK_LAYER_fossilize")" == "" ]]; then
    test_log "VK_LAYER_VALVE_rpo was not enabled!"
    test_failure
fi

./lepton stop test-apk.apk

test_log "Testing gfxreconstruct"

monitor_logcat test-apk.apk &
LOGCAT_PID="$!"

(ENABLE_VULKAN_GFXRECONSTRUCT_LAYER=true LEPTON_GFXRECON_LOG_LEVEL=warning ./lepton start test-apk.apk || test_log "container test-apk.apk failed to start, test will timeout.") &

wait_for_boot test-apk.apk

wait_for_app test-apk.apk com.example.neon42

# The command doesn't exit by itself.
(
    sleep 5
    killall logcat
) &

if [[ "$(./lepton logcat test-apk.apk --full |grep "GraphicsEnvironment: Vulkan debug layer list: VK_LAYER_fossilize:VK_LAYER_LUNARG_gfxreconstruct")" == "" ]]; then
    test_log "VK_LAYER_LUNARG_gfxreconstruct was not enabled after VK_LAYER_fossilize!"
    test_failure
fi

if [[ "$(./lepton run test-apk.apk getprop debug.gfxrecon.log_level)" != "warning" ]]; then
    test_log "LEPTON_GFXRECON_LOG_LEVEL was not translated to debug.gfxrecon.log_level, but \"$(./lepton run test-apk.apk getprop debug.gfxrecon.log_level)\"!"
    test_failure
fi

./lepton stop test-apk.apk

kill "${LOGCAT_PID}"

test_log "Testing GLES_RenderDoc"

monitor_logcat test-apk.apk &

(ENABLE_VULKAN_RENDERDOC_CAPTURE=true ./lepton start test-apk.apk || test_log "container test-apk.apk failed to start, test will timeout.") &

wait_for_boot test-apk.apk

wait_for_app test-apk.apk com.example.neon42

# The command doesn't exit by itself.
(
    sleep 5
    killall logcat
) &

if [[ "$(./lepton logcat test-apk.apk --full |grep "GraphicsEnvironment: Vulkan debug layer list: VK_LAYER_fossilize:VK_LAYER_RENDERDOC_Capture")" == "" ]]; then
    test_log "VK_LAYER_RENDERDOC_Capture was not enabled!"
    test_failure
fi

./lepton stop test-apk.apk

test_log "Testing fossilize"

cp tests/test-vulkan.apk .

monitor_logcat test-vulkan.apk &

(./lepton start test-vulkan.apk || test_log "container test-vulkan.apk failed to start, test will timeout.") &

wait_for_boot test-vulkan.apk

wait_for_app test-vulkan.apk com.android.example.vulkan.tutorials.five

# The command doesn't exit by itself.
(
    sleep 5
    killall logcat
) &

if [[ "$(./lepton logcat test-vulkan.apk --full | grep "GraphicsEnvironment: Vulkan debug layer list: VK_LAYER_fossilize")" == "" ]]; then
    test_log "VK_LAYER_fossilize was not enabled!"
    test_failure
fi

sleep 5

if ! compgen -G '/home/steamos/.local/share/lepton/contexts/test-vulkan.apk/compatdata/test-vulkan.apk/external/fossilize.*.foz' >/dev/null; then
    test_log "fossilize was not functional!"
    test_failure
fi

# TODO: Find a way to test this on gitlab CI:

#if ! compgen -G '/home/steamos/.local/share/lepton/contexts/test-vulkan.apk/shadercache/test-vulkan.apk/fozpipelinesv6/steamapprun_pipeline_cache.*' >/dev/null; then
#    test_log "fossilize was not functional (2)!"
#    test_failure
#fi

#if ! compgen -G '/home/steamos/.local/share/lepton/contexts/test-vulkan.apk/shadercache/test-vulkan.apk/mesa_shader_cache_sf/**/foz_cache.foz.*' >/dev/null; then
#    test_log "fossilize was not functional (3)!"
#    test_failure
#fi

./lepton stop test-vulkan.apk

