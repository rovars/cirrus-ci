#!/usr/bin/env bash
set -e

RCLONE_REMOTE="me:rom"
ARCHIVE_NAME="ccache-losq.tar.gz"

setup_workspace() {
    exec > >(tee resync.txt) 2>&1
    repo init --depth=1 -u https://github.com/querror/android.git -b lineage-17.1

    git clone -q https://github.com/llcpp/rom llcpp
    git clone https://github.com/AXP-OS/build.git Axp

    mkdir -p .repo/local_manifests/
    mv llcpp/q/losq.xml .repo/local_manifests/roomservice.xml

    repo sync -j"$(nproc --all)" -c --force-sync --no-clone-bundle --no-tags --prune
    
    rm -rf frameworks/base/packages/OsuLogin
    rm -rf frameworks/base/packages/PrintRecommendationService
    
    declare -A PATCHES=(
        ["art"]="android_art/0001-constify_JNINativeMethod.patch"
        ["external/conscrypt"]="android_external_conscrypt/0001-constify_JNINativeMethod.patch"
        ["frameworks/base"]="android_frameworks_base/0018-constify_JNINativeMethod.patch"
        ["frameworks/opt/net/wifi"]="android_frameworks_opt_net_wifi/0001-constify_JNINativeMethod.patch"
        ["libcore"]="android_libcore/0004-constify_JNINativeMethod.patch"
        ["packages/apps/Nfc"]="android_packages_apps_Nfc/0001-constify_JNINativeMethod.patch"
        ["packages/apps/Bluetooth"]="android_packages_apps_Bluetooth/0001-constify_JNINativeMethod.patch"
        ["prebuilts/abi-dumps/vndk"]="android_prebuilts_abi-dumps_vndk/0001-protobuf-avi.patch"
    )

    for target_dir in "${!PATCHES[@]}"; do
        patch_file="${PATCHES[$target_dir]}"
        cd "$target_dir" || exit
        git am "$WORKDIR/Axp/Patches/LineageOS-17.1/$patch_file"
        cd "$WORKDIR"
    done
}

build_src() {
    exec > >(tee build.txt) 2>&1
    local -r timeout_seconds=5400   
    source build/envsetup.sh
    export USE_CCACHE=1
    export CCACHE_EXEC="$(command -v ccache)"
    export CCACHE_DIR="$CACHE_DIR"
    ccache -M 50G -F 0
    ccache -o compression=true

    lunch lineage_RMX2185-user
    mka bacon -j"$(nproc --all)" &
    local build_pid=$!
    SECONDS=0

    while kill -0 "$build_pid" &>/dev/null; do
        if (( SECONDS >= timeout_seconds )); then
            kill -s TERM "$build_pid" &>/dev/null || true
            wait "$build_pid" &>/dev/null || true
            tle -t "Build timed out after $timeout_seconds seconds"
            exit 1
        fi
        sleep 1
    done

    wait "$build_pid"
    local build_status=$?

    exit $build_status
}

upload_artifact() {
    exec > upload.txt 2>&1
    local filezip
    filezip=$(find out/target/product/*/ -maxdepth 1 -name "lineage-*.zip" | head -n 1)
    [[ -z "$filezip" ]] && return 1
    curl bashupload.com -T "$filezip" || true
    retry rclone copy "$filezip" "$RCLONE_REMOTE" || true
    save_cache
}