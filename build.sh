#!/bin/bash

set -e

VANADIUM_TAG=${1:-"145.0.7632.45.1"}
TARGET_CPU="arm64"
ROOT_DIR="$(pwd)"
ROM_REPO_DIR="$ROOT_DIR/rom"

# Load custom .env from root if it exists
if [ -f "$ROOT_DIR/.env" ]; then
  echo "Loading custom .env from $ROOT_DIR/.env"
  set -a
  source "$ROOT_DIR/.env"
  set +a
fi

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

export SISO_REAPI_ADDRESS="nano.buildbuddy.io:443"
export SISO_REAPI_INSTANCE="default_instance"
export SISO_PROFILER=1
export SISO_CREDENTIAL_HELPER="$ROOT_DIR/siso_helper.sh"
export SISO_FALLBACK=true

export DEPOT_TOOLS_UPDATE=1
export GCLIENT_SUPPRESS_GIT_VERSION_WARNING=1
export PATH="$ROOT_DIR/depot_tools:$PATH"

git clone -q https://chromium.googlesource.com/chromium/tools/depot_tools.git "$ROOT_DIR/depot_tools"

git clone -q --depth=1 https://github.com/GrapheneOS/Vanadium.git "$ROOT_DIR/Vanadium"
cd "$ROOT_DIR/Vanadium"

cat <<EOF > .gclient
solutions = [
  {
    "name": "src",
    "url": "https://chromium.googlesource.com/chromium/src.git",
    "managed": False,
    "custom_vars": {
      "rbe_instance": "default_instance",
      "reapi_address": "nano.buildbuddy.io:443",
    },
  },
]
target_os = ["android"]
EOF

gclient sync --nohooks --no-history -j 8

cd src
# Create dummy afdo.prof
mkdir -p chrome/android/profiles
touch chrome/android/profiles/afdo.prof

CHROMIUM_VERSION=$(echo "$VANADIUM_TAG" | cut -d'.' -f1-4)
git fetch --depth=1 origin "refs/tags/$CHROMIUM_VERSION:refs/tags/$CHROMIUM_VERSION"
git checkout "$CHROMIUM_VERSION"
git am --3way --whitespace=nowarn --keep-non-patch ../patches/*.patch

gclient sync -D --no-history --with_branch_heads --with_tags -j 8
gclient runhooks

SCRIPT_DIR="$ROM_REPO_DIR/script/chromium"
if [ -f "$SCRIPT_DIR/rov.keystore" ]; then
    CERT_DIGEST=$(keytool -export-cert -alias rov -keystore "$SCRIPT_DIR/rov.keystore" -storepass rovars | sha256sum | cut -d' ' -f1)
else
    CERT_DIGEST="000000"
fi

BUILD_DIR="out/Default"
mkdir -p "$BUILD_DIR"
cat <<EOF > "$BUILD_DIR/args.gn"
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
chrome_pgo_phase = 0
enable_android_afdo = false
enable_chrome_android_internal_profiles = false
EOF

chrt -b 0 autoninja -C "$BUILD_DIR" chrome_public_apk

[ -f "$ROM_REPO_DIR/config.zip" ] && unzip -q "$ROM_REPO_DIR/config.zip" -d ~/.config

cd "$BUILD_DIR/apks"
APKSIGNER=$(find ../../../third_party/android_sdk/public/build-tools -name apksigner -type f | head -n 1)

if [ -f "$SCRIPT_DIR/rov.keystore" ]; then
    $APKSIGNER sign --ks "$SCRIPT_DIR/rov.keystore" --ks-pass pass:rovars --ks-key-alias rov --in ChromePublic.apk --out Vanadium-Monolithic.apk
    FINAL_APK="Vanadium-Monolithic.apk"
else
    FINAL_APK="ChromePublic.apk"
fi

ARCHIVE_FILE="Vanadium-Monolithic-${VANADIUM_TAG}-${TARGET_CPU}-$(date +%Y%m%d).tar.gz"
tar -czf "$ROOT_DIR/$ARCHIVE_FILE" "$FINAL_APK"

cd "$ROOT_DIR"
timeout 15m telegram-upload "$ARCHIVE_FILE" --to "$TG_CHAT_ID"