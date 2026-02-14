#!/bin/bash

set -e

TARGET_CPU="arm64"
ROOT_DIR="$(pwd)"
ROM_REPO_DIR="$ROOT_DIR/xx"

# RBE / Siso Environment Variables
export SISO_REAPI_ADDRESS="nano.buildbuddy.io:443"
export SISO_REAPI_HEADER="x-buildbuddy-api-key=${RBE_API_KEY}"
export SISO_CREDENTIAL_HELPER="$ROOT_DIR/siso_helper.sh"

# Brave Specific Environment Variables
export PYTHONUNBUFFERED=1
export GSUTIL_ENABLE_LUCI_AUTH=0
export DEPOT_TOOLS_UPDATE=0

# Git cache path
export GIT_CACHE_PATH="$ROOT_DIR/.git_cache"
mkdir -p "$GIT_CACHE_PATH"

# Ensure depot_tools is in PATH (Brave init installs it to vendor/depot_tools)
export PATH="$ROOT_DIR/src/brave/vendor/depot_tools:$PATH"

# 1. Setup Directory Structure and Clone brave-core
mkdir -p src
git clone -q --depth=1 --branch master https://github.com/brave/brave-core.git src/brave

# 2. Install dependencies inside brave-core
cd src/brave
sudo chown -R cirrus:cirrus /usr/local/lib/python3.* /usr/local/bin || true
node -v
npm -v
npm install

# --- FIX START: Inject .gclient vars via .env ---
# The log indicates variables must be set in brave/.env using projects_chrome_custom_vars
# and formatted as a JSON object.
echo "Creating src/brave/.env to configure .gclient..."
cat <<EOF > .env
projects_chrome_custom_vars='{
  "rbe_instance": "default_instance",
  "reapi_address": "nano.buildbuddy.io:443",
  "reapi_backend_config_path": "$ROOT_DIR/buildbuddy_backend.star",
  "checkout_pgo_profiles": false
}'
EOF
# --- FIX END ---

# 3. Initialize build
echo "Running npm run init..."
# verify .env exists
ls -la .env
npm run init -- --target_os=android --target_arch=$TARGET_CPU --no-history --gclient_verbose

# 4. Setup Python path for Brave utils
export PYTHONPATH="$ROOT_DIR/src/brave/script:$ROOT_DIR/src/brave/python:$ROOT_DIR/src/brave/python/brave_chromium_utils:$PYTHONPATH"

# 5. Setup custom GN args and Build Directory
SCRIPT_DIR="$ROM_REPO_DIR/script/chromium"
CERT_DIGEST=$(keytool -export-cert -alias rov -keystore "$SCRIPT_DIR/rov.keystore" -storepass rovars | sha256sum | cut -d' ' -f1)

cd "$ROOT_DIR/src"
# Match Brave's internal naming: out/Release_android_arm64
BUILD_DIR="out/Release_android_$TARGET_CPU"
mkdir -p "$BUILD_DIR"

echo "Generating GN files for $BUILD_DIR ..."
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

echo "Starting Build with Autoninja (RBE)..."
chrt -b 0 autoninja -C "$BUILD_DIR" chrome_public_apk

# 6. Upload
[ -f "$ROM_REPO_DIR/config.zip" ] && unzip -q "$ROM_REPO_DIR/config.zip" -d ~/.config
cd "$BUILD_DIR/apks"
APKSIGNER=$(find ../../../third_party/android_sdk -name apksigner -type f | head -n 1)
$APKSIGNER sign --ks "$SCRIPT_DIR/rov.keystore" --ks-pass pass:rovars --ks-key-alias rov --in BravePublic.apk --out Brave-Clean.apk
ARCHIVE="Brave-Clean-$(date +%Y%m%d).tar.gz"
tar -czf "$ROOT_DIR/$ARCHIVE" Brave-Clean.apk
cd "$ROOT_DIR"
timeout 15m telegram-upload "$ARCHIVE" --to "$TG_CHAT_ID"