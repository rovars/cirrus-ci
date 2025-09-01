#!/usr/bin/env bash

setup_src() {
    git clone -q https://github.com/llcpp/rom romx
    ./romx/resync.sh   
}

xbuild_src() {
    source build/envsetup.sh
    set_cache
    lunch dot_RMX2185-userdebug
    make bacon -j16
}

build_src() {
    source build/envsetup.sh
    set_cache
    lunch dot_RMX2185-userdebug
    make bacon -j16 &
    sleep 10m
    kill %1 
    save_cache
}

upload_src() {
    upSrc="out/target/product/*/*-RMX*.zip"
    curl bashupload.com -T $upSrc || true
    mkdir -p ~/.config && mv romx/config/* ~/.config || true
    telegram-upload $upSrc --caption "${CIRRUS_COMMIT_MESSAGE}" --to $idtl || true
    save_cache
}