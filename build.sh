#!/usr/bin/env bash

setup_src() {
    repo init -u https://github.com/AICP/platform_manifest.git -b s12.1 --groups=all,-notdefault,-darwin,-mips --git-lfs --depth=1

    git clone -q https://github.com/rovars/rom r

    xp=$SRC_DIR/r/12
    zp=$SRC_DIR/r/12/patch

    mkdir -p .repo/local_manifests
    mv $xp/12.xml .repo/local_manifests

    retry_rc repo sync --no-tags --no-clone-bundle -j8

    rm -rf external/chromium-webview
    git clone -q --depth=1 https://github.com/LineageOS/android_external_chromium-webview -b master external/chromium-webview
  
    cd system/core
    git am $zp/patches_treble_phh/platform_system_core/0001*    
    git am $xp/12-allow-per*
    cd $SRC_DIR

    cd external/selinux
    git am $zp/patches_treble_phh/platform_external_selinux/0002-*
    cd $SRC_DIR

    cd device/realme/RMX2185
    sed -i 's/lineage_/aicp_/g' AndroidProducts.mk
    sed -i 's/lineage_/aicp_/g' lineage_RMX2185.mk
    sed -i 's|$(call inherit-product, vendor/lineage/config/common_full_phone.mk)|$(call inherit-product, vendor/aicp/config/common_full_phone.mk)|g' lineage_RMX2185.mk
    mv lineage_RMX2185.mk aicp_RMX2185.mk
    cd $SRC_DIR

    patch -p1 < $xpatch/init_fatal_reboot_target_recovery.patch
    awk -i inplace '!/true cannot be used in user builds/' system/sepolicy/Android.mk

}

build_src() {
    source build/envsetup.sh
    set_remote_vars
    export RBE_instance="nano.buildbuddy.io"
    export RBE_service="nano.buildbuddy.io:443"
    export RBE_remote_headers="x-buildbuddy-api-key=$nanokeyvars"
    export RBE_CXX_EXEC_STRATEGY="racing"
    export RBE_JAVAC_EXEC_STRATEGY="racing"
    export RBE_R8_EXEC_STRATEGY="racing"
    export RBE_D8_EXEC_STRATEGY="racing"
    brunch RMX2185 user
}

upload_src() {
    REPO="rovars/vars"
    RELEASE_TAG="AICP"
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