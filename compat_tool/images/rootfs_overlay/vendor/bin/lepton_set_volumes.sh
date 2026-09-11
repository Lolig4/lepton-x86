#!/system/bin/sh

# Initialize audio output to max loudness, e.g. 15
# NOTE: These constants come from the AudioSystem AIDL and headers
setStreamVolume="10"
STREAM_MUSIC="3"
service call audio "${setStreamVolume}" i32 "${STREAM_MUSIC}" i32 15