#!/usr/bin/env bash
set -e

USE_CACHE="true"
RCLONE_REMOTE="me:rom"
ARCHIVE_NAME="ccache-losq.tar.gz"
BUILDCM="lunch lineage_RMX2185-user && mka bacon"
ZIPNAME="lineage-*.zip"
SENDFILE='telegram-upload "$zip_file" --to "$idtl" --caption "${CIRRUS_COMMIT_MESSAGE}"'

setup_workspace() {
    repo init --depth=1 -u https://github.com/querror/android.git -b lineage-17.1
    git clone -q https://github.com/llcpp/rom llcpp
    mkdir -p .repo/local_manifests/
    mv llcpp/q/losq.xml .repo/local_manifests/roomservice.xml

    repo sync -j"$(nproc --all)" -c --force-sync --no-clone-bundle --no-tags --prune
   
    for patch in llcpp/q/000{1..3}*; do
        [[ -f "$patch" ]] && patch -p1 < "$patch"
    done

    rm -rf frameworks/base/packages/OsuLogin
    rm -rf frameworks/base/packages/PrintRecommendationService
}