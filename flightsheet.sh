#!/data/data/com.termux/files/usr/bin/bash
# ══════════════════════════════════════════════════════════
#  CapStash Miner Flightsheet
#
#  One-shot setup + run. No SSH, no server, no cluster.
#  Just paste this into Termux on any Android phone.
#
#  curl -sL https://raw.githubusercontent.com/lukewrightmain/capstash-miner/main/flightsheet.sh | bash
#
#  Or clone and run:
#  git clone https://github.com/lukewrightmain/capstash-miner.git && bash capstash-miner/flightsheet.sh
# ══════════════════════════════════════════════════════════

# ┌─────────────────────────────────────────────────────┐
# │  EDIT THESE — your flightsheet config               │
# └─────────────────────────────────────────────────────┘

WALLET=""                                                 # <-- SET YOUR WALLET ADDRESS HERE
THREADS=-1                                                # -1 = all cores
WORKER=""                                                 # leave empty = auto (device model)
TAG="CellSwarm"                                           # coinbase tag in mined blocks
TARGET="auto"                                             # auto-detect SoC, or: sd888, generic_v82, etc.

# SECURITY NOTE:
# The wallet address is PUBLIC — it's safe to share. Anyone who mines
# with your address is mining coins FOR YOU. They cannot access or
# spend your coins. Only the device with the wallet file (private keys)
# can spend coins. The wallet file lives at ~/capstash/data/wallets/
# and is only created on the first device that runs install.sh without
# --wallet-address.

# ┌─────────────────────────────────────────────────────┐
# │  Everything below is automatic                      │
# └─────────────────────────────────────────────────────┘

set -e
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

INSTALL_DIR="$HOME/capstash"
BIN_DIR="$INSTALL_DIR/bin"
DATA_DIR="$INSTALL_DIR/data"
REPO_DIR="$HOME/capstash-miner"

echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════╗"
echo "  ║     CapStash Miner Flightsheet        ║"
echo "  ╚═══════════════════════════════════════╝"
echo -e "${NC}"

# ── Validate wallet ─────────────────────────────────────
if [ -z "$WALLET" ] || [ "$WALLET" = "cap1qYOUR_ADDRESS_HERE" ]; then
    echo -e "${RED}ERROR: Set your wallet address at the top of this script!${NC}"
    echo "Edit the WALLET= line, then re-run."
    exit 1
fi

echo "  Wallet:  $WALLET"
echo "  Threads: $THREADS"
echo "  Tag:     $TAG"
echo "  Target:  $TARGET"
echo ""

# ── Auto-detect SoC ────────────────────────────────────
detect_target() {
    local board=$(getprop ro.board.platform 2>/dev/null || echo "")
    case "$board" in
        lahaina) echo "sd888";;
        taro) echo "sd8gen1";;
        kalama) echo "sd8gen2";;
        pineapple) echo "sd8gen3";;
        sun) echo "sd8elite";;
        kona) echo "sd865";;
        msmnile) echo "sd855";;
        sdm845) echo "sd845";;
        msm8998) echo "sd835";;
        msm8996) echo "sd821";;
        lito) echo "sd765";;
        gs101) echo "tensor_g1";;
        gs201) echo "tensor_g2";;
        zuma) echo "tensor_g3";;
        zumapro) echo "tensor_g4";;
        exynos2100) echo "exynos2100";;
        exynos2200) echo "exynos2200";;
        exynos2400) echo "exynos2400";;
        exynos990) echo "exynos990";;
        exynos9820) echo "exynos9820";;
        exynos9810) echo "exynos9810";;
        exynos8895) echo "exynos8895";;
        mt6893) echo "dimensity1200";;
        mt6983) echo "dimensity9000";;
        mt6985) echo "dimensity9200";;
        *) echo "generic_v82";;
    esac
}

if [ "$TARGET" = "auto" ]; then
    TARGET=$(detect_target)
    echo -e "${GREEN}Detected SoC target: $TARGET${NC}"
fi

if [ -z "$WORKER" ]; then
    WORKER=$(getprop ro.product.model 2>/dev/null | tr ' ' '-' || echo "phone")
    echo "  Worker:  $WORKER"
