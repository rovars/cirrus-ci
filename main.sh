#!/usr/bin/env bash
set -e

export USE_DEX2OAT_DEBUG=false
export WITH_DEXPREOPT_DEBUG_INFO=false
export NINJA_HIGHMEM_NUM_JOBS=1
export DISABLE_ROBO_RUN_TESTS=true
export TZ=Asia/Jakarta

source "$PWD/build.sh"

set_ccache_vars() {
    export USE_CCACHE=1
    export CCACHE_EXEC="$(command -v ccache)"
    export CCACHE_DIR="$HOME/.ccache"
    ccache -M 50G -F 0
    ccache -o compression=true
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
    if retry_rc rclone copy "$rclonedir/$rclonefile" . &> /dev/null; then
        tar -xzf "$rclonefile" -C .
        rm -f "$rclonefile"
        echo "setup ccache done!"
    else
        rm -f "$rclonefile"
        echo "no ccache? skip"
        xc -x "no ccache? skip"
    fi
}

save_cache() {
    export CCACHE_DISABLE=1
    ccache -s    
    ccache --cleanup
    ccache --zero-stats

    cd ~/
    tar -czf "$rclonefile" -C . .ccache --warning=no-file-changed || {
        xc -x "create ccache archive failure!"
        return 1
    }

    if retry_rc rclone copy "$rclonefile" "$rclonedir" &> /dev/null; then
        rm -f "$rclonefile"
        echo "ccache save done!"
    else
        echo "ccache not save!"
        xc -x "ccache not save!"
        return 1
    fi
}

set_remote_vars() {
    git clone -q https://github.com/rovars/reclient

    unset USE_CCACHE CCACHE_EXEC CCACHE_DIR USE_GOMA

    export USE_RBE=1 RBE_DIR="reclient" RBE_instance="rovars.buildbuddy.io" RBE_service="rovars.buildbuddy.io:443" RBE_remote_headers="x-buildbuddy-api-key=yaDX7CznLv0XcEqk0wee"
    export RBE_R8_EXEC_STRATEGY=remote_local_fallback RBE_CXX_EXEC_STRATEGY=remote_local_fallback RBE_D8_EXEC_STRATEGY=remote_local_fallback RBE_JAVAC_EXEC_STRATEGY=remote_local_fallback
    export RBE_JAR_EXEC_STRATEGY=remote_local_fallback RBE_ZIP_EXEC_STRATEGY=remote_local_fallback RBE_TURBINE_EXEC_STRATEGY=remote_local_fallback RBE_SIGNAPK_EXEC_STRATEGY=remote_local_fallback
    export RBE_CXX_LINKS_EXEC_STRATEGY=remote_local_fallback RBE_ABI_LINKER_EXEC_STRATEGY=remote_local_fallback RBE_CLANG_TIDY_EXEC_STRATEGY=remote_local_fallback RBE_METALAVA_EXEC_STRATEGY=remote_local_fallback
    export RBE_LINT_EXEC_STRATEGY=remote_local_fallback RBE_ABI_DUMPER_EXEC_STRATEGY=""
    export RBE_JAVAC=1 RBE_R8=1 RBE_D8=1 RBE_JAR=1 RBE_ZIP=1 RBE_TURBINE=1 RBE_SIGNAPK=1 RBE_CXX_LINKS=1 RBE_CXX=1
    export RBE_ABI_LINKER=1 RBE_CLANG_TIDY=1 RBE_METALAVA=1 RBE_LINT=1 RBE_ABI_DUMPER=""
    export RBE_JAVA_POOL=default RBE_METALAVA_POOL=default RBE_LINT_POOL=default
    export RBE_log_dir="/tmp" RBE_output_dir="/tmp" RBE_proxy_log_dir="/tmp"
    export RBE_service_no_auth=true RBE_use_rpc_credentials=false RBE_use_unified_cas_ops=true RBE_use_unified_downloads=true
    export RBE_use_unified_uploads=true RBE_use_application_default_credentials=true

    echo "(RBE) setup done!"
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