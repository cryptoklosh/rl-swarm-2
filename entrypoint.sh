#!/bin/bash
set -euo pipefail

# Create self-signed certificate for HTTPS (if needed)
mkdir -p /root/ssl
openssl req -x509 -newkey rsa:4096 \
  -keyout /root/ssl/key.pem -out /root/ssl/cert.pem \
  -sha256 -days 3650 -nodes \
  -subj "/C=XX/ST=NodesGarden/L=NodesGarden/O=NodesGarden/OU=NodesGarden/CN=localhost"

# Upgrade pip & setuptools at runtime so we reuse the host’s tooling
echo ">> Upgrading pip & setuptools for runtime installs..."
pip3 install --no-cache-dir 'setuptools<67.6.0' wheel packaging

# Delegate to the main runner
exec ./run_rl_swarm.sh
