#!/bin/bash
set -e

MAX_RETRY=3
RETRY_DELAY=10
RCLONE_REMOTE="me:rom"
ARCHIVE_NAME="ccache-losq.tar.gz"
ARCHIVE_PATH="$HOME/$ARCHIVE_NAME"
CCACHE_DIR="$HOME/.ccache"

retry_command() {
    for i in $(seq 1 "$MAX_RETRY"); do
        "$@" && return 0
        [ "$i" -lt "$MAX_RETRY" ] && sleep "$RETRY_DELAY"
    done
    return 1
}

restoreCache() {
    echo "--> Attempting to restore cache from remote..."
    mkdir -p "$CCACHE_DIR"

    if retry_command rclone copy "$RCLONE_REMOTE/$ARCHIVE_NAME" "$HOME" --progress; then
        echo "--> Cache found. Extracting..."
        tar -xzf "$ARCHIVE_PATH" -C "$HOME"
        echo "--> Cache restored successfully."
        rm -f "$ARCHIVE_PATH"
    else
        echo "--> Cache not found on remote. Skipping restore."
    fi
}

uploadCache() {
    echo "--> Creating archive from cache..."
    tar -czf "$ARCHIVE_PATH" -C "$HOME" .ccache
    echo "--> Uploading cache to remote..."
    retry_command rclone copy "$ARCHIVE_PATH" "$RCLONE_REMOTE" --progress
    echo "--> Cache uploaded successfully."
    rm -f "$ARCHIVE_PATH"
}

case "$1" in
    --restore) restoreCache ;;
    --upload) uploadCache ;;
    *)
        echo "Usage: $0 {--restore|--upload}"
        exit 1
        ;;
esac