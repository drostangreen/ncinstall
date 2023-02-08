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
db_user=ncadmin
db_pass=password

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

# configure php ini file, set memory_limit, upload_max_filesize, post_max_size, max_execution_time and date.timezone

echo "Backup php.ini file then modify"; sed -i.bak "s|^memory_limit = .*|memory_limit = 512M|;s|^upload_max_filesize = .*|upload_max_filesize = 500M|;s|^post_max_size = .*|post_max_size = 500M|;s|^max_execution_time = .*|max_execution_time = 300|;s|\;date.timezone =|date.timezone = $timezone|" /etc/php/$version/apache2/php.ini

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
systemctl restart apache2 > /dev/null

echo "Finish installing nexctloud at $servername or $(hostname -I)"
