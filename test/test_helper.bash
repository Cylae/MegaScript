#!/bin/bash

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

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