fi

# ── Install if needed ───────────────────────────────────
if [ -f "$BIN_DIR/CapStashd" ]; then
    echo -e "${GREEN}Already installed.${NC}"
else
    echo -e "${YELLOW}Installing...${NC}"

    # Clone repo if not present
    if [ ! -d "$REPO_DIR" ]; then
        pkg install -y git 2>/dev/null || true
        git clone https://github.com/lukewrightmain/capstash-miner.git "$REPO_DIR"
    fi

    # Check for pre-built binary
    if [ -f "$REPO_DIR/builds/$TARGET/CapStashd" ]; then
        mkdir -p "$BIN_DIR"
        cp "$REPO_DIR/builds/$TARGET/CapStashd" "$BIN_DIR/"
        cp "$REPO_DIR/builds/$TARGET/CapStash-cli" "$BIN_DIR/"
        chmod +x "$BIN_DIR/CapStashd" "$BIN_DIR/CapStash-cli"
        echo -e "${GREEN}Installed pre-built binary for $TARGET${NC}"
    else
        echo -e "${YELLOW}No pre-built for $TARGET, trying generic_v82...${NC}"
        TARGET="generic_v82"
        mkdir -p "$BIN_DIR"
        cp "$REPO_DIR/builds/$TARGET/CapStashd" "$BIN_DIR/"
        cp "$REPO_DIR/builds/$TARGET/CapStash-cli" "$BIN_DIR/"
        chmod +x "$BIN_DIR/CapStashd" "$BIN_DIR/CapStash-cli"
    fi
fi

# ── Write config ────────────────────────────────────────
mkdir -p "$DATA_DIR"

RPCPASS=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)

cat > "$DATA_DIR/CapStash.conf" << CONF
server=1
daemon=1
rpcuser=miner
rpcpassword=$RPCPASS
rpcallowip=127.0.0.1
rpcbind=127.0.0.1
listen=1
dbcache=256
maxmempool=50
CONF

cat > "$INSTALL_DIR/miner.conf" << MCONF
MINING_ADDR=$WALLET
THREADS=$THREADS
COINBASE_TAG=$TAG
TARGET=$TARGET
WORKER=$WORKER
MCONF

# ── Write config.json ──────────────────────────────────
cat > "$INSTALL_DIR/config.json" << CJSON
{
    "wallet_address": "$WALLET",
    "threads": $THREADS,
    "worker_name": "$WORKER",
    "coinbase_tag": "$TAG",
    "target": "$TARGET",
    "autostart": true
}
CJSON

# ── Copy helper scripts ────────────────────────────────
if [ -d "$REPO_DIR/scripts" ]; then
    for f in launcher.sh launcher.py; do
        [ -f "$REPO_DIR/scripts/$f" ] && cp "$REPO_DIR/scripts/$f" "$INSTALL_DIR/$f" 2>/dev/null
    done
fi

# ── Write status.sh ─────────────────────────────────────
cat > "$INSTALL_DIR/status.sh" << 'STATUSSCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
CLI="$HOME/capstash/bin/CapStash-cli -datadir=$HOME/capstash/data"
INFO=$($CLI getmininginfo 2>/dev/null)
if [ $? -ne 0 ]; then echo "Daemon not running."; exit 1; fi
source "$HOME/capstash/miner.conf" 2>/dev/null
BLOCKS=$($CLI getblockchaininfo 2>/dev/null | grep '"blocks"' | head -1 | tr -dc '0-9')
HEADERS=$($CLI getblockchaininfo 2>/dev/null | grep '"headers"' | head -1 | tr -dc '0-9')
CONNS=$($CLI getnetworkinfo 2>/dev/null | grep '"connections"' | head -1 | tr -dc '0-9')
MINING=$(echo "$INFO" | grep '"mining"' | grep -c true)
HR=$(echo "$INFO" | grep '"localhashps"' | head -1 | sed 's/[^0-9.]//g')
THRDS=$(echo "$INFO" | grep '"threads"' | head -1 | tr -dc '0-9')
FOUND=$(echo "$INFO" | grep '"localblocksfound"' | head -1 | tr -dc '0-9')
HR_MHS=$(echo "$HR" | awk '{printf "%.2f", $1/1000000}')
echo "=== CapStash Miner ==="
echo "  Chain:    $BLOCKS / $HEADERS"
echo "  Peers:    $CONNS"
echo "  Mining:   $([ "$MINING" = "1" ] && echo "YES" || echo "NO") ($THRDS threads)"
echo "  Hashrate: ${HR_MHS} MH/s"
echo "  Found:    $FOUND blocks"
echo "  Worker:   ${WORKER:-$TARGET}"
echo "  Address:  $MINING_ADDR"
STATUSSCRIPT
chmod +x "$INSTALL_DIR/status.sh"

