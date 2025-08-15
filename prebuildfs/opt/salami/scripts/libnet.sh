#!/bin/sh
# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# Library for network functions

# shellcheck disable=SC1091

# Load Generic Libraries
. /opt/salami/scripts/liblog.sh
. /opt/salami/scripts/libvalidations.sh

# Functions

dns_lookup() {
    host="${1:?host is missing}"
    ip_version="${2:-}"
    getent "ahosts${ip_version}" "$host" | awk '/STREAM/ {print $1 }' | head -n 1
}

wait_for_dns_lookup() {
    hostname="${1:?hostname is missing}"
    retries="${2:-5}"
    seconds="${3:-1}"
    check_host() {
        [ -n "$(dns_lookup "$hostname")" ]
    }
    # Wait for the host to be ready
    retry_while "check_host" "$retries" "$seconds"
    dns_lookup "$hostname"
}

get_machine_ip() {
    hostname="$(hostname)"
    ip_addresses="$(dns_lookup "$hostname" | xargs echo)"
    set -- $ip_addresses
    if [ "$#" -gt 1 ]; then
        warn "Found more than one IP address associated to hostname ${hostname}: $*, will use $1"
    elif [ "$#" -lt 1 ]; then
        error "Could not find any IP address associated to hostname ${hostname}"
        exit 1
    fi
    # Check if the first IP address is IPv6 to add brackets
    if validate_ipv6 "$1" ; then
        echo "[$1]"
    else
        echo "$1"
    fi
}

is_hostname_resolved() {
    host="${1:?missing value}"
    if [ -n "$(dns_lookup "$host")" ]; then
        return 0
    else
        return 1
    fi
}

parse_uri() {
    uri="${1:?uri is missing}"
    component="${2:?component is missing}"

    # Only basic parsing for POSIX sh; advanced regexes and BASH_REMATCH are not available
    case "$component" in
        scheme)
            echo "$uri" | sed -n 's,^\([a-zA-Z0-9+.-]*\)://.*,\1,p'
            ;;
        authority)
            echo "$uri" | sed -n 's,^[a-zA-Z0-9+.-]*://\([^/]*\).*,\1,p'
            ;;
        host)
            echo "$uri" | sed -n 's,^[a-zA-Z0-9+.-]*://\([^/@]*@\)\?\([^/:?#]*\).*,\2,p'
            ;;
        port)
            echo "$uri" | sed -n 's,^[a-zA-Z0-9+.-]*://[^/:?#]*:\([0-9]*\).*,\1,p'
            ;;
        path)
            echo "$uri" | sed -n 's,^[a-zA-Z0-9+.-]*://[^/]*\(/[^?#]*\).*,\1,p'
            ;;
        query)
            echo "$uri" | sed -n 's,^[^?]*?\([^#]*\).*,\1,p'
            ;;
        fragment)
            echo "$uri" | sed -n 's,^[^#]*#\(.*\),\1,p'
            ;;
        *)
            stderr_print "unrecognized component $component"
            return 1
            ;;
    esac
}

wait_for_http_connection() {
    url="${1:?missing url}"
    retries="${2:-}"
    sleep_time="${3:-}"
    if ! retry_while "debug_execute curl --silent ${url}" "$retries" "$sleep_time"; then
        error "Could not connect to ${url}"
        return 1
    fi
}