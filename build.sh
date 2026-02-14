#!/bin/bash

set -e

echo "Installing system prerequisites..."
sudo apt-get -qq update
sudo apt-get -qq install -y git python-is-python3 curl lsb-release sudo file wget tar

TARGET_CPU="arm64"
ROOT_DIR="$(pwd)"
ROM_REPO_DIR="$ROOT_DIR/xx"

export SISO_REAPI_ADDRESS="nano.buildbuddy.io:443"
export SISO_REAPI_HEADER="x-buildbuddy-api-key=${RBE_API_KEY}"
export SISO_CREDENTIAL_HELPER="$ROOT_DIR/siso_helper.sh"

export PYTHONUNBUFFERED=1
export GSUTIL_ENABLE_LUCI_AUTH=0
export DEPOT_TOOLS_UPDATE=1

export PATH="$ROOT_DIR/src/brave/vendor/depot_tools:$PATH"

mkdir -p src
git clone -q --depth=1 https://github.com/brave/brave-core.git src/brave

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

npm run init -- --target_os=android --target_arch=$TARGET_CPU --no-history --delete_unused_deps

sudo ./src/build/install-build-deps.sh --android --no-prompt

SCRIPT_DIR="$ROM_REPO_DIR/script/chromium"
if [ -f "$SCRIPT_DIR/rov.keystore" ]; then
    CERT_DIGEST=$(keytool -export-cert -alias rov -keystore "$SCRIPT_DIR/rov.keystore" -storepass rovars | sha256sum | cut -d' ' -f1)
else
    CERT_DIGEST="000000" 
fi

cd "$ROOT_DIR/src"
BUILD_DIR="out/Release_android_$TARGET_CPU"
mkdir -p "$BUILD_DIR"

gn gen "$BUILD_DIR" --args="
  import(\"//brave/build/config/android.gni\")
  target_os = \"android\"
  target_cpu = \"$TARGET_CPU\"
  trichrome_certdigest = \"$CERT_DIGEST\"
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
"

chrt -b 0 autoninja -C "$BUILD_DIR" chrome_public_apk

[ -f "$ROM_REPO_DIR/config.zip" ] && unzip -q "$ROM_REPO_DIR/config.zip" -d ~/.config

cd "$BUILD_DIR/apks"
APKSIGNER=$(find ../../../third_party/android_sdk -name apksigner -type f | head -n 1)

if [ -f "$SCRIPT_DIR/rov.keystore" ]; then
    $APKSIGNER sign --ks "$SCRIPT_DIR/rov.keystore" --ks-pass pass:rovars --ks-key-alias rov --in BravePublic.apk --out Brave-Clean.apk
    FINAL_APK="Brave-Clean.apk"
else
    FINAL_APK="BravePublic.apk"
fi

ARCHIVE="Brave-Clean-$(date +%Y%m%d).tar.gz"
tar -czf "$ROOT_DIR/$ARCHIVE" "$FINAL_APK"

cd "$ROOT_DIR"
timeout 15m telegram-upload "$ARCHIVE" --to "$TG_CHAT_ID"