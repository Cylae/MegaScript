# 🚀 GCP Mail & WordPress Server Setup Guide 🚀

This guide provides all the necessary steps to deploy a full-featured mail server and a WordPress website on a single, cost-effective Google Cloud Platform (GCP) virtual machine.

## ✅ Prerequisites

Before you begin, make sure you have the following:

*   A Google Cloud Platform (GCP) account with billing enabled.
*   A registered domain name (e.g., `example.com`).
*   Access to your domain's DNS settings at your domain registrar.
*   (For Windows Users) [PuTTY](https://www.putty.org/) and PuTTYgen installed for SSH access.

## ✨ What You'll Deploy

*   **📬 A Complete Mail Server:** Using the robust and easy-to-manage [Mail-in-a-Box](https://mailinabox.email/) software, with its admin panel secured by an SSL certificate.
*   **📝 A WordPress Website:** The world's most popular content management system, also secured by an SSL certificate.
*   **🔗 A URL Shortener:** Using the popular and lightweight [Yourls](https://yourls.org/) software.
*   **🔒 Automatic Security:** The server will be configured with automatic security updates.
*   **💰 Cost-Effective:** All running on a single `e2-micro` VM instance that is eligible for the GCP Free Tier.

## 🗺️ Table of Contents

*   [Part 1: GCP Prerequisites](#part-1-gcp-prerequisites)
*   [Part 2: DNS Pre-configuration](#part-2-dns-pre-configuration)
*   [Part 3: Connecting via SSH (PuTTY for Windows)](#part-3-connecting-via-ssh-putty-for-windows)
*   [Part 4: Running the Setup Script](#part-4-running-the-setup-script)
*   [Part 5: Post-Installation Steps](#part-5-post-installation-steps)
*   [Part 6: Server Management](#part-6-server-management)

The process is divided into two main phases:
1.  **Manual GCP & DNS Setup:** You will first configure the necessary infrastructure on the GCP console and at your domain registrar.
2.  **Automated Server Setup:** You will then run a shell script on the VM that automates the installation and configuration of all required software.

---

## ☁️ Part 1: GCP Prerequisites

Log in to your [GCP Console](https://console.cloud.google.com/) and perform the following actions.

<details>
<summary><strong>1.1. Create the VM Instance</strong></summary>

We will create a VM instance that is eligible for the GCP "Free Tier".

1.  Navigate to **Compute Engine > VM instances**.
2.  Click **CREATE INSTANCE**.
3.  Use the following configuration:
    *   **Name:** A descriptive name, e.g., `mail-wordpress-server`.
    *   **Region:** A US region eligible for the free tier, e.g., `us-west1` (Oregon).
    *   **Series:** `E2`.
    *   **Machine type:** `e2-micro`.
    *   **Boot disk:**
        *   **OS:** `Debian` (latest stable version, e.g., Debian 12).
        *   **Size:** `30` GB.
    *   **Firewall:** Check both `Allow HTTP traffic` and `Allow HTTPS traffic`.
4.  Click **Create**.

</details>

<details>
<summary><strong>1.2. Reserve a Static IP Address</strong></summary>

A mail server requires a fixed IP address.

1.  Navigate to **VPC network > IP addresses**.
2.  Find the IP address of your newly created VM (listed as "Type: Ephemeral").
3.  Click **RESERVE**.
4.  Give the static IP a name (e.g., `mail-server-ip`) and confirm. The type will change to "Static". **Take note of this IP address.**

</details>

<details>
<summary><strong>1.3. Configure Firewall Rules</strong></summary>

Open the necessary ports for mail services.

1.  Navigate to **VPC network > Firewall**.
2.  Click **CREATE FIREWALL RULE** for each of the rules below.
3.  For each rule, use these settings:
    *   **Direction:** `Ingress`.
    *   **Targets:** `Specified target tags`.
    *   **Target tags:** `http-server` and `https-server` (these tags are automatically applied to your VM).
    *   **Source IPv4 ranges:** `0.0.0.0/0`.
    *   **Protocols and ports:** `Specified protocols and ports`.

    **Rules to Create:**
    *   **Name:** `allow-smtp` -> **tcp:** `25`, `587`
    *   **Name:** `allow-smtps` -> **tcp:** `465`
    *   **Name:** `allow-imaps` -> **tcp:** `993`

</details>

---

## 🌐 Part 2: DNS Pre-configuration

> **Note:** Before running the script, you must configure these essential DNS records at your domain registrar. Replace `YOUR_STATIC_IP` with the IP address you reserved.

<details>
<summary><strong>Click to view required DNS records</strong></summary>

*   **A Record for the mail server hostname:**
    *   **Type:** `A`
    *   **Name/Host:** `box`
    *   **Value:** `YOUR_STATIC_IP`

*   **A Record for the main domain:**
    *   **Type:** `A`
    *   **Name/Host:** `@` (or your root domain)
    *   **Value:** `YOUR_STATIC_IP`

*   **MX Record for mail delivery:**
    *   **Type:** `MX`
    *   **Name/Host:** `@`
    *   **Value:** `box.yourdomain.com` (e.g., `box.example.com`)
    *   **Priority:** `10`

</details>

The setup script will later instruct you on creating additional records (SPF, DKIM, etc.) from the Mail-in-a-Box admin panel.

---

## 🔑 Part 3: Connecting via SSH (PuTTY for Windows)

<details>
<summary><strong>3.1. Generate SSH Keys with PuTTYgen</strong></summary>

1.  Open `puttygen.exe`.
2.  Click **Generate** and move your mouse to generate randomness.
3.  In the `Key comment` field, enter a simple username (e.g., `debian`).
4.  Save both keys:
    *   **Save public key:** name it `gcp_key.pub`.
    *   **Save private key:** name it `gcp_key.ppk`.
5.  Copy the entire public key text from the top text box.

</details>

<details>
<summary><strong>3.2. Add Your Public Key to the VM</strong></summary>

1.  In the GCP console, go to your VM's details page and click **EDIT**.
2.  Scroll down to the "SSH Keys" section and click **ADD ITEM**.
3.  Paste your public key. The username (`debian`) should appear on the right.
4.  **Save** the changes to the VM.

</details>

<details>
<summary><strong>3.3. Configure PuTTY to Connect</strong></summary>

1.  Open `putty.exe`.
2.  **Session:**
    *   `Host Name (or IP address)`: Enter your server's static IP address.
    *   `Saved Sessions`: Give the session a name (e.g., "GCP Server") and click **Save**.
3.  **Connection > SSH > Auth > Credentials:**
    *   Click **Browse...** and select your private key file (`gcp_key.ppk`).
4.  Return to **Session**, and click **Save** again.
5.  Click **Open**. Accept the security alert on the first connection.
6.  When prompted `login as:`, enter the username you set (`debian`).

</details>

---

## 🚀 Part 4: Running the Setup Script

Once connected to your server via SSH, follow these steps:

1.  **Download the Scripts:**
    Download `setup-server.sh` and the other management scripts from the repository.
    ```bash
    # Example using wget - replace with the actual URL
    wget https://raw.githubusercontent.com/path/to/repo/setup-server.sh
    wget https://raw.githubusercontent.com/path/to/repo/config.ini.example
    # ... download other scripts as needed ...
    ```

2.  **Configure Your Setup:**
    The server setup is now controlled by a configuration file for safety and ease of use.
    *   First, copy the example config:
        ```bash
        cp config.ini.example config.ini
        ```
    *   Next, edit the `config.ini` file with your details:
        ```bash
        nano config.ini
        ```
    *   Fill in your `DOMAIN`, `EMAIL`, `TIMEZONE`, and other desired settings.

3.  **Make the Script Executable:**
    ```bash
    chmod +x setup-server.sh
    ```

4.  **Run the Setup:**
    Run the script with `sudo`. It will now present you with an interactive menu.
    ```bash
    sudo ./setup-server.sh
    ```
    From the menu, you can choose to run the full initial setup, install additional components like the URL shortener, or access the other management scripts.

---

## 🎉 Part 5: Post-Installation Steps

The script automates most of the setup. At the end of the process, you will be shown your WordPress credentials.

1.  **Final DNS Configuration:** After the script finishes, log in to your Mail-in-a-Box admin panel at `https://box.yourdomain.com/admin`. Go to the "System > External DNS" page. You will find a list of DNS records you need to add at your domain registrar. This is crucial for your mail server to work correctly.
2.  **WordPress Finalization:** Navigate to `https://www.yourdomain.com` in your browser. Your site is already installed, so you can log in directly at `https://www.yourdomain.com/wp-admin` using the credentials provided at the end of the setup script.
3.  **Security Scan Review:** The script automatically runs a security scan with `Lynis` at the end of the installation. You can review the detailed report at `/var/log/lynis-report.dat` to see potential security hardening suggestions.

---

## 🛠️ Part 6: Server Management

This project includes a suite of scripts to help you manage and maintain your server after the initial setup.

### 🛡️ 6.1. Automatic Security Updates

The `setup-server.sh` script automatically installs and configures the `unattended-upgrades` package. This means your server will check for and install important security updates in the background without any manual intervention.

### ⚙️ 6.2. Service Management (`manage-services.sh`)

<details>
<summary><strong>Click to view details for `manage-services.sh`</strong></summary>

A simple management script, `manage-services.sh`, is provided to easily control your server's main functions. You must download this script separately or create it from the repository.

**Usage:**

Make the script executable first:
`chmod +x manage-services.sh`

Then, run it with `sudo`:

*   **To stop the web services (WordPress):**
    `sudo ./manage-services.sh stop web`
*   **To start the mail services:**
    `sudo ./manage-services.sh start mail`
*   **To check the status of all services:**
    `sudo ./manage-services.sh status all`
*   **To check server resource usage:**
    `sudo ./manage-services.sh usage all`
*   **To view live logs for web services:**
    `sudo ./manage-services.sh logs web`

**Available Commands:** `start`, `stop`, `restart`, `status`, `usage`, `logs`
**Available Service Groups:** `web`, `mail`, `all`

</details>

### 💾 6.3. Backup & Restore (`backup.sh`)

A powerful backup script is included to help you safeguard your server data.

<details>
<summary><strong>Click to view `backup.sh` Usage & Features</strong></summary>

**Features:**
*   Backs up WordPress files and database.
*   Backs up Mail-in-a-Box data.
*   Optional automatic upload to a cloud storage provider using `rclone`.
*   Optional email notifications on success or failure.
*   **New:** Automated restore from a backup file.

**Usage:**
*   `sudo ./backup.sh`: Run a standard backup.
*   `sudo ./backup.sh -r my-remote:path`: Run a backup and upload to an `rclone` remote.
*   `sudo ./backup.sh -e admin@example.com`: Send a notification email after backup.
*   `sudo ./backup.sh -f /path/to/backup.tar.gz`: Restore the server from a backup file.
*   `sudo ./backup.sh -h`: Show manual restore instructions.

**Automated Restore Process:**
The `-f` option provides an automated way to restore your server.
> **Warning:** This is a destructive operation and will overwrite your current data.

The restore process will:
1.  Ask for confirmation by requiring you to type the domain name.
2.  Stop web and mail services.
3.  Restore WordPress files, the database, and Mail-in-a-Box data.
4.  Restart the services.

**Cloud Backup Setup:**
To use the cloud backup feature, you must first install and configure `rclone`.
1.  You can install it with `sudo apt-get update && sudo apt-get install rclone`.
2.  Once installed, run `sudo rclone config` to set up a new remote for your chosen cloud provider (e.g., Google Drive, Dropbox, S3).
3.  Follow the official [rclone documentation](https://rclone.org/docs/) for detailed instructions.
4.  Once configured, you can use the `-r` option with the remote name you created.

</details>

### ❤️ 6.4. Auto-healing Script (`autoheal.sh`)

To improve server reliability, an `autoheal.sh` script is provided. This script automatically checks critical services (`nginx`, `php-fpm`, `mariadb`, `postfix`, `dovecot`) and restarts them if they are not running.

<details>
<summary><strong>Click to view `autoheal.sh` Setup</strong></summary>

**Setup:**
To make this script run automatically, you need to add it to the system's cron table.

1.  **Make the script executable:**
    ```bash
    chmod +x autoheal.sh
    ```

2.  **Edit the root crontab:**
    ```bash
    sudo crontab -e
    ```

3.  **Add the following line** to the end of the file to run the script every 5 minutes:
    ```cron
    */5 * * * * /full/path/to/your/scripts/autoheal.sh
    ```
    > **Note:** Make sure to replace `/full/path/to/your/scripts/` with the actual absolute path to where you've saved the scripts.

The script will log its actions to `/var/log/autoheal.log`.

</details>

### 🚀 6.5. Smart Update Script (`update.sh`)

<details>
<summary><strong>Click to view details for `update.sh`</strong></summary>

A smart update script, `update.sh`, is provided to simplify server maintenance. It is highly recommended to run this script manually and supervise the process.

**Features:**
*   Performs a full server backup using `backup.sh` before starting the update.
*   Updates all system packages using `apt`.
*   Updates Mail-in-a-Box to the latest version.
*   Updates WordPress core, themes, and plugins using `wp-cli` (which it will install if not present).

**Usage:**
```bash
sudo ./update.sh
```
> **Warning:** This script performs major updates to your system. While it includes a backup step, always be prepared for potential issues after an update. It is recommended to reboot the server after the script completes.

</details>

### 🪄 6.6. WordPress Manager (`wp-manager.sh`)

<details>
<summary><strong>Click to view details for `wp-manager.sh`</strong></summary>

For easier WordPress administration from the command line, a `wp-manager.sh` script is provided. It uses `wp-cli` to perform common tasks.

**Usage:**
*   `sudo ./wp-manager.sh user-create <user> <email> [pass]`
    *   Creates a new WordPress administrator. A secure password will be generated if not provided.
*   `sudo ./wp-manager.sh plugin <activate|deactivate|toggle> <plugin-slug>`
    *   Manages a plugin.
*   `sudo ./wp-manager.sh maintenance <on|off>`
    *   Enables or disables WordPress maintenance mode.

</details>

### 🔗 6.7. URL Shortener (`setup-server.sh`)

The main setup script now includes an option to install a [Yourls](https://yourls.org/) URL shortener.

**Usage:**
1.  Run the main setup script: `sudo ./setup-server.sh`
2.  Select option **2. Install URL Shortener (Yourls)** from the menu.
3.  The script will guide you through the process, asking for the domain you want to use and an admin username and password.
4.  It will automatically install and configure the application, database, and web server, and secure it with an SSL certificate.
5.  At the end, it will provide you with the URL and admin credentials.
