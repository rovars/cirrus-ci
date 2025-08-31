#!/usr/bin/env bash

retry() {
    local -r max_retries=5
    local -r delay=10
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
    mkdir -p ~/cache
    if retry rclone copy "$rclonedir/$rclonefile" ~/ --progress; then
        tar -xzf ~/"$rclonefile" -C ~/ || { tle -t "Failed to extract cache"; return 1; }
        rm -f ~/"$rclonefile"
        tle -t "Cache copied and extracted successfully"
    else
        rm -f ~/"$rclonefile"
        tle -t "Cache not found on remote, proceeding without cache"
    fi
}

save_cache() {
    tle -t "Saving cache to remote..."
    ccache --cleanup
    ccache --zero-stats

    if ! tar -czf ~/"$rclonefile" -C ~/ cache --warning=no-file-changed; then 
        tle -t "Failed to create cache archive"
        return 1
    fi

    if retry rclone copy ~/"$rclonefile" "$rclonedir" --progress; then
        rm -f ~/"$rclonefile"
        tle -t "Ccache Save Completed!"
        return 0
    else
        tle -t "Failed to copy cache to remote"
        return 1
    fi
}

setup_ccache() {
    export USE_CCACHE=1
    export CCACHE_EXEC="$(command -v ccache)"
    export CCACHE_DIR=~/cache
    ccache -M 50G -F 0
    ccache -o compression=true
}

make_time_out() {
    local build_cmd="$*"
    eval "$build_cmd" &
    local pid=$!
    
    while kill -0 $pid 2>/dev/null; do
        if ! sleep 5m; then
            break
        fi
        kill -TERM -$pid 2>/dev/null
        sleep 3
        kill -KILL -$pid 2>/dev/null
        sleep 2
        save_cache
        return
    done    
    
    wait $pid
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then       
        return $exit_code
    fi
}