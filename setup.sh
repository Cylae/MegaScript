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
SCRIPT_LANG="en" # Default language

# --- Helper Functions ---

# Provides colored and timestamped output for script messages.
# Usage: print_message "info" "This is a simple message."
# For formatted messages, format the string first:
#   local msg; msg=$(printf "$VAR_WITH_FORMAT" "value")
#   print_message "info" "$msg"
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

# A function to read user input with validation and looping.
# Usage: read_with_validation "prompt" "variable_name" "validation_type" ["error_message"]
# Returns 0 on successful read.
read_with_validation() {
    local prompt_msg="$1"
    local -n var_name="$2" # Nameref to assign to the variable in the caller's scope
    local type="$3"
    local error_msg="$4" # Optional custom error message
    local regex

    case "$type" in
        "domain")
            # More compliant regex for domain names
            regex='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
            [ -z "$error_msg" ] && error_msg="$MSG_ERROR_INVALID_DOMAIN"
            ;;
        "email")
            regex='^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
            [ -z "$error_msg" ] && error_msg="$MSG_ERROR_INVALID_EMAIL"
            ;;
        "username")
            # Basic linux username validation
            regex='^[a-z_][a-z0-9_-]{0,30}$'
            [ -z "$error_msg" ] && error_msg="$MSG_ERROR_INVALID_USERNAME"
            ;;
        "path")
            regex='^\/.*$'
            [ -z "$error_msg" ] && error_msg="$MSG_ERROR_INVALID_PATH"
            ;;
        "db_name")
            regex='^[a-zA-Z0-9_]+$'
            [ -z "$error_msg" ] && error_msg="$MSG_ERROR_INVALID_DB_NAME"
            ;;
        "not_empty")
            # Loop until a non-empty value is provided
            while true; do
                read -p "$prompt_msg" var_name
                if [ -n "$var_name" ]; then
                    return 0
                fi
                print_message "error" "${error_msg:-$MSG_ERROR_CANNOT_BE_EMPTY}"
            done
            ;;
        *)
            # Default behavior: just read without any validation
            read -p "$prompt_msg" var_name
            return 0
            ;;
    esac

    # Loop for regex-based validations
    while true; do
        read -p "$prompt_msg" var_name
        # Also check for empty on regex types, as most should not be empty
        if [ -z "$var_name" ]; then
            print_message "error" "${MSG_ERROR_CANNOT_BE_EMPTY}"
            continue
        fi
        if [[ "$var_name" =~ $regex ]]; then
            break
        else
            print_message "error" "$error_msg"
        fi
    done
}

# --- Core Functions ---

# Checks for root privileges and exits if not found.
initial_checks() {
    print_message "info" "$MSG_INFO_RUNNING_CHECKS"
    if [ "$(id -u)" -ne 0 ]; then
        print_message "error" "$MSG_ERROR_MUST_BE_ROOT"
        exit 1
    fi
    print_message "success" "$MSG_SUCCESS_ROOT_CONFIRMED"
}

# Detects the Linux distribution and sets global variables for the package manager.
detect_os() {
    print_message "info" "$MSG_INFO_DETECTING_OS"
    if [ -f /etc/os-release ]; then
        # Source the os-release file to get OS info
        . /etc/os-release
        OS_ID=$ID
        OS_VERSION=$VERSION_ID
    else
        print_message "error" "$MSG_ERROR_CANNOT_DETECT_OS"
        exit 1
    fi

    case "$OS_ID" in
        "debian" | "ubuntu")
            PKG_MANAGER="apt-get"
            print_message "success" "$MSG_SUCCESS_DEBIAN_BASED"
            ;;
        "centos" | "rhel" | "fedora" | "almalinux" | "rocky")
            if command -v dnf &> /dev/null; then
                PKG_MANAGER="dnf"
            elif command -v yum &> /dev/null; then
                PKG_MANAGER="yum"
            else
                print_message "error" "$MSG_ERROR_NO_PKG_MANAGER"
                exit 1
            fi
            print_message "success" "$MSG_SUCCESS_RHEL_BASED"
            ;;
        *)
            local msg; msg=$(printf "$MSG_ERROR_UNSUPPORTED_OS" "$OS_ID")
            print_message "error" "$msg"
            exit 1
            ;;
    esac
}

# This function will be called by option 1 in the menu
run_initial_setup() {
    print_message "warn" "$MSG_WARN_INITIAL_SETUP"
    local confirmation_prompt="$PROMPT_ARE_YOU_SURE"
    read -p "$confirmation_prompt " confirmation
    if [[ ! "$confirmation" =~ ^[yYoO](es|ui)?$ ]]; then
        print_message "info" "$MSG_INFO_OPERATION_CANCELLED"
        return
    fi

    print_message "info" "$MSG_INFO_STARTING_SETUP"
    setup_firewall
    setup_lemp_stack
    secure_mariadb
    print_message "success" "$MSG_SUCCESS_SETUP_COMPLETE"
}

# Configures the UFW firewall
setup_firewall() {
    print_message "info" "$MSG_INFO_CONFIG_FIREWALL"
    if ! command -v ufw &> /dev/null; then
        print_message "warn" "$MSG_WARN_UFW_NOT_FOUND"
        return
    fi
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow http
    ufw allow https
    # Enable UFW non-interactively
    ufw --force enable
    print_message "success" "$MSG_SUCCESS_FIREWALL_CONFIGURED"
}

