#!/bin/bash

mkdir -p /root/ssl
openssl req -x509 -newkey rsa:4096 -keyout /root/ssl/key.pem -out /root/ssl/cert.pem -sha256 -days 3650 -nodes -subj "/C=XX/ST=NodesGarden/L=NodesGarden/O=NodesGarden/OU=NodesGarden/CN=$HOST_IP"

function get_last_log {
    while true; do
        sleep 5m
        cat /root/logs/node_log.log | tail -40 > /root/logs/last_40.log
    done
}

mkdir -p /root/logs
get_last_log &
trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT

# python3 -m venv .venv
# source .venv/bin/activate
./run_rl_swarm_cpu.sh 2>&1 | tee /root/logs/node_log.log