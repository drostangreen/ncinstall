#!/bin/bash

. /etc/os-release

# PHP Version
version=8.1

# Webserver Vars
webserver=nginx
timezone=America/Chicago
webserver_log_dir=/var/log/nginx
servername=nextcloud.example.com
root_dir=/var/www/html/nextcloud
key_path=/etc/pki/tls/private
cert_path=/etc/pki/tls/certs
ssl_days=3650

# MariaDB/MySQL Vars
db_name=nextclouddb
db_user=dbadmin
db_pass=password

# Nextcloud
nc_user=ncadmin
nc_pass=password

set -e

Help(){
    echo "Setups up Nextcloud"
    echo
    echo "Default options: Installs with nginx and ssl validity days of 3650"
    echo "options:"
    echo "-a    sets httpd as the web server"
    echo "-n    sets nginx as the web server"
    echo "-d    create Diffie-Hellman Parameter key *WARNING* this can take a long time"
    echo "-s    set the days for ssl validity"
    echo "-h    show help"
    echo
    echo '######################################################'
    echo "long options:"
    echo "--apache | --httpd  sets httpd as the web server"
    echo "--nginx               sets nginx as the web server"
    echo "--dhparam-file        create Diffie-Hellman Parameter key"
    echo "--ssl-valid-days      set the days for ssl validity"
    echo "--help                show help"
}

Error(){
    echo "Error at line $1"
}
trap 'Error $LINENO' ERR

function pause(){
    read -p "$*"
}

php_config(){
    # configure php ini file, set normal params then setup for memcache

    echo "Backup php.ini file then modify"; sed -i.bak "s|^memory_limit = .*|memory_limit = 512M|;s|^upload_max_filesize = .*|upload_max_filesize = 500M|;s|^post_max_size = .*|post_max_size = 500M|;s|^max_execution_time = .*|max_execution_time = 300|;s|\;date.timezone =|date.timezone = $timezone|" /etc/php.ini
    sed -i "s/^;opcache\.enable=.*/opcache\.enable=1/;s/^;opcache\.interned_strings_bugger=.*/opcache\.interned_strings_buffer=8/;s/^;opcache\.max_accelerated_files=.*/opcache\.max_accelerated_files=10000/;s/^;opcache\.memory_consumption=.*/opcache.memory_consumption=128/;s/^;opcache\.save_comments=.*/opcache.save_comments=1/;s/^;opcache\.revalidate_freq=.*/opcache.revalidate_freq=1/" /etc/php.d/10-opcache.ini
}

redhat_repo(){
    echo "Add Remis repo for PHP"; dnf install -y https://rpms.remirepo.net/enterprise/remi-release-$(lsb_release -sr | cut -d. -f1).rpm > /dev/null 2>&1
}

fedora_repo(){
    echo "Add Remis repo for PHP"; dnf -y install http://rpms.remirepo.net/fedora/remi-release-$VERSION_ID.rpm > /dev/null 2>&1
}

mysql_setup(){
mysql -sfu root <<EOS
-- set root password
UPDATE mysql.user SET Password=PASSWORD('$db_root_pass') WHERE User='root';
-- delete anonymous users
DELETE FROM mysql.user WHERE User='';
-- delete remote root capabilities
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
-- drop database 'test'
DROP DATABASE IF EXISTS test;
-- also make sure there are lingering permissions to it
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
-- make changes immediately
FLUSH PRIVILEGES;
EOS


# Create a database with a user, grant privileges
mysql --user=root --password=password <<EOF
CREATE DATABASE ${db_name};
CREATE USER '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';
GRANT ALL ON ${db_name}.* TO '${db_user}'@'localhost';
FLUSH PRIVILEGES;
EOF
}

ssl_create(){
    # Generate Self Signed Certs, Uncomment to create a Diffie Helman
    openssl req -newkey rsa:4096 -x509 -sha256 -days $ssl_days -nodes -out $cert_path/nextcloudcrt.pem -keyout $key_path/nextcloud.key -subj "/C=US/ST=/L=/O=/OU=/CN=$servername" > /dev/null
    if [[ $dhparam == true ]]; then
        openssl dhparam -out $cert_path/dhparam.pem 4096
    else
        true
    fi
}

nc_autoconfig(){
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
}

optional_optimization(){
    sed -i.bak  "$ i\ \ 'default_phone_region' => 'US',\n\ \ 'memcache.local' => ""'\\\\OC\\\\Memcache\\\\APCu'""," $root_dir/config/config.php
    sed -i 's/\\/\\\\/g' $root_dir/config/config.php

    echo "Enjoy your new Nextcloud at https://$servername!"
}