# Installs Nginx, MariaDB, and PHP
setup_lemp_stack() {
    print_message "info" "$MSG_INFO_INSTALLING_LEMP"
    if [[ "$PKG_MANAGER" == "apt-get" ]]; then
        # Debian/Ubuntu
        print_message "info" "$MSG_INFO_UPDATING_PACKAGES"
        $PKG_MANAGER update -y
        # Find latest PHP version
        local php_version_short=$(apt-cache search --names-only '^php[0-9]+\.[0-9]+-fpm$' | cut -d' ' -f1 | sort -V | tail -n 1 | grep -oP '(?<=php)\d+\.\d+')
        if [ -z "$php_version_short" ]; then
            print_message "warn" "$MSG_ERROR_PHP_FPM_NOT_FOUND"
            local php_packages="php-fpm php-mysql php-curl php-gd php-mbstring php-xml php-zip"
        else
            local msg; msg=$(printf "$MSG_INFO_PHP_VERSION_DETECTED" "$php_version_short")
            print_message "info" "$msg"
            local php_packages="php${php_version_short}-fpm php${php_version_short}-mysql php${php_version_short}-curl php${php_version_short}-gd php${php_version_short}-mbstring php${php_version_short}-xml php${php_version_short}-zip"
        fi
        # Install packages
        $PKG_MANAGER install -y nginx mariadb-server $php_packages curl wget unzip
    elif [[ "$PKG_MANAGER" == "dnf" ]] || [[ "$PKG_MANAGER" == "yum" ]]; then
        # RHEL/CentOS/Fedora
        print_message "info" "$MSG_INFO_UPDATING_PACKAGES"
        $PKG_MANAGER update -y
        # Enable EPEL for Nginx on older RHEL/CentOS
        if [[ "$OS_ID" == "centos" || "$OS_ID" == "rhel" ]] && [[ ${OS_VERSION:0:1} -lt 8 ]]; then
            $PKG_MANAGER install -y epel-release
        fi
        # Install packages
        $PKG_MANAGER install -y nginx mariadb-server php-fpm php-mysqlnd php-gd php-mbstring php-xml php-zip curl wget unzip
    fi

    print_message "info" "$MSG_INFO_ENABLE_SERVICES"
    systemctl enable --now nginx
    systemctl enable --now mariadb

    # PHP-FPM service name varies
    if systemctl list-unit-files | grep -q "php[0-9\.]*-fpm.service"; then
        local php_fpm_service=$(systemctl list-unit-files | grep -o "php[0-9\.]*-fpm.service" | head -n 1)
        systemctl enable --now "$php_fpm_service"
    elif systemctl list-unit-files | grep -q "php-fpm.service"; then
        systemctl enable --now php-fpm
    else
        print_message "warn" "$MSG_WARN_PHP_FPM_SERVICE_UNKNOWN"
    fi

    print_message "success" "$MSG_SUCCESS_LEMP_INSTALLED"
}

# Secures the MariaDB installation
secure_mariadb() {
    print_message "info" "$MSG_INFO_SECURING_MARIADB"
    # Generate a secure root password
    local db_root_password=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 20)

    # Non-interactive security script
    # Use sudo to ensure it works with socket authentication
    sudo mysql -u root <<-EOF
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

    print_message "success" "$MSG_SUCCESS_MARIADB_SECURED"
    print_message "warn" "$MSG_WARN_MARIADB_ROOT_PASSWORD_SET"
    local msg; msg=$(printf "$MSG_WARN_MARIADB_ROOT_PASSWORD_IS" "$db_root_password")
    print_message "warn" "$msg"
    # Save the password to a file for future script use, with strict permissions.
    echo "${db_root_password}" > /root/.mysql_root_password
    chmod 600 /root/.mysql_root_password
    print_message "info" "$MSG_INFO_MARIADB_PASSWORD_SAVED"
}

# Adds a new website with an Nginx server block and SSL
add_new_website() {
    print_message "info" "$MENU_ADD_WEBSITE"
    local domain_name
    read_with_validation "$PROMPT_ENTER_DOMAIN" domain_name "domain"
    local email
    read_with_validation "$PROMPT_ENTER_EMAIL" email "email"

    add_new_website_logic "$domain_name" "$email"
}

