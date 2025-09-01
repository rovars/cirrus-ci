#!/usr/bin/env bash

retry_rc() {
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

set_cache() {
    export USE_CCACHE=1
    export CCACHE_EXEC="$(command -v ccache)"
    export CCACHE_DIR=~/.ccache
    ccache -M 50G -F 0
    ccache -o compression=true
}

