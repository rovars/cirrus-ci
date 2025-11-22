#!/usr/bin/env bash

setup_src() {
    repo init -u https://github.com/LineageOS/android.git -b lineage-18.1 --groups=all,-notdefault,-darwin,-mips --git-lfs --depth=1

    git clone -q https://github.com/rovars/rom xx
    git clone -q https://codeberg.org/lin18-microG/local_manifests -b lineage-18.1 .repo/local_manifests
    
    rm -rf .repo/local_manifests/setup*
    mv xx/11/device.xml .repo/local_manifests/

    retry_rc repo sync -j8 -c --no-clone-bundle --no-tags

    rm -rf external/AOSmium-prebuilt 
    rm -rf external/hardened_malloc
    rm -rf prebuilts/AuroraStore
    rm -rf prebuilts/prebuiltapks

    rm -rf external/chromium-webview
    git clone -q https://github.com/LineageOS/android_external_chromium-webview external/chromium-webview -b master --depth=1

    rm -rf lineage-sdk
    git clone https://github.com/bimuafaq/android_lineage-sdk lineage-sdk -b lineage-18.1 --depth=1

    rm -rf build/make
    git clone https://github.com/bimuafaq/android_build_make build/make -b lineage-18.1 --depth=1

    rm -rf system/core
    git clone https://github.com/bimuafaq/android_system_core system/core -b lineage-18.1 --depth=1

    rm -rf vendor/lineage
    git clone https://github.com/bimuafaq/android_vendor_lineage vendor/lineage -b lineage-18.1 --depth=1

    rm -rf frameworks/base
    git clone https://github.com/bimuafaq/android_frameworks_base frameworks/base -b lineage-18.1 --depth=1

    rm -rf packages/apps/Settings
    git clone https://github.com/bimuafaq/android_packages_apps_Settings packages/apps/Settings -b lineage-18.1 --depth=1

    rm -rf packages/apps/Trebuchet
    git clone https://github.com/rovars/android_packages_apps_Trebuchet packages/apps/Trebuchet -b exthm-11 --depth=1

    rm -rf packages/apps/DeskClock
    git clone https://github.com/rovars/android_packages_apps_DeskClock packages/apps/DeskClock -b exthm-11 --depth=1

    rm -rf packages/apps/LineageParts
    git clone https://github.com/bimuafaq/android_packages_apps_LineageParts packages/apps/LineageParts -b lineage-18.1 --depth=1

    patch -p1 < $PWD/xx/11/allow-permissive-user-build.patch
}

build_src() {
    source build/envsetup.sh
    setup_rbe

    export OWN_KEYS_DIR=$PWD/xx/keys
    sudo ln -s $OWN_KEYS_DIR/releasekey.pk8 $OWN_KEYS_DIR/testkey.pk8
    sudo ln -s $OWN_KEYS_DIR/releasekey.x509.pem $OWN_KEYS_DIR/testkey.x509.pem

    lunch lineage_RMX2185-user
    
    # mmma packages/apps/Trebuchet:TrebuchetQuickStep
    # cd out/target/product/RMX2185
    # 7z a -r launcher3.7z system/system_ext/priv-app/TrebuchetQuickStep/TrebuchetQuickStep.apk
    # xc -c launcher3.7z

    mmma frameworks/base/packages/SystemUI:SystemUI
    cd out/target/product/RMX2185
    7z a -r SystemUI.7z system/system_ext/priv-app/SystemUI/SystemUI.apk
    xc -c SystemUI.7z

    # mka bacon
}

upload_src() {
    REPO="rovars/release"
    RELEASE_TAG="lineage-18.1"
    ROM_FILE=$(find out/target/product -name "*-RMX*.zip" -print -quit)
    ROM_X="https://github.com/$REPO/releases/download/$RELEASE_TAG/$(basename "$ROM_FILE")"

    echo "$tokenpat" > tokenpat.txt
    gh auth login --with-token < tokenpat.txt

    if ! gh release view "$RELEASE_TAG" -R "$REPO" > /dev/null 2>&1; then
        gh release create "$RELEASE_TAG" -t "$RELEASE_TAG" -R "$REPO" --generate-notes
    fi

    gh release upload "$RELEASE_TAG" "$ROM_FILE" -R "$REPO" --clobber || true

    echo "$ROM_X"
    MSG_XC2="( <a href='https://cirrus-ci.com/task/${CIRRUS_TASK_ID}'>Cirrus CI</a> ) - $CIRRUS_COMMIT_MESSAGE ( <a href='$ROM_X'>$(basename "$CIRRUS_BRANCH")</a> )"
    xc -s "$MSG_XC2"

    mkdir -p ~/.config && mv xx/config/* ~/.config
    timeout 15m telegram-upload $ROM_FILE --to $idtl --caption "$CIRRUS_COMMIT_MESSAGE" || true
}