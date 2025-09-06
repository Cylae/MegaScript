# Unified Server Setup & Management Script

**Author:** Jules
**Version:** 2.0

---

## English

### 🚀 Introduction

This script provides a single, powerful, and user-friendly tool to automate the setup and management of a complete web server. It is a menu-driven script designed to work on modern Debian-based (Debian, Ubuntu) and RHEL-based (CentOS, Fedora, Rocky, AlmaLinux) systems.

It simplifies complex tasks like setting up a LEMP stack, creating websites with SSL, configuring a mail server, and managing users and backups, all while being robust and secure.

### ✨ Features

*   **Multi-Language Support**: Choose between English and French at startup.
*   **Initial Server Setup**: Installs a full LEMP stack (Linux, Nginx, MariaDB, PHP), configures a UFW firewall, and secures the database installation.
*   **Website Management**: Easily add new websites. The script automatically creates the Nginx server block and obtains a free SSL certificate from Let's Encrypt.
*   **Mail Server**: Sets up a complete, functional mail server using Postfix and Dovecot, ready to handle emails for your domain.
*   **Secure SFTP Users**: Create new users who are restricted (jailed) to a specific directory and can only connect via SFTP, not SSH. Perfect for giving clients or developers access to manage web files securely.
*   **Security Hardening**: Installs and configures **Fail2ban** to protect against brute-force attacks on services like SSH, Postfix, and Dovecot.
*   **Robust Configuration**: Uses `augtool` and `postconf` instead of fragile `sed` commands for safer and more reliable configuration changes.
*   **Backup & Restore**: A simple yet powerful utility to back up a website's files and its database into a single archive. A restore function with built-in safety checks is also included.
*   **Automated Testing**: Comes with a test suite built with `bats` to ensure reliability and prevent regressions.

### ✅ Prerequisites & Dependencies

1.  A server running a fresh installation of a supported OS (Debian 10+, Ubuntu 20.04+, CentOS/RHEL 8+, Fedora 30+ recommended).
2.  A registered domain name.
3.  Root or `sudo` access to the server.
4.  The script will attempt to install the following dependencies if they are not found:
    *   `augeas-tools` (for robust configuration management)
    *   `fail2ban` (for security hardening)
    *   `bats`, `bats-support`, `bats-assert` (for running the test suite)

### 🛠️ How to Use

1.  **Download the script and its language files:**
    ```bash
    # You will need to download setup.sh and the lang/ directory
    wget -O setup.sh https://raw.githubusercontent.com/your-repo/path/to/setup.sh
    mkdir lang
    wget -O lang/en.sh https://raw.githubusercontent.com/your-repo/path/to/lang/en.sh
    wget -O lang/fr.sh https://raw.githubusercontent.com/your-repo/path/to/lang/fr.sh
    ```

2.  **Make it executable:**
    ```bash
    chmod +x setup.sh
    ```

3.  **Run the script:**
    ```bash
    sudo ./setup.sh
    ```
    You will first be prompted to choose a language, then the main menu will appear.

### 🧪 Testing

This project includes an automated test suite using `bats`. The tests are located in the `test/` directory.

**To run the tests:**
1.  Ensure you have `bats` installed (the script will try to install it if you run the testing option, but you can also install it manually: `sudo apt-get install bats`).
2.  Run the tests from the root of the project directory:
    ```bash
    sudo bats test/test_sftp.bats
    ```
    *Note: `sudo` is required because the tests perform real system operations like creating users and modifying configuration files.*

### 📋 Menu Options Explained

*   **1. Initial Server Setup (Update, Firewall, LEMP)**
    *   This should be the first option you run on a new server. It installs LEMP, configures the firewall, and secures MariaDB.

*   **2. Add New Website (with SSL)**
    *   Creates a new website with an Nginx server block and a free Let's Encrypt SSL certificate.

*   **3. Setup Mail Server (Postfix & Dovecot)**
    *   **DNS Prerequisite:** You MUST have correctly configured MX and A records for your domain.
    *   Installs and configures a full mail server.

