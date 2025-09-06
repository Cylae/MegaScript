#!/bin/bash

# ####################################################################
#
#  Unified Server Setup & Management Script
#
#  Author: Jules
#  Version: 1.0
#
#  This script provides a menu-driven interface to set up and
#  manage a complete web server, including LEMP stack, websites,
#  SSL, a mail server, SFTP users, and backups.
#
# ####################################################################

# --- Script Configuration ---
# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u
# Prevent errors in a pipeline from being masked.
set -o pipefail

# --- Global Variables ---
LOG_FILE="/var/log/server_setup.log"
OS_ID=""
OS_VERSION=""
PKG_MANAGER=""

# --- Helper Functions ---

# Provides colored and timestamped output for script messages.
# Usage: print_message "info" "This is an informational message."
print_message() {
    local type=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local color_code

    case "$type" in
        "info")    color_code="\033[0;34m" ;; # Blue
        "success") color_code="\033[0;32m" ;; # Green
        "warn")    color_code="\033[0;33m" ;; # Yellow
        "error")   color_code="\033[0;31m" ;; # Red
        *)         color_code="\033[0m"    ;; # No Color
    esac

    # The main 'exec' command at the end of the script handles logging to file.
    # This function just needs to print to the correct stream (stdout or stderr).
    if [[ "$type" == "error" ]]; then
        # Print errors to stderr
        printf "%b[%s] [%s] %s\033[0m\n" "$color_code" "$timestamp" "${type^^}" "$message" >&2
    else
        # Print other messages to stdout
        printf "%b[%s] [%s] %s\033[0m\n" "$color_code" "$timestamp" "${type^^}" "$message"
    fi
}

# --- Core Functions ---

# Checks for root privileges and exits if not found.
initial_checks() {
    print_message "info" "Running initial system checks..."
    if [ "$(id -u)" -ne 0 ]; then
        print_message "error" "This script must be run as root or with sudo."
        exit 1
    fi
    print_message "success" "Root privileges confirmed."
}

# Detects the Linux distribution and sets global variables for the package manager.
detect_os() {
    print_message "info" "Detecting operating system..."
    if [ -f /etc/os-release ]; then
        # Source the os-release file to get OS info
        . /etc/os-release
        OS_ID=$ID
        OS_VERSION=$VERSION_ID
    else
        print_message "error" "Cannot detect operating system from /etc/os-release."
        exit 1
    fi

    case "$OS_ID" in
        "debian" | "ubuntu")
            PKG_MANAGER="apt-get"
            print_message "success" "Detected Debian/Ubuntu based system."
            ;;
        "centos" | "rhel" | "fedora" | "almalinux" | "rocky")
            if command -v dnf &> /dev/null; then
                PKG_MANAGER="dnf"
            elif command -v yum &> /dev/null; then
                PKG_MANAGER="yum"
            else
                print_message "error" "Cannot find 'dnf' or 'yum' package manager on this system."
                exit 1
            fi
            print_message "success" "Detected RHEL/CentOS/Fedora based system."
            ;;
        *)
            print_message "error" "Unsupported operating system: $OS_ID. This script supports Debian, Ubuntu, CentOS, RHEL, and Fedora."
            exit 1
            ;;
    esac
}

# This function will be called by option 1 in the menu
run_initial_setup() {
    print_message "warn" "This will install and configure the LEMP stack (Nginx, MariaDB, PHP) and set up the firewall."
    read -p "Are you sure you want to continue? [y/N]: " confirmation
    if [[ ! "$confirmation" =~ ^[yY](es)?$ ]]; then
        print_message "info" "Operation cancelled."
        return
    fi

    print_message "info" "Starting initial server setup..."
    setup_firewall
    setup_lemp_stack
    secure_mariadb
    print_message "success" "Initial server setup completed successfully."
}

# Configures the UFW firewall
setup_firewall() {
    print_message "info" "Configuring firewall (UFW)..."
    if ! command -v ufw &> /dev/null; then
        print_message "warn" "UFW command not found. Skipping firewall setup. Please install and configure it manually."
        return
    fi
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow http
    ufw allow https
    # Enable UFW non-interactively
    ufw --force enable
    print_message "success" "Firewall is configured and enabled."
}

