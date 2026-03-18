#!/data/data/com.termux/files/usr/bin/bash
# CapStash Miner Launcher — reads config.json, starts daemon + miner
# Place config.json next to the binary or in ~/capstash/
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

INSTALL_DIR="$HOME/capstash"
BIN_DIR="$INSTALL_DIR/bin"
DATA_DIR="$INSTALL_DIR/data"

# ── Find config.json ─────────────────────────────────────
CONFIG=""
for path in \
    "$INSTALL_DIR/config.json" \
    "$BIN_DIR/config.json" \
    "$(dirname "$0")/../config.json" \
    "$(dirname "$0")/config.json" \
    "./config.json"; do
    if [ -f "$path" ]; then
        CONFIG="$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
        break
    fi
done

if [ -z "$CONFIG" ]; then
    echo -e "${RED}Error: config.json not found.${NC}"
    echo "Place config.json in one of:"
    echo "  ~/capstash/config.json"
    echo "  ~/capstash/bin/config.json"
    echo "  ./config.json"
    exit 1
fi

echo -e "${CYAN}CapStash Miner${NC}"
echo "  Config: $CONFIG"

# ── Parse config.json ─────────────────────────────────────
# Minimal JSON parser using python3 (available on all Termux installs)
parse_json() {
    python3 -c "
import json, sys
with open('$CONFIG') as f:
    c = json.load(f)
print(c.get('$1', '$2'))
" 2>/dev/null
}

parse_json_list() {
    python3 -c "
import json
with open('$CONFIG') as f:
    c = json.load(f)
v = c.get('$1', [])
if isinstance(v, list):
    print('\n'.join(str(x) for x in v))
" 2>/dev/null
}

WALLET=$(parse_json wallet_address "")
THREADS=$(parse_json threads "-1")
WORKER=$(parse_json worker_name "")
TAG=$(parse_json coinbase_tag "CellSwarm")
TARGET=$(parse_json target "auto")
RPC_PORT=$(parse_json rpc_port "8332")
RPC_USER=$(parse_json rpc_user "miner")
RPC_PASS=$(parse_json rpc_password "")
MAX_CONN=$(parse_json max_connections "16")
DBCACHE=$(parse_json dbcache "256")
MAXMEMPOOL=$(parse_json maxmempool "50")
LISTEN=$(parse_json listen "true")
TXINDEX=$(parse_json txindex "false")
AUTOSTART=$(parse_json autostart "true")

# ── Validate wallet address ──────────────────────────────
if [ -z "$WALLET" ]; then
    echo ""
    echo -e "${RED}Error: wallet_address is empty in config.json${NC}"
    echo ""
    echo "You need a wallet address to mine to. Options:"
    echo ""
    echo -e "  ${GREEN}1. Generate one on this device:${NC}"
    echo "     bash scripts/install.sh"
    echo "     (it will print the address)"
    echo ""
    echo -e "  ${GREEN}2. Use an address from another device:${NC}"
    echo '     Edit config.json and set "wallet_address": "cap1q..."'
    echo ""
    echo "The wallet address is just a payout destination."
    echo "No wallet needs to exist on this device."
    exit 1
fi

# ── Set worker name from hostname if not specified ────────
if [ -z "$WORKER" ]; then
    WORKER=$(getprop ro.product.model 2>/dev/null | tr ' ' '-' || hostname || echo "phone")
fi

# ── Generate RPC password if empty ────────────────────────
if [ -z "$RPC_PASS" ]; then
    RPC_PASS=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)
fi

echo "  Wallet:  $WALLET"
echo "  Threads: $THREADS"
echo "  Worker:  $WORKER"
echo "  Tag:     $TAG"
echo "  Target:  $TARGET"
echo ""

# ── Create data dir and config ────────────────────────────
mkdir -p "$DATA_DIR"

