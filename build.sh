#!/usr/bin/env bash

setup_src() {
    repo init -u https://github.com/LineageOS/android.git -b lineage-18.1 --groups=all,-notdefault,-darwin,-mips --git-lfs --depth=1
    git clone -q https://github.com/rovars/rom romx

    mkdir -p .repo/local_manifests
    mv romx/script/rom/lin11* .repo/local_manifests/

    retry_rc repo sync -c -j16 --force-sync --no-clone-bundle --no-tags --prune

    zpatch=$SRC_DIR/z_patches
    xpatch=$SRC_DIR/romx/script/rom/patch

    patch -p1 < $xpatch/lin11-allow-permissive-user-build.patch

    cd vendor/lineage
    git am $zpatch/patch_002_vendor-lineage.patch
    git am $zpatch/patch_004_vendor-lineage.patch
    git am $xpatch/lin11-vendor*.patch
    cd $SRC_DIR

    cd frameworks/base
    git am $zpatch/patch_001_base.patch
    git am $xpatch/lin11-base*.patch
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

    [ ! -e $OWN_KEYS_DIR/testkey.pk8 ] && ln -s $OWN_KEYS_DIR/releasekey.pk8 $OWN_KEYS_DIR/testkey.pk8
    [ ! -e $OWN_KEYS_DIR/testkey.x509.pem ] && ln -s $OWN_KEYS_DIR/releasekey.x509.pem $OWN_KEYS_DIR/testkey.x509.pem
    
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
    xc -s "$MSG_XC2"
}
