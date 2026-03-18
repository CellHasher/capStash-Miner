#!/data/data/com.termux/files/usr/bin/bash
# CapStash Miner - Termux Install Script
# Usage: bash install.sh [--wallet-address <addr>] [--target <target>]
set -e

INSTALL_DIR="$HOME/capstash"
DATA_DIR="$HOME/capstash/data"
BIN_DIR="$HOME/capstash/bin"
REPO_URL="https://github.com/lukewrightmain/capstash-miner"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════╗"
echo "  ║       CapStash Miner Installer        ║"
echo "  ║         Termux / Android              ║"
echo "  ╚═══════════════════════════════════════╝"
echo -e "${NC}"

# ── Parse args ──────────────────────────────────────────
WALLET_ADDR=""
TARGET=""
THREADS=""
COINBASE_TAG="CellSwarm"
while [[ $# -gt 0 ]]; do
    case $1 in
        --wallet-address|--wallet|-w) WALLET_ADDR="$2"; shift 2;;
        --target|-t) TARGET="$2"; shift 2;;
        --threads|-j) THREADS="$2"; shift 2;;
        --tag) COINBASE_TAG="$2"; shift 2;;
        --help|-h)
            echo "Usage: bash install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -w, --wallet-address ADDR  Mining wallet address (shared across devices)"
            echo "  -t, --target TARGET        SoC target (e.g. sd888, tensor_g3, generic_v8)"
            echo "  -j, --threads N            Number of mining threads (default: all cores)"
            echo "      --tag TAG              Coinbase tag (default: CellSwarm)"
            echo "  -h, --help                 Show this help"
            echo ""
            echo "If --wallet-address is not provided, a new wallet will be created."
            echo "For phone clusters, generate a wallet on one device, then use that"
            echo "same address on all other devices with --wallet-address."
            exit 0;;
        *) echo "Unknown option: $1"; exit 1;;
    esac
done

# ── Detect SoC ──────────────────────────────────────────
detect_soc() {
    local soc=""
    # Try to read SoC from various Android sources
    if [ -f /sys/devices/soc0/soc_id ]; then
        soc=$(cat /sys/devices/soc0/soc_id 2>/dev/null)
    fi
    local hw=$(getprop ro.hardware 2>/dev/null || echo "")
    local board=$(getprop ro.board.platform 2>/dev/null || echo "")
    local chip=$(getprop ro.chipname 2>/dev/null || echo "")
    local model=$(getprop ro.product.model 2>/dev/null || echo "")
    local soc_model=$(getprop ro.soc.model 2>/dev/null || echo "")

    echo -e "${YELLOW}Detected hardware:${NC}" >&2
    [ -n "$hw" ] && echo "  Hardware:  $hw" >&2
    [ -n "$board" ] && echo "  Platform:  $board" >&2
    [ -n "$model" ] && echo "  Model:     $model" >&2
    [ -n "$soc_model" ] && echo "  SoC Model: $soc_model" >&2

    # Map known platforms to targets
    case "$board" in
        lahaina) echo "sd888";;       # SM8350
        taro) echo "sd8gen1";;        # SM8450
        kalama) echo "sd8gen2";;      # SM8550
        pineapple) echo "sd8gen3";;   # SM8650
        sun) echo "sd8elite";;        # SM8750
        kona) echo "sd865";;          # SM8250
        msmnile) echo "sd855";;       # SM8150
        sdm845) echo "sd845";;        # SDM845
        msm8998) echo "sd835";;       # MSM8998
        msm8996) echo "sd821";;       # MSM8996
        lito) echo "sd765";;          # SM7250
        gs101) echo "tensor_g1";;
        gs201) echo "tensor_g2";;
        zuma) echo "tensor_g3";;
        zumapro) echo "tensor_g4";;
        exynos850|exynos7904|exynos7885) echo "generic_v8";;
        exynos8895) echo "exynos8895";;
        exynos9810) echo "exynos9810";;
        exynos9820) echo "exynos9820";;
        exynos990) echo "exynos990";;
        exynos2100) echo "exynos2100";;
        exynos2200) echo "exynos2200";;
        exynos2400) echo "exynos2400";;
        mt6779|mt6771|mt6765) echo "helio_p60";;
        mt6885|mt6889) echo "dimensity1000";;
        mt6893) echo "dimensity1200";;
        mt6983) echo "dimensity9000";;
        mt6985) echo "dimensity9200";;
        *)
            # Try chip name
            case "$chip" in
                *SM8350*|*888*) echo "sd888";;
                *SM8250*|*865*) echo "sd865";;
                *SM8150*|*855*) echo "sd855";;
                *) echo "generic_v82";;  # Safe fallback
            esac
            ;;
    esac
}

