#!/bin/bash

set -e

sudo apt-get -qq update > /dev/null 2>&1
sudo apt-get -qq install -y git python-is-python3 curl lsb-release sudo file wget tar unzip > /dev/null 2>&1

ROOT_DIR="$(pwd)"
ROM_REPO_DIR="$ROOT_DIR/rom"

envsubst < $ROOT_DIR/siso_helper.sh >> $ROOT_DIR/siso_helper_env.sh

export SISO_REAPI_ADDRESS="nano.buildbuddy.io:443"
export SISO_REAPI_HEADER="x-buildbuddy-api-key=${RBE_API_KEY}"
export SISO_CREDENTIAL_HELPER="$ROOT_DIR/siso_helper_env.sh"

export DEPOT_TOOLS_UPDATE=1

export BRAVE_IPFS_ENABLED=false
export BRAVE_REWARDS_ENABLED=false
export BRAVE_WALLET_ENABLED=false
export BRAVE_TOR_ENABLED=false
export BRAVE_SPEEDREADER_ENABLED=false
export BRAVE_ADS_ENABLED=false
export BRAVE_VPN_ENABLED=false

export USE_REMOTEEXEC=true
export USE_SISO=true
export SYMBOL_LEVEL=0

mkdir -p src
git clone -q https://github.com/brave/brave-core.git src/brave
export PATH="$ROOT_DIR/src/brave/vendor/depot_tools:$PATH"

cd src/brave
sudo chown -R $(whoami):$(whoami) /usr/local/lib/python3.* /usr/local/bin || true
npm install

cat <<EOF > .env
projects_chrome_custom_vars='{
  "rbe_instance": "nano.buildbuddy.io",
  "reapi_address": "nano.buildbuddy.io:443",
  "reapi_backend_config_path": "$ROOT_DIR/src/brave/build/config/siso/brave_siso_config.star"
}'
EOF

npm run init -- --target_os=android --target_arch=arm --no-history

sudo "$ROOT_DIR/src/build/install-build-deps.sh" --android --no-prompt > /dev/null 2>&1

export RBE_exec_strategy=remote
npm run build -- --target_os=android --target_arch=arm

BUILD_DIR="../out/Release_android"

cd "$BUILD_DIR/apks"
APKSIGNER=$(find "$ROOT_DIR/src/third_party/android_sdk" -name apksigner -type f | head -n 1)

FINAL_APK="BravePublic.apk"
SCRIPT_DIR="$ROM_REPO_DIR/script/chromium"

if [ -f "$SCRIPT_DIR/rov.keystore" ]; then
    "$APKSIGNER" sign --ks "$SCRIPT_DIR/rov.keystore" --ks-pass pass:rovars --ks-key-alias rov --in BravePublic.apk --out Brave-Clean.apk
    FINAL_APK="Brave-Clean.apk"
fi

ARCHIVE="Brave-Clean-$(date +%Y%m%d).tar.gz"
tar -czf "$ROOT_DIR/$ARCHIVE" "$FINAL_APK"

cd "$ROOT_DIR"
timeout 15m telegram-upload "$ARCHIVE" --to "$TG_CHAT_ID" || echo "Upload failed"