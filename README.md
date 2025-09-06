# Unified Server Setup & Management Script

**Author:** Jules
**Version:** 1.0

---

## English

### 🚀 Introduction

This script provides a single, powerful, and user-friendly tool to automate the setup and management of a complete web server. It is a menu-driven script designed to work on modern Debian-based (Debian, Ubuntu) and RHEL-based (CentOS, Fedora, Rocky, AlmaLinux) systems.

It simplifies complex tasks like setting up a LEMP stack, creating websites with SSL, configuring a mail server, and managing users and backups.

### ✨ Features

*   **Initial Server Setup**: Installs a full LEMP stack (Linux, Nginx, MariaDB, PHP), configures a UFW firewall, and secures the database installation.
*   **Website Management**: Easily add new websites. The script automatically creates the Nginx server block and obtains a free SSL certificate from Let's Encrypt.
*   **Mail Server**: Sets up a complete, functional mail server using Postfix and Dovecot, ready to handle emails for your domain.
*   **Secure SFTP Users**: Create new users who are restricted (jailed) to a specific directory and can only connect via SFTP, not SSH. Perfect for giving clients or developers access to manage web files securely.
*   **Backup & Restore**: A simple yet powerful utility to back up a website's files and its database into a single archive. A restore function with built-in safety checks is also included.

### ✅ Prerequisites

1.  A server running a fresh installation of a supported OS (Debian 10+, Ubuntu 20.04+, CentOS/RHEL 8+, Fedora 30+ recommended).
2.  A registered domain name.
3.  Root or `sudo` access to the server.

### 🛠️ How to Use

1.  **Download the script:**
    ```bash
    wget -O setup.sh https://raw.githubusercontent.com/your-repo/path/to/setup.sh
    ```

2.  **Make it executable:**
    ```bash
    chmod +x setup.sh
    ```

3.  **Run the script:**
    ```bash
    sudo ./setup.sh
    ```
    You will be presented with the main menu.

### 📋 Menu Options Explained

*   **1. Initial Server Setup (Update, Firewall, LEMP)**
    *   This should be the first option you run on a new server.
    *   It updates system packages, installs Nginx, MariaDB, and PHP, configures the firewall (UFW), and runs the initial MariaDB security setup.

*   **2. Add New Website (with SSL)**
    *   Prompts for a domain name (e.g., `example.com`).
    *   Creates the web directory at `/var/www/example.com`.
    *   Creates a new Nginx server block.
    *   Installs Certbot (if needed) and obtains a free SSL certificate for the domain and its `www` subdomain. Your site will be available via `https://`.

*   **3. Setup Mail Server (Postfix & Dovecot)**
    *   **DNS Prerequisite:** Before running this, you MUST have an **MX record** for your domain pointing to your server's hostname (e.g., `mail.example.com`). You must also have an **A record** for that hostname pointing to your server's IP.
    *   This option installs and configures Postfix and Dovecot to create a fully functional mail server.

*   **4. Create SFTP User**
    *   **Security Prerequisite:** The directory you want to jail the user in (e.g., `/var/www/example.com`) **MUST be owned by `root`**. This is a security requirement of the SSH server. You can then create a writable subdirectory inside (e.g., `/var/www/example.com/public_html`) owned by the new user.
    *   This option creates a new user who can only log in via SFTP to manage files in their specified directory.

*   **5. Backup Server/Website**
    *   Prompts for a domain name and its associated database name.
    *   Creates a `.tar.gz` archive containing all web files and a `.sql` dump of the database.
    *   Backups are saved in `/root/backups/`.

*   **6. Restore Server/Website**
    *   ⚠️ **WARNING:** This is a destructive operation.
    *   Prompts for the path to a backup file.
    *   It will overwrite the current web files and database. For safety, it renames the existing web directory to `.bak` before restoring.

### 📝 Logging

All operations performed by the script are logged to `/var/log/server_setup.log` for easy debugging and review.

---
---

## Français

### 🚀 Introduction

Ce script fournit un outil unique, puissant et convivial pour automatiser l'installation et la gestion d'un serveur web complet. Il s'agit d'un script piloté par un menu, conçu pour fonctionner sur les systèmes modernes basés sur Debian (Debian, Ubuntu) et RHEL (CentOS, Fedora, Rocky, AlmaLinux).

Il simplifie des tâches complexes telles que la mise en place d'une pile LEMP, la création de sites web avec SSL, la configuration d'un serveur de messagerie, et la gestion des utilisateurs et des sauvegardes.

### ✨ Fonctionnalités

