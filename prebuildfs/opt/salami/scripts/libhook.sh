#!/bin/sh
# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# Library to use for scripts expected to be used as Kubernetes lifecycle hooks

# shellcheck disable=SC1091

# Load generic libraries
. /opt/salami/scripts/liblog.sh
. /opt/salami/scripts/libos.sh

# POSIX sh does not support 'declare -f' or function overriding via eval.
# Instead, redefine the functions directly to redirect output to process 1.

stderr_print() {
    printf "%s\n" "$*" >/proc/1/fd/2
}

debug_execute() {
    # This is a simple passthrough; adjust as needed for your actual debug_execute logic
    "$@" >/proc/1/fd/1 2>/proc/1/fd/2
}