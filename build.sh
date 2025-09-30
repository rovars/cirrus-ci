#!/usr/bin/env bash

setup_src() {
    repo init -u https://github.com/LineageOS/android.git -b lineage-19.1 --groups=all,-notdefault,-darwin,-mips --git-lfs --depth=1
    git clone -q https://github.com/rovars/rom romx
    mkdir -p .repo/local_manifests
    mv romx/manifest/lin12.xml .repo/local_manifests

    retry_rc repo sync -j16 -c --force-sync --no-clone-bundle --no-tags --prune

    source romx/script/nun
}

build_src() {   
    source build/envsetup.sh
    set_remote_vars
    export SKIP_ABI_CHECKS=true
    brunch RMX2185 user
}


upload_src() {
    upSrc="out/target/product/*/*-RMX*.zip"
    mkdir -p ~/.config && mv romx/config/* ~/.config || true
    curl bashupload.com -T $upSrc || true
    timeout 15m telegram-upload $upSrc --caption "${CIRRUS_COMMIT_MESSAGE}" --to $idtl || true
    save_cache
}