# ── Auto-detect target if not specified ─────────────────
if [ -z "$TARGET" ]; then
    TARGET=$(detect_soc)
fi
echo -e "${GREEN}Target: $TARGET${NC}"

# ── Find pre-built binaries (fallback to generic_v82) ───
BINARY_SOURCE=""
for try_target in "$TARGET" "generic_v82" "generic_v8"; do
    if [ -f "$SCRIPT_DIR/../builds/$try_target/CapStashd" ]; then
        BINARY_SOURCE="$SCRIPT_DIR/../builds/$try_target"
        break
    elif [ -f "$SCRIPT_DIR/builds/$try_target/CapStashd" ]; then
        BINARY_SOURCE="$SCRIPT_DIR/builds/$try_target"
        break
    fi
done

if [ -n "$BINARY_SOURCE" ]; then
    echo -e "${GREEN}Using pre-built binary: $(basename "$BINARY_SOURCE")${NC}"
else
    echo -e "${YELLOW}No pre-built binary found. Building from source...${NC}"
fi

# ── Install dependencies (if building from source) ──────
if [ -z "$BINARY_SOURCE" ]; then
    echo -e "${CYAN}Installing build dependencies...${NC}"
    pkg update -y
    pkg install -y git clang make autoconf automake libtool pkg-config \
        python3 boost boost-headers libevent libsqlite
fi

# ── Create install dirs ─────────────────────────────────
mkdir -p "$INSTALL_DIR" "$DATA_DIR" "$BIN_DIR"

# ── Install binaries ────────────────────────────────────
if [ -n "$BINARY_SOURCE" ]; then
    echo -e "${CYAN}Installing pre-built binaries...${NC}"
    cp "$BINARY_SOURCE/CapStashd" "$BIN_DIR/"
    cp "$BINARY_SOURCE/CapStash-cli" "$BIN_DIR/"
    chmod +x "$BIN_DIR/CapStashd" "$BIN_DIR/CapStash-cli"
else
    echo -e "${CYAN}Building from source (this will take a while)...${NC}"
    BUILD_DIR="$INSTALL_DIR/build"
    rm -rf "$BUILD_DIR"
    git clone https://github.com/CapStash/CapStash-Core.git "$BUILD_DIR"
    cd "$BUILD_DIR"
    ./autogen.sh
    ./configure --without-gui --disable-tests --disable-bench --disable-fuzz-binary \
        --without-bdb CXX=clang++ CC=clang CXXFLAGS="-O2" \
        EVENT_CFLAGS=" " EVENT_PTHREADS_CFLAGS=" " SQLITE_CFLAGS=" "
    make -j$(nproc)
    cp src/CapStashd src/CapStash-cli "$BIN_DIR/"
    strip "$BIN_DIR/CapStashd" "$BIN_DIR/CapStash-cli"
    chmod +x "$BIN_DIR/CapStashd" "$BIN_DIR/CapStash-cli"
    rm -rf "$BUILD_DIR"
fi

echo -e "${GREEN}Binaries installed to $BIN_DIR${NC}"

# ── Copy config.json if present ─────────────────────────
for cfgpath in "$SCRIPT_DIR/../config.json" "$SCRIPT_DIR/config.json"; do
    if [ -f "$cfgpath" ]; then
        cp "$cfgpath" "$INSTALL_DIR/config.json"
        echo -e "${GREEN}Copied config.json to $INSTALL_DIR/${NC}"
        # If wallet address was passed via CLI, patch it into config.json
        if [ -n "$WALLET_ADDR" ]; then
            python3 -c "
import json
with open('$INSTALL_DIR/config.json') as f: c=json.load(f)
c['wallet_address']='$WALLET_ADDR'
with open('$INSTALL_DIR/config.json','w') as f: json.dump(c,f,indent=4)
" 2>/dev/null || true
        fi
        break
    fi
