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

# Check if public multi-address is given else set to default
DEFAULT_PUB_MULTI_ADDRS=""
PUB_MULTI_ADDRS=${PUB_MULTI_ADDRS:-$DEFAULT_PUB_MULTI_ADDRS}

# Check if peer multi-address is given else set to default
DEFAULT_PEER_MULTI_ADDRS="/ip4/38.101.215.13/tcp/30002/p2p/QmQ2gEXoPJg6iMBSUFWGzAabS2VhnzuS782Y637hGjfsRJ" # gensyn coordinator node
PEER_MULTI_ADDRS=${PEER_MULTI_ADDRS:-$DEFAULT_PEER_MULTI_ADDRS}

# Check if host multi-address is given else set to default
DEFAULT_HOST_MULTI_ADDRS="/ip4/0.0.0.0/tcp/38331"
HOST_MULTI_ADDRS=${HOST_MULTI_ADDRS:-$DEFAULT_HOST_MULTI_ADDRS}

# Path to an RSA private key. If this path does not exist, a new key pair will be created.
# Remove this file if you want a new PeerID.
DEFAULT_IDENTITY_PATH="$ROOT"/identity/swarm.pem
IDENTITY_PATH=${IDENTITY_PATH:-$DEFAULT_IDENTITY_PATH}

SMALL_SWARM_CONTRACT="0x69C6e1D608ec64885E7b185d39b04B491a71768C"
BIG_SWARM_CONTRACT="0x6947c6E196a48B77eFa9331EC1E3e45f3Ee5Fd58"

# Will ignore any visible GPUs if set.
CPU_ONLY=${CPU_ONLY:-""}

# Set if successfully parsed from modal-login/temp-data/userData.json.
ORG_ID=${ORG_ID:-""}

GREEN_TEXT="\033[32m"
BLUE_TEXT="\033[34m"
RESET_TEXT="\033[0m"

echo_green() {
    echo -e "$GREEN_TEXT$1$RESET_TEXT"
}

echo_blue() {
    echo -e "$BLUE_TEXT$1$RESET_TEXT"
}

ROOT_DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"

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
            echo "${FORWARDING_URL}" > ~/cloudflared/url.txt
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
        if curl -f $(cat ~/cloudflared/url.txt) > /dev/null 2>&1; then
            echo "Cloudflared tunnel is expired. Renewing..."
            kill $PID 2>/dev/null || true
            start_tunnel
            PID=$?
        else
            echo "Cloudflared tunnel is still active. No need to renew."
        fi
    done
}

# Function to clean up the server process upon exit
# cleanup() {
#     echo_green ">> Shutting down trainer..."

#     # Remove modal credentials if they exist
#     rm -r $ROOT_DIR/modal-login/temp-data/*.json 2> /dev/null || true

#     # Kill all processes belonging to this script's process group
#     kill -- -$$ || true

#     exit 0
# }

# trap cleanup EXIT

echo -e "\033[38;5;224m"
cat << "EOF"
    ██████  ██            ███████ ██     ██  █████  ██████  ███    ███
    ██   ██ ██            ██      ██     ██ ██   ██ ██   ██ ████  ████
    ██████  ██      █████ ███████ ██  █  ██ ███████ ██████  ██ ████ ██
    ██   ██ ██                 ██ ██ ███ ██ ██   ██ ██   ██ ██  ██  ██
    ██   ██ ███████       ███████  ███ ███  ██   ██ ██   ██ ██      ██

    From Gensyn

EOF

CONNECT_TO_TESTNET=true
# while true; do
#     echo -en $GREEN_TEXT
#     read -p ">> Would you like to connect to the Testnet? [Y/n] " yn
#     echo -en $RESET_TEXT
#     yn=${yn:-Y}  # Default to "Y" if the user presses Enter
#     case $yn in
#         [Yy]*)  CONNECT_TO_TESTNET=true && break ;;
#         [Nn]*)  CONNECT_TO_TESTNET=false && break ;;
#         *)  echo ">>> Please answer yes or no." ;;
#     esac
# done

