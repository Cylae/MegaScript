#!/bin/bash

# ####################################################################
#
# WordPress Management Script
#
# This script provides a command-line interface to manage common
# WordPress tasks using wp-cli.
#
# Author: Jules
# Version: 1.0
#
# ####################################################################

# --- Script Internals ---
set -e
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

print_usage() {
    print_message "info" "WordPress Management Script"
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  user-create <username> <email> [password]"
    echo "    Creates a new administrator user. If password is not provided, one will be generated."
    echo ""
    echo "  plugin <activate|deactivate|toggle> <plugin_name>"
    echo "    Manages a plugin."
    echo ""
    echo "  maintenance <on|off>"
    echo "    Activates or deactivates maintenance mode."
    exit 1
}

# --- Pre-flight Checks ---

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
  print_message "error" "This script must be run as root or with sudo."
  exit 1
fi

# Check for wp-cli
if ! command -v wp &> /dev/null; then
    print_message "error" "wp-cli is not installed. Please run the update.sh script first, or install it manually."
    exit 1
fi

# Auto-detect WordPress path
WP_DOMAIN=$(find /var/www -mindepth 1 -maxdepth 1 -type d ! -name 'html' -printf '%f\n' | head -n 1)
if [ -z "$WP_DOMAIN" ]; then
    print_message "error" "Could not auto-detect the WordPress domain."
    exit 1
fi
WP_PATH="/var/www/$WP_DOMAIN"

# --- Main Script ---

if [ "$#" -lt 2 ]; then
    print_usage
fi

COMMAND=$1
shift

# Run wp-cli commands as the www-data user
WP_CLI_CMD="sudo -u www-data wp --path=$WP_PATH"

case "$COMMAND" in
    "user-create")
        if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
            print_message "error" "Usage: $0 user-create <username> <email> [password]"
            exit 1
        fi
        USERNAME=$1
        EMAIL=$2
        PASSWORD=${3:-$(openssl rand -base64 12)}

        print_message "info" "Creating user '$USERNAME'..."
        $WP_CLI_CMD user create "$USERNAME" "$EMAIL" --role=administrator --user_pass="$PASSWORD"
        print_message "success" "User '$USERNAME' created with password: $PASSWORD"
        ;;

    "plugin")
        if [ "$#" -ne 2 ]; then
            print_message "error" "Usage: $0 plugin <activate|deactivate|toggle> <plugin_name>"
            exit 1
        fi
        ACTION=$1
        PLUGIN_NAME=$2

        print_message "info" "Attempting to '$ACTION' plugin '$PLUGIN_NAME'..."
        $WP_CLI_CMD plugin "$ACTION" "$PLUGIN_NAME"
        print_message "success" "Action '$ACTION' completed for plugin '$PLUGIN_NAME'."
        ;;

    "maintenance")
        if [ "$#" -ne 1 ]; then
            print_message "error" "Usage: $0 maintenance <on|off>"
            exit 1
        fi
        MODE=$1

        if [ "$MODE" == "on" ]; then
            print_message "info" "Activating maintenance mode..."
            $WP_CLI_CMD maintenance-mode activate
            print_message "success" "Maintenance mode is now ON."
        elif [ "$MODE" == "off" ]; then
            print_message "info" "Deactivating maintenance mode..."
            $WP_CLI_CMD maintenance-mode deactivate
            print_message "success" "Maintenance mode is now OFF."
        else
            print_message "error" "Invalid mode for maintenance. Use 'on' or 'off'."
            exit 1
        fi
        ;;

    *)
        print_message "error" "Invalid command: '$COMMAND'"
        print_usage
        ;;
esac
