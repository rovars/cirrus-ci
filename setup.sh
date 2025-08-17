#!/usr/bin/env bash
set -e

CCACHE_ROM=0
RCLONE_REMOTE="me:rom"
ARCHIVE_NAME="ccache.tar.gz"

setup_workspace() {
    repo init -u https://github.com/PixelExperience-LEGACY-edition/manifest.git -b thirteen-plus --depth=1 --git-lfs
    git clone -q https://github.com/llcpp/rom llcpp
    mkdir -p .repo/local_manifests/
    mv llcpp/q/rom.xml .repo/local_manifests/roomservice.xml
    repo sync -j"$(nproc --all)" -c --force-sync --no-clone-bundle --no-tags --prune   
}

build_src() {
    exec > >(tee build.txt) 2>&1

    local -r timeout_seconds=5400
    
    source llcpp/rbe.env
    source build/envsetup.sh

    if [[ "$CCACHE_ROM" == "1" ]]; then
        export USE_CCACHE=1
        export CCACHE_EXEC="$(command -v ccache)"
        export CCACHE_DIR="$CACHE_DIR"
        ccache -M 50G -F 0
        ccache -o compression=true
    else
        export CCACHE_DISABLE=1
        unset USE_CCACHE
        unset CCACHE_EXEC
        unset CCACHE_DIR
    fi

    lunch aosp_RMX2185-userdebug
    mka bacon -j"$(nproc --all)" &
    local build_pid=$!
    SECONDS=0

    while kill -0 "$build_pid" &>/dev/null; do
        if (( SECONDS >= timeout_seconds )); then
            kill -s TERM "$build_pid" &>/dev/null || true
            wait "$build_pid" &>/dev/null || true
            tle -t "Build timed out after $timeout_seconds seconds"
            exit 1
        fi
        sleep 1
    done

    wait "$build_pid"
    local build_status=$?

    exit $build_status
}

upload_artifact() {
    zip_file=$(find out/target/product/*/ -maxdepth 1 -name "lineage-*.zip" -print | head -n 1)
    if [[ -n "$zip_file" ]]; then
        mkdir -p ~/.config
        mv llcpp/config/* ~/.config
        telegram-upload "$zip_file" --to "$idtl" --caption "${CIRRUS_COMMIT_MESSAGE}"   
        tle -f "build.txt"
    fi
    push_cache
}
