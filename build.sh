#!/bin/bash

rclone_remote="thisfor:/rom/losq"
base_dir="$(pwd)"
cache_file="ccache.tar.gz"
cache_dir="${base_dir}/ccache"
archive_path="${base_dir}/${cache_file}"
work_dir="${base_dir}/workdir"
patch_dir="${work_dir}/AXP/Patches/LineageOS-17.1"

mkdir -p "$work_dir"
cd "$work_dir"

function RepoSync() {
    sendtl -t "Build Started! <a href='https://cirrus-ci.com/task/${CIRRUS_TASK_ID}'>View On Cirrus CI</a>"
    echo "Initializing and syncing repositories..."
    repo init --depth=1 -u https://github.com/rducks/android.git -b lineage-17.1
    git clone -q https://github.com/rducks/rom rom
    git clone -q https://github.com/AXP-OS/build AXP
    mkdir -p .repo/local_manifests/
    mv rom/q/los.xml .repo/local_manifests/roomservice.xml
    repo sync -j$(nproc --all) -c --force-sync --no-clone-bundle --no-tags --prune

    echo "Removing specific files..."
    rm -rf vendor/lineage/overlay/common/lineage-sdk/packages/LineageSettingsProvider/res/values/defaults.xml
    rm -rf packages/apps/LineageParts/src/org/lineageos/lineageparts/lineagestats/
    rm -rf packages/apps/LineageParts/res/xml/anonymous_stats.xml
    rm -rf packages/apps/LineageParts/res/xml/preview_data.xml

    echo "Applying patches from AXP-OS..."
    cd packages/apps/LineageParts
    patch_file="$patch_dir/android_packages_apps_LineageParts/0001-Remove_Analytics.patch"
    git apply --verbose "$patch_file"
    cd "$work_dir"

    cd packages/apps/SetupWizard
    patch_file="$patch_dir/android_packages_apps_SetupWizard/0001-Remove_Analytics.patch"
    git apply --verbose "$patch_file"
    cd "$work_dir"

    cd packages/apps/Settings
    patch_file="$patch_dir/android_packages_apps_Settings/0011-LTE_Only_Mode.patch"
    git apply --verbose "$patch_file"
    cd "$work_dir"

    cd frameworks/opt/net/ims
    patch_file="$patch_dir/android_frameworks_opt_net_ims/0001-Fix_Calling.patch"
    git apply --verbose "$patch_file"
    cd "$work_dir"

    cd build/make
    patch_file="$patch_dir/android_build/0003-Enable_fwrapv.patch"
    git apply --verbose "$patch_file"
    cd "$work_dir"

    cd build/soong
    patch_file_1="$patch_dir/android_build_soong/0001-Enable_fwrapv.patch"
    patch_file_2="$patch_dir/android_build_soong/0002-auto_var_init.patch"
    git apply --verbose "$patch_file_1"
    git apply --verbose "$patch_file_2"
    cd "$work_dir"

    echo "Applying patches from rom/q (using 'patch -p1')..."
    for patch in rom/q/{0001..0007}*; do
        if [ -f "$patch" ]; then
            patch -p1 < "$patch"
        else
            echo "Warning: Patch file $patch not found. Skipping."
        fi
    done

    echo "Cleaning AXP directory..."
    rm -rf AXP
    echo "Patching process completed."
}

function Build() {
    source build/envsetup.sh
    
    export USE_CCACHE=1
    export CCACHE_EXEC=/usr/bin/ccache
    export CCACHE_DIR="$cache_dir"

    ccache -o compression=true
    ccache -o compression_level=1
    ccache -o hash_dir=true
    ccache -o sloppiness=time_macros
    ccache -M 10G

    lunch lineage_RMX2185-user
    mka bacon -j$(nproc --all)
}

function RestoreCache() {
    echo "Restoring ccache from remote..."
    rclone copy "${rclone_remote}/${cache_file}" "${base_dir}/"
    
    if [ -f "$archive_path" ]; then
        echo "Cache file downloaded. Extracting..."
        mkdir -p "$cache_dir"
        tar -xf "$archive_path" -C "$cache_dir"
        rm -f "$archive_path"
        echo "Cache restored."
    else
        echo "No remote cache found. Starting with a fresh cache."
    fi
}

function UploadCache() {
    echo "Compressing and uploading ccache..."
    ccache -s
    tar -I pigz -cf "$archive_path" -C "$cache_dir" .
    rclone copy "$archive_path" "${rclone_remote}"
    rm -f "$archive_path"
    echo "Cache uploaded."
}

function UploadArtefak() {
    mkdir -p ~/.config    
    mv rom/config/* ~/.config

    zip_file=$(find out/target/product/*/ -name "lineage-*.zip" | head -n 1)

    if [ -n "$zip_file" ]; then
        echo "Build artifact found: $zip_file"
        echo "Starting upload..."
        telegram-upload --to "$idtl" --caption "${CIRRUS_COMMIT_MESSAGE}" "$zip_file"
        rclone copy "$zip_file" "${rclone_remote}"
        echo "Upload commands executed."
    else
        echo "Error: Build artifact (zip file) not found. Skipping upload."
    fi
}

case "$1" in
    sync) RepoSync ;;
    build) Build ;;
    upload) UploadArtefak ;;
    rcache) RestoreCache ;;
    ucache) UploadCache ;;
    *) echo "Usage: $0 {sync|build|upload|cache}" ;;
esac


