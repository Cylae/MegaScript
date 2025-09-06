#!/usr/bin/env bats

load 'libs/bats-support/load.bash'
load 'libs/bats-assert/load.bash'

# The project root is the current working directory.
# This test must be run from the root of the project.
PROJECT_ROOT="$PWD"

# Source the main script to get access to its functions
source "$PROJECT_ROOT/setup.sh"

# Load the English language file for testing
source "$PROJECT_ROOT/lang/en.sh"

# --- Test Variables ---
TEST_DOMAIN="backup-test.com"
TEST_WEB_ROOT="/var/www/$TEST_DOMAIN"
TEST_DB_NAME="test_db_backup"
TEST_DB_USER="test_user"
TEST_DB_PASS="password" # Not used for root login, but good practice
BACKUP_DIR="/root/backups"

# This setup function runs before each test.
setup() {
    # Ensure directories exist
    sudo mkdir -p "$TEST_WEB_ROOT"
    sudo mkdir -p "$BACKUP_DIR"
    # Create a dummy index file
    echo "<h1>Hello from $TEST_DOMAIN</h1>" | sudo tee "$TEST_WEB_ROOT/index.html" > /dev/null

    # Setup MariaDB if not already set up
    if ! mysql -u root -e "SELECT 1" &>/dev/null; then
        # This is a simplified setup for testing; assumes MariaDB is installed
        # In a real CI environment, you'd have a setup script for this
        echo "MariaDB not configured for root. Skipping DB tests."
        skip "MariaDB root access is not configured."
    fi

    # Create a test database and table
    mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`$TEST_DB_NAME\`;"
    mysql -u root -e "CREATE TABLE IF NOT EXISTS \`$TEST_DB_NAME\`.test_table (id INT, message VARCHAR(255));"
    mysql -u root -e "INSERT INTO \`$TEST_DB_NAME\`.test_table VALUES (1, 'hello world');"

    # Ensure the root password file exists for the script, creating it if necessary.
    if [ ! -f "/root/.mysql_root_password" ]; then
        echo "temppassword" | sudo tee /root/.mysql_root_password > /dev/null
        sudo chmod 600 /root/.mysql_root_password
    fi
}

# This teardown function runs after each test.
teardown() {
    # Clean up files and directories
    sudo rm -rf "$TEST_WEB_ROOT"
    sudo rm -f "$BACKUP_DIR"/backup-${TEST_DOMAIN}-*.tar.gz
    # Clean up database
    if mysql -u root -e "SELECT 1" &>/dev/null; then
        mysql -u root -e "DROP DATABASE IF EXISTS \`$TEST_DB_NAME\`;"
    fi
}

@test "BACKUP: backup_website should create a backup archive" {
    # Mock user input for the function
    # We are testing the core logic, not the user-facing part
    run backup_website_logic "$TEST_DOMAIN" "$TEST_DB_NAME"

    assert_success
    assert_output --partial "Backup complete!"

    # Check if the backup file was actually created
    run ls -1 "$BACKUP_DIR"/backup-${TEST_DOMAIN}-*.tar.gz
    assert_success
}

@test "RESTORE: restore_website should restore files and database" {
    # First, create a backup
    backup_website_logic "$TEST_DOMAIN" "$TEST_DB_NAME"
    local backup_file=$(ls -1 "$BACKUP_DIR"/backup-${TEST_DOMAIN}-*.tar.gz | head -n 1)

    # Pre-restore cleanup: remove original files and DB to ensure restore works
    sudo rm -rf "$TEST_WEB_ROOT"
    mysql -u root -e "DROP DATABASE \`$TEST_DB_NAME\`;"

    # Run the restore logic
    run restore_website_logic "$backup_file" "$TEST_DOMAIN" "$TEST_DB_NAME"

    assert_success
    assert_output --partial "Restore complete"

    # Verify file restoration
    run test -f "$TEST_WEB_ROOT/index.html"
    assert_success
    run sudo grep -q "Hello from $TEST_DOMAIN" "$TEST_WEB_ROOT/index.html"
    assert_success

    # Verify database restoration
    run mysql -u root -e "USE \`$TEST_DB_NAME\`; SELECT message FROM test_table WHERE id=1;"
    assert_success
    assert_output --partial "hello world"
}
