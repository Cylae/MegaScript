#!/bin/bash

# ####################################################################
#
# Auto-healing Script for Web & Mail Services
#
# This script checks the status of critical services and attempts
# to restart them if they are found to be inactive.
# It's designed to be run as a cron job.
#
# Author: Jules
# Version: 1.0
#
# ####################################################################

# --- Configuration ---
LOG_FILE="/var/log/autoheal.log"
# Email for notifications. Leave empty to disable.
NOTIFICATION_EMAIL=""

# --- Script Internals ---
set -u
set -o pipefail

# --- Helper Functions ---
log_message() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" >> "$LOG_FILE"
}

send_notification() {
    local subject=$1
    local body=$2
    if [ -n "$NOTIFICATION_EMAIL" ]; then
        if command -v sendmail &> /dev/null; then
            printf "Subject: %s\nTo: %s\n\n%s" "$subject" "$NOTIFICATION_EMAIL" "$body" | sendmail -t
            log_message "INFO: Sent notification email to $NOTIFICATION_EMAIL."
        else
            log_message "WARN: NOTIFICATION_EMAIL is set, but sendmail command not found."
        fi
    fi
}

detect_php_service() {
    local detected_service
    detected_service=$(systemctl list-units --type=service --state=running | grep -o 'php[0-9]\.[0-9]\+-fpm\.service' | head -n 1)
    if [ -n "$detected_service" ]; then
        echo "${detected_service%.service}"
    else
        # Fallback if service not running
        echo "php-fpm"
    fi
}

# --- Main Script ---

# Check for root privileges, as this is needed to restart services
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Exiting." | tee -a "$LOG_FILE"
  exit 1
fi

# --- Service Definitions ---
PHP_FPM_SERVICE=$(detect_php_service)
SERVICES_TO_CHECK="nginx ${PHP_FPM_SERVICE} mariadb postfix dovecot"

log_message "INFO: Starting auto-heal check..."

for service in $SERVICES_TO_CHECK; do
    # Check if the service is active
    if ! systemctl is-active --quiet "$service"; then
        log_message "WARN: Service '$service' is INACTIVE. Attempting restart..."

        # Attempt to restart the service
        systemctl restart "$service"

        # Verify the restart
        if systemctl is-active --quiet "$service"; then
            log_message "SUCCESS: Service '$service' has been restarted successfully."
            local subject="[Auto-Heal] Service '$service' was restarted on $(hostname)"
            local body="The service '$service' was found to be inactive and has been automatically restarted."
            send_notification "$subject" "$body"
        else
            log_message "ERROR: Failed to restart service '$service'."
            local subject="[CRITICAL] Failed to restart service '$service' on $(hostname)"
            local body="The service '$service' was found to be inactive and the attempt to restart it FAILED. Manual intervention is required."
            send_notification "$subject" "$body"
        fi
    fi
done

log_message "INFO: Auto-heal check finished."
