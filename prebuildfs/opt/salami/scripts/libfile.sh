#!/bin/sh
# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# Library for managing files

# shellcheck disable=SC1091

# Load Generic Libraries
. /opt/salami/scripts/libos.sh

# Functions

replace_in_file() {
    local filename="${1:?filename is required}"
    local match_regex="${2:?match regex is required}"
    local substitute_regex="${3:?substitute regex is required}"
    local posix_regex=${4:-true}
    local result
    # Use a non-printable character as a 'sed' delimiter to avoid issues
    # $'\001' is not POSIX, so use a literal control-A (press Ctrl+V then Ctrl+A) or use another uncommon char
    del="$(printf '\001')"
    if [ "$posix_regex" = true ]; then
        result="$(sed -E "s${del}${match_regex}${del}${substitute_regex}${del}g" "$filename")"
    else
        result="$(sed "s${del}${match_regex}${del}${substitute_regex}${del}g" "$filename")"
    fi
    echo "$result" > "$filename"
}

replace_in_file_multiline() {
    local filename="${1:?filename is required}"
    local match_regex="${2:?match regex is required}"
    local substitute_regex="${3:?substitute regex is required}"
    local result
    del="$(printf '\001')"
    # Perl is not POSIX, but if you require it, keep this line
    result="$(perl -pe "BEGIN{undef \$\/;} s${del}${match_regex}${del}${substitute_regex}${del}sg" "$filename")"
    echo "$result" > "$filename"
}

remove_in_file() {
    local filename="${1:?filename is required}"
    local match_regex="${2:?match regex is required}"
    local posix_regex=${3:-true}
    local result
    if [ "$posix_regex" = true ]; then
        result="$(sed -E "/$match_regex/d" "$filename")"
    else
        result="$(sed "/$match_regex/d" "$filename")"
    fi
    echo "$result" > "$filename"
}

append_file_after_last_match() {
    local file="${1:?missing file}"
    local match_regex="${2:?missing pattern}"
    local value="${3:?missing value}"
    # If tac is not available, use awk as a fallback
    if command -v tac >/dev/null 2>&1; then
        result="$(tac "$file" | sed -E "0,/($match_regex)/s||${value}\n\1|" | tac)"
    else
        result="$(awk -v v="$value" -v r="$match_regex" '
            {a[NR]=$0}
            END{
                for(i=NR;i>=1;i--){
                    if(!found && a[i] ~ r){
                        print v
                        found=1
                    }
                    print a[i]
                }
            }' "$file" | awk '{a[NR]=$0} END{for(i=NR;i>=1;i--)print a[i]}')"
    fi
    echo "$result" > "$file"
}

wait_for_log_entry() {
    local entry="${1:-missing entry}"
    local log_file="${2:-missing log file}"
    local retries="${3:-12}"
    local interval_time="${4:-5}"
    local attempt=0

    check_log_file_for_entry() {
        if ! grep -qE "$entry" "$log_file"; then
            debug "Entry \"${entry}\" still not present in ${log_file} (attempt $(($attempt + 1))/${retries})"
            attempt=$(($attempt + 1))
            return 1
        fi
    }
    debug "Checking that ${log_file} log file contains entry \"${entry}\""
    i=0
    while [ $i -lt "$retries" ]; do
        if check_log_file_for_entry; then
            debug "Found entry \"${entry}\" in ${log_file}"
            return 0
        fi
        sleep "$interval_time"
        i=$((i+1))
    done
    error "Could not find entry \"${entry}\" in ${log_file} after ${retries} retries"
    debug_execute cat "$log_file"
    return 1
}