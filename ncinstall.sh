#!/bin/bash

version=8.1
timezone=America/Chicago

echo "Updating repos"; sudo apt update > /dev/null
echo "Installing Prereqs for PHP"; sudo apt install -y lsb-release ca-certificates apt-transport-https software-properties-common gnupg2 > /dev/null
echo "Adding Sury repo"; echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/sury-php.list
echo "Adding GPG key for Sury repo"; curl -fsSL  https://packages.sury.org/php/apt.gpg| sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/sury-keyring.gpg
echo "Installing Base"; sudo apt install -y apache2 libapache2-mod-php$version mariadb-server php$version-xml php$version-cli php$version-cgi php$version-mysql php$version-mbstring php$version-gd php$version-curl php$version-zip wget unzip > /dev/null

#configure php ini file, check version

sudo sed -i 's/^memory_limit = .*/memory_limit = 512M/' /etc/php/$version/apache2/php.ini
sudo sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 500M/' /etc/php/$version/apache2/php.ini
sudo sed -i 's/^post_max_size = .*/post_max_size = 500M/' /etc/php/$version/apache2/php.ini
sudo sed -i 's/^max_execution_time = .*/max_execution_time = 300/' /etc/php/$version/apache2/php.ini
sudo sed -i "s|\;date.timezone =|date.timezone = $timezone|g" /etc/php/$version/apache2/php.ini

toilet -f smblock --gay "enabling services"
systemctl start apache2
systemctl start mariadb
systemctl enable apache2
systemctl enable mariadb

#setup a database, provide root password when asked
##mysql -u root -p
##MariaDB [(none)]> CREATE DATABASE nextclouddb;
##MariaDB [(none)]> CREATE USER 'username'@'localhost' IDENTIFIED BY 'password';
#grant privileges to the database, flush and exit mariadb
##MariaDB [(none)]> GRANT ALL ON nextclouddb.* TO 'username'@'localhost';
##MariaDB [(none)]> FLUSH PRIVILEGES;
##MariaDB [(none)]> EXIT;

#download nc
echo Would you like to install Next Cloud? "(Y or N)"
read x
if [ "$x" = "y" ]; then
    echo "Installing Base" &&
    toilet -f smblock --gay "downloading nextcloud"
    wget https://download.nextcloud.com/server/releases/nextcloud-20.0.1.zip
    unzip nextcloud-20.0.1.zip
    mv nextcloud /var/www/html/
    chown -R www-data:www-data /var/www/html/nextcloud/
    chmod -R 755 /var/www/html/nextcloud/
fi

#configure apache, add lines
##nano /etc/apache2/sites-available/nextcloud.conf
###<VirtualHost *:80>
###     ServerAdmin admin@example.com
###     DocumentRoot /var/www/html/nextcloud/
###     ServerName nextcloud.example.com
###
###     Alias /nextcloud "/var/www/html/nextcloud/"
###
###     <Directory /var/www/html/nextcloud/>
###        Options +FollowSymlinks
###        AllowOverride All
###        Require all granted
###          <IfModule mod_dav.c>
###            Dav off
###          </IfModule>
###        SetEnv HOME /var/www/html/nextcloud
###        SetEnv HTTP_HOME /var/www/html/nextcloud
###     </Directory>
###
###     ErrorLog ${APACHE_LOG_DIR}/error.log
###     CustomLog ${APACHE_LOG_DIR}/access.log combined
###
###</VirtualHost>

#enable apache virtual host
##a2ensite nextcloud.conf
##a2enmod rewrite
##a2enmod headers
##a2enmod env
##a2enmod dir
##a2enmod mime
##systemctl restart apache2

#SSL
##apt-get install python-certbot-apache -y
##certbot --apache -d domain.whatever