# Core logic for adding a new website
add_new_website_logic() {
    local domain_name=$1
    local email=$2
    local web_root="/var/www/$domain_name"
    local nginx_conf="/etc/nginx/sites-available/$domain_name.conf"

    # Create web root directory and placeholder file
    local msg; msg=$(printf "$MSG_INFO_CREATING_WEB_ROOT" "$web_root")
    print_message "info" "$msg"
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
    print_message "success" "$MSG_SUCCESS_WEB_ROOT_CREATED"

    # Create Nginx server block
    print_message "info" "$MSG_INFO_CONFIGURING_NGINX"
    cat <<EOF > "$nginx_conf"
server {
    listen 80;

    server_name $domain_name www.$domain_name;
    root $web_root;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
    local msg2; msg2=$(printf "$MSG_SUCCESS_NGINX_CONF_CREATED" "$nginx_conf")
    print_message "success" "$msg2"

    # Enable the site
    ln -sf "$nginx_conf" "/etc/nginx/sites-enabled/"

    # Test and reload Nginx
    print_message "info" "$MSG_INFO_TESTING_NGINX"
    if nginx -t; then
        systemctl reload nginx
        print_message "success" "$MSG_SUCCESS_NGINX_RELOADED"
    else
        local msg3; msg3=$(printf "$MSG_ERROR_NGINX_TEST_FAILED" "$nginx_conf")
        print_message "error" "$msg3"
        # Clean up failed config
        rm -f "$nginx_conf"
        rm -f "/etc/nginx/sites-enabled/${domain_name}.conf"
        return 1
    fi

    # Setup SSL
    setup_ssl_for_domain "$domain_name" "$email"
}

# Installs Certbot and obtains an SSL certificate for a given domain
setup_ssl_for_domain() {
    local domain_name=$1
    local email=$2
    local msg; msg=$(printf "$MSG_INFO_SETTING_UP_SSL" "$domain_name")
    print_message "info" "$msg"

    # Install Certbot if not present
    if ! command -v certbot &> /dev/null; then
        print_message "info" "$MSG_INFO_CERTBOT_NOT_FOUND"
        if [[ "$PKG_MANAGER" == "apt-get" ]]; then
            $PKG_MANAGER install -y certbot python3-certbot-nginx
        elif [[ "$PKG_MANAGER" == "dnf" ]] || [[ "$PKG_MANAGER" == "yum" ]]; then
            $PKG_MANAGER install -y certbot-nginx
        fi
        print_message "success" "$MSG_SUCCESS_CERTBOT_INSTALLED"
    fi

    # Obtain certificate
    local msg2; msg2=$(printf "$MSG_INFO_REQUESTING_CERT" "$domain_name" "$domain_name")
    print_message "info" "$msg2"

    # The --nginx flag will automatically edit the Nginx config
    if certbot --nginx --non-interactive --agree-tos --email "$email" -d "$domain_name" -d "www.$domain_name"; then
        local msg3; msg3=$(printf "$MSG_SUCCESS_SSL_OBTAINED" "$domain_name")
        print_message "success" "$msg3"
    else
        local msg4; msg4=$(printf "$MSG_ERROR_SSL_FAILED" "$domain_name")
        print_message "error" "$msg4"
        print_message "warn" "$MSG_WARN_SITE_HTTP_ONLY"
        return 1
    fi
}

# Installs augeas-tools if not present.
install_augeas_if_needed() {
    if ! command -v augtool &> /dev/null; then
        print_message "info" "$MSG_INFO_INSTALLING_AUGEAS"
        if [[ -n "$PKG_MANAGER" ]]; then
            $PKG_MANAGER update -y
            $PKG_MANAGER install -y augeas-tools
            print_message "success" "$MSG_SUCCESS_AUGEAS_INSTALLED"
        else
            print_message "error" "$MSG_ERROR_CANNOT_INSTALL_AUGEAS"
            return 1
        fi
    fi
}

# Sets up a basic mail server using Postfix and Dovecot
setup_mail_server() {
    print_message "info" "$MENU_SETUP_MAIL_SERVER"
    print_message "warn" "$MSG_WARN_MAIL_ADVANCED_SETUP"
    local mail_domain
    read_with_validation "$PROMPT_ENTER_MAIL_DOMAIN" mail_domain "domain"

    local mail_hostname
    read_with_validation "$PROMPT_ENTER_MAIL_HOSTNAME" mail_hostname "domain"

    read -p "$PROMPT_ARE_YOU_SURE " confirmation
    if [[ ! "$confirmation" =~ ^[yYoO](es|ui)?$ ]]; then
        print_message "info" "$MSG_INFO_OPERATION_CANCELLED"
        return
    fi

    setup_mail_server_logic "$mail_domain" "$mail_hostname"
}

# Core logic for setting up the mail server.
setup_mail_server_logic() {
    local mail_domain=$1
    local mail_hostname=$2

    # --- Installation ---
    print_message "info" "$MSG_INFO_INSTALLING_MAIL_SERVER"
    install_augeas_if_needed || return 1

    if [[ "$PKG_MANAGER" == "apt-get" ]]; then
        # Pre-seed Postfix to avoid interactive prompts
        debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
        debconf-set-selections <<< "postfix postfix/mailname string $mail_domain"
        $PKG_MANAGER install -y postfix dovecot-core dovecot-imapd
    else
        # RHEL/CentOS/Fedora
        $PKG_MANAGER install -y postfix dovecot
    fi
    print_message "success" "$MSG_SUCCESS_MAIL_SERVER_INSTALLED"

    # --- Postfix Configuration ---
    print_message "info" "$MSG_INFO_CONFIGURING_POSTFIX_MAIN"
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
        local msg; msg=$(printf "$MSG_INFO_FOUND_CERT" "$mail_hostname")
        print_message "info" "$msg"
        postconf -e "smtpd_tls_cert_file=/etc/letsencrypt/live/$mail_hostname/fullchain.pem"
        postconf -e "smtpd_tls_key_file=/etc/letsencrypt/live/$mail_hostname/privkey.pem"
        postconf -e "smtpd_tls_security_level = may"
        postconf -e "smtp_tls_security_level = may"
    else
        local msg2; msg2=$(printf "$MSG_WARN_NO_CERT_FOUND" "$mail_hostname")
        print_message "warn" "$msg2"
        local msg3; msg3=$(printf "$MSG_WARN_CREATE_WEBSITE_FOR_CERT" "$mail_hostname")
        print_message "warn" "$msg3"
    fi

    # Enable submission port (587) and its options in master.cf using postconf
    print_message "info" "$MSG_INFO_CONFIGURING_POSTFIX_MASTER"
    postconf -M "submission/inet=submission inet n - n - - smtpd"
    postconf -P "submission/inet/syslog_name=postfix/submission"
    postconf -P "submission/inet/smtpd_tls_security_level=encrypt"
    postconf -P "submission/inet/smtpd_sasl_auth_enable=yes"
    # The 'smtpd_recipient_restrictions' is inherited from main.cf, but can be set explicitly if needed
    # postconf -P "submission/inet/smtpd_recipient_restrictions=permit_sasl_authenticated,reject"

    print_message "success" "$MSG_SUCCESS_POSTFIX_CONFIGURED"

    # --- Dovecot Configuration ---
    print_message "info" "$MSG_INFO_CONFIGURING_DOVECOT"
    augtool --autosave <<EOF
set /files/etc/dovecot/conf.d/10-mail.conf/mail_location "maildir:~/Maildir"
set /files/etc/dovecot/conf.d/10-auth.conf/auth_mechanisms "plain login"

# Set up authentication socket for Postfix
set /files/etc/dovecot/conf.d/10-master.conf/service[last()+1] "unix_listener"
set /files/etc/dovecot/conf.d/10-master.conf/service[last()]/name "/var/spool/postfix/private/auth"
set /files/etc/dovecot/conf.d/10-master.conf/service[last()]/mode "0660"
set /files/etc/dovecot/conf.d/10-master.conf/service[last()]/user "postfix"
set /files/etc/dovecot/conf.d/10-master.conf/service[last()]/group "postfix"

# Configure SSL
set /files/etc/dovecot/conf.d/10-ssl.conf/ssl "required"
EOF

    if [ -f "/etc/letsencrypt/live/$mail_hostname/fullchain.pem" ]; then
        augtool --autosave <<EOF
set /files/etc/dovecot/conf.d/10-ssl.conf/ssl_cert "</etc/letsencrypt/live/$mail_hostname/fullchain.pem"
set /files/etc/dovecot/conf.d/10-ssl.conf/ssl_key "</etc/letsencrypt/live/$mail_hostname/privkey.pem"
EOF
    else
        local msg4; msg4=$(printf "$MSG_WARN_DOVECOT_SELF_SIGNED" "$mail_hostname")
        print_message "warn" "$msg4"
    fi

    print_message "success" "$MSG_SUCCESS_DOVECOT_CONFIGURED"

    # --- Firewall & Services ---
    print_message "info" "$MSG_INFO_OPENING_MAIL_PORTS"
    if command -v ufw &> /dev/null; then
        ufw allow 25/tcp  # SMTP
        ufw allow 587/tcp # Submission
        ufw allow 993/tcp # IMAPS
        print_message "success" "$MSG_SUCCESS_MAIL_PORTS_OPENED"
    fi

    print_message "info" "$MSG_INFO_RESTARTING_MAIL_SERVICES"
    systemctl restart postfix
    systemctl restart dovecot

    print_message "success" "$MSG_SUCCESS_MAIL_SERVER_COMPLETE"
    print_message "info" "$MSG_INFO_ADD_MAIL_USERS_HOW_TO"
}

# Creates a new user restricted to SFTP access in a specific directory.
create_sftp_user() {
    print_message "info" "$MENU_CREATE_SFTP_USER"
    local sftp_user
    read_with_validation "$PROMPT_ENTER_SFTP_USER" sftp_user "username"

    local prompt_pw; prompt_pw=$(printf "$PROMPT_ENTER_SFTP_PASSWORD" "$sftp_user")
    local sftp_password
    read -s -p "$prompt_pw " sftp_password
    echo
    if [ -z "$sftp_password" ]; then
        print_message "error" "$MSG_ERROR_PASSWORD_EMPTY"
        return
    fi

    local sftp_dir
    read_with_validation "$PROMPT_ENTER_SFTP_DIR" sftp_dir "path"
    if [ ! -d "$sftp_dir" ]; then
        local msg; msg=$(printf "$MSG_ERROR_DIR_NOT_EXIST" "$sftp_dir")
        print_message "error" "$msg"
        return
    fi

    create_sftp_user_logic "$sftp_user" "$sftp_password" "$sftp_dir"
}

# Core logic for creating an SFTP user.
create_sftp_user_logic() {
    local sftp_user=$1
    local sftp_password=$2
    local sftp_dir=$3
    local sshd_config_path="/etc/ssh/sshd_config"

    # --- Chroot Directory Ownership Check ---
    local owner=$(stat -c '%U' "$sftp_dir")
    if [ "$owner" != "root" ]; then
        local msg; msg=$(printf "$MSG_ERROR_SFTP_JAIL_OWNER" "$sftp_dir")
        print_message "error" "$msg"
        print_message "warn" "$MSG_WARN_SFTP_JAIL_PRACTICE"
        return 1
    fi

    local msg2; msg2=$(printf "$MSG_INFO_CREATING_SFTP_USER" "$sftp_user")
    print_message "info" "$msg2"
    install_augeas_if_needed || return 1

    # Create user with no shell access and add to www-data group
    local msg3; msg3=$(printf "$MSG_INFO_USER_EXISTS" "$sftp_user")
    # Generate an encrypted password to use with useradd
    local encrypted_password
    encrypted_password=$(openssl passwd -1 "$sftp_password")
    useradd --home "$sftp_dir" --shell "/usr/sbin/nologin" --gid "www-data" -p "$encrypted_password" "$sftp_user" &>/dev/null || print_message "info" "$msg3"
    local msg4; msg4=$(printf "$MSG_SUCCESS_USER_CREATED" "$sftp_user")
    print_message "success" "$msg4"

    # Configure sshd_config using augtool
    print_message "info" "$MSG_INFO_CONFIGURING_SSHD"

    # Idempotency Check: only add sshd config if it doesn't exist
    if augtool match "/files${sshd_config_path}/Match[Condition/User='${sftp_user}']" | grep -q 'Match'; then
        local msg_exists; msg_exists=$(printf "$MSG_WARN_SFTP_CONF_EXISTS" "$sftp_user")
        print_message "warn" "$msg_exists"
    else
        # Using a more robust augtool command structure
        local aug_commands
        aug_commands=$(mktemp)
        cat > "$aug_commands" <<EOF
# Ensure the SFTP subsystem is set to the secure internal-sftp
set /files${sshd_config_path}/Subsystem/sftp internal-sftp

# Define the path for the new Match block to make it cleaner
defvar match_block /files${sshd_config_path}/Match[last()+1]
set \$match_block/Condition/User "$sftp_user"
set \$match_block/Settings/ForceCommand "internal-sftp"
set \$match_block/Settings/PasswordAuthentication "yes"
set \$match_block/Settings/ChrootDirectory "$sftp_dir"
set \$match_block/Settings/AllowTcpForwarding "no"
set \$match_block/Settings/X11Forwarding "no"
EOF

        if augtool --autosave --file "$aug_commands"; then
            local msg5; msg5=$(printf "$MSG_SUCCESS_SFTP_JAIL_CONFIGURED" "$sftp_user" "$sshd_config_path")
            print_message "success" "$msg5"
        else
            print_message "error" "$MSG_ERROR_SSHD_CONFIG_FAILED"
            # Optional: show augtool errors if any were logged
            [ -f /tmp/augtool.err ] && cat /tmp/augtool.err
            rm -f "$aug_commands"
            return 1
        fi
        rm -f "$aug_commands"
    fi

    # The chroot directory itself must be root-owned with 755 permissions.
    chmod 755 "$sftp_dir"

    # Create a writable subdirectory for the user
    local writable_dir="${sftp_dir}/public_html"
    local msg6; msg6=$(printf "$MSG_INFO_CREATING_WRITABLE_DIR" "$writable_dir")
    print_message "info" "$msg6"
    mkdir -p "$writable_dir"
    chown "${sftp_user}:www-data" "$writable_dir"
    chmod 755 "$writable_dir"
    print_message "success" "$MSG_SUCCESS_WRITABLE_DIR_CREATED"

    # Restart SSH service
    print_message "info" "$MSG_INFO_RESTARTING_SSH"
    systemctl restart sshd
    print_message "success" "$MSG_SUCCESS_SSH_RESTARTED"
    local msg7; msg7=$(printf "$MSG_SUCCESS_SFTP_USER_READY" "$sftp_user" "$sftp_dir" "$writable_dir")
    print_message "success" "$msg7"
}

# Installs and configures Fail2ban for enhanced security
setup_fail2ban() {
    print_message "info" "$MENU_FAIL2BAN"
    read -p "$PROMPT_INSTALL_FAIL2BAN " confirmation
    if [[ ! "$confirmation" =~ ^[yYoO](es|ui)?$ ]]; then
        print_message "info" "$MSG_INFO_OPERATION_CANCELLED"
        return
    fi

    print_message "info" "$MSG_INFO_INSTALLING_FAIL2BAN"
    $PKG_MANAGER install -y fail2ban
    if [ $? -ne 0 ]; then
        print_message "error" "$MSG_ERROR_FAIL2BAN_INSTALL_FAILED"
        return 1
    fi
    print_message "success" "$MSG_SUCCESS_FAIL2BAN_INSTALLED"

    print_message "info" "$MSG_INFO_CONFIGURING_FAIL2BAN"
    # Create a local jail file to override defaults without editing the main config.
    tee /etc/fail2ban/jail.local <<EOF
[DEFAULT]
# Ban hosts for 1 hour
bantime = 1h
# An host is banned if it has generated "maxretry" during the last "findtime"
findtime = 10m
maxretry = 5

# Enable jails for common services
[sshd]
enabled = true

[dovecot]
enabled = true

[postfix-sasl]
enabled = true
EOF

    print_message "info" "$MSG_INFO_STARTING_FAIL2BAN"
    systemctl enable --now fail2ban
    systemctl restart fail2ban

    print_message "success" "$MSG_SUCCESS_FAIL2BAN_ACTIVE"
}

# Backs up a website's files and database
backup_website() {
    print_message "info" "$MENU_BACKUP_WEBSITE"
    local domain_name
    read_with_validation "$PROMPT_ENTER_DOMAIN_TO_BACKUP" domain_name "domain"

    local web_root="/var/www/$domain_name"
    if [ ! -d "$web_root" ]; then
        local msg; msg=$(printf "$MSG_ERROR_WEB_ROOT_NOT_EXIST" "$web_root")
        print_message "error" "$msg"
        return
    fi

    local db_name
    read_with_validation "$PROMPT_ENTER_DB_TO_BACKUP" db_name "db_name"

    backup_website_logic "$domain_name" "$db_name"
}

# Core logic for backing up a website
backup_website_logic() {
    local domain_name=$1
    local db_name=$2
    local web_root="/var/www/$domain_name"

    local backup_dir="/root/backups"
    mkdir -p "$backup_dir"
    local timestamp=$(date "+%Y-%m-%d-%H%M%S")
    local backup_file="$backup_dir/backup-${domain_name}-${timestamp}.tar.gz"
    local temp_dir
    temp_dir=$(mktemp -d)

    local msg2; msg2=$(printf "$MSG_INFO_STARTING_BACKUP" "$domain_name")
    print_message "info" "$msg2"

    # Backup database
    local msg3; msg3=$(printf "$MSG_INFO_DUMPING_DB" "$db_name")
    print_message "info" "$msg3"
    if [ ! -f "/root/.mysql_root_password" ]; then
        print_message "error" "$MSG_ERROR_DB_PASS_NOT_FOUND"
        rm -rf "$temp_dir"
        return 1
    fi
    local db_root_pw
    db_root_pw=$(cat /root/.mysql_root_password)
    if ! mysqldump -u root -p"${db_root_pw}" "${db_name}" > "${temp_dir}/${db_name}.sql"; then
        local msg4; msg4=$(printf "$MSG_ERROR_DB_DUMP_FAILED" "$db_name")
        print_message "error" "$msg4"
        rm -rf "$temp_dir"
        return 1
    fi
    print_message "success" "$MSG_SUCCESS_DB_DUMPED"

    # Create archive of web files
    local msg5; msg5=$(printf "$MSG_INFO_ARCHIVING_FILES" "$web_root")
    print_message "info" "$msg5"
    mkdir -p "${temp_dir}/web_root_content"
    cp -a "${web_root}/." "${temp_dir}/web_root_content/"

    # Create final combined archive
    local msg6; msg6=$(printf "$MSG_INFO_CREATING_BACKUP_FILE" "$backup_file")
    print_message "info" "$msg6"
    tar -czf "$backup_file" -C "$temp_dir" .

    # Cleanup
    rm -rf "$temp_dir"

    local msg7; msg7=$(printf "$MSG_SUCCESS_BACKUP_COMPLETE" "$backup_file")
    print_message "success" "$msg7"
}

# Restores a website from a backup file
restore_website() {
    print_message "info" "$MENU_RESTORE_WEBSITE"
    print_message "warn" "$MSG_WARN_RESTORE_DESTRUCTIVE"

    local backup_file
    read_with_validation "$PROMPT_ENTER_BACKUP_PATH" backup_file "path"
    if [ ! -f "$backup_file" ]; then
        local msg; msg=$(printf "$MSG_ERROR_BACKUP_FILE_NOT_FOUND" "$backup_file")
        print_message "error" "$msg"
        return
    fi

    local domain_name
    read_with_validation "$PROMPT_ENTER_DOMAIN_TO_RESTORE" domain_name "domain"

    local web_root="/var/www/$domain_name"
    local db_name
    read_with_validation "$PROMPT_ENTER_DB_TO_RESTORE" db_name "db_name"

    local msg2; msg2=$(printf "$MSG_WARN_CONFIRM_RESTORE" "$web_root" "$db_name")
    print_message "warn" "$msg2"
    local msg3; msg3=$(printf "$PROMPT_CONFIRM_RESTORE" "$domain_name")
    read -p "$msg3 " confirmation
    if [ "$confirmation" != "$domain_name" ]; then
        print_message "error" "$MSG_ERROR_CONFIRMATION_FAILED"
        return
    fi

    restore_website_logic "$backup_file" "$domain_name" "$db_name"
}

# Core logic for restoring a website
restore_website_logic() {
    local backup_file=$1
    local domain_name=$2
    local db_name=$3
    local web_root="/var/www/$domain_name"

    local temp_dir
    temp_dir=$(mktemp -d)
    print_message "info" "$MSG_INFO_EXTRACTING_BACKUP"
    tar -xzf "$backup_file" -C "$temp_dir"

    # Restore Files
    local backup_content_dir="${temp_dir}/web_root_content"
    if [ -d "$backup_content_dir" ]; then
        local msg4; msg4=$(printf "$MSG_INFO_RESTORING_FILES" "$web_root")
        print_message "info" "$msg4"
        # Safety: move existing directory
        if [ -d "$web_root" ]; then
            local bak_dir="${web_root}.bak-$(date "+%Y%m%d%H%M%S")"
            mv "$web_root" "$bak_dir"
            local msg5; msg5=$(printf "$MSG_INFO_MOVED_EXISTING_ROOT" "$web_root")
            print_message "info" "$msg5"
        fi

        # Create the new web root and copy contents from the backup.
        mkdir -p "$web_root"
        cp -a "${backup_content_dir}/." "$web_root/"
        chown -R www-data:www-data "$web_root"
        print_message "success" "$MSG_SUCCESS_FILES_RESTORED"
    else
        print_message "warn" "$MSG_WARN_NO_WEB_ROOT_IN_BACKUP"
        print_message "info" "$MSG_INFO_RESTORE_VERSION_NOTE"
    fi

    # Restore Database
    local sql_file
    sql_file=$(find "$temp_dir" -name "*.sql" -type f | head -n 1)
    if [ -n "$sql_file" ]; then
        local msg6; msg6=$(printf "$MSG_INFO_RESTORING_DB" "$db_name" "$(basename "$sql_file")")
        print_message "info" "$msg6"
        if [ ! -f "/root/.mysql_root_password" ]; then
            print_message "error" "$MSG_ERROR_DB_RESTORE_PASS_NOT_FOUND"
            rm -rf "$temp_dir"
            return 1
        fi
        local db_root_pw
        db_root_pw=$(cat /root/.mysql_root_password)
        # Ensure database exists
        mysql -u root -p"${db_root_pw}" -e "CREATE DATABASE IF NOT EXISTS \`${db_name}\`;"
        if ! mysql -u root -p"${db_root_pw}" "${db_name}" < "$sql_file"; then
            print_message "error" "$MSG_ERROR_DB_RESTORE_FAILED"
            rm -rf "$temp_dir"
            return 1
        fi
        print_message "success" "$MSG_SUCCESS_DB_RESTORED"
    else
        print_message "warn" "$MSG_WARN_NO_SQL_IN_BACKUP"
    fi

    # Cleanup
    rm -rf "$temp_dir"
    local msg7; msg7=$(printf "$MSG_SUCCESS_RESTORE_COMPLETE" "$domain_name")
    print_message "success" "$msg7"
}

# Displays the main menu of the script.
show_main_menu() {
    clear
    echo
    print_message "info" "$MENU_MAIN_HEADER"
    print_message "info" "      $MENU_MAIN_TITLE"
    print_message "info" "$MENU_MAIN_HEADER"
    echo
    echo " $MENU_SECTION_INITIAL"
    echo "  $MENU_OPTION_1"
    echo "  $MENU_OPTION_2"
    echo "  $MENU_OPTION_3"
    echo "  $MENU_OPTION_4"
    echo "  $MENU_OPTION_5"
    echo
    echo " $MENU_SECTION_UTILS"
    echo "  $MENU_OPTION_6"
    echo "  $MENU_OPTION_7"
    echo
    echo " $MENU_SECTION_MGMT"
    echo "  $MENU_OPTION_8"
    echo "  $MENU_OPTION_9"
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
        print_message "warn" "$MSG_NO_WEBSITES_FOUND"
        return 1
    fi
    print_message "info" "$MENU_LIST_WEBSITES_HEADER"
    for site in $all_sites; do
        local symlink_path="$sites_enabled/$site"
        if [[ "$status" == "enabled" && -L "$symlink_path" ]]; then
            echo "  - $site $MENU_LIST_WEBSITES_ENABLED"
        elif [[ "$status" == "disabled" && ! -L "$symlink_path" ]]; then
            echo "  - $site $MENU_LIST_WEBSITES_DISABLED"
        elif [[ "$status" == "all" ]]; then
            if [ -L "$symlink_path" ]; then
                echo "  - $site $MENU_LIST_WEBSITES_ENABLED"
            else
                echo "  - $site $MENU_LIST_WEBSITES_DISABLED"
            fi
        fi
    done
    echo "------------------------"
    return 0
}

# Deletes a website completely
delete_website() {
    print_message "info" "$MENU_WEBSITE_MGMT"
    list_nginx_sites "all" || return

    read -p "$PROMPT_WEBSITE_DELETE " site_conf
    local domain=$(basename "$site_conf" .conf)

    if [ -z "$site_conf" ] || [ ! -f "/etc/nginx/sites-available/$site_conf" ]; then
        print_message "error" "$MSG_INVALID_SELECTION"
        return
    fi

    local msg; msg=$(printf "$MSG_WARN_PERMANENT_DELETE" "$domain")
    print_message "warn" "$msg"
    local msg2; msg2=$(printf "$PROMPT_CONFIRM_DELETE_WEBSITE" "$domain")
    read -p "$msg2 " confirmation
    if [ "$confirmation" != "$domain" ]; then
        print_message "error" "$MSG_ERROR_CONFIRMATION_FAILED"
        return
    fi

    local db_to_delete=""
    read -p "$PROMPT_DELETE_DB " del_db
    if [[ "$del_db" =~ ^[yYoO](es|ui)?$ ]]; then
        read_with_validation "$PROMPT_ENTER_DB_TO_DELETE" db_to_delete "db_name"
    fi

    delete_website_logic "$site_conf" "$db_to_delete"
}

# Core logic for deleting a website
delete_website_logic() {
    local site_conf=$1
    local db_to_delete=$2
    local domain=$(basename "$site_conf" .conf)

    # Delete Nginx files
    rm -f "/etc/nginx/sites-available/$site_conf"
    rm -f "/etc/nginx/sites-enabled/$site_conf"
    print_message "info" "$MSG_NGINX_CONF_REMOVED"

    # Delete web root
    if [ -d "/var/www/$domain" ]; then
        rm -rf "/var/www/$domain"
        local msg3; msg3=$(printf "$MSG_WEB_ROOT_REMOVED" "$domain")
        print_message "info" "$msg3"
    fi

    # Delete SSL certificate
    if command -v certbot &> /dev/null; then
        local msg4; msg4=$(printf "$MSG_SSL_CERT_DELETED" "$domain")
        certbot delete --non-interactive --cert-name "$domain" &>/dev/null || print_message "warn" "$msg4"
        print_message "info" "$msg4"
    fi

    # Delete database if a name is provided
    if [ -n "$db_to_delete" ]; then
        if [ ! -f "/root/.mysql_root_password" ]; then
            print_message "error" "$MSG_ERROR_DB_PASS_NOT_FOUND"
        else
            local db_root_pw=$(cat /root/.mysql_root_password)
            mysql -u root -p"${db_root_pw}" -e "DROP DATABASE IF EXISTS \`${db_to_delete}\`;"
            local msg5; msg5=$(printf "$MSG_DB_DELETED" "$db_to_delete")
            print_message "info" "$msg5"
        fi
    fi

    systemctl reload nginx
    local msg6; msg6=$(printf "$MSG_WEBSITE_DELETED" "$domain")
    print_message "success" "$msg6"
}

# Disables an active Nginx site
disable_website() {
    print_message "info" "$MENU_WEBSITE_MGMT"
    list_nginx_sites "enabled" || return

    read -p "$PROMPT_WEBSITE_DISABLE " site_conf
    if [ -z "$site_conf" ] || [ ! -L "/etc/nginx/sites-enabled/$site_conf" ]; then
        print_message "error" "$MSG_INVALID_SELECTION"
        return
    fi

    rm -f "/etc/nginx/sites-enabled/$site_conf"
    systemctl reload nginx
    local msg; msg=$(printf "$MSG_SITE_DISABLED" "$site_conf")
    print_message "success" "$msg"
}

# Enables an inactive Nginx site
enable_website() {
    print_message "info" "$MENU_WEBSITE_MGMT"
    list_nginx_sites "disabled" || return

    read -p "$PROMPT_WEBSITE_ENABLE " site_conf
    if [ -z "$site_conf" ] || [ ! -f "/etc/nginx/sites-available/$site_conf" ] || [ -L "/etc/nginx/sites-enabled/$site_conf" ]; then
        print_message "error" "$MSG_INVALID_SELECTION"
        return
    fi

    ln -s "/etc/nginx/sites-available/$site_conf" "/etc/nginx/sites-enabled/"
    systemctl reload nginx
    local msg; msg=$(printf "$MSG_SITE_ENABLED" "$site_conf")
    print_message "success" "$msg"
}

# Main function for website management sub-menu
manage_websites() {
    while true; do
        clear
        print_message "info" "$MENU_WEBSITE_MGMT"
        list_nginx_sites "all" || { read -n 1 -s -r -p "$MSG_PRESS_ANY_KEY"; break; }
        echo
        echo "  $MENU_WEBSITE_OPTION_1"
        echo "  $MENU_WEBSITE_OPTION_2"
        echo "  $MENU_WEBSITE_OPTION_3"
        echo "  $MENU_WEBSITE_OPTION_4"
        echo
        read -rp "$PROMPT_CHOOSE_OPTION [1-4]: " choice
        case $choice in
            1) delete_website ;;
            2) disable_website ;;
            3) enable_website ;;
            4) break ;;
            *) print_message "warn" "$MSG_ERROR_INVALID_OPTION" ;;
        esac
        read -n 1 -s -r -p "$MSG_PRESS_ANY_KEY"
    done
}

