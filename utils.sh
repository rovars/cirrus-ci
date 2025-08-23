#!/usr/bin/env bash

retry() {
    local -r max_retries=5
    local -r delay=10
    for ((i=1; i<=max_retries; i++)); do
        "$@" && return 0
        (( i < max_retries )) && sleep "$delay"
    done
    return 1
}

copy_cache() {
    if retry rclone copy "$rclonedir/$rclonefile" "$HOME" --progress; then
        if [[ -f "$HOME/$rclonefile" ]]; then
            (
                cd "$HOME"
                rm -rf .ccache
                tar -xzf "$rclonefile"
                rm -f "$rclonefile"      
            )
        fi
    fi
    export USE_CCACHE=1
    export CCACHE_EXEC="$(command -v ccache)"
    export CCACHE_DIR="$CACHE_DIR"
    ccache -M 50G -F 0
    ccache -o compression=true
}

save_cache() {
   export CCACHE_DISABLE=1
    ccache --cleanup
    ccache --zero-stats
    (
        cd "$HOME"
        tar -czf "$rclonefile" .ccache --warning=no-file-changed
        retry rclone copy "$rclonefile" "$rclonedir" --progress
    )
}


mka_time_out() {
   local -r timeout_seconds=5400
   local build_pid=$!
   SECONDS=0

   while kill -0 "$build_pid" &>/dev/null; do
        if (( SECONDS >= timeout_seconds )); then
            kill -s TERM "$build_pid" &>/dev/null || true
            wait "$build_pid" &>/dev/null || true
            save_cache
            tle -t "Build timed out after $timeout_seconds seconds"            
            exit 1
        fi
        sleep 1
    done

    wait "$build_pid"
    local build_status=$?

    exit $build_status
}