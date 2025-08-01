#!/bin/bash

MAX_RETRY=3
RETRY_DELAY=10

BASE_DIR="${BASE_DIR:-$(pwd)}"
CCACHE_DIR="${CCACHE_DIR:-$BASE_DIR/cache}"
CCACHE_ARCHIVE="$BASE_DIR/cache/ccache-losq.tar.gz"
CCACHE_REMOTE="me:rom"

setupCcache() {
    echo "[INFO] Preparing ccache directory at $CCACHE_DIR..."
    mkdir -p "$CCACHE_DIR"

    echo "[INFO] Downloading ccache archive from remote..."
    retry=0
    until [ "$retry" -ge "$MAX_RETRY" ]; do
        rclone copy "$CCACHE_REMOTE/ccache.tar.gz" "$BASE_DIR/cache" --progress && break
        retry=$((retry + 1))
        echo "[WARN] Failed to download ccache (attempt: $retry/$MAX_RETRY), retrying..."
        sleep "$RETRY_DELAY"
    done

    local archive_path="${BASE_DIR}/cache/ccache.tar.gz"
    if [ ! -f "$archive_path" ]; then
        echo "[WARN] No ccache archive found. Skipping extraction."
        return
    fi

    echo "[INFO] Extracting ccache archive..."
    if ! tar --use-compress-program=unpigz -xf "$archive_path" -C "$CCACHE_DIR"; then
        echo "[ERROR] Failed to extract ccache. Removing corrupted archive..."
        rm -f "$archive_path"
    else
        echo "[INFO] Ccache extracted successfully."
    fi
}

saveCcache() {
    echo "[INFO] Compressing ccache..."
    if ! tar --use-compress-program=pigz -cf "$CCACHE_ARCHIVE" -C "$CCACHE_DIR" .; then
        echo "[ERROR] Failed to compress ccache."
        return 1
    fi

    echo "[INFO] Uploading ccache to remote..."
    retry=0
    until [ "$retry" -ge "$MAX_RETRY" ]; do
        rclone copy "$CCACHE_ARCHIVE" "$CCACHE_REMOTE" --progress && break
        retry=$((retry + 1))
        echo "[WARN] Upload failed (attempt: $retry/$MAX_RETRY), retrying..."
        sleep "$RETRY_DELAY"
    done

    if [ "$retry" -ge "$MAX_RETRY" ]; then
        echo "[ERROR] Upload failed after $MAX_RETRY retries."
        return 1
    fi
    echo "[INFO] Ccache uploaded successfully."
}

case "$1" in
    -c|--create|--setup)
        setupCcache
        ;;
    -s|--save)
        saveCcache
        ;;
    *)
        echo "Usage: $0 [-c|--setup] | [-s|--save]"
        exit 1
        ;;
esac