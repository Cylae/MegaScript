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
TEST_DOMAIN="website-test.com"
TEST_WEB_ROOT="/var/www/$TEST_DOMAIN"
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
NGINX_CONF="$NGINX_SITES_AVAILABLE/$TEST_DOMAIN.conf"

# This setup function runs before each test.
setup() {
    # Ensure Nginx directories exist
    sudo mkdir -p "$NGINX_SITES_AVAILABLE"
    sudo mkdir -p "$NGINX_SITES_ENABLED"

    # Remove default nginx config to avoid IPv6 issues in test env
    sudo rm -f "$NGINX_SITES_ENABLED/default"

    # Start nginx
    sudo systemctl start nginx

    # Mock certbot
    sudo ln -sf /bin/true /usr/bin/certbot
}

# This teardown function runs after each test.
teardown() {
    # Clean up files and directories
    sudo rm -f "$NGINX_CONF"
    sudo rm -f "$NGINX_SITES_ENABLED/$TEST_DOMAIN.conf"
    sudo rm -rf "$TEST_WEB_ROOT"

    # Unmock certbot
    sudo rm -f /usr/bin/certbot
}

@test "WEBSITE: add_new_website_logic should create web root and nginx config" {
    # We will test the logic function directly
    run add_new_website_logic "$TEST_DOMAIN" "test@example.com"

    assert_success

    # Verify output messages
    assert_output --partial "Creating web root at $TEST_WEB_ROOT"
    assert_output --partial "Configuring Nginx server block"
    assert_output --partial "Nginx configuration reloaded"

    # Verify web root and index.html
    run sudo test -d "$TEST_WEB_ROOT"
    assert_success
    run sudo test -f "$TEST_WEB_ROOT/index.html"
    assert_success

    # Verify Nginx config
    run sudo test -f "$NGINX_CONF"
    assert_success
    run sudo grep -q "server_name $TEST_DOMAIN" "$NGINX_CONF"
    assert_success

    # Verify site is enabled
    run sudo test -L "$NGINX_SITES_ENABLED/$TEST_DOMAIN.conf"
    assert_success
}

@test "WEBSITE: delete_website_logic should remove all assets" {
    # First, create the website
    add_new_website_logic "$TEST_DOMAIN" "test@example.com"

    # Now, test the deletion logic
    run delete_website_logic "$TEST_DOMAIN.conf" ""

    assert_success

    # Verify everything is gone
    run sudo test ! -f "$NGINX_CONF"
    assert_success
    run sudo test ! -L "$NGINX_SITES_ENABLED/$TEST_DOMAIN.conf"
    assert_success
    run sudo test ! -d "$TEST_WEB_ROOT"
    assert_success
}
