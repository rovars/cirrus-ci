#!/usr/bin/env bash

setup_src() {
    repo init -u https://github.com/LineageOS/android.git -b lineage-18.1 --groups=all,-notdefault,-darwin,-mips --git-lfs --depth=1

    git clone -q https://github.com/rovars/rom romx

    mkdir -p .repo/local_manifests
    mv romx/manifest/lin11* .repo/local_manifests/

    retry_rc repo sync -c -j16 --force-sync --no-clone-bundle --no-tags --prune

    zpatch=$SRC_DIR/z_patches
    xpatch=$SRC_DIR/romx/patch

    cd vendor/lineage
    git am $zpatch/patch_002_vendor-lineage.patch
    git am $zpatch/patch_004_vendor-lineage.patch
    git am $xpatch/lin11-Vendor*.patch
    cd $SRC_DIR

    cd frameworks/base
    git am $zpatch/patch_001_base.patch
    git am $xpatch/lin11-Base*.patch
    cd $SRC_DIR

    cd packages/apps/Settings
    git am $zpatch/patch_005_Settings.patch
    git am $zpatch/patch_006_Settings.patch
    cd $SRC_DIR

    patch -p1 < romx/patch/lin11-allow-permissive-user-build.patch
}

build_src() {
    source build/envsetup.sh

    export PRODUCT_DISABLE_SCUDO=true
    export SKIP_ABI_CHECKS=true
    export OWN_KEYS_DIR=$SRC_DIR/romx/keys
    export RELEASE_TYPE=signed

    [ ! -e $OWN_KEYS_DIR/testkey.pk8 ] && ln -s $OWN_KEYS_DIR/releasekey.pk8 $OWN_KEYS_DIR/testkey.pk8
    [ ! -e $OWN_KEYS_DIR/testkey.x509.pem ] && ln -s $OWN_KEYS_DIR/releasekey.x509.pem $OWN_KEYS_DIR/testkey.x509.pem

    set_rbe_vars
    brunch RMX2185 user
}

upload_src() {
    upSrc="out/target/product/*/*-RMX*.zip"
    curl bashupload.com -T $upSrc || true
    mkdir -p ~/.config
    mv romx/config/* ~/.config 2>/dev/null || true
    timeout 15m telegram-upload $upSrc --caption "$CIRRUS_COMMIT_MESSAGE" --to $idtl
}
