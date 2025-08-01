#!/bin/bash

MAX_RETRY=3
RETRY_DELAY=10  # seconds

setupCcache() {
    echo "[INFO] Preparing ccache directory..."
    mkdir -p "$CCACHE_DIR"

    echo "[INFO] Downloading ccache archive from remote..."
    retry=0
    until [ "$retry" -ge "$MAX_RETRY" ]
    do
        rclone copy "$CCACHE_REMOTE/ccache.tar.gz" "$WORK_DIR" --progress && break
        retry=$((retry + 1))
        echo "[WARN] Failed to download ccache (attempt: $retry/$MAX_RETRY), retrying in $RETRY_DELAY seconds..."
        sleep "$RETRY_DELAY"
    done

    if [ ! -f "$CCACHE_ARCHIVE" ]; then
        echo "[WARN] No ccache archive found after $MAX_RETRY attempts. Skipping extraction."
        return
    fi

    echo "[INFO] Extracting ccache archive..."
    if ! tar --use-compress-program=unpigz -xf "$CCACHE_ARCHIVE" -C "$CCACHE_DIR"; then
        echo "[ERROR] Failed to extract ccache archive. Deleting possibly corrupted file..."
        rm -f "$CCACHE_ARCHIVE"
    else
        echo "[INFO] Ccache extracted successfully."
    fi
}

saveCcache() {
    echo "[INFO] Compressing ccache for upload..."
    if ! tar --use-compress-program=pigz -cf "$CCACHE_ARCHIVE" -C "$CCACHE_DIR" .; then
        echo "[ERROR] Failed to compress ccache. Upload aborted."
        return 1
    fi

    echo "[INFO] Uploading ccache to remote..."
    retry=0
    until [ "$retry" -ge "$MAX_RETRY" ]
    do
        rclone copy "$CCACHE_ARCHIVE" "$CCACHE_REMOTE" --progress && break
        retry=$((retry + 1))
        echo "[WARN] Failed to upload ccache (attempt: $retry/$MAX_RETRY), retrying in $RETRY_DELAY seconds..."
        sleep "$RETRY_DELAY"
    done

    if [ "$retry" -ge "$MAX_RETRY" ]; then
        echo "[ERROR] Failed to upload ccache after $MAX_RETRY attempts."
        return 1
    else
        echo "[INFO] Ccache uploaded successfully."
    fi
}

export -f setupCcache
export -f saveCcache