#!/bin/bash
set -ex

sudo apt-get -qq update > /dev/null 2>&1
sudo apt-get -qq install -y git python-is-python3 curl pkg-config > /dev/null 2>&1

ROOT_DIR="$(pwd)"
ROM_REPO_DIR="$ROOT_DIR/rom"

mkdir -p src
git clone -q https://github.com/brave/brave-core.git src/brave
cd src/brave

sudo chown -R $(whoami):$(whoami) /usr/local/lib/python3.* /usr/local/bin || true

npm install

cat > "$ROOT_DIR/siso_helper.sh" << 'EOF'
#!/bin/bash
cat << HELPER
{
  "headers": {
    "x-buildbuddy-api-key": ["${RBE_API_KEY}"]
  },
  "token": "dummy"
}
HELPER
EOF
chmod +x "$ROOT_DIR/siso_helper.sh"

if [ -z "$RBE_API_KEY" ]; then
  echo "ERROR: RBE_API_KEY not set"
  exit 1
fi

export SISO_REAPI_ADDRESS="nano.buildbuddy.io:443"
export SISO_CREDENTIAL_HELPER="$ROOT_DIR/siso_helper.sh"
export SISO_CACHE_DIR="/tmp/siso-cache"
export DEPOT_TOOLS_UPDATE=1

mkdir -p "$SISO_CACHE_DIR"

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
brave_services_key=
brave_variations_server_url=https://variations.brave.com
updater_dev_endpoint=https://updates.bravesoftware.com
is_official_build=false
allow_unset_env_config_flags=true
EOF

echo "Running npm run init..."
npm run init -- --target_os=android --target_arch=arm --no-history

echo "Installing build deps..."
sudo "$ROOT_DIR/src/build/install-build-deps.sh" --android --no-prompt > /dev/null 2>&1

echo "Starting build..."
npm run build -- --target_os=android --target_arch=arm Release

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