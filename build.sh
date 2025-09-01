#!/usr/bin/env bash

setup_src() {
    git clone -q https://github.com/llcpp/rom romx
    ./romx/resync.sh   
}

build_src() {
    source build/envsetup.sh
    set_cache
    lunch dot_RMX2185-userdebug
    make bacon -j16 &
    sleep 80m
    kill %1 
    ccache -s
}

upload_src() {
    upSrc="out/target/product/*/*-RMX*.zip"
    curl bashupload.com -T $upSrc || true
    mkdir -p ~/.config && mv romx/config/* ~/.config || true
    telegram-upload $upSrc --caption "${CIRRUS_COMMIT_MESSAGE}" --to $idtl || true
    save_cache
}