#!/bin/bash
set -e

BASE_DIR="$(pwd)"
SRC_DIR="$BASE_DIR/src/android"
PATCH_DIR="$SRC_DIR/AXP/Patches/LineageOS-17.1"
TIMEOUT_LIMIT=600
USE_CCACHE=true

export CCACHE_DIR="$BASE_DIR/ccache"
export CCACHE_REMOTE="me:rom"
export CCACHE_ARCHIVE_NAME="ccache-lineage-17.1.tar.gz"
export CCACHE_ARCHIVE_PATH="$BASE_DIR/$CCACHE_ARCHIVE_NAME"

mkdir -p "$SRC_DIR" "$CCACHE_DIR"
cd "$SRC_DIR"

syncAndPatch() {
    local CCACHE_PID=""
    if [ "$USE_CCACHE" = true ]; then
        echo "[INFO] Running ccache restore in background..."
        "$BASE_DIR/ccache.sh" --restore &
        CCACHE_PID=$!
    fi

    echo "[INFO] Initializing repo..."
    repo init --depth=1 -u https://github.com/rducks/android.git -b lineage-17.1
    git clone -q https://github.com/rducks/rom rom
    git clone -q https://github.com/AXP-OS/build AXP

    echo "[INFO] Setting up local_manifests..."
    mkdir -p .repo/local_manifests/
    mv rom/q/los.xml .repo/local_manifests/roomservice.xml

    echo "[INFO] Syncing repositories..."
    repo sync -j"$(nproc)" -c --force-sync --no-clone-bundle --no-tags --prune

    if [ -n "$CCACHE_PID" ]; then
        echo "[INFO] Waiting for ccache restore to complete..."
        wait "$CCACHE_PID"
        echo "[INFO] Ccache restore finished."
    fi

    echo "[INFO] Cleaning unused files..."
    rm -rf vendor/lineage/overlay/common/lineage-sdk/packages/LineageSettingsProvider/res/values/defaults.xml
    rm -rf packages/apps/LineageParts/src/org/lineageos/lineageparts/lineagestats/
    rm -rf packages/apps/LineageParts/res/xml/{anonymous_stats.xml,preview_data.xml}

    echo "[INFO] Applying AXP patches..."
    declare -A PATCHES=(
        ["packages/apps/LineageParts"]="android_packages_apps_LineageParts/0001-Remove_Analytics.patch"
        ["packages/apps/SetupWizard"]="android_packages_apps_SetupWizard/0001-Remove_Analytics.patch"
        ["packages/apps/Settings"]="android_packages_apps_Settings/0011-LTE_Only_Mode.patch"
        ["frameworks/opt/net/ims"]="android_frameworks_opt_net_ims/0001-Fix_Calling.patch"
        ["build/make"]="android_build/0003-Enable_fwrapv.patch"
        ["build/soong"]="android_build_soong/0001-Enable_fwrapv.patch android_build_soong/0002-auto_var_init.patch"
    )

    for dir in "${!PATCHES[@]}"; do
        pushd "$dir" >/dev/null
        for patch in ${PATCHES[$dir]}; do
            git apply --verbose "$PATCH_DIR/$patch" || echo "[WARN] Failed to apply patch: $patch in $dir"
        done
        popd >/dev/null
    done

    echo "[INFO] Applying additional rom/q patches..."
    for patch in rom/q/000{1..7}*; do
        [ -f "$patch" ] && patch -p1 < "$patch" || echo "[WARN] Patch not found or failed to apply: $patch"
    done

    rm -rf AXP
    echo "[INFO] Sync and patching complete."
}

buildRom() {    
    source build/envsetup.sh

    if [ "$USE_CCACHE" = true ]; then
        export USE_CCACHE=1
        export CCACHE_EXEC="$(which ccache)"
        export CCACHE_DIR="$BASE_DIR/ccache"
        ccache -M 50G
        ccache -z
    fi

    lunch lineage_RMX2185-user

    mka bacon -j$(nproc) &
    BUILD_PID=$!

    SECONDS_PASSED=0
    while kill -0 $BUILD_PID 2>/dev/null; do
        if [ $SECONDS_PASSED -ge $TIMEOUT_LIMIT ]; then
            kill -9 $BUILD_PID 2>/dev/null || true
            wait $BUILD_PID 2>/dev/null || true
            echo "[ERROR] Build timed out after $TIMEOUT_LIMIT seconds."
            [ "$USE_CCACHE" = 1 ] && "$BASE_DIR/ccache.sh" --upload
            exit 1
        fi
        sleep 1
        SECONDS_PASSED=$((SECONDS_PASSED + 1))
    done

    wait $BUILD_PID
    BUILD_STATUS=$?

    if [ $BUILD_STATUS -eq 0 ]; then
        echo "[INFO] Build finished successfully."
        [ "$USE_CCACHE" = true ] && "$BASE_DIR/ccache.sh" --upload
    else
        echo "[ERROR] Build failed with exit code $BUILD_STATUS."
        exit 1
    fi
}

uploadArtifact() {
    local zip_file
    zip_file=$(find out/target/product/*/ -maxdepth 1 -name "lineage-*.zip" | head -n 1)

    mkdir -p ~/.config
    mv rom/config/* ~/.config

    if [ -n "$zip_file" ]; then
        echo "[INFO] Found build artifact: $zip_file"
        echo "[INFO] Uploading artifact to Telegram..."
        telegram-upload --to "$idtl" --caption "${CIRRUS_COMMIT_MESSAGE}" "$zip_file"
    else
        echo "[WARN] No build artifact found to upload."
    fi
}

case "$1" in
    sync) syncAndPatch ;;
    build) buildRom ;;
    upload) uploadArtifact ;;
    *) echo "Usage: $0 {sync|build|upload}" && exit 1 ;;
esac