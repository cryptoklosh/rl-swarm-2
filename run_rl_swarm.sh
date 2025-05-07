#!/bin/bash
set -euo pipefail

# General arguments
export ROOT=$PWD
export PUB_MULTI_ADDRS PEER_MULTI_ADDRS HOST_MULTI_ADDRS IDENTITY_PATH CONNECT_TO_TESTNET ORG_ID
export HF_HUB_DOWNLOAD_TIMEOUT=120  # 2 minutes

# Default multi-addresses
DEFAULT_PUB_MULTI_ADDRS=""
PUB_MULTI_ADDRS=${PUB_MULTI_ADDRS:-$DEFAULT_PUB_MULTI_ADDRS}
DEFAULT_PEER_MULTI_ADDRS="/ip4/38.101.215.13/tcp/30002/p2p/QmQ2gEXoPJg6iMBSUFWGzAabS2VhnzuS782Y637hGjfsRJ"
PEER_MULTI_ADDRS=${PEER_MULTI_ADDRS:-$DEFAULT_PEER_MULTI_ADDRS}
DEFAULT_HOST_MULTI_ADDRS="/ip4/0.0.0.0/tcp/38331"
HOST_MULTI_ADDRS=${HOST_MULTI_ADDRS:-$DEFAULT_HOST_MULTI_ADDRS}

# Identity path
DEFAULT_IDENTITY_PATH="$ROOT/identity/swarm.pem"
IDENTITY_PATH=${IDENTITY_PATH:-$DEFAULT_IDENTITY_PATH}

# Constants
SMALL_SWARM_CONTRACT="0x69C6e1D608ec64885E7b185d39b04B491a71768C"
BIG_SWARM_CONTRACT="0x6947c6E196a48B77eFa9331EC1E3e45f3Ee5Fd58"

# CPU-only override
CPU_ONLY=${CPU_ONLY:-""}

# Organization ID
ORG_ID=${ORG_ID:-""}

# Color codes
GREEN_TEXT="\033[32m"
BLUE_TEXT="\033[34m"
RESET_TEXT="\033[0m"

echo_green() { echo -e "${GREEN_TEXT}$1${RESET_TEXT}"; }
echo_blue()  { echo -e "${BLUE_TEXT}$1${RESET_TEXT}"; }

# Welcome banner
echo -e "\033[38;5;224m"
cat << "EOF"
    ██████  ██            ███████ ██     ██  █████  ██████  ███    ███
    ██   ██ ██            ██      ██     ██ ██   ██ ██   ██ ████  ████
    ██████  ██      █████ ███████ ██  █  ██ ███████ ██████  ██ ████ ██
    ██   ██ ██                 ██ ██ ███ ██ ██   ██ ██   ██ ██  ██  ██
    ██   ██ ███████       ███████  ███ ███  ██   ██ ██   ██ ██      ██

    From Gensyn
EOF

# Determine swarm contract
USE_BIG_SWARM=${USE_BIG_SWARM:-false}
if [ "$USE_BIG_SWARM" = true ]; then
    SWARM_CONTRACT="$BIG_SWARM_CONTRACT"
    echo_green ">> Using big swarm: $SWARM_CONTRACT"
else
    SWARM_CONTRACT="$SMALL_SWARM_CONTRACT"
    echo_green ">> Using small swarm: $SWARM_CONTRACT"
fi

# Model size parameter
PARAM_B=${PARAM_B:-1.5}

echo_green ">> Upgrading setuptools for PEP 621 support..."
pip3 install --no-cache-dir "setuptools>=67.6.0" wheel packaging

# Pip install helper
pip_install() { pip3 install --disable-pip-version-check -q -r "$1"; }

echo_green ">> Installing Python requirements..."
if [ -n "$CPU_ONLY" ] || ! command -v nvidia-smi &> /dev/null; then
    pip_install "$ROOT/requirements-cpu.txt"
else
    pip_install "$ROOT/requirements-gpu.txt"
fi

# Start modal-login server
echo_green ">> Starting modal-login server..."
cd modal-login
yarn dev > /dev/null 2>&1 &
SERVER_PID=$!
echo "Started server (PID $SERVER_PID)"

# Wait for login data
echo_green ">> Waiting for userData.json..."
while [ ! -f "modal-login/temp-data/userData.json" ]; do
    sleep 5
done

# Extract ORG_ID
ORG_ID=$(awk 'BEGIN { FS = "\"" } !/^[ \t]*[{}]/ { print $(NF-1); exit }' modal-login/temp-data/userData.json)
echo_green ">> ORG_ID: $ORG_ID"

# Update .env with contract address
ENV_FILE="modal-login/.env"
sed -i "3s/.*/SMART_CONTRACT_ADDRESS=$SWARM_CONTRACT/" "$ENV_FILE"

# Start cloudflared tunnel (optional)
# start_tunnel

# Run training
echo_green ">> Launching training on \$([ -n "$CPU_ONLY" ] && echo CPU || echo GPU)..."
cd ~

# Patch timeouts in hivemind
sed -i -E 's/(startup_timeout: *float *= *)[0-9.]+/\1120/' \
    $(python -c "import hivemind.p2p.p2p_daemon as m; print(m.__file__)")
sed -i -E 's/\(await_ready=await_ready\)/\(await_ready=await_ready,timeout=600\)/' \
    /usr/local/lib/python3.11/dist-packages/hivemind/dht/dht.py

# Execute training
if [ -n "$ORG_ID" ]; then
    python3 -u -m hivemind_exp.gsm8k.train_single_gpu \
        --hf_token "${HF_HUB_DOWNLOAD_TIMEOUT}" \
        --identity_path "$IDENTITY_PATH" \
        --modal_org_id "$ORG_ID" \
        --contract_address "$SWARM_CONTRACT" \
        --config "$ROOT/hivemind_exp/configs/gpu/grpo-qwen-2.5-${PARAM_B}b-deepseek-r1.yaml" \
        --game gsm8k
else
    echo_blue ">> No ORG_ID, exiting."
    exit 1
fi