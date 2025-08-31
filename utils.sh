#!/usr/bin/env bash

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
    mkdir -p ~/cache
    if rclone copy "$rclonedir/$rclonefile" ~/ --progress; then
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
    tle -t "Setting up ccache..."
    export USE_CCACHE=1
    export CCACHE_EXEC="$(command -v ccache)"
    export CCACHE_DIR=~/cache
    ccache -M 50G -F 0
    ccache -o compression=true
    tle -t "Ccache setup completed"
}

make_time_out() {
    local -r timeout_seconds=1400
    local build_cmd="$*"
    local build_pid
    local build_status

    tle -t "Starting build with timeout: $timeout_seconds seconds"

    eval "$build_cmd" &
    build_pid=$!

    SECONDS=0
    while kill -0 "$build_pid" 2>/dev/null; do
        if (( SECONDS >= timeout_seconds )); then
            tle -t "Build is taking too long, initiating timeout..."
            kill -TERM "$build_pid" 2>/dev/null || true
            sleep 5
            if kill -0 "$build_pid" 2>/dev/null; then
                kill -KILL "$build_pid" 2>/dev/null || true
            fi
            save_cache || tle -t "Failed to save cache during timeout"
            tle -t "Build timed out after $timeout_seconds seconds"
            return 1
        fi
        sleep 1
    done

    wait "$build_pid"
    build_status=$?

    if [[ $build_status -eq 0 ]]; then
        tle -t "Build completed successfully"
    else
        tle -t "Build failed with status $build_status"
    fi

    save_cache || tle -t "Failed to save cache after build"
    return $build_status
}