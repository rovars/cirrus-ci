#!/bin/bash

set -e

TARGET_CPU="arm64"
ROOT_DIR="$(pwd)"
ROM_REPO_DIR="$ROOT_DIR/xx"

export SISO_REAPI_ADDRESS="nano.buildbuddy.io:443"
export SISO_REAPI_HEADER="x-buildbuddy-api-key=${RBE_API_KEY}"
export SISO_CREDENTIAL_HELPER="$ROOT_DIR/siso_helper.sh"

# 1. Setup Directory Structure and Clone brave-core
mkdir -p src
git clone -q --depth=1 https://github.com/brave/brave-core.git src/brave

# 2. Install dependencies inside brave-core
cd src/brave
sudo chown -R cirrus:cirrus /usr/local/lib/python3.* /usr/local/bin || true
node -v
npm -v
npm install

# 3. Initialize build (This downloads Chromium and applies patches)
echo "Running npm run init..."
npm run init -- --target_os=android --target_arch=$TARGET_CPU --no-history -j 8

# 4. Setup custom GN args
SCRIPT_DIR="$ROM_REPO_DIR/script/chromium"
CERT_DIGEST=$(keytool -export-cert -alias rov -keystore "$SCRIPT_DIR/rov.keystore" -storepass rovars | sha256sum | cut -d' ' -f1)

cd "$ROOT_DIR/src"
BUILD_DIR="out/Release"
mkdir -p "$BUILD_DIR"

cat <<EOF > "$BUILD_DIR/args.gn"
import("//brave/build/config/android.gni")
target_os = "android"
target_cpu = "$TARGET_CPU"
trichrome_certdigest = "$CERT_DIGEST"
symbol_level = 0
is_debug = false
is_official_build = false
use_remoteexec = true
use_siso = true
is_clang = true
treat_warnings_as_errors = false
enable_brave_rewards = false
enable_brave_wallet = false
enable_brave_vpn = false
enable_brave_news = false
enable_ai_chat = false
enable_brave_talk = false
enable_brave_ads = false
enable_brave_wayback_machine = false
EOF

echo "Regenerating GN with custom args for RBE..."
gn gen "$BUILD_DIR"

echo "Starting Build with Autoninja (RBE)..."
chrt -b 0 autoninja -C "$BUILD_DIR" chrome_public_apk

# 5. Upload
[ -f "$ROM_REPO_DIR/config.zip" ] && unzip -q "$ROM_REPO_DIR/config.zip" -d ~/.config
cd "$BUILD_DIR/apks"
APKSIGNER=$(find ../../../third_party/android_sdk -name apksigner -type f | head -n 1)
$APKSIGNER sign --ks "$SCRIPT_DIR/rov.keystore" --ks-pass pass:rovars --ks-key-alias rov --in BravePublic.apk --out Brave-Clean.apk
ARCHIVE="Brave-Clean-$(date +%Y%m%d).tar.gz"
tar -czf "$ROOT_DIR/$ARCHIVE" Brave-Clean.apk
cd "$ROOT_DIR"
timeout 15m telegram-upload "$ARCHIVE" --to "$TG_CHAT_ID"