*   **4. Create SFTP User**
    *   **Security Prerequisite:** The user's jail directory MUST be owned by `root`.
    *   Creates a new, secure SFTP-only user.

*   **5. Harden Security (Install Fail2ban)**
    *   Installs and configures Fail2ban to protect against brute-force attacks.

*   **6. Backup Website**
    *   Creates a `.tar.gz` archive of a site's files and database, saved in `/root/backups/`.

*   **7. Restore Website**
    *   ⚠️ **WARNING:** This is a destructive operation.
    *   Restores a site from a backup file, with safety checks.

*   **8. Manage Existing Services**
    *   Opens a sub-menu for managing services that have already been created.
    *   **Manage Websites:** Allows you to delete, disable, or enable existing websites.
    *   **Manage SFTP Users:** Allows you to change the password of or delete existing SFTP users.
    *   **Manage Email Accounts:** Allows you to add, delete, or list existing email accounts.

*   **9. Exit**
    *   Exits the script.

### 📝 Logging

All operations performed by the script are logged to `/var/log/server_setup.log` for easy debugging and review.

---
---

## Français

### 🚀 Introduction

Ce script fournit un outil unique, puissant et convivial pour automatiser l'installation et la gestion d'un serveur web complet. Il s'agit d'un script piloté par un menu, conçu pour fonctionner sur les systèmes modernes basés sur Debian (Debian, Ubuntu) et RHEL (CentOS, Fedora, Rocky, AlmaLinux).

Il simplifie des tâches complexes telles que la mise en place d'une pile LEMP, la création de sites web avec SSL, la configuration d'un serveur de messagerie, et la gestion des utilisateurs et des sauvegardes, tout en étant robuste et sécurisé.

### ✨ Fonctionnalités

*   **Support Multilingue**: Choisissez entre l'anglais et le français au démarrage.
*   **Installation Initiale du Serveur**: Installe une pile LEMP complète (Linux, Nginx, MariaDB, PHP), configure un pare-feu UFW et sécurise l'installation de la base de données.
*   **Gestion de Sites Web**: Ajoutez facilement de nouveaux sites web. Le script crée automatiquement le "server block" Nginx et obtient un certificat SSL gratuit de Let's Encrypt.
*   **Serveur de Messagerie**: Met en place un serveur de messagerie complet et fonctionnel utilisant Postfix et Dovecot, prêt à gérer les e-mails pour votre domaine.
*   **Utilisateurs SFTP Sécurisés**: Créez de nouveaux utilisateurs qui sont restreints (emprisonnés ou "jailed") à un répertoire spécifique et ne peuvent se connecter que via SFTP, pas en SSH. Parfait pour donner un accès sécurisé à des clients ou des développeurs pour gérer les fichiers d'un site.
*   **Renforcement de la Sécurité**: Installe et configure **Fail2ban** pour protéger contre les attaques par force brute sur des services comme SSH, Postfix et Dovecot.
*   **Configuration Robuste**: Utilise `augtool` et `postconf` au lieu de commandes `sed` fragiles pour des modifications de configuration plus sûres et plus fiables.
*   **Sauvegarde & Restauration**: Un utilitaire simple mais puissant pour sauvegarder les fichiers d'un site web et sa base de données dans une seule archive. Une fonction de restauration avec des mesures de sécurité intégrées est également incluse.
*   **Tests Automatisés**: Fourni avec une suite de tests construite avec `bats` pour assurer la fiabilité et prévenir les régressions.

### ✅ Prérequis & Dépendances

1.  Un serveur avec une nouvelle installation d'un OS supporté (Debian 10+, Ubuntu 20.04+, CentOS/RHEL 8+, Fedora 30+ recommandé).
2.  Un nom de domaine enregistré.
3.  Un accès root ou `sudo` au serveur.
4.  Le script tentera d'installer les dépendances suivantes si elles ne sont pas trouvées :
    *   `augeas-tools` (pour une gestion de configuration robuste)
    *   `fail2ban` (pour le renforcement de la sécurité)
    *   `bats`, `bats-support`, `bats-assert` (pour exécuter la suite de tests)

