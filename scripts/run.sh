#!/data/data/com.termux/files/usr/bin/bash
# CapStash Miner - Run Script
# Reads config from ~/capstash/config.json, starts daemon, waits for sync, starts mining

set -e

INSTALL_DIR="$HOME/capstash"
DATA_DIR="$INSTALL_DIR/data"
BIN_DIR="$INSTALL_DIR/bin"
CONFIG_JSON="$INSTALL_DIR/config.json"

CLI="$BIN_DIR/CapStash-cli -datadir=$DATA_DIR"
DAEMON="$BIN_DIR/CapStashd -datadir=$DATA_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# ---------- helpers ----------

find_python() {
    if command -v python3 >/dev/null 2>&1; then
        echo "python3"
        return 0
    fi
    if command -v python >/dev/null 2>&1; then
        echo "python"
        return 0
    fi
    return 1
}

trim() {
    local var="$1"
    # trim leading
    var="${var#"${var%%[![:space:]]*}"}"
    # trim trailing
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s' "$var"
}

# ---------- load config.json ----------

if [ ! -f "$CONFIG_JSON" ]; then
    echo -e "${RED}Error: config.json not found at $CONFIG_JSON${NC}"
    exit 1
fi

PYTHON_BIN="$(find_python || true)"
if [ -z "$PYTHON_BIN" ]; then
    echo -e "${RED}Error: python3/python not found. Cannot parse config.json${NC}"
    exit 1
fi

PARSED_CONFIG="$("$PYTHON_BIN" - "$CONFIG_JSON" <<'PY'
import json, sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    cfg = json.load(f)

wallet_address = str(cfg.get("wallet_address", "") or "").strip()
threads = cfg.get("threads", -1)
coinbase_tag = str(cfg.get("coinbase_tag", "CellSwarm") or "CellSwarm").strip()
target = str(cfg.get("target", "auto") or "auto").strip()

print(f"MINING_ADDR={wallet_address}")
print(f"THREADS={threads}")
print(f"COINBASE_TAG={coinbase_tag}")
print(f"TARGET={target}")
PY
)"

# shell-safe-ish parse because values are simple
MINING_ADDR="$(printf '%s\n' "$PARSED_CONFIG" | sed -n 's/^MINING_ADDR=//p' | head -n1)"
THREADS="$(printf '%s\n' "$PARSED_CONFIG" | sed -n 's/^THREADS=//p' | head -n1)"
COINBASE_TAG="$(printf '%s\n' "$PARSED_CONFIG" | sed -n 's/^COINBASE_TAG=//p' | head -n1)"
TARGET="$(printf '%s\n' "$PARSED_CONFIG" | sed -n 's/^TARGET=//p' | head -n1)"

MINING_ADDR="$(trim "$MINING_ADDR")"
THREADS="$(trim "$THREADS")"
COINBASE_TAG="$(trim "$COINBASE_TAG")"
TARGET="$(trim "$TARGET")"

# defaults / validation
[ -z "$COINBASE_TAG" ] && COINBASE_TAG="CellSwarm"
[ -z "$TARGET" ] && TARGET="auto"
[ -z "$THREADS" ] && THREADS="-1"

if [ -z "$MINING_ADDR" ]; then
    echo -e "${RED}wallet_address is empty in config.json${NC}"
    exit 1
fi

case "$THREADS" in
    ''|*[!0-9-]*)
        echo -e "${RED}Invalid threads value in config.json: '$THREADS'${NC}"
        exit 1
        ;;
esac

echo -e "${CYAN}CapStash Miner${NC}"
echo "  Address: $MINING_ADDR"
echo "  Target:  $TARGET"
echo "  Threads: $THREADS"
echo ""

# ---------- start daemon if not running ----------

if ! $CLI getblockchaininfo >/dev/null 2>&1; then
    echo -e "${YELLOW}Starting daemon...${NC}"
    $DAEMON -daemon

    echo "Waiting for RPC..."
    for i in $(seq 1 60); do
        if $CLI getblockchaininfo >/dev/null 2>&1; then
            echo -e "${GREEN}Daemon started.${NC}"
            break
        fi
        sleep 2
    done

    if ! $CLI getblockchaininfo >/dev/null 2>&1; then
        echo -e "${RED}Error: Daemon failed to start. Check logs in $DATA_DIR/debug.log${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}Daemon already running.${NC}"
fi

# ---------- wait for sync ----------

while true; do
    INFO="$($CLI getblockchaininfo 2>/dev/null || true)"

    if [ -z "$INFO" ]; then
        echo -ne "\rWaiting for blockchain info...   "
        sleep 5
        continue
    fi

    IBD="$(echo "$INFO" | grep initialblockdownload | grep -c true || true)"
    if [ "$IBD" = "0" ]; then
        echo -e "${GREEN}Chain synced!${NC}"
        break
    fi

    BLOCKS="$(echo "$INFO" | grep '"blocks"' | tr -dc '0-9')"
    HEADERS="$(echo "$INFO" | grep '"headers"' | tr -dc '0-9')"

    if [ -n "$HEADERS" ] && [ "$HEADERS" -gt 0 ] 2>/dev/null; then
        PCT=$((BLOCKS * 100 / HEADERS))
        echo -ne "\rSyncing: $BLOCKS / $HEADERS blocks ($PCT%)   "
    else
        echo -ne "\rSyncing blockchain...   "
    fi

    sleep 10
done

# ---------- start mining ----------

echo ""
echo -e "${CYAN}Starting miner...${NC}"
RESULT="$($CLI setgenerate true "$THREADS" "$MINING_ADDR" "$COINBASE_TAG" 2>&1 || true)"
echo "$RESULT"

# ---------- show status ----------
echo ""
bash "$INSTALL_DIR/status.sh" 2>/dev/null || true
echo ""
echo -e "${GREEN}Miner is running in the background.${NC}"
echo "  Check status: bash ~/capstash/status.sh"
echo "  Stop:         bash ~/capstash/stop.sh"