USE_BIG_SWARM=false
# while true; do
#     echo -en $GREEN_TEXT
#     read -p ">> Which swarm would you like to join (Math (A) or Math Hard (B))? [A/b] " ab
#     echo -en $RESET_TEXT
#     ab=${ab:-A}  # Default to "A" if the user presses Enter
#     case $ab in
#         [Aa]*)  USE_BIG_SWARM=false && break ;;
#         [Bb]*)  USE_BIG_SWARM=true && break ;;
#         *)  echo ">>> Please answer A or B." ;;
#     esac
# done
if [ "$USE_BIG_SWARM" = true ]; then
    SWARM_CONTRACT="$BIG_SWARM_CONTRACT"
else
    SWARM_CONTRACT="$SMALL_SWARM_CONTRACT"
fi

PARAM_B=1.5
# while true; do
#     echo -en $GREEN_TEXT
#     read -p ">> How many parameters (in billions)? [0.5, 1.5, 7, 32, 72] " pc
#     echo -en $RESET_TEXT
#     pc=${pc:-0.5}  # Default to "0.5" if the user presses Enter
#     case $pc in
#         0.5 | 1.5 | 7 | 32 | 72) PARAM_B=$pc && break ;;
#         *)  echo ">>> Please answer in [0.5, 1.5, 7, 32, 72]." ;;
#     esac
# done

if [ "$CONNECT_TO_TESTNET" = true ]; then
    # Run modal_login server.
    echo "Please login to create an Ethereum Server Wallet"
    cd modal-login
    # Check if the yarn command exists; if not, install Yarn.
    # source ~/.bashrc

    # Node.js + NVM setup
    if ! command -v node > /dev/null 2>&1; then
        echo "Node.js not found. Installing NVM and latest Node.js..."
        export NVM_DIR="$HOME/.nvm"
        if [ ! -d "$NVM_DIR" ]; then
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
        fi
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
        nvm install node
    else
        echo "Node.js is already installed: $(node -v)"
    fi

    if ! command -v yarn > /dev/null 2>&1; then
        # Detect Ubuntu (including WSL Ubuntu) and install Yarn accordingly
        if grep -qi "ubuntu" /etc/os-release 2> /dev/null || uname -r | grep -qi "microsoft"; then
            echo "Detected Ubuntu or WSL Ubuntu. Installing Yarn via apt..."
            curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
            echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
            sudo apt update && sudo apt install -y yarn
        else
            echo "Yarn is not installed. Installing Yarn..."
            curl -o- -L https://yarnpkg.com/install.sh | sh
            echo 'export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH"' >> ~/.bashrc
            source ~/.bashrc
        fi
    fi
    yarn install
    yarn dev > /dev/null 2>&1 &

    install_cloudflared
    run_tunnel & 
    trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT

    SERVER_PID=$!  # Store the process ID
    echo "Started server process: $SERVER_PID"
    sleep 5

    curl -s "http://localhost:3000" > /dev/null

    # # Try to open the URL in the default browser
    # if open http://localhost:3000 2> /dev/null; then
    #     echo_green ">> Successfully opened http://localhost:3000 in your default browser."
    # else
    #     echo ">> Failed to open http://localhost:3000. Please open it manually."
    # fi

    cd ..

    if [ ! -f "${IDENTITY_PATH}" ]; then
        echo_green ">> Waiting for modal userData.json to be created..."
        while [ ! -f "modal-login/temp-data/userData.json" ]; do
            sleep 5  # Wait for 5 seconds before checking again
        done
        echo "Found userData.json. Proceeding..."

        ORG_ID=$(awk 'BEGIN { FS = "\"" } !/^[ \t]*[{}]/ { print $(NF - 1); exit }' modal-login/temp-data/userData.json)
        echo "Your ORG_ID is set to: $ORG_ID"

        # Wait until the API key is activated by the client
        echo "Waiting for API key to become activated..."
        while true; do
            STATUS=$(curl -s "http://localhost:3000/api/get-api-key-status?orgId=$ORG_ID")
            echo "API key status: $STATUS"
            if [[ "$STATUS" == "activated" ]]; then
                echo "API key is activated! Proceeding..."
                break
            else
                echo "Waiting for API key to be activated..."
                sleep 5
            fi
        done
    fi

    ENV_FILE="$ROOT"/modal-login/.env
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS version
        sed -i '' "3s/.*/SMART_CONTRACT_ADDRESS=$SWARM_CONTRACT/" "$ENV_FILE"
    else
        # Linux version
        sed -i "3s/.*/SMART_CONTRACT_ADDRESS=$SWARM_CONTRACT/" "$ENV_FILE"
    fi
