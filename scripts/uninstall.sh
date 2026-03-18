#!/data/data/com.termux/files/usr/bin/bash
# CapStash Miner - Uninstall Script
set -e

INSTALL_DIR="$HOME/capstash"
CLI="$INSTALL_DIR/bin/CapStash-cli -datadir=$INSTALL_DIR/data"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}CapStash Miner Uninstaller${NC}"
echo ""

# Check if installed
if [ ! -d "$INSTALL_DIR" ]; then
    echo "CapStash miner is not installed."
    exit 0
fi

# Show what we're removing
echo "This will remove:"
echo "  - Binaries:    $INSTALL_DIR/bin/"
echo "  - Config:      $INSTALL_DIR/data/CapStash.conf"
echo "  - Blockchain:  $INSTALL_DIR/data/ (all chain data)"
echo "  - Scripts:     $INSTALL_DIR/*.sh"
echo ""

# Warn about wallet
if [ -f "$INSTALL_DIR/miner.conf" ]; then
    source "$INSTALL_DIR/miner.conf"
    echo -e "${RED}WARNING: If this device has the wallet, make sure you have${NC}"
    echo -e "${RED}backed up your wallet or sent all coins to another address!${NC}"
    echo -e "Mining address: ${YELLOW}$MINING_ADDR${NC}"
    echo ""
fi

read -p "Are you sure you want to uninstall? [y/N]: " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Aborted."
    exit 0
fi

# Stop daemon if running
if $CLI getblockchaininfo >/dev/null 2>&1; then
    echo "Stopping miner..."
    $CLI setgenerate false 2>/dev/null || true
    echo "Stopping daemon..."
    $CLI stop 2>/dev/null || true
    sleep 3
fi

# Kill any remaining processes
pkill -f "CapStashd" 2>/dev/null || true
sleep 1

# Remove everything
echo "Removing files..."
rm -rf "$INSTALL_DIR"

echo ""
echo -e "${GREEN}CapStash miner has been uninstalled.${NC}"
