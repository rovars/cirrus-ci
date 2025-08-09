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
    local patch_dir="$WORKDIR/AXP/Patches/LineageOS-17.1"
    
    declare -A patches=(
        ["frameworks/opt/net/ims"]="android_frameworks_opt_net_ims/0001-Fix_Calling.patch"
        ["build/make"]="android_build/0003-Enable_fwrapv.patch"
        ["build/soong"]="android_build_soong/0001-Enable_fwrapv.patch android_build_soong/0002-auto_var_init.patch"
    )
    
    for dir in "${!patches[@]}"; do
        if [[ -d "$dir" ]]; then
            (
                cd "$dir" || exit
                for patch in ${patches[$dir]}; do
                    [[ -f "$patch_dir/$patch" ]] && git apply --verbose "$patch_dir/$patch"
                done
            )
        else
            echo "Warning: Directory $dir not found, skipping patches"
        fi
    done
    
    for patch in llcpp/q/000{1..3}*; do
        [[ -f "$patch" ]] && patch -p1 < "$patch"
    done
    
    rm -rf AXP
}