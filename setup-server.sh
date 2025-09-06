#!/bin/bash

# ####################################################################
#
# Mail-in-a-Box & WordPress Installation Script
#
# This script automates the setup of a complete mail server
# and a WordPress website on a single Debian-based server.
#
# Author: Jules
# Version: 3.0 (Optimized, English, Automated)
#
# ####################################################################

# --- Script Configuration ---
# These can be overridden with command-line flags or a config.ini file.
DOMAIN=""
EMAIL=""
TIMEZONE=""
WP_ADMIN_USER=""
WP_ADMIN_PASSWORD=""
WP_DB_NAME=""
WP_DB_USER=""
WP_DB_PASSWORD=""
DB_ROOT_PASSWORD=""
NON_INTERACTIVE=false
SETUP_SFTP=false
SFTP_USER=""
SFTP_PASSWORD=""

# --- Script Internals ---
# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u
# Prevent errors in a pipeline from being masked.
set -o pipefail

# --- Global Variables ---
LOG_FILE="/var/log/setup-server.log"
MAIL_HOSTNAME=""
PHP_FPM_SERVICE=""
PHP_FPM_SOCK_PATH=""

# --- Helper Functions ---
load_config() {
    if [ -f "config.ini" ]; then
        print_message "info" "Loading configuration from config.ini..."
        # Read the .ini file, remove comments and empty lines, and export the variables
        export $(grep -v '^#' config.ini | grep -v '^\s*$' | sed 's/\r$//')
    else
        print_message "info" "config.ini not found. Using defaults and interactive prompts."
    fi
}

# Provides colored output for script messages.
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

# --- Setup Functions ---

function initial_checks() {
    print_message "info" "Running initial system checks..."
    if [ "$(id -u)" -ne 0 ]; then
        print_message "error" "This script must be run as root or with sudo."
        exit 1
    fi
    print_message "success" "Root privileges confirmed."
}

function assign_defaults() {
    print_message "info" "Assigning configuration defaults..."
    # If variables are not set by config.ini or flags, assign defaults
    DOMAIN=${DOMAIN:-}
    EMAIL=${EMAIL:-}
    TIMEZONE=${TIMEZONE:-Etc/UTC}
    WP_ADMIN_USER=${WP_ADMIN_USER:-admin}
    WP_ADMIN_PASSWORD=${WP_ADMIN_PASSWORD:-$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 20)}
    WP_DB_NAME=${WP_DB_NAME:-wordpress_db}
    WP_DB_USER=${WP_DB_USER:-wp_user}
    WP_DB_PASSWORD=${WP_DB_PASSWORD:-$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 20)}
    DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD:-}

    # SFTP password default
    SFTP_PASSWORD=${SFTP_PASSWORD:-$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 20)}
}

function parse_arguments() {
    # Command-line flags will override config.ini values
    while getopts ":d:e:n" opt; do
        case ${opt} in
            d ) DOMAIN=$OPTARG ;;
            e ) EMAIL=$OPTARG ;;
            n ) NON_INTERACTIVE=true ;;
            \? ) print_message "error" "Invalid option: -$OPTARG" >&2; exit 1 ;;
            : ) print_message "error" "Invalid option: -$OPTARG requires an argument" >&2; exit 1 ;;
        esac
    done

    if [[ -z "$DOMAIN" || -z "$EMAIL" ]]; then
        if [ "$NON_INTERACTIVE" = true ]; then
            print_message "error" "Domain and Email are required in non-interactive mode (either via flags or config.ini)."
            exit 1
        else
            print_message "info" "Please enter the required information:"
            # Only ask for info if it wasn't provided in config.ini or flags
            [ -z "$DOMAIN" ] && read -p "Enter the main domain (e.g., example.com): " DOMAIN
            [ -z "$EMAIL" ] && read -p "Enter the admin email (e.g., admin@example.com): " EMAIL
        fi
    fi
    MAIL_HOSTNAME="box.${DOMAIN}"

    # Set default SFTP username if not provided
    if [ -z "$SFTP_USER" ]; then
        SFTP_USER="sftp-user-$(echo $DOMAIN | sed 's/\./-/g')"
    fi
}

