#!/bin/bash

version=8.1
timezone=America/Chicago
APACHE_LOG_DIR=/var/log/apache2

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit 1
fi

echo "Updating repos"; apt update > /dev/null 2>&1
echo "Installing Prereqs for PHP"; apt install -y lsb-release ca-certificates apt-transport-https software-properties-common gnupg2 > /dev/null 2>&1
echo "Adding Sury repo"; echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" |  tee /etc/apt/sources.list.d/sury-php.list > /dev/null 
echo "Adding GPG key for Sury repo"; curl -fsSL  https://packages.sury.org/php/apt.gpg|  gpg --dearmor -o /etc/apt/trusted.gpg.d/sury-keyring.gpg > /dev/null
echo "Updating repos"; apt update > /dev/null 2>&1
echo "Installing Base"; apt install -y apache2 libapache2-mod-php$version mariadb-server php$version-xml php$version-cli php$version-cgi php$version-mysql php$version-mbstring php$version-gd php$version-curl php$version-zip wget unzip > /dev/null 2>&1

# configure php ini file, check version

cp /etc/php/$version/apache2/php.ini /etc/php/$version/apache2/php.ini.bak
sed -i 's/^memory_limit = .*/memory_limit = 512M/' /etc/php/$version/apache2/php.ini
sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 500M/' /etc/php/$version/apache2/php.ini
sed -i 's/^post_max_size = .*/post_max_size = 500M/' /etc/php/$version/apache2/php.ini
sed -i 's/^max_execution_time = .*/max_execution_time = 300/' /etc/php/$version/apache2/php.ini
sed -i "s|\;date.timezone =|date.timezone = $timezone|g" /etc/php/$version/apache2/php.ini

echo "Enabling Services"
systemctl enable --now apache2 > /dev/null 2>&1
systemctl enable --now mariadb > /dev/null 2>&1

# Create a database with a user, grant privileges
mysql -e "CREATE DATABASE nextclouddb;"
mysql -e "CREATE USER 'ncadmin'@'localhost' IDENTIFIED BY 'password';"
mysql -e "GRANT ALL ON nextclouddb.* TO 'ncadmin'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Download, Extract and place nextcloud
echo "Installing Nextcloud"; wget -q https://download.nextcloud.com/server/releases/latest.zip
echo "Unzipping"; unzip latest.zip > /dev/null && rm latest.zip
mv nextcloud /var/www/html/
chown -R www-data:www-data /var/www/html/nextcloud/
chmod -R 755 /var/www/html/nextcloud/

#configure apache, add lines
cat << EOF > /etc/apache2/sites-available/nextcloud.conf
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
EOF

#enable apache virtual host
echo "Disable default site"; a2dissite 000-default.conf > /dev/null
echo "Enable nextcloud.conf"; a2ensite nextcloud.conf > /dev/null
a2enmod rewrite headers env dir mime > /dev/null
systemctl restart apache2 > /dev/null


#SSL
##apt-get install python-certbot-apache -y
##certbot --apache -d domain.whatever