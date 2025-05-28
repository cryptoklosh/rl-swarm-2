#!/bin/bash

set -euo pipefail

# General arguments
export ROOT=$PWD

export PUB_MULTI_ADDRS
export PEER_MULTI_ADDRS
export HOST_MULTI_ADDRS
export IDENTITY_PATH
export CONNECT_TO_TESTNET
export ORG_ID
export HF_HUB_DOWNLOAD_TIMEOUT=120  # 2 minutes

#-------------------------------------------------------------------
# 1) Defaults for multi-addrs, identity, contracts, etc.
#-------------------------------------------------------------------

DEFAULT_PUB_MULTI_ADDRS=""
PUB_MULTI_ADDRS=${PUB_MULTI_ADDRS:-$DEFAULT_PUB_MULTI_ADDRS}

DEFAULT_PEER_MULTI_ADDRS="/ip4/38.101.215.13/tcp/30002/p2p/QmQ2gEXoPJg6iMBSUFWGzAabS2VhnzuS782Y637hGjfsRJ"
PEER_MULTI_ADDRS=${PEER_MULTI_ADDRS:-$DEFAULT_PEER_MULTI_ADDRS}

DEFAULT_HOST_MULTI_ADDRS="/ip4/0.0.0.0/tcp/38331"
HOST_MULTI_ADDRS=${HOST_MULTI_ADDRS:-$DEFAULT_HOST_MULTI_ADDRS}

DEFAULT_IDENTITY_PATH="$ROOT/swarm.pem"
IDENTITY_PATH=${IDENTITY_PATH:-$DEFAULT_IDENTITY_PATH}

SMALL_SWARM_CONTRACT="0x69C6e1D608ec64885E7b185d39b04B491a71768C"
BIG_SWARM_CONTRACT="0x6947c6E196a48B77eFa9331EC1E3e45f3Ee5Fd58"

CPU_ONLY=${CPU_ONLY:-""}
ORG_ID=${ORG_ID:-""}

#-------------------------------------------------------------------
# 2) Non-interactive settings (from your answers / env vars)
#-------------------------------------------------------------------

# Connect to testnet? (true/false)
CONNECT_TO_TESTNET=${CONNECT_TO_TESTNET:-true}

# Which swarm? (true = “Math Hard (B)”, false = “Math (A)”)
USE_BIG_SWARM=${USE_BIG_SWARM:-false}

# Model size in billions (choose from 0.5,1.5,7,32,72)
PARAM_B=${PARAM_B:-0.5}

# Push to Hugging Face? (true/false)
HUGGINGFACE_PUSH=${HUGGINGFACE_PUSH:-false}

# HF access token if pushing
HUGGINGFACE_ACCESS_TOKEN=${HUGGINGFACE_ACCESS_TOKEN:-"None"}

#-------------------------------------------------------------------
# 3) Helper for colors
#-------------------------------------------------------------------

GREEN_TEXT="\033[32m"
BLUE_TEXT="\033[34m"
RESET_TEXT="\033[0m"

echo_green() {
    echo -e "$GREEN_TEXT$1$RESET_TEXT"
}

echo_blue() {
    echo -e "$BLUE_TEXT$1$RESET_TEXT"
}

#-------------------------------------------------------------------
# Cloudflared
#-------------------------------------------------------------------

install_cloudflared() {
    apt-get install -y wget
    if command -v cloudflared >/dev/null 2>&1; then
        echo -e "Cloudflared is already installed."
        return
    fi
    echo -e "Installing cloudflared..."
    CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
    wget -q --show-progress "$CF_URL" -O cloudflared
    if [ $? -ne 0 ]; then
        echo -e "Failed to download cloudflared."
        exit 1
    fi
    chmod +x cloudflared
    mv cloudflared /usr/local/bin/
    if [ $? -ne 0 ]; then
        echo -e "Failed to move cloudflared to /usr/local/bin/."
        exit 1
    fi
    echo -e "Cloudflared installed successfully."
}

start_tunnel() {
    echo -e "Starting cloudflared tunnel..."
    cloudflared tunnel --url http://localhost:3000 > ~/cloudflared/cloudflared_output.log 2>&1 &
    TUNNEL_PID=$!
    counter=0
    MAX_WAIT=30
    while [ $counter -lt $MAX_WAIT ]; do
        echo -e "Waiting for cloudflared tunnel to start..."
        sleep 60
        FORWARDING_URL=$(grep -o 'https://[^ ]*\.trycloudflare.com' ~/cloudflared/cloudflared_output.log | head -n1)
        if [ -n "$FORWARDING_URL" ]; then
            echo -e "Cloudflared tunnel started successfully."
            echo "${FORWARDING_URL}" > /root/cloudflared/url.txt
            return $TUNNEL_PID
        fi
        counter=$((counter + 1))
    done
    echo -e "Timeout waiting for cloudflared URL."
    kill $TUNNEL_PID 2>/dev/null || true
    exit 1
}

run_tunnel() {
    start_tunnel
    PID=$?
    while true; do
        sleep 2h
        if curl -f $(cat /root/cloudflared/url.txt) > /dev/null 2>&1; then
            echo "Cloudflared tunnel is expired. Renewing..."
            kill $PID 2>/dev/null || true
            start_tunnel
            PID=$?
        else
            echo "Cloudflared tunnel is still active. No need to renew."
        fi
    done
}

#-------------------------------------------------------------------
# 4) Choose swarm contract
#-------------------------------------------------------------------

if [ "$USE_BIG_SWARM" = "true" ]; then
    SWARM_CONTRACT="$BIG_SWARM_CONTRACT"
else
    SWARM_CONTRACT="$SMALL_SWARM_CONTRACT"
fi

