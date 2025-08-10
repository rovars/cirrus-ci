#!/usr/bin/env bash
set -e

CI_DIR="$PWD"
WORKDIR="$CI_DIR/android"
CACHE_DIR="$HOME/.ccache"

source "$CI_DIR/setup.sh"

main() {
    mkdir -p "$CACHE_DIR" "$WORKDIR"
    cd "$WORKDIR"
    case "${1:-}" in
        sync)   setup_workspace ;;
        build)  build_src ;;
        upload) upload_artifact ;;
        cache-pull) pull_cache ;;
        cache-push) push_cache ;;
        *)
            echo "Error: Invalid argument." >&2
            echo "Usage: $0 {sync|build|upload|cache-pull|cache-push}" >&2
            exit 1
            ;;
    esac
}

retry() {
    local -r max_retries=5
    local -r delay=10
    for ((i=1; i<=max_retries; i++)); do
        "$@" && return 0
        (( i < max_retries )) && sleep "$delay"
    done
    return 1
}

pull_cache() {
    [[ "$USE_CACHE" != "true" ]] && return 0
    if retry rclone copy "$RCLONE_REMOTE/$ARCHIVE_NAME" "$HOME" --progress; then
        if [[ -f "$HOME/$ARCHIVE_NAME" ]]; then
            (
                cd "$HOME"
                rm -rf .ccache
                tar -xzf "$ARCHIVE_NAME"
                rm -f "$ARCHIVE_NAME"
            )
        fi
    fi
}

push_cache() {
    [[ "$USE_CACHE" != "true" || ! -d "$CACHE_DIR" ]] && return 0
    export CCACHE_DISABLE=1
    ccache --cleanup
    ccache --zero-stats
    (
        cd "$HOME"
        tar -czf "$ARCHIVE_NAME" .ccache --warning=no-file-changed
        retry rclone copy "$ARCHIVE_NAME" "$RCLONE_REMOTE" --progress
        rm -f "$ARCHIVE_NAME"
    )
    unset CCACHE_DISABLE
}

main "$@"