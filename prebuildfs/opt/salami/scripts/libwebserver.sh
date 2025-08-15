#!/bin/sh
# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# Bitnami web server handler library

# shellcheck disable=SC1090,SC1091

# Load generic libraries
. /opt/bitnami/scripts/liblog.sh

########################
# Execute a command (or list of commands) with the web server environment and library loaded
# Globals:
#   *
# Arguments:
#   None
# Returns:
#   None
#########################
web_server_execute() {
    web_server="${1:?missing web server}"
    shift
    (
        . "/opt/salami/scripts/lib${web_server}.sh"
        . "/opt/salami/scripts/${web_server}-env.sh"
        "$@"
    )
}

########################
# Prints the list of enabled web servers
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#########################
web_server_list() {
    supported_web_servers="apache nginx"
    existing_web_servers=""
    for web_server in $supported_web_servers; do
        if [ -f "/opt/salami/scripts/${web_server}-env.sh" ]; then
            existing_web_servers="$existing_web_servers $web_server"
        fi
    done
    # Remove leading space
    echo "$existing_web_servers" | sed 's/^ //'
}

########################
# Prints the currently-enabled web server type (only one, in order of preference)
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#########################
web_server_type() {
    set -- $(web_server_list)
    echo "${1:-}"
}

########################
# Validate that a supported web server is configured
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#########################
web_server_validate() {
    error_code=0
    supported_web_servers="apache nginx"

    print_validation_error() {
        error "$1"
        error_code=1
    }

    web_type="$(web_server_type)"
    found=0
    for ws in $supported_web_servers; do
        [ "$ws" = "$web_type" ] && found=1
    done
    if [ -z "$web_type" ] || [ "$found" -eq 0 ]; then
        print_validation_error "Could not detect any supported web servers. It must be one of: $supported_web_servers"
    elif ! web_server_execute "$web_type" type -t "is_${web_type}_running" >/dev/null 2>&1; then
        print_validation_error "Could not load the $web_type web server library from /opt/bitnami/scripts. Check that it exists and is readable."
    fi

    return "$error_code"
}

########################
# Check whether the web server is running
# Globals:
#   *
# Arguments:
#   None
# Returns:
#   true if the web server is running, false otherwise
#########################
is_web_server_running() {
    web_type="$(web_server_type)"
    "is_${web_type}_running"
}

########################
# Start web server
# Globals:
#   *
# Arguments:
#   None
# Returns:
#   None
#########################
web_server_start() {
    info "Starting $(web_server_type) in background"
    if [ "${BITNAMI_SERVICE_MANAGER:-}" = "systemd" ]; then
        systemctl start "bitnami.$(web_server_type).service"
    else
        "${BITNAMI_ROOT_DIR}/scripts/$(web_server_type)/start.sh"
    fi
}

########################
# Stop web server
# Globals:
#   *
# Arguments:
#   None
# Returns:
#   None
#########################
web_server_stop() {
    info "Stopping $(web_server_type)"
    if [ "${BITNAMI_SERVICE_MANAGER:-}" = "systemd" ]; then
        systemctl stop "bitnami.$(web_server_type).service"
    else
        "${BITNAMI_ROOT_DIR}/scripts/$(web_server_type)/stop.sh"
    fi
}

########################
# Restart web server
# Globals:
#   *
# Arguments:
#   None
# Returns:
#   None
#########################
web_server_restart() {
    info "Restarting $(web_server_type)"
    if [ "${BITNAMI_SERVICE_MANAGER:-}" = "systemd" ]; then
        systemctl restart "bitnami.$(web_server_type).service"
    else
        "${BITNAMI_ROOT_DIR}/scripts/$(web_server_type)/restart.sh"
    fi
}

########################
# Reload web server
# Globals:
#   *
# Arguments:
#   None
# Returns:
#   None
#########################
web_server_reload() {
    if [ "${BITNAMI_SERVICE_MANAGER:-}" = "systemd" ]; then
        systemctl reload "bitnami.$(web_server_type).service"
    else
        "${BITNAMI_ROOT_DIR}/scripts/$(web_server_type)/reload.sh"
    fi
}