# Installs Nginx, MariaDB, and PHP
setup_lemp_stack() {
    print_message "info" "Installing LEMP stack (Nginx, MariaDB, PHP)..."
    if [[ "$PKG_MANAGER" == "apt-get" ]]; then
        # Debian/Ubuntu
        print_message "info" "Updating package lists..."
        $PKG_MANAGER update -y
        # Find latest PHP version
        local php_version_short=$(apt-cache search --names-only '^php[0-9]+\.[0-9]+-fpm$' | cut -d' ' -f1 | sort -V | tail -n 1 | grep -oP '(?<=php)\d+\.\d+')
        if [ -z "$php_version_short" ]; then
            print_message "error" "Could not detect a suitable PHP-FPM package. Defaulting to 'php-fpm'."
            local php_packages="php-fpm php-mysql php-curl php-gd php-mbstring php-xml php-zip"
        else
            print_message "info" "Detected latest PHP version: $php_version_short"
            local php_packages="php${php_version_short}-fpm php${php_version_short}-mysql php${php_version_short}-curl php${php_version_short}-gd php${php_version_short}-mbstring php${php_version_short}-xml php${php_version_short}-zip"
        fi
        # Install packages
        $PKG_MANAGER install -y nginx mariadb-server $php_packages curl wget unzip
    elif [[ "$PKG_MANAGER" == "dnf" ]] || [[ "$PKG_MANAGER" == "yum" ]]; then
        # RHEL/CentOS/Fedora
        print_message "info" "Updating package lists..."
        $PKG_MANAGER update -y
        # Enable EPEL for Nginx on older RHEL/CentOS
        if [[ "$OS_ID" == "centos" || "$OS_ID" == "rhel" ]] && [[ ${OS_VERSION:0:1} -lt 8 ]]; then
            $PKG_MANAGER install -y epel-release
        fi
        # Install packages
        $PKG_MANAGER install -y nginx mariadb-server php-fpm php-mysqlnd php-gd php-mbstring php-xml php-zip curl wget unzip
    fi

    print_message "info" "Enabling and starting services..."
    systemctl enable --now nginx
    systemctl enable --now mariadb

    # PHP-FPM service name varies
    if systemctl list-unit-files | grep -q "php[0-9\.]*-fpm.service"; then
        local php_fpm_service=$(systemctl list-unit-files | grep -o "php[0-9\.]*-fpm.service" | head -n 1)
        systemctl enable --now "$php_fpm_service"
    elif systemctl list-unit-files | grep -q "php-fpm.service"; then
        systemctl enable --now php-fpm
    else
        print_message "warn" "Could not determine PHP-FPM service name to enable it."
    fi

    print_message "success" "LEMP stack installed."
}

# Secures the MariaDB installation
secure_mariadb() {
    print_message "info" "Securing MariaDB installation..."
    # Generate a secure root password
    local db_root_password=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 20)

    # Non-interactive security script
    mysql -u root <<-EOF
-- Set root password
ALTER USER 'root'@'localhost' IDENTIFIED BY '${db_root_password}';
-- Remove anonymous users
DELETE FROM mysql.user WHERE User='';
-- Disallow remote root login
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
-- Drop test database
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
-- Reload privilege tables
FLUSH PRIVILEGES;
EOF

    print_message "success" "MariaDB installation has been secured."
    print_message "warn" "A new random password has been set for the MariaDB 'root' user."
    print_message "warn" "Root password (save this!): ${db_root_password}"
    # Save the password to a file for future script use, with strict permissions.
    echo "${db_root_password}" > /root/.mysql_root_password
    chmod 600 /root/.mysql_root_password
    print_message "info" "Root password saved to /root/.mysql_root_password for script automation."
}

