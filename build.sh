#!/usr/bin/env bash

setup_src() {
    repo init -u https://github.com/LineageOS/android.git -b lineage-17.1
    git clone -q https://github.com/rovars/rom xx
    mkdir -p .repo/local_manifests/
    mv xx/10/device.xml .repo/local_manifests
    # mv xx/10/rev.xml .repo/local_manifests
    repo sync -j8 -c --no-clone-bundle --no-tags
    patch -p1 < permissive.patch
}

build_src() {    
    source build/envsetup.sh

    chmod +x xx/10/*.sh
    source xx/10/repopick.sh
    source xx/10/cb.sh
 
    export OWN_KEYS_DIR=$PWD/xx/keys
    sudo ln -s $OWN_KEYS_DIR/releasekey.pk8 $OWN_KEYS_DIR/testkey.pk8
    sudo ln -s $OWN_KEYS_DIR/releasekey.x509.pem $OWN_KEYS_DIR/testkey.x509.pem

    # brunch RMX2185
}

upload_src() {
    ROM_FILE=$(find out/target/product -name "*-RMX*.zip" -print -quit)

    echo "$tokenpat" | gh auth login --with-token
    gh release view "lineage-17.1" -R "rovars/release" >/dev/null 2>&1 || gh release create "lineage-17.1" -R "rovars/release" -t "lineage-17.1" --generate-notes

    mkdir -p ~/.config && mv xx/config/* ~/.config
    timeout 15m telegram-upload "$ROM_FILE" --to "$idtl" --caption "$CIRRUS_COMMIT_MESSAGE" || true
}