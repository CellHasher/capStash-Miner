#!/usr/bin/env python3
"""CapStash Miner - Uninstall Script (Python version)"""
import os
import shutil
import subprocess
import sys

INSTALL_DIR = os.path.expanduser("~/capstash")
CLI = f"{os.path.join(INSTALL_DIR, 'bin', 'CapStash-cli')} -datadir={os.path.join(INSTALL_DIR, 'data')}"

RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
NC = "\033[0m"


def run(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True)


def main():
    print(f"{YELLOW}CapStash Miner Uninstaller{NC}")
    print()

    if not os.path.isdir(INSTALL_DIR):
        print("CapStash miner is not installed.")
        return

    print("This will remove:")
    print(f"  - Binaries:    {INSTALL_DIR}/bin/")
    print(f"  - Config:      {INSTALL_DIR}/data/CapStash.conf")
    print(f"  - Blockchain:  {INSTALL_DIR}/data/ (all chain data)")
    print(f"  - Scripts:     {INSTALL_DIR}/*.sh")
    print()

    # Load and show wallet info
    conf_path = os.path.join(INSTALL_DIR, "miner.conf")
    if os.path.exists(conf_path):
        with open(conf_path) as f:
            for line in f:
                if line.startswith("MINING_ADDR="):
                    addr = line.strip().split("=", 1)[1]
                    print(f"{RED}WARNING: If this device has the wallet, back it up first!{NC}")
                    print(f"Mining address: {YELLOW}{addr}{NC}")
                    print()

    confirm = input("Are you sure you want to uninstall? [y/N]: ").strip().lower()
    if confirm != "y":
        print("Aborted.")
        return

    # Stop daemon
    r = run(f"{CLI} getblockchaininfo")
    if r.returncode == 0:
        print("Stopping miner...")
        run(f"{CLI} setgenerate false")
        print("Stopping daemon...")
        run(f"{CLI} stop")
        import time
        time.sleep(3)

    run("pkill -f CapStashd")

    print("Removing files...")
    shutil.rmtree(INSTALL_DIR, ignore_errors=True)
    print(f"\n{GREEN}CapStash miner has been uninstalled.{NC}")


if __name__ == "__main__":
    main()
