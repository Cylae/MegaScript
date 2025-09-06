#!/bin/bash

# ####################################################################
#
# Server Backup Script
#
# This script creates a compressed backup of the WordPress site
# (files and database) and the Mail-in-a-Box data.
#
# Author: Jules
# Version: 1.0
#
# ####################################################################

# --- Configuration ---
# The domain of the WordPress site. The script will try to find it automatically.
WP_DOMAIN=""
# The rclone remote name (e.g., "gdrive:my_backups"). Leave empty to disable cloud backup.
RCLONE_REMOTE_NAME=""
# The email address for sending notifications. Leave empty to disable.
NOTIFICATION_EMAIL=""
# Path to the backup file to restore.
RESTORE_FILE_PATH=""
# The main directory where backups will be stored.
BACKUP_BASE_DIR="/var/backups/server-backups"
# Timestamp for the backup file.
TIMESTAMP=$(date +"%Y-%m-%d-%H%M%S")

# --- Script Internals ---
set -e
set -u
set -o pipefail

# --- Helper Functions ---

# This variable will hold the path to the final backup file
FINAL_BACKUP_FILE=""

send_notification() {
    local subject=$1
    local body=$2
    if [ -n "$NOTIFICATION_EMAIL" ]; then
        if command -v sendmail &> /dev/null; then
            printf "Subject: %s\nTo: %s\n\n%s" "$subject" "$NOTIFICATION_EMAIL" "$body" | sendmail -t
            print_message "info" "Sent notification email to $NOTIFICATION_EMAIL."
        else
            print_message "warn" "NOTIFICATION_EMAIL is set, but sendmail command not found. Cannot send email."
        fi
    fi
}

cleanup() {
    if [ -n "${TEMP_BACKUP_DIR-}" ] && [ -d "$TEMP_BACKUP_DIR" ]; then
        print_message "info" "Cleaning up temporary files..."
        rm -rf "$TEMP_BACKUP_DIR"
        print_message "success" "Cleanup complete."
    fi
}

handle_exit() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        local subject="[FAIL] Server Backup Failed on $(hostname)"
        local body="The server backup script failed with exit code $exit_code."
        send_notification "$subject" "$body"
    fi
    cleanup
    exit $exit_code
}

# Trap exit signals to ensure cleanup and failure notifications
trap handle_exit EXIT

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
    echo "Usage: $0 [-d domain] [-r rclone_remote] [-e email] [-f /path/to/backup.tar.gz]"
    echo ""
    echo "This script backs up or restores the WordPress site and Mail-in-a-Box data."
    echo ""
    echo "Backup Options:"
    echo "  -d <domain>   Specify the WordPress domain manually if auto-detection fails."
    echo "  -r <remote>   Specify the rclone remote name for cloud backup."
    echo "  -e <email>    Specify the email address for notifications."
    echo ""
    echo "Restore Options:"
    echo "  -f <file>     Restore from the specified backup archive."
    echo "  -h, --help    Show the manual restore instructions."
    exit 0
}

print_restore_instructions() {
    print_message "info" "--- How to Restore from a Backup ---"
    echo "Restoring is a manual process to prevent accidental data loss."
    echo "1. Uncompress the backup file: tar -xzvf server-backup-YYYY-MM-DD-HHMMSS.tar.gz"
    echo "2. Restore WordPress Files:"
    echo "   - Move the current /var/www/<domain> to a backup location."
    echo "   - Copy the backed-up 'wordpress_files' directory to /var/www/<domain>."
    echo "   - Ensure file permissions are correct: chown -R www-data:www-data /var/www/<domain>"
    echo "3. Restore WordPress Database:"
    echo "   - Drop all tables from your current WordPress database."
    echo "   - Import the backup: mysql -u <db_user> -p <db_name> < wordpress_db.sql"
    echo "     (You can find credentials in your wp-config.php)"
    echo "4. Restore Mail-in-a-Box:"
    echo "   - Follow the official Mail-in-a-Box guide for moving to a new machine."
    echo "   - The 'mail_backup' directory contains your mail data."
    echo "   - See: https://mailinabox.email/maintenance.html#moving-to-a-new-box"
    exit 0
}

