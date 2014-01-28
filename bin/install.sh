#!/bin/bash
#
# © 2014 David J. Goehrig
#
# This script will install the components necessary to build a WoT.io server image on Centos 6.3
#
#
#
#

if [[ -z "$1" || -z "$2" ]]; then
	echo "Usage: $0 password servername"
	exit 0
fi

# Environment variables
MASTER_PASSWORD=$1
SERVER=$2
RABBITMQ_SERVER=/usr/lib/rabbitmq/bin/rabbitmq-server
RABBITMQCTL=/usr/lib/rabbitmq/bin/rabbitmqctl
DIR=$(dirname $0)/..

if [[ $(whoami) == 'root' ]]; then
	echo "Installing server $SERVER"
else
	echo "You must be root to install $SERVER"
	exit 0
fi

# Install Development tools so we can build software
yum -y groupinstall "Development Tools"

# Install EPEL6
yum -y install http://mirror.pnl.gov/epel/6/i386/epel-release-6-8.noarch.rpm

# Install the postgres repo
rpm -i http://yum.postgresql.org/9.3/redhat/rhel-6-x86_64/pgdg-centos93-9.3-1.noarch.rpm

# Install postgres
yum install -y postgresql93-server postgresql93-contrib postgresql93-devel

# Install PowerDNS with the postgresql backend
yum install -y pdns bind-utils pdns-backend-postgresql.x86_64

# Install the PowerDNS configuration and SQL script
cp $DIR/etc/pdns.conf /etc/pdns/pdns.conf

# delete the stock password, and add our master password
sed -i -e '16d' /etc/pdns/pdns.conf
echo "webserver-password=$MASTER_PASSWORD" >> /etc/pdns/pdns.conf

# Install the Postgres database
su - postgres -c '/usr/pgsql-9.3/bin/initdb -D /var/lib/pgsql/data'

# Configure the database to trust localhost & listen only on localhost
echo "host    all             all             127.0.0.1/32            trust" >> /var/lib/pgsql/data/pg_hba.conf
echo "listen_addresses='127.0.0.1'" >> /var/lib/pgsql/data/postgresql.conf

# Startup postgres
su - postgres -c '/usr/pgsql-9.3/bin/postgres -D /var/lib/pgsql/data' &
echo "su - postgres -c '/usr/pgsql-9.3/bin/postgres -D /var/lib/pgsql/data' &" >> /etc/rc.local
sleep 5

# Create the postgresql database & create the user & schema
su - postgres -c 'createdb pdns'
su - postgres -c 'createuser pdns'
psql -U postgres -h localhost pdns < $DIR/etc/pdns.sql
sleep 4

# Start the PowerDNS server
/usr/sbin/pdns_server &
echo "/usr/sbin/pdns_server &" >> /etc/rc.local

# Install RabbitMQ 3.1.5 from upstream
yum -y install http://www.rabbitmq.com/releases/rabbitmq-server/v3.1.5/rabbitmq-server-3.1.5-1.noarch.rpm

# Enable the plugins we need
/usr/sbin/rabbitmq-plugins enable rabbitmq_mqtt rabbitmq_stomp rabbitmq_management  rabbitmq_management_agent rabbitmq_management_visualiser rabbitmq_federation rabbitmq_federation_management sockjs

# Create a new erlang.cookie
uuidgen -r | sed 's%-%%g' > ~/.erlang.cookie
cat ~/.erlang.cookie > /var/lib/rabbitmq/.erlang.cookie
chmod 400 /var/lib/rabbitmq/.erlang.cookie
chown rabbitmq:rabbitmq /var/lib/rabbitmq/.erlang.cookie

# Install a custom RabbitMQ server scripts so we can use FQDN with our RabbitMQ
cp $DIR/rabbitmq-server > $RABBITMQ_SERVER
cp $DIR/rabbitmqctl > $RABBITMQCTL

# Start the rabbitmq server and install in rc.local and add it to the path
export CONTAINER_SERVER="$SERVER"
$RABBITMQ_SERVER &
echo "CONTAINER_SERVER=$SERVER $RABBITMQ_SERVER &"  >> /etc/rc.local
echo "export PATH=/usr/lib/rabbitmq/bin:$PATH" >> /etc/profile.d/rabbitmq.sh
sleep 5

# Setup the wot-admin user and remove guest:guest
$RABBITMQCTL add_user wot-admin "$MASTER_PASSWORD"
$RABBITMQCTL set_permissions wot-admin '.*' '.*' '.*'
$RABBITMQCTL delete_user guest
for VHOST in wot wot-management wot-testing; do
	$RABBITMQCTL add_vhost $VHOST
	$RABBITMQCTL -p $VHOST set_permissions wot-admin '.*' '.*' '.*'
done

# Add a default user for the wot vhost w/ default password wot
$RABBITMQCTL add_user wot "wot"
$RABBITMQCTL -p wot set_permissions wot '.*' '.*' '.*'

# Build and Install nodejs from source
pushd /tmp/
curl -O http://nodejs.org/dist/v0.10.25/node-v0.10.25.tar.gz
tar zxvf node-v0.10.25.tar.gz
pushd node-v0.10.25 && ./configure 
make
make install
popd
rm -rf node-v0.10.25 node-v0.10.25.tar.gz
popd

# Setup default path to include node and npm in path
echo "export PATH=/usr/local/bin:/usr/local/sbin:$PATH" > /etc/profile.d/nodejs.sh
echo "export NODE_PATH=\"$$(npm root -g)\"" >> /etc/profile.d/nodejs.sh
source /etc/profile.d/nodejs.sh

# Install the core NPM modules
npm install -g coffee-script
npm install -g uuid
npm install -g request
npm install -g express
npm install -g supervisor
npm install -g twitter
npm install -g amqp
npm install -g pgproc
npm install -g pgproc.http
npm install -g pontifex
npm install -g pontifex.ws
npm install -g pontifex.udp
npm install -g pontifex.http
npm install -g opifex
npm install -g opifex.nova
npm install -g opifex.rabbitmq
npm install -g opifex.docker
npm install -g opifex.redis
npm install -g opifex.twitter
npm install -g opifex.rss
npm install -g opifex.pipe
# npm install -g wot

# Startup the Postgresql HTTP API
su - postgres -c '/node_modules/.bin/pgproc postgres://localhost:5432/pdns public 5380' &
echo "su - postgres -c '/node_modules/.bin/pgproc postgres://localhost:5432/pdns public 5380' &" >> /etc/rc.local
sleep 1

# Build and install Redis
pushd /tmp/
curl -O http://download.redis.io/releases/redis-2.6.16.tar.gz
tar zxvf redis-2.6.16.tar.gz
pushd redis-2.6.16 
make 
make install
popd
rm -rf redis-2.6.16.tar.gz redis-2.6.16
popd

# Install Varnish repo
rpm --nosignature -i http://repo.varnish-cache.org/redhat/varnish-3.0/el6/noarch/varnish-release/varnish-release-3.0-1.el6.noarch.rpm
yum install varnish

# Install the varnish config for all of the applications
cp $DIR/etc/default.vcl /etc/vanishd/default.vcl
cp $DIR/etc/varnish /etc/sysconfig/varnish