# --- SFTP User Management Functions ---

# Lists SFTP users by parsing sshd_config
list_sftp_users() {
    print_message "info" "$MSG_JAILED_SFTP_USERS"
    # This grep command uses a Perl-compatible regex to find usernames after "Match User"
    local users=$(grep -oP '(?<=^Match User\s)\S+' /etc/ssh/sshd_config || true)
    if [ -z "$users" ]; then
        print_message "warn" "$MSG_NO_SFTP_USERS"
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
    print_message "info" "$MENU_SFTP_MGMT"
    list_sftp_users || return

    local sftp_user
    read_with_validation "$PROMPT_USERNAME_TO_MODIFY" sftp_user "username"

    # Verify user exists in the SFTP config
    if ! grep -q "^Match User $sftp_user" /etc/ssh/sshd_config; then
        local msg; msg=$(printf "$MSG_ERROR_USER_NOT_SFTP" "$sftp_user")
        print_message "error" "$msg"
        return
    fi

    local msg2; msg2=$(printf "$PROMPT_NEW_PASSWORD" "$sftp_user")
    read -s -p "$msg2 " sftp_password
    echo
    if [ -z "$sftp_password" ]; then
        print_message "error" "$MSG_ERROR_PASSWORD_EMPTY"
        return
    fi

    echo "$sftp_user:$sftp_password" | chpasswd
    local msg3; msg3=$(printf "$MSG_PASSWORD_CHANGED" "$sftp_user")
    print_message "success" "$msg3"
}