# Adds a new website with an Nginx server block and SSL
add_new_website() {
    print_message "info" "--- Add New Website ---"
    read -p "Enter the domain name (e.g., example.com): " domain_name

    if [ -z "$domain_name" ]; then
        print_message "error" "Domain name cannot be empty."
        return
    fi

    local web_root="/var/www/$domain_name"
    local nginx_conf="/etc/nginx/sites-available/$domain_name.conf"

    # Create web root directory and placeholder file
    print_message "info" "Creating web root at $web_root..."
    mkdir -p "$web_root"
    chown -R www-data:www-data "$web_root"
    # Create a placeholder index file
    cat <<EOF > "$web_root/index.html"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Welcome to $domain_name</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; margin-top: 50px; background-color: #f0f0f0; color: #333; }
        h1 { color: #0056b3; }
        p { font-size: 1.1em; }
        strong { color: #d9534f; }
    </style>
</head>
<body>
    <h1>Success!</h1>
    <p>The <strong>$domain_name</strong> server block is working.</p>
    <p>This site was set up using the server management script.</p>
</body>
</html>
EOF
    print_message "success" "Web root created."

    # Create Nginx server block
    print_message "info" "Configuring Nginx server block..."
    cat <<EOF > "$nginx_conf"
server {
    listen 80;
    listen [::]:80;

    server_name $domain_name www.$domain_name;
    root $web_root;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
    print_message "success" "Nginx configuration file created at $nginx_conf."

    # Enable the site
    ln -sf "$nginx_conf" "/etc/nginx/sites-enabled/"

    # Test and reload Nginx
    print_message "info" "Testing and reloading Nginx..."
    if nginx -t; then
        systemctl reload nginx
        print_message "success" "Nginx configuration reloaded."
    else
        print_message "error" "Nginx configuration test failed. Please check $nginx_conf"
        # Clean up failed config
        rm -f "$nginx_conf"
        rm -f "/etc/nginx/sites-enabled/${domain_name}.conf"
        return 1
    fi

    # Setup SSL
    setup_ssl_for_domain "$domain_name"
}

# Installs Certbot and obtains an SSL certificate for a given domain
setup_ssl_for_domain() {
    local domain_name=$1
    print_message "info" "Setting up SSL for $domain_name using Certbot..."

    # Install Certbot if not present
    if ! command -v certbot &> /dev/null; then
        print_message "info" "Certbot not found. Installing..."
        if [[ "$PKG_MANAGER" == "apt-get" ]]; then
            $PKG_MANAGER install -y certbot python3-certbot-nginx
        elif [[ "$PKG_MANAGER" == "dnf" ]] || [[ "$PKG_MANAGER" == "yum" ]]; then
            $PKG_MANAGER install -y certbot-nginx
        fi
        print_message "success" "Certbot installed."
    fi

    # Obtain certificate
    print_message "info" "Requesting SSL certificate for $domain_name and www.$domain_name..."
    local email
    read -p "Enter your email address (for SSL certificate notices): " email
    if [ -z "$email" ]; then
        print_message "error" "Email is required for Certbot."
        return 1
    fi

    # The --nginx flag will automatically edit the Nginx config
    if certbot --nginx --non-interactive --agree-tos --email "$email" -d "$domain_name" -d "www.$domain_name"; then
        print_message "success" "SSL certificate successfully obtained and configured for $domain_name."
    else
        print_message "error" "Failed to obtain SSL certificate for $domain_name."
        print_message "warn" "Your site is currently only available via HTTP."
        return 1
    fi
}

# Sets up a basic mail server using Postfix and Dovecot
setup_mail_server() {
    print_message "info" "--- Setup Mail Server (Postfix & Dovecot) ---"
    print_message "warn" "This is an advanced setup. You MUST have a registered domain name and have configured the MX DNS record to point to this server's hostname."
    read -p "Enter your main mail domain (e.g., example.com): " mail_domain
    if [ -z "$mail_domain" ]; then
        print_message "error" "Mail domain cannot be empty."
        return
    fi

    read -p "Enter the hostname for the mail server (e.g., mail.example.com): " mail_hostname
    if [ -z "$mail_hostname" ]; then
        print_message "error" "Mail hostname cannot be empty."
        return
    fi

    read -p "Are you sure you want to proceed? [y/N]: " confirmation
    if [[ ! "$confirmation" =~ ^[yY](es)?$ ]]; then
        print_message "info" "Operation cancelled."
        return
    fi

    # --- Installation ---
    print_message "info" "Installing Postfix and Dovecot..."
    if [[ "$PKG_MANAGER" == "apt-get" ]]; then
        # Pre-seed Postfix to avoid interactive prompts
        debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
        debconf-set-selections <<< "postfix postfix/mailname string $mail_domain"
        $PKG_MANAGER install -y postfix dovecot-core dovecot-imapd
    else
        # RHEL/CentOS/Fedora
        $PKG_MANAGER install -y postfix dovecot
    fi
    print_message "success" "Postfix and Dovecot installed."

    # --- Postfix Configuration ---
    print_message "info" "Configuring Postfix..."
    postconf -e "myhostname = $mail_hostname"
    postconf -e "mydomain = $mail_domain"
    postconf -e "myorigin = \$mydomain"
    postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
    postconf -e "mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128"
    postconf -e "home_mailbox = Maildir/"

    # SMTP-Auth settings
    postconf -e "smtpd_sasl_type = dovecot"
    postconf -e "smtpd_sasl_path = private/auth"
    postconf -e "smtpd_sasl_auth_enable = yes"
    postconf -e "smtpd_recipient_restrictions = permit_sasl_authenticated,permit_mynetworks,reject_unauth_destination"

    # TLS settings
    if [ -f "/etc/letsencrypt/live/$mail_hostname/fullchain.pem" ]; then
        print_message "info" "Found Let's Encrypt certificate for $mail_hostname."
        postconf -e "smtpd_tls_cert_file=/etc/letsencrypt/live/$mail_hostname/fullchain.pem"
        postconf -e "smtpd_tls_key_file=/etc/letsencrypt/live/$mail_hostname/privkey.pem"
        postconf -e "smtpd_tls_security_level = may"
        postconf -e "smtp_tls_security_level = may"
    else
        print_message "warn" "No SSL certificate found for $mail_hostname. Postfix will use opportunistic TLS without a certificate."
        print_message "warn" "It is highly recommended to create a website for $mail_hostname to get a certificate."
    fi

    # Enable submission port (587) in master.cf
    sed -i -E "s/^[#\s]*submission\s+inet\s+n\s+-\s+n\s+-\s+-\s+smtpd/submission inet n       -       n       -       -       smtpd/" /etc/postfix/master.cf
    sed -i -E "/^submission\s+inet/,/^\s*-o/s/^[#\s]*-o\s+smtpd_tls_security_level=encrypt/-o smtpd_tls_security_level=encrypt/" /etc/postfix/master.cf
    sed -i -E "/^submission\s+inet/,/^\s*-o/s/^[#\s]*-o\s+smtpd_sasl_auth_enable=yes/-o smtpd_sasl_auth_enable=yes/" /etc/postfix/master.cf

    print_message "success" "Postfix configured."

    # --- Dovecot Configuration ---
    print_message "info" "Configuring Dovecot..."
    # Set mail location
    sed -i "s/^#?mail_location =.*/mail_location = maildir:~\/Maildir/" /etc/dovecot/conf.d/10-mail.conf

    # Set up authentication socket for Postfix
    sed -i -E "s/^#\s*unix_listener\s+\/var\/spool\/postfix\/private\/auth/unix_listener \/var\/spool\/postfix\/private\/auth/" /etc/dovecot/conf.d/10-master.conf
    sed -i -E "/unix_listener \/var\/spool\/postfix\/private\/auth/,/}/s/^#\s*mode\s*=\s*0666/mode = 0660/" /etc/dovecot/conf.d/10-master.conf
    sed -i -E "/unix_listener \/var\/spool\/postfix\/private\/auth/,/}/s/^#\s*user\s*=\s*postfix/user = postfix/" /etc/dovecot/conf.d/10-master.conf
    sed -i -E "/unix_listener \/var\/spool\/postfix\/private\/auth/,/}/s/^#\s*group\s*=\s*postfix/group = postfix/" /etc/dovecot/conf.d/10-master.conf

    # Enable plain login auth
    sed -i "s/auth_mechanisms = plain/auth_mechanisms = plain login/" /etc/dovecot/conf.d/10-auth.conf

    # Configure SSL
    if [ -f "/etc/letsencrypt/live/$mail_hostname/fullchain.pem" ]; then
        sed -i "s/^#\s*ssl\s*=\s*yes/ssl = required/" /etc/dovecot/conf.d/10-ssl.conf
        sed -i "s|^#\s*ssl_cert\s*=\s*</etc/dovecot/private/dovecot.pem|ssl_cert = </etc/letsencrypt/live/$mail_hostname/fullchain.pem|" /etc/dovecot/conf.d/10-ssl.conf
        sed -i "s|^#\s*ssl_key\s*=\s*</etc/dovecot/private/dovecot.key|ssl_key = </etc/letsencrypt/live/$mail_hostname/privkey.pem|" /etc/dovecot/conf.d/10-ssl.conf
    else
        print_message "warn" "No SSL certificate found for $mail_hostname. Dovecot will use self-signed certs."
    fi

    print_message "success" "Dovecot configured."

    # --- Firewall & Services ---
    print_message "info" "Opening mail ports in firewall..."
    if command -v ufw &> /dev/null; then
        ufw allow 25/tcp  # SMTP
        ufw allow 587/tcp # Submission
        ufw allow 993/tcp # IMAPS
        print_message "success" "Mail ports opened."
    fi

    print_message "info" "Restarting mail services..."
    systemctl restart postfix
    systemctl restart dovecot

    print_message "success" "Mail server setup is complete."
    print_message "info" "You can now add email accounts by creating standard Linux users (e.g., 'useradd -m username')."
}

# Creates a new user restricted to SFTP access in a specific directory.
create_sftp_user() {
    print_message "info" "--- Create New SFTP User ---"
    read -p "Enter the new SFTP username: " sftp_user
    if [ -z "$sftp_user" ]; then
        print_message "error" "SFTP username cannot be empty."
        return
    fi

    read -s -p "Enter the password for $sftp_user: " sftp_password
    echo
    if [ -z "$sftp_password" ]; then
        print_message "error" "Password cannot be empty."
        return
    fi

    read -p "Enter the full path of the directory to grant access to (e.g., /var/www/example.com): " sftp_dir
    if [ ! -d "$sftp_dir" ]; then
        print_message "error" "Directory '$sftp_dir' does not exist."
        return
    fi

    # --- Chroot Directory Ownership Check ---
    # The ChrootDirectory and all its components must be owned by root.
    local owner=$(stat -c '%U' "$sftp_dir")
    if [ "$owner" != "root" ]; then
        print_message "error" "SFTP Jail Requirement Failed: The directory '$sftp_dir' must be owned by 'root'."
        print_message "warn" "A common practice is to have a root-owned jail (e.g., /var/www/domain) and a writable subdirectory inside it (e.g., /var/www/domain/public_html) owned by the sftp user."
        return 1
    fi

    print_message "info" "Creating user '$sftp_user' and configuring SFTP jail..."

    # Create user with no shell access and add to www-data group
    useradd --home "$sftp_dir" --shell "/usr/sbin/nologin" --gid "www-data" "$sftp_user" &>/dev/null || print_message "info" "User '$sftp_user' may already exist. Proceeding with configuration."
    echo "$sftp_user:$sftp_password" | chpasswd
    print_message "success" "User '$sftp_user' created/password updated."

    # Configure sshd_config
    print_message "info" "Configuring SSH server for SFTP jail..."
    local sshd_config="/etc/ssh/sshd_config"

    # Ensure the SFTP subsystem is configured for jailing
    if ! grep -q "Subsystem sftp internal-sftp" "$sshd_config"; then
        sed -i 's|^Subsystem\s*sftp\s*/usr/lib/openssh/sftp-server|Subsystem sftp internal-sftp|' "$sshd_config"
        # If the line still doesn't exist, add it
        if ! grep -q "Subsystem sftp internal-sftp" "$sshd_config"; then
            echo "Subsystem sftp internal-sftp" >> "$sshd_config"
        fi
    fi

    # Check if a Match block for the user already exists
    if ! grep -q "Match User $sftp_user" "$sshd_config"; then
        # Append Match User block
        tee -a "$sshd_config" <<EOF

Match User $sftp_user
    ForceCommand internal-sftp
    PasswordAuthentication yes
    ChrootDirectory $sftp_dir
    AllowTcpForwarding no
    X11Forwarding no
EOF
        print_message "success" "SFTP jail configured for '$sftp_user' in $sshd_config."
    else
        print_message "info" "SFTP configuration for '$sftp_user' already exists."
    fi

    # The chroot directory itself must be root-owned with 755 permissions.
    chmod 755 "$sftp_dir"

    # Create a writable subdirectory for the user
    local writable_dir="${sftp_dir}/public_html"
    print_message "info" "Creating writable directory at ${writable_dir}..."
    mkdir -p "$writable_dir"
    chown "${sftp_user}:www-data" "$writable_dir"
    chmod 755 "$writable_dir"
    print_message "success" "Writable directory created."

    # Restart SSH service
    print_message "info" "Restarting SSH service..."
    systemctl restart sshd
    print_message "success" "SSH service restarted."
    print_message "success" "SFTP user '$sftp_user' is ready. User is jailed to '${sftp_dir}' and has write access to '${writable_dir}'."
}

# Backs up a website's files and database
backup_website() {
    print_message "info" "--- Backup Website ---"
    read -p "Enter the domain of the site to back up (e.g., example.com): " domain_name
    if [ -z "$domain_name" ]; then
        print_message "error" "Domain name cannot be empty."
        return
    fi

    local web_root="/var/www/$domain_name"
    if [ ! -d "$web_root" ]; then
        print_message "error" "Web root '$web_root' does not exist."
        return
    fi

    read -p "Enter the name of the database to back up: " db_name
    if [ -z "$db_name" ]; then
        print_message "error" "Database name cannot be empty."
        return
    fi

    local backup_dir="/root/backups"
    mkdir -p "$backup_dir"
    local timestamp=$(date "+%Y-%m-%d-%H%M%S")
    local backup_file="$backup_dir/backup-${domain_name}-${timestamp}.tar.gz"
    local temp_dir=$(mktemp -d)

    print_message "info" "Starting backup for '$domain_name'..."

    # Backup database
    print_message "info" "Dumping database '$db_name'..."
    if [ ! -f "/root/.mysql_root_password" ]; then
        print_message "error" "MariaDB root password file not found. Cannot automate backup."
        rm -rf "$temp_dir"
        return 1
    fi
    local db_root_pw=$(cat /root/.mysql_root_password)
    mysqldump -u root -p"${db_root_pw}" "${db_name}" > "${temp_dir}/${db_name}.sql"
    if [ $? -ne 0 ]; then
        print_message "error" "Database dump failed. Check if database '$db_name' exists."
        rm -rf "$temp_dir"
        return 1
    fi
    print_message "success" "Database dumped successfully."

    # Create archive of web files
    print_message "info" "Archiving web root contents from '$web_root'..."
    mkdir -p "${temp_dir}/web_root_content"
    # Copy contents of web_root, not the directory itself, to allow for flexible restore.
    # The `/.` ensures that the contents of the directory are copied, not the directory itself.
    cp -a "${web_root}/." "${temp_dir}/web_root_content/"

    # Create final combined archive
    print_message "info" "Creating final backup file at '$backup_file'..."
    tar -czf "$backup_file" -C "$temp_dir" .

    # Cleanup
    rm -rf "$temp_dir"

    print_message "success" "Backup complete! File saved to: $backup_file"
}

# Restores a website from a backup file
restore_website() {
    print_message "info" "--- Restore Website from Backup ---"
    print_message "warn" "This is a DESTRUCTIVE operation. It will overwrite website files and database content."

    read -p "Enter the full path to the backup file to restore: " backup_file
    if [ ! -f "$backup_file" ]; then
        print_message "error" "Backup file not found at '$backup_file'."
        return
    fi

    read -p "Enter the domain name you are restoring (e.g., example.com): " domain_name
    if [ -z "$domain_name" ]; then
        print_message "error" "Domain name cannot be empty."
        return
    fi

    local web_root="/var/www/$domain_name"
    read -p "Enter the name of the database to restore into: " db_name
    if [ -z "$db_name" ]; then
        print_message "error" "Database name cannot be empty."
        return
    fi

    print_message "warn" "This will overwrite all files in '$web_root' and all tables in the database '$db_name'."
    read -p "To confirm, please type the domain name '$domain_name': " confirmation
    if [ "$confirmation" != "$domain_name" ]; then
        print_message "error" "Confirmation failed. Restore operation cancelled."
        return
    fi

    local temp_dir=$(mktemp -d)
    print_message "info" "Extracting backup file..."
    tar -xzf "$backup_file" -C "$temp_dir"

    # Restore Files
    local backup_content_dir="${temp_dir}/web_root_content"
    if [ -d "$backup_content_dir" ]; then
        print_message "info" "Restoring files to '$web_root'..."
        # Safety: move existing directory
        if [ -d "$web_root" ]; then
            mv "$web_root" "${web_root}.bak-$(date "+%Y%m%d%H%M%S")"
            print_message "info" "Existing web root moved to '${web_root}.bak-...'."
        fi

        # Create the new web root and copy contents from the backup.
        mkdir -p "$web_root"
        # Using cp -a with /.' to copy all contents including hidden files.
        cp -a "${backup_content_dir}/." "$web_root/"

        chown -R www-data:www-data "$web_root"
        print_message "success" "Files restored."
    else
        print_message "warn" "No 'web_root_content' directory found in backup archive. Skipping file restore."
        print_message "info" "Note: This script may not be able to restore backups made with older versions."
    fi

    # Restore Database
    local sql_file=$(find "$temp_dir" -name "*.sql" -type f | head -n 1)
    if [ -n "$sql_file" ]; then
        print_message "info" "Restoring database '$db_name' from '$(basename "$sql_file")'..."
        if [ ! -f "/root/.mysql_root_password" ]; then
            print_message "error" "MariaDB root password file not found. Cannot automate restore."
            rm -rf "$temp_dir"
            return 1
        fi
        local db_root_pw=$(cat /root/.mysql_root_password)
        # Ensure database exists
        mysql -u root -p"${db_root_pw}" -e "CREATE DATABASE IF NOT EXISTS \`${db_name}\`;"
        mysql -u root -p"${db_root_pw}" "${db_name}" < "$sql_file"
        if [ $? -ne 0 ]; then
            print_message "error" "Database restore failed."
            rm -rf "$temp_dir"
            return 1
        fi
        print_message "success" "Database restored."
    else
        print_message "warn" "No .sql file found in backup archive. Skipping database restore."
    fi

    # Cleanup
    rm -rf "$temp_dir"
    print_message "success" "Restore complete for '$domain_name'."
}

# Displays the main menu of the script.
show_main_menu() {
    clear
    echo
    print_message "info" "============================================="
    print_message "info" "      Server Setup & Management Menu"
    print_message "info" "============================================="
    echo
    echo " --- Initial Setup ---"
    echo "  1. Initial Server Setup (Update, Firewall, LEMP)"
    echo "  2. Add New Website (with SSL)"
    echo "  3. Setup Mail Server (Postfix & Dovecot)"
    echo "  4. Create SFTP User"
    echo
    echo " --- Utilities ---"
    echo "  5. Backup Website"
    echo "  6. Restore Website"
    echo
    echo " --- Management ---"
    echo "  7. Manage Existing Services"
    echo "  8. Exit"
    echo
}

# --- Website Management Functions ---

# Lists Nginx sites based on status (enabled, disabled, or all)
list_nginx_sites() {
    local status=$1 # "enabled", "disabled", or "all"
    local sites_available="/etc/nginx/sites-available"
    local sites_enabled="/etc/nginx/sites-enabled"

    # Exclude default config and ensure directory exists
    if [ ! -d "$sites_available" ]; then return; fi
    local all_sites=$(ls "$sites_available" | grep -v "default" || true)

    if [ -z "$all_sites" ]; then
        print_message "warn" "No website configurations found."
        return 1
    fi

    print_message "info" "--- Available Websites ---"
    for site in $all_sites; do
        local symlink_path="$sites_enabled/$site"
        if [[ "$status" == "enabled" && -L "$symlink_path" ]]; then
            echo "  - $site (Enabled)"
        elif [[ "$status" == "disabled" && ! -L "$symlink_path" ]]; then
            echo "  - $site (Disabled)"
        elif [[ "$status" == "all" ]]; then
            if [ -L "$symlink_path" ]; then
                echo "  - $site (Enabled)"
            else
                echo "  - $site (Disabled)"
            fi
        fi
    done
    echo "------------------------"
    return 0
}

# Deletes a website completely
delete_website() {
    print_message "info" "--- Delete Website ---"
    list_nginx_sites "all" || return

    read -p "Enter the full config name of the website to delete (e.g., example.com.conf): " site_conf
    local domain=$(basename "$site_conf" .conf)

    if [ -z "$site_conf" ] || [ ! -f "/etc/nginx/sites-available/$site_conf" ]; then
        print_message "error" "Invalid selection or config file not found."
        return
    fi

    print_message "warn" "This will permanently delete the Nginx config, web files at /var/www/$domain, the SSL certificate, and optionally the database."
    read -p "To confirm, please type the domain name '$domain': " confirmation
    if [ "$confirmation" != "$domain" ]; then
        print_message "error" "Confirmation failed. Deletion cancelled."
        return
    fi

    # Delete Nginx files
    rm -f "/etc/nginx/sites-available/$site_conf"
    rm -f "/etc/nginx/sites-enabled/$site_conf"
    print_message "info" "Nginx configuration removed."

    # Delete web root
    if [ -d "/var/www/$domain" ]; then
        rm -rf "/var/www/$domain"
        print_message "info" "Web root directory /var/www/$domain removed."
    fi

    # Delete SSL certificate
    if command -v certbot &> /dev/null; then
        certbot delete --non-interactive --cert-name "$domain" &>/dev/null || print_message "warn" "Could not delete SSL certificate for $domain. It may not exist."
        print_message "info" "SSL certificate for $domain deletion attempted."
    fi

    # Delete database
    read -p "Do you want to delete the associated database? [y/N]: " del_db
    if [[ "$del_db" =~ ^[yY](es)?$ ]]; then
        read -p "Enter the database name to delete: " db_name
        if [ -n "$db_name" ]; then
            if [ ! -f "/root/.mysql_root_password" ]; then
                print_message "error" "MariaDB root password file not found. Cannot automate database deletion."
            else
                local db_root_pw=$(cat /root/.mysql_root_password)
                mysql -u root -p"${db_root_pw}" -e "DROP DATABASE IF EXISTS \`${db_name}\`;"
                print_message "info" "Database '$db_name' deleted."
            fi
        fi
    fi

    systemctl reload nginx
    print_message "success" "Website '$domain' has been completely deleted."
}

# Disables an active Nginx site
disable_website() {
    print_message "info" "--- Disable Website ---"
    list_nginx_sites "enabled" || return

    read -p "Enter the config name of the site to disable: " site_conf
    if [ -z "$site_conf" ] || [ ! -L "/etc/nginx/sites-enabled/$site_conf" ]; then
        print_message "error" "Invalid selection or site is not enabled."
        return
    fi

    rm -f "/etc/nginx/sites-enabled/$site_conf"
    systemctl reload nginx
    print_message "success" "Site '$site_conf' has been disabled."
}

# Enables an inactive Nginx site
enable_website() {
    print_message "info" "--- Enable Website ---"
    list_nginx_sites "disabled" || return

    read -p "Enter the config name of the site to enable: " site_conf
    if [ -z "$site_conf" ] || [ ! -f "/etc/nginx/sites-available/$site_conf" ] || [ -L "/etc/nginx/sites-enabled/$site_conf" ]; then
        print_message "error" "Invalid selection or site is already enabled."
        return
    fi

    ln -s "/etc/nginx/sites-available/$site_conf" "/etc/nginx/sites-enabled/"
    systemctl reload nginx
    print_message "success" "Site '$site_conf' has been enabled."
}

# Main function for website management sub-menu
manage_websites() {
    while true; do
        clear
        print_message "info" "--- Website Management Menu ---"
        list_nginx_sites "all" || { read -n 1 -s -r -p "Press any key to return..."; break; }
        echo
        echo "  1. Delete a Website"
        echo "  2. Disable a Website"
        echo "  3. Enable a Website"
        echo "  4. Back to Management Menu"
        echo
        read -rp "Enter your choice [1-4]: " choice
        case $choice in
            1) delete_website ;;
            2) disable_website ;;
            3) enable_website ;;
            4) break ;;
            *) print_message "warn" "Invalid option." ;;
        esac
        read -n 1 -s -r -p "Press any key to continue..."
    done
}

