#!/bin/bash

MAX_RETRY=3
RETRY_DELAY=10

BASE_DIR="${BASE_DIR:-$(pwd)}"
CCACHE_DIR="${CCACHE_DIR:-$BASE_DIR/cache}"
CCACHE_ARCHIVE="$BASE_DIR/ccache-losq.tar.gz"
CCACHE_REMOTE="me:rom"

setupCcache() {
    echo "[INFO] Preparing ccache directory at $CCACHE_DIR..."
    mkdir -p "$CCACHE_DIR"

    echo "[INFO] Downloading ccache archive to $BASE_DIR..."
    retry=0
    until [ "$retry" -ge "$MAX_RETRY" ]; do
        rclone copy "$CCACHE_REMOTE/ccache.tar.gz" "$BASE_DIR" --progress && break
        retry=$((retry + 1))
        echo "[WARN] Failed to download ccache (attempt: $retry/$MAX_RETRY), retrying in $RETRY_DELAY sec..."
        sleep "$RETRY_DELAY"
    done

    if [ ! -f "$CCACHE_ARCHIVE" ]; then
        echo "[WARN] No ccache archive found after retries. Skipping extraction."
        return
    fi

    echo "[INFO] Extracting $CCACHE_ARCHIVE to $CCACHE_DIR..."
    if ! tar --use-compress-program=unpigz -xf "$CCACHE_ARCHIVE" -C "$CCACHE_DIR"; then
        echo "[ERROR] Failed to extract ccache. Removing corrupted archive..."
        rm -f "$CCACHE_ARCHIVE"
    else
        echo "[INFO] Ccache extracted successfully."
    fi
}

saveCcache() {
    echo "[INFO] Compressing $CCACHE_DIR to $CCACHE_ARCHIVE..."
    if ! tar --use-compress-program=pigz -cf "$CCACHE_ARCHIVE" -C "$CCACHE_DIR" .; then
        echo "[ERROR] Compression failed. Aborting upload."
        return 1
    fi

    echo "[INFO] Uploading ccache archive to remote..."
    retry=0
    until [ "$retry" -ge "$MAX_RETRY" ]; do
        rclone copy "$CCACHE_ARCHIVE" "$CCACHE_REMOTE" --progress && break
        retry=$((retry + 1))
        echo "[WARN] Upload failed (attempt: $retry/$MAX_RETRY), retrying..."
        sleep "$RETRY_DELAY"
    done

    if [ "$retry" -ge "$MAX_RETRY" ]; then
        echo "[ERROR] Upload failed after $MAX_RETRY attempts."
        return 1
    fi

    echo "[INFO] Ccache successfully uploaded."
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