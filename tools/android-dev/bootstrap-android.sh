#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/android-env.sh"
mkdir -p "$OTC_ANDROID_CACHE_ROOT/logs" "$GRADLE_USER_HOME" "$VCPKG_DEFAULT_BINARY_CACHE" "$CCACHE_DIR"
if [[ "$SCRIPT_DIR" != "$OTC_ANDROID_CACHE_ROOT/scripts" ]]; then
  mkdir -p "$OTC_ANDROID_CACHE_ROOT/scripts"
  cp "$SCRIPT_DIR/"*.sh "$OTC_ANDROID_CACHE_ROOT/scripts/"
fi

echo '[1/5] Installing Linux build tools and Java 17'
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
  openjdk-17-jdk-headless build-essential ccache curl ca-certificates \
  gcc-multilib g++-multilib git make ninja-build pkg-config python3 unzip zip \
  autoconf autoconf-archive automake libtool libltdl-dev bison flex gperf nasm \
  > "$OTC_ANDROID_CACHE_ROOT/logs/apt-install.log" 2>&1

echo '[2/5] Installing Android command line tools'
if [[ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]]; then
  archive="$OTC_ANDROID_CACHE_ROOT/commandlinetools.zip"
  staging="$(mktemp -d "$OTC_ANDROID_CACHE_ROOT/cmdline-stage.XXXXXX")"
  curl --fail --location --retry 3 --silent --show-error \
    https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip \
    --output "$archive"
  unzip -q "$archive" -d "$staging"
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  mv "$staging/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
  rmdir "$staging"
  rm -f -- "$archive"
fi

echo '[3/5] Installing pinned SDK, NDK and CMake'
set +o pipefail
yes | sdkmanager --sdk_root="$ANDROID_HOME" --licenses \
  > "$OTC_ANDROID_CACHE_ROOT/logs/sdk-licenses.log" 2>&1
sdk_status=${PIPESTATUS[1]}
set -o pipefail
if [[ "$sdk_status" != 0 ]]; then
  cat "$OTC_ANDROID_CACHE_ROOT/logs/sdk-licenses.log"
  exit "$sdk_status"
fi
sdkmanager --sdk_root="$ANDROID_HOME" \
  platform-tools 'platforms;android-36' 'build-tools;36.0.0' \
  'ndk;29.0.13599879' 'cmake;3.22.1' \
  > "$OTC_ANDROID_CACHE_ROOT/logs/sdk-install.log" 2>&1

echo '[4/5] Preparing vcpkg at the repository baseline'
baseline="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["builtin-baseline"])' "$OTC_ANDROID_REPO/vcpkg.json")"
if [[ ! -d "$VCPKG_ROOT/.git" ]]; then
  git clone --filter=blob:none --no-checkout https://github.com/microsoft/vcpkg.git "$VCPKG_ROOT" \
    > "$OTC_ANDROID_CACHE_ROOT/logs/vcpkg-clone.log" 2>&1
fi
git -C "$VCPKG_ROOT" fetch --depth 1 origin "$baseline" \
  > "$OTC_ANDROID_CACHE_ROOT/logs/vcpkg-fetch.log" 2>&1
git -C "$VCPKG_ROOT" checkout --detach "$baseline" \
  > "$OTC_ANDROID_CACHE_ROOT/logs/vcpkg-checkout.log" 2>&1
"$VCPKG_ROOT/bootstrap-vcpkg.sh" -disableMetrics \
  > "$OTC_ANDROID_CACHE_ROOT/logs/vcpkg-bootstrap.log" 2>&1

echo '[5/5] Configuring persistent caches and the debug signing key'
cat > "$GRADLE_USER_HOME/gradle.properties" <<'GRADLE'
org.gradle.daemon=true
org.gradle.caching=true
org.gradle.workers.max=4
org.gradle.jvmargs=-Xmx3072m -Dfile.encoding=UTF-8
GRADLE
ccache --max-size=1G
mkdir -p "$OTC_ANDROID_CACHE_ROOT/signing" "$HOME/.android"
signing_key="$OTC_ANDROID_CACHE_ROOT/signing/debug.keystore"
if [[ ! -f "$signing_key" && -n "${OTCLIENT_DEBUG_KEYSTORE_BASE64:-}" ]]; then
  printf '%s' "$OTCLIENT_DEBUG_KEYSTORE_BASE64" | tr -d '\r\n' | base64 --decode > "$signing_key"
  chmod 600 "$signing_key"
fi
if [[ ! -f "$signing_key" ]]; then
  if [[ -f "$HOME/.android/debug.keystore" ]]; then
    cp "$HOME/.android/debug.keystore" "$signing_key"
  else
    keytool -genkeypair -keystore "$signing_key" -storepass android \
      -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 \
      -validity 10000 -dname 'CN=Android Debug,O=Android,C=US' \
      > "$OTC_ANDROID_CACHE_ROOT/logs/debug-key.log" 2>&1
  fi
  chmod 600 "$signing_key"
fi
if [[ ! -e "$HOME/.android/debug.keystore" && ! -L "$HOME/.android/debug.keystore" ]]; then
  ln -s "$signing_key" "$HOME/.android/debug.keystore"
fi
if ! grep -Fq '/workspaces/.otc-android/scripts/android-env.sh' "$HOME/.bashrc"; then
  printf '\n# OTClient Android build environment\nsource /workspaces/.otc-android/scripts/android-env.sh\n' >> "$HOME/.bashrc"
fi
printf '\nSetup complete. Build with:\n  bash %s/build-android.sh\n' "$SCRIPT_DIR"
df -h /workspaces