# --- SFTP User Management Functions ---

# Lists SFTP users by parsing sshd_config
list_sftp_users() {
    print_message "info" "--- Jailed SFTP Users ---"
    # This grep command uses a Perl-compatible regex to find usernames after "Match User"
    local users=$(grep -oP '(?<=^Match User\s)\S+' /etc/ssh/sshd_config || true)
    if [ -z "$users" ]; then
        print_message "warn" "No SFTP users configured in /etc/ssh/sshd_config."
        return 1
    fi
    for user in $users; do
        echo "  - $user"
    done
    echo "-------------------------"
    return 0
}

# Changes the password for an SFTP user
change_sftp_password() {
    print_message "info" "--- Change SFTP User Password ---"
    list_sftp_users || return

    read -p "Enter the username to modify: " sftp_user
    if [ -z "$sftp_user" ]; then
        print_message "error" "Username cannot be empty."
        return
    fi

    # Verify user exists in the SFTP config
    if ! grep -q "^Match User $sftp_user" /etc/ssh/sshd_config; then
        print_message "error" "User '$sftp_user' is not a configured SFTP user."
        return
    fi

    read -s -p "Enter the new password for $sftp_user: " sftp_password
    echo
    if [ -z "$sftp_password" ]; then
        print_message "error" "Password cannot be empty."
        return
    fi

    echo "$sftp_user:$sftp_password" | chpasswd
    print_message "success" "Password for '$sftp_user' has been changed."
}

