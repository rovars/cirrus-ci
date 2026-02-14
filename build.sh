#!/bin/bash

set -e

TARGET_CPU="arm64"

export SISO_REAPI_ADDRESS="nano.buildbuddy.io:443"
export SISO_REAPI_HEADER="x-buildbuddy-api-key=${RBE_API_KEY}"
export SISO_CREDENTIAL_HELPER="$(pwd)/siso_helper.sh"

# 1. Get Brave Browser wrapper
git clone -q --depth=1 https://github.com/brave/brave-browser.git
cd brave-browser

# 2. Install dependencies and Init
sudo chown -R cirrus:cirrus /usr/local/lib/python3.* /usr/local/bin || true
node -v
npm -v
npm install

# npm run init handles .gclient creation, gclient sync, and patching
npm run init -- --target_os=android --target_arch=$TARGET_CPU

# 3. Setup custom GN args and generate Ninja files
# We use 'npm run build' to prepare the environment and GN args
# Passing custom GN args via environment or arguments if supported, 
# or we can modify the generated args.gn afterwards.

# Get the cert digest for the keystore
SCRIPT_DIR="$(pwd)/../../xx/script/chromium"
CERT_DIGEST=$(keytool -export-cert -alias rov -keystore "$SCRIPT_DIR/rov.keystore" -storepass rovars | sha256sum | cut -d' ' -f1)

# Run build prep
# Static build for Android with RBE enabled
npm run build -- --target_os=android --target_arch=$TARGET_CPU Static

# 4. Inject our custom RBE/Siso args into the generated args.gn
cd src
BUILD_DIR="out/Static_Android"
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

echo "Regenerating GN with custom args..."
gn gen "$BUILD_DIR"

echo "Starting Build..."
chrt -b 0 autoninja -C "$BUILD_DIR" chrome_public_apk

# 5. Upload
[ -f "../../xx/config.zip" ] && unzip -q "../../xx/config.zip" -d ~/.config
cd "$BUILD_DIR/apks"
APKSIGNER=$(find ../../../third_party/android_sdk -name apksigner -type f | head -n 1)
$APKSIGNER sign --ks "$SCRIPT_DIR/rov.keystore" --ks-pass pass:rovars --ks-key-alias rov --in BravePublic.apk --out Brave-Clean.apk
ARCHIVE="Brave-Clean-$(date +%Y%m%d).tar.gz"
tar -czf "../../../../../$ARCHIVE" Brave-Clean.apk
cd ../../../../../
timeout 15m telegram-upload "$ARCHIVE" --to "$TG_CHAT_ID"
