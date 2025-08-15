#!/bin/sh
# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# Bitnami persistence library
# Used for bringing persistence capabilities to applications that don't have clear separation of data and logic

# shellcheck disable=SC1091

# Load Generic Libraries
. /opt/salami/scripts/libfs.sh
. /opt/salami/scripts/libos.sh
. /opt/salami/scripts/liblog.sh
. /opt/salami/scripts/libversion.sh

# Functions

########################
# Persist an application directory
# Globals:
#   SALAMI_ROOT_DIR
#   SALAMI_VOLUME_DIR
# Arguments:
#   $1 - App folder name
#   $2 - List of app files to persist (comma/semicolon/colon separated)
# Returns:
#   true if all steps succeeded, false otherwise
#########################
persist_app() {
    app="${1:?missing app}"
    files_to_persist_raw="$2"
    install_dir="${SALAMI_ROOT_DIR}/${app}"
    persist_dir="${SALAMI_VOLUME_DIR}/${app}"

    # Split files_to_persist_raw into positional parameters
    old_IFS="$IFS"
    IFS=',;:'
    set -- $files_to_persist_raw
    IFS="$old_IFS"

    if [ "$#" -le 0 ]; then
        warn "No files are configured to be persisted"
        return
    fi

    tmp_file="/tmp/perms.acl"
    (
        cd "$install_dir" >/dev/null || exit 1
        for file_to_persist; do
            if [ ! -f "$file_to_persist" ] && [ ! -d "$file_to_persist" ]; then
                error "Cannot persist '${file_to_persist}' because it does not exist"
                return 1
            fi
            file_to_persist_relative="$(relativize "$file_to_persist" "$install_dir")"
            file_to_persist_destination="${persist_dir}/${file_to_persist_relative}"
            file_to_persist_destination_folder="$(dirname "$file_to_persist_destination")"
            # Get original permissions for existing files, which will be applied later
            # Exclude the root directory with 'sed', to avoid issues when copying the entirety of it to a volume
            getfacl -R "$file_to_persist_relative" | sed -E '/# file: (\..+|[^.])/,$!d' > "$tmp_file"
            # Copy directories to the volume
            ensure_dir_exists "$file_to_persist_destination_folder"
            cp -Lr --preserve=links "$file_to_persist_relative" "$file_to_persist_destination_folder"
            # Restore permissions
            (
                cd "$persist_dir" >/dev/null || exit 1
                if am_i_root; then
                    setfacl --restore="$tmp_file"
                else
                    # When running as non-root, don't change ownership
                    grep -E -v '^# (owner|group):' "$tmp_file" | setfacl --restore=-
                fi
            )
        done
    )
    rm -f "$tmp_file"
    # Install the persisted files into the installation directory, via symlinks
    restore_persisted_app "$@"
}

########################
# Restore a persisted application directory
# Globals:
#   SALAMI_ROOT_DIR
#   SALAMI_VOLUME_DIR
#   FORCE_MAJOR_UPGRADE
# Arguments:
#   $1 - App folder name
#   $2 - List of app files to restore (comma/semicolon/colon separated)
# Returns:
#   true if all steps succeeded, false otherwise
#########################
restore_persisted_app() {
    app="${1:?missing app}"
    files_to_restore_raw="$2"
    install_dir="${SALAMI_ROOT_DIR}/${app}"
    persist_dir="${SALAMI_VOLUME_DIR}/${app}"

    # Split files_to_restore_raw into positional parameters
    old_IFS="$IFS"
    IFS=',;:'
    set -- $files_to_restore_raw
    IFS="$old_IFS"

    if [ "$#" -le 0 ]; then
        warn "No persisted files are configured to be restored"
        return
    fi

    for file_to_restore; do
        file_to_restore_relative="$(relativize "$file_to_restore" "$install_dir")"
        # We use 'realpath --no-symlinks' to ensure that the case of '.' is covered and the directory is removed
        file_to_restore_origin="$(realpath --no-symlinks "${install_dir}/${file_to_restore_relative}")"
        file_to_restore_destination="$(realpath --no-symlinks "${persist_dir}/${file_to_restore_relative}")"
        rm -rf "$file_to_restore_origin"
        ln -sfn "$file_to_restore_destination" "$file_to_restore_origin"
    done
}

########################
# Check if an application directory was already persisted
# Globals:
#   SALAMI_VOLUME_DIR
# Arguments:
#   $1 - App folder name
# Returns:
#   true if all steps succeeded, false otherwise
#########################
is_app_initialized() {
    app="${1:?missing app}"
    persist_dir="${SALAMI_VOLUME_DIR}/${app}"
    if ! is_mounted_dir_empty "$persist_dir"; then
        true
    else
        false
    fi
}