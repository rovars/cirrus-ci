#!/bin/bash

set -e

TARGET_CPU="arm64"

export SISO_REAPI_ADDRESS="nano.buildbuddy.io:443"
export SISO_REAPI_HEADER="x-buildbuddy-api-key=${RBE_API_KEY}"
export SISO_CREDENTIAL_HELPER="$(pwd)/siso_helper.sh"

# 1. Setup .gclient in the root (where brave-browser will be cloned)
cat <<EOF > .gclient
solutions = [
  {
    "name": "src/brave",
    "url": "https://github.com/brave/brave-core.git",
    "managed": False,
  },
  {
    "name": "src",
    "url": "https://github.com/brave/chromium.git",
    "managed": False,
    "custom_vars": {
      "rbe_instance": "default_instance",
      "reapi_address": "nano.buildbuddy.io:443",
      "reapi_backend_config_path": "$(pwd)/buildbuddy_backend.star",
    },
  },
]
target_os = ["android"]
EOF

# 2. Get Brave Browser wrapper
git clone -q --depth=1 https://github.com/brave/brave-browser.git
cd brave-browser

# 3. Sync and Init using Brave's recommended way
sudo chown -R cirrus:cirrus /usr/local/lib/python3.* /usr/local/bin || true
node -v
npm -v
npm install

# Run init to setup the environment properly (this handles hooks and utils)
npm run init

# Sync dependencies
gclient sync --nohooks --no-history -j 8

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

gn gen out/Release
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