fi

echo_green ">> Getting requirements..."
pip_install() {
    pip3 install --disable-pip-version-check -q -r "$1"
}

# echo_green ">> Getting requirements..."
# pip_install "$ROOT"/requirements-hivemind.txt
# pip_install "$ROOT"/requirements.txt

# pip install --upgrade pip
if [ -n "$CPU_ONLY" ] || ! command -v nvidia-smi &> /dev/null; then
    # CPU-only mode or no NVIDIA GPU found
    pip install -r "$ROOT"/requirements-cpu.txt
    CONFIG_PATH="$ROOT/hivemind_exp/configs/mac/grpo-qwen-2.5-0.5b-deepseek-r1.yaml" # TODO: Fix naming.
    GAME="gsm8k"
else
    # NVIDIA GPU found
    pip_install "$ROOT"/requirements-gpu.txt
    pip install flash-attn --no-build-isolation

    case "$PARAM_B" in
        32 | 72) CONFIG_PATH="$ROOT/hivemind_exp/configs/gpu/grpo-qwen-2.5-${PARAM_B}b-bnb-4bit-deepseek-r1.yaml" && break ;;
        0.5 | 1.5 | 7) CONFIG_PATH="$ROOT/hivemind_exp/configs/gpu/grpo-qwen-2.5-${PARAM_B}b-deepseek-r1.yaml" && break ;;
        *)  echo ">>> Please answer in [0.5, 1.5, 7, 32, 72]." ;;
    esac
    if [ "$USE_BIG_SWARM" = true ]; then
        GAME="dapo"
    else
        GAME="gsm8k"
    fi
fi

echo_green ">> Done!"

HUGGINGFACE_ACCESS_TOKEN=None
# HF_TOKEN=${HF_TOKEN:-""}
# if [ -n "${HF_TOKEN}" ]; then # Check if HF_TOKEN is already set and use if so. Else give user a prompt to choose.
#     HUGGINGFACE_ACCESS_TOKEN=${HF_TOKEN}
# else
#     echo -en $GREEN_TEXT
#     read -p ">> Would you like to push models you train in the RL swarm to the Hugging Face Hub? [y/N] " yn
#     echo -en $RESET_TEXT
#     yn=${yn:-N} # Default to "N" if the user presses Enter
#     case $yn in
#         [Yy]*) read -p "Enter your Hugging Face access token: " HUGGINGFACE_ACCESS_TOKEN ;;
#         [Nn]*) HUGGINGFACE_ACCESS_TOKEN="None" ;;
#         *) echo ">>> No answer was given, so NO models will be pushed to Hugging Face Hub" && HUGGINGFACE_ACCESS_TOKEN="None" ;;
#     esac
# fi

echo_green ">> Good luck in the swarm!"
echo_blue ">> Post about rl-swarm on X/twitter! --> https://tinyurl.com/swarmtweet"
echo_blue ">> And remember to star the repo on GitHub! --> https://github.com/gensyn-ai/rl-swarm"

ORG_ID=$(awk 'BEGIN { FS = "\"" } !/^[ \t]*[{}]/ { print $(NF - 1); exit }' modal-login/temp-data/userData.json)
echo "Your ORG_ID is set to: $ORG_ID"

function get_last_log {
    while true; do
        sleep 5m
        cat /root/logs/node_log.log | tail -40 > /root/logs/last_40.log
    done
}

get_last_log &
trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT

sed -i -E 's/(startup_timeout: *float *= *)[0-9.]+/\1120/' $(python -c "import hivemind.p2p.p2p_daemon as m; print(m.__file__)")
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

wait  # Keep script running until Ctrl+C
