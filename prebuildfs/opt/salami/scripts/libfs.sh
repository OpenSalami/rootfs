#!/bin/sh
# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# Library for file system actions

# shellcheck disable=SC1091

# Load Generic Libraries
. /opt/salami/scripts/liblog.sh

# Functions

owned_by() {
    local path="${1:?path is missing}"
    local owner="${2:?owner is missing}"
    local group="${3:-}"

    if [ -n "$group" ]; then
        chown "$owner":"$group" "$path"
    else
        chown "$owner":"$owner" "$path"
    fi
}

ensure_dir_exists() {
    local dir="${1:?directory is missing}"
    local owner_user="${2:-}"
    local owner_group="${3:-}"

    [ -d "${dir}" ] || mkdir -p "${dir}"
    if [ -n "$owner_user" ]; then
        owned_by "$dir" "$owner_user" "$owner_group"
    fi
}

is_dir_empty() {
    local path="${1:?missing directory}"
    # Calculate real path in order to avoid issues with symlinks
    local dir
    dir="$(realpath "$path")"
    if [ ! -e "$dir" ] || [ -z "$(ls -A "$dir")" ]; then
        return 0
    else
        return 1
    fi
}

is_mounted_dir_empty() {
    local dir="${1:?missing directory}"

    if is_dir_empty "$dir" || find "$dir" -mindepth 1 -maxdepth 1 -not -name ".snapshot" -not -name "lost+found" -exec false {} +; then
        return 0
    else
        return 1
    fi
}

is_file_writable() {
    local file="${1:?missing file}"
    local dir
    dir="$(dirname "$file")"

    if { [ -f "$file" ] && [ -w "$file" ]; } || { [ ! -f "$file" ] && [ -d "$dir" ] && [ -w "$dir" ]; }; then
        return 0
    else
        return 1
    fi
}

relativize() {
    local path="${1:?missing path}"
    local base="${2:?missing base}"
    (cd "$base" >/dev/null 2>&1 && realpath -q --no-symlinks --relative-base="$base" "$path" | sed -e 's|^/$|.|' -e 's|^/||')
}

configure_permissions_ownership() {
    local paths="${1:?paths is missing}"
    local dir_mode=""
    local file_mode=""
    local user=""
    local group=""

    shift 1
    while [ "$#" -gt 0 ]; do
        case "$1" in
        -f | --file-mode)
            shift
            file_mode="${1:?missing mode for files}"
            ;;
        -d | --dir-mode)
            shift
            dir_mode="${1:?missing mode for directories}"
            ;;
        -u | --user)
            shift
            user="${1:?missing user}"
            ;;
        -g | --group)
            shift
            group="${1:?missing group}"
            ;;
        *)
            echo "Invalid command line flag $1" >&2
            return 1
            ;;
        esac
        shift
    done

    # Split paths string into positional parameters
    set -- $paths
    for p in "$@"; do
        if [ -e "$p" ]; then
            # find -L "$p" -printf "" # Not POSIX, so skip or replace as needed
            if [ -n "$dir_mode" ]; then
                find -L "$p" -type d ! -perm "$dir_mode" -print0 | xargs -r -0 chmod "$dir_mode"
            fi
            if [ -n "$file_mode" ]; then
                find -L "$p" -type f ! -perm "$file_mode" -print0 | xargs -r -0 chmod "$file_mode"
            fi
            if [ -n "$user" ] && [ -n "$group" ]; then
                find -L "$p" -print0 | xargs -r -0 chown "${user}:${group}"
            elif [ -n "$user" ] && [ -z "$group" ]; then
                find -L "$p" -print0 | xargs -r -0 chown "${user}"
            elif [ -z "$user" ] && [ -n "$group" ]; then
                find -L "$p" -print0 | xargs -r -0 chgrp "${group}"
            fi
        else
            stderr_print "$p does not exist"
        fi
    done
}