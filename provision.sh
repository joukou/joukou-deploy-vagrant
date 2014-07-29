#!/bin/zsh
#
# Starting from an Ubuntu 14.04 LTS 64-bit installation this script provisions
# a single Joukou platform node (i.e. a docker host with running containers).
#
# Author: Isaac Johnston <isaac.johnston@joukou.com>
# Copyright (c) 2009-2014 Joukou Ltd. All rights reserved.
#

export DEBIAN_FRONTEND=noninteractive

DOCKER_USERNAME=joukoudeploy
DOCKER_EMAIL=platform@joukou.com
DOCKER_PASSWORD=talnovjilcukedhx
DOCKER_TAG=latest

## Set the timezone
echo "Pacific/Auckland" | tee /etc/timezone
dpkg-reconfigure tzdata

# Add the Docker apt repository to the keychain
apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 36A1D7869245C8950F966E92D8576A8BA88D21E9

# Add the Docker apt repository to the sources list
echo "deb https://get.docker.io/ubuntu docker main" > /etc/apt/sources.list.d/docker.list

# Resynchronize the Ubuntu package index files from their sources
apt-get update -qq

# Upgrade all packages
apt-get dist-upgrade -y --no-install-recommends

# Install Docker and some common utilities
apt-get install -y --no-install-recommends curl etckeeper git-core htop lxc-docker tmux vim

# Use git for etckeeper
sed -e 's:^\(VCS\s*=.*bzr\):#\1:' -e 's:^#\(VCS\s*=.*git\):\1:' -i /etc/etckeeper/etckeeper.conf

# Initialize etckeeper repository
cd /etc && etckeeper init && etckeeper commit "Initial commit"
cd -

# Enable memory cgroup and swap accounting for Docker.
# http://docs.docker.io/en/latest/installation/kernel/#memory-and-swap-accounting-on-debian-ubuntu
sed -i 's/^GRUB_CMDLINE_LINUX=""$/GRUB_CMDLINE_LINUX="cgroup_enable=memory swapaccount=1"/' /etc/default/grub

update-grub

cd /etc && etckeeper commit "Enables memory cgroup and swap accounting for Docker"
cd -

# Configure Docker DNS for SkyDock
DOCKER_BIP=$(ip -o -4 addr list docker0 | awk '{print $4}')
DOCKER_DNS=$(ip -o -4 addr list docker0 | awk '{print $4}' | cut -d/ -f1)
sed -i 's/^#DOCKER_OPTS="--dns 8.8.8.8 --dns 8.8.4.4"$/DOCKER_OPTS="--bip=$DOCKER_BIP --dns=$DOCKER_DNS"/'

service docker restart

cd /etc && etckeeper commit "Configures Docker for DNS for SkyDock"
cd -

# Add users and groups
groupadd admin

# TODO visudo, users etc

cd /etc && etckeeper commit "Adds users and groups"
cd -

# Install Prezto
git clone --recursive https://github.com/sorin-ionescu/prezto.git "${ZDOTDIR:-$HOME}/.zprezto"

setopt EXTENDED_GLOB
for rcfile in "${ZDOTDIR:-$HOME}"/.zprezto/runcoms/^README.md(.N); do
  ln -s "$rcfile" "${ZDOTDIR:-$HOME}/.${rcfile:t}"
done

chsh -s /bin/zsh

# Firewall

# Allow external SSH
ufw allow 22

# Allow external HTTP
ufw allow 80

# Allow external HTTPS
ufw allow 443

