#!/usr/bin/env bash
set -e

export USE_DEX2OAT_DEBUG=false
export WITH_DEXPREOPT_DEBUG_INFO=false
export NINJA_HIGHMEM_NUM_JOBS=1

source "$PWD/build.sh"

set_ccache_vars() {
    export USE_CCACHE=1
    export CCACHE_EXEC="$(command -v ccache)"
    export CCACHE_DIR="$HOME/.ccache"
    ccache -M 50G -F 0
}

retry_rc() {
    local max_retries=20
    local delay=5
    local attempt=1
    
    while [[ $attempt -le $max_retries ]]; do
        "$@" && return 0
        [[ $attempt -lt $max_retries ]] && sleep "$delay"
        ((attempt++))
    done
    return 1
}

copy_cache() {
    mkdir -p ~/.ccache
    cd ~/
    set_ccache_vars
    if retry_rc rclone copy "$rclonedir/$rclonefile" . --progress; then
        tar -xzf "$rclonefile" -C .
        rm -f "$rclonefile"
    else
        rm -f "$rclonefile"
        xc -x "no remote ccache!"
    fi
}

save_cache() {
    export CCACHE_DISABLE=1
    ccache -s    
    ccache --cleanup
    ccache --zero-stats

    cd ~/
    tar -czf "$rclonefile" -C . .ccache --warning=no-file-changed || {
        xc -x "Failed to create cache archive"
        return 1
    }

    if retry_rc rclone copy "$rclonefile" "$rclonedir" --progress; then
        rm -f "$rclonefile"
    else
        xc -x "Failed to copy cache to remote"
        return 1
    fi
}

set_remote_vars() {
git clone -q https://github.com/rovars/reclient
mkdir -p /tmp/rbe_log_dir

unset USE_CCACHE CCACHE_EXEC CCACHE_DIR USE_GOMA

export USE_RBE=1
export RBE_DIR="reclient"
export RBE_instance="rovars.buildbuddy.io"
export RBE_service="rovars.buildbuddy.io:443"
export RBE_remote_headers="x-buildbuddy-api-key=yaDX7CznLv0XcEqk0wee"

export RBE_R8_EXEC_STRATEGY=remote_local_fallback
export RBE_CXX_EXEC_STRATEGY=remote_local_fallback
export RBE_D8_EXEC_STRATEGY=remote_local_fallback
export RBE_JAVAC_EXEC_STRATEGY=remote_local_fallback
export RBE_JAR_EXEC_STRATEGY=remote_local_fallback
export RBE_ZIP_EXEC_STRATEGY=remote_local_fallback
export RBE_TURBINE_EXEC_STRATEGY=remote_local_fallback
export RBE_SIGNAPK_EXEC_STRATEGY=remote_local_fallback
export RBE_CXX_LINKS_EXEC_STRATEGY=remote_local_fallback
export RBE_ABI_LINKER_EXEC_STRATEGY=remote_local_fallback
export RBE_CLANG_TIDY_EXEC_STRATEGY=remote_local_fallback
export RBE_METALAVA_EXEC_STRATEGY=remote_local_fallback
export RBE_LINT_EXEC_STRATEGY=remote_local_fallback
export RBE_ABI_DUMPER_EXEC_STRATEGY=""

export RBE_JAVAC=1
export RBE_R8=1
export RBE_D8=1
export RBE_JAR=1
export RBE_ZIP=1
export RBE_TURBINE=1
export RBE_SIGNAPK=1
export RBE_CXX_LINKS=1
export RBE_CXX=1
export RBE_ABI_LINKER=1
export RBE_CLANG_TIDY=1
export RBE_METALAVA=1
export RBE_LINT=1
export RBE_ABI_DUMPER=""

export RBE_JAVA_POOL=default
export RBE_METALAVA_POOL=default
export RBE_LINT_POOL=default
export RBE_log_dir="/tmp/rbe_log_dir"
export RBE_output_dir="/tmp/rbe_log_dir"
export RBE_proxy_log_dir="/tmp/rbe_log_dir"
export RBE_service_no_auth=true
export RBE_use_rpc_credentials=false
export RBE_use_unified_cas_ops=true
export RBE_use_unified_downloads=true
export RBE_use_unified_uploads=true
export RBE_use_application_default_credentials=true
}

main() {
    cd "$SRC_DIR"
    case "${1:-}" in
        sync) setup_src ;;
        build) build_src ;;
        upload) upload_src ;;
        copy_cache) copy_cache ;;
        save_cache) save_cache ;;
        *)
            echo "Error: Invalid argument." >&2
            echo "Usage: $0 {sync|build|upload|copy_cache|save_cache}" >&2
            exit 1
            ;;
    esac
}

main "$@"