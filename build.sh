#!/bin/bash
set -ex

ROOT_DIR="$(pwd)"
ROM_REPO_DIR="$ROOT_DIR/rom"

mkdir -p src
git clone -q --depth=1 https://github.com/brave/brave-core.git -b 1.87.x src/brave
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
  echo "ERROR: RBE_API_KEY not set. Please export it in your environment."
  exit 1
fi

export SISO_REAPI_ADDRESS="${rbe_service:-nano.buildbuddy.io:443}"
export SISO_REAPI_INSTANCE="default"
export SISO_CREDENTIAL_HELPER="$ROOT_DIR/siso_helper.sh"
export SISO_CACHE_DIR="${siso_cache_dir:-/tmp/siso-cache}"
export SISO_FALLBACK=true
export DEPOT_TOOLS_UPDATE=1

mkdir -p "$SISO_CACHE_DIR"

echo "Running npm run init..."
npm run init -- --target_os=android --target_arch=arm --no-history

echo "Ensuring scripts are executable..."
find "$ROOT_DIR/src/brave/script" -name "*.py" -exec chmod +x {} +
find "$ROOT_DIR/src/buildtools" -type f -not -name "*.gn" -not -name "*.gni" -exec chmod +x {} + || true

echo "Starting build..."
npm run build -- --target_os=android --target_arch=arm \
  --gn="enable_ai_chat:false" \
  --gn="enable_ai_rewriter:false" \
  --gn="enable_brave_news:false" \
  --gn="enable_brave_ads:false" \
  --gn="enable_brave_rewards:false" \
  --gn="enable_brave_wallet:false" \
  --gn="enable_tor:false" \
  --gn="enable_ipfs:false" \
  --gn="enable_speedreader:false" \
  --gn="enable_brave_vpn:false" \
  --gn="enable_brave_sync:false" \
  --gn="enable_brave_wayback_machine:false" \
  --gn="enable_sidebar:false" \
  --gn="enable_sparkle:false" \
  --gn="enable_brave_talk:false" \
  --gn="enable_commander:false" \
  --gn="enable_brave_education:false" \
  --gn="enable_text_recognition:false"

BUILD_DIR="../out/Debug_android"

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