# Deletes an SFTP user and their configuration
delete_sftp_user() {
    print_message "info" "--- Delete SFTP User ---"
    list_sftp_users || return

    read -p "Enter the username to delete: " sftp_user
    if [ -z "$sftp_user" ]; then
        print_message "error" "Username cannot be empty."
        return
    fi

    # Verify user exists in the SFTP config
    if ! grep -q "^Match User $sftp_user" /etc/ssh/sshd_config; then
        print_message "error" "User '$sftp_user' is not a configured SFTP user."
        return
    fi

    print_message "warn" "This will permanently delete the user '$sftp_user' and their SFTP configuration."
    read -p "To confirm, please type the username '$sftp_user': " confirmation
    if [ "$confirmation" != "$sftp_user" ]; then
        print_message "error" "Confirmation failed. Deletion cancelled."
        return
    fi

    # Delete user
    userdel "$sftp_user"
    print_message "info" "System user '$sftp_user' deleted."

    # Remove sshd_config block. This is tricky.
    # We create a temp file, copy the config excluding the user's block, then replace the original.
    local temp_sshd_config=$(mktemp)
    awk -v user="$sftp_user" '
        # If we find the start of the block for our user, set a flag and skip the line.
        $1 == "Match" && $2 == "User" && $3 == user { in_block=1; next }
        # If we are in the block and see a new Match block or are at the end of the file, we are out of the block.
        $1 == "Match" || END { in_block=0 }
        # If we are not in the block, print the line.
        !in_block { print }
    ' /etc/ssh/sshd_config > "$temp_sshd_config"

    # Verify the temp file is not empty before overwriting
    if [ -s "$temp_sshd_config" ]; then
        cp "$temp_sshd_config" /etc/ssh/sshd_config
        rm "$temp_sshd_config"
        print_message "success" "SFTP configuration for '$sftp_user' removed from /etc/ssh/sshd_config."
    else
        print_message "error" "Failed to edit sshd_config. The temporary file was empty. Aborting change."
        rm "$temp_sshd_config"
        return 1
    fi

    # Restart SSH
    systemctl restart sshd
    print_message "success" "SFTP user '$sftp_user' has been deleted."
}

