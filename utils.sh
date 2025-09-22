#!/usr/bin/env bash

retry_rc() {
    local -r max_retries=20
    local -r delay=5
    local attempt=1
    while [[ $attempt -le $max_retries ]]; do
        if "$@"; then
            return 0
        fi
        if [[ $attempt -lt $max_retries ]]; then
            sleep "$delay"
        fi
        ((attempt++))
    done
    return 1
}

copy_cache() {
    mkdir -p ~/.ccache
    cd ~/ && \
    if retry_rc rclone copy "$rclonedir/$rclonefile" . --progress; then
        tar -xzf "$rclonefile" -C .
        rm -f "$rclonefile"
        tle -t "Cache copied and extracted successfully"
    else
        rm -f "$rclonefile"
        tle -t "Cache not found on remote, proceeding without cache"
    fi
}

save_cache() {
    tle -t "Saving cache to remote..."
    export CCACHE_DISABLE=1
    ccache -s    
    ccache --cleanup
    ccache --zero-stats
    
    cd ~/ && \
    if ! tar -czf "$rclonefile" -C . .ccache --warning=no-file-changed; then
        tle -t "Failed to create cache archive"
        return 1
    fi

    if retry_rc rclone copy "$rclonefile" "$rclonedir" --progress; then
        rm -f "$rclonefile"
        tle -t "Ccache Save Completed!"
        return 0
    else
        tle -t "Failed to copy cache to remote"
        return 1
    fi
}

set_ccache_vars() {
    export USE_CCACHE=1
    export CCACHE_EXEC="$(command -v ccache)"
    export CCACHE_DIR="$HOME/.ccache"
    ccache -M 50G -F 0
    ccache -o compression=true
}

unset_ccache_vars() {
    unset USE_CCACHE
    unset CCACHE_EXEC
    unset CCACHE_DIR
    unset USE_GOMA
}

set_rbeenv_vars() {
    git clone -q https://github.com/rovars/reclient reclient

    unset_ccache_vars   

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
    export RBE_ABI_DUMPER=""
    export RBE_CLANG_TIDY=1
    export RBE_METALAVA=1
    export RBE_LINT=1

    export RBE_JAVA_POOL=default
    export RBE_METALAVA_POOL=default
    export RBE_LINT_POOL=default

    export RBE_log_dir="/tmp"
    export RBE_output_dir="/tmp"
    export RBE_proxy_log_dir="/tmp"

    export RBE_service_no_auth=true
    export RBE_use_rpc_credentials=false
    export RBE_use_unified_cas_ops=true
    export RBE_use_unified_downloads=true
    export RBE_use_unified_uploads=true
    export RBE_use_application_default_credentials=true
}

rbe_metrics() {
   tle -f /tmp/rbe_metrics.txt
   cat /tmp/rbe_metrics.txt
}
