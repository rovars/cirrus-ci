#!/usr/bin/env bash

setup_src() {
    repo init -u https://gitlab.e.foundation/e/os/android.git -b v1-s --git-lfs --groups=all,-notdefault,-darwin,-mips --git-lfs --depth=1
    git clone -q https://github.com/rovars/rom romx

    mkdir -p .repo/local_manifests
    mv romx/script/rom/*12* .repo/local_manifests/

    retry_rc repo sync -c -j8 --force-sync --no-clone-bundle --no-tags --prune

    rm -rf external/chromium-webview
    git clone -q --depth=1 https://github.com/LineageOS/android_external_chromium-webview -b master external/chromium-webview

    cd prebuilts/prebuiltapks
    git lfs pull
    rm -rf Browser Notes Mail Camera eDrive
    cd $SRC_DIR

    xpatch=$SRC_DIR/romx/script/rom/patch

    # patch -p1 < $xpatch/lin11-allow-permissive-user-build.patch
    patch -p1 < $xpatch/init_fatal_reboot_target_recovery.patch

    cd frameworks/base
    git am $xpatch/lin11-base-Revert-New-activity-transitions.patch 
    cd $SRC_DIR

    cd vendor/lineage
    # git am $xpatch/lin11-vendor-*
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
    sed -i "1s;^;PRODUCT_DEFAULT_DEV_CERTIFICATE := user-keys/releasekey\nPRODUCT_OTA_PUBLIC_KEYS := user-keys/releasekey\n\n;" "vendor/lineage/config/common.mk"
    
    brunch RMX2185
}

upload_src() {
    REPO="rovars/vars"
    RELEASE_TAG="e/OS"
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