# Main function for SFTP user management
manage_sftp_users() {
    while true; do
        clear
        print_message "info" "--- SFTP User Management ---"
        list_sftp_users || { read -n 1 -s -r -p "Press any key to return..."; break; }
        echo
        echo "  1. Change User Password"
        echo "  2. Delete User"
        echo "  3. Back to Management Menu"
        echo
        read -rp "Enter your choice [1-3]: " choice
        case $choice in
            1) change_sftp_password ;;
            2) delete_sftp_user ;;
            3) break ;;
            *) print_message "warn" "Invalid option." ;;
        esac
        read -n 1 -s -r -p "Press any key to continue..."
    done
}

# --- Mail User Management Functions ---

# Lists mail users (standard users with home directories)
list_mail_users() {
    print_message "info" "--- Email Accounts ---"
    # This awk command lists users with UID >= 1000 and a home dir in /home
    local users=$(awk -F: '$3 >= 1000 && $6 ~ /^\/home/ { print $1 }' /etc/passwd || true)
    if [ -z "$users" ]; then
        print_message "warn" "No mail/system users found."
        return 1
    fi
    for user in $users; do
        echo "  - $user"
    done
    echo "----------------------"
    return 0
}

# Adds a new email account (system user)
add_mail_user() {
    print_message "info" "--- Add Email Account ---"
    read -p "Enter the new email username (e.g., 'contact' for 'contact@domain.com'): " user_name
    if [ -z "$user_name" ]; then
        print_message "error" "Username cannot be empty."
        return
    fi

    read -s -p "Enter the password for this account: " user_password
    echo
    if [ -z "$user_password" ]; then
        print_message "error" "Password cannot be empty."
        return
    fi

    # Create user with a home directory and no shell access
    useradd -m -s /usr/sbin/nologin "$user_name"
    echo "$user_name:$user_password" | chpasswd

    print_message "success" "Email account '$user_name' created. The user can now log in via IMAP."
}

