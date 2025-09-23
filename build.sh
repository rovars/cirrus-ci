#!/usr/bin/env bash

setup_src() {
    repo init -u https://github.com/LineageOS/android.git -b lineage-18.1 --groups=all,-notdefault,-darwin,-mips --git-lfs --depth=1
    git clone -q https://github.com/rovars/rom romx
    mkdir -p .repo/local_manifests
    mv romx/A11/los/patch.sh .
    mv romx/A11/los/* .repo/local_manifests
    retry_rc repo sync -c -j16 --force-sync --no-clone-bundle --no-tags --prune
    source patch.sh
}

build_src() {    
    export PRODUCT_DISABLE_SCUDO=true
    export SKIP_ABI_CHECKS=true
    export OWN_KEYS_DIR=$WORKDIR/rovarsx/keys
    export RELEASE_TYPE=UNOFFICIAL-signed
    source build/envsetup.sh
    set_rbeenv_vars
    brunch RMX2185 user
}

upload_src() {
  upSrc="out/target/product/*/*-RMX*.zip"
  curl bashupload.com -T $upSrc || true
  mkdir -p ~/.config
  mv romx/config/* ~/.config 2>/dev/null || true
  timeout 15m telegram-upload $upSrc --caption "$CIRRUS_COMMIT_MESSAGE" --to $idtl
}