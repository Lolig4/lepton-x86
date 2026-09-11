LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := RemovePackages
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_TAGS := optional
LOCAL_OVERRIDES_PACKAGES := AudioFX Bluetooth BluetoothMidiService

# Lepton
LOCAL_OVERRIDES_PACKAGES := $(LOCAL_OVERRIDES_PACKAGES) \
    LatinIME \
    HTMLViewer \
    OsuLogin \
    NavigationBarMode2ButtonOverlay \
    ServiceWifiResources \
    Tethering \
    bootanimation \
    com.android.neuralnetworks \
    wificond \
    incidentd

# /system/app/*
LOCAL_OVERRIDES_PACKAGES := $(LOCAL_OVERRIDES_PACKAGES) \
	BasicDreams \
	BookmarkProvider \
	BoringdroidSystemUIApk \
	CaptivePortalLogin \
	CompanionDeviceManager \
	CtsShimPrebuilt \
	EasterEgg \
	LiveWallpapersPicker \
	NfcNci \
	PacProcessor \
	PrintRecommendationService \
	PrintSpooler \
	SimAppDialog \
	Traceur \
	WallpaperBackup \
	# ExtShared <--- required, apparently

# /system/product/app
LOCAL_OVERRIDES_PACKAGES := $(LOCAL_OVERRIDES_PACKAGES) \
	PhotoTable \
	Backgrounds \
	LocalContactsBackup \
	Jelly \
	LineageThemesStub

# /system/priv-app/*
LOCAL_OVERRIDES_PACKAGES := $(LOCAL_OVERRIDES_PACKAGES) \
	BackupRestoreConfirmation \
	BlockedNumberProvider \
	BuiltInPrintService \
	CalendarProvider \
	ContactsProvider \
	CtsShimPrivPrebuilt \
	DownloadProvider \
	DownloadProviderUi \
	DynamicSystemInstallationService \
	InputDevices \
	LineageParts \
	LocalTransport \
	ManagedProvisioning \
	MediaProviderLegacy \
	MmsService \
	MtpService \
	NetworkPermissionConfig \
	ProxyHandler \
	Seedvault \
	SharedStorageBackup \
	SoundPicker \
	StatementService \
	TeleService \
	Telecom \
	TelephonyProvider \
	UserDictionaryProvider \
	VpnDialogs \
	#FusedLocation <--- this required, perhaps can find way to disable all location? \
	#LineageSettingsProvider \
	#NetworkStack \
	#PackageInstaller <--- this required \
	#SettingsProvider \
	#Shell <--- To disable this, need to patch out `DevelopmentSettingsObserver` from looking for us \

# /system/system_ext/priv-app
LOCAL_OVERRIDES_PACKAGES := $(LOCAL_OVERRIDES_PACKAGES) \
	Gallery2 \
	Provision \
	StorageManager \
	ThemePicker \
	WallpaperCropper \
	WAPPushManager \
	WaydroidUpdater \
	#TrebuchetQuickStep \
	#SystemUI <--- This would be great, but is going to need some serious surgery. \
	#Settings \
	#SimpleDeviceConfig \

# /system/product/overlay
LOCAL_OVERRIDES_PACKAGES := $(LOCAL_OVERRIDES_PACKAGES) \
	LineageBlackTheme \
	LineageBlackAccent \
	LineageBlueAccent \
	LineageBrownAccent \
	LineageCyanAccent \
	LineageGreenAccent \
	LineageOrangeAccent \
	LineagePinkAccent \
	LineagePurpleAccent \
	LineageRedAccent \
	LineageYellowAccent \
	LineageRubikFont \
	IconShapeSquareOverlay \
	LineageNavigationBarNoHint \
	frameworks-base-overlays \


# /system/product/priv-app
LOCAL_OVERRIDES_PACKAGES := $(LOCAL_OVERRIDES_PACKAGES) \
	Contacts \
	OneTimeInitializer \

# Frameworks.  To build these, I ran:
#    find . -name Android.mk -o -name Android.bp > list.txt
#     xargs grep --color 'name: .*android.hardware.radio.*' < list.txt | cut -f3- -d: | sort -u

