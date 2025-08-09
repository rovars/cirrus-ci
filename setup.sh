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

    git clone -q https://github.com/AXP-OS/build AXP

    local patch_dir="$WORKDIR/AXP/Patches"
    declare -A patches=(
        ["frameworks/base"]="Common/android_frameworks_base/0008-No_Crash_GSF.patch"
        ["build/make"]="Common/android_build/android_build/0001-verity-openssl3.patch \
                        LineageOS-17.1/android_build/android_build/0003-Enable_fwrapv.patch"
        ["build/soong"]="LineageOS-17.1/android_build_soong/0001-Enable_fwrapv.patch \
                        LineageOS-17.1/android_build_soong/0002-auto_var_init.patch"
    )

    for dir in "${!patches[@]}"; do
        if [[ -d "$dir" ]]; then
            (
                cd "$dir" || exit
                for patch in ${patches[$dir]}; do
                    patch_path="$patch_dir/$patch"
                    [[ -f "$patch_path" ]] && git apply --verbose "$patch_path"
                done
            )
        fi
    done
  
    for patch in llcpp/q/000{1..3}*; do
        [[ -f "$patch" ]] && patch -p1 < "$patch"
    done

    rm -rf frameworks/base/packages/OsuLogin
    rm -rf frameworks/base/packages/PrintRecommendationService
    rm -rf AXP
}