done
# Copy launcher scripts
for f in launcher.sh launcher.py; do
    [ -f "$SCRIPT_DIR/$f" ] && cp "$SCRIPT_DIR/$f" "$INSTALL_DIR/$f" && chmod +x "$INSTALL_DIR/$f"
done

# ── Generate config ─────────────────────────────────────
RPCPASS=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)
cat > "$DATA_DIR/CapStash.conf" << CONF
# CapStash Miner Configuration
server=1
daemon=1
rpcuser=miner
rpcpassword=$RPCPASS
rpcallowip=127.0.0.1
rpcbind=127.0.0.1
listen=1
txindex=0
dbcache=256
maxmempool=50
CONF

echo -e "${GREEN}Config written to $DATA_DIR/CapStash.conf${NC}"

# ── Wallet setup ────────────────────────────────────────
if [ -n "$WALLET_ADDR" ]; then
    echo -e "${GREEN}Wallet: $WALLET_ADDR${NC}"
    MINING_ADDR="$WALLET_ADDR"
else
    echo "No wallet address provided — generating one..."

    # Start daemon temporarily
    "$BIN_DIR/CapStashd" -datadir="$DATA_DIR" -daemon 2>/dev/null
    sleep 5

    CLI="$BIN_DIR/CapStash-cli -datadir=$DATA_DIR"
    # Wait for RPC
    for i in $(seq 1 30); do
        if $CLI getblockchaininfo >/dev/null 2>&1; then
            break
        fi
        sleep 2
    done

    # Create wallet and address
    $CLI createwallet "miner" >/dev/null 2>&1
    MINING_ADDR=$($CLI -rpcwallet=miner getnewaddress "mining" 2>/dev/null)

    # Stop daemon
    $CLI stop >/dev/null 2>&1
    sleep 3

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  YOUR MINING WALLET ADDRESS:                         ║${NC}"
    echo -e "${GREEN}║                                                      ║${NC}"
    echo -e "${YELLOW}  $MINING_ADDR${NC}"
    echo -e "${GREEN}║                                                      ║${NC}"
    echo -e "${GREEN}║  SAVE THIS ADDRESS! Use it on all other devices:     ║${NC}"
    echo -e "${GREEN}║  bash install.sh --wallet-address $MINING_ADDR${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
fi

# ── Save mining config ──────────────────────────────────
THREADS_FLAG="${THREADS:--1}"
cat > "$INSTALL_DIR/miner.conf" << MCONF
MINING_ADDR=$MINING_ADDR
THREADS=$THREADS_FLAG
COINBASE_TAG=$COINBASE_TAG
TARGET=$TARGET
MCONF

# ── Create convenience scripts ──────────────────────────
# run.sh — reads config.json, starts daemon, syncs, mines, shows live hashrate
cat > "$INSTALL_DIR/run.sh" << 'RUNSCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
# If capstash-mine CLI exists, use it (reads config.json, shows live stats)
if [ -f "$HOME/capstash/capstash-mine" ]; then
    exec bash "$HOME/capstash/capstash-mine" start
fi

# Fallback: inline version that reads config.json
INSTALL_DIR="$HOME/capstash"
BIN_DIR="$INSTALL_DIR/bin"
DATA_DIR="$INSTALL_DIR/data"
CLI="$BIN_DIR/CapStash-cli -datadir=$DATA_DIR"
CONFIG="$INSTALL_DIR/config.json"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

# Read config.json, fall back to miner.conf
if [ -f "$CONFIG" ] && command -v python3 >/dev/null 2>&1; then
    WALLET=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('wallet_address',''))" 2>/dev/null)
    THREADS=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('threads',-1))" 2>/dev/null)
    WORKER=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('worker_name',''))" 2>/dev/null)
    TAG=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('coinbase_tag','CellSwarm'))" 2>/dev/null)
    DBCACHE=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('dbcache',256))" 2>/dev/null)
    MAXMEMPOOL=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('maxmempool',50))" 2>/dev/null)
elif [ -f "$INSTALL_DIR/miner.conf" ]; then
    source "$INSTALL_DIR/miner.conf"
    WALLET="$MINING_ADDR"
    TAG="$COINBASE_TAG"
