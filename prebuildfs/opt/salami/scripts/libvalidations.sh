#!/bin/sh
# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# Validation functions library

# shellcheck disable=SC1091,SC2086

# Load Generic Libraries
. /opt/salami/scripts/liblog.sh

# Functions

########################
# Check if the provided argument is an integer
# Arguments:
#   $1 - Value to check
# Returns:
#   Boolean
#########################
is_int() {
    int="${1:?missing value}"
    case "$int" in
        -[0-9]*|[0-9]*) true ;;
        *) false ;;
    esac
}

########################
# Check if the provided argument is a positive integer
# Arguments:
#   $1 - Value to check
# Returns:
#   Boolean
#########################
is_positive_int() {
    int="${1:?missing value}"
    if is_int "$int" && [ "$int" -ge 0 ] 2>/dev/null; then
        true
    else
        false
    fi
}

########################
# Check if the provided argument is a boolean or is the string 'yes/true'
# Arguments:
#   $1 - Value to check
# Returns:
#   Boolean
#########################
is_boolean_yes() {
    bool="${1:-}"
    case "$bool" in
        1|[Yy][Ee][Ss]|[Tt][Rr][Uu][Ee]) true ;;
        *) false ;;
    esac
}

########################
# Check if the provided argument is a boolean yes/no value
# Arguments:
#   $1 - Value to check
# Returns:
#   Boolean
#########################
is_yes_no_value() {
    bool="${1:-}"
    case "$bool" in
        [Yy][Ee][Ss]|[Nn][Oo]) true ;;
        *) false ;;
    esac
}

########################
# Check if the provided argument is a boolean true/false value
# Arguments:
#   $1 - Value to check
# Returns:
#   Boolean
#########################
is_true_false_value() {
    bool="${1:-}"
    case "$bool" in
        [Tt][Rr][Uu][Ee]|[Ff][Aa][Ll][Ss][Ee]) true ;;
        *) false ;;
    esac
}

########################
# Check if the provided argument is a boolean 1/0 value
# Arguments:
#   $1 - Value to check
# Returns:
#   Boolean
#########################
is_1_0_value() {
    bool="${1:-}"
    case "$bool" in
        1|0) true ;;
        *) false ;;
    esac
}

########################
# Check if the provided argument is an empty string or not defined
# Arguments:
#   $1 - Value to check
# Returns:
#   Boolean
#########################
is_empty_value() {
    val="${1:-}"
    [ -z "$val" ]
}

########################
# Validate if the provided argument is a valid port
# Arguments:
#   $1 - Port to validate
# Returns:
#   Boolean and error message
#########################
validate_port() {
    unprivileged=0

    # Parse flags
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -unprivileged)
                unprivileged=1
                ;;
            --)
                shift
                break
                ;;
            -*)
                stderr_print "unrecognized flag $1"
                return 1
                ;;
            *)
                break
                ;;
        esac
        shift
    done

    if [ "$#" -gt 1 ]; then
        echo "too many arguments provided"
        return 2
    elif [ "$#" -eq 0 ]; then
        stderr_print "missing port argument"
        return 1
    else
        value=$1
    fi

    if [ -z "$value" ]; then
        echo "the value is empty"
        return 1
    else
        if ! is_int "$value"; then
            echo "value is not an integer"
            return 2
        elif [ "$value" -lt 0 ]; then
            echo "negative value provided"
            return 2
        elif [ "$value" -gt 65535 ]; then
            echo "requested port is greater than 65535"
            return 2
        elif [ "$unprivileged" = 1 ] && [ "$value" -lt 1024 ]; then
            echo "privileged port requested"
            return 3
        fi
    fi
}

########################
# Validate if the provided argument is a valid IPv6 address
# Arguments:
#   $1 - IP to validate
# Returns:
#   Boolean
#########################
validate_ipv6() {
    ip="${1:?ip is missing}"
    # Basic check for IPv6 format (not exhaustive)
    case "$ip" in
        *:*:*:*:*:*:*:*) true ;;
        ::) true ;;
        *) false ;;
    esac
}

########################
# Validate if the provided argument is a valid IPv4 address
# Arguments:
#   $1 - IP to validate
# Returns:
#   Boolean
#########################
validate_ipv4() {
    ip="${1:?ip is missing}"
    stat=1
    if echo "$ip" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
        set -- $(echo "$ip" | tr '.' ' ')
        if [ "$1" -le 255 ] && [ "$2" -le 255 ] && [ "$3" -le 255 ] && [ "$4" -le 255 ]; then
            stat=0
        fi
    fi
    return $stat
}

########################
# Validate if the provided argument is a valid IPv4 or IPv6 address
# Arguments:
#   $1 - IP to validate
# Returns:
#   Boolean
#########################
validate_ip() {
    ip="${1:?ip is missing}"
    if validate_ipv4 "$ip"; then
        return 0
    elif validate_ipv6 "$ip"; then
        return 0
    else
        return 1
    fi
}

########################
# Validate a string format
# Arguments:
#   $1 - String to validate
# Returns:
#   Boolean
#########################
validate_string() {
    string=""
    min_length=-1
    max_length=-1

    # Parse flags
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -min-length)
                shift
                min_length=${1:-}
                ;;
            -max-length)
                shift
                max_length=${1:-}
                ;;
            --)
                shift
                break
                ;;
            -*)
                stderr_print "unrecognized flag $1"
                return 1
                ;;
            *)
                string="$1"
                ;;
        esac
        shift
    done

    if [ "$min_length" -ge 0 ] && [ "$(printf "%s" "$string" | wc -c)" -lt "$min_length" ]; then
        echo "string length is less than $min_length"
        return 1
    fi
    if [ "$max_length" -ge 0 ] && [ "$(printf "%s" "$string" | wc -c)" -gt "$max_length" ]; then
        echo "string length is great than $max_length"
        return 1
    fi
}