LOCAL_OVERRIDES_PACKAGES := $(LOCAL_OVERRIDES_PACKAGES) \
	com.android.phone \
	android.hardware.gnss \
	android.hardware.radio@1.0 \
	android.hardware.radio@1.1 \
	android.hardware.radio@1.2 \
	android.hardware.radio@1.2-radio-service \
	android.hardware.radio@1.2-sap-service \
	android.hardware.radio@1.3 \
	android.hardware.radio@1.4 \
	android.hardware.radio@1.5 \
	android.hardware.radio.config@1.0 \
	android.hardware.radio.config@1.0-service \
	android.hardware.radio.config@1.1 \
	android.hardware.radio.config@1.2 \
	android.hardware.radio.deprecated@1.0 \
	android.hardware.gnss@1.0-impl \
	android.hardware.gnss@1.0-impl.legacy \
	android.hardware.gnss@1.0-service \
	android.hardware.gnss@1.0-service.legacy \
	android.hardware.gnss@1.1-service \
	android.hardware.gnss@2.0-service \
	android.hardware.gnss@2.0-service.ranchu \
	android.hardware.gnss@2.1-service \
	android.hardware.gnss@common-default-lib \
	android.hardware.gnss@common-vts-lib \
	android.automotive.computepipe.registry \
	android.automotive.computepipe.router@1.0 \
	android.automotive.computepipe.router@1.0-impl \
	android.automotive.computepipe.runner \
	android.automotive.evs.manager@1.0 \
	android.automotive.evs.manager@1.1 \
	android.automotive.evs.manager.fuzzlib \
	android.frameworks.automotive.display@1.0 \
	android.frameworks.automotive.display@1.0-service \
	android.hardware.automotive.audiocontrol@1.0 \
	android.hardware.automotive.audiocontrol@1.0-service \
	android.hardware.automotive.audiocontrol@2.0 \
	android.hardware.automotive.audiocontrol@2.0-service \
	android.hardware.automotive.can@1.0 \
	android.hardware.automotive.can@1.0-service \
	android.hardware.automotive.can@1.x-config-format \
	android.hardware.automotive.can@defaults \
	android.hardware.automotive.can@hidl-utils-lib \
	android.hardware.automotive.can@libcanhaltools \
	android.hardware.automotive.can@libnetdevice \
	android.hardware.automotive.can@vts-defaults \
	android.hardware.automotive.can@vts-utils-lib \
	android.hardware.automotive.evs@1.0 \
	android.hardware.automotive.evs@1.0-service \
	android.hardware.automotive.evs@1.1 \
	android.hardware.automotive.evs@1.1-sample \
	android.hardware.automotive.evs@1.1-service \
	android.hardware.automotive.evs@common-default-lib \
	android.hardware.automotive.evs@fuzz-defaults \
	android.hardware.automotive@libc++fs \
	android.hardware.automotive@libc++fsdefaults \
	android.hardware.automotive.occupant_awareness \
	android.hardware.automotive.occupant_awareness@1.0-service \
	android.hardware.automotive.occupant_awareness@1.0-service_mock \
	android.hardware.automotive.sv@1.0 \
	android.hardware.automotive.sv@1.0-service \
	android.hardware.automotive.vehicle@2.0 \
	android.hardware.automotive.vehicle@2.0-default-impl-lib \
	android.hardware.automotive.vehicle@2.0-default-impl-unit-tests \
	android.hardware.automotive.vehicle@2.0-emulated-user-hal-lib \
	android.hardware.automotive.vehicle@2.0-libproto-native \
	android.hardware.automotive.vehicle@2.0-manager-lib \
	android.hardware.automotive.vehicle@2.0-manager-unit-tests \
	android.hardware.automotive.vehicle@2.0-server-common-lib \
	android.hardware.automotive.vehicle@2.0-server-impl-lib \
	android.hardware.automotive.vehicle@2.0-service \
	android.hardware.automotive.vehicle@2.0-user-hal-helper-lib \
	android.hardware.automotive.vehicle@2.0-utils-unit-tests \
	android.hardware.audio.effect@2.0 \
	android.hardware.audio.effect@2.0-impl \
	android.hardware.audio.effect@5.0 \
	android.hardware.audio.effect@5.0-impl \
	android.hardware.audio.effect@6.0 \
	android.hardware.audio.effect@6.0-impl \
	#com.android.tethering \
	#android.hardware.audio.effect-impl_default \
	#android.hardware.audio.effect@4.0 \
	#android.hardware.audio.effect@4.0-impl \


LOCAL_UNINSTALLABLE_MODULE := true
LOCAL_CERTIFICATE := PRESIGNED
LOCAL_SRC_FILES := /dev/null
include $(BUILD_PREBUILT)
