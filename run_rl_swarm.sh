#!/bin/bash
set -euo pipefail

export ROOT="$PWD"
export PUB_MULTI_ADDRS PEER_MULTI_ADDRS HOST_MULTI_ADDRS IDENTITY_PATH \
       CONNECT_TO_TESTNET ORG_ID HF_HUB_DOWNLOAD_TIMEOUT
HF_HUB_DOWNLOAD_TIMEOUT=120

# Defaults
PUB_MULTI_ADDRS=${PUB_MULTI_ADDRS:-}
PEER_MULTI_ADDRS=${PEER_MULTI_ADDRS:-/ip4/38.101.215.13/tcp/30002/p2p/QmQ2gEXoPJg6iMBSUFWGzAabS2VhnzuS782Y637hGjfsRJ}
HOST_MULTI_ADDRS=${HOST_MULTI_ADDRS:-/ip4/0.0.0.0/tcp/38331}
IDENTITY_PATH=${IDENTITY_PATH:-$ROOT/identity/swarm.pem}
CPU_ONLY=${CPU_ONLY:-}
ORG_ID=${ORG_ID:-}

# Simple colored echo
GREEN="\033[32m"; RESET="\033[0m"
echo_green(){ echo -e "${GREEN}$1${RESET}"; }

# Banner
echo_green "From Gensyn → Starting RL Swarm"

# Helper: install via host’s setuptools (no isolated build)
pip_install(){
  pip3 install --disable-pip-version-check --no-build-isolation -q -r "$1"
}

echo_green "Installing Python requirements..."
if [ -n "$CPU_ONLY" ] || ! command -v nvidia-smi &> /dev/null; then
  pip_install "$ROOT/requirements-cpu.txt"
else
  pip_install "$ROOT/requirements-gpu.txt"
fi

# Start modal-login frontend
echo_green "Starting modal-login server..."
cd modal-login
yarn dev > /dev/null 2>&1 &
SERVER_PID=$!
sleep 5

echo_green "Waiting for user login..."
while [ ! -f temp-data/userData.json ]; do sleep 2; done
ORG_ID=$(grep -oP '(?<="orgId": ")[^"]+' temp-data/userData.json)
echo_green "Detected ORG_ID: $ORG_ID"
cd "$ROOT"

# Patch hivemind timeouts
echo_green "Patching hivemind timeouts..."
PYDAEMON=$(python3 -c "import hivemind.p2p.p2p_daemon as m; print(m.__file__)")
sed -i -E 's/(startup_timeout: *float *= *)[0-9]+/\1120/' "$PYDAEMON"
sed -i -E 's/\(await_ready=await_ready\)/\(await_ready=await_ready,timeout=600\)/' \
    /usr/local/lib/python3.11/dist-packages/hivemind/dht/dht.py

# Launch training
echo_green "Launching training ($( [ -n "$CPU_ONLY" ] && echo CPU || echo GPU ))..."
python3 -u -m hivemind_exp.gsm8k.train_single_gpu \
  --hf_token "$HF_HUB_DOWNLOAD_TIMEOUT" \
  --identity_path "$IDENTITY_PATH" \
  --modal_org_id "$ORG_ID" \
  --contract_address "$SWARM_CONTRACT" \
  --config "$ROOT/hivemind_exp/configs/gpu/grpo-qwen-2.5-1.5b-deepseek-r1.yaml" \
  --game gsm8k

wait