selinux_config(){
    semanage fcontext -a -t httpd_sys_rw_content_t "$root_dir/config(/.*)?"
    semanage fcontext -a -t httpd_sys_rw_content_t "$root_dir/apps(/.*)?"
    semanage fcontext -a -t httpd_sys_rw_content_t "$root_dir/.htaccess"
    semanage fcontext -a -t httpd_sys_rw_content_t "$root_dir/.user.ini"
    semanage fcontext -a -t httpd_sys_rw_content_t "$root_dir/3rdparty/aws/aws-sdk-php/src/data/logs(/.*)?"

    restorecon -R "$root_dir"

    setsebool -P httpd_can_network_connect on
    setsebool -P httpd_execmem 1
}

nextcloud_install(){
    echo "Installing Nextcloud"; wget -q https://download.nextcloud.com/server/releases/latest.zip
    echo "Unzipping"; unzip latest.zip > /dev/null && rm latest.zip
    mv nextcloud $root_dir
    mkdir $root_dir/data
    chown -R $web_user:$web_user $root_dir
    chmod -R 755 $root_dir
}

nginx_setup(){
php_path=/etc/php-fpm.d
web_user=nginx
root_dir=/usr/share/nginx/html/nextcloud
nextcloud_install

echo "install php-fpm"; dnf install -y php-fpm > /dev/null 2>&1

cat << EOF > /etc/nginx/conf.d/nextcloud.conf
upstream php-handler {
    server unix:/run/php-fpm/www.sock;
    #server 127.0.0.1:9000;
}
map \$arg_v \$asset_immutable {
    "" "";
    default "immutable";
}
server {
    listen 80;
    listen [::]:80;
    server_name $servername ;
    return 301 https://\$server_name\$request_uri;
}
server {
    listen 443      ssl http2;
    listen [::]:443 ssl http2;
    server_name $servername ;
    root $root_dir;
    ssl_certificate     $cert_path/nextcloudcrt.pem ;
    ssl_certificate_key $key_path/nextcloud.key ;
    #ssl_dhparam $cert_path/dhparam.pem ;
    client_max_body_size 512M;
    client_body_timeout 300s;
    fastcgi_buffers 64 4K;
    gzip on;
    gzip_vary on;
    gzip_comp_level 4;
    gzip_min_length 256;
    gzip_proxied expired no-cache no-store private no_last_modified no_etag auth;
    gzip_types application/atom+xml application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/wasm application/x-font-ttf application/x-web-app-manifest+json application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy;
    client_body_buffer_size 512k;
    add_header Strict-Transport-Security            "max-age=63072000"  always;
    add_header Referrer-Policy                      "no-referrer"       always;
    add_header X-Content-Type-Options               "nosniff"           always;
    add_header X-Download-Options                   "noopen"            always;
    add_header X-Frame-Options                      "SAMEORIGIN"        always;
    add_header X-Permitted-Cross-Domain-Policies    "none"              always;
    add_header X-Robots-Tag                         "none"              always;
    add_header X-XSS-Protection                     "1; mode=block"     always;
    fastcgi_hide_header X-Powered-By;
    index index.php index.html /index.php\$request_uri;
    location = / {
        if ( \$http_user_agent ~ ^DavClnt ) {
            return 302 /remote.php/webdav/\$is_args\$args;
        }
    }
    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }
    location ^~ /.well-known {
        location = /.well-known/carddav { return 301 /remote.php/dav/; }
        location = /.well-known/caldav  { return 301 /remote.php/dav/; }
        location /.well-known/acme-challenge    { try_files \$uri \$uri/ =404; }
        location /.well-known/pki-validation    { try_files \$uri \$uri/ =404; }
        return 301 /index.php\$request_uri;
    }
    location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)(?:$|/)  { return 404; }
    location ~ ^/(?:\.|autotest|occ|issue|indie|db_|console)                { return 404; }
    location ~ \.php(?:$|/) {
        # Required for legacy support
        rewrite ^/(?!index|remote|public|cron|core\/ajax\/update|status|ocs\/v[12]|updater\/.+|oc[ms]-provider\/.+|.+\/richdocumentscode\/proxy) /index.php$request_uri;
        fastcgi_split_path_info ^(.+?\.php)(/.*)$;
        set \$path_info \$fastcgi_path_info;
        try_files \$fastcgi_script_name =404;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$path_info;
        fastcgi_param HTTPS on;
        fastcgi_param modHeadersAvailable true;
        fastcgi_param front_controller_active true;
        fastcgi_pass php-handler;
        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;
        fastcgi_max_temp_file_size 0;
    }
    location ~ \.(?:css|js|svg|gif|png|jpg|ico|wasm|tflite|map)$ {
        try_files \$uri /index.php\$request_uri;
        add_header Cache-Control "public, max-age=15778463, \$asset_immutable";
        access_log off;     # Optional: Don't log access to assets
        location ~ \.wasm$ {
            default_type application/wasm;
        }
    }
    location ~ \.woff2?$ {
        try_files \$uri /index.php\$request_uri;
        expires 7d;
        access_log off;
    }
    location /remote {
        return 301 /remote.php\$request_uri;
    }
    location / {
        try_files \$uri \$uri/ /index.php\$request_uri;
    }
}
EOF

