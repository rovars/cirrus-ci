#!/bin/bash

set -e

TARGET_CPU="arm64"
KEYSTORE_PASS="rovars"

export SISO_REAPI_ADDRESS="nano.buildbuddy.io:443"
export SISO_REAPI_HEADER="x-buildbuddy-api-key=${RBE_API_KEY}"
export SISO_CREDENTIAL_HELPER="$(pwd)/siso_helper.sh"
export PATH="$(pwd)/depot_tools:$(pwd)/src/third_party/depot_tools:$PATH"

do_sync() {
    git clone -q https://chromium.googlesource.com/chromium/tools/depot_tools.git
    git clone -q --depth=1 https://github.com/brave/brave-core src/brave
    
    sudo chown -R cirrus:cirrus /usr/local/lib/python3.12/dist-packages /usr/local/bin || true
    
    cd src/brave
    npm install
    
    cat <<EOF > ../../.gclient
solutions = [
  {
    "name": "src",
    "url": "https://github.com/brave/chromium.git",
    "managed": False,
    "custom_vars": {
      "rbe_instance": "default_instance",
      "reapi_address": "nano.buildbuddy.io:443",
      "reapi_backend_config_path": "$(pwd)/../../buildbuddy_backend.star",
    },
  },
]
target_os = ["android"]
EOF

    npm run sync -- --target_os=android --target_arch=$TARGET_CPU
}

do_build() {
    [ ! -d "xx" ] && git clone -q https://rovars:${GITHUB_TOKEN}@github.com/rovars/rom xx
    SCRIPT_DIR="$(pwd)/xx/script/chromium"
    
    cd src
    CERT_DIGEST=$(keytool -export-cert -alias rov -keystore "$SCRIPT_DIR/rov.keystore" -storepass "$KEYSTORE_PASS" | sha256sum | cut -d' ' -f1)

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
brave_stats_updater_url = ""
brave_variations_server_url = ""
brave_p3a_enabled = false
enable_ipfs = false
enable_tor = false
enable_speedreader = false
EOF

    gn gen out/Release
    chrt -b 0 autoninja -C out/Release chrome_public_apk
}

do_upload() {
    cd src/out/Release/apks
    APKSIGNER=$(find ../../../third_party/android_sdk -name apksigner -type f | head -n 1)
    [ ! -d "../../../../xx" ] && git clone -q https://rovars:${GITHUB_TOKEN}@github.com/rovars/rom ../../../../xx
    
    $APKSIGNER sign --ks ../../../../xx/script/chromium/rov.keystore --ks-pass pass:"$KEYSTORE_PASS" --ks-key-alias rov --in BravePublic.apk --out Brave-Clean.apk

    ARCHIVE="Brave-Clean-$(date +%Y%m%d).tar.gz"
    tar -czf "../../../../$ARCHIVE" Brave-Clean.apk
    
    cd ../../../../
    unzip -q xx/config.zip -d ~/.config
    timeout 15m telegram-upload "$ARCHIVE" --to "$TG_CHAT_ID"
}

case "$1" in
    --sync) do_sync ;;
    --build) do_build ;;
    --upload) do_upload ;;
    *) echo "Usage: $0 {--sync|--build|--upload}" ;;
esac
