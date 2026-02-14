#!/bin/bash

set -e

sudo apt-get -qq update
sudo apt-get -qq install -y git python-is-python3 curl lsb-release sudo file wget tar unzip

TARGET_CPU="${1:-arm64}"
ROOT_DIR="$(pwd)"
ROM_REPO_DIR="$ROOT_DIR/rom"

export SISO_REAPI_ADDRESS="nano.buildbuddy.io:443"
export SISO_REAPI_HEADER="x-buildbuddy-api-key=${RBE_API_KEY}"
export SISO_CREDENTIAL_HELPER="$ROOT_DIR/siso_helper.sh"

export PYTHONUNBUFFERED=1
export GSUTIL_ENABLE_LUCI_AUTH=0
export DEPOT_TOOLS_UPDATE=1

mkdir -p src
if [ ! -d "src/brave" ]; then
    git clone -q --depth=1 https://github.com/brave/brave-core.git src/brave
else
    echo "brave-core repository already exists."
fi

export PATH="$ROOT_DIR/src/brave/vendor/depot_tools:$PATH"

cd src/brave
sudo chown -R cirrus:cirrus /usr/local/lib/python3.* /usr/local/bin || true
npm install

cat <<EOF > .env
projects_chrome_custom_vars='{
  "rbe_instance": "default_instance",
  "reapi_address": "nano.buildbuddy.io:443",
  "reapi_backend_config_path": "$ROOT_DIR/buildbuddy_backend.star",
  "checkout_pgo_profiles": false
}'
EOF

echo "Initializing Brave build environment for Android ($TARGET_CPU)..."
npm run init -- --target_os=android --target_arch=$TARGET_CPU --no-history

echo "Installing Android build dependencies..."
sudo "$ROOT_DIR/src/build/install-build-deps.sh" --android --no-prompt

BUILD_DIR="out/Release_android_$TARGET_CPU"
mkdir -p "$BUILD_DIR"
echo 'is_brave_origin_branded = true' > "$BUILD_DIR/args.gn"

echo "Starting Brave compilation for $TARGET_CPU..."
chrt -b 0 autoninja -C "$BUILD_DIR" chrome_public_apk

[ -f "$ROM_REPO_DIR/config.zip" ] && unzip -q "$ROM_REPO_DIR/config.zip" -d ~/.config

cd "$BUILD_DIR/apks"
APKSIGNER=$(find "$ROOT_DIR/src/third_party/android_sdk" -name apksigner -type f | head -n 1)

FINAL_APK="BravePublic.apk"
SCRIPT_DIR="$ROM_REPO_DIR/script/chromium"
if [ -f "$SCRIPT_DIR/rov.keystore" ]; then
    echo "Signing BravePublic.apk with rov.keystore..."
    "$APKSIGNER" sign --ks "$SCRIPT_DIR/rov.keystore" --ks-pass pass:rovars --ks-key-alias rov --in BravePublic.apk --out Brave-Clean.apk
    FINAL_APK="Brave-Clean.apk"
else
    echo "Keystore not found ($SCRIPT_DIR/rov.keystore). Skipping APK signing."
fi

ARCHIVE="Brave-Clean-$(date +%Y%m%d).tar.gz"
echo "Creating archive: $ARCHIVE"
tar -czf "$ROOT_DIR/$ARCHIVE" "$FINAL_APK"

cd "$ROOT_DIR"
echo "Uploading $ARCHIVE to Telegram..."
timeout 15m telegram-upload "$ARCHIVE" --to "$TG_CHAT_ID" || echo "Upload failed"