*   **Installation Initiale du Serveur**: Installe une pile LEMP complète (Linux, Nginx, MariaDB, PHP), configure un pare-feu UFW et sécurise l'installation de la base de données.
*   **Gestion de Sites Web**: Ajoutez facilement de nouveaux sites web. Le script crée automatiquement le "server block" Nginx et obtient un certificat SSL gratuit de Let's Encrypt.
*   **Serveur de Messagerie**: Met en place un serveur de messagerie complet et fonctionnel utilisant Postfix et Dovecot, prêt à gérer les e-mails pour votre domaine.
*   **Utilisateurs SFTP Sécurisés**: Créez de nouveaux utilisateurs qui sont restreints (emprisonnés ou "jailed") à un répertoire spécifique et ne peuvent se connecter que via SFTP, pas en SSH. Parfait pour donner un accès sécurisé à des clients ou des développeurs pour gérer les fichiers d'un site.
*   **Sauvegarde & Restauration**: Un utilitaire simple mais puissant pour sauvegarder les fichiers d'un site web et sa base de données dans une seule archive. Une fonction de restauration avec des mesures de sécurité intégrées est également incluse.

### ✅ Prérequis

1.  Un serveur avec une nouvelle installation d'un OS supporté (Debian 10+, Ubuntu 20.04+, CentOS/RHEL 8+, Fedora 30+ recommandé).
2.  Un nom de domaine enregistré.
3.  Un accès root ou `sudo` au serveur.

### 🛠️ Comment l'utiliser

1.  **Téléchargez le script :**
    ```bash
    wget -O setup.sh https://raw.githubusercontent.com/votre-repo/path/to/setup.sh
    ```

2.  **Rendez-le exécutable :**
    ```bash
    chmod +x setup.sh
    ```

3.  **Exécutez le script :**
    ```bash
    sudo ./setup.sh
    ```
    Le menu principal s'affichera.

### 📋 Explication des Options du Menu

*   **1. Installation Initiale du Serveur (Mise à jour, Pare-feu, LEMP)**
    *   Ce devrait être la première option que vous exécutez sur un nouveau serveur.
    *   Elle met à jour les paquets système, installe Nginx, MariaDB et PHP, configure le pare-feu (UFW) et effectue la configuration de sécurité initiale de MariaDB.

*   **2. Ajouter un Nouveau Site Web (avec SSL)**
    *   Demande un nom de domaine (ex: `example.com`).
    *   Crée le répertoire web dans `/var/www/example.com`.
    *   Crée un nouveau "server block" Nginx.
    *   Installe Certbot (si nécessaire) et obtient un certificat SSL gratuit pour le domaine et son sous-domaine `www`. Votre site sera disponible via `https://`.

*   **3. Configurer le Serveur de Messagerie (Postfix & Dovecot)**
    *   **Prérequis DNS :** Avant d'exécuter cette option, vous DEVEZ avoir un **enregistrement MX** pour votre domaine qui pointe vers le nom d'hôte de votre serveur (ex: `mail.example.com`). Vous devez également avoir un **enregistrement A** pour ce nom d'hôte qui pointe vers l'adresse IP de votre serveur.
    *   Cette option installe et configure Postfix et Dovecot pour créer un serveur de messagerie entièrement fonctionnel.

*   **4. Créer un Utilisateur SFTP**
    *   **Prérequis de Sécurité :** Le répertoire dans lequel vous souhaitez emprisonner l'utilisateur (ex: `/var/www/example.com`) **DOIT appartenir à `root`**. C'est une exigence de sécurité du serveur SSH. Vous pouvez ensuite créer un sous-répertoire accessible en écriture à l'intérieur (ex: `/var/www/example.com/public_html`) appartenant au nouvel utilisateur.
    *   Cette option crée un nouvel utilisateur qui ne peut se connecter que via SFTP pour gérer les fichiers dans le répertoire spécifié.

*   **5. Sauvegarder le Serveur/Site Web**
    *   Demande un nom de domaine et le nom de sa base de données associée.
    *   Crée une archive `.tar.gz` contenant tous les fichiers web et un export `.sql` de la base de données.
    *   Les sauvegardes sont enregistrées dans `/root/backups/`.

*   **6. Restaurer le Serveur/Site Web**
    *   ⚠️ **ATTENTION :** Ceci est une opération destructive.
    *   Demande le chemin vers un fichier de sauvegarde.
    *   Elle écrasera les fichiers web et la base de données actuels. Par sécurité, elle renomme le répertoire web existant en `.bak` avant la restauration.

### 📝 Journalisation (Logging)

Toutes les opérations effectuées par le script sont enregistrées dans `/var/log/server_setup.log` pour faciliter le débogage et la consultation.
