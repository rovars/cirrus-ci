#!/bin/bash
set -e

rclone_remote="me:rom"
archive_name="ccache.tar.gz"
cd "$src_dir"

retry_command() {
    max_retry=3
    retry_delay=10
    for i in $(seq 1 "$max_retry"); do
        "$@" && return 0
        [ "$i" -lt "$max_retry" ] && sleep "$retry_delay"
    done
    return 1
}

restoreCache() {
    if retry_command rclone copy "$rclone_remote/$archive_name" . --progress; then
        tar -xzf "$archive_name"
        rm -f "$archive_name"
    fi
}

uploadCache() {
    if tar -czf "$archive_name" cache; then       
        retry_command rclone copy "$archive_name" "$rclone_remote" --progress
        rm -f "$archive_name"
    fi
}

syncAndPatch() {
    repo init --depth=1 -u https://github.com/rducks/android.git -b lineage-17.1
    git clone -q https://github.com/rducks/rom rom

    mkdir -p .repo/local_manifests/
    mv rom/q/los.xml .repo/local_manifests/roomservice.xml

    repo sync -j"$(nproc)" -c --force-sync --no-clone-bundle --no-tags --prune

    git clone -q https://github.com/AXP-OS/build AXP
    patch_dir="$src_dir/AXP/Patches/LineageOS-17.1"

    rm -rf vendor/lineage/overlay/common/lineage-sdk/packages/LineageSettingsProvider/res/values/defaults.xml
    rm -rf packages/apps/LineageParts/src/org/lineageos/lineageparts/lineagestats/
    rm -rf packages/apps/LineageParts/res/xml/{anonymous_stats.xml,preview_data.xml}

    declare -A patches=(
        ["packages/apps/LineageParts"]="android_packages_apps_LineageParts/0001-Remove_Analytics.patch"
        ["packages/apps/SetupWizard"]="android_packages_apps_SetupWizard/0001-Remove_Analytics.patch"
        ["packages/apps/Settings"]="android_packages_apps_Settings/0011-LTE_Only_Mode.patch"
        ["frameworks/opt/net/ims"]="android_frameworks_opt_net_ims/0001-Fix_Calling.patch"
        ["build/make"]="android_build/0003-Enable_fwrapv.patch"
        ["build/soong"]="android_build_soong/0001-Enable_fwrapv.patch android_build_soong/0002-auto_var_init.patch"
    )

    for dir in "${!patches[@]}"; do
        pushd "$dir" >/dev/null
        for patch in ${patches[$dir]}; do
            git apply --verbose "$patch_dir/$patch"
        done
        popd >/dev/null
    done

    for patch in rom/q/000{1..7}*; do
        [ -f "$patch" ] && patch -p1 < "$patch"
    done

    rm -rf AXP
}

buildRom() {
    timeout_limit=200

    source build/envsetup.sh

    if [ "$use_cache" = true ]; then
        export USE_CCACHE=1
        export CCACHE_EXEC="$(which ccache)"
        export CCACHE_DIR="$ccache_dirs"
        ccache -M 50G
        ccache -z
    fi

    lunch lineage_RMX2185-user

    mka bacon -j"$(nproc)" &
    build_pid=$!

    SECONDS=0
    while kill -0 $build_pid 2>/dev/null; do
        if [ $SECONDS -ge $timeout_limit ]; then
            kill -9 $build_pid 2>/dev/null || true
            wait $build_pid 2>/dev/null || true
            [ "$use_cache" = true ] && uploadCache
            exit 1
        fi
        sleep 1
    done

    wait $build_pid
    build_status=$?

    if [ $build_status -eq 0 ]; then
        [ "$use_cache" = true ] && uploadCache
    else
        exit 1
    fi
}

uploadArtifact() {
    local zip_file
    zip_file=$(find out/target/product/*/ -maxdepth 1 -name "lineage-*.zip" | head -n 1)
    if [ -n "$zip_file" ]; then
        mv rom/config/* ~/.config
        telegram-upload --to "$idtl" --caption "${CIRRUS_COMMIT_MESSAGE}" "$zip_file"
    fi
}

case "$1" in
    sync) syncAndPatch ;;
    build) buildRom ;;
    upload) uploadArtifact ;;
    cache) restoreCache ;;
    *) echo "Usage: $0 {sync|build|upload|cache}" && exit 1 ;;
esac