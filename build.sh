#!/usr/bin/env bash

export rclonedir="me:rom"
export rclonefile="lin_18.tar.gz"
export use_ccache="false"

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
    sed -i 's#\(<bool[^>]*name="config_cellBroadcastAppLinks"[^>]*>\)\s*true\s*\(</bool>\)#\1false\2#g' frameworks/base/core/res/res/values/config.xml
    grep -n 'config_cellBroadcastAppLinks' frameworks/base/core/res/res/values/config.xml

    rm -rf packages/apps/Settings
    git clone https://github.com/bimuafaq/android_packages_apps_Settings packages/apps/Settings -b lineage-18.1 --depth=1

    rm -rf packages/apps/Trebuchet
    git clone https://github.com/rovars/android_packages_apps_Trebuchet packages/apps/Trebuchet -b wip --depth=1


    rm -rf packages/apps/DeskClock
    git clone https://github.com/rovars/android_packages_apps_DeskClock packages/apps/DeskClock -b exthm-11 --depth=1

    rm -rf packages/apps/LineageParts
    git clone https://github.com/bimuafaq/android_packages_apps_LineageParts packages/apps/LineageParts -b lineage-18.1 --depth=1

    rm -rf frameworks/opt/telephony
    git clone https://github.com/bimuafaq/android_frameworks_opt_telephony frameworks/opt/telephony -b lineage-18.1 --depth=1
    
    patch -p1 < $PWD/xx/11/permissive.patch

    chmod +x $PWD/xx/11/constify.sh
    source $PWD/xx/11/constify.sh
}

_m_rovv() {
    VERSION=$(date +%y%m%d-%H%M)
    OUT="out/target/product/RMX2185"
    ZIPNAME="system-test-$VERSION.zip"
}

_m_trebuchet() {
    _m_rovv
    m TrebuchetQuickStep
    cd "$OUT"
    # zip -r TrebuchetQuickStep-A11.zip "system/system_ext/priv-app/TrebuchetQuickStep/TrebuchetQuickStep.apk" "system/system_ext/etc/permissions/com.android.launcher3.xml"
    # xc -c TrebuchetQuickStep-A11.zip && exit 0
    cd "system/system_ext/priv-app/TrebuchetQuickStep"
    zip -r launcher3.zip TrebuchetQuickStep.apk
    xc -c launcher3.zip
    croot
}

_m_system() {
    _m_rovv
    m org.lineageos.platform SystemUI LineageParts
    cd "$OUT"
    echo -e "id=system_push_test\nname=System Test\nversion=$VERSION\nversionCode=${VERSION//-/}\nauthor=system\ndescription=System Test" > module.prop
    zip -r "$ZIPNAME" module.prop system/framework/org.lineageos.platform.jar system/system_ext/priv-app/SystemUI/SystemUI.apk system/priv-app/LineageParts/LineageParts.apk
    xc -c "$ZIPNAME"
    croot
}

_m_systemui() {
    _m_rovv
    m SystemUI
    cd "$OUT"
    echo -e "id=system_push_test\nname=System Test\nversion=$VERSION\nversionCode=${VERSION//-/}\nauthor=system\ndescription=System Test" > module.prop
    zip -r "$ZIPNAME" module.prop system/system_ext/priv-app/SystemUI/SystemUI.apk
    xc -c "$ZIPNAME"
    croot
}

_m_settings() {
    _m_rovv
    m Settings
    cd "$OUT/system/system_ext/priv-app/Settings"
    zip -r Settings.zip Settings.apk
    xc -c Settings.zip
    croot
}

build_src() {
    source build/envsetup.sh
    # _ccache_env
    _use_rbe

    export OWN_KEYS_DIR=$PWD/xx/keys
    sudo ln -s $OWN_KEYS_DIR/releasekey.pk8 $OWN_KEYS_DIR/testkey.pk8
    sudo ln -s $OWN_KEYS_DIR/releasekey.x509.pem $OWN_KEYS_DIR/testkey.x509.pem

    lunch lineage_RMX2185-user
    # make clean

    _m_trebuchet
    # _m_system
    # _m_systemui
    # _m_settings

    # mka bacon
}

upload_src() {
    REPO="bimuafaq/releases"
    RELEASE_TAG=$(date +%Y%m%d)
    RELEASE_FILE=$(find out/target/product -name "*-RMX*.zip" -print -quit)
    RELEASE_NAME=$(basename "$RELEASE_FILE")

    echo "$tokenpat" > tokenpat.txt
    gh auth login --with-token < tokenpat.txt    

    #gh release create "$RELEASE_TAG" -t "$RELEASE_NAME" -R "$REPO" --generate-notes
    #gh release upload "$RELEASE_TAG" "$RELEASE_FILE" -R "$REPO" --clobber || true

    mkdir -p ~/.config && mv xx/config/* ~/.config
    timeout 15m telegram-upload $RELEASE_FILE --to $idtl --caption "$CIRRUS_COMMIT_MESSAGE" || true
}