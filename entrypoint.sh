#!/bin/bash

mkdir -p /root/ssl
openssl req -x509 -newkey rsa:4096 -keyout /root/ssl/key.pem -out /root/ssl/cert.pem -sha256 -days 3650 -nodes -subj "/C=XX/ST=NodesGarden/L=NodesGarden/O=NodesGarden/OU=NodesGarden/CN=62.84.190.11"

./run_rl_swarm.sh