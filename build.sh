#!/usr/bin/env bash

setup_src() {
    repo init -u https://github.com/rovars/android.git -b lineage-19.1 --git-lfs --groups=all,-notdefault,-darwin,-mips --depth=1
 
    git clone -q https://github.com/rovars/rom r

    xp=$SRC_DIR/r/12
    zp=$SRC_DIR/r/12/patch

    mkdir -p .repo/local_manifests
    mv $xp/12.xml .repo/local_manifests
   
    retry_rc repo sync --no-tags --no-clone-bundle -j8

    rm -rf external/chromium-webview
    git clone -q --depth=1 https://github.com/LineageOS/android_external_chromium-webview -b master external/chromium-webview
    
    cd packages/apps/DeskClock
    git am $zp/patches_platform_personal/packages_apps_DeskClock/00*
    cd $SRC_DIR

    rm -rf system/core
    git clone -q --depth=1 https://github.com/droid-legacy/android_system_core system/core -b lineage-19.1

    cd system/core
    git am $zp/patches_treble_phh/platform_system_core/0001*
    git am $xp/12-allow-per*
    cd $SRC_DIR

    cd external/selinux
    git am $zp/patches_treble_phh/platform_external_selinux/0002-*
    cd $SRC_DIR

    patch -p1 < $xp/init_fatal_reboot_target_recovery.patch
    patch -p1 < $xp/12.patch
    awk -i inplace '!/true cannot be used in user builds/' system/sepolicy/Android.mk
    sed -i '$ a PRODUCT_SYSTEM_DEFAULT_PROPERTIES += persist.sys.disable_rescue=true' vendor/lineage/config/common.mk

    git clone -q https://github.com/rovars/build npatch

    declare -A PATCHES=(
        ["art"]="android_art/0001-constify_JNINativeMethod.patch"
        ["external/conscrypt"]="android_external_conscrypt/0001-constify_JNINativeMethod.patch"        
        ["frameworks/ex"]="android_frameworks_ex/0001-constify_JNINativeMethod.patch"
        ["libcore"]="android_libcore/0002-constify_JNINativeMethod.patch"
        ["packages/apps/Nfc"]="android_packages_apps_Nfc/0001-constify_JNINativeMethod.patch"
        ["packages/apps/Bluetooth"]="android_packages_apps_Bluetooth/0001-constify_JNINativeMethod.patch"       
        ["build/make"]="android_build/0001-Enable_fwrapv.patch"
        ["build/soong"]="android_build_soong/0001-Enable_fwrapv.patch"
    )

    for target_dir in "${!PATCHES[@]}"; do
        patch_file="${PATCHES[$target_dir]}"
        cd "$target_dir" || exit
        git am "$SRC_DIR/npatch/Patches/LineageOS-19.1/$patch_file"
        cd "$SRC_DIR"
    done

}

build_src() {
    source build/envsetup.sh
    set_remote_vars
    # export RBE_instance="nano.buildbuddy.io"
    # export RBE_service="nano.buildbuddy.io:443"
    # export RBE_remote_headers="x-buildbuddy-api-key=$nanokeyvars"
    export RBE_CXX_EXEC_STRATEGY="racing"
    export RBE_JAVAC_EXEC_STRATEGY="racing"
    export RBE_R8_EXEC_STRATEGY="racing"
    export RBE_D8_EXEC_STRATEGY="racing"
    brunch RMX2185 user
}

upload_src() {
    REPO="rovars/vars"
    RELEASE_TAG="lineage-19.1"
    ROM_FILE=$(find out/target/product -name "*UNOFFICIAL*.zip" -print -quit)
    ROM_X="https://github.com/$REPO/releases/download/$RELEASE_TAG/$(basename "$ROM_FILE")"

    echo "$tokenpat" > tokenpat.txt
    gh auth login --with-token < tokenpat.txt
    if ! gh release view "$RELEASE_TAG" -R "$REPO" > /dev/null 2>&1; then
        gh release create "$RELEASE_TAG" -t "$RELEASE_TAG" -R "$REPO" --generate-notes
    fi
    gh release upload "$RELEASE_TAG" "$ROM_FILE" -R "$REPO" --clobber
    echo "$ROM_X"

    xc -s "( <a href='https://cirrus-ci.com/task/${CIRRUS_TASK_ID}'>Cirrus CI</a> ) - $CIRRUS_COMMIT_MESSAGE ( <a href='$ROM_X'>$(basename "$CIRRUS_BRANCH")</a> )"

    mkdir -p ~/.config
    mv r/config/* ~/.config
    timeout 15m telegram-upload $ROM_FILE --to $idtl --caption "$CIRRUS_COMMIT_MESSAGE"
}