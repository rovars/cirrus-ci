#!/bin/bash

set -e

MAX_RETRY=3
RETRY_DELAY=10

if [ -z "$CCACHE_DIR" ] || [ -z "$CCACHE_ARCHIVE_PATH" ] || [ -z "$CCACHE_REMOTE" ] || [ -z "$CCACHE_ARCHIVE_NAME" ]; then
    echo "[ERROR] Ccache environment variables are not set. Exiting."
    exit 1
fi

restoreCache() {
    echo "[INFO] Preparing ccache directory at $CCACHE_DIR..."
    mkdir -p "$CCACHE_DIR"

    echo "[INFO] Downloading ccache archive from remote..."
    local retry=0
    local archive_dir
    archive_dir="$(dirname "$CCACHE_ARCHIVE_PATH")"
    mkdir -p "$archive_dir"

    until [ "$retry" -ge "$MAX_RETRY" ]; do
        if rclone copy "$CCACHE_REMOTE/$CCACHE_ARCHIVE_NAME" "$archive_dir" --progress; then
            break
        fi
        retry=$((retry + 1))
        echo "[WARN] Download failed (attempt: $retry/$MAX_RETRY), retrying in $RETRY_DELAY seconds..."
        sleep "$RETRY_DELAY"
    done

    if [ ! -f "$CCACHE_ARCHIVE_PATH" ]; then
        echo "[WARN] No ccache archive found. Proceeding with empty cache."
        return
    fi

    echo "[INFO] Extracting archive to $CCACHE_DIR..."
    if tar -xzf "$CCACHE_ARCHIVE_PATH" -C "$CCACHE_DIR"; then
        echo "[INFO] Ccache successfully restored."
        rm -f "$CCACHE_ARCHIVE_PATH"
    else
        echo "[ERROR] Failed to extract archive. Removing corrupted file."
        rm -f "$CCACHE_ARCHIVE_PATH"
    fi
}

uploadCache() {
    echo "[INFO] Checking if $CCACHE_DIR has content..."
    if [ -z "$(ls -A "$CCACHE_DIR")" ]; then
        echo "[WARN] Ccache directory is empty. Skipping compression and upload."
        return
    fi

    echo "[INFO] Compressing $CCACHE_DIR to archive..."
    if ! tar --use-compress-program="pigz -k -1" -cf "$CCACHE_ARCHIVE_PATH" -C "$(dirname "$CCACHE_DIR")" "$(basename "$CCACHE_DIR")"; then
        echo "[ERROR] Compression failed. Skipping upload."
        return 1
    fi

    echo "[INFO] Uploading archive to remote..."
    local retry=0
    until [ "$retry" -ge "$MAX_RETRY" ]; do
        if rclone copy "$CCACHE_ARCHIVE_PATH" "$CCACHE_REMOTE" --progress; then
            break
        fi
        retry=$((retry + 1))
        echo "[WARN] Upload failed (attempt: $retry/$MAX_RETRY), retrying in $RETRY_DELAY seconds..."
        sleep "$RETRY_DELAY"
    done

    if [ "$retry" -ge "$MAX_RETRY" ]; then
        echo "[ERROR] Failed to upload cache after $MAX_RETRY attempts."
        rm -f "$CCACHE_ARCHIVE_PATH"
        return 1
    fi

    echo "[INFO] Ccache archive uploaded successfully."
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
