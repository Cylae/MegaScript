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
    *   This should be the first option you run on a new server. It installs LEMP, configures the firewall, and secures MariaDB.

*   **2. Add New Website (with SSL)**
    *   Creates a new website with an Nginx server block and a free Let's Encrypt SSL certificate.

*   **3. Setup Mail Server (Postfix & Dovecot)**
    *   **DNS Prerequisite:** You MUST have correctly configured MX and A records for your domain.
    *   Installs and configures a full mail server.

*   **4. Create SFTP User**
    *   **Security Prerequisite:** The user's jail directory MUST be owned by `root`.
    *   Creates a new, secure SFTP-only user.

*   **5. Backup Website**
    *   Creates a `.tar.gz` archive of a site's files and database, saved in `/root/backups/`.

*   **6. Restore Website**
    *   ⚠️ **WARNING:** This is a destructive operation.
    *   Restores a site from a backup file, with safety checks.

*   **7. Manage Existing Services**
    *   Opens a sub-menu for managing services that have already been created.
    *   **Manage Websites:** Allows you to delete, disable, or enable existing websites.
    *   **Manage SFTP Users:** Allows you to change the password of or delete existing SFTP users.
    *   **Manage Email Accounts:** Allows you to add, delete, or list existing email accounts.

*   **8. Exit**
    *   Exits the script.

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
    *   La première option à exécuter sur un nouveau serveur. Elle installe LEMP, configure le pare-feu et sécurise MariaDB.

*   **2. Ajouter un Nouveau Site Web (avec SSL)**
    *   Crée un nouveau site web avec un "server block" Nginx et un certificat SSL gratuit de Let's Encrypt.

*   **3. Configurer le Serveur de Messagerie (Postfix & Dovecot)**
    *   **Prérequis DNS :** Vous DEVEZ avoir configuré correctement les enregistrements MX et A pour votre domaine.
    *   Installe et configure un serveur de messagerie complet.

*   **4. Créer un Utilisateur SFTP**
    *   **Prérequis de Sécurité :** Le répertoire d'emprisonnement de l'utilisateur DOIT appartenir à `root`.
    *   Crée un nouvel utilisateur sécurisé, limité au SFTP.

*   **5. Sauvegarder un Site Web**
    *   Crée une archive `.tar.gz` des fichiers et de la base de données d'un site, sauvegardée dans `/root/backups/`.

*   **6. Restaurer un Site Web**
    *   ⚠️ **ATTENTION :** Ceci est une opération destructive.
    *   Restaure un site à partir d'un fichier de sauvegarde, avec des mesures de sécurité.

*   **7. Gérer les services existants**
    *   Ouvre un sous-menu pour la gestion des services déjà créés.
    *   **Gérer les sites web :** Vous permet de supprimer, désactiver ou activer des sites web existants.
    *   **Gérer les utilisateurs SFTP :** Vous permet de changer le mot de passe ou de supprimer des utilisateurs SFTP existants.
    *   **Gérer les comptes de messagerie :** Vous permet d'ajouter, de supprimer ou de lister les comptes de messagerie existants.

*   **8. Quitter**
    *   Quitte le script.

### 📝 Journalisation (Logging)

Toutes les opérations effectuées par le script sont enregistrées dans `/var/log/server_setup.log` pour faciliter le débogage et la consultation.
