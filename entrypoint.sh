#!/bin/bash
set -euo pipefail

# Create self-signed cert for localhost
mkdir -p /root/ssl
openssl req -x509 -newkey rsa:4096 \
  -keyout /root/ssl/key.pem -out /root/ssl/cert.pem \
  -sha256 -days 3650 -nodes \
  -subj "/C=XX/ST=NodesGarden/L=NodesGarden/O=NodesGarden/OU=NodesGarden/CN=localhost"

# Upgrade pip so runtime installs parse platform tags correctly
echo ">> Upgrading pip..."
pip3 install --no-cache-dir --upgrade pip

# Then call the main runner
./run_rl_swarm.sh
