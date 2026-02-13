#!/bin/bash

set -e

git clone -q https://rovars:${GITHUB_TOKEN}@github.com/rovars/rom xx
SCRIPT_DIR="$(pwd)/xx/script/chromium"
BRAVE_TAG="v1.87.186"
TARGET_CPU="arm64"
KEYSTORE_PASS=${1:-"rovars"}

export GCLIENT_SUPPRESS_GIT_VERSION_WARNING=1
export SISO_REAPI_ADDRESS="nano.buildbuddy.io:443"
export SISO_REAPI_INSTANCE="default_instance"
export SISO_REAPI_HEADER="x-buildbuddy-api-key=${RBE_API_KEY}"
export SISO_PROFILER=1
export SISO_CREDENTIAL_HELPER="$(pwd)/siso_helper.sh"
export CHROME_HEADLESS=1

git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
export PATH="$(pwd)/depot_tools:$PATH"
export DEPOT_TOOLS_UPDATE=1
cd depot_tools && ./update_depot_tools && cd ..

git clone --depth=1 --branch "$BRAVE_TAG" https://github.com/brave/brave-browser.git
cd brave-browser

# Fix Python permissions for Brave sync
sudo chown -R cirrus:cirrus /usr/local/lib/python3.10/dist-packages || true
sudo chown -R cirrus:cirrus /usr/local/bin || true

npm cache clean --force > /dev/null 2>&1 || true
npm install
npm run init -- --target_os=android --target_arch=$TARGET_CPU

cat <<EOF > .gclient
solutions = [
  {
    "name": "src",
    "url": "https://chromium.googlesource.com/chromium/src.git",
    "managed": False,
    "custom_deps": {},
    "custom_vars": {
      "rbe_instance": "default_instance",
      "reapi_address": "nano.buildbuddy.io:443",
      "reapi_instance": "default_instance",
      "reapi_backend_config_path": "$(pwd)/buildbuddy_backend.star",
    },
  },
]
target_os = ["android"]
EOF

npm run sync -- --target_os=android

export PATH="$PATH:$(pwd)/src/third_party/depot_tools"
./src/third_party/depot_tools/gclient runhooks

cp "$SCRIPT_DIR/rov.keystore" .
CERT_DIGEST=$(keytool -export-cert -alias rov -keystore rov.keystore -storepass "$KEYSTORE_PASS" | sha256sum | cut -d' ' -f1)

mkdir -p src/out/Release
cat <<EOF > src/out/Release/args.gn
import("//brave/build/config/android.gni")
target_os = "android"
target_cpu = "$TARGET_CPU"
trichrome_certdigest = "$CERT_DIGEST"
symbol_level = 0
blink_symbol_level = 0
v8_symbol_level = 0
is_component_build = false
use_remoteexec = true
use_siso = true
is_official_build = false
is_debug = false
android_static_analysis = "off"
is_clang = true
treat_warnings_as_errors = false
enable_brave_rewards = false
enable_brave_wallet = false
enable_brave_vpn = false
enable_brave_news = false
enable_brave_ads = false
enable_ai_chat = false
enable_brave_talk = false
enable_brave_wayback_machine = false
brave_stats_updater_url = ""
brave_variations_server_url = ""
brave_p3a_enabled = false
enable_ipfs = false
enable_tor = false
enable_speedreader = false
EOF

cd src
gn gen out/Release
chrt -b 0 autoninja -C out/Release chrome_public_apk

APKSIGNER=$(find third_party/android_sdk/public/build-tools -name apksigner -type f | head -n 1)
mkdir -p out/Release/apks/signed
INPUT_APK="out/Release/apks/BravePublic.apk"
OUTPUT_APK="out/Release/apks/signed/Brave-Clean.apk"

if [ -f "$INPUT_APK" ]; then
    $APKSIGNER sign --ks ../rov.keystore --ks-pass pass:"$KEYSTORE_PASS" --ks-key-alias rov --in "$INPUT_APK" --out "$OUTPUT_APK"
fi

cd ../..
ARCHIVE_FILE="Brave-Clean-${BRAVE_TAG}-${TARGET_CPU}-$(date +%Y%m%d).tar.gz"
tar -czf "$ARCHIVE_FILE" -C brave-browser/src/out/Release/apks/signed .

if [ -f "xx/config.zip" ]; then
    unzip -q xx/config.zip -d ~/.config
    timeout 15m telegram-upload "$ARCHIVE_FILE" --to "$TG_CHAT_ID"
fi
