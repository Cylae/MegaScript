#!/usr/bin/env bats

load '/usr/lib/bats/bats-support/load'
load '/usr/lib/bats/bats-assert/load'

# Get the directory of this helper file
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# Get the root project directory
PROJECT_ROOT="$TEST_DIR/.."

# Source the main script to get access to its functions
# The main script is now "source-safe" and won't execute its main() function
source "$PROJECT_ROOT/setup.sh"

# Load the English language file for testing
# This ensures our tests are consistent and not dependent on user interaction
source "$PROJECT_ROOT/lang/en.sh"

# Set a dummy domain for testing purposes
TEST_DOMAIN="test.example.com"
TEST_SFTP_USER="test-sftp"
TEST_SFTP_DIR="/var/www/sftp-jail"


# This setup function runs before each test.
setup() {
    # Ensure the test directory exists and is owned by root, as required by sshd
    sudo mkdir -p "$TEST_SFTP_DIR"
    sudo chown root:root "$TEST_SFTP_DIR"
    # Run any other setup tasks here
}

# This teardown function runs after each test.
teardown() {
    # Clean up the user and their configuration
    if id "$TEST_SFTP_USER" &>/dev/null; then
        sudo userdel -r "$TEST_SFTP_USER"
    fi
    # Use augtool to remove the specific Match block if it exists
    sudo augtool --autosave "rm /files/etc/ssh/sshd_config/Match[Condition/User='$TEST_SFTP_USER']"
    # Clean up the test directory
    if [ -d "$TEST_SFTP_DIR" ]; then
        sudo rm -rf "$TEST_SFTP_DIR"
    fi
    # It's good practice to restart sshd after config changes, even in teardown
    sudo systemctl restart sshd
}

@test "SFTP: create_sftp_user_logic should create a user and configure sshd" {
    # Run the function to be tested
    run create_sftp_user_logic "$TEST_SFTP_USER" "password123" "$TEST_SFTP_DIR"

    # Assert that the function completed successfully
    assert_success

    # Verify that the user was created
    assert_line --regexp "User '$TEST_SFTP_USER' created/password updated."

    # Check if the user actually exists in the system
    run id "$TEST_SFTP_USER"
    assert_success

    # Check if the sshd_config was modified correctly using grep
    run grep -q "ChrootDirectory $TEST_SFTP_DIR" /etc/ssh/sshd_config
    assert_success

    # Check that the writable subdirectory was created
    run test -d "${TEST_SFTP_DIR}/public_html"
    assert_success
}

@test "SFTP: delete_sftp_user_logic should remove the user and sshd configuration" {
    # First, create the user so we have something to delete
    create_sftp_user_logic "$TEST_SFTP_USER" "password123" "$TEST_SFTP_DIR"

    # Now, run the real logic function from setup.sh
    run delete_sftp_user_logic "$TEST_SFTP_USER"
    assert_success

    # Verify that the success message is printed
    assert_line --regexp "SFTP user '$TEST_SFTP_USER' has been deleted."

    # Verify the user no longer exists in the system
    run id "$TEST_SFTP_USER"
    assert_failure

    # Verify the sshd_config block is gone
    run sudo augtool get "/files/etc/ssh/sshd_config/Match[Condition/User='$TEST_SFTP_USER']"
    assert_failure
}
