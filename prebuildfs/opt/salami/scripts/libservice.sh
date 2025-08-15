#!/bin/sh
# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# Library for managing services

# shellcheck disable=SC1091

# Load Generic Libraries
. /opt/salami/scripts/libvalidations.sh
. /opt/salami/scripts/liblog.sh

# Functions

########################
# Read the provided pid file and returns a PID
# Arguments:
#   $1 - Pid file
# Returns:
#   PID
#########################
get_pid_from_file() {
    pid_file="${1:?pid file is missing}"

    if [ -f "$pid_file" ]; then
        pid="$(cat "$pid_file")"
        if [ -n "$pid" ] && [ "$pid" -gt 0 ] 2>/dev/null; then
            echo "$pid"
        fi
    fi
}

########################
# Check if a provided PID corresponds to a running service
# Arguments:
#   $1 - PID
# Returns:
#   Boolean
#########################
is_service_running() {
    pid="${1:?pid is missing}"
    kill -0 "$pid" 2>/dev/null
}

########################
# Stop a service by sending a termination signal to its pid
# Arguments:
#   $1 - Pid file
#   $2 - Signal number (optional)
# Returns:
#   None
#########################
stop_service_using_pid() {
    pid_file="${1:?pid file is missing}"
    signal="${2:-}"
    pid="$(get_pid_from_file "$pid_file")"
    if [ -z "$pid" ] || ! is_service_running "$pid"; then
        return
    fi

    if [ -n "$signal" ]; then
        kill "-${signal}" "$pid"
    else
        kill "$pid"
    fi

    counter=10
    while [ "$counter" -ne 0 ] && is_service_running "$pid"; do
        sleep 1
        counter=$((counter - 1))
    done
}

########################
# Start cron daemon
# Arguments:
#   None
# Returns:
#   true if started correctly, false otherwise
#########################
cron_start() {
    if [ -x "/usr/sbin/cron" ]; then
        /usr/sbin/cron
    elif [ -x "/usr/sbin/crond" ]; then
        /usr/sbin/crond
    else
        false
    fi
}

########################
# Generate a cron configuration file for a given service
# Arguments:
#   $1 - Service name
#   $2 - Command
# Flags:
#   --run-as - User to run as (default: root)
#   --schedule - Cron schedule configuration (default: * * * * *)
# Returns:
#   None
#########################
generate_cron_conf() {
    service_name="${1:?service name is missing}"
    cmd="${2:?command is missing}"
    run_as="root"
    schedule="* * * * *"
    clean="true"

    # Parse optional CLI flags
    shift 2
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --run-as)
                shift
                run_as="$1"
                ;;
            --schedule)
                shift
                schedule="$1"
                ;;
            --no-clean)
                clean="false"
                ;;
            *)
                echo "Invalid command line flag ${1}" >&2
                return 1
                ;;
        esac
        shift
    done

    mkdir -p /etc/cron.d
    if [ "$clean" = "true" ]; then
        cat > "/etc/cron.d/${service_name}" <<EOF
# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0

${schedule} ${run_as} ${cmd}
EOF
    else
        echo "${schedule} ${run_as} ${cmd}" >> /etc/cron.d/"$service_name"
    fi
}

########################
# Remove a cron configuration file for a given service
# Arguments:
#   $1 - Service name
# Returns:
#   None
#########################
remove_cron_conf() {
    service_name="${1:?service name is missing}"
    cron_conf_dir="/etc/monit/conf.d"
    rm -f "${cron_conf_dir}/${service_name}"
}

########################
# Generate a monit configuration file for a given service
# Arguments:
#   $1 - Service name
#   $2 - Pid file
#   $3 - Start command
#   $4 - Stop command
# Flags:
#   --disable - Whether to disable the monit configuration
# Returns:
#   None
#########################
generate_monit_conf() {
    service_name="${1:?service name is missing}"
    pid_file="${2:?pid file is missing}"
    start_command="${3:?start command is missing}"
    stop_command="${4:?stop command is missing}"
    monit_conf_dir="/etc/monit/conf.d"
    disabled="no"
    conf_suffix=""

    # Parse optional CLI flags
    shift 4
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --disable)
                disabled="yes"
                ;;
            *)
                echo "Invalid command line flag ${1}" >&2
                return 1
                ;;
        esac
        shift
    done

    is_boolean_yes "$disabled" && conf_suffix=".disabled"
    mkdir -p "$monit_conf_dir"
    cat > "${monit_conf_dir}/${service_name}.conf${conf_suffix}" <<EOF
# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0

check process ${service_name}
  with pidfile "${pid_file}"
  start program = "${start_command}" with timeout 90 seconds
  stop program = "${stop_command}" with timeout 90 seconds
EOF
}

########################
# Remove a monit configuration file for a given service
# Arguments:
#   $1 - Service name
# Returns:
#   None
#########################
remove_monit_conf() {
    service_name="${1:?service name is missing}"
    monit_conf_dir="/etc/monit/conf.d"
    rm -f "${monit_conf_dir}/${service_name}.conf"
}

########################
# Generate a logrotate configuration file
# Arguments:
#   $1 - Service name
#   $2 - Log files pattern
# Flags:
#   --period - Period
#   --rotations - Number of rotations to store
#   --extra - Extra options (Optional)
# Returns:
#   None
#########################
generate_logrotate_conf() {
    service_name="${1:?service name is missing}"
    log_path="${2:?log path is missing}"
    period="weekly"
    rotations="150"
    extra=""
    logrotate_conf_dir="/etc/logrotate.d"
    # Parse optional CLI flags
    shift 2
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --period)
                shift
                period="${1:?period is missing}"
                ;;
            --rotations)
                shift
                rotations="${1:?rotations is missing}"
                ;;
            --extra)
                shift
                extra="${1:?extra is missing}"
                ;;
            *)
                echo "Invalid command line flag ${1}" >&2
                return 1
                ;;
        esac
        shift
    done

    mkdir -p "$logrotate_conf_dir"
    cat <<EOF | sed '/^\s*$/d' > "${logrotate_conf_dir}/${service_name}"
# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0

${log_path} {
  ${period}
  rotate ${rotations}
  dateext
  compress
  copytruncate
  missingok
$(indent "$extra" 2)
}
EOF
}

########################
# Remove a logrotate configuration file
# Arguments:
#   $1 - Service name
# Returns:
#   None
#########################
remove_logrotate_conf() {
    service_name="${1:?service name is missing}"
    logrotate_conf_dir="/etc/logrotate.d"
    rm -f "${logrotate_conf_dir}/${service_name}"
}

