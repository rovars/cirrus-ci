#!/usr/bin/env bash

setup_src() {
    repo init -u https://github.com/LineageOS/android.git -b lineage-17.1 --depth=1
    git clone -q https://github.com/rovars/rom xx
    mkdir -p .repo/local_manifests/
    mv xx/10/device.xml .repo/local_manifests
    mv xx/10/rev.xml .repo/local_manifests
    repo sync -j8 -c --no-clone-bundle --no-tags

    awk -i inplace '!/true cannot be used in user builds/' system/sepolicy/Android.mk;
    sed -i '/permissivedomains 1>&2; \\/{n;d;}' system/sepolicy/Android.mk
    sed -i 's/-DALLOW_PERMISSIVE_SELINUX=0/-DALLOW_PERMISSIVE_SELINUX=1/g' system/core/init/Android.bp
    sed -i 's/-DALLOW_PERMISSIVE_SELINUX=0/-DALLOW_PERMISSIVE_SELINUX=1/g' system/core/init/Android.mk

    git clone https://github.com/LineageOS/android_vendor_apn vendor/apn --depth=1
    
    rm -rf packages/apps/Settings
    git clone https://github.com/bimuafaq/android_packages_apps_Settings packages/apps/Settings -b lineage-17.1 --depth=1

    rm -rf frameworks/base
    git clone https://github.com/bimuafaq/android_frameworks_base frameworks/base -b lineage-17.1 --depth=1

    rm -rf frameworks/opt/telephony
    git clone https://github.com/bimuafaq/android_frameworks_opt_telephony frameworks/opt/telephony -b lineage-17.1 --depth=1
    
    rm -rf lineage-sdk
    git clone https://github.com/bimuafaq/android_lineage-sdk lineage-sdk -b lineage-17.1 --depth=1

    rm -rf packages/apps/LineageParts
    git clone https://github.com/bimuafaq/android_packages_apps_LineageParts packages/apps/LineageParts -b lineage-17.1 --depth=1

    rm -rf vendor/lineage
    git clone https://github.com/bimuafaq/android_vendor_lineage vendor/lineage -b lineage-17.1 --depth=1
}

build_src() {    
    source build/envsetup.sh
    _ccache_env

    export OWN_KEYS_DIR=$PWD/xx/keys
    sudo ln -s $OWN_KEYS_DIR/releasekey.pk8 $OWN_KEYS_DIR/testkey.pk8
    sudo ln -s $OWN_KEYS_DIR/releasekey.x509.pem $OWN_KEYS_DIR/testkey.x509.pem

    brunch RMX2185 user
}

upload_src() {
    ROM_FILE=$(find out/target/product -name "*-RMX*.zip" -print -quit)

    # echo "$tokenpat" | gh auth login --with-token
    # gh release view "lineage-17.1" -R "rovars/release" >/dev/null 2>&1 || gh release create "lineage-17.1" -R "rovars/release" -t "lineage-17.1" --generate-notes

    mkdir -p ~/.config && mv xx/config/* ~/.config
    timeout 15m telegram-upload "$ROM_FILE" --to "$idtl" --caption "$CIRRUS_COMMIT_MESSAGE" || true
}