### 🛠️ Comment l'utiliser

1.  **Téléchargez le script et ses fichiers de langue :**
    ```bash
    # Vous devrez télécharger setup.sh et le répertoire lang/
    wget -O setup.sh https://raw.githubusercontent.com/votre-repo/chemin/vers/setup.sh
    mkdir lang
    wget -O lang/en.sh https://raw.githubusercontent.com/votre-repo/chemin/vers/lang/en.sh
    wget -O lang/fr.sh https://raw.githubusercontent.com/votre-repo/chemin/vers/lang/fr.sh
    ```

2.  **Rendez-le exécutable :**
    ```bash
    chmod +x setup.sh
    ```

3.  **Exécutez le script :**
    ```bash
    sudo ./setup.sh
    ```
    Il vous sera d'abord demandé de choisir une langue, puis le menu principal s'affichera.

### 🧪 Tests

Ce projet inclut une suite de tests automatisés utilisant `bats`. Les tests se trouvent dans le répertoire `test/`.

**Pour exécuter les tests :**
1.  Assurez-vous que `bats` est installé (le script essaiera de l'installer si vous exécutez l'option de test, mais vous pouvez aussi l'installer manuellement : `sudo apt-get install bats`).
2.  Exécutez les tests depuis la racine du répertoire du projet :
    ```bash
    sudo bats test/test_sftp.bats
    ```
    *Note : `sudo` est requis car les tests effectuent de réelles opérations système comme la création d'utilisateurs et la modification de fichiers de configuration.*

### 📋 Explication des Options du Menu

*   **1. Configuration Initiale du Serveur (MàJ, Pare-feu, LEMP)**
    *   La première option à exécuter sur un nouveau serveur. Elle installe LEMP, configure le pare-feu et sécurise MariaDB.

*   **2. Ajouter un Nouveau Site Web (avec SSL)**
    *   Crée un nouveau site web avec un "server block" Nginx et un certificat SSL gratuit de Let's Encrypt.

*   **3. Configurer le Serveur Mail (Postfix & Dovecot)**
    *   **Prérequis DNS :** Vous DEVEZ avoir configuré correctement les enregistrements MX et A pour votre domaine.
    *   Installe et configure un serveur de messagerie complet.

*   **4. Créer un Utilisateur SFTP**
    *   **Prérequis de Sécurité :** Le répertoire d'emprisonnement de l'utilisateur DOIT appartenir à `root`.
    *   Crée un nouvel utilisateur sécurisé, limité au SFTP.

*   **5. Renforcer la Sécurité (Installer Fail2ban)**
    *   Installe et configure Fail2ban pour protéger contre les attaques par force brute.

*   **6. Sauvegarder un Site Web**
    *   Crée une archive `.tar.gz` des fichiers et de la base de données d'un site, sauvegardée dans `/root/backups/`.

*   **7. Restaurer un Site Web**
    *   ⚠️ **ATTENTION :** Ceci est une opération destructive.
    *   Restaure un site à partir d'un fichier de sauvegarde, avec des mesures de sécurité.

*   **8. Gérer les Services Existants**
    *   Ouvre un sous-menu pour la gestion des services déjà créés.
    *   **Gérer les sites web :** Vous permet de supprimer, désactiver ou activer des sites web existants.
    *   **Gérer les utilisateurs SFTP :** Vous permet de changer le mot de passe ou de supprimer des utilisateurs SFTP existants.
    *   **Gérer les comptes de messagerie :** Vous permet d'ajouter, de supprimer ou de lister les comptes de messagerie existants.

*   **9. Quitter**
    *   Quitte le script.

### 📝 Journalisation (Logging)

Toutes les opérations effectuées par le script sont enregistrées dans `/var/log/server_setup.log` pour faciliter le débogage et la consultation.
