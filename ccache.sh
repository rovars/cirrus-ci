#!/bin/bash
set -e

MAX_RETRY=3
RETRY_DELAY=10

CCACHE_DIR=~/ccache
RCLONE_REMOTE=me:rom
ARCHIVE_NAME=ccache-losq.tar.gz
ARCHIVE_FILE=~/$ARCHIVE_NAME

restoreCache() {
    echo "[INFO] Creating ccache directory: $CCACHE_DIR"
    mkdir -p "$CCACHE_DIR"

    echo "[INFO] Downloading archive from: $RCLONE_REMOTE/$ARCHIVE_NAME to home"
    local retry=0
    until [ "$retry" -ge "$MAX_RETRY" ]; do
        if rclone copy "$RCLONE_REMOTE/$ARCHIVE_NAME" ~ --progress; then
            break
        fi
        retry=$((retry + 1))
        echo "[WARN] Download failed (attempt $retry/$MAX_RETRY), retrying in $RETRY_DELAY seconds..."
        sleep "$RETRY_DELAY"
    done

    if [ ! -f "$ARCHIVE_FILE" ]; then
        echo "[WARN] Archive not found at $ARCHIVE_FILE. Skipping restore."
        return
    fi

    echo "[INFO] Extracting archive to home"
    if tar -xzf "$ARCHIVE_FILE" -C ~; then
        echo "[INFO] Restore completed."
        rm -f "$ARCHIVE_FILE"
    else
        echo "[ERROR] Failed to extract archive. Removing $ARCHIVE_FILE"
        rm -f "$ARCHIVE_FILE"
    fi
}

uploadCache() {
    echo "[INFO] Checking cache directory: $CCACHE_DIR"
    if [ ! -d "$CCACHE_DIR" ] || [ -z "$(ls -A "$CCACHE_DIR" 2>/dev/null)" ]; then
        echo "[WARN] Cache directory is empty. Skipping upload."
        return
    fi

    echo "[INFO] Creating archive: $ARCHIVE_FILE"
    if ! tar -czf "$ARCHIVE_FILE" -C ~ ccache; then
        echo "[ERROR] Archive creation failed. Upload canceled."
        return 1
    fi

    echo "[INFO] Uploading archive to remote: $RCLONE_REMOTE"
    local retry=0
    until [ "$retry" -ge "$MAX_RETRY" ]; do
        if rclone copy "$ARCHIVE_FILE" "$RCLONE_REMOTE" --progress; then
            break
        fi
        retry=$((retry + 1))
        echo "[WARN] Upload failed (attempt $retry/$MAX_RETRY). Retrying in $RETRY_DELAY seconds..."
        sleep "$RETRY_DELAY"
    done

    if [ "$retry" -ge "$MAX_RETRY" ]; then
        echo "[ERROR] Upload failed after $MAX_RETRY attempts. Removing archive."
        rm -f "$ARCHIVE_FILE"
        return 1
    fi

    echo "[INFO] Upload completed. Cleaning up local archive."
    rm -f "$ARCHIVE_FILE"
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

