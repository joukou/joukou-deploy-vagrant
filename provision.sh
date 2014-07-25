#!/bin/zsh
#
# Starting from an Ubuntu 14.04 LTS 64-bit installation this script provisions
# a single Joukou platform node (i.e. a docker host with running containers).
#
# Author: Isaac Johnston <isaac.johnston@joukou.com>
# Copyright (c) 2009-2014 Joukou Ltd. All rights reserved.
#

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

# Add the admin group
groupadd admin

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

while true; do
  read -p "Other host's IP address:" OTHER_HOST_IP
  if [ -z "$OTHER_HOST_IP" ]; then
    exit
  fi
  # Allow intra-cluster Basho Riak Protobuf
  ufw allow proto tcp from $OTHER_HOST_IP to any port 8087
  # Allow intra-cluster Basho Riak HTTP
  ufw allow proto tcp from $OTHER_HOST_IP to any port 8098
  # Allow intra-cluster Basho Riak / RabbitMQ epmd listener
  ufw allow proto tcp from $OTHER_HOST_IP to any port 4369
  # Allow intra-cluster Basho Riak handoff
  ufw allow proto tcp from $OTHER_HOST_IP to any port 8099
  # Allow intra-cluster RabbitMQ
  ufw allow proto tcp from $OTHER_HOST_IP to any port 5672
  # Allow intra-cluster Erlang distribution for Basho Riak (configured in
  # riak.conf)
  ufw allow proto tcp from $OTHER_HOST_IP to any port 8088:8092
  # Allow intra-cluster Erlang distribution for RabbitMQ (configured in 
  # rabbitmq.config or environment variables)
  ufw allow proto tcp from $OTHER_HOST_IP to any port 25672
  # Allow ElasticSearch HTTP
  ufw allow proto tcp from $OTHER_HOST_IP to any port 9200
  # Allow ElasticSearch Node-to-Node
  ufw allow proto tcp from $OTHER_HOST_IP to any port 9300
  # Allow ElasticSearch service discovery
  ufw allow proto tcp from $OTHER_HOST_IP to any port 54328
done

ufw enable

cd /etc && etckeeper commit "Enables and configures ufw"
cd -