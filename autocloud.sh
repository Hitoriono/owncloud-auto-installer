#!/bin/sh
clear
echo ".:Configuration:."
echo -n  "What is your domain? "
read my_domain
echo -n "What is your database password? "
read sec_db_pwd
echo -n "What is your admin account password? "
read sec_admin_pwd

echo ".:Prerequisites:."
cd ~
sudo apt update -y
sudo apt upgrade -y
hostnamectl set-hostname $my_domain
hostname -f
echo $sec_admin_pwd > /etc/.sec_admin_pwd.txt
echo $sec_db_pwd > /etc/.sec_db_pwd.txt
FILE="/usr/local/bin/occ"
cat <<EOM >$FILE

#! /bin/bash
echo ".:Setup:."
cd /var/www/owncloud
sudo -E -u www-data /usr/bin/php /var/www/owncloud/occ "\$@"
EOM
chmod +x $FILE
sudo apt update -y 
sudo apt upgrade -y 
sudo apt install -y  apache2 libapache2-mod-php mariadb-server openssl redis-server wget php-imagick php-common php-curl php-gd php-imap php-intl php-json php-mbstring php-mysql php-ssh2 php-xml php-zip php-apcu php-redis php-ldap php-opcache
sudo apt install -y libsmbclient-dev php-dev php-pear
sudo a2dismod mpm_event
sudo systemctl restart apache2
sudo a2enmod mpm_prefork
sudo systemctl restart apache2
sudo apt update -y
sudo apt upgrade -y
pecl channel-update pecl.php.net
mkdir -p /tmp/pear/cache
pecl install smbclient-stable
echo "extension=smbclient.so" > /etc/php/7.4/mods-available/smbclient.ini
phpenmod smbclient
systemctl restart apache2
sudo apt update -y
sudo apt upgrade -y
sudo apt install -y unzip bzip2 rsync curl jq inetutils-ping ldap-utils smbclient
FILE="/etc/apache2/sites-available/owncloud.conf"
cat <<EOM >$FILE
<VirtualHost *:80>
#ServerName $my_domain
DirectoryIndex index.php index.html
DocumentRoot /var/www/owncloud
<Directory /var/www/owncloud>
  Options +FollowSymlinks -Indexes
  AllowOverride All
  Require all granted

 <IfModule mod_dav.c>
  Dav off
 </IfModule>

 SetEnv HOME /var/www/owncloud
 SetEnv HTTP_HOME /var/www/owncloud
</Directory>
</VirtualHost>
EOM
a2dissite 000-default
a2ensite owncloud.conf
sed -i "/\[mysqld\]/atransaction-isolation = READ-COMMITTED\nperformance_schema = on" /etc/mysql/mariadb.conf.d/50-server.cnf
systemctl start mariadb
mysql -u root -e "CREATE DATABASE owncloud; \
GRANT ALL PRIVILEGES ON owncloud.* \
  TO owncloud@localhost \
  IDENTIFIED BY '${sec_db_pwd}'";
a2enmod dir env headers mime rewrite setenvif
systemctl restart apache2
cd ~
cd /var/www/
wget https://download.owncloud.org/community/owncloud-complete-latest.tar.bz2 && \
tar -xjf owncloud-complete-latest.tar.bz2 && \
chown -R www-data. owncloud
occ maintenance:install \
    --database "mysql" \
    --database-name "owncloud" \
    --database-user "owncloud" \
    --database-pass ${sec_db_pwd} \
    --data-dir "/var/www/owncloud/data" \
    --admin-user "admin" \
    --admin-pass ${sec_admin_pwd}
my_ip=$(hostname -I|cut -f1 -d ' ')
occ config:system:set trusted_domains 1 --value="$my_ip"
occ config:system:set trusted_domains 2 --value="$my_domain"
occ background:cron
echo "*/15  *  *  *  * /var/www/owncloud/occ system:cron" \
  | sudo -u www-data -g crontab tee -a \
  /var/spool/cron/crontabs/www-data
echo "0  2  *  *  * /var/www/owncloud/occ dav:cleanup-chunks" \
  | sudo -u www-data -g crontab tee -a \
  /var/spool/cron/crontabs/www-data
echo "1 */6 * * * /var/www/owncloud/occ user:sync \
  'OCA\User_LDAP\User_Proxy' -m disable -vvv >> \
  /var/log/ldap-sync/user-sync.log 2>&1" \
  | sudo -u www-data -g crontab tee -a \
  /var/spool/cron/crontabs/www-data
mkdir -p /var/log/ldap-sync
touch /var/log/ldap-sync/user-sync.log
chown www-data. /var/log/ldap-sync/user-sync.log
occ config:system:set \
   memcache.local \
   --value '\OC\Memcache\APCu'
occ config:system:set \
   memcache.locking \
   --value '\OC\Memcache\Redis'
occ config:system:set \
   redis \
   --value '{"host": "127.0.0.1", "port": "6379"}' \
   --type json
FILE="/etc/logrotate.d/owncloud"
sudo cat <<EOM >$FILE
/var/www/owncloud/data/owncloud.log {
  size 10M
  rotate 12
  copytruncate
  missingok
  compress
  compresscmd /bin/gzip
}
EOM
cd /var/www/
chown -R www-data. owncloud
clear
echo ".:Information:."
occ -V
echo "Domain: " $my_domain
echo "Admin Username: Admin"
echo "Admin Password: " $sec_admin_pwd
echo "Admin password is stored at /etc/.sec_admin_pwd.txt"
echo "Database Name: owncloud"
echo "Database Username: owncloud"
echo "Database Password: " $sec_db_pwd
echo "Script made by Hitoriono"
