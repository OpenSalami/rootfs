#!/bin/sh
# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# Library for operating system actions

# shellcheck disable=SC1091

# Load Generic Libraries
. /opt/salami/scripts/liblog.sh
. /opt/salami/scripts/libfs.sh
. /opt/salami/scripts/libvalidations.sh

# Functions

user_exists() {
    user="${1:?user is missing}"
    id "$user" >/dev/null 2>&1
}

group_exists() {
    group="${1:?group is missing}"
    getent group "$group" >/dev/null 2>&1
}

ensure_group_exists() {
    group="${1:?group is missing}"
    gid=""
    is_system_user=false

    shift 1
    while [ "$#" -gt 0 ]; do
        case "$1" in
        -i | --gid)
            shift
            gid="${1:?missing gid}"
            ;;
        -s | --system)
            is_system_user=true
            ;;
        *)
            echo "Invalid command line flag $1" >&2
            return 1
            ;;
        esac
        shift
    done

    if ! group_exists "$group"; then
        args=""
        if [ -n "$gid" ]; then
            if group_exists "$gid"; then
                error "The GID $gid is already in use." >&2
                return 1
            fi
            args="$args --gid $gid"
        fi
        if [ "$is_system_user" = true ]; then
            args="$args --system"
        fi
        groupadd $args "$group" >/dev/null 2>&1
    fi
}

ensure_user_exists() {
    user="${1:?user is missing}"
    uid=""
    group=""
    append_groups=""
    home=""
    is_system_user=false

    shift 1
    while [ "$#" -gt 0 ]; do
        case "$1" in
        -i | --uid)
            shift
            uid="${1:?missing uid}"
            ;;
        -g | --group)
            shift
            group="${1:?missing group}"
            ;;
        -a | --append-groups)
            shift
            append_groups="${1:?missing append_groups}"
            ;;
        -h | --home)
            shift
            home="${1:?missing home directory}"
            ;;
        -s | --system)
            is_system_user=true
            ;;
        *)
            echo "Invalid command line flag $1" >&2
            return 1
            ;;
        esac
        shift
    done

    if ! user_exists "$user"; then
        user_args="-N"
        if [ -n "$uid" ]; then
            if user_exists "$uid"; then
                error "The UID $uid is already in use."
                return 1
            fi
            user_args="$user_args --uid $uid"
        elif [ "$is_system_user" = true ]; then
            user_args="$user_args --system"
        fi
        useradd $user_args "$user" >/dev/null 2>&1
    fi

    if [ -n "$group" ]; then
        group_args="$group"
        if [ "$is_system_user" = true ]; then
            group_args="$group_args --system"
        fi
        ensure_group_exists $group_args
        usermod -g "$group" "$user" >/dev/null 2>&1
    fi

    if [ -n "$append_groups" ]; then
        # Split on , or ;
        old_IFS="$IFS"
        IFS=',;'
        set -- $append_groups
        IFS="$old_IFS"
        for group in "$@"; do
            ensure_group_exists "$group"
            usermod -aG "$group" "$user" >/dev/null 2>&1
        done
    fi

    if [ -n "$home" ]; then
        mkdir -p "$home"
        usermod -d "$home" "$user" >/dev/null 2>&1
        configure_permissions_ownership "$home" -d "775" -f "664" -u "$user" -g "$group"
    fi
}

am_i_root() {
    if [ "$(id -u)" = "0" ]; then
        true
    else
        false
    fi
}

get_os_metadata() {
    flag_name="${1:?missing flag}"
    get_os_release_metadata() {
        env_name="${1:?missing environment variable name}"
        (
            . /etc/os-release
            eval "echo \${$env_name}"
        )
    }
    case "$flag_name" in
    --id)
        get_os_release_metadata ID
        ;;
    --version)
        get_os_release_metadata VERSION_ID
        ;;
    --branch)
        get_os_release_metadata VERSION_ID | sed 's/\..*//'
        ;;
    --codename)
        get_os_release_metadata VERSION_CODENAME
        ;;
    --name)
        get_os_release_metadata NAME
        ;;
    --pretty-name)
        get_os_release_metadata PRETTY_NAME
        ;;
    *)
        error "Unknown flag ${flag_name}"
        return 1
        ;;
    esac
}

get_total_memory() {
    echo $(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024))
}

get_machine_size() {
    memory=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --memory)
            shift
            memory="${1:?missing memory}"
            ;;
        *)
            echo "Invalid command line flag $1" >&2
            return 1
            ;;
        esac
        shift
    done
    if [ -z "$memory" ]; then
        debug "Memory was not specified, detecting available memory automatically"
        memory="$(get_total_memory)"
    fi
    sanitized_memory=$(convert_to_mb "$memory")
    if [ "$sanitized_memory" -gt 26000 ]; then
        echo 2xlarge
    elif [ "$sanitized_memory" -gt 13000 ]; then
        echo xlarge
    elif [ "$sanitized_memory" -gt 6000 ]; then
        echo large
    elif [ "$sanitized_memory" -gt 3000 ]; then
        echo medium
    elif [ "$sanitized_memory" -gt 1500 ]; then
        echo small
    else
        echo micro
    fi
}