# Deletes an email account
delete_mail_user() {
    print_message "info" "--- Delete Email Account ---"
    list_mail_users || return

    read -p "Enter the username of the account to delete: " user_name
    if [ -z "$user_name" ]; then
        print_message "error" "Username cannot be empty."
        return
    fi

    # Verify user exists
    if ! id "$user_name" &>/dev/null; then
        print_message "error" "User '$user_name' does not exist."
        return
    fi

    print_message "warn" "This will permanently delete the user '$user_name' and all their emails."
    read -p "To confirm, please type the username '$user_name': " confirmation
    if [ "$confirmation" != "$user_name" ]; then
        print_message "error" "Confirmation failed. Deletion cancelled."
        return
    fi

    # Delete the user and their home directory (-r)
    userdel -r "$user_name"
    print_message "success" "Email account '$user_name' and all associated data have been deleted."
}

# Main function for mail user management
manage_mail_users() {
    while true; do
        clear
        print_message "info" "--- Email Account Management ---"
        echo
        echo "  1. Add Email Account"
        echo "  2. Delete Email Account"
        echo "  3. List Email Accounts"
        echo "  4. Back to Management Menu"
        echo
        read -rp "Enter your choice [1-4]: " choice
        case $choice in
            1) add_mail_user ;;
            2) delete_mail_user ;;
            3) list_mail_users ;;
            4) break ;;
            *) print_message "warn" "Invalid option." ;;
        esac
        read -n 1 -s -r -p "Press any key to continue..."
    done
}

