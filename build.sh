#!/usr/bin/env bash

setup_src() {
    repo init -u https://github.com/exthmui-legacy/android.git -b exthm-11 --groups=all,-notdefault,-darwin,-mips --git-lfs --depth=1
    git clone -q https://github.com/rovars/rom romx

    mkdir -p .repo/local_manifests
    mv romx/script/rom/11* .repo/local_manifests/

    retry_rc repo sync -c -j8 --force-sync --no-clone-bundle --no-tags --prune

    xpatch=$SRC_DIR/romx/script/rom/patch
    patch -p1 < $xpatch/lin11-allow-permissive-user-build.patch
    cd frameworks/base
    git am $xpatch/lin11-base-Revert-New-activity-transitions.patch
    cd $SRC_DIR

    sed -i 's/lineage_/exthm_/g' device/realme/RMX2185/AndroidProducts.mk
    sed -i 's/lineage_/exthm_/g' device/realme/RMX2185/lineage_RMX2185.mk
    sed -i 's|$(call inherit-product, vendor/lineage/config/common_full_phone.mk)|$(call inherit-product, vendor/exthm/config/common_full_phone.mk)|g' device/realme/RMX2185/lineage_RMX2185.mk
    mv device/realme/RMX2185/lineage_RMX2185.mk device/realme/RMX2185/exthm_RMX2185.mk

    sed -i 's#`<item name="config_(w)allpaperMaxScale" format="float" type="dimen">`1\.10`</item>`#\11\2#' frameworks/base/core/core/res/values/config.xml
}

build_src() {
    source build/envsetup.sh
    set_remote_vars

    export SKIP_ABI_CHECKS=true
    export OWN_KEYS_DIR=$SRC_DIR/romx/keys

    ln -s $OWN_KEYS_DIR/releasekey.pk8 $OWN_KEYS_DIR/testkey.pk8
    ln -s $OWN_KEYS_DIR/releasekey.x509.pem $OWN_KEYS_DIR/testkey.x509.pem

    ln -sf "$OWN_KEYS_DIR" user-keys
    sed -i "1s;^;PRODUCT_DEFAULT_DEV_CERTIFICATE := user-keys/releasekey\nPRODUCT_OTA_PUBLIC_KEYS := user-keys/releasekey\n\n;" "vendor/exthm/config/common.mk"
    
    brunch RMX2185 user
}

upload_src() {
    REPO="rovars/vars"
    RELEASE_TAG="lineage-18.1"
    ROM_FILE=$(find out/target/product -name "*-RMX*.zip" -print -quit)
    ROM_X="https://github.com/$REPO/releases/download/$RELEASE_TAG/$(basename "$ROM_FILE")"

    echo "$tokenpat" > tokenpat.txt
    gh auth login --with-token < tokenpat.txt

    if ! gh release view "$RELEASE_TAG" -R "$REPO" > /dev/null 2>&1; then
        gh release create "$RELEASE_TAG" -t "$RELEASE_TAG" -R "$REPO" --generate-notes
    fi

    gh release upload "$RELEASE_TAG" "$ROM_FILE" -R "$REPO" --clobber

    echo "$ROM_X"
    MSG_XC2="( <a href='https://cirrus-ci.com/task/${CIRRUS_TASK_ID}'>Cirrus CI</a> ) - $CIRRUS_COMMIT_MESSAGE ( <a href='$ROM_X'>$(basename "$CIRRUS_BRANCH")</a> )"
    xc -s "$MSG_XC2"

    mkdir -p ~/.config
    mv romx/config/* ~/.config
    timeout 15m telegram-upload $ROM_FILE --to $idtl --caption "$CIRRUS_COMMIT_MESSAGE"
}