# while true; do
#   read -p "Other host's IP address:" OTHER_HOST_IP
#   if [ -z "$OTHER_HOST_IP" ]; then
#     exit
#   fi
#   # Allow intra-cluster Basho Riak Protobuf
#   ufw allow proto tcp from $OTHER_HOST_IP to any port 8087
#   # Allow intra-cluster Basho Riak HTTP
#   ufw allow proto tcp from $OTHER_HOST_IP to any port 8098
#   # Allow intra-cluster Basho Riak / RabbitMQ epmd listener
#   ufw allow proto tcp from $OTHER_HOST_IP to any port 4369
#   # Allow intra-cluster Basho Riak handoff
#   ufw allow proto tcp from $OTHER_HOST_IP to any port 8099
#   # Allow intra-cluster RabbitMQ
#   ufw allow proto tcp from $OTHER_HOST_IP to any port 5672
#   # Allow intra-cluster Erlang distribution for Basho Riak (configured in
#   # riak.conf)
#   ufw allow proto tcp from $OTHER_HOST_IP to any port 8088:8092
#   # Allow intra-cluster Erlang distribution for RabbitMQ (configured in 
#   # rabbitmq.config or environment variables)
#   ufw allow proto tcp from $OTHER_HOST_IP to any port 25672
#   # Allow ElasticSearch HTTP
#   ufw allow proto tcp from $OTHER_HOST_IP to any port 9200
#   # Allow ElasticSearch Node-to-Node
#   ufw allow proto tcp from $OTHER_HOST_IP to any port 9300
#   # Allow ElasticSearch service discovery
#   ufw allow proto tcp from $OTHER_HOST_IP to any port 54328
# done

ufw enable

cd /etc && etckeeper commit "Enables and configures ufw"
cd -

docker login \
  --email=$DOCKER_EMAIL \
  --username=$DOCKER_USERNAME \
  --password=$DOCKER_PASSWORD

docker pull crosbymichael/skydns
docker run -d \
  -p $DOCKER_DNS:53:53/udp \
  --name skydns \
  crosbymichael/skydns -nameserver 8.8.8.8:53 -domain joukou.com

docker pull crosbymichael/skydock
docker run -d \
  -v /var/run/docker.sock:/docker.sock \
  --name skydock \
  crosbymichael/skydock -ttl 30 -environment dev -s /docker.sock -domain joukou.com -name skydns

docker pull joukou/elasticsearch:$DOCKER_TAG
docker run -d \
  -v /var/lib/elasticsearch:/var/lib/elasticsearch \
  -v /var/log/elasticsearc:/var/log/elasticsearch \
  -p 9200:9200 \
  -p 9300:9300 \
  -p 54328:54328 \
  --name elasticsearch \
  joukou/elasticsearch:$DOCKER_TAG

docker pull joukou/nginx:$DOCKER_TAG
docker run -d \
  -v /etc/ssl/certs/wildcard.joukou.com.crt:/etc/ssl/certs/wildcard.joukou.com.crt \
  -v /etc/ssl/private/wildcard.joukou.com.key:/etc/ssl/private/wildcard.joukou.com.key \
  -p 80:80 \
  -p 443:443 \
  --name nginx \
  joukou/nginx:$DOCKER_TAG

docker pull joukou/rabbitmq:$DOCKER_TAG
docker run -d \
  -v /var/lib/rabbitmq:/var/lib/rabbitmq \
  -v /var/log/rabbitmq:/var/log/rabbitmq \
  -p 4369:4369 \
  -p 5672:5672 \
  -p 15672:15672 \
  -p 25672:25672 \
  --name rabbitmq \
  joukou/rabbitmq:$DOCKER_TAG

docker pull joukou/riak:$DOCKER_TAG
docker run -d \
  -v /var/lib/riak:/var/lib/riak \
  -v /var/log/riak:/var/log/riak \
  -p 4370:4370 \
  -p 8087:8087 \
  -p 8088:8088 \
  -p 8089:8089 \
  -p 8090:8090 \
  -p 8091:8091 \
  -p 8092:8092 \
  -p 8093:8093 \
  -p 8098:8098 \
  -p 8099:8099 \
  -p 8985:8985 \
  --name riak \
  joukou/riak:$DOCKER_TAG

docker pull google/cadvisor:canary
docker run -d \
  --volume=/var/run:/var/run:rw \
  --volume=/sys:/sys:ro \
  --volume=/var/lib/docker/:/var/lib/docker:ro \
  --publish=8080:8080 \
  --name=cadvisor \
  google/cadvisor:canary