# Deletes an SFTP user and their configuration
delete_sftp_user() {
    print_message "info" "$MENU_SFTP_MGMT"
    list_sftp_users || return

    local sftp_user
    read_with_validation "$PROMPT_USERNAME_TO_DELETE" sftp_user "username"

    # Verify user exists in the SFTP config using a more robust check
    local sftp_user_exists=$(augtool get "/files/etc/ssh/sshd_config/Match[Condition/User='$sftp_user']/Condition/User")
    if [ -z "$sftp_user_exists" ]; then
        local msg; msg=$(printf "$MSG_ERROR_USER_NOT_SFTP" "$sftp_user")
        print_message "error" "$msg"
        return
    fi

    local msg2; msg2=$(printf "$MSG_WARN_PERMANENT_DELETE_USER" "$sftp_user")
    print_message "warn" "$msg2"
    local msg3; msg3=$(printf "$PROMPT_CONFIRM_DELETE_USER" "$sftp_user")
    read -p "$msg3 " confirmation
    if [ "$confirmation" != "$sftp_user" ]; then
        print_message "error" "$MSG_ERROR_CONFIRMATION_FAILED"
        return
    fi

    delete_sftp_user_logic "$sftp_user"
}

# Core logic for deleting an SFTP user
delete_sftp_user_logic() {
    local sftp_user=$1

    # Delete system user
    if id "$sftp_user" &>/dev/null; then
        userdel "$sftp_user"
        local msg4; msg4=$(printf "$MSG_USER_DELETED" "$sftp_user")
        print_message "info" "$msg4"
    else
        local msg5; msg5=$(printf "$MSG_USER_NOT_FOUND_SKIPPING" "$sftp_user")
        print_message "warn" "$msg5"
    fi

    # Remove sshd_config block using augtool
    local msg6; msg6=$(printf "$MSG_INFO_REMOVING_SFTP_CONF" "$sftp_user")
    print_message "info" "$msg6"
    augtool --autosave "rm /files/etc/ssh/sshd_config/Match[Condition/User='$sftp_user']"
    if [ $? -eq 0 ]; then
        local msg7; msg7=$(printf "$MSG_SUCCESS_SFTP_CONF_REMOVED" "$sftp_user")
        print_message "success" "$msg7"
    else
        print_message "error" "$MSG_ERROR_REMOVING_SFTP_CONF"
        return 1
    fi

    # Restart SSH
    systemctl restart sshd
    print_message "success" "$MSG_SUCCESS_SSH_RESTARTED"
    local msg8; msg8=$(printf "$MSG_SFTP_USER_DELETED" "$sftp_user")
    print_message "success" "$msg8"
}

