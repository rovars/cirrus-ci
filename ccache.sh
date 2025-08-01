#!/bin/bash

set -e

MAX_RETRY=3
RETRY_DELAY=15

if [ -z "$CCACHE_DIR" ] || [ -z "$CCACHE_ARCHIVE_PATH" ] || [ -z "$CCACHE_REMOTE" ] || [ -z "$CCACHE_ARCHIVE_NAME" ]; then
    echo "[ERROR] Ccache environment variables are not set. Exiting."
    exit 1
fi

restoreCache() {
    echo "[INFO] Preparing ccache directory at $CCACHE_DIR..."
    mkdir -p "$CCACHE_DIR"

    echo "[INFO] Downloading ccache archive from remote..."
    local retry=0
    until [ "$retry" -ge "$MAX_RETRY" ]; do
        rclone copy "$CCACHE_REMOTE/$CCACHE_ARCHIVE_NAME" "$(dirname "$CCACHE_ARCHIVE_PATH")" --progress && break
        retry=$((retry + 1))
        echo "[WARN] Download failed (attempt: $retry/$MAX_RETRY), retrying in $RETRY_DELAY seconds..."
        sleep "$RETRY_DELAY"
    done

    if [ ! -f "$CCACHE_ARCHIVE_PATH" ]; then
        echo "[WARN] No ccache archive found after retries. A new cache will be created."
        return
    fi

    echo "[INFO] Extracting $CCACHE_ARCHIVE_PATH to $CCACHE_DIR..."
    if tar --use-compress-program=unpigz -xf "$CCACHE_ARCHIVE_PATH" -C "$CCACHE_DIR"; then
        echo "[INFO] Ccache restored successfully."
        rm -f "$CCACHE_ARCHIVE_PATH"
    else
        echo "[ERROR] Failed to extract ccache. Removing corrupted archive..."
        rm -f "$CCACHE_ARCHIVE_PATH"
    fi
}

uploadCache() {
    echo "[INFO] Compressing $CCACHE_DIR to $CCACHE_ARCHIVE_PATH..."
    if ! tar --use-compress-program=pigz -cf "$CCACHE_ARCHIVE_PATH" -C "$CCACHE_DIR" .; then
        echo "[ERROR] Ccache compression failed. Aborting upload."
        return 1
    fi

    echo "[INFO] Uploading ccache archive to remote..."
    local retry=0
    until [ "$retry" -ge "$MAX_RETRY" ]; do
        rclone copy "$CCACHE_ARCHIVE_PATH" "$CCACHE_REMOTE" --progress && break
        retry=$((retry + 1))
        echo "[WARN] Upload failed (attempt: $retry/$MAX_RETRY), retrying in $RETRY_DELAY seconds..."
        sleep "$RETRY_DELAY"
    done

    if [ "$retry" -ge "$MAX_RETRY" ]; then
        echo "[ERROR] Upload failed after $MAX_RETRY attempts."
        rm -f "$CCACHE_ARCHIVE_PATH"
        return 1
    fi

    echo "[INFO] Ccache successfully uploaded."
    rm -f "$CCACHE_ARCHIVE_PATH"
}

case "$1" in
    --restore)
        restoreCache
        ;;
    --upload)
        uploadCache
        ;;
    *)
        echo "Usage: $0 {--restore|--upload}"
        exit 1
        ;;
esac