fi

[ -z "$WALLET" ] && { echo "Error: No wallet address in config.json or miner.conf"; exit 1; }
[ -z "$WORKER" ] && WORKER=$(getprop ro.product.model 2>/dev/null | tr ' ' '-' || echo "phone")

echo -e "${CYAN}CapStash Miner${NC}"
echo "  Wallet:  $WALLET"
echo "  Worker:  $WORKER"
echo ""

# Write CapStash.conf from config
mkdir -p "$DATA_DIR"
if [ ! -f "$DATA_DIR/CapStash.conf" ]; then
    RPCPASS=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)
    cat > "$DATA_DIR/CapStash.conf" << CONF
server=1
daemon=1
rpcuser=miner
rpcpassword=$RPCPASS
rpcallowip=127.0.0.1
rpcbind=127.0.0.1
listen=1
dbcache=${DBCACHE:-256}
maxmempool=${MAXMEMPOOL:-50}
CONF
fi

# Start daemon
if ! $CLI getblockchaininfo >/dev/null 2>&1; then
    echo -ne "${YELLOW}Starting daemon...${NC} "
    "$BIN_DIR/CapStashd" -datadir="$DATA_DIR" -daemon
    for i in $(seq 1 60); do
        $CLI getblockchaininfo >/dev/null 2>&1 && break
        sleep 2
    done
    if $CLI getblockchaininfo >/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo "FAILED — check $DATA_DIR/debug.log"
        exit 1
    fi
else
    echo -e "${GREEN}Daemon running.${NC}"
fi

# Sync
echo "Syncing..."
while true; do
    INFO=$($CLI getblockchaininfo 2>/dev/null) || { sleep 5; continue; }
    IBD=$(echo "$INFO" | grep initialblockdownload | grep -c true)
    [ "$IBD" = "0" ] && break
    BLOCKS=$(echo "$INFO" | grep '"blocks"' | head -1 | tr -dc '0-9')
    HEADERS=$(echo "$INFO" | grep '"headers"' | head -1 | tr -dc '0-9')
    [ -n "$HEADERS" ] && [ "$HEADERS" -gt 0 ] 2>/dev/null && \
        echo -ne "\r  ${YELLOW}$BLOCKS / $HEADERS ($(( BLOCKS * 100 / HEADERS ))%)${NC}   "
    sleep 5
done
echo -e "\n${GREEN}Synced!${NC}"

# Start mining
echo -e "${CYAN}Starting miner...${NC}"
$CLI setgenerate true ${THREADS:--1} "$WALLET" "${TAG:-CellSwarm}" >/dev/null 2>&1

echo ""
echo -e "${GREEN}Mining! Ctrl+C to detach (miner keeps running)${NC}"
echo ""

# Live hashrate display
while true; do
    INFO=$($CLI getmininginfo 2>/dev/null) || { sleep 5; continue; }
    CHAIN=$($CLI getblockchaininfo 2>/dev/null) || { sleep 5; continue; }
    HR=$(echo "$INFO" | grep '"localhashps"' | head -1 | sed 's/[^0-9.]//g')
    THRDS=$(echo "$INFO" | grep '"threads"' | head -1 | tr -dc '0-9')
    FOUND=$(echo "$INFO" | grep '"localblocksfound"' | head -1 | tr -dc '0-9')
    DIFF=$(echo "$INFO" | grep '"difficulty"' | head -1 | sed 's/[^0-9.]//g')
    BLOCKS=$(echo "$CHAIN" | grep '"blocks"' | head -1 | tr -dc '0-9')
    BEST=$(echo "$INFO" | grep '"bestlocaldiffhit"' | head -1 | sed 's/[^0-9.]//g')
    HR_MHS=$(echo "$HR" | awk '{printf "%.2f", $1/1000000}')
    NOW=$(date '+%H:%M:%S')
    echo -ne "\r  ${DIM}$NOW${NC}  ${GREEN}${HR_MHS} MH/s${NC}  ${THRDS}T  blk:$BLOCKS  found:${GREEN}$FOUND${NC}  diff:$DIFF  best:$BEST   "
    sleep 10
done
RUNSCRIPT
chmod +x "$INSTALL_DIR/run.sh"