# Main function for SFTP user management
manage_sftp_users() {
    while true; do
        clear
        print_message "info" "$MENU_SFTP_MGMT"
        list_sftp_users || { read -n 1 -s -r -p "$MSG_PRESS_ANY_KEY"; break; }
        echo
        echo "  $MENU_SFTP_OPTION_1"
        echo "  $MENU_SFTP_OPTION_2"
        echo "  $MENU_SFTP_OPTION_3"
        echo
        read -rp "$PROMPT_CHOOSE_OPTION [1-3]: " choice
        case $choice in
            1) change_sftp_password ;;
            2) delete_sftp_user ;;
            3) break ;;
            *) print_message "warn" "$MSG_ERROR_INVALID_OPTION" ;;
        esac
        read -n 1 -s -r -p "$MSG_PRESS_ANY_KEY"
    done
}

# --- Mail User Management Functions ---

# Lists mail users (standard users with home directories)
list_mail_users() {
    print_message "info" "$MSG_EMAIL_ACCOUNTS"
    # This awk command lists users with UID >= 1000 and a home dir in /home
    local users=$(awk -F: '$3 >= 1000 && $6 ~ /^\/home/ { print $1 }' /etc/passwd || true)
    if [ -z "$users" ]; then
        print_message "warn" "$MSG_NO_MAIL_USERS"
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
    print_message "info" "$MENU_MAIL_MGMT"
    local user_name
    read_with_validation "$PROMPT_ADD_EMAIL_USER" user_name "username"

    local user_password
    read -s -p "$PROMPT_PASSWORD_FOR_ACCOUNT " user_password
    echo
    if [ -z "$user_password" ]; then
        print_message "error" "$MSG_ERROR_PASSWORD_EMPTY"
        return
    fi

    # Create user with a home directory and no shell access
    useradd -m -s /usr/sbin/nologin "$user_name"
    echo "$user_name:$user_password" | chpasswd

    local msg; msg=$(printf "$MSG_SUCCESS_EMAIL_CREATED" "$user_name")
    print_message "success" "$msg"
}