if [ -f $cert_path/dhparam.pem ];
then
    sed -i '/ssl_dhparam.*/s/#//g' /etc/nginx/conf.d/nextcloud.conf
fi 

php_config
sed -i.bak '/env\[/s/^;//g' $php_path/www.conf
sed -i 's/pm\.max_children =.*/pm\.max_children = 120/;s/pm\.start_servers =.*/pm\.start_servers = 12/;s/pm\.min_spare_servers =.*/pm\.min_spare_servers = 6/;s/pm\.max_spare_servers =.*/pm\.max_spare_servers = 18/' $php_path/www.conf
sed -i "s/user =.*/user = $web_user/;s/group =.*/group = $web_user/" $php_path/www.conf

chgrp -R nginx /var/lib/php/{opcache,session,wsdlcache}

semanage fcontext -a -t httpd_sys_rw_content_t "$root_dir/data(/.*)?"
selinux_config

chcon -t httpd_sys_rw_content_t $root_dir -R
setfacl -R -m u:nginx:rwx /var/lib/php/opcache/
setfacl -R -m u:nginx:rwx /var/lib/php/session/
setfacl -R -m u:nginx:rwx /var/lib/php/wsdlcache

#enable nginx virtual host
systemctl enable --now php-fpm > /dev/null
systemctl restart nginx php-fpm > /dev/null
}

httpd_setup(){
php_path=/etc/php/$version/httpd
web_user=apache
# dnf install -y libhttpd-mod-php$version
dnf install -y mod_ssl
nextcloud_install

cat << EOF > /etc/httpd/conf.d/nextcloud.conf
<VirtualHost *:80>
    DocumentRoot $root_dir
    ServerName $servername

    Redirect permanent / https://$servername

</VirtualHost>

<VirtualHost *:443>
    ServerName $servername
    DocumentRoot $root_dir


    SSLEngine on
    SSLCertificateFile $cert_path/nextcloudcrt.pem
    SSLCertificateKeyFile $key_path/nextcloud.key

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

    <IfModule mod_headers.c>
        Header always set Strict-Transport-Security "max-age=15552000; includeSubDomains"
    </IfModule>

    ErrorLog ${webserver_log_dir}/error.log
    CustomLog ${webserver_log_dir}/access.log combined
</VirtualHost>
EOF

php_config
selinux_config
systemctl restart httpd php-fpm > /dev/null
}

while [ "$1" != "" ]; do
    case $1 in
    -a | --apache | --httpd)
        webserver=httpd
        webserver_log_dir=/var/log/httpd
        ;;
    -n | --nginx)
        webserver=nginx
        ;;

    -d | --dhparam-file)
        dhparam=true
        ;;

    -h | --help)
        Help # run Help function
        exit 0
        ;;

    -s | --ssl-valid-days)
        shift
        ssl_days=$1
        ;;
    
    *)
        echo Invalid option
        Help
        exit 1
        ;;
    esac
    shift # remove the current value for `$1` and use the next
done

################## Begining of Script ##################

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"; Help
  exit 1
fi

echo "Installing Prereqs for PHP"; dnf install -y redhat-lsb-core epel-release yum-utils unzip curl wget bash-completion policycoreutils-python-utils mlocate bzip2 > /dev/null 2>&1

if [[ $ID == "rocky" ]] || [[ $ID == "centos" ]] || [[ $ID == "rhel" ]] || [[ $ID == "almalinux" ]]; then
  redhat_repo
elif [[ $ID == "fedora" ]]; then
    fedora_repo
fi

echo "Setting PHP to version $version"; dnf module enable php:remi-$version -y > /dev/null 2>&1
echo "Installing Base"; dnf install -y $webserver mariadb-server wget unzip php php-{bcmath,bz2,intl,gd,mbstring,mysql,zip,xml,curl,cli,mbstring,imagick,gmp,apcu,posix}  > /dev/null 2>&1


echo "Enabling Services"
systemctl enable --now $webserver mariadb > /dev/null 2>&1

# Create a database with a user, grant privileges
mysql_setup

# Generate Self Signed Certs, Uncomment to create a Diffie Helman
ssl_create

$webserver\_setup

# Autoconfig for Nextcloud
nc_autoconfig

echo "Finish installing nexctloud at https://$servername"
echo "You will either select to install recommended apps or skip for most minimal setup"
echo "First login is automatic"
echo "Username: $nc_user"
echo "Password: $nc_pass"
pause "Press [ENTER] to continue..."

# Default Yes to question

read -p "Setup Memcache and fix Default Phone Region Error (Y/n)"
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "Enjoy your new Nextcloud at https://$servername!"
    exit
else
    optional_optimization
fi

echo "Enjoy your new Nextcloud at https://$servername!"