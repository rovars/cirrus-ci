#!/usr/bin/env bash

set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source "$SCRIPT_DIR/build.sh"

export NINJA_HIGHMEM_NUM_JOBS=1
export SKIP_ABI_CHECKS=true

retry_rc() {
    local max_retries=12 delay=5 attempt=1
    while [[ $attempt -le $max_retries ]]; do
        "$@" && return 0
        [[ $attempt -lt $max_retries ]] && sleep "$delay"
        ((attempt++))
    done
    return 1
}

_ccache_env() {
    export USE_CCACHE=1
    export CCACHE_EXEC="$(command -v ccache)"
    export CCACHE_DIR="/tmp/ccache"
}

setup_cache() {
    if [ "$use_ccache" != "true" ]; then
        echo "Skipping setup_cache (use_ccache is not true)"
        return 0
    fi
    cd /tmp
    _ccache_env
    mkdir -p "$CCACHE_DIR"
    ccache -M 50G -F 0 &>/dev/null
    ccache -o compression=true &>/dev/null

    echo "Attempting to restore ccache from rclone..."
    if retry_rc rclone copy "$rclonedir/$rclonefile" "." ; then
        tar -xzf "$rclonefile"
        rm -rf "$rclonefile"
        echo "ccache restored successfully to $CCACHE_DIR"
        xc -s2 "(CI: ccache restored)"
    else
        rm -rf "$rclonefile"
        echo "No ccache archive found. Skipping restore."
        xc -s2 "(CI: No ccache found)"
    fi
    cd -
}

save_cache() {
    if [ "$use_ccache" != "true" ]; then
        echo "Skipping save_cache (use_ccache is not true)"
        return 0
    fi
    cd /tmp
    export CCACHE_DISABLE=1
    echo "Saving ccache..."
    ccache -s
    ccache --cleanup --zero-stats

    echo "Creating ccache archive..."    
    tar -czf "$rclonefile" ccache --warning=no-file-changed || {
        echo "Failed to create ccache archive!"
        xc -x "(CI: ccache archive creation failed)"
        return 1
    }

    echo "Uploading ccache archive to rclone..."
    if retry_rc rclone copy "$rclonefile" "$rclonedir" ; then
        echo "ccache saved successfully to $rclonedir"
        xc -s2 "(CI: ccache saved)"
    else
        echo "Failed to upload ccache archive!"
        xc -s2 "(CI: ccache save failed)"        
        return 1
    fi
    cd -
}

_use_rbe() {
    git clone -q https://github.com/rovars/reclient
    unset USE_CCACHE CCACHE_EXEC CCACHE_DIR USE_GOMA

    export USE_RBE=1 RBE_DIR="reclient"
    export RBE_CXX_EXEC_STRATEGY="remote_local_fallback"
    export RBE_JAVAC_EXEC_STRATEGY="remote_local_fallback"
    export RBE_R8_EXEC_STRATEGY="remote_local_fallback"
    export RBE_D8_EXEC_STRATEGY="remote_local_fallback"
    export RBE_JAVAC=1 RBE_R8=1 RBE_D8=1
    export RBE_use_unified_cas_ops="true"
    export RBE_use_unified_downloads="true"
    export RBE_use_unified_uploads="true"
    export RBE_instance="rovars.buildbuddy.io"
    export RBE_service="rovars.buildbuddy.io:443"
    export RBE_remote_headers="x-buildbuddy-api-key=yaDX7CznLv0XcEqk0wee"
    export RBE_use_rpc_credentials="false"
    export RBE_service_no_auth="true"

    local rbex_logs="/tmp/rbelogs"
    mkdir -p "$rbex_logs"
    export RBE_log_dir="$rbex_logs" RBE_output_dir="$rbex_logs" RBE_proxy_log_dir="$rbex_logs"
}

main() {
    case "${1:-}" in
        sync)
            xc -s "( <a href='https://cirrus-ci.com/task/${CIRRUS_TASK_ID}'>Cirrus CI</a> ) - $CIRRUS_COMMIT_MESSAGE ( $CIRRUS_BRANCH )"
            setup_src
            ;;
        build) build_src ;;
        upload) upload_src ;;
        setup_cache) setup_cache ;;
        save_cache) save_cache ;;
        *)
            echo "Error: Invalid argument. Usage: $0 {sync|build|upload|setup_cache|save_cache}" >&2
            exit 1
            ;;
    esac
}

main "$@"