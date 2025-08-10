#!/usr/bin/env bash
set -e

USE_CACHE="true"
RCLONE_REMOTE="me:rom"
ARCHIVE_NAME="ccache-losq.tar.gz"

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

build_src() {
    local -r timeout_seconds=5400
    source build/envsetup.sh
    if [[ "$USE_CACHE" == "true" ]]; then
        export USE_CCACHE=1
        export CCACHE_EXEC="$(command -v ccache)"
        export CCACHE_DIR="$CACHE_DIR"
        ccache -M 50G -F 0
        ccache -o compression=true
    fi
    lunch lineage_RMX2185-user
    mka bacon -j"$(nproc --all)" 2>&1 | tee build.txt &
    local build_pid=$!
    SECONDS=0    
    while kill -0 "$build_pid" &>/dev/null; do
        if (( SECONDS >= timeout_seconds )); then
            kill -s TERM "$build_pid" &>/dev/null || true
            wait "$build_pid" &>/dev/null || true
            push_cache
            exit 1
        fi
        sleep 1
    done    
    wait "$build_pid"
}

upload_artifact() {
    local zip_file
    zip_file=$(find out/target/product/*/ -maxdepth 1 -name "lineage-*.zip" -print | head -n 1)
    if [[ -n "$zip_file" ]]; then
        mkdir -p ~/.config
        mv llcpp/config/* ~/.config
        telegram-upload "$zip_file" --to "$idtl" --caption "${CIRRUS_COMMIT_MESSAGE}"
    fi
    push_cache
}
