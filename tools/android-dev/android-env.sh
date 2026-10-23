#!/usr/bin/env bash
# Source this file in the Codespace before invoking Android tools.
export OTC_ANDROID_CACHE_ROOT="${OTC_ANDROID_CACHE_ROOT:-/workspaces/.otc-android}"
export OTC_ANDROID_REPO="${OTC_ANDROID_REPO:-/workspaces/otclientpoke}"
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export ANDROID_HOME="$OTC_ANDROID_CACHE_ROOT/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/29.0.13599879"
export VCPKG_ROOT="$OTC_ANDROID_CACHE_ROOT/vcpkg"
export VCPKG_DEFAULT_BINARY_CACHE="$OTC_ANDROID_CACHE_ROOT/vcpkg-binary"
export VCPKG_BINARY_SOURCES="clear;files,$VCPKG_DEFAULT_BINARY_CACHE,readwrite"
export GRADLE_USER_HOME="$OTC_ANDROID_CACHE_ROOT/gradle"
export OTCLIENT_ANDROID_ABIS="${OTCLIENT_ANDROID_ABIS:-armeabi-v7a}"
export OTCLIENT_USE_CCACHE=true
export CCACHE_DIR="$OTC_ANDROID_CACHE_ROOT/ccache"
export CCACHE_BASEDIR="$OTC_ANDROID_REPO"
export CCACHE_COMPILERCHECK=content
# Required for Clang PCH caching; iteration builds are identified by commit, not time macros.
export CCACHE_SLOPPINESS=pch_defines,time_macros
export CCACHE_MAXSIZE=1G
export OTCLIENT_DEBUG_KEYSTORE="$OTC_ANDROID_CACHE_ROOT/signing/debug.keystore"
export CMAKE_BUILD_PARALLEL_LEVEL=4
export VCPKG_MAX_CONCURRENCY=4
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