get_supported_machine_sizes() {
    echo micro small medium large xlarge 2xlarge
}

convert_to_mb() {
    amount="${1:-}"
    case "$amount" in
        *[mM])
            echo "${amount%[mM]}"
            ;;
        *[gG])
            num="${amount%[gG]}"
            echo $((num * 1024))
            ;;
        *)
            echo "$amount"
            ;;
    esac
}

debug_execute() {
    if is_boolean_yes "${BITNAMI_DEBUG:-false}"; then
        "$@"
    else
        "$@" >/dev/null 2>&1
    fi
}

retry_while() {
    cmd="${1:?cmd is missing}"
    retries="${2:-12}"
    sleep_time="${3:-5}"
    return_value=1

    i=1
    while [ "$i" -le "$retries" ]; do
        sh -c "$cmd" && return_value=0 && break
        sleep "$sleep_time"
        i=$((i+1))
    done
    return $return_value
}

generate_random_string() {
    type="ascii"
    count="32"
    filter=""
    result=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
        -t | --type)
            shift
            type="$1"
            ;;
        -c | --count)
            shift
            count="$1"
            ;;
        *)
            echo "Invalid command line flag $1" >&2
            return 1
            ;;
        esac
        shift
    done
    case "$type" in
    ascii)
        filter="[:print:]"
        ;;
    numeric)
        filter="0-9"
        ;;
    alphanumeric)
        filter="a-zA-Z0-9"
        ;;
    alphanumeric+special|special+alphanumeric)
        filter='a-zA-Z0-9:@.,/+!='
        ;;
    *)
        echo "Invalid type ${type}" >&2
        return 1
        ;;
    esac
    result="$(head -n "$((count + 10))" /dev/urandom | tr -dc "$filter" | head -c "$count")"
    echo "$result"
}

generate_md5_hash() {
    str="${1:?missing input string}"
    echo -n "$str" | md5sum | awk '{print $1}'
}

generate_sha_hash() {
    str="${1:?missing input string}"
    algorithm="${2:-1}"
    echo -n "$str" | "sha${algorithm}sum" | awk '{print $1}'
}

convert_to_hex() {
    str=${1:?missing input string}
    i=0
    len=$(printf "%s" "$str" | wc -c)
    while [ "$i" -lt "$len" ]; do
        char=$(printf "%s" "$str" | cut -c $((i+1)))
        printf '%x' "'$char"
        i=$((i+1))
    done
}

get_boot_time() {
    stat /proc --format=%Y
}

get_machine_id() {
    machine_id=""
    if [ -f /etc/machine-id ]; then
        machine_id="$(cat /etc/machine-id)"
    fi
    if [ -z "$machine_id" ]; then
        machine_id="$(get_boot_time)"
    fi
    echo "$machine_id"
}

get_disk_device_id() {
    device_id=""
    if grep -q ^/dev /proc/mounts; then
        device_id="$(grep ^/dev /proc/mounts | awk '$2 == "/" { print $1 }' | tail -1)"
    fi
    if [ -z "$device_id" ] || [ ! -b "$device_id" ]; then
        device_id="/dev/sda1"
    fi
    echo "$device_id"
}

get_root_disk_device_id() {
    get_disk_device_id | sed -E 's/p?[0-9]+$//'
}

get_root_disk_size() {
    fdisk -l "$(get_root_disk_device_id)" | grep 'Disk.*bytes' | sed -E 's/.*, ([0-9]+) bytes,.*/\1/' || true
}

run_as_user() {
    run_chroot "$@"
}

exec_as_user() {
    run_chroot --replace-process "$@"
}

run_chroot() {
    userspec=""
    user=""
    homedir=""
    replace=false
    cwd="$(pwd)"

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -r | --replace-process)
                replace=true
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

    if [ "$#" -lt 2 ]; then
        echo "expected at least 2 arguments"
        return 1
    else
        userspec=$1
        shift
        user=$(echo "$userspec" | cut -d':' -f1)
    fi

    if ! am_i_root; then
        error "Could not switch to '${userspec}': Operation not permitted"
        return 1
    fi

    homedir=$(eval echo "~${user}")
    if [ ! -d "$homedir" ]; then
        homedir="${HOME:-/}"
    fi

    if [ "$replace" = true ]; then
        exec chroot --userspec="$userspec" / sh -c "cd ${cwd}; export HOME=${homedir}; exec \"\$@\"" -- "$@"
    else
        chroot --userspec="$userspec" / sh -c "cd ${cwd}; export HOME=${homedir}; exec \"\$@\"" -- "$@"
    fi
}