# --- Restore Logic ---
restore_backup() {
    local backup_file=$1
    print_message "warn" "--- Starting Restore Process ---"

    if [ ! -f "$backup_file" ]; then
        print_message "error" "Restore file not found: $backup_file"
        exit 1
    fi

    # Auto-detect domain
    if [ -z "$WP_DOMAIN" ]; then
        WP_DOMAIN=$(find /var/www -mindepth 1 -maxdepth 1 -type d ! -name 'html' -printf '%f\n' | head -n 1)
        if [ -z "$WP_DOMAIN" ]; then
            print_message "error" "Could not auto-detect the WordPress domain. Please specify it with -d."
            exit 1
        fi
    fi
    print_message "info" "WordPress domain for restore: $WP_DOMAIN"

    print_message "warn" "This will overwrite your current WordPress files, database, and Mail-in-a-Box data."
    read -p "To confirm, please type the domain name '$WP_DOMAIN': " confirmation
    if [ "$confirmation" != "$WP_DOMAIN" ]; then
        print_message "error" "Confirmation failed. Aborting restore."
        exit 1
    fi

    local restore_temp_dir
    restore_temp_dir=$(mktemp -d)

    print_message "info" "Stopping services..."
    if [ -f "./manage-services.sh" ]; then
        ./manage-services.sh stop all
    else
        print_message "warn" "manage-services.sh not found. Skipping service management. Please stop services manually."
    fi

    print_message "info" "Extracting backup archive..."
    tar -xzf "$backup_file" -C "$restore_temp_dir"

    # Restore WordPress Files
    print_message "info" "Restoring WordPress files..."
    local wp_path="/var/www/$WP_DOMAIN"
    local wp_backup_path_old="/var/www/${WP_DOMAIN}_backup_$(date +%s)"
    mv "$wp_path" "$wp_backup_path_old"
    print_message "info" "Moved existing WordPress directory to $wp_backup_path_old"
    tar -xzf "$restore_temp_dir/wordpress_files.tar.gz" -C "/var/www"
    mv "/var/www/." "$wp_path" # This is tricky, might need a better way
    chown -R www-data:www-data "$wp_path"
    print_message "success" "WordPress files restored."

    # Restore WordPress Database
    print_message "info" "Restoring WordPress database..."
    local wp_config_file="$wp_path/wp-config.php"
    local db_name=$(grep "DB_NAME" "$wp_config_file" | cut -d \' -f 4)
    local db_user=$(grep "DB_USER" "$wp_config_file" | cut -d \' -f 4)
    local db_password=$(grep "DB_PASSWORD" "$wp_config_file" | cut -d \' -f 4)
    mysql -u"$db_user" -p"$db_password" -e "DROP DATABASE IF EXISTS \`$db_name\`; CREATE DATABASE \`$db_name\`;"
    mysql -u"$db_user" -p"$db_password" "$db_name" < "$restore_temp_dir/wordpress_db.sql"
    print_message "success" "WordPress database restored."

    # Restore Mail-in-a-Box
    print_message "info" "Restoring Mail-in-a-Box data..."
    # This is a destructive operation. The official guide should be followed.
    # Here, we will just copy the data back.
    if [ -d "$restore_temp_dir/mail_backup" ]; then
        rsync -a --delete "$restore_temp_dir/mail_backup/" /home/user-data/backup/
        print_message "success" "Mail-in-a-Box data restored."
    else
        print_message "warn" "No mail backup found in archive. Skipping."
    fi

    print_message "info" "Starting services..."
    if [ -f "./manage-services.sh" ]; then
        ./manage-services.sh start all
    else
        print_message "warn" "manage-services.sh not found. Skipping service management."
    fi

    rm -rf "$restore_temp_dir"
    print_message "success" "--- Restore Process Complete ---"
    exit 0
}


# --- Main Script ---

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    print_message "error" "This script must be run as root or with sudo."
    exit 1
fi

# Parse command-line options
while getopts ":d:r:e:f:h" opt; do
    case ${opt} in
        d ) WP_DOMAIN=$OPTARG ;;
        r ) RCLONE_REMOTE_NAME=$OPTARG ;;
        e ) NOTIFICATION_EMAIL=$OPTARG ;;
        f ) RESTORE_FILE_PATH=$OPTARG ;;
        h ) print_restore_instructions ;;
        \? ) print_usage ;;
    esac
done

