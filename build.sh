#!/usr/bin/env bash

setup_src() {
    repo init -u https://github.com/rovars/android.git -b exthm-11 --groups=all,-notdefault,-darwin,-mips --git-lfs --depth=1

    git clone -q https://github.com/rovars/rom x
    mkdir -p  .repo/local_manifests
    mv x/11/*.xml .repo/local_manifests/

    retry_rc repo sync -j8 -c --no-clone-bundle --no-tags

    rm -rf external/chromium-webview
    git clone -q --depth=1 https://github.com/LineageOS/android_external_chromium-webview -b master external/chromium-webview

    xpatch=$rom_src/x/11
    patch -p1 < $xpatch/*build.patch
}

build_module_src() {
    rm -rf packages/apps/Trebuchet
    git clone --depth=1 https://github.com/rovars/android_packages_apps_Trebuchet -b x packages/apps/Trebuchet

    lunch exthm_RMX2185-user

    mmm packages/apps/Trebuchet/:TrebuchetQuickStep
    7z a -t7z -mx=9 TrebuchetQuickStep.apk.7z out/*/*/*/system/system_ext/priv-app/TrebuchetQuickStep/TrebuchetQuickStep.apk
    xc -c TrebuchetQuickStep.apk.7z

    mka installclean

    mmm packages/apps/Trebuchet/:TrebuchetQuickStepGo
    7z a -t7z -mx=9 TrebuchetQuickStepGo.apk.7z out/*/*/*/system/system_ext/priv-app/TrebuchetQuickStepGo/TrebuchetQuickStepGo.apk
    xc -c TrebuchetQuickStepGo.apk.7z
    exit 1
}

build_src() {
    source build/envsetup.sh
    setup_rbe_vars
    # build_module_src

    export INSTALL_MOD_STRIP=1
    export BOARD_USES_MTK_HARDWARE=true
    export MTK_HARDWARE=true
    export USE_OPENGL_RENDERER=true

    export KBUILD_BUILD_USER=nobody
    export KBUILD_BUILD_HOST=android-build
    export BUILD_USERNAME=nobody
    export BUILD_HOSTNAME=android-build

    export OWN_KEYS_DIR=$rom_src/x/keys
    export EXTHM_EXTRAVERSION=signed

    sudo ln -s $OWN_KEYS_DIR/releasekey.pk8 $OWN_KEYS_DIR/testkey.pk8
    sudo ln -s $OWN_KEYS_DIR/releasekey.x509.pem $OWN_KEYS_DIR/testkey.x509.pem

    brunch RMX2185 user 2>&1 | tee build.txt
}

upload_src() {
    REPO="rovars/release"
    RELEASE_TAG="ExthmUI"
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
    xc -c "build.txt"
}