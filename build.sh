#!/usr/bin/env bash
set -e

setup_src() {
    git clone -q https://github.com/llcpp/rom romx
    # repo init --depth=1 -u https://github.com/querror/android.git -b lineage-17.1
    # mv romx/patch/remove.xml .repo/local_manifests/roomservice.xml
    # repo sync -j"$(nproc --all)" -c --force-sync --no-clone-bundle --no-tags --prune
    ./romx/resync.sh
    # ./romx/patches.sh
}

build_src() {
    source build/envsetup.sh
    envr_cache
    lunch dot_RMX2185-userdebug
    make_time_out "make bacon -j16"
}

upload_src() {    
    upSrc="out/target/product/*/*-RMX*.zip"
    curl bashupload.com -T $upSrc || true
    mkdir -p ~/.config && mv romx/config/* ~/.config || true
    telegram-upload $upSrc --caption "${CIRRUS_COMMIT_MESSAGE}" --to $idtl || true
    save_cache
}