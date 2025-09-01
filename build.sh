#!/usr/bin/env bash

setup_src() {
    git clone -q https://github.com/llcpp/rom romx
    mkdir -p .repo/local_manifests/
    mv romx/patch/remove.xml .repo/local_manifests/
    repo sync -j16 -c --force-sync --no-clone-bundle --no-tags --prune
    # ./romx/resync.sh   
}

build_src() {
    source build/envsetup.sh
    set_cache
    lunch lineage_RMX2185-user
    make bacon -j16 &
    sleep 90m
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