function detect_php_version() {
    print_message "info" "Detecting available PHP version..."
    # Find the latest available php-fpm package (e.g., php8.2-fpm)
    PHP_FPM_SERVICE=$(apt-cache search --names-only '^php[0-9]+\.[0-9]+-fpm$' | cut -d' ' -f1 | sort -V | tail -n 1)
    if [ -z "$PHP_FPM_SERVICE" ]; then
        print_message "error" "Could not detect a suitable PHP-FPM package."
        exit 1
    fi
    # Extract version number (e.g., 8.2) from the package name
    PHP_VERSION=$(echo "$PHP_FPM_SERVICE" | grep -oP '(?<=php)\d+\.\d+')
    PHP_FPM_SOCK_PATH="/var/run/php/php${PHP_VERSION}-fpm.sock"
    print_message "success" "Detected PHP-FPM service: $PHP_FPM_SERVICE"
}

function system_setup() {
    print_message "info" "Updating system and installing dependencies..."
    apt-get update && apt-get upgrade -y
    # Added jq for parsing github api, and php-cli for hashing
    apt-get install -y curl wget socat mariadb-server "$PHP_FPM_SERVICE" unattended-upgrades ufw jq php-cli
    print_message "success" "System updated and dependencies installed."

    print_message "info" "Configuring automatic security updates..."
    echo 'APT::Periodic::Update-Package-Lists "1";' > /etc/apt/apt.conf.d/20auto-upgrades
    echo 'APT::Periodic::Unattended-Upgrade "1";' >> /etc/apt/apt.conf.d/20auto-upgrades
    print_message "success" "Automatic security updates configured."

    print_message "info" "Setting system hostname to '$MAIL_HOSTNAME'..."
    hostnamectl set-hostname "$MAIL_HOSTNAME"
    PUBLIC_IP=$(curl -s --fail https://ifconfig.me || echo "127.0.0.1")
    echo "$PUBLIC_IP $MAIL_HOSTNAME box" >> /etc/hosts
    print_message "success" "Hostname is set."
}

function setup_firewall() {
    print_message "info" "Configuring firewall (UFW)..."
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow http
    ufw allow https
    # Mail Ports
    ufw allow 25/tcp   # SMTP
    ufw allow 587/tcp  # SMTP Submission
    ufw allow 465/tcp  # SMTPS
    ufw allow 993/tcp  # IMAPS
    # Enable UFW non-interactively
    ufw --force enable
    print_message "success" "Firewall is configured and enabled."
}

function setup_database() {
    print_message "info" "Creating WordPress database and user..."
    mysql -e "CREATE DATABASE IF NOT EXISTS \`${WP_DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql -e "CREATE USER IF NOT EXISTS '${WP_DB_USER}'@'localhost' IDENTIFIED BY '${WP_DB_PASSWORD}';"
    mysql -e "GRANT ALL PRIVILEGES ON \`${WP_DB_NAME}\`.* TO '${WP_DB_USER}'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    print_message "success" "WordPress database and user created."

    print_message "info" "Starting MariaDB security script..."
    if [ -n "$DB_ROOT_PASSWORD" ]; then
        print_message "info" "Automating mysql_secure_installation with provided root password..."
        # This is a non-interactive way to set the root password and secure the installation.
        mysql -e "UPDATE mysql.user SET Password = PASSWORD('$DB_ROOT_PASSWORD') WHERE User = 'root';"
        mysql -e "DELETE FROM mysql.user WHERE User='';"
        mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
        mysql -e "DROP DATABASE IF EXISTS test;"
        mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
        mysql -e "FLUSH PRIVILEGES;"
        print_message "success" "MariaDB security script automated."
    elif [ "$NON_INTERACTIVE" = true ]; then
        print_message "warn" "Skipping interactive mysql_secure_installation. Please run it manually later."
    else
        print_message "warn" "This next step is INTERACTIVE. You will be asked to set a root password for MariaDB."
        print_message "warn" "It is highly recommended to answer 'Y' (yes) to all prompts."
        mysql_secure_installation
    fi
    print_message "success" "MariaDB is secured."
}

function install_mailinabox() {
    print_message "info" "Starting Mail-in-a-Box installation..."
    # Set environment variables for setup
    export PRIMARY_HOSTNAME="$MAIL_HOSTNAME"
    export PUBLIC_IP=$(curl -s --fail https://ifconfig.me || echo "127.0.0.1")
    export CONTACT_EMAIL="$EMAIL"
    export TZ="$TIMEZONE"

    if [ "$NON_INTERACTIVE" = true ]; then
        print_message "warn" "Running Mail-in-a-Box non-interactively."
        # This will use the environment variables set above.
        curl -s https://mailinabox.email/setup.sh | sudo -E bash
    else
        print_message "warn" "This step is INTERACTIVE. Please follow the on-screen prompts."
        # The script will still use the environment variables but may prompt for confirmation.
        curl -s https://mailinabox.email/setup.sh | sudo -E bash
    fi
    print_message "success" "Mail-in-a-Box installation finished."
}

function install_wp_cli() {
    print_message "info" "Installing WP-CLI..."
    if ! command -v wp &> /dev/null; then
        wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        chmod +x wp-cli.phar
        mv wp-cli.phar /usr/local/bin/wp
        print_message "success" "WP-CLI installed."
    else
        print_message "info" "WP-CLI is already installed."
    fi
}

function install_wordpress() {
    print_message "info" "Installing WordPress for $DOMAIN using WP-CLI..."
    local wp_path="/var/www/$DOMAIN"
    mkdir -p "$wp_path"
    chown -R www-data:www-data "$wp_path"

    # Run WP-CLI commands as the www-data user for correct file permissions
    sudo -u www-data wp core download --path="$wp_path"
    sudo -u www-data wp config create --path="$wp_path" \
        --dbname="$WP_DB_NAME" \
        --dbuser="$WP_DB_USER" \
        --dbpass="$WP_DB_PASSWORD" \
        --extra-php <<PHP
define('FS_METHOD', 'direct');
PHP
    sudo -u www-data wp core install --path="$wp_path" \
        --url="https://www.$DOMAIN" \
        --title="Welcome to $DOMAIN" \
        --admin_user="$WP_ADMIN_USER" \
        --admin_password="$WP_ADMIN_PASSWORD" \
        --admin_email="$EMAIL"

    print_message "success" "WordPress installed and configured via WP-CLI."
}

function setup_nginx() {
    print_message "info" "Configuring Nginx for WordPress site..."
    local nginx_conf="/etc/nginx/sites-available/$DOMAIN.conf"

    # Embedded Nginx configuration with improvements
    cat <<EOF > "$nginx_conf"
# Redirect non-www to www
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    return 301 https://www.$DOMAIN\$request_uri;
}

server {
    listen 80;
    listen [::]:80;
    server_name www.$DOMAIN;

    root /var/www/$DOMAIN;
    index index.php index.html;

    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header X-XSS-Protection "1; mode=block" always;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    # Browser Caching for static assets
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|webp)$ {
        expires 7d;
        add_header Cache-Control "public";
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$PHP_FPM_SOCK_PATH;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

    rm -f /etc/nginx/sites-enabled/default
    ln -sf "$nginx_conf" "/etc/nginx/sites-enabled/"

    if nginx -t; then
        systemctl reload nginx
        print_message "success" "Nginx configured and reloaded."
    else
        print_message "error" "Nginx configuration test failed. Please check $nginx_conf"
        exit 1
    fi
}

function setup_ssl() {
    print_message "info" "Obtaining SSL certificates using Certbot..."
    apt-get install -y certbot python3-certbot-nginx

    print_message "info" "Issuing certificate for WordPress site: www.$DOMAIN and $DOMAIN"
    certbot --nginx --non-interactive --agree-tos --email "$EMAIL" -d "www.$DOMAIN" -d "$DOMAIN"
    print_message "success" "SSL certificate has been installed for WordPress."

    print_message "info" "Issuing certificate for Mail-in-a-Box admin panel: $MAIL_HOSTNAME"
    # This assumes Mail-in-a-Box has set up its Nginx config.
    # We run it as a separate command to avoid issues if one domain fails validation.
    certbot --nginx --non-interactive --agree-tos --email "$EMAIL" -d "$MAIL_HOSTNAME"
    print_message "success" "SSL certificate has been installed for Mail-in-a-Box."
}

function run_security_scan() {
    print_message "info" "Running initial security scan with Lynis..."
    if ! command -v lynis &> /dev/null; then
        apt-get install -y lynis
    fi
    # We run in quiet mode to not overwhelm the user, but the report is saved.
    lynis audit system --quiet
    print_message "info" "Lynis security scan complete. A detailed report can be found in /var/log/lynis-report.dat"
}

function install_yourls() {
    print_message "info" "--- Installing Yourls URL Shortener ---"

    read -p "Enter the domain/subdomain for Yourls (e.g., short.example.com): " yourls_domain
    if [ -z "$yourls_domain" ]; then
        print_message "error" "Domain cannot be empty."
        return 1
    fi

    # Database Setup
    local yourls_db="yourls_db"
    local yourls_user="yourls_user"
    local yourls_pw=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 20)
    print_message "info" "Creating MariaDB database '$yourls_db' and user '$yourls_user'..."
    mysql -e "CREATE DATABASE IF NOT EXISTS \`$yourls_db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql -e "CREATE USER IF NOT EXISTS '$yourls_user'@'localhost' IDENTIFIED BY '$yourls_pw';"
    mysql -e "GRANT ALL PRIVILEGES ON \`$yourls_db\`.* TO '$yourls_user'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    print_message "success" "Database created."

    # Download and Install Latest Version
    print_message "info" "Finding latest Yourls version..."
    local yourls_latest_url=$(curl -s https://api.github.com/repos/YOURLS/YOURLS/releases/latest | jq -r ".tarball_url")
    if [ -z "$yourls_latest_url" ] || [ "$yourls_latest_url" = "null" ]; then
        print_message "error" "Could not find latest Yourls release URL. Using fallback."
        yourls_latest_url="https://github.com/YOURLS/YOURLS/archive/refs/tags/1.10.2.tar.gz"
    fi
    print_message "info" "Downloading from $yourls_latest_url"
    local yourls_path="/var/www/$yourls_domain"
    mkdir -p "$yourls_path"
    wget -qO- "$yourls_latest_url" | tar -xz -C "$yourls_path" --strip-components=1
    chown -R www-data:www-data "$yourls_path"
    print_message "success" "Yourls installed."

    # Configuration
    print_message "info" "Configuring Yourls..."
    local config_file="$yourls_path/user/config.php"
    cp "$yourls_path/user/config-sample.php" "$config_file"

    read -p "Enter an admin username for Yourls: " admin_user
    read -s -p "Enter an admin password for Yourls: " admin_pass
    echo

    # Hash the password using MD5, as required by Yourls
    local hashed_pass=$(echo -n "$admin_pass" | md5sum | awk '{print $1}')

    sed -i "s/define( 'YOURLS_DB_USER', 'your db user' );/define( 'YOURLS_DB_USER', '$yourls_user' );/" "$config_file"
    sed -i "s/define( 'YOURLS_DB_PASS', 'your db password' );/define( 'YOURLS_DB_PASS', '$yourls_pw' );/" "$config_file"
    sed -i "s/define( 'YOURLS_DB_NAME', 'yourls' );/define( 'YOURLS_DB_NAME', '$yourls_db' );/" "$config_file"
    sed -i "s|define( 'YOURLS_SITE', 'http://your-own-domain-here.com' );|define( 'YOURLS_SITE', 'https://$yourls_domain' );|" "$config_file"
    local cookie_key=$(LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*(-_=+' < /dev/urandom | head -c 64)
    sed -i "s/define( 'YOURLS_COOKIEKEY', 'modify me!' );/define( 'YOURLS_COOKIEKEY', '$cookie_key' );/" "$config_file"
    # Make the user setting more robust
    sed -i "s|\$yourls_user_passwords = array(|\$yourls_user_passwords = array( '$admin_user' => '$hashed_pass',|" "$config_file"

    print_message "success" "Yourls configured securely."

    # Nginx Setup
    print_message "info" "Configuring Nginx for Yourls..."
    local nginx_yourls_conf="/etc/nginx/sites-available/$yourls_domain.conf"
    cat <<EOF > "$nginx_yourls_conf"
server {
    listen 80;
    listen [::]:80;
    server_name $yourls_domain;
    root $yourls_path;
    index index.php;

    location / {
        try_files \$uri \$uri/ /yourls-loader.php\$is_args\$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$PHP_FPM_SOCK_PATH;
    }
}
EOF
    ln -sf "$nginx_yourls_conf" "/etc/nginx/sites-enabled/"
    if nginx -t; then
        systemctl reload nginx
    else
        print_message "error" "Nginx configuration for Yourls failed."
        return 1
    fi
    print_message "success" "Nginx configured for Yourls."

    # SSL Setup
    print_message "info" "Setting up SSL for Yourls..."
    # Use the main domain's admin email for the certificate
    local admin_email_for_cert=$(grep -oP "(?<=EMAIL=).*" config.ini || echo "admin@$yourls_domain")
    certbot --nginx --non-interactive --agree-tos --email "$admin_email_for_cert" -d "$yourls_domain"
    print_message "success" "SSL enabled for Yourls."

    print_message "success" "--- YOURLS INSTALLATION COMPLETE ---"
    echo "--------------------------------------------------"
    print_message "warn" "Yourls Admin Credentials (SAVE THESE):"
    echo "  - URL:               https://$yourls_domain/admin"
    echo "  - Username:          $admin_user"
    echo "  - Password:          (the one you just entered)"
    echo "--------------------------------------------------"
}

function setup_sftp() {
    # Check if SFTP setup is enabled
    if [ "$SETUP_SFTP" != "true" ]; then
        print_message "info" "SFTP user setup is disabled. Skipping."
        return
    fi

    print_message "info" "Setting up dedicated SFTP user: $SFTP_USER..."

    # Create a standard system user with a home directory and no shell access.
    # Add user to www-data group to grant access to web files.
    # '|| true' prevents the script from exiting if the user already exists.
    useradd --create-home --shell "/usr/sbin/nologin" --gid "www-data" "$SFTP_USER" 2>/dev/null || true

    # Set the password for the new user
    echo "$SFTP_USER:$SFTP_PASSWORD" | chpasswd

    # Grant group write permissions to the web root for the sftp user
    print_message "info" "Adjusting directory permissions for SFTP user..."
    chmod -R g+w "/var/www/$DOMAIN"

    # Append SFTP-only configuration to sshd_config to enhance security
    print_message "info" "Configuring SSH server to restrict user to SFTP-only access..."
    # Ensure the block isn't added multiple times on script re-runs
    if ! grep -q "Match User $SFTP_USER" /etc/ssh/sshd_config; then
        tee -a /etc/ssh/sshd_config <<EOF

Match User $SFTP_USER
    ForceCommand internal-sftp
    PasswordAuthentication yes
    AllowTcpForwarding no
    X11Forwarding no
EOF
    fi

    # Restart SSH service to apply changes
    systemctl restart sshd
    print_message "success" "SFTP user '$SFTP_USER' created with access to the web root."
}

# This function encapsulates the original, linear setup process.
function run_full_setup() {
    print_message "info" "--- Starting Full Server Setup (Mail-in-a-Box + WordPress) ---"
    load_config
    assign_defaults
    # Pass along any command-line arguments to preserve non-interactive functionality
    parse_arguments "$@"

    print_message "info" "Starting server setup for $DOMAIN..."

    detect_php_version
    system_setup
    setup_firewall
    setup_database
    install_wp_cli
    # Run Mail-in-a-Box setup before touching Nginx/WordPress
    install_mailinabox
    install_wordpress
    setup_nginx
    setup_ssl
    setup_sftp # Setup SFTP user after WP files and folders are in place
    run_security_scan

    print_message "success" "--- FULL INSTALLATION COMPLETE ---"
    print_message "info" "Please check your Mail-in-a-Box admin panel for DNS status."
    echo "--------------------------------------------------"
    print_message "warn" "WordPress Admin Credentials (SAVE THESE):"
    echo "  - URL:               https://www.$DOMAIN/wp-admin"
    echo "  - Username:          $WP_ADMIN_USER"
    echo "  - Password:          $WP_ADMIN_PASSWORD"
    echo "--------------------------------------------------"
    print_message "warn" "WordPress Database Credentials (SAVE THESE):"
    echo "  - Database Name:     $WP_DB_NAME"
    echo "  - Database User:     $WP_DB_USER"
    echo "  - Database Password: $WP_DB_PASSWORD"
    echo "--------------------------------------------------"

    if [ "$SETUP_SFTP" = "true" ]; then
        print_message "warn" "SFTP User Credentials (SAVE THESE):"
        echo "  - Hostname:          www.$DOMAIN"
        echo "  - Port:              22"
        echo "  - Username:          $SFTP_USER"
        echo "  - Password:          $SFTP_PASSWORD"
        echo "--------------------------------------------------"
    fi

    print_message "info" "A detailed installation log can be found at $LOG_FILE"
}

function show_menu() {
    echo
    print_message "info" "============================================="
    print_message "info" "        Server Management Menu"
    print_message "info" "============================================="
    echo
    echo "    1. Run Full Initial Setup (Mail-in-a-Box + WordPress)"
    echo "    2. Install URL Shortener (Yourls)"
    echo "    3. Manage Services (Start/Stop/Status)"
    echo "    4. Run Server Backup"
    echo "    5. Run Server Updates"
    echo "    6. Manage WordPress"
    echo "    7. Exit"
    echo
}

function main() {
    # Redirect all output to log file and console
    exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)
    initial_checks

    while true; do
        show_menu
        read -rp "Enter your choice [1-7]: " choice
        case $choice in
            1)
                run_full_setup
                ;;
            2)
                install_yourls
                ;;
            3)
                if [ -f "./manage-services.sh" ]; then
                    print_message "info" "Launching Service Manager..."
                    sudo ./manage-services.sh
                else
                    print_message "error" "'manage-services.sh' not found."
                fi
                ;;
            4)
                if [ -f "./backup.sh" ]; then
                    print_message "info" "Launching Backup Script..."
                    sudo ./backup.sh
                else
                    print_message "error" "'backup.sh' not found."
                fi
                ;;
            5)
                if [ -f "./update.sh" ]; then
                    print_message "info" "Launching Update Script..."
                    sudo ./update.sh
                else
                    print_message "error" "'update.sh' not found."
                fi
                ;;
            6)
                if [ -f "./wp-manager.sh" ]; then
                    print_message "info" "Launching WordPress Manager..."
                    sudo ./wp-manager.sh
                else
                    print_message "error" "'wp-manager.sh' not found."
                fi
                ;;
            7)
                print_message "info" "Exiting."
                break
                ;;
            *)
                print_message "warn" "Invalid option. Please try again."
                ;;
        esac
        # Wait for user to press Enter before showing the menu again
        read -n 1 -s -r -p "Press any key to continue..."
    done
}


# --- Run Script ---
# Pass all script arguments to the main function
main "$@"
