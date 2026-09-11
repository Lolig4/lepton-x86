#
# Copyright (C) 2021 The Waydroid Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

PRODUCT_MAKEFILES := \
    aosp_lepton_arm64_only:$(LOCAL_DIR)/lepton_arm64_only/aosp_lepton_arm64_only.mk

COMMON_LUNCH_CHOICES := \
    aosp_lepton_arm64_only-trunk_staging-user \
    aosp_lepton_arm64_only-trunk_staging-userdebug \
    aosp_lepton_arm64_only-trunk_staging-eng \
