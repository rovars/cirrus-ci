#!/usr/bin/env bash

setup_src() {
    repo init -u https://github.com/LineageOS/android.git -b lineage-18.1 --groups=all,-notdefault,-darwin,-mips --git-lfs --depth=1

    git clone -q https://github.com/rovars/rom romx
    git clone -q https://codeberg.org/lin18-microG/local_manifests .repo/local_manifests
    rm -rf .repo/local_manifests/setup*
    mv romx/11/lin11.xml .repo/local_manifests/

    retry_rc repo sync -c -j8 --force-sync --no-clone-bundle --no-tags --prune

    rm -rf external/AOSmium-prebuilt
    rm -rf external/chromium-webview
    git clone -q --depth=1 https://github.com/LineageOS/android_external_chromium-webview -b master external/chromium-webview

    zpatch=$SRC_DIR/z_patches
    xpatch=$SRC_DIR/romx/A11

    patch -p1 < $xpatch/*user-build.patch

    cd vendor/lineage
    git am $zpatch/patch_002_vendor-lineage.patch
    git am $zpatch/patch_004_vendor-lineage.patch
    git am $xpatch/*vendor*.patch
    cd $SRC_DIR

    cd frameworks/base
    git am $zpatch/patch_001_base.patch
    git am $xpatch/*base*.patch
    cd $SRC_DIR

    cd packages/apps/Settings
    git am $zpatch/patch_005_Settings.patch
    git am $zpatch/patch_006_Settings.patch
    cd $SRC_DIR  
}

build_src() {
    source build/envsetup.sh
    set_remote_vars

    export SKIP_ABI_CHECKS=true
    export OWN_KEYS_DIR=$SRC_DIR/romx/keys
    export RELEASE_TYPE=UNOFFICIAL

    sudo ln -s $OWN_KEYS_DIR/releasekey.pk8 $OWN_KEYS_DIR/testkey.pk8
    sudo ln -s $OWN_KEYS_DIR/releasekey.x509.pem $OWN_KEYS_DIR/testkey.x509.pem
    
    brunch RMX2185 user
}

upload_src() {
    REPO="rovars/vars"
    RELEASE_TAG="lineage-17.1"
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
    mv x/config/* ~/.config
    timeout 15m telegram-upload $ROM_FILE --to $idtl --caption "$CIRRUS_COMMIT_MESSAGE"
}