# Deletes an email account
delete_mail_user() {
    print_message "info" "$MENU_MAIL_MGMT"
    list_mail_users || return

    local user_name
    read_with_validation "$PROMPT_USERNAME_TO_DELETE_EMAIL" user_name "username"

    # Verify user exists
    if ! id "$user_name" &>/dev/null; then
        local msg; msg=$(printf "$MSG_ERROR_USER_NOT_EXIST" "$user_name")
        print_message "error" "$msg"
        return
    fi

    local msg2; msg2=$(printf "$MSG_WARN_PERMANENT_DELETE_EMAIL" "$user_name")
    print_message "warn" "$msg2"
    local msg3; msg3=$(printf "$PROMPT_CONFIRM_DELETE_EMAIL" "$user_name")
    read -p "$msg3 " confirmation
    if [ "$confirmation" != "$user_name" ]; then
        print_message "error" "$MSG_ERROR_CONFIRMATION_FAILED"
        return
    fi

    # Delete the user and their home directory (-r)
    userdel -r "$user_name"
    local msg4; msg4=$(printf "$MSG_EMAIL_DELETED" "$user_name")
    print_message "success" "$msg4"
}

# Main function for mail user management
manage_mail_users() {
    while true; do
        clear
        print_message "info" "$MENU_MAIL_MGMT"
        echo
        echo "  $MENU_MAIL_OPTION_1"
        echo "  $MENU_MAIL_OPTION_2"
        echo "  $MENU_MAIL_OPTION_3"
        echo "  $MENU_MAIL_OPTION_4"
        echo
        read -rp "$PROMPT_CHOOSE_OPTION [1-4]: " choice
        case $choice in
            1) add_mail_user ;;
            2) delete_mail_user ;;
            3) list_mail_users ;;
            4) break ;;
            *) print_message "warn" "$MSG_ERROR_INVALID_OPTION" ;;
        esac
        read -n 1 -s -r -p "$MSG_PRESS_ANY_KEY"
    done
}