########################
# Generate a Systemd configuration file
# Arguments:
#   $1 - Service name
# Flags:
#   --custom-service-content - Custom content to add to the [service] block
#   --environment - Environment variable to define (multiple --environment options may be passed)
#   --environment-file - Text file with environment variables (multiple --environment-file options may be passed)
#   --exec-start - Start command (required)
#   --exec-start-pre - Pre-start command (optional)
#   --exec-start-post - Post-start command (optional)
#   --exec-stop - Stop command (optional)
#   --exec-reload - Reload command (optional)
#   --group - System group to start the service with
#   --name - Service full name (e.g. Apache HTTP Server, defaults to $1)
#   --restart - When to restart the Systemd service after being stopped (defaults to always)
#   --pid-file - Service PID file
#   --standard-output - File where to print stdout output
#   --standard-error - File where to print stderr output
#   --success-exit-status - Exit code that indicates a successful shutdown
#   --type - Systemd unit type (defaults to forking)
#   --user - System user to start the service with
#   --working-directory - Working directory at which to start the service
# Returns:
#   None
#########################
generate_systemd_conf() {
    service_name="${1:?service name is missing}"
    systemd_units_dir="/etc/systemd/system"
    service_file="${systemd_units_dir}/bitnami.${service_name}.service"
    # Default values
    name="$service_name"
    type="forking"
    user=""
    group=""
    environment=""
    environment_file=""
    exec_start=""
    exec_start_pre=""
    exec_start_post=""
    exec_stop=""
    exec_reload=""
    restart="always"
    pid_file=""
    standard_output="journal"
    standard_error=""
    limits_content=""
    success_exit_status=""
    custom_service_content=""
    working_directory=""

    # Parse CLI flags
    shift
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --name|--type|--user|--group|--exec-start|--exec-stop|--exec-reload|--restart|--pid-file|--standard-output|--standard-error|--success-exit-status|--custom-service-content|--working-directory)
                var_name=$(echo "$1" | sed -e "s/^--//" -e "s/-/_/g")
                shift
                eval "$var_name=\"\${1:?${var_name} value is missing}\""
                ;;
            --limit-*)
                var_name=$(echo "$1" | sed -e "s/^--limit-//" -e "s/-/_/g")
                shift
                limits_content="${limits_content}Limit$(echo "$var_name" | tr '[:lower:]' '[:upper:]')=${1:?--limit-${var_name} value is missing}\n"
                ;;
            --exec-start-pre)
                shift
                if [ -n "$exec_start_pre" ]; then
                    exec_start_pre="${exec_start_pre}\n"
                fi
                exec_start_pre="${exec_start_pre}ExecStartPre=${1:?--exec-start-pre value is missing}"
                ;;
            --exec-start-post)
                shift
                if [ -n "$exec_start_post" ]; then
                    exec_start_post="${exec_start_post}\n"
                fi
                exec_start_post="${exec_start_post}ExecStartPost=${1:?--exec-start-post value is missing}"
                ;;
            --environment)
                shift
                if [ -n "$environment" ]; then
                    environment="${environment}\n"
                fi
                environment="${environment}Environment=${1:?--environment value is missing}"
                ;;
            --environment-file)
                shift
                if [ -n "$environment_file" ]; then
                    environment_file="${environment_file}\n"
                fi
                environment_file="${environment_file}EnvironmentFile=${1:?--environment-file value is missing}"
                ;;
            *)
                echo "Invalid command line flag ${1}" >&2
                return 1
                ;;
        esac
        shift
    done

    # Validate inputs
    error="no"
    if [ -z "$exec_start" ]; then
        error "The --exec-start option is required"
        error="yes"
    fi
    if [ "$error" != "no" ]; then
        return 1
    fi

    # Generate the Systemd unit
    mkdir -p "$systemd_units_dir"
    {
        echo "# Copyright Broadcom, Inc. All Rights Reserved."
        echo "# SPDX-License-Identifier: APACHE-2.0"
        echo
        echo "[Unit]"
        echo "Description=Bitnami service for ${name}"
        echo "# Starting/stopping the main bitnami service should cause the same effect for this service"
        echo "PartOf=bitnami.service"
        echo
        echo "[Service]"
        echo "Type=${type}"
        [ -n "$working_directory" ] && echo "WorkingDirectory=${working_directory}"
        [ -n "$exec_start_pre" ] && printf "%b\n" "$exec_start_pre"
        [ -n "$exec_start" ] && echo "ExecStart=${exec_start}"
        [ -n "$exec_start_post" ] && printf "%b\n" "$exec_start_post"
        [ -n "$exec_stop" ] && echo "ExecStop=${exec_stop}"
        [ -n "$exec_reload" ] && echo "ExecReload=${exec_reload}"
        [ -n "$user" ] && echo "User=${user}"
        [ -n "$group" ] && echo "Group=${group}"
        [ -n "$pid_file" ] && echo "PIDFile=${pid_file}"
        [ -n "$restart" ] && echo "Restart=${restart}"
        [ -n "$environment" ] && printf "%b\n" "$environment"
        [ -n "$environment_file" ] && printf "%b\n" "$environment_file"
        [ -n "$standard_output" ] && echo "StandardOutput=${standard_output}"
        [ -n "$standard_error" ] && echo "StandardError=${standard_error}"
        [ -n "$custom_service_content" ] && printf "%b\n" "$custom_service_content"
        [ -n "$success_exit_status" ] && {
            echo "# When the process receives a SIGTERM signal, it exits with code ${success_exit_status}"
            echo "SuccessExitStatus=${success_exit_status}"
        }
        echo "# Optimizations"
        echo "TimeoutStartSec=2min"
        echo "TimeoutStopSec=30s"
        echo "IgnoreSIGPIPE=no"
        echo "KillMode=mixed"
        [ -n "$limits_content" ] && {
            echo "# Limits"
            printf "%b\n" "$limits_content"
        }
        echo
        echo "[Install]"
        echo "# Enabling/disabling the main bitnami service should cause the same effect for this service"
        echo "WantedBy=bitnami.service"
    } > "$service_file"
}