LISTEN_FLAG=1
[ "$LISTEN" = "false" ] && LISTEN_FLAG=0
TXINDEX_FLAG=0
[ "$TXINDEX" = "true" ] && TXINDEX_FLAG=1

# Build CapStash.conf
cat > "$DATA_DIR/CapStash.conf" << CONF
server=1
daemon=1
rpcuser=$RPC_USER
rpcpassword=$RPC_PASS
rpcallowip=127.0.0.1
rpcbind=127.0.0.1
rpcport=$RPC_PORT
listen=$LISTEN_FLAG
txindex=$TXINDEX_FLAG
dbcache=$DBCACHE
maxmempool=$MAXMEMPOOL
maxconnections=$MAX_CONN
CONF

# Add custom nodes
while IFS= read -r node; do
    [ -n "$node" ] && echo "addnode=$node" >> "$DATA_DIR/CapStash.conf"
done <<< "$(parse_json_list addnodes)"

# ── Save miner.conf for status.sh compatibility ──────────
cat > "$INSTALL_DIR/miner.conf" << MCONF
MINING_ADDR=$WALLET
THREADS=$THREADS
COINBASE_TAG=$TAG
TARGET=$TARGET
WORKER=$WORKER
MCONF

# ── Ensure binaries exist ────────────────────────────────
if [ ! -f "$BIN_DIR/CapStashd" ]; then
    echo -e "${RED}Error: CapStashd not found at $BIN_DIR${NC}"
    echo "Run install.sh first, or copy the binary for your target to $BIN_DIR/"
    exit 1
fi

CLI="$BIN_DIR/CapStash-cli -datadir=$DATA_DIR"

# ── Start daemon ─────────────────────────────────────────
if ! $CLI getblockchaininfo >/dev/null 2>&1; then
    echo -e "${YELLOW}Starting daemon...${NC}"
    "$BIN_DIR/CapStashd" -datadir="$DATA_DIR" -daemon
    for i in $(seq 1 60); do
        if $CLI getblockchaininfo >/dev/null 2>&1; then
            echo -e "${GREEN}Daemon ready.${NC}"
            break
        fi
        sleep 2
    done
    if ! $CLI getblockchaininfo >/dev/null 2>&1; then
        echo -e "${RED}Daemon failed to start. Check: $DATA_DIR/debug.log${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}Daemon already running.${NC}"
fi

# ── Wait for sync ────────────────────────────────────────
echo "Syncing blockchain..."
while true; do
    INFO=$($CLI getblockchaininfo 2>/dev/null) || { sleep 5; continue; }
    IBD=$(echo "$INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('initialblockdownload',True))" 2>/dev/null)
    if [ "$IBD" = "False" ]; then
        echo -e "\n${GREEN}Chain synced!${NC}"
        break
    fi
    BLOCKS=$(echo "$INFO" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f\"{d['blocks']}/{d['headers']} ({d['verificationprogress']*100:.1f}%)\")" 2>/dev/null)
    echo -ne "\r  Sync: $BLOCKS   "
    sleep 10
done

# ── Start mining ─────────────────────────────────────────
if [ "$AUTOSTART" = "true" ] || [ "$AUTOSTART" = "True" ]; then
    echo -e "${CYAN}Starting miner...${NC}"
    RESULT=$($CLI setgenerate true $THREADS "$WALLET" "$TAG" 2>&1)
    MINING=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('mining',False))" 2>/dev/null)
    NTHREADS=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('threads',0))" 2>/dev/null)
    echo -e "${GREEN}Mining: $NTHREADS threads -> $WALLET${NC}"
    echo "  Worker: $WORKER"
    echo "  Tag:    $TAG"
else
    echo -e "${YELLOW}autostart=false — chain synced but miner not started.${NC}"
    echo "To start manually: $CLI setgenerate true $THREADS \"$WALLET\" \"$TAG\""
fi

echo ""
echo "  Status:  bash ~/capstash/status.sh"
echo "  Stop:    bash ~/capstash/stop.sh"