# --- Management Menu ---

show_management_menu() {
    clear
    echo
    print_message "info" "$MENU_MAIN_HEADER"
    print_message "info" "        $MENU_MGMT_TITLE"
    print_message "info" "$MENU_MAIN_HEADER"
    echo
    echo "  $MENU_MGMT_OPTION_1"
    echo "  $MENU_MGMT_OPTION_2"
    echo "  $MENU_MGMT_OPTION_3"
    echo "  $MENU_MGMT_OPTION_4"
    echo
}

run_management_menu() {
    while true; do
        show_management_menu
        read -rp "$PROMPT_CHOOSE_OPTION [1-4]: " choice
        case $choice in
            1) manage_websites ;;
            2) manage_sftp_users ;;
            3) manage_mail_users ;;
            4)
                print_message "info" "$MSG_RETURN_TO_MAIN_MENU"
                break
                ;;
            *)
                print_message "warn" "$MSG_ERROR_INVALID_OPTION"
                ;;
        esac
        read -n 1 -s -r -p "$MSG_PRESS_ANY_KEY"
    done
}

# --- Main Execution Logic ---

# Asks the user to select a language and sources the corresponding file.
select_language() {
    read -p "Please choose a language: [1] English, [2] Français: " lang_choice
    case $lang_choice in
        2)
            if [ -f "lang/fr.sh" ]; then
                source "lang/fr.sh"
                SCRIPT_LANG="fr"
            else
                echo "[ERROR] French language file (lang/fr.sh) not found. Defaulting to English."
                source "lang/en.sh"
            fi
            ;;
        *)
            if [ -f "lang/en.sh" ]; then
                source "lang/en.sh"
            else
                echo "[ERROR] English language file (lang/en.sh) not found. Exiting."
                exit 1
            fi
            ;;
    esac
}

main() {
    # Ensure log file exists and has correct permissions
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"

    select_language

    initial_checks
    detect_os

    while true; do
        show_main_menu
        read -rp "$PROMPT_CHOOSE_OPTION [1-9]: " choice
        case $choice in
            1) run_initial_setup ;;
            2) add_new_website ;;
            3) setup_mail_server ;;
            4) create_sftp_user ;;
            5) setup_fail2ban ;;
            6) backup_website ;;
            7) restore_website ;;
            8) run_management_menu ;;
            9)
                print_message "info" "$MSG_EXITING"
                break
                ;;
            *)
                print_message "warn" "$MSG_ERROR_INVALID_OPTION"
                ;;
        esac
        # Pause for user to read message before showing menu again
        read -n 1 -s -r -p "$MSG_PRESS_ANY_KEY"
    done
}

# --- Script Entry Point ---
# This block runs only when the script is executed directly, not when sourced
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    # Redirect all output (stdout and stderr) to both console and log file
    exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)
    # Run the main function
    main
fi
