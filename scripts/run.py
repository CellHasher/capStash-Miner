#!/usr/bin/env python3
"""CapStash Miner - Run Script (Python version)
Starts daemon, waits for sync, starts mining.
"""
import json
import os
import subprocess
import sys
import time

INSTALL_DIR = os.path.expanduser("~/capstash")
DATA_DIR = os.path.join(INSTALL_DIR, "data")
BIN_DIR = os.path.join(INSTALL_DIR, "bin")
CLI = f"{os.path.join(BIN_DIR, 'CapStash-cli')} -datadir={DATA_DIR}"
DAEMON = f"{os.path.join(BIN_DIR, 'CapStashd')} -datadir={DATA_DIR}"

GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
CYAN = "\033[0;36m"
NC = "\033[0m"


def run(cmd):
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return r.returncode == 0, r.stdout.strip()


def load_config():
    conf = {}
    conf_path = os.path.join(INSTALL_DIR, "miner.conf")
    if not os.path.exists(conf_path):
        print("Error: Not installed. Run install.sh first.")
        sys.exit(1)
    with open(conf_path) as f:
        for line in f:
            line = line.strip()
            if "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                conf[k] = v
    return conf


def main():
    conf = load_config()
    addr = conf.get("MINING_ADDR", "")
    threads = conf.get("THREADS", "-1")
    tag = conf.get("COINBASE_TAG", "CellSwarm")
    target = conf.get("TARGET", "unknown")

    print(f"{CYAN}CapStash Miner{NC}")
    print(f"  Address: {addr}")
    print(f"  Target:  {target}")
    print()

    # Start daemon if not running
    ok, _ = run(f"{CLI} getblockchaininfo")
    if not ok:
        print(f"{YELLOW}Starting daemon...{NC}")
        subprocess.run(f"{DAEMON} -daemon", shell=True)
        print("Waiting for RPC...")
        for _ in range(60):
            ok, _ = run(f"{CLI} getblockchaininfo")
            if ok:
                print(f"{GREEN}Daemon started.{NC}")
                break
            time.sleep(2)
        else:
            print("Error: Daemon failed to start.")
            sys.exit(1)
    else:
        print(f"{GREEN}Daemon already running.{NC}")

    # Wait for sync
    while True:
        ok, out = run(f"{CLI} getblockchaininfo")
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
        headers = info.get("headers", 0)
        pct = (blocks * 100 // headers) if headers > 0 else 0
        print(f"\rSyncing: {blocks} / {headers} blocks ({pct}%)   ", end="", flush=True)
        time.sleep(10)

    # Start mining
    print(f"\n{CYAN}Starting miner...{NC}")
    ok, result = run(f'{CLI} setgenerate true {threads} "{addr}" "{tag}"')
    if ok:
        try:
            info = json.loads(result)
            print(f"  Mining:   {info.get('mining', False)}")
            print(f"  Threads:  {info.get('threads', 0)}")
            print(f"  Address:  {info.get('address', '')}")
        except json.JSONDecodeError:
            print(result)
    else:
        print(f"Warning: {result}")

    print(f"\n{GREEN}Miner is running in the background.{NC}")
    print("  Check status: bash ~/capstash/status.sh")
    print("  Stop:         bash ~/capstash/stop.sh")


if __name__ == "__main__":
    main()