# status.sh
cat > "$INSTALL_DIR/status.sh" << 'STATUSSCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
CLI="$HOME/capstash/bin/CapStash-cli -datadir=$HOME/capstash/data"
echo "=== CapStash Miner Status ==="
INFO=$($CLI getmininginfo 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "Daemon not running. Start with: bash ~/capstash/run.sh"
    exit 1
fi
BLOCKS=$($CLI getblockchaininfo 2>/dev/null | grep '"blocks"' | head -1 | tr -dc '0-9')
HEADERS=$($CLI getblockchaininfo 2>/dev/null | grep '"headers"' | head -1 | tr -dc '0-9')
CONNS=$($CLI getnetworkinfo 2>/dev/null | grep '"connections"' | head -1 | tr -dc '0-9')
MINING=$(echo "$INFO" | grep '"mining"' | grep -c true)
HASHRATE=$(echo "$INFO" | grep '"localhashps"' | head -1 | sed 's/[^0-9.]//g')
THREADS=$(echo "$INFO" | grep '"threads"' | head -1 | tr -dc '0-9')
FOUND=$(echo "$INFO" | grep '"localblocksfound"' | head -1 | tr -dc '0-9')
DIFF=$(echo "$INFO" | grep '"difficulty"' | head -1 | sed 's/[^0-9.]//g')
source "$HOME/capstash/miner.conf" 2>/dev/null
HR_MHS=$(echo "$HASHRATE" | awk '{printf "%.2f", $1/1000000}')
echo "  Chain:      $BLOCKS / $HEADERS blocks"
echo "  Peers:      $CONNS connections"
echo "  Mining:     $([ "$MINING" = "1" ] && echo "YES" || echo "NO") ($THREADS threads)"
echo "  Hashrate:   ${HR_MHS} MH/s"
echo "  Difficulty:  $DIFF"
echo "  Blocks found: $FOUND"
echo "  Address:    ${MINING_ADDR:-unknown}"
echo "  Target:     ${TARGET:-unknown}"
STATUSSCRIPT
chmod +x "$INSTALL_DIR/status.sh"

# stop.sh
cat > "$INSTALL_DIR/stop.sh" << 'STOPSCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
CLI="$HOME/capstash/bin/CapStash-cli -datadir=$HOME/capstash/data"
echo "Stopping miner..."
$CLI setgenerate false 2>/dev/null
echo "Stopping daemon..."
$CLI stop 2>/dev/null
echo "Stopped."
STOPSCRIPT
chmod +x "$INSTALL_DIR/stop.sh"

# ── Install CLI tool ────────────────────────────────────
for src in "$SCRIPT_DIR/capstash-mine" "$SCRIPT_DIR/../scripts/capstash-mine"; do
    if [ -f "$src" ]; then
        cp "$src" "$INSTALL_DIR/capstash-mine"
        chmod +x "$INSTALL_DIR/capstash-mine"
        # Symlink to PATH so it works as a command
        mkdir -p "$HOME/.local/bin" 2>/dev/null
        ln -sf "$INSTALL_DIR/capstash-mine" "$HOME/.local/bin/capstash-mine" 2>/dev/null
        # Also try Termux bin
        ln -sf "$INSTALL_DIR/capstash-mine" "$PREFIX/bin/capstash-mine" 2>/dev/null || true
        break
    fi
done

echo ""
echo -e "${GREEN}═══ Installation Complete ═══${NC}"
echo ""
echo "  Install dir:  $INSTALL_DIR"
echo "  Target:       $TARGET"
echo "  Address:      $MINING_ADDR"
echo ""
echo "  Commands:"
echo -e "    ${GREEN}capstash-mine${NC}            Start mining + live hashrate"
echo -e "    ${GREEN}capstash-mine status${NC}     Show stats"
echo -e "    ${GREEN}capstash-mine stop${NC}       Stop mining"
echo -e "    ${GREEN}capstash-mine watch${NC}      Live hashrate monitor"
echo -e "    ${GREEN}capstash-mine shutdown${NC}   Stop everything"
echo -e "    ${GREEN}capstash-mine help${NC}       All commands"
echo ""
echo "  Config: ~/capstash/config.json"
echo ""
echo -e "${YELLOW}  For clusters: use the same --wallet-address on every device!${NC}"
echo ""