# --- Management Menu ---

show_management_menu() {
    clear
    echo
    print_message "info" "============================================="
    print_message "info" "        Manage Existing Services"
    print_message "info" "============================================="
    echo
    echo "  1. Manage Websites"
    echo "  2. Manage SFTP Users"
    echo "  3. Manage Email Accounts"
    echo "  4. Back to Main Menu"
    echo
}

run_management_menu() {
    while true; do
        show_management_menu
        read -rp "Enter your choice [1-4]: " choice
        case $choice in
            1) manage_websites ;;
            2) manage_sftp_users ;;
            3) manage_mail_users ;;
            4)
                print_message "info" "Returning to main menu."
                break
                ;;
            *)
                print_message "warn" "Invalid option. Please try again."
                ;;
        esac
        read -n 1 -s -r -p "Press any key to continue..."
    done
}

# --- Main Execution Logic ---

main() {
    # Ensure log file exists and has correct permissions
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"

    initial_checks
    detect_os

    while true; do
        show_main_menu
        read -rp "Enter your choice [1-8]: " choice
        case $choice in
            1) run_initial_setup ;;
            2) add_new_website ;;
            3) setup_mail_server ;;
            4) create_sftp_user ;;
            5) backup_website ;;
            6) restore_website ;;
            7) run_management_menu ;;
            8)
                print_message "info" "Exiting script. Goodbye!"
                break
                ;;
            *)
                print_message "warn" "Invalid option. Please try again."
                ;;
        esac
        # Pause for user to read message before showing menu again
        read -n 1 -s -r -p "Press any key to continue..."
    done
}

# --- Script Entry Point ---
# Redirect all output (stdout and stderr) to both console and log file
exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)

# Run the main function
main
