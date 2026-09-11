# SPDX-License-Identifier: Apache-2.0

-include device/waydroid/waydroid/BoardConfig.mk

# Architecture
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-2a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
# Using the highest available cpu variant for now
TARGET_CPU_VARIANT := cortex-a76

TARGET_2ND_ARCH :=
TARGET_2ND_ARCH_VARIANT :=
TARGET_2ND_CPU_ABI :=
TARGET_2ND_CPU_ABI2 :=
TARGET_2ND_CPU_VARIANT :=

AUDIOSERVER_MULTILIB := first

# We inject vulkan drivers from elsewhere
# and we only need mesa to be able to build
# gralloc against libgbm_mesa.
BOARD_MESA3D_VULKAN_DRIVERS :=