########################
# Ensure a web server application configuration exists (i.e. Apache virtual host format or NGINX server block)
# It serves as a wrapper for the specific web server function
# Globals:
#   *
# Arguments:
#   $1 - App name
# Flags:
#   --type - Application type, which has an effect on which configuration template to use
#   --hosts - Host listen addresses
#   --server-name - Server name
#   --server-aliases - Server aliases
#   --allow-remote-connections - Whether to allow remote connections or to require local connections
#   --disable - Whether to render server configurations with a .disabled prefix
#   --disable-http - Whether to render the app's HTTP server configuration with a .disabled prefix
#   --disable-https - Whether to render the app's HTTPS server configuration with a .disabled prefix
#   --http-port - HTTP port number
#   --https-port - HTTPS port number
#   --document-root - Path to document root directory
# Apache-specific flags:
#   --apache-additional-configuration - Additional vhost configuration (no default)
#   --apache-additional-http-configuration - Additional HTTP vhost configuration (no default)
#   --apache-additional-https-configuration - Additional HTTPS vhost configuration (no default)
#   --apache-before-vhost-configuration - Configuration to add before the <VirtualHost> directive (no default)
#   --apache-allow-override - Whether to allow .htaccess files (only allowed when --move-htaccess is set to 'no' and type is not defined)
#   --apache-extra-directory-configuration - Extra configuration for the document root directory
#   --apache-proxy-address - Address where to proxy requests
#   --apache-proxy-configuration - Extra configuration for the proxy
#   --apache-proxy-http-configuration - Extra configuration for the proxy HTTP vhost
#   --apache-proxy-https-configuration - Extra configuration for the proxy HTTPS vhost
#   --apache-move-htaccess - Move .htaccess files to a common place so they can be loaded during Apache startup (only allowed when type is not defined)
# NGINX-specific flags:
#   --nginx-additional-configuration - Additional server block configuration (no default)
#   --nginx-external-configuration - Configuration external to server block (no default)
# Returns:
#   true if the configuration was enabled, false otherwise
########################
ensure_web_server_app_configuration_exists() {
    app="${1:?missing app}"
    shift
    apache_args="$app"
    nginx_args="$app"
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --disable|--disable-http|--disable-https)
                apache_args="$apache_args $1"
                nginx_args="$nginx_args $1"
                ;;
            --hosts|--server-name|--server-aliases|--type|--allow-remote-connections|--http-port|--https-port|--document-root)
                apache_args="$apache_args $1 $2"
                nginx_args="$nginx_args $1 $2"
                shift
                ;;
            --apache-additional-configuration|--apache-additional-http-configuration|--apache-additional-https-configuration|--apache-before-vhost-configuration|--apache-allow-override|--apache-extra-directory-configuration|--apache-proxy-address|--apache-proxy-configuration|--apache-proxy-http-configuration|--apache-proxy-https-configuration|--apache-move-htaccess)
                apache_args="$apache_args ${1#--apache-} $2"
                shift
                ;;
            --nginx-additional-configuration|--nginx-external-configuration)
                nginx_args="$nginx_args ${1#--nginx-} $2"
                shift
                ;;
            *)
                echo "Invalid command line flag $1" >&2
                return 1
                ;;
        esac
        shift
    done
    for web_server in $(web_server_list); do
        case "$web_server" in
            apache)
                web_server_execute apache ensure_apache_app_configuration_exists $apache_args
                ;;
            nginx)
                web_server_execute nginx ensure_nginx_app_configuration_exists $nginx_args
                ;;
        esac
    done
}

########################
# Ensure a web server application configuration does not exist anymore (i.e. Apache virtual host format or NGINX server block)
# It serves as a wrapper for the specific web server function
# Globals:
#   *
# Arguments:
#   $1 - App name
# Returns:
#   true if the configuration was disabled, false otherwise
########################
ensure_web_server_app_configuration_not_exists() {
    app="${1:?missing app}"
    for web_server in $(web_server_list); do
        web_server_execute "$web_server" "ensure_${web_server}_app_configuration_not_exists" "$app"
    done
}

