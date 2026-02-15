#!/bin/bash
set -ex

ROOT_DIR="$(pwd)"
ROM_REPO_DIR="$ROOT_DIR/rom"

# Load custom .env from root if it exists
if [ -f "$ROOT_DIR/.env" ]; then
  echo "Loading custom .env from $ROOT_DIR/.env"
  set -a
  source "$ROOT_DIR/.env"
  set +a
fi

mkdir -p src
git clone -q --depth=1 https://github.com/brave/brave-core.git src/brave
cd src/brave

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
  echo "ERROR: RBE_API_KEY not set. Please add it to your .env file or export it."
  exit 1
fi

export SISO_REAPI_ADDRESS="${rbe_service:-nano.buildbuddy.io:443}"
export SISO_REAPI_INSTANCE="default"
export SISO_CREDENTIAL_HELPER="$ROOT_DIR/siso_helper.sh"
export SISO_CACHE_DIR="${siso_cache_dir:-/tmp/siso-cache}"
export SISO_FALLBACK=true
export DEPOT_TOOLS_UPDATE=1

mkdir -p "$SISO_CACHE_DIR"

# Generate src/brave/.env with defaults, allowing overrides from environment
# These dummy values are required to pass GN assertions in Release builds
cat > .env << EOF
rbe_service=${rbe_service:-nano.buildbuddy.io:443}
use_siso=${use_siso:-true}
use_remoteexec=${use_remoteexec:-true}
siso_cache_dir=${siso_cache_dir:-/tmp/siso-cache}
enable_ipfs=${enable_ipfs:-false}
enable_brave_rewards=${enable_brave_rewards:-false}
enable_brave_wallet=${enable_brave_wallet:-false}
enable_tor=${enable_tor:-false}
enable_speedreader=${enable_speedreader:-false}
enable_brave_ads=${enable_brave_ads:-false}
enable_brave_vpn=${enable_brave_vpn:-false}
brave_services_key=${brave_services_key:-dummy_key}
brave_services_key_id=${brave_services_key_id:-dummy_id}
brave_stats_updater_url=${brave_stats_updater_url:-https://localhost}
brave_variations_server_url=${brave_variations_server_url:-https://variations.brave.com}
updater_dev_endpoint=${updater_dev_endpoint:-https://updates.bravesoftware.com}
updater_prod_endpoint=${updater_prod_endpoint:-https://updates.bravesoftware.com}
service_key_aichat=${service_key_aichat:-dummy_aichat_key}
service_key_stt=${service_key_stt:-dummy_stt_key}
brave_sync_endpoint=${brave_sync_endpoint:-https://sync-v2.brave.com/v2}
rewards_grant_dev_endpoint=${rewards_grant_dev_endpoint:-https://localhost}
rewards_grant_staging_endpoint=${rewards_grant_staging_endpoint:-https://localhost}
rewards_grant_prod_endpoint=${rewards_grant_prod_endpoint:-https://localhost}
bitflyer_production_client_id=${bitflyer_production_client_id:-dummy_id}
bitflyer_production_client_secret=${bitflyer_production_client_secret:-dummy_secret}
bitflyer_production_fee_address=${bitflyer_production_fee_address:-dummy_address}
bitflyer_production_url=${bitflyer_production_url:-https://localhost}
gemini_production_api_url=${gemini_production_api_url:-https://localhost}
gemini_production_fee_address=${gemini_production_fee_address:-dummy_address}
gemini_production_oauth_url=${gemini_production_oauth_url:-https://localhost}
uphold_production_api_url=${uphold_production_api_url:-https://localhost}
uphold_production_fee_address=${uphold_production_fee_address:-dummy_address}
uphold_production_oauth_url=${uphold_production_oauth_url:-https://localhost}
zebpay_production_api_url=${zebpay_production_api_url:-https://localhost}
zebpay_production_oauth_url=${zebpay_production_oauth_url:-https://localhost}
brave_google_api_key=${brave_google_api_key:-dummy_google_key}
brave_google_api_endpoint=${brave_google_api_endpoint:-https://localhost}
brave_stats_api_key=${brave_stats_api_key:-dummy_stats_key}
safebrowsing_api_endpoint=${safebrowsing_api_endpoint:-https://localhost}
# Disable AFDO and PGO to avoid missing profile errors
call_afdo=false
chrome_pgo_phase=0
clang_use_default_sample_profile=false
enable_android_afdo=false
enable_chrome_android_internal_profiles=false
is_official_build=false
EOF

# Create a dummy afdo.prof file just in case GN still expects it
mkdir -p "$ROOT_DIR/src/chrome/android/profiles"
touch "$ROOT_DIR/src/chrome/android/profiles/afdo.prof"

echo "Running npm run init..."
npm run init -- --target_os=android --target_arch=arm --no-history

echo "Ensuring scripts are executable..."
find "$ROOT_DIR/src/brave/script" -name "*.py" -exec chmod +x {} +
find "$ROOT_DIR/src/buildtools" -type f -not -name "*.gn" -not -name "*.gni" -exec chmod +x {} + || true

echo "Starting build..."
npm run build -- --target_os=android --target_arch=arm Release --gn="is_official_build:false" --gn="call_afdo:false" --gn="chrome_pgo_phase:0" --gn="clang_use_default_sample_profile:false" --gn="enable_android_afdo:false"

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