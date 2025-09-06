#!/bin/bash

# ####################################################################
#
# Smart Update Script
#
# This script automates the update process for the entire server,
# including system packages, Mail-in-a-Box, and WordPress.
# It is recommended to run this manually and supervise it.
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

# --- Main Script ---

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
  print_message "error" "This script must be run as root or with sudo."
  exit 1
fi

print_message "info" "--- Starting Smart Update Process ---"

# 1. Perform a backup before doing anything
print_message "info" "Step 1: Performing a pre-update backup..."
if [ -f "./backup.sh" ]; then
    ./backup.sh
    print_message "success" "Pre-update backup completed."
else
    print_message "warn" "./backup.sh not found. Skipping pre-update backup. This is risky."
    read -p "Do you want to continue without a backup? (y/N): " confirmation
    if [[ "$confirmation" != "y" && "$confirmation" != "Y" ]]; then
        print_message "error" "Aborting update process."
        exit 1
    fi
fi

# 2. Update System Packages
print_message "info" "Step 2: Updating system packages (apt)..."
apt-get update
apt-get dist-upgrade -y
apt-get autoremove -y
print_message "success" "System packages updated."

# 3. Update Mail-in-a-Box
print_message "info" "Step 3: Updating Mail-in-a-Box..."
if [ -d "/usr/local/lib/mailinabox" ]; then
    # The recommended way to update is to re-run the setup script
    curl -s https://mailinabox.email/setup.sh | bash
    print_message "success" "Mail-in-a-Box update process completed."
else
    print_message "warn" "Mail-in-a-Box installation not found. Skipping."
fi

# 4. Update WordPress using wp-cli
print_message "info" "Step 4: Updating WordPress (core, themes, plugins)..."

# Check for wp-cli
if ! command -v wp &> /dev/null; then
    print_message "info" "wp-cli not found. Installing it now..."
    curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    chmod +x wp-cli.phar
    mv wp-cli.phar /usr/local/bin/wp
    print_message "success" "wp-cli installed successfully."
fi

# Auto-detect WordPress path
WP_DOMAIN=$(find /var/www -mindepth 1 -maxdepth 1 -type d ! -name 'html' -printf '%f\n' | head -n 1)
if [ -z "$WP_DOMAIN" ]; then
    print_message "error" "Could not auto-detect the WordPress domain. Skipping WordPress updates."
else
    WP_PATH="/var/www/$WP_DOMAIN"
    print_message "info" "Updating WordPress core for $WP_DOMAIN..."
    sudo -u www-data wp core update --path="$WP_PATH"

    print_message "info" "Updating WordPress themes for $WP_DOMAIN..."
    sudo -u www-data wp theme update --all --path="$WP_PATH"

    print_message "info" "Updating WordPress plugins for $WP_DOMAIN..."
    sudo -u www-data wp plugin update --all --path="$WP_PATH"

    print_message "success" "WordPress updates completed."
fi

print_message "success" "--- Smart Update Process Finished ---"
print_message "info" "It is recommended to reboot the server if a new kernel was installed."
