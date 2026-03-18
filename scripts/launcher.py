#!/usr/bin/env python3
"""CapStash Miner Launcher — reads config.json, starts daemon + miner.
Place config.json next to the binary or in ~/capstash/.
"""
import json
import os
import secrets
import string
import subprocess
import sys
import time

GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
CYAN = "\033[0;36m"
RED = "\033[0;31m"
NC = "\033[0m"

INSTALL_DIR = os.path.expanduser("~/capstash")
BIN_DIR = os.path.join(INSTALL_DIR, "bin")
DATA_DIR = os.path.join(INSTALL_DIR, "data")


def find_config():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        os.path.join(INSTALL_DIR, "config.json"),
        os.path.join(BIN_DIR, "config.json"),
        os.path.join(script_dir, "..", "config.json"),
        os.path.join(script_dir, "config.json"),
        os.path.join(os.getcwd(), "config.json"),
    ]
    for path in candidates:
        if os.path.isfile(path):
            return os.path.abspath(path)
    return None


def cli(cmd):
    full = f"{os.path.join(BIN_DIR, 'CapStash-cli')} -datadir={DATA_DIR} {cmd}"
    r = subprocess.run(full, shell=True, capture_output=True, text=True)
    return r.returncode == 0, r.stdout.strip()


def getprop(key):
    try:
        return subprocess.run(
            ["getprop", key], capture_output=True, text=True, timeout=3
        ).stdout.strip()
    except Exception:
        return ""


def main():
    config_path = find_config()
    if not config_path:
        print(f"{RED}Error: config.json not found.{NC}")
        print("Place config.json in ~/capstash/, ~/capstash/bin/, or current directory.")
        sys.exit(1)

    with open(config_path) as f:
        cfg = json.load(f)

    wallet = cfg.get("wallet_address", "")
    threads = cfg.get("threads", -1)
    worker = cfg.get("worker_name", "")
    tag = cfg.get("coinbase_tag", "CellSwarm")
    target = cfg.get("target", "auto")
    rpc_port = cfg.get("rpc_port", 8332)
    rpc_user = cfg.get("rpc_user", "miner")
    rpc_pass = cfg.get("rpc_password", "")
    max_conn = cfg.get("max_connections", 16)
    dbcache = cfg.get("dbcache", 256)
    maxmempool = cfg.get("maxmempool", 50)
    listen = cfg.get("listen", True)
    txindex = cfg.get("txindex", False)
    addnodes = cfg.get("addnodes", [])
    autostart = cfg.get("autostart", True)

    print(f"{CYAN}CapStash Miner{NC}")
    print(f"  Config: {config_path}")

    # Validate wallet
    if not wallet:
        print(f"\n{RED}Error: wallet_address is empty in config.json{NC}")
        print()
        print("You need a wallet address to mine to. Options:")
        print(f"  {GREEN}1.{NC} Generate on this device: bash scripts/install.sh")
        print(f"  {GREEN}2.{NC} Edit config.json: set \"wallet_address\": \"cap1q...\"")
        print()
        print("The wallet address is just a payout destination.")
        print("No wallet needs to exist on this device.")
        sys.exit(1)

    # Default worker name
    if not worker:
        worker = getprop("ro.product.model").replace(" ", "-") or "phone"

    # Generate RPC password if empty
    if not rpc_pass:
        alphabet = string.ascii_letters + string.digits
        rpc_pass = "".join(secrets.choice(alphabet) for _ in range(24))

    print(f"  Wallet:  {wallet}")
    print(f"  Threads: {threads}")
    print(f"  Worker:  {worker}")
    print(f"  Tag:     {tag}")
    print(f"  Target:  {target}")
    print()

    # Create data dir and config
    os.makedirs(DATA_DIR, exist_ok=True)

    conf_lines = [
        "server=1",
        "daemon=1",
        f"rpcuser={rpc_user}",
        f"rpcpassword={rpc_pass}",
        "rpcallowip=127.0.0.1",
        "rpcbind=127.0.0.1",
        f"rpcport={rpc_port}",
        f"listen={'1' if listen else '0'}",
        f"txindex={'1' if txindex else '0'}",
        f"dbcache={dbcache}",
        f"maxmempool={maxmempool}",
        f"maxconnections={max_conn}",
    ]
    for node in addnodes:
        conf_lines.append(f"addnode={node}")

    with open(os.path.join(DATA_DIR, "CapStash.conf"), "w") as f:
        f.write("\n".join(conf_lines) + "\n")

    # Save miner.conf for status.sh compatibility
    with open(os.path.join(INSTALL_DIR, "miner.conf"), "w") as f:
        f.write(f"MINING_ADDR={wallet}\n")
        f.write(f"THREADS={threads}\n")
        f.write(f"COINBASE_TAG={tag}\n")
        f.write(f"TARGET={target}\n")
        f.write(f"WORKER={worker}\n")

    # Check binary
    daemon_path = os.path.join(BIN_DIR, "CapStashd")
    if not os.path.isfile(daemon_path):
        print(f"{RED}Error: CapStashd not found at {BIN_DIR}{NC}")
        print("Run install.sh first or copy the binary.")
        sys.exit(1)

    # Start daemon if not running
    ok, _ = cli("getblockchaininfo")
    if not ok:
        print(f"{YELLOW}Starting daemon...{NC}")
        subprocess.run(f"{daemon_path} -datadir={DATA_DIR} -daemon", shell=True)
        for _ in range(60):
            ok, _ = cli("getblockchaininfo")
            if ok:
                print(f"{GREEN}Daemon ready.{NC}")
                break
            time.sleep(2)
        else:
            print(f"{RED}Daemon failed to start. Check {DATA_DIR}/debug.log{NC}")
            sys.exit(1)
    else:
        print(f"{GREEN}Daemon already running.{NC}")

    # Wait for sync
    print("Syncing blockchain...")
    while True:
        ok, out = cli("getblockchaininfo")
        if not ok:
            time.sleep(5)
            continue
        try:
            info = json.loads(out)
        except json.JSONDecodeError:
            time.sleep(5)
            continue

        if not info.get("initialblockdownload", True):
            print(f"\n{GREEN}Chain synced!{NC}")
            break

        blocks = info.get("blocks", 0)
        headers = info.get("headers", 1)
        pct = info.get("verificationprogress", 0) * 100
        print(f"\r  Sync: {blocks}/{headers} ({pct:.1f}%)   ", end="", flush=True)
        time.sleep(10)

    # Start mining
    if autostart:
        print(f"{CYAN}Starting miner...{NC}")
        ok, result = cli(f'setgenerate true {threads} "{wallet}" "{tag}"')
        if ok:
            try:
                r = json.loads(result)
                print(f"{GREEN}Mining: {r.get('threads', 0)} threads -> {wallet}{NC}")
                print(f"  Worker: {worker}")
                print(f"  Tag:    {tag}")
            except json.JSONDecodeError:
                print(result)
        else:
            print(f"{RED}Failed to start miner: {result}{NC}")
    else:
        print(f"{YELLOW}autostart=false - synced but not mining.{NC}")
        print(f"  Start manually: CapStash-cli setgenerate true {threads} \"{wallet}\" \"{tag}\"")

    print()
    print("  Status: bash ~/capstash/status.sh")
    print("  Stop:   bash ~/capstash/stop.sh")


if __name__ == "__main__":
    main()
