#!/bin/bash
yum install net-tools vim wget -y
##################################################
#					         #
#                install graphite and statsd     #
#						 #
##################################################

# Constants
GRAPHITE_ROOT='/opt/graphite'
GRAPHITE_CONF_DIR='/opt/graphite/conf'
GRAPHITE_WEBAPP_CONF='/opt/graphite/webapp/graphite/local_settings.py'
GRAPHITE_VHOST_EXAMPLE='/opt/graphite/examples/example-graphite-vhost.conf'
FIREWALL='firewall-cmd --permanent'


echo -e "\nINSTALLING graphite-web + carbon-cache + apache2 \n"
echo -e "\ninstall httpd net-snmp perl pycairo mod_wsgi python-devel git gcc-c++ \n"
########################## Firewalld ####################################
$FIREWALL --add-port=8080/tcp
$FIREWALL --add-port=2003-2004/tcp
$FIREWALL --add-port=5432/tcp 
$FIREWALL --add-port=7002/tcp
firewall-cmd --reload
#systemctl stop firewalld
#systemctl disable firewalld
#######################################################################
#****************** SELinux ******************************************#
# sed -i "s:SELINUX=enforcing:SELINUX=disabled:g" /etc/selinux/config
#List all port defitions
#       # semanage port -l
#       Allow Apache to listen on tcp port 81
#       # semanage port -a -t http_port_t -p tcp 81
#       Allow sshd to listen on tcp port 8991
#       # semanage port -a -t ssh_port_t -p tcp 8991
semanage port -a -t http_port_t -p tcp 8080

yum install -y httpd net-snmp perl pycairo mod_wsgi python-devel git gcc-c++

echo -e "\n install epel-release \n"

yum install -y epel-release

echo -e "\n update \n"

yum -y update 

echo -e "\n install python-pip node and npm \n"

yum install -y python-pip node npm

echo -e "\n install django, Twisted, django-tagging, whisper, graphite-web and carbon \n"
######################################################################################
####  To know Django Version
####  python -c "import django; print(django.get_version())"             or
####  python ./manage.py --version
####  django-admin.py version
####  Use  'pip freeze' to know everyting 
#######################################################################################
pip install 'django==1.8'  #must use django 1.8 version 
pip install 'Twisted'
pip install 'django-tagging==0.3.6'
pip install whisper
pip install graphite-web
pip install carbon

echo -e "\n install collectd \n"

yum install -y collectd collectd-snmp

echo -e "\n clone git of statsd \n"

git clone https://github.com/etsy/statsd.git /usr/local/src/statsd/

echo -e "\n copy configuration files \n"

cp $GRAPHITE_VHOST_EXAMPLE /etc/httpd/conf.d/graphite.conf
cp $GRAPHITE_CONF_DIR/dashboard.conf.example $GRAPHITE_CONF_DIR/dashboard.conf
cp $GRAPHITE_CONF_DIR/storage-schemas.conf.example $GRAPHITE_CONF_DIR/storage-schemas.conf
cp $GRAPHITE_CONF_DIR/relay-rules.conf.example $GRAPHITE_CONF_DIR/relay-rules.conf
cp $GRAPHITE_CONF_DIR/storage-aggregation.conf.example $GRAPHITE_CONF_DIR/storage-aggregation.conf
cp $GRAPHITE_CONF_DIR/graphite.wsgi.example $GRAPHITE_CONF_DIR/graphite.wsgi
cp $GRAPHITE_CONF_DIR/graphTemplates.conf.example $GRAPHITE_CONF_DIR/graphTemplates.conf
cp $GRAPHITE_CONF_DIR/carbon.conf.example $GRAPHITE_CONF_DIR/carbon.conf
# Copy configuration templates
cp $GRAPHITE_WEBAPP_CONF".example" $GRAPHITE_WEBAPP_CONF

chown -R apache:apache $GRAPHITE_ROOT/storage/
chmod 777 $GRAPHITE_CONF_DIR/storage-schemas.conf

SCHEMA="

