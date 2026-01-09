#!/usr/bin/env bash

export rclonedir="me:rom"
export rclonefile="lin_18.tar.gz"
export use_ccache="false"

setup_src() {
    repo init -u https://github.com/rovars/android.git -b exthm-11 --groups=all,-notdefault,-darwin,-mips --git-lfs --depth=1
    git clone -q https://github.com/rovars/rom xx
    mkdir -p .repo/local_manifests
    mv xx/11/exthm.xml .repo/local_manifests/device.xml

    retry_rc repo sync -j8 -c --no-clone-bundle --no-tags

    rm -rf external/chromium-webview
    git clone -q https://github.com/LineageOS/android_external_chromium-webview external/chromium-webview -b master --depth=1

    cd device/realme/RMX2185
    mv lineage_RMX2185.mk exthm_RMX2185.mk
    sed -i \
    -e 's|\$(call inherit-product, vendor/lineage/config/common_mini_phone\.mk)|\$(call inherit-product, vendor/exthm/config/common_mini_phone.mk)|' \
    -e 's|PRODUCT_NAME := lineage_RMX2185|PRODUCT_NAME := exthm_RMX2185|' exthm_RMX2185.mk
    sed -i 's|lineage_RMX2185|exthm_RMX2185|g' AndroidProducts.mk
    cd -

    patch -p1 < $PWD/xx/11/permissive.patch
}

build_src() {
    source build/envsetup.sh
    # _ccache_env
    _use_rbe

    export OWN_KEYS_DIR=$PWD/xx/keys
    sudo ln -s $OWN_KEYS_DIR/releasekey.pk8 $OWN_KEYS_DIR/testkey.pk8
    sudo ln -s $OWN_KEYS_DIR/releasekey.x509.pem $OWN_KEYS_DIR/testkey.x509.pem

    lunch exthm_RMX2185-user
    mka bacon
}

upload_src() {
    REPO="bimuafaq/releases"
    RELEASE_TAG=$(date +%Y%m%d)
    RELEASE_FILE=$(find out/target/product -name "*-RMX*.zip" -print -quit)
    RELEASE_NAME=$(basename "$RELEASE_FILE")    

    echo "$tokenpat" > tokenpat.txt
    gh auth login --with-token < tokenpat.txt
   
    RELEASE_TAG=test
    # gh release create "$RELEASE_TAG" -t "$RELEASE_NAME" -R "$REPO" --generate-notes
    gh release upload "$RELEASE_TAG" "$RELEASE_FILE" -R "$REPO" --clobber || true

    mkdir -p ~/.config && mv xx/config/* ~/.config
    timeout 15m telegram-upload $RELEASE_FILE --to $idtl --caption "$CIRRUS_COMMIT_MESSAGE" || true
}