#!/bin/bash
set -e

BASE_DIR="$(pwd)"
WORK_DIR="${BASE_DIR}/workdir"
PATCH_DIR="${WORK_DIR}/AXP/Patches/LineageOS-17.1"
CCACHE_DIR="${WORK_DIR}/ccache"
CCACHE_ARCHIVE="${WORK_DIR}/ccache.tar.gz"
CCACHE_REMOTE="remote:ccache"
TIMEOUT_LIMIT="90m"

mkdir -p "$WORK_DIR"
exec > >(tee "$WORK_DIR/build.log") 2>&1
cd "$WORK_DIR"

USE_CCACHE=true
[ -f ./ccache.sh ] && source ./ccache.sh

syncAndPatch() {
    if [ "$USE_CCACHE" = true ]; then
        echo "[INFO] Running ccache setup in background..."
        setupCcache &
        CCACHE_PID=$!
    fi

    echo "[INFO] Starting repo initialization..."
    repo init --depth=1 -u https://github.com/rducks/android.git -b lineage-17.1
    git clone -q https://github.com/rducks/rom rom || exit 1
    git clone -q https://github.com/AXP-OS/build AXP || exit 1

    echo "[INFO] Moving local_manifests..."
    mkdir -p .repo/local_manifests/
    mv rom/q/los.xml .repo/local_manifests/roomservice.xml

    echo "[INFO] Syncing repositories..."
    repo sync -j"$(nproc)" -c --force-sync --no-clone-bundle --no-tags --prune

    echo "[INFO] Waiting for ccache setup to finish..."
    [ "$USE_CCACHE" = true ] && wait "$CCACHE_PID"

    echo "[INFO] Cleaning unwanted files..."
    rm -rf vendor/lineage/overlay/common/lineage-sdk/packages/LineageSettingsProvider/res/values/defaults.xml
    rm -rf packages/apps/LineageParts/src/org/lineageos/lineageparts/lineagestats/
    rm -rf packages/apps/LineageParts/res/xml/{anonymous_stats.xml,preview_data.xml}

    echo "[INFO] Applying patches..."
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
            git apply --verbose "$PATCH_DIR/$patch" || echo "[WARN] Failed to apply patch: $patch"
        done
        popd >/dev/null
    done

    echo "[INFO] Applying extra patches from rom/q..."
    for patch in rom/q/000{1..7}*; do
        [ -f "$patch" ] && patch -p1 < "$patch" || echo "[WARN] Patch not found: $patch"
    done

    rm -rf AXP
    echo "[INFO] Sync & patching completed."
}

buildRom() {
    source build/envsetup.sh

    if [ "$USE_CCACHE" = true ]; then
        export USE_CCACHE=1
        export CCACHE_EXEC="$(which ccache)"
        export CCACHE_DIR="$CCACHE_DIR"
        ccache -M 50G
    fi

    lunch lineage_RMX2185-user

    echo "[INFO] Starting build with timeout $TIMEOUT_LIMIT..."
    if timeout --foreground "$TIMEOUT_LIMIT" bash -c "mka bacon -j$(nproc)"; then
        echo "[INFO] Build completed successfully."
        [ "$USE_CCACHE" = true ] && saveCcache
    else
        if [ $? -eq 124 ]; then
            echo "[WARN] Build was stopped due to timeout."
            [ "$USE_CCACHE" = true ] && saveCcache
            exit 1
        else
            echo "[ERROR] Build failed."
            exit 1
        fi
    fi
}

uploadArtefak() {
    mkdir -p ~/.config
    mv rom/config/* ~/.config 2>/dev/null || true

    zip_file=$(find out/target/product/*/ -name "lineage-*.zip" | head -n 1)
    if [ -n "$zip_file" ]; then
        echo "[INFO] Uploading zip to Telegram..."
        telegram-upload --to "$idtl" --caption "${CIRRUS_COMMIT_MESSAGE}" "$zip_file"
    else
        echo "[WARN] No build artifact found to upload."
    fi
}

case "$1" in
    sync)
        syncAndPatch
        ;;
    build)
        buildRom
        ;;
    upload)
        uploadArtefak
        ;;
    *)
        echo "Usage: $0 {sync|build|upload}"
        exit 1
        ;;
esac