[stats]
pattern = ^stats.*
retentions = 10s:6h,1min:6d,10min:1800d

[default]
pattern = .*
retentions = 10s:4h, 1m:3d, 5m:8d, 15m:32d, 1h:1y

"
echo "$SCHEMA">>$GRAPHITE_CONF_DIR/storage-schemas.conf


AGGREGATE="

[count]
pattern = \.count$
xFilesFactor = 0
aggregationMethod = sum

[count_legacy]
pattern = ^stats_counts.*
xFilesFactor = 0
aggregationMethod = sum

"
echo "$AGGREGATE">>$GRAPHITE_CONF_DIR/storage-aggregation.conf


cat >> $GRAPHITE_ROOT/webapp/graphite/local_settings.py<<EOF
TIME_ZONE = 'Asia/Dhaka'
SECRET_KEY = '#UZ$!wNKYGBv'
USE_REMOTE_USER_AUTHENTICATION = True
DATABASES = {
	'default': {
  		'NAME': 'graphite',
		'ENGINE': 'django.db.backends.postgresql_psycopg2',
		'USER': 'graphite',
		'PASSWORD': 'password',
		'HOST': '127.0.0.1',
		'PORT': ''
    }
}
EOF


echo -e "\n install epel-release \n"

yum install -y postgresql-server 
yum install -y postgresql-contrib 
yum install -y python-psycopg2

################################################################################
######
###### su - postgres -c "initdb --locale en_US.UTF-8 -D '/var/lib/pgsql/data'"
######
################################################################################
su - postgres -c "initdb --locale en_US.UTF-8 -D '/var/lib/pgsql/data'"
#sudo postgresql-setup initdb
#sudo systemctl start postgresql
#sudo systemctl enable postgresql

sudo systemctl start postgresql
sudo systemctl enable postgresql

sed -i "s:host    all             all             127.0.0.1/32            ident:host    all             all             127.0.0.1/32            md5:g" /var/lib/pgsql/data/pg_hba.conf
db_create="
CREATE USER graphite WITH PASSWORD 'password';
CREATE DATABASE graphite WITH OWNER graphite;
GRANT ALL ON DATABASE graphite to graphite;
\q"
sudo -u postgres psql -e <<<$db_create
python $GRAPHITE_ROOT/webapp/graphite/manage.py migrate auth # Auth_User to DB Migration 
python $GRAPHITE_ROOT/webapp/graphite/manage.py syncdb --noinput
#python $GRAPHITE_ROOT/webapp/graphite/manage.py migrate --noinput
###################################################################
#####   syncdb command is deprecated in django 1.7. Use the python manage.py migrate instead.
#####   python manage.py migrate
#####
###################################################################
python $GRAPHITE_ROOT/webapp/graphite/manage.py createsuperuser --username="root" --email="example@example.com" --noinput
systemctl enable httpd
systemctl start httpd
$GRAPHITE_ROOT/bin/carbon-cache.py start
cd /usr/local/src/statsd
touch local.js
# add graphite host server ip given as localhost 
add_string='{
  graphitePort: 2003
, graphiteHost: "127.0.0.1"
, port: 8125
, backends: [ "./backends/graphite" ]
, graphite: { legacyNamespace: false }
}'

echo "$add_string">>/usr/local/src/statsd/local.js
node stats.js local.js &

echo -e "\n installed ok \n"


$GRAPHITE_ROOT/bin/run-graphite-devel-server.py $GRAPHITE_ROOT/ &

echo -e "congratulations, u have successully install statsd with graphite . "
cd
echo "$GRAPHITE_ROOT/bin/carbon-cache.py start">graphite_start.sh
echo "$GRAPHITE_ROOT/bin/run-graphite-devel-server.py $GRAPHITE_ROOT/ &">>graphite_start.sh
echo "route add -net 192.168.108.0 netmask 255.255.255.0 gw 192.168.8.195">>graphite_start.sh
echo "/root/graphite_start.sh">>/etc/rc.d/rc.local
chmod +x /root/graphite_start.sh
chmod +x /etc/rc.d/rc.local
reboot


