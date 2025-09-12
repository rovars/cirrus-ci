#!/usr/bin/env bash

setup_src() {
    repo init --depth=1 -u https://github.com/querror/android -b lineage-17.1
    git clone -q https://github.com/rovars/rom romx
    git clone -q https://github.com/AXP-OS/build Axp

    mkdir -p .repo/local_manifests/
    mv romx/patch/remove.xml .repo/local_manifests/roomservice.xml

    repo sync -j16 -c --force-sync --no-clone-bundle --no-tags --prune

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
    source build/envsetup.sh
    set_cache
    lunch lineage_RMX2185-user
    mka bacon # & sleep 90m; kill %1; ccache -s
}

upload_src() {
    upSrc="out/target/product/*/*-RMX*.zip"
    mkdir -p ~/.config && mv romx/config/* ~/.config || true   
    curl bashupload.com -T $upSrc || true    
    timeout 10m telegram-upload $upSrc --caption "${CIRRUS_COMMIT_MESSAGE}" --to $idtl || true
    save_cache
}