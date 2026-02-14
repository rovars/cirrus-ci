#!/bin/bash
set -e

sudo apt-get -qq update > /dev/null 2>&1
sudo apt-get -qq install -y git python-is-python3 curl > /dev/null 2>&1
sudo chown -R $(whoami):$(whoami) /usr/local/lib/python3.* /usr/local/bin || true

ROOT_DIR="$(pwd)"
ROM_REPO_DIR="$ROOT_DIR/rov"

git clone -q https://github.com/brave/brave-core chr/src/brave
cd chr/src/brave

npm install

cat > .env << 'EOF'
rbe_service=nano.buildbuddy.io:443
use_siso=true
use_remoteexec=true
siso_cache_dir=/tmp/siso-cache
enable_ipfs=false
enable_brave_rewards=false
enable_brave_wallet=false
enable_tor=false
enable_speedreader=false
enable_brave_ads=false
enable_brave_vpn=false
EOF

export REAPI_AUTH_TOKEN="$RBE_API_KEY"
export SISO_CACHE_DIR="/tmp/siso-cache"
mkdir -p "$SISO_CACHE_DIR"

npm run init -- --target_os=android --target_arch=arm --no-history

sudo "$ROOT_DIR/src/build/install-build-deps.sh" --android --no-prompt > /dev/null 2>&1

npm run build -- --target_os=android --target_arch=arm Release

BUILD_DIR="../../out/Release_android"

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