#!/usr/bin/env bash
set -e

export KBUILD_BUILD_USER=android
export KBUILD_BUILD_HOST=localhost
export BUILD_USERNAME=android
export BUILD_HOSTNAME=localhost

CI_DIR="$PWD"
WORKDIR="$CI_DIR/android"

source "$CI_DIR/utils.sh"
source "$CI_DIR/build.sh"

_nfy_script() {
   tle -t "${CIRRUS_COMMIT_MESSAGE} ( <a href='https://cirrus-ci.com/task/${CIRRUS_TASK_ID}'>$CIRRUS_BRANCH</a> )"
    echo "$credensial" > ~/.git-credentials
    echo "$gitconfigs" > ~/.gitconfig
}

main() {
    mkdir -p "$WORKDIR"
    cd "$WORKDIR"
    case "${1:-}" in
        sync)   
            _nfy_script
            setup_src;;
        build)  
            build_src;;
        upload) 
            upload_src;;
        copy_cache) 
            copy_cache;;
        save_cache) 
            save_cache;;
        results) 
            rbe_metrics;;
        *)
            echo "Error: Invalid argument." >&2
            echo "Usage: $0 {sync|build|upload|copy_cache|save_cache}" >&2
            exit 1;;
    esac
}

main "$@"