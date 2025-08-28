#!/usr/bin/env bash
set -e

CI_DIR="$PWD"
WORKDIR="$CI_DIR/android"
CACHE_DIR="$HOME/.ccache"

source "$CI_DIR/utils.sh"
source "$CI_DIR/build.sh"

main() {
    mkdir -p "$CACHE_DIR" "$WORKDIR"
    cd "$WORKDIR"
    case "${1:-}" in
        sync)   setup_src ;;
        build)  build_src ;;
        upload) upload_src ;;
        copy_cache) copy_cache ;;
        save_cache) save_cache ;;
        *)
            echo "Error: Invalid argument." >&2
            echo "Usage: $0 {sync|build|upload|copy_cache|save_cache}" >&2
            exit 1
            ;;
    esac
}

main "$@"