#!/usr/bin/env bash

setup_src() {
    repo init -u https://github.com/AICP/platform_manifest.git -b s12.1 --groups=all,-notdefault,-darwin,-mips --git-lfs --depth=1

    git clone -q https://github.com/rovars/rom
    mkdir -p .repo/local_manifests
    mv rom/12/12* .repo/local_manifests/

    retry_rc repo sync --no-clone-bundle --no-tags -j8

    rm -rf external/chromium-webview
    git clone -q --depth=1 https://github.com/LineageOS/android_external_chromium-webview -b master external/chromium-webview  

    xpatch=$SRC_DIR/rom/12
    zpatch=$SRC_DIR/rom/12/patch

    patch -p1 < $xpatch/init_fatal_reboot_target_recovery.patch
    awk -i inplace '!/true cannot be used in user builds/' system/sepolicy/Android.mk
  
    cd system/core
    git am $zpatch/patches_treble_phh/platform_system_core/0001*    
    git am $xpatch/12-allow-per*
    cd $SRC_DIR

    cd external/selinux
    git am $zpatch/patches_treble_phh/platform_external_selinux/0002-*
    cd $SRC_DIR

    cd device/realme/RMX2185
    sed -i 's/lineage_/aicp_/g' AndroidProducts.mk
    sed -i 's/lineage_/aicp_/g' lineage_RMX2185.mk
    sed -i 's|$(call inherit-product, vendor/lineage/config/common_full_phone.mk)|$(call inherit-product, vendor/aicp/config/common_full_phone.mk)|g' lineage_RMX2185.mk
    mv lineage_RMX2185.mk aicp_RMX2185.mk
    cd $SRC_DIR

}

build_src() {
    source build/envsetup.sh
    set_remote_vars

    export SKIP_ABI_CHECKS=true    
    export OWN_KEYS_DIR=$SRC_DIR/romx/keys
    ln -s $OWN_KEYS_DIR/releasekey.pk8 $OWN_KEYS_DIR/testkey.pk8
    ln -s $OWN_KEYS_DIR/releasekey.x509.pem $OWN_KEYS_DIR/testkey.x509.pem
    ln -sf "$OWN_KEYS_DIR" user-keys
    sed -i "1s;^;PRODUCT_DEFAULT_DEV_CERTIFICATE := user-keys/releasekey\nPRODUCT_OTA_PUBLIC_KEYS := user-keys/releasekey\n\n;" "vendor/aicp/config/common.mk"
   
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
    mv romx/config/* ~/.config
    timeout 15m telegram-upload $ROM_FILE --to $idtl --caption "$CIRRUS_COMMIT_MESSAGE"
}