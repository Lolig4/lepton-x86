# SPDX-License-Identifier: Apache-2.0

# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)

# Inherit from waydroid device
$(call inherit-product, $(LOCAL_PATH)/../device.mk)

PRODUCT_BRAND := Steam-Frame
PRODUCT_DEVICE := lepton_arm64_only
PRODUCT_MANUFACTURER := Lepton
PRODUCT_NAME := lineage_lepton_arm64_only
PRODUCT_MODEL := Lepton arm64 only Device
