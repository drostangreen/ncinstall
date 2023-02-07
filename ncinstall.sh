#!/bin/bash

version=8.1
timezone=America/Chicago
APACHE_LOG_DIR=/var/log/apache2

echo "Updating repos"; sudo apt update > /dev/null
echo "Installing Prereqs for PHP"; sudo apt install -y lsb-release ca-certificates apt-transport-https software-properties-common gnupg2 > /dev/null
echo "Adding Sury repo"; echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/sury-php.list
echo "Adding GPG key for Sury repo"; curl -fsSL  https://packages.sury.org/php/apt.gpg| sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/sury-keyring.gpg
echo "Installing Base"; sudo apt install -y apache2 libapache2-mod-php$version mariadb-server php$version-xml php$version-cli php$version-cgi php$version-mysql php$version-mbstring php$version-gd php$version-curl php$version-zip wget unzip > /dev/null

# configure php ini file, check version

cp /etc/php/$version/apache2/php.ini /etc/php/$version/apache2/php.ini.bak
sudo sed -i 's/^memory_limit = .*/memory_limit = 512M/' /etc/php/$version/apache2/php.ini
sudo sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 500M/' /etc/php/$version/apache2/php.ini
sudo sed -i 's/^post_max_size = .*/post_max_size = 500M/' /etc/php/$version/apache2/php.ini
sudo sed -i 's/^max_execution_time = .*/max_execution_time = 300/' /etc/php/$version/apache2/php.ini
sudo sed -i "s|\;date.timezone =|date.timezone = $timezone|g" /etc/php/$version/apache2/php.ini

echo "Enabling Services"
sudo systemctl enable --now apache2
sudo systemctl enable --now mariadb

# Create a database with a user, grant privileges
sudo mysql -e "CREATE DATABASE nextclouddb;"
sudo mysql -e "CREATE USER 'ncadmin'@'localhost' IDENTIFIED BY 'password';"
sudo mysql -e "GRANT ALL ON nextclouddb.* TO 'ncadmin'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# Download, Extract and place nextcloud
echo "Installing Nextcloud"; wget -q https://download.nextcloud.com/server/releases/latest.zip
echo "Unzipping"; unzip latest.zip > /dev/null && rm latest.zip
sudo mv nextcloud /var/www/html/
sudo chown -R www-data:www-data /var/www/html/nextcloud/
sudo chmod -R 755 /var/www/html/nextcloud/

#configure apache, add lines
sudo bash -c 'cat << EOF > /etc/apache2/sites-available/nextcloud.conf
<VirtualHost *:80>
    DocumentRoot /var/www/html/nextcloud/
    ServerName nextcloud.example.com

    Alias /nextcloud "/var/www/html/nextcloud/"

    <Directory /var/www/html/nextcloud/>
       Options +FollowSymlinks
       AllowOverride All
       Require all granted
         <IfModule mod_dav.c>
           Dav off
         </IfModule>
       SetEnv HOME /var/www/html/nextcloud
       SetEnv HTTP_HOME /var/www/html/nextcloud
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined

</VirtualHost>
EOF'

#enable apache virtual host
sudo a2ensite nextcloud.conf
sudo a2enmod rewrite headers env dir mime
sudo systemctl restart apache2

#SSL
##apt-get install python-certbot-apache -y
##certbot --apache -d domain.whatever