#Installation Script #2 Test
#!/bin/bash

# Updating packages
apt update
apt upgrade -y

# Installing Necessary Dependencies
apt install -y lsb-release apt-transport-https ca-certificates software-properties-common wget sudo

# Adding PHP repository
sudo wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
sudo sh -c 'echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list'
sudo apt update

# PHP 8.3 Installation and Necessary Modules
sudo apt install -y php8.3 php8.3-{bcmath,xml,fpm,mysql,zip,intl,ldap,gd,cli,bz2,curl,mbstring,pgsql,opcache,soap,cgi}

# Installation of Apache and configuration for PHP 8.3
sudo apt install -y apache2 libapache2-mod-php8.3

# Installation de MariaDB
sudo apt -y install mariadb-server mariadb-client

# Secure configuration of MariaDB
sudo mysql_secure_installation

# Prompts the user to enter the database username and password
read -p "Enter username for Nextcloud database: (ex: nextcloud): " dbuser
read -sp "Enter the password for the Nextcloud database: (ex: nextcloud): " dbpass
echo

# Database configuration for Nextcloud
sudo mysql -u root -p <<MYSQL_SCRIPT
CREATE USER '${dbuser}'@'localhost' IDENTIFIED BY '${dbpass}';
CREATE DATABASE ${dbuser};
GRANT ALL PRIVILEGES ON ${dbuser}.* TO '${dbuser}'@'localhost';
FLUSH PRIVILEGES;
QUIT
MYSQL_SCRIPT

echo "The database for Nextcloud has been configured."

# Request Nextcloud directory path and server name
read -p "Enter the full path to the Nextcloud directory (ex: /var/www/nextcloud): " nextcloud_path
read -p "Enter the server name for Nextcloud (ex: cloud.example.net): " server_name

# Configuring VirtualHost Apache for Nextcloud
echo "Do you want to configure a VirtualHost for Nextcloud in HTTP or HTTPS (SSL) ? [HTTP/HTTPS]"
read -r server_protocol

if [ "$server_protocol" == "HTTPS" ]; then
    # Configuration pour HTTPS
    sudo bash -c 'cat > /etc/apache2/sites-available/nextcloud.conf' << EOF
<VirtualHost *:80>
    ServerName $server_name
    RewriteEngine On
    RewriteCond %{HTTPS} !=on
    RewriteRule ^/?(.*) https://%{SERVER_NAME}/$1 [R=301,L]
</VirtualHost>
<VirtualHost *:443>
    ServerAdmin admin@$server_name
    DocumentRoot $nextcloud_path
    ServerName $server_name
    <Directory $nextcloud_path>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
        SetEnv HOME $nextcloud_path
        SetEnv HTTP_HOME $nextcloud_path
    </Directory>
    ErrorLog /var/log/apache2/nextcloud-error.log
    CustomLog /var/log/apache2/nextcloud-access.log combined
    SSLEngine on
    SSLCertificateFile /etc/ssl/nextcloud/fullchain.pem
    SSLCertificateKeyFile /etc/ssl/nextcloud/privkey.pem
</VirtualHost>
EOF
else
    # Configuration pour HTTP
    sudo bash -c 'cat > /etc/apache2/sites-available/nextcloud.conf' << EOF
<VirtualHost *:80>
    ServerAdmin admin@$server_name
    DocumentRoot $nextcloud_path
    ServerName $server_name
    <Directory $nextcloud_path>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog /var/log/apache2/nextcloud-error.log
    CustomLog /var/log/apache2/nextcloud-access.log combined
</VirtualHost>
EOF
fi

# Activating the new site and restarting Apache
sudo a2ensite nextcloud.conf
sudo systemctl restart apache2

# Installing additional PHP modules for Nextcloud
sudo apt-get install -y php-gmp php-bcmath php-imagick smbclient php-smbclient
sudo phpenmod gmp
sudo phpenmod bcmath
sudo phpenmod imagick

# Installing and configuring Redis
sudo apt install -y redis-server php-redis
sudo systemctl restart redis-server

# Editing Nextcloud config.php file for Redis configuration
CONFIG_FILE="$nextcloud_path/config/config.php"
if [ -f "$CONFIG_FILE" ]; then
    sudo sed -i "/);/i 'memcache.local' => '\\OC\\Memcache\\Redis'," $CONFIG_FILE
    grep -q "'memcache.locking'" $CONFIG_FILE || sudo sed -i "/);/i 'memcache.locking' => '\\OC\\Memcache\\Redis'," $CONFIG_FILE
    grep -q "'redis' =>" $CONFIG_FILE || {
        sudo sed -i "/);/i 'redis' => array(" $CONFIG_FILE
        sudo sed -i "/);/i 'host' => 'localhost'," $CONFIG_FILE
        sudo sed -i "/);/i 'port' => 6379," $CONFIG_FILE
        sudo sed -i "/);/i )," $CONFIG_FILE
    }
else
    echo "The config.php file was not found. Make sure Nextcloud is installed correctly and the path is correct."
fi

echo "Nextcloud and all dependencies have been installed successfully."
