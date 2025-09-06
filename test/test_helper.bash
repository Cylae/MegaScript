#!/bin/bash
# Load testing libraries from the vendored location
load 'libs/bats-support/load'
load 'libs/bats-assert/load'

# Get the project root from the current working directory.
# This assumes tests are run from the project's root directory, which is standard practice.
PROJECT_ROOT="$(pwd)"

# Source the main script to get access to its functions
source "$PROJECT_ROOT/setup.sh"

# Load the English language file for testing
source "$PROJECT_ROOT/lang/en.sh"

# Export functions so they are available to subshells invoked by `sudo` in tests
export -f create_sftp_user_logic
export -f delete_sftp_user_logic

# Define constants for testing
TEST_DOMAIN="test.example.com"
TEST_SFTP_USER="test-sftp"
TEST_SFTP_DIR="/var/www/sftp-jail"