########################
# Ensure the web server loads the configuration for an application in a URL prefix
# It serves as a wrapper for the specific web server function
# Globals:
#   *
# Arguments:
#   $1 - App name
# Flags:
#   --allow-remote-connections - Whether to allow remote connections or to require local connections
#   --document-root - Path to document root directory
#   --prefix - URL prefix from where it will be accessible (i.e. /myapp)
#   --type - Application type, which has an effect on what configuration template will be used
# Apache-specific flags:
#   --apache-additional-configuration - Additional vhost configuration (no default)
#   --apache-allow-override - Whether to allow .htaccess files (only allowed when --move-htaccess is set to 'no')
#   --apache-extra-directory-configuration - Extra configuration for the document root directory
#   --apache-move-htaccess - Move .htaccess files to a common place so they can be loaded during Apache startup
# NGINX-specific flags:
#   --nginx-additional-configuration - Additional server block configuration (no default)
# Returns:
#   true if the configuration was enabled, false otherwise
########################
ensure_web_server_prefix_configuration_exists() {
    app="${1:?missing app}"
    shift
    apache_args="$app"
    nginx_args="$app"
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --allow-remote-connections|--document-root|--prefix|--type)
                apache_args="$apache_args $1 $2"
                nginx_args="$nginx_args $1 $2"
                shift
                ;;
            --apache-additional-configuration|--apache-allow-override|--apache-extra-directory-configuration|--apache-move-htaccess)
                apache_args="$apache_args ${1#--apache-} $2"
                shift
                ;;
            --nginx-additional-configuration)
                nginx_args="$nginx_args ${1#--nginx-} $2"
                shift
                ;;
            *)
                echo "Invalid command line flag $1" >&2
                return 1
                ;;
        esac
        shift
    done
    for web_server in $(web_server_list); do
        case "$web_server" in
            apache)
                web_server_execute apache ensure_apache_prefix_configuration_exists $apache_args
                ;;
            nginx)
                web_server_execute nginx ensure_nginx_prefix_configuration_exists $nginx_args
                ;;
        esac
    done
}

########################
# Ensure a web server application configuration is updated with the runtime configuration (i.e. ports)
# It serves as a wrapper for the specific web server function
# Globals:
#   *
# Arguments:
#   $1 - App name
# Flags:
#   --hosts - Host listen addresses
#   --server-name - Server name
#   --server-aliases - Server aliases
#   --enable-http - Enable HTTP app configuration (if not enabled already)
#   --enable-https - Enable HTTPS app configuration (if not enabled already)
#   --disable-http - Disable HTTP app configuration (if not disabled already)
#   --disable-https - Disable HTTPS app configuration (if not disabled already)
#   --http-port - HTTP port number
#   --https-port - HTTPS port number
# Returns:
#   true if the configuration was updated, false otherwise
########################
web_server_update_app_configuration() {
    app="${1:?missing app}"
    shift
    args="$app"
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --enable-http|--enable-https|--disable-http|--disable-https)
                args="$args $1"
                ;;
            --hosts|--server-name|--server-aliases|--http-port|--https-port)
                args="$args $1 $2"
                shift
                ;;
            *)
                echo "Invalid command line flag $1" >&2
                return 1
                ;;
        esac
        shift
    done
    for web_server in $(web_server_list); do
        web_server_execute "$web_server" "${web_server}_update_app_configuration" $args
    done
}

########################
# Enable loading page, which shows users that the initialization process is not yet completed
# Globals:
#   *
# Arguments:
#   None
# Returns:
#   None
#########################
web_server_enable_loading_page() {
    ensure_web_server_app_configuration_exists "__loading" --hosts "_default_" \
        --apache-additional-configuration "
# Show a HTTP 503 Service Unavailable page by default
RedirectMatch 503 ^/\$
# Show index.html if server is answering with 404 Not Found or 503 Service Unavailable status codes
ErrorDocument 404 /index.html
ErrorDocument 503 /index.html" \
        --nginx-additional-configuration "
# Show a HTTP 503 Service Unavailable page by default
location / {
  return 503;
}
# Show index.html if server is answering with 404 Not Found or 503 Service Unavailable status codes
error_page 404 @installing;
error_page 503 @installing;
location @installing {
  rewrite ^(.*)\$ /index.html break;
}"
    web_server_reload
}

########################
# Disable loading page
# Globals:
#   *
# Arguments:
#   None
# Returns:
#   None
#########################
web_server_disable_install_page() {
    ensure_web_server_app_configuration_not_exists "__loading"
    web_server_reload
}