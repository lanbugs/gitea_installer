#!/bin/bash

# -----------------------------------------------------------------------------
# GITEA Installer with Nginx, MariaDB, UFW & Letsencrypt
# Version 0.1
# Written by Maximilian Thoma 2020
# Visit https://lanbugs.de for further informations.
# -----------------------------------------------------------------------------
# gitea_installer.sh is free software;  you can redistribute it and/or
# modify it under the  terms of the  GNU General Public License  as
# published by the Free Software Foundation in version 2.
# gitea_installer.sh is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; with-out even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the  GNU General Public License for more details.
# You should have  received  a copy of the  GNU  General Public
# License along with GNU Make; see the file  COPYING.  If  not,  write
# to the Free Software Foundation, Inc., 51 Franklin St,  Fifth Floor,
# Boston, MA 02110-1301 USA.
#

LETSENCRYPT='false'
UFW='false'

#GETOPTS
while getopts f:e:i:p:r:lu flag
do
    case "${flag}" in
      f) FQDN=${OPTARG};;
      e) EMAIL=${OPTARG};;
      i) IP=${OPTARG};;
      p) PASSWORD=${OPTARG};;
      r) SQLROOT=${OPTARG};;
      l) LETSENCRYPT='true';;
      u) UFW='true';;
    esac
done

if [ -z "$FQDN" ] || [ -z "$EMAIL" ] || [ -z "$IP" ] || [ -z "$PASSWORD" ] || [ -z "$SQLROOT" ]; then
echo "One of the options is missing:"
echo "-f FQDN - Systemname of GITEA system"
echo "-e EMAIL - E-Mail for letsencrypt"
echo "-i IP - IPv4 address of this system"
echo "-p PASSWORD - Used for GITEA DB"
echo "-r SQLROOT - MySQL ROOT password"
echo "-l LETSENCRYPT - Use letsencrypt"
echo "-u UFW - Use UFW"
exit
fi

# Check if curl is installed
if [ ! -x /usr/bin/curl ] ; then
CURL_NOT_EXIST=1
apt install -y curl
else
CURL_NOT_EXIST=0
fi

# Install packages
apt update
apt install -y nginx mariadb-server git ssl-cert

