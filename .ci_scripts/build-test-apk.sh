#!/bin/bash

export ANDROID_NDK=/opt/android/ndk/25.2.9519653
export ANDROID_HOME=/opt/android
export JAVA_HOME="$(compgen -G "/usr/lib/jvm/java-17-openjdk")"

sudo mkdir -p /opt/android
sudo chown $(id -u):$(id -g) -R /opt

pushd tests/test-apk
./gradlew assembleDebug

cp app/build/outputs/apk/debug/app-debug.apk ../test-apk.apk

touch app/src/main/java/com/example/neon42/MainActivity.kt

./gradlew assembleDebug
cp app/build/outputs/apk/debug/app-debug.apk ../test-apk2.apk

sed -i "s/compileSdk.*/compileSdk 34/g" app/build.gradle
sed -i "s/minSdk.*/minSdk 37/g" app/build.gradle
sed -i "s/targetSdk.*/targetSdk 37/g" app/build.gradle

./gradlew assembleDebug
cp app/build/outputs/apk/debug/app-debug.apk ../test-apk3.apk

if [[ "$(sha256sum ../test-apk.apk)" == "$(sha256sum ../test-apk2.apk)" ]]; then
    exit 1
fi

popd

pushd tests/android-vulkan-tutorials/tutorial05_triangle

export ANDROID_SDK_ROOT="$(pwd)/Android/Sdk"
export ANDROID_HOME="${ANDROID_SDK_ROOT}"

CMDLINE_TOOLS_VERSION="13114758"
CMDLINE_TOOLS_ZIP="commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip"
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/${CMDLINE_TOOLS_ZIP}"

curl -O "$CMDLINE_TOOLS_URL"

mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools/latest"

bsdtar -xf "$CMDLINE_TOOLS_ZIP" --strip-components 1 -C "$ANDROID_SDK_ROOT/cmdline-tools/latest"

SDKMANAGER="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"

yes | "$SDKMANAGER" \
        "cmake;3.18.1"

sed -i "s/'armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64'/'arm64-v8a'/" app/build.gradle
JAVA_HOME="$(compgen -G "/usr/lib/jvm/java-11-openjdk")" ./gradlew assembleDebug
cp app/build/outputs/apk/debug/app-debug.apk ../../test-vulkan.apk
popd

