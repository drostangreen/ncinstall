#!/bin/bash

# PHP Version
version=8.1

# Apache Vars
timezone=America/Chicago
APACHE_LOG_DIR=/var/log/apache2
servername=nexctloud.example.com
root_dir=/var/www/html/nextcloud

# MariaDB/MySQL Vars
db_name=nextclouddb
db_user=dbadmin
db_pass=password

# Nextcloud
nc_user=ncadmin
nc_pass=password

set -e

Error(){
    echo "Error at line $1"
}
trap 'Error $LINENO' ERR

function pause(){
   read -p "$*"
}

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit 1
fi

echo "Updating repos"; apt update > /dev/null 2>&1
echo "Installing Prereqs for PHP"; apt install -y lsb-release ca-certificates apt-transport-https software-properties-common gnupg2 > /dev/null 2>&1
echo "Adding Sury repo"; echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" |  tee /etc/apt/sources.list.d/sury-php.list > /dev/null 
echo "Adding GPG key for Sury repo"; curl -fsSL  https://packages.sury.org/php/apt.gpg|  gpg --dearmor -o /etc/apt/trusted.gpg.d/sury-keyring.gpg > /dev/null
echo "Updating repos"; apt update > /dev/null 2>&1
echo "Installing Base"; apt install -y apache2 libapache2-mod-php$version mariadb-server php$version-xml php$version-cli php$version-cgi php$version-mysql php$version-mbstring php$version-gd php$version-curl php$version-zip php$version-imagick libmagickcore-6.q16-6-extra php$version-gmp php$version-intl php$version-bcmath php$version-apcu wget unzip > /dev/null 2>&1

# configure php ini file, set normal params then setup for memcache

echo "Backup php.ini file then modify"; sed -i.bak "s|^memory_limit = .*|memory_limit = 512M|;s|^upload_max_filesize = .*|upload_max_filesize = 500M|;s|^post_max_size = .*|post_max_size = 500M|;s|^max_execution_time = .*|max_execution_time = 300|;s|\;date.timezone =|date.timezone = $timezone|" /etc/php/$version/apache2/php.ini
sed -i "s/^;opcache\.enable=.*/opcache\.enable=1/;s/^;opcache\.interned_strings_bugger=.*/opcache\.interned_strings_buffer=8/;s/^;opcache\.max_accelerated_files=.*/opcache\.max_accelerated_files=10000/;s/^;opcache\.memory_consumption=.*/opcache.memory_consumption=128/;s/^;opcache\.save_comments=.*/opcache.save_comments=1/;s/^;opcache\.revalidate_freq=.*/opcache.revalidate_freq=1/" /etc/php/$version/apache2/php.ini

echo "Enabling Services"
systemctl enable --now apache2 mariadb > /dev/null 2>&1

# Create a database with a user, grant privileges
mysql -e "CREATE DATABASE ${db_name};"
mysql -e "CREATE USER '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';"
mysql -e "GRANT ALL ON ${db_name}.* TO '${db_user}'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Download, Extract and place nextcloud
echo "Installing Nextcloud"; wget -q https://download.nextcloud.com/server/releases/latest.zip
echo "Unzipping"; unzip latest.zip > /dev/null && rm latest.zip
mv nextcloud $root_dir
chown -R www-data:www-data $root_dir
chmod -R 755 $root_dir

#configure apache, add lines
cat << EOF > /etc/apache2/sites-available/nextcloud.conf
<VirtualHost *:80>
    DocumentRoot $root_dir
    ServerName $servername
    Alias /nextcloud "$root_dir"

    <Directory $root_dir>
       Options +FollowSymlinks
       AllowOverride All
       Require all granted
         <IfModule mod_dav.c>
           Dav off
         </IfModule>
       SetEnv HOME $root_dir
       SetEnv HTTP_HOME $root_dir
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined

</VirtualHost>
EOF

#enable apache virtual host
echo "Disable default site"; a2dissite 000-default.conf > /dev/null
echo "Enable nextcloud.conf"; a2ensite nextcloud.conf > /dev/null
a2enmod rewrite headers env dir mime > /dev/null
phpenmod bcmath gmp imagick intl > /dev/null
systemctl restart apache2 > /dev/null

# Autoconfig for Nextcloud

cat << EOF > $root_dir/config/autoconfig.php
<?php
\$AUTOCONFIG = array(
  "dbtype"        => "mysql",
  "dbname"        => "$db_name",
  "dbuser"        => "$db_user",
  "dbpass"        => "$db_pass",
  "dbhost"        => "localhost",
  "dbtableprefix" => "",
  "adminlogin"    => "$nc_user",
  "adminpass"     => "$nc_pass",
  "directory"     => "$root_dir/data",
);
EOF

echo "Finish installing nexctloud at $servername"
echo "Username: $nc_user"
echo "Password: $nc_pass"
pause "Press [ENTER] to continue..."

# Default Yes to question

read -p "Setup Memcache and fix Default Phone Region Error (Y/n)"
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "Enjoy your new Nextcloud at http://$servername!"
    exit
fi

sed -i.bak  "$ i\ \ 'default_phone_region' => 'US',\n\ \ 'memcache.local' => ""'\\\\OC\\\\Memcache\\\\APCu'""," $root_dir/config/config.php
sed -i 's/\\/\\\\/g' $root_dir/config/config.php

echo "Enjoy your new Nextcloud at http://$servername!"