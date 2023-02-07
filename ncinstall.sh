#!/bin/bash
toilet -f smblock --gay "updating"
sudo apt update -y
notify-send "Linux Rulez" &&
notify-send "Tristan Smellz"
echo Would you like to install required packages? "(Y or N)"
read x
if [ "$x" = "y" ]; then
    echo "Installing Base" &&
    apt-get install apache2 libapache2-mod-php mariadb-server php-xml php-cli php-cgi php-mysql php-mbstring php-gd php-curl php-zip wget unzip -y
fi

#configure php ini file, check version
#add to file
##nano /etc/php/7.3/apache2/php.ini
###memory_limit = 512M
###upload_max_filesize = 500M
###post_max_size = 500M
###max_execution_time = 300
###date.timezone = America/Chicago

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