# Get last version
VER=$(curl --silent "https://api.github.com/repos/go-gitea/gitea/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | sed 's|[v,]||g' )                                               

# Create git user
adduser --system --group --disabled-password --shell /bin/bash --home /home/git --gecos 'Git Version Control' git

# Download gitea
# Check if architecure is i386 and download Gitea
if [ -n "$(uname -a | grep i386)" ]; then
    sudo curl -fsSL -o "/tmp/gitea" "https://dl.gitea.io/gitea/$VER/gitea-$VER-linux-386"
fi

# Check if architecure is x86 and download Gitea
if [ -n "$(uname -a | grep x86_64)" ]; then
  sudo curl -fsSL -o "/tmp/gitea" "https://dl.gitea.io/gitea/$VER/gitea-$VER-linux-amd64"
fi

# Check if architecure is ARMv6 and download Gitea
if [ -n "$(uname -a | grep armv6l)" ]; then
  sudo curl -fsSL -o "/tmp/gitea" "https://dl.gitea.io/gitea/$VER/gitea-$VER-linux-arm-6"
fi

# Check if architecure is ARMv7 and download Gitea
if [ -n "$(uname -a | grep armv7l)" ]; then
  sudo curl -fsSL -o "/tmp/gitea" "https://dl.gitea.io/gitea/$VER/gitea-$VER-linux-arm-7"
fi

# Move binary
mv /tmp/gitea /usr/local/bin
chmod +x /usr/local/bin/gitea

# Create folders
mkdir -p /var/lib/gitea/{custom,data,indexers,public,log}
chown git: /var/lib/gitea/{data,indexers,log}
chmod 750 /var/lib/gitea/{data,indexers,log}
mkdir /etc/gitea
chown root:git /etc/gitea
chmod 770 /etc/gitea

# Get systemd file
curl -fsSL -o /etc/systemd/system/gitea.service https://raw.githubusercontent.com/go-gitea/gitea/master/contrib/systemd/gitea.service

# Enable mariadb requirement in systemd gitea.service script
perl -pi -w -e 's/#Requires=mariadb.service/Requires=mariadb.service/g;' /etc/systemd/system/gitea.service

# Reload & Enable gitea daemon
systemctl daemon-reload
systemctl enable --now gitea

# Create db in mariadb
mysql -u root -Bse "CREATE DATABASE giteadb;"
mysql -u root -Bse "CREATE USER 'gitea'@'localhost' IDENTIFIED BY '$PASSWORD';"
mysql -u root -Bse "GRANT ALL ON giteadb.* TO 'gitea'@'localhost' IDENTIFIED BY '$PASSWORD' WITH GRANT OPTION;"
mysql -u root -Bse "ALTER DATABASE giteadb CHARACTER SET = utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -u root -Bse "FLUSH PRIVILEGES;"

# Save original config
cp /etc/mysql/mariadb.conf.d/50-server.cnf /etc/mysql/mariadb.conf.d/50-server.org

cat >> /etc/mysql/mariadb.conf.d/50-server.cnf << XYZ
#
# These groups are read by MariaDB server.
# Use it for options that only the server (but not clients) should see
#
# See the examples of server my.cnf files in /usr/share/mysql

# this is read by the standalone daemon and embedded servers
[server]

# this is only for the mysqld standalone daemon
[mysqld]

#
# * Basic Settings
#
user                    = mysql
pid-file                = /run/mysqld/mysqld.pid
socket                  = /run/mysqld/mysqld.sock
#port                   = 3306
basedir                 = /usr
datadir                 = /var/lib/mysql
tmpdir                  = /tmp
lc-messages-dir         = /usr/share/mysql
#skip-external-locking

# Instead of skip-networking the default is now to listen only on
# localhost which is more compatible and is not less secure.
bind-address            = 127.0.0.1

#
# * Fine Tuning
#
#key_buffer_size        = 16M
#max_allowed_packet     = 16M
#thread_stack           = 192K
#thread_cache_size      = 8
# This replaces the startup script and checks MyISAM tables if needed
# the first time they are touched
#myisam_recover_options = BACKUP
#max_connections        = 100
#table_cache            = 64
#thread_concurrency     = 10

#
# * Query Cache Configuration
#
#query_cache_limit      = 1M
query_cache_size        = 16M

#
# * Logging and Replication
#
# Both location gets rotated by the cronjob.
# Be aware that this log type is a performance killer.
# As of 5.1 you can enable the log at runtime!
#general_log_file       = /var/log/mysql/mysql.log
#general_log            = 1
#
# Error log - should be very few entries.
#
log_error = /var/log/mysql/error.log
#
# Enable the slow query log to see queries with especially long duration
#slow_query_log_file    = /var/log/mysql/mariadb-slow.log
#long_query_time        = 10
#log_slow_rate_limit    = 1000
#log_slow_verbosity     = query_plan
#log-queries-not-using-indexes
#
# The following can be used as easy to replay backup logs or for replication.
# note: if you are setting up a replication slave, see README.Debian about
#       other settings you may need to change.
#server-id              = 1
#log_bin                = /var/log/mysql/mysql-bin.log
expire_logs_days        = 10
#max_binlog_size        = 100M
#binlog_do_db           = include_database_name
#binlog_ignore_db       = exclude_database_name

#
# * Security Features
#
# Read the manual, too, if you want chroot!
#chroot = /var/lib/mysql/
#
# For generating SSL certificates you can use for example the GUI tool "tinyca".
#
#ssl-ca = /etc/mysql/cacert.pem
#ssl-cert = /etc/mysql/server-cert.pem
#ssl-key = /etc/mysql/server-key.pem
#
# Accept only connections using the latest and most secure TLS protocol version.
# ..when MariaDB is compiled with OpenSSL:
#ssl-cipher = TLSv1.2
# ..when MariaDB is compiled with YaSSL (default in Debian):
#ssl = on

#
# * Character sets
#
# MySQL/MariaDB default is Latin1, but in Debian we rather default to the full
# utf8 4-byte character set. See also client.cnf
#
character-set-server  = utf8mb4
collation-server      = utf8mb4_general_ci

#
# * InnoDB
#
# InnoDB is enabled by default with a 10MB datafile in /var/lib/mysql/.
# Read the manual for more InnoDB related options. There are many!

innodb_file_format = Barracuda
innodb_large_prefix = 1
innodb_default_row_format = dynamic

#
# * Unix socket authentication plugin is built-in since 10.0.22-6
#
# Needed so the root database user can authenticate without a password but
# only when running as the unix root user.
#
# Also available for other users if required.
# See https://mariadb.com/kb/en/unix_socket-authentication-plugin/

# this is only for embedded server
[embedded]

# This group is only read by MariaDB servers, not by MySQL.
# If you use the same .cnf file for MySQL and MariaDB,
# you can put MariaDB-only options here
[mariadb]

# This group is only read by MariaDB-10.3 servers.
# If you use the same .cnf file for MariaDB of different versions,
# use this group for options that older servers don't understand
[mariadb-10.3]
XYZ

#Restart mariadb
systemctl restart mariadb

#Secure mariadb
mysql -u root -Bse "UPDATE mysql.user SET Password=PASSWORD('$SQLROOT') WHERE User='root'"
mysql -u root -p"$SQLROOT" -Bse "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')"
mysql -u root -p"$SQLROOT" -Bse "DELETE FROM mysql.user WHERE User=''"
mysql -u root -p"$SQLROOT" -Bse "DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%'"
mysql -u root -p"$SQLROOT" -Bse "FLUSH PRIVILEGES"

# Create nginx config
cat >> /etc/nginx/sites-enabled/$FQDN << XYZ
server {
    listen 80;
    server_name $FQDN;

    return 301 https://$FQDN\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $FQDN;

    proxy_read_timeout 720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;

    client_max_body_size 50m;

    # Proxy headers
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Real-IP \$remote_addr;

    # SSL parameters
    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;

    # log files
    access_log /var/log/nginx/$FQDN.access.log;
    error_log /var/log/nginx/$FQDN.error.log;

    # Handle / requests
    location / {
       proxy_redirect off;
       proxy_pass http://127.0.0.1:3000;
    }
}
XYZ

# Restart nginx
service nginx restart

#Aquire certificate letsencrypt
if [ $LETSENCRYPT=='true' ] ; then
apt install -y certbot python3-certbot-nginx
certbot --nginx -d $FQDN --non-interactive --agree-tos -m $EMAIL
fi

# Install if ufw true
if [ $UFW=='true' ] ; then

# UFW installed?
if [ ! -x /usr/sbin/ufw ] ; then
apt install -y ufw
fi

# UFW policy
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw logging on
ufw --force enable

fi


# Cleanup packages
if [[ $CURL_NOT_EXIST == 1 ]]; then
apt remove -y curl
fi

# Final message
echo "--------------------------------------------------------------------------------------"
echo " GITEA $VER installed on system $FQDN"
echo "--------------------------------------------------------------------------------------"
echo " Mysql database        : giteadb "
echo " Mysql user            : gitea "
echo " Mysql password        : $PASSWORD "
echo " Mysql character set   : utf8mb4"
echo "--------------------------------------------------------------------------------------"
echo " Mysql root user       : root"
echo " Mysql root password   : $SQLROOT"
echo "--------------------------------------------------------------------------------------"
echo " System is accessable via https://$FQDN"
echo "--------------------------------------------------------------------------------------"
echo " >>> You must finish the initial setup <<< "
echo "--------------------------------------------------------------------------------------"
echo " Site Title            : Enter your organization name."
echo " Repository Root Path  : Leave the default /home/git/gitea-repositories."
echo " Git LFS Root Path     : Leave the default /var/lib/gitea/data/lfs."
echo " Run As Username       : git"
echo " SSH Server Domain     : Use $FQDN"
echo " SSH Port              : 22, change it if SSH is listening on other Port"
echo " Gitea HTTP Listen Port: 3000"
echo " Gitea Base URL        : Use https://$FQDN/ "
echo " Log Path              : Leave the default /var/lib/gitea/log"
echo "--------------------------------------------------------------------------------------"
if [ $UFW=='true' ] ; then
echo " Following firewall rules applied:"
ufw status numbered
echo "--------------------------------------------------------------------------------------"
fi
