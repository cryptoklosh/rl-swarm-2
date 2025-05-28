#!/bin/bash

# mkdir -p /root/ssl
# openssl req -x509 -newkey rsa:4096 -keyout /root/ssl/key.pem -out /root/ssl/cert.pem -sha256 -days 3650 -nodes -subj "/C=XX/ST=NodesGarden/L=NodesGarden/O=NodesGarden/OU=NodesGarden/CN=$HOST_IP"

python3 -m venv .venv
source .venv/bin/activate

function run_node_manager() {
    MANIFEST_FILE=/root/node-manager/nodeV3.yaml \
    MODE=init \
    /root/node-manager/node-manager | tee /root/logs/node_manager.log
    
    MANIFEST_FILE=/root/node-manager/nodeV3.yaml \
    MODE=sidecar \
    /root/node-manager/node-manager | tee -a /root/logs/node_manager.log
}
function get_last_log {
    while true; do
        sleep 5m
        cat /root/logs/node_log.log | tail -40 > /root/logs/last_40.log
    done
}

mkdir /root/logs
mkdir /root/identity
mkdir /root/cloudflared
get_last_log &
run_node_manager &
trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT

./run_rl_swarm_vastai.sh 2>&1 | tee /root/logs/node_log.log