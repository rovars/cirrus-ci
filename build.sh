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
    git clone https://github.com/bimuafaq/android_system_core system/core -b lineage-18.1
    cd system/core
    git revert --no-edit 4c5d682b0134310ece17eba2fa21854d2c57397c
    cd -

    rm -rf vendor/lineage
    git clone https://github.com/bimuafaq/android_vendor_lineage vendor/lineage -b lineage-18.1 --depth=1

    rm -rf frameworks/base
    git clone https://github.com/bimuafaq/android_frameworks_base frameworks/base -b lineage-18.1 --depth=1
    sed -i 's#\(<bool[^>]*name="config_cellBroadcastAppLinks"[^>]*>\)\s*true\s*\(</bool>\)#\1false\2#g' frameworks/base/core/res/res/values/config.xml
    grep -n 'config_cellBroadcastAppLinks' frameworks/base/core/res/res/values/config.xml

    rm -rf packages/apps/Settings
    git clone https://github.com/bimuafaq/android_packages_apps_Settings packages/apps/Settings -b lineage-18.1 --depth=1

    rm -rf packages/apps/Trebuchet
    git clone https://github.com/rovars/android_packages_apps_Trebuchet packages/apps/Trebuchet -b exthm-11 --depth=1

    rm -rf packages/apps/DeskClock
    git clone https://github.com/rovars/android_packages_apps_DeskClock packages/apps/DeskClock -b exthm-11 --depth=1

    rm -rf packages/apps/LineageParts
    git clone https://github.com/bimuafaq/android_packages_apps_LineageParts packages/apps/LineageParts -b lineage-18.1 --depth=1

    patch -p1 < $PWD/xx/11/allow-permissive-user-build.patch

    git clone -q https://github.com/rovars/build xxx
    git clone -q https://codeberg.org/lin18-microG/z_patches -b lin-18.1-microG zzz

    z_patch="$PWD/zzz"
    x_patch="$PWD/xxx/Patches/LineageOS-18.1"

list_merged_repos() {
cat <<EOF
Z:external/conscrypt:patch_703_conscrypt.patch
Z:external/icu:patch_704_icu.patch
Z:external/neven:patch_705_neven.patch
Z:frameworks/rs:patch_706_rs.patch
Z:frameworks/ex:patch_707_ex.patch
Z:frameworks/opt/net/voip:patch_708_voip.patch
Z:hardware/qcom-caf/common:patch_709_qc-common.patch
Z:lineage-sdk:patch_710_lineage-sdk.patch
Z:packages/apps/FMRadio:patch_711_FMRadio.patch
Z:packages/apps/Gallery2:patch_712_Gallery2.patch
Z:vendor/qcom/opensource/fm-commonsys:patch_716_fm-commonsys.patch
Z:vendor/nxp/opensource/commonsys/packages/apps/Nfc:patch_717_nxp-Nfc.patch
Z:vendor/qcom/opensource/libfmjni:patch_718_libfmjni.patch
X:art:android_art/0001-constify_JNINativeMethod.patch
X:frameworks/base:android_frameworks_base/0017-constify_JNINativeMethod.patch
X:libcore:android_libcore/0002-constify_JNINativeMethod.patch
X:packages/apps/Bluetooth:android_packages_apps_Bluetooth/0001-constify_JNINativeMethod.patch
X:packages/apps/Nfc:android_packages_apps_Nfc/0001-constify_JNINativeMethod.patch
EOF
}

list_merged_repos | while read STR; do
    [ -z "$STR" ] && continue
    
    TYPE="${STR%%:*}"
    REMAINDER="${STR#*:}"
    
    DIR="${REMAINDER%%:*}"
    PTC="${REMAINDER#*:}"

    if [ "$TYPE" == "Z" ]; then
        SOURCE_PATH="$z_patch"
    elif [ "$TYPE" == "X" ]; then
        SOURCE_PATH="$x_patch"
    else
        continue
    fi

    echo "Applying $PTC to $DIR"
    
    if [ -d "$DIR" ]; then
        cd "$DIR"
        if [ -f "$SOURCE_PATH/$PTC" ]; then
            git am < "$SOURCE_PATH/$PTC"
        else
            echo "Error: Patch file not found: $SOURCE_PATH/$PTC"
        fi
        cd - > /dev/null
    else
        echo "Warning: Directory not found: $DIR"
    fi
done

    rm -rf xxx zzz
}

system_push_test() {
    # m TrebuchetQuickStep
    # cd out/target/product/RMX2185
    # zip launcher3.zip system/system_ext/priv-app/TrebuchetQuickStep/TrebuchetQuickStep.apk
    # xc -c launcher3.zip

    # m org.lineageos.platform
    m SystemUI
    # m LineageParts
    cd out/target/product/RMX2185
    VERSION=$(date +%y%m%d-%H%M)
    echo "id=system_push_test
name=system test
version=$VERSION
versionCode=$VERSION
author=system
description=system test" > module.prop
    # zip -r system-test-$VERSION.zip system/framework/org.lineageos.platform.jar system/system_ext/priv-app/SystemUI/SystemUI.apk system/priv-app/LineageParts/LineageParts.apk module.prop
    zip -r system-test-$VERSION.zip system/system_ext/priv-app/SystemUI/SystemUI.apk module.prop
    xc -c system-test-$VERSION.zip
}

build_src() {
    source build/envsetup.sh
    setup_rbe

    export OWN_KEYS_DIR=$PWD/xx/keys
    sudo ln -s $OWN_KEYS_DIR/releasekey.pk8 $OWN_KEYS_DIR/testkey.pk8
    sudo ln -s $OWN_KEYS_DIR/releasekey.x509.pem $OWN_KEYS_DIR/testkey.x509.pem

    lunch lineage_RMX2185-user
    
    system_push_test

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

    #gh release upload "$RELEASE_TAG" "$ROM_FILE" -R "$REPO" --clobber || true

    echo "$ROM_X"
    MSG_XC2="( <a href='https://cirrus-ci.com/task/${CIRRUS_TASK_ID}'>Cirrus CI</a> ) - $CIRRUS_COMMIT_MESSAGE ( <a href='$ROM_X'>$(basename "$CIRRUS_BRANCH")</a> )"
    xc -s "$MSG_XC2"

    mkdir -p ~/.config && mv xx/config/* ~/.config
    timeout 15m telegram-upload $ROM_FILE --to $idtl --caption "$CIRRUS_COMMIT_MESSAGE" || true
}