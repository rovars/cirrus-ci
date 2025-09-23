#!/usr/bin/env bash

setup_src() {
    repo init -u https://github.com/LineageOS/android.git -b lineage-18.1 --groups=all,-notdefault,-darwin,-mips --git-lfs --depth=1
    git clone -q https://github.com/rovars/rom romx
    mkdir -p .repo/local_manifests
    mv romx/A11/los/patch n_patch
    mv romx/A11/los/* .repo/local_manifests
    retry_rc repo sync -c -j16 --force-sync --no-clone-bundle --no-tags --prune
    source n_patch/patch.sh
}

build_src() {
  source build/envsetup.sh

  export PRODUCT_DISABLE_SCUDO=true
  export SKIP_ABI_CHECKS=true
  export OWN_KEYS_DIR=$WORKDIR/romx/A11/keys
  export RELEASE_TYPE=UNOFFICIAL-GmsCompat-signed

  if [ ! -e $OWN_KEYS_DIR/testkey.pk8 ] ; then
    ln -s $OWN_KEYS_DIR/releasekey.pk8 $OWN_KEYS_DIR/testkey.pk8
    echo "Symlink testkey.pk8 created"
  fi
  if [ ! -e $OWN_KEYS_DIR/testkey.x509.pem ] ; then
    ln -s $OWN_KEYS_DIR/releasekey.x509.pem $OWN_KEYS_DIR/testkey.x509.pem
    echo "Symlink testkey.x509.pem created"
  fi

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