#!/bin/bash

set -e

TARGET_CPU="arm64"

# Brave Specific Environment Variables
export PYTHONUNBUFFERED=1
export GSUTIL_ENABLE_LUCI_AUTH=0
export DEPOT_TOOLS_UPDATE=0

export SISO_REAPI_ADDRESS="nano.buildbuddy.io:443"
export SISO_REAPI_HEADER="x-buildbuddy-api-key=${RBE_API_KEY}"
export SISO_CREDENTIAL_HELPER="$(pwd)/siso_helper.sh"

# 1. Setup .gclient based on Brave Wiki
cat <<EOF > .gclient
solutions = [
  {
    "name": "src",
    "managed": False, 
    "url": "https://github.com/brave/chromium",
    "custom_deps": {
      "src/testing/libfuzzer/fuzzers/wasm_corpus": None, 
      "src/third_party/chromium-variations": None
    },
    "custom_vars": {
      "checkout_pgo_profiles": False,
      "rbe_instance": "default_instance",
      "reapi_address": "nano.buildbuddy.io:443",
      "reapi_backend_config_path": "$(pwd)/buildbuddy_backend.star",
    }
  },
  {
    "name": "src/brave",
    "managed": False, 
    "url": "https://github.com/brave/brave-core.git"
  }
]
target_os = ["android"]
target_cpu = ["$TARGET_CPU"]
EOF

# 2. Sync Source
echo "Starting gclient sync..."
# Note: You can specify revisions here if needed, e.g., --revision src@VERSION
gclient sync --nohooks --no-history -j 8

# 3. Setup Python path and Apply Patches
# Important: Brave build requires patches to be applied manually if not using npm
export PYTHONPATH="$(pwd)/src/brave/script:$(pwd)/src/brave/python/brave_chromium_utils:$PYTHONPATH"

echo "Applying Brave patches..."
python3 src/brave/script/apply-patches.py

echo "Running gclient runhooks..."
gclient runhooks

# 4. Build
cd src
SCRIPT_DIR="$(pwd)/../../xx/script/chromium"
CERT_DIGEST=$(keytool -export-cert -alias rov -keystore "$SCRIPT_DIR/rov.keystore" -storepass rovars | sha256sum | cut -d' ' -f1)

mkdir -p out/Release
cat <<EOF > out/Release/args.gn
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

echo "Generating Ninja files..."
gn gen out/Release
echo "Starting Build..."
chrt -b 0 autoninja -C out/Release chrome_public_apk

# 5. Upload
[ -f "../../xx/config.zip" ] && unzip -q "../../xx/config.zip" -d ~/.config
cd out/Release/apks
APKSIGNER=$(find ../../../third_party/android_sdk -name apksigner -type f | head -n 1)
$APKSIGNER sign --ks "$SCRIPT_DIR/rov.keystore" --ks-pass pass:rovars --ks-key-alias rov --in BravePublic.apk --out Brave-Clean.apk
ARCHIVE="Brave-Clean-$(date +%Y%m%d).tar.gz"
tar -czf "../../../../../$ARCHIVE" Brave-Clean.apk
cd ../../../../../
timeout 15m telegram-upload "$ARCHIVE" --to "$TG_CHAT_ID"
