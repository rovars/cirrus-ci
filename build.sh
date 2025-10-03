#!/usr/bin/env bash

setup_src() {
    repo init --depth=1 -u https://github.com/querror/android -b lineage-17.1
    git clone -q https://github.com/rovars/rom romx
    git clone -q https://github.com/rovars/build npatch

    mkdir -p .repo/local_manifests/
    mv romx/manifest/lin10.xml .repo/local_manifests/roomservice.xml

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
        git am "$SRC_DIR/npatch/Patches/LineageOS-17.1/$patch_file"
        cd "$SRC_DIR"
    done
}

build_src() {
    source build/envsetup.sh
    export KBUILD_BUILD_USER=nobody
    export KBUILD_BUILD_HOST=android-build
    export BUILD_USERNAME=nobody
    export BUILD_HOSTNAME=android-build
    export RELEASE_TYPE=FE
    export EXCLUDE_SYSTEMUI_TESTS=true
    export OWN_KEYS_DIR=$SRC_DIR/romx/keys

    ln -s $OWN_KEYS_DIR/releasekey.pk8 $OWN_KEYS_DIR/testkey.pk8
    ln -s $OWN_KEYS_DIR/releasekey.x509.pem $OWN_KEYS_DIR/testkey.x509.pem

    set_ccache_vars
    brunch RMX2185 user
}


upload_src() {
    upSrc="out/target/product/*/*-RMX*.zip"
    mkdir -p ~/.config && mv romx/config/* ~/.config || true
    timeout 15m telegram-upload $upSrc --caption "${CIRRUS_COMMIT_MESSAGE}" --to $idtl || true
}
