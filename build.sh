#!/bin/bash

set -e

TARGET_CPU="arm64"

export SISO_REAPI_ADDRESS="nano.buildbuddy.io:443"
export SISO_REAPI_HEADER="x-buildbuddy-api-key=${RBE_API_KEY}"
export SISO_CREDENTIAL_HELPER="$(pwd)/siso_helper.sh"
export PATH="$(pwd)/depot_tools:$(pwd)/brave-browser/src/third_party/depot_tools:$PATH"

# 1. Sync
git clone -q https://chromium.googlesource.com/chromium/tools/depot_tools.git
./depot_tools/update_depot_tools

git clone -q --depth=1 https://github.com/brave/brave-browser.git
cd brave-browser

cat <<EOF > .gclient
solutions = [
  {
    "name": "src",
    "url": "https://github.com/brave/chromium.git",
    "managed": False,
    "custom_vars": {
      "rbe_instance": "default_instance",
      "reapi_address": "nano.buildbuddy.io:443",
      "reapi_backend_config_path": "$(pwd)/../buildbuddy_backend.star",
    },
  },
]
target_os = ["android"]
EOF

sudo chown -R cirrus:cirrus /usr/local/lib/python3.12/dist-packages /usr/local/bin || true
npm install
gclient sync --nohooks --no-history -j 8

# 2. Hooks
gclient runhooks

# 3. Build
SCRIPT_DIR="$(pwd)/../xx/script/chromium"
cd src
CERT_DIGEST=$(keytool -export-cert -alias rov -keystore "../../$SCRIPT_DIR/rov.keystore" -storepass rovars | sha256sum | cut -d' ' -f1)

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

gn gen out/Release
chrt -b 0 autoninja -C out/Release chrome_public_apk

# 4. Upload
[ -f "../../xx/config.zip" ] && unzip -q "../../xx/config.zip" -d ~/.config
cd out/Release/apks
APKSIGNER=$(find ../../../third_party/android_sdk -name apksigner -type f | head -n 1)
$APKSIGNER sign --ks ../../../../../$SCRIPT_DIR/rov.keystore --ks-pass pass:rovars --ks-key-alias rov --in BravePublic.apk --out Brave-Clean.apk
ARCHIVE="Brave-Clean-$(date +%Y%m%d).tar.gz"
tar -czf "../../../../../$ARCHIVE" Brave-Clean.apk
cd ../../../../../
timeout 15m telegram-upload "$ARCHIVE" --to "$TG_CHAT_ID"
