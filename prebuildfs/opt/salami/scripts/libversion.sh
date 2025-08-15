#!/bin/sh
# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# Library for managing versions strings

# shellcheck disable=SC1091

# Load Generic Libraries
. /opt/salami/scripts/liblog.sh

# Functions
########################
# Gets semantic version
# Arguments:
#   $1 - version: string to extract major.minor.patch
#   $2 - section: 1 to extract major, 2 to extract minor, 3 to extract patch
# Returns:
#   Prints the requested section or error
#########################
get_sematic_version() {
    version="${1:?version is required}"
    section="${2:?section is required}"

    # Use POSIX sh and sed/awk to extract version sections
    # Accepts versions like 1.2.3, 1.2, 1
    # Extract major, minor, patch
    major=$(echo "$version" | awk -F. '{print $1}')
    minor=$(echo "$version" | awk -F. '{print (NF>=2)?$2:"0"}')
    patch=$(echo "$version" | awk -F. '{print (NF>=3)?$3:"0"}')

    case "$section" in
        1) echo "$major" ;;
        2) echo "$minor" ;;
        3) echo "$patch" ;;
        *)
            stderr_print "Section allowed values are: 1, 2, and 3"
            return 1
            ;;
    esac
}