# --- Restore Execution ---
if [ -n "$RESTORE_FILE_PATH" ]; then
    restore_backup "$RESTORE_FILE_PATH"
fi

# --- Backup Execution ---

print_message "info" "Starting server backup process..."

# Auto-detect domain if not provided
if [ -z "$WP_DOMAIN" ]; then
    # Find the first directory in /var/www that is not 'html'
    WP_DOMAIN=$(find /var/www -mindepth 1 -maxdepth 1 -type d ! -name 'html' -printf '%f\n' | head -n 1)
    if [ -z "$WP_DOMAIN" ]; then
        print_message "error" "Could not auto-detect the WordPress domain. Please specify it with -d."
        exit 1
    fi
    print_message "info" "Auto-detected WordPress domain: $WP_DOMAIN"
fi

WP_PATH="/var/www/$WP_DOMAIN"
WP_CONFIG_FILE="$WP_PATH/wp-config.php"

if [ ! -f "$WP_CONFIG_FILE" ]; then
    print_message "error" "WordPress config file not found at $WP_CONFIG_FILE."
    exit 1
fi

# Create a temporary directory for the backup
TEMP_BACKUP_DIR=$(mktemp -d)
print_message "info" "Using temporary backup directory: $TEMP_BACKUP_DIR"

# 1. Backup WordPress Database
print_message "info" "Backing up WordPress database..."
DB_NAME=$(grep "DB_NAME" "$WP_CONFIG_FILE" | cut -d \' -f 4)
DB_USER=$(grep "DB_USER" "$WP_CONFIG_FILE" | cut -d \' -f 4)
DB_PASSWORD=$(grep "DB_PASSWORD" "$WP_CONFIG_FILE" | cut -d \' -f 4)
mysqldump -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" > "$TEMP_BACKUP_DIR/wordpress_db.sql"
print_message "success" "WordPress database backed up."

# 2. Backup WordPress Files
print_message "info" "Backing up WordPress files..."
tar -czf "$TEMP_BACKUP_DIR/wordpress_files.tar.gz" -C "$WP_PATH" .
print_message "success" "WordPress files backed up."

# 3. Backup Mail-in-a-Box data
if [ -d "/home/user-data/backup/encrypted" ]; then
    print_message "info" "Running Mail-in-a-Box backup command..."
    # This command will generate a new backup if needed.
    /usr/local/bin/mailinabox-daemon
    print_message "info" "Copying Mail-in-a-Box backup data..."
    # Copy the entire backup directory
    cp -r /home/user-data/backup "$TEMP_BACKUP_DIR/mail_backup"
    print_message "success" "Mail-in-a-Box data copied."
else
    print_message "warn" "Mail-in-a-Box backup directory not found. Skipping."
fi

# 4. Create Final Compressed Archive
print_message "info" "Creating final compressed backup archive..."
mkdir -p "$BACKUP_BASE_DIR"
FINAL_BACKUP_FILE="$BACKUP_BASE_DIR/server-backup-$TIMESTAMP.tar.gz"
tar -czf "$FINAL_BACKUP_FILE" -C "$TEMP_BACKUP_DIR" .
print_message "success" "Backup created successfully at: $FINAL_BACKUP_FILE"

# 5. Cloud Backup
if [ -n "$RCLONE_REMOTE_NAME" ]; then
    if command -v rclone &> /dev/null; then
        print_message "info" "Starting cloud backup to rclone remote: $RCLONE_REMOTE_NAME..."
        rclone copy "$FINAL_BACKUP_FILE" "$RCLONE_REMOTE_NAME":
        if [ $? -eq 0 ]; then
            print_message "success" "Cloud backup completed successfully."
        else
            print_message "error" "Cloud backup failed. Please check your rclone configuration."
        fi
    else
        print_message "warn" "RCLONE_REMOTE_NAME is set, but rclone is not installed. Skipping cloud backup."
    fi
fi

# 6. Success Notification
subject="[SUCCESS] Server Backup Completed on $(hostname)"
body="The server backup was created successfully.

File: $FINAL_BACKUP_FILE
Size: $(du -h "$FINAL_BACKUP_FILE" | cut -f1)
"
send_notification "$subject" "$body"

echo "--------------------------------------------------"
print_message "info" "To restore from this backup, run: $0 --help"
echo "--------------------------------------------------"
