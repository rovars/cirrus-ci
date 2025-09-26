#!/usr/bin/env bash

setup_src() {
    repo init --depth=1 -u https://github.com/querror/android -b lineage-17.1
    git clone -q https://github.com/rovars/rom romx
    git clone -q https://github.com/rovars/build r_patch

    mkdir -p .repo/local_manifests/
    mv romx/A10/remove.xml .repo/local_manifests/roomservice.xml

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

    rm -rf frameworks/base
    git clone https://github.com/querror/android_frameworks_base -b lineage-17.1-q --depth=1 frameworks/base

    for target_dir in "${!PATCHES[@]}"; do
        patch_file="${PATCHES[$target_dir]}"
        cd "$target_dir" || exit
        git am "$WORKDIR/r_patch/Patches/LineageOS-17.1/$patch_file"
        cd "$WORKDIR"
    done
}

build_src() {
    source build/envsetup.sh
    export PRODUCT_DISABLE_SCUDO=true
    export TARGET_UNOFFICIAL_BUILD_ID=signed
    export OWN_KEYS_DIR=$WORKDIR/romx/A10/keys

    [ ! -e $OWN_KEYS_DIR/testkey.pk8 ] && ln -s $OWN_KEYS_DIR/releasekey.pk8 $OWN_KEYS_DIR/testkey.pk8
    [ ! -e $OWN_KEYS_DIR/testkey.x509.pem ] && ln -s $OWN_KEYS_DIR/releasekey.x509.pem $OWN_KEYS_DIR/testkey.x509.pem

    set_ccache_vars
    brunch RMX2185 user # & sleep 90m; kill %1
}


upload_src() {
    upSrc="out/target/product/*/*-RMX*.zip"
    mkdir -p ~/.config && mv romx/config/* ~/.config || true
    curl bashupload.com -T $upSrc || true
    timeout 15m telegram-upload $upSrc --caption "${CIRRUS_COMMIT_MESSAGE}" --to $idtl || true
    save_cache
}
