#!/bin/bash

# ####################################################################
#
# Advanced Service Management Script
#
# This script provides a robust interface to manage the mail and
# web services, with auto-detection of service names.
#
# Author: Jules
# Version: 2.0
#
# ####################################################################

# --- Script Internals ---
set -u
set -o pipefail

# --- Helper Functions ---
print_message() {
    local color=$1
    local message=$2
    case "$color" in
        "info")    printf "\033[0;34m[INFO] %s\033[0m\n" "$message" ;;
        "success") printf "\033[0;32m[SUCCESS] %s\033[0m\n" "$message" ;;
        "warn")    printf "\033[0;33m[WARNING] %s\033[0m\n" "$message" ;;
        "error")   printf "\033[0;31m[ERROR] %s\033[0m\n" "$message" >&2 ;;
    esac
}

detect_php_service() {
    # Find the running php-fpm service by inspecting systemd units
    local detected_service
    detected_service=$(systemctl list-units --type=service --state=running | grep -o 'php[0-9]\.[0-9]\+-fpm\.service' | head -n 1)
    if [ -n "$detected_service" ]; then
        # Remove the .service suffix
        PHP_FPM_SERVICE=${detected_service%.service}
    else
        # Fallback for when the service isn't running
        PHP_FPM_SERVICE="php-fpm"
        print_message "warn" "Could not detect a running PHP-FPM service. Falling back to 'php-fpm'. This might not work."
    fi
}

show_usage() {
    print_message "info" "--- Server Resource Usage ---"

    echo ""
    print_message "info" "Disk Usage:"
    df -h | grep -E "^/dev/|Filesystem"

    echo ""
    print_message "info" "Memory Usage:"
    free -h

    echo ""
    print_message "info" "CPU Usage and Load:"
    top -b -n 1 | head -n 5

    echo ""
    exit 0
}

show_logs() {
    local group=$1
    print_message "info" "Tailing logs for '$group'. Press Ctrl+C to exit."

    local log_files=()
    case "$group" in
        "web")
            log_files+=("/var/log/nginx/error.log")
            log_files+=("/var/log/nginx/access.log")
            # Try to find the PHP log file
            local php_log_dir="/var/log"
            local php_log_file=$(find "$php_log_dir" -name "*php*-fpm.log" | head -n 1)
            if [ -n "$php_log_file" ]; then
                log_files+=("$php_log_file")
            fi
            log_files+=("/var/log/mariadb/error.log")
            ;;
        "mail")
            log_files+=("/var/log/mail.log")
            ;;
        "all")
            # For 'all', let's just show the mail log and nginx error log to avoid too much noise
            log_files+=("/var/log/mail.log")
            log_files+=("/var/log/nginx/error.log")
            ;;
        *)
            print_message "error" "Invalid service group for logs: '$group'. Use 'web', 'mail', or 'all'."
            exit 1
            ;;
    esac

    local existing_logs=()
    for log in "${log_files[@]}"; do
        if [ -f "$log" ]; then
            existing_logs+=("$log")
        else
            print_message "warn" "Log file not found: $log"
        fi
    done

    if [ ${#existing_logs[@]} -eq 0 ]; then
        print_message "error" "No log files found for this group."
        exit 1
    fi

    tail -n 50 -f "${existing_logs[@]}"
}

# --- Service Definitions ---
detect_php_service
WEB_SERVICES="nginx ${PHP_FPM_SERVICE} mariadb"
# Mail-in-a-Box is best managed by its own daemon. We will use that if available.
MAIL_SERVICES_FALLBACK="postfix dovecot"

# --- Usage Function ---
print_usage() {
    echo "Usage: $0 [command] [service_group]"
    echo ""
    echo "Commands:"
    echo "  start       Start services."
    echo "  stop        Stop services."
    echo "  restart     Restart services."
    echo "  status      Show service status."
    echo "  usage       Show server resource usage (CPU, RAM, Disk)."
    echo "  logs        Tail the logs for a service group (web or mail)."
    echo ""
    echo "Service Groups:"
    echo "  web         Manages: $WEB_SERVICES"
    if [ -x "/usr/local/bin/mailinabox-daemon" ]; then
        echo "  mail        Manages: Mail-in-a-Box services via its daemon."
    else
        echo "  mail        Manages: $MAIL_SERVICES_FALLBACK (fallback)"
    fi
    echo "  all         Manages all services."
    exit 1
}

# --- Main Script ---

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
  print_message "error" "This script must be run as root or with sudo."
  exit 1
fi

# Check for correct number of arguments
if [ "$#" -ne 2 ]; then
    print_usage
fi

COMMAND=$1
SERVICE_GROUP=$2

# Validate the command
case "$COMMAND" in
    "start" | "stop" | "restart" | "status" | "usage" | "logs")
        # Command is valid, proceed
        ;;
    *)
        print_message "error" "Invalid command: '$COMMAND'"
        print_usage
        ;;
esac

manage_services() {
    local services_to_manage=$1
    print_message "info" "Executing '$COMMAND' on services: $services_to_manage"
    for service in $services_to_manage; do
        echo "--- $COMMAND $service ---"
        if ! systemctl "$COMMAND" "$service"; then
            print_message "error" "Command '$COMMAND' failed for service '$service'."
        fi
        if [ "$COMMAND" == "status" ]; then
          echo "-----------------------"
        fi
    done
}

# Handle commands that don't follow the standard service management flow
if [ "$COMMAND" == "usage" ]; then
    show_usage
fi
if [ "$COMMAND" == "logs" ]; then
    show_logs "$SERVICE_GROUP"
fi

# Determine which services to manage and execute
case "$SERVICE_GROUP" in
    "web")
        manage_services "$WEB_SERVICES"
        ;;
    "mail")
        if [ -x "/usr/local/bin/mailinabox-daemon" ]; then
            print_message "info" "Using mailinabox-daemon to manage mail services..."
            # The daemon does not support 'status', so we handle it separately.
            if [ "$COMMAND" == "status" ]; then
                print_message "warn" "'status' command for 'mail' group is not directly supported by mailinabox-daemon."
                print_message "info" "Check the Mail-in-a-Box admin panel for a detailed status."
                manage_services "$MAIL_SERVICES_FALLBACK"
            else
                if ! /usr/local/bin/mailinabox-daemon "$COMMAND"; then
                    print_message "error" "Mail-in-a-Box daemon command failed."
                fi
            fi
        else
            print_message "warn" "mailinabox-daemon not found. Using fallback service list."
            manage_services "$MAIL_SERVICES_FALLBACK"
        fi
        ;;
    "all")
        print_message "info" "Managing all service groups..."
        # First web
        manage_services "$WEB_SERVICES"
        # Then mail
        # Trigger the 'mail' case logic by re-calling the script logic conceptually
        if [ -x "/usr/local/bin/mailinabox-daemon" ]; then
             if [ "$COMMAND" == "status" ]; then
                manage_services "$MAIL_SERVICES_FALLBACK"
             else
                /usr/local/bin/mailinabox-daemon "$COMMAND"
             fi
        else
            manage_services "$MAIL_SERVICES_FALLBACK"
        fi
        ;;
    *)
        print_message "error" "Invalid service group: '$SERVICE_GROUP'"
        print_usage
        ;;
esac

print_message "success" "Command '$COMMAND' executed for service group '$SERVICE_GROUP'."
