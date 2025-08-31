#!/usr/bin/env bash
set -e

setup_src() {
    repo init --depth=1 -u https://github.com/LineageOS/android.git -b lineage-18.1 --git-lfs
    # repo init --depth=1 -u https://github.com/querror/android.git -b lineage-17.1

    git clone -q https://github.com/llcpp/rom llcpp
    git clone -q https://github.com/AXP-OS/build Axp

    mkdir -p .repo/local_manifests/
    mv llcpp/q/losq.xml .repo/local_manifests/roomservice.xml

    repo sync -j"$(nproc --all)" -c --force-sync --no-clone-bundle --no-tags --prune

    # rm -rf frameworks/base/packages/OsuLogin
    # rm -rf frameworks/base/packages/PrintRecommendationService

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
        # git am "$WORKDIR/Axp/Patches/LineageOS-17.1/$patch_file"
        cd "$WORKDIR"
    done
}

build_src() {
    source build/envsetup.sh
    export USE_CCACHE=1
    export CCACHE_EXEC="$(command -v ccache)"
    export CCACHE_DIR="$CACHE_DIR"
    ccache -M 50G -F 0
    ccache -o compression=true
    lunch lineage_RMX2185-userdebug
    mka bacon -j"$(nproc --all)" &
    mka_time_out
}

upload_src() {    
    upSrc="out/target/product/*/lineage-*.zip"
    curl bashupload.com -T $upSrc || true
    mkdir -p ~/.config && mv llcpp/config/* ~/.config || true
    telegram-upload $upSrc --caption "${CIRRUS_COMMIT_MESSAGE}" --to $idtl || true
    save_cache
}