# ── Write stop.sh ───────────────────────────────────────
cat > "$INSTALL_DIR/stop.sh" << 'STOPSCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
CLI="$HOME/capstash/bin/CapStash-cli -datadir=$HOME/capstash/data"
$CLI setgenerate false 2>/dev/null; $CLI stop 2>/dev/null; echo "Stopped."
STOPSCRIPT
chmod +x "$INSTALL_DIR/stop.sh"

# ── Install CLI tool ────────────────────────────────────
if [ -f "$REPO_DIR/scripts/capstash-mine" ]; then
    cp "$REPO_DIR/scripts/capstash-mine" "$INSTALL_DIR/capstash-mine"
    chmod +x "$INSTALL_DIR/capstash-mine"
    ln -sf "$INSTALL_DIR/capstash-mine" "$PREFIX/bin/capstash-mine" 2>/dev/null || true
fi

CLI="$BIN_DIR/CapStash-cli -datadir=$DATA_DIR"

# ── Start daemon ────────────────────────────────────────
if ! $CLI getblockchaininfo >/dev/null 2>&1; then
    echo -e "${YELLOW}Starting daemon...${NC}"
    "$BIN_DIR/CapStashd" -datadir="$DATA_DIR" -daemon
    for i in $(seq 1 60); do
        $CLI getblockchaininfo >/dev/null 2>&1 && break
        sleep 2
    done
    if ! $CLI getblockchaininfo >/dev/null 2>&1; then
        echo -e "${RED}Daemon failed. Check $DATA_DIR/debug.log${NC}"
        exit 1
    fi
    echo -e "${GREEN}Daemon running.${NC}"
else
    echo -e "${GREEN}Daemon already running.${NC}"
fi

# ── Sync ────────────────────────────────────────────────
echo "Syncing..."
while true; do
    INFO=$($CLI getblockchaininfo 2>/dev/null) || { sleep 5; continue; }
    IBD=$(echo "$INFO" | grep initialblockdownload | grep -c true)
    [ "$IBD" = "0" ] && break
    BLOCKS=$(echo "$INFO" | grep '"blocks"' | tr -dc '0-9')
    HEADERS=$(echo "$INFO" | grep '"headers"' | tr -dc '0-9')
    [ -n "$HEADERS" ] && [ "$HEADERS" -gt 0 ] 2>/dev/null && echo -ne "\r  $BLOCKS / $HEADERS ($(( BLOCKS * 100 / HEADERS ))%)   "
    sleep 10
done
echo -e "\n${GREEN}Synced!${NC}"

# ── Mine ────────────────────────────────────────────────
echo -e "${CYAN}Starting miner...${NC}"
$CLI setgenerate true $THREADS "$WALLET" "$TAG"

echo ""
echo -e "${GREEN}══════════════════════════════════════${NC}"
echo -e "${GREEN}  Mining!${NC}"
echo -e "${GREEN}  Worker:  $WORKER${NC}"
echo -e "${GREEN}  Address: $WALLET${NC}"
echo -e "${GREEN}  Target:  $TARGET${NC}"
echo -e "${GREEN}══════════════════════════════════════${NC}"
echo ""
echo "  bash ~/capstash/status.sh   — check hashrate"
echo "  bash ~/capstash/stop.sh     — stop mining"
echo ""

# Show initial hashrate after 15s
sleep 15
bash "$INSTALL_DIR/status.sh" 2>/dev/null || true