#-------------------------------------------------------------------
# 5) Testnet login & org setup
#-------------------------------------------------------------------

if [ "$CONNECT_TO_TESTNET" = "true" ]; then
    echo_green ">> Starting Modal login server for Testnet connection..."

    cd modal-login

    # Ensure Node.js & Yarn
    if ! command -v node > /dev/null 2>&1; then
        export NVM_DIR="$HOME/.nvm"
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
        . "$NVM_DIR/nvm.sh"
        nvm install node
    fi

    if ! command -v yarn > /dev/null 2>&1; then
        if grep -qi ubuntu /etc/os-release 2>/dev/null; then
            curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
            echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
            sudo apt update && sudo apt install -y yarn
        else
            npm install -g --silent yarn
        fi
    fi

    yarn install
    yarn dev > /dev/null 2>&1 &
    SERVER_PID=$!

    echo_green ">> Modal server PID: $SERVER_PID"
    sleep 5

    install_cloudflared
    run_tunnel & 
    trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT

    cd ..

    if [ ! -f "${IDENTITY_PATH}" ]; then
        echo_green ">> Waiting for modal-login/temp-data/userData.json..."
        until [ -f modal-login/temp-data/userData.json ]; do
            sleep 2
        done

        ORG_ID=$(awk 'BEGIN{FS="\""} !/^[ \t]*[{}]/{print $(NF-1); exit}' modal-login/temp-data/userData.json)
        echo_green ">> ORG_ID: $ORG_ID"

        echo_green ">> Waiting for API key activation..."
        until curl -s "http://localhost:3000/api/get-api-key-status?orgId=$ORG_ID" | grep -q activated; do
            sleep 5
        done
    fi

    ENV_FILE="$ROOT/modal-login/.env"
    sed -i "3s/.*/SMART_CONTRACT_ADDRESS=$SWARM_CONTRACT/" "$ENV_FILE"
fi

#-------------------------------------------------------------------
# 6) Install Python requirements & choose config
#-------------------------------------------------------------------

echo_green ">> Installing Python requirements..."
pip install --upgrade pip

if [ -n "$CPU_ONLY" ] || ! command -v nvidia-smi &>/dev/null; then
    pip install -r "$ROOT/requirements-cpu.txt"
    CONFIG_PATH="$ROOT/hivemind_exp/configs/mac/grpo-qwen-2.5-${PARAM_B}b-deepseek-r1.yaml"
    GAME="gsm8k"
else
    pip install -r "$ROOT/requirements-gpu.txt"
    # pip install flash-attn --no-build-isolation

    if [[ "$PARAM_B" == "32" || "$PARAM_B" == "72" ]]; then
        CONFIG_PATH="$ROOT/hivemind_exp/configs/gpu/grpo-qwen-2.5-${PARAM_B}b-bnb-4bit-deepseek-r1.yaml"
    else
        CONFIG_PATH="$ROOT/hivemind_exp/configs/gpu/grpo-qwen-2.5-${PARAM_B}b-deepseek-r1.yaml"
    fi

    if [ "$USE_BIG_SWARM" = "true" ]; then
        GAME="dapo"
    else
        GAME="gsm8k"
    fi
fi

# echo_green ">> Configuration complete."
# echo_blue " Swarm:         $SWARM_CONTRACT"
# echo_blue " Testnet:       $CONNECT_TO_TESTNET"
# echo_blue " Model size:    ${PARAM_B}B"
# echo_blue " Config file:   $CONFIG_PATH"
# echo_blue " Game:          $GAME"

#-------------------------------------------------------------------
# 7) Hugging Face push logic
#-------------------------------------------------------------------

if [ "$HUGGINGFACE_PUSH" = "true" ]; then
    if [ -z "$HUGGINGFACE_ACCESS_TOKEN" ] || [ "$HUGGINGFACE_ACCESS_TOKEN" = "None" ]; then
        echo_green ">> Warning: HUGGINGFACE_PUSH=true but no token provided; skipping push."
        HUGGINGFACE_ACCESS_TOKEN="None"
    fi
else
    HUGGINGFACE_ACCESS_TOKEN="None"
fi

#-------------------------------------------------------------------
# 8) Launch training
#-------------------------------------------------------------------

echo_green ">> Launching training job..."

ORG_ID=$(awk 'BEGIN{FS="\""} !/^[ \t]*[{}]/{print $(NF-1); exit}' modal-login/temp-data/userData.json)
echo_green ">> ORG_ID: $ORG_ID"

sed -i -E 's/(startup_timeout: *float *= *)[0-9.]+/\1120/' $(python -c "import hivemind.p2p.p2p_daemon as m; print(m.__file__)")
rm -rf .venv/lib/python3.10/site-packages/trl/trainer/grpo_trainer.py
cp fixes/grpo_trainer.py .venv/lib/python3.10/site-packages/trl/trainer/grpo_trainer.py

if [ -n "$ORG_ID" ]; then
    python -m hivemind_exp.gsm8k.train_single_gpu \
        --hf_token "$HUGGINGFACE_ACCESS_TOKEN" \
        --identity_path "$IDENTITY_PATH" \
        --modal_org_id "$ORG_ID" \
        --contract_address "$SWARM_CONTRACT" \
        --config "$CONFIG_PATH" \
        --game "$GAME"
else
    python -m hivemind_exp.gsm8k.train_single_gpu \
        --hf_token "$HUGGINGFACE_ACCESS_TOKEN" \
        --identity_path "$IDENTITY_PATH" \
        --public_maddr "$PUB_MULTI_ADDRS" \
        --initial_peers "$PEER_MULTI_ADDRS" \
        --host_maddr "$HOST_MULTI_ADDRS" \
        --config "$CONFIG_PATH" \
        --game "$GAME"
fi

wait
