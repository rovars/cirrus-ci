#!/usr/bin/env bash

# Add error handling function
handle_error() {
    local exit_code=$?
    tle -t "Error occurred in ${FUNCNAME[1]}: $1"
    return $exit_code
}

retry() {
    local -r max_retries=5
    local -r delay=10
    local attempt=1
    
    while [[ $attempt -le $max_retries ]]; do
        if "$@"; then
            return 0
        fi
        
        tle -t "Attempt $attempt failed. Retrying in $delay seconds..."
        if [[ $attempt -lt $max_retries ]]; then
            sleep "$delay"
        fi
        ((attempt++))
    done
    
    return 1
}

copy_cache() {
    if [[ ! -d "$HOME" ]]; then
        tle -t "HOME directory not found"
        return 1
    fi

    if retry rclone copy "$rclonedir/$rclonefile" "$HOME" --progress; then
        if [[ -f "$HOME/$rclonefile" ]]; then
            (
                cd "$HOME" || { tle -t "Failed to change directory to HOME"; return 1; }
                rm -rf .ccache
                if ! tar -xzf "$rclonefile"; then
                    tle -t "Failed to extract cache"
                    return 1
                fi
                rm -f "$rclonefile"
            )
        fi
    fi
    mkdir -p "$HOME/.ccache"
}

save_cache() {
    export CCACHE_DISABLE=1
    ccache --cleanup
    ccache --zero-stats
    
    (
        cd "$HOME" || { tle -t "Failed to change directory to HOME"; return 1; }
        if ! tar -czf "$rclonefile" .ccache --warning=no-file-changed; then
            tle -t "Failed to create cache archive"
            return 1
        fi
        
        if retry rclone copy "$rclonefile" "$rclonedir" --progress; then
            tle -t "Ccache Save Completed!"
        else
            tle -t "Failed to copy cache to remote"
            return 1
        fi
    )
}

envr_cache() {
    export USE_CCACHE=1
    export CCACHE_EXEC="$(command -v ccache)"
    if [[ -z "$CACHE_DIR" ]]; then
        CACHE_DIR="$HOME/.ccache"
    fi
    export CCACHE_DIR="$CACHE_DIR"
    ccache -M 50G -F 0
    ccache -o compression=true
}

make_time_out() {
    local -r timeout_seconds=1400
    local build_cmd="$*"
    local build_pid
    
    # Start the build command in background
    eval "$build_cmd" &
    build_pid=$!
    
    SECONDS=0
    
    # Monitor the build process
    while kill -0 "$build_pid" 2>/dev/null; do
        if (( SECONDS >= timeout_seconds )); then
            tle -t "Build is taking too long, initiating timeout..."
            
            # Send SIGTERM first
            kill -TERM "$build_pid" 2>/dev/null || true
            
            # Wait a moment for graceful shutdown
            sleep 5
            
            # Force kill if still running
            if kill -0 "$build_pid" 2>/dev/null; then
                kill -KILL "$build_pid" 2>/dev/null || true
            fi
            
            # Try to save cache before exiting
            if ! save_cache; then
                tle -t "Failed to save cache during timeout"
            fi
            
            tle -t "Build timed out after $timeout_seconds seconds"
            return 1
        fi
        sleep 1
    done
    
    # Wait for the build process and get its exit status
    wait "$build_pid"
    local build_status=$?
    
    # If build succeeded, try to save cache
    if [[ $build_status -eq 0 ]]; then
        if ! save_cache; then
            tle -t "Build succeeded but cache save failed"
        fi
    fi
    
    return $build_status
}