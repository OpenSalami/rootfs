#!/bin/sh
# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# Library for logging functions

# Constants
RESET='\033[0m'
RED='\033[38;5;1m'
GREEN='\033[38;5;2m'
YELLOW='\033[38;5;3m'
MAGENTA='\033[38;5;5m'
CYAN='\033[38;5;6m'

# Functions

stderr_print() {
    # 'is_boolean_yes' is defined in libvalidations.sh, but depends on this file so we cannot source it
    bool="${SALAMI_QUIET:-false}"
    case "$bool" in
        1|[Yy][Ee][Ss]|[Tt][Rr][Uu][Ee]) return 0 ;;
        *) printf "%b\n" "$*" >&2 ;;
    esac
}

log() {
    color_bool="${SALAMI_COLOR:-true}"
    if echo "$color_bool" | grep -iqE '^(1|yes|true)$'; then
        stderr_print "${CYAN}${MODULE:-} ${MAGENTA}$(date "+%T.%2N ")${RESET}$*"
    else
        stderr_print "${MODULE:-} $(date "+%T.%2N ")$*"
    fi
}

info() {
    msg_color=""
    color_bool="${SALAMI_COLOR:-true}"
    if echo "$color_bool" | grep -iqE '^(1|yes|true)$'; then
        msg_color="$GREEN"
    fi
    log "${msg_color}INFO ${RESET} ==> $*"
}

warn() {
    msg_color=""
    color_bool="${SALAMI_COLOR:-true}"
    if echo "$color_bool" | grep -iqE '^(1|yes|true)$'; then
        msg_color="$YELLOW"
    fi
    log "${msg_color}WARN ${RESET} ==> $*"
}

error() {
    msg_color=""
    color_bool="${BITNAMI_COLOR:-true}"
    if echo "$color_bool" | grep -iqE '^(1|yes|true)$'; then
        msg_color="$RED"
    fi
    log "${msg_color}ERROR${RESET} ==> $*"
}

debug() {
    msg_color=""
    color_bool="${SALAMI_COLOR:-true}"
    if echo "$color_bool" | grep -iqE '^(1|yes|true)$'; then
        msg_color="$MAGENTA"
    fi
    debug_bool="${BITNAMI_DEBUG:-false}"
    if echo "$debug_bool" | grep -iqE '^(1|yes|true)$'; then
        log "${msg_color}DEBUG${RESET} ==> $*"
    fi
}

indent() {
    string="${1:-}"
    num="${2:?missing num}"
    char="${3:-" "}"
    indent_unit=""
    i=0
    while [ "$i" -lt "$num" ]; do
        indent_unit="${indent_unit}${char}"
        i=$((i+1))
    done
    echo "$string" | sed "s/^/${indent_unit}/"
}