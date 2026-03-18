#!/usr/bin/env python3
"""CapStash Miner - Termux Install Script (Python version)
Usage: python3 install.py [--wallet-address <addr>] [--target <target>]
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import time
import secrets
import string

INSTALL_DIR = os.path.expanduser("~/capstash")
DATA_DIR = os.path.join(INSTALL_DIR, "data")
BIN_DIR = os.path.join(INSTALL_DIR, "bin")

# ANSI colors
RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
CYAN = "\033[0;36m"
NC = "\033[0m"

TARGETS = [
    "sd821", "sd835", "sd845", "sd855", "sd865", "sd888", "sd888_x1",
    "sd8gen1", "sd8plusgen1", "sd8gen2", "sd8gen3", "sd8elite",
    "sd765", "sd7plusgen3",
    "exynos8895", "exynos9810", "exynos9820", "exynos990",
    "exynos2100", "exynos2200", "exynos2400",
    "tensor_g1", "tensor_g2", "tensor_g3", "tensor_g4",
    "kirin970", "kirin980", "kirin990",
    "dimensity1000", "dimensity1200", "dimensity9000", "dimensity9200",
    "helio_p60",
    "generic_v8", "generic_v82", "generic_v82_i8mm",
]

SOC_MAP = {
    "lahaina": "sd888", "taro": "sd8gen1", "kalama": "sd8gen2",
    "pineapple": "sd8gen3", "sun": "sd8elite", "kona": "sd865",
    "msmnile": "sd855", "sdm845": "sd845", "msm8998": "sd835",
    "msm8996": "sd821", "lito": "sd765",
    "gs101": "tensor_g1", "gs201": "tensor_g2",
    "zuma": "tensor_g3", "zumapro": "tensor_g4",
    "exynos8895": "exynos8895", "exynos9810": "exynos9810",
    "exynos9820": "exynos9820", "exynos990": "exynos990",
    "exynos2100": "exynos2100", "exynos2200": "exynos2200",
    "exynos2400": "exynos2400",
    "mt6885": "dimensity1000", "mt6889": "dimensity1000",
    "mt6893": "dimensity1200", "mt6983": "dimensity9000",
    "mt6985": "dimensity9200",
    "mt6779": "helio_p60", "mt6771": "helio_p60", "mt6765": "helio_p60",
}


def run(cmd, capture=True, check=True):
    r = subprocess.run(cmd, shell=True, capture_output=capture, text=True)
    if check and r.returncode != 0:
        if capture:
            print(f"{RED}Error: {r.stderr}{NC}")
        return None
    return r.stdout.strip() if capture else ""


def getprop(key):
    try:
        return subprocess.run(
            ["getprop", key], capture_output=True, text=True, timeout=5
        ).stdout.strip()
    except Exception:
        return ""


def detect_soc():
    board = getprop("ro.board.platform")
    chip = getprop("ro.chipname")
    model = getprop("ro.product.model")
    soc_model = getprop("ro.soc.model")

    print(f"{YELLOW}Detected hardware:{NC}")
    for label, val in [("Platform", board), ("Chip", chip),
                       ("Model", model), ("SoC", soc_model)]:
        if val:
            print(f"  {label}: {val}")

    if board in SOC_MAP:
        return SOC_MAP[board]

    for key, target in SOC_MAP.items():
        if key in chip.lower():
            return target

    return "generic_v82"


def gen_rpc_password():
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(24))


def find_binaries(target):
    script_dir = os.path.dirname(os.path.abspath(__file__))
    for try_target in [target, "generic_v82", "generic_v8"]:
        for base in [os.path.join(script_dir, "..", "builds"),
                     os.path.join(script_dir, "builds")]:
            path = os.path.join(base, try_target)
            if os.path.isfile(os.path.join(path, "CapStashd")):
                return path
    return None


def install_binaries_prebuilt(source_dir):
    os.makedirs(BIN_DIR, exist_ok=True)
    for binary in ["CapStashd", "CapStash-cli"]:
        src = os.path.join(source_dir, binary)
        dst = os.path.join(BIN_DIR, binary)
        shutil.copy2(src, dst)
        os.chmod(dst, 0o755)
    print(f"{GREEN}Binaries installed to {BIN_DIR}{NC}")


def install_binaries_source():
    print(f"{CYAN}Installing build dependencies...{NC}")
    run("pkg update -y", capture=False, check=False)
    run("pkg install -y git clang make autoconf automake libtool pkg-config "
        "python3 boost boost-headers libevent libsqlite", capture=False, check=False)

    build_dir = os.path.join(INSTALL_DIR, "build")
    if os.path.exists(build_dir):
        shutil.rmtree(build_dir)

    print(f"{CYAN}Cloning CapStash-Core...{NC}")
    run(f"git clone https://github.com/CapStash/CapStash-Core.git {build_dir}",
        capture=False)

    print(f"{CYAN}Building (this takes ~30 min)...{NC}")
    cmds = [
        f"cd {build_dir} && ./autogen.sh",
        f"cd {build_dir} && ./configure --without-gui --disable-tests "
        f"--disable-bench --disable-fuzz-binary --without-bdb "
        f'CXX=clang++ CC=clang CXXFLAGS="-O2" '
        f'EVENT_CFLAGS=" " EVENT_PTHREADS_CFLAGS=" " SQLITE_CFLAGS=" "',
        f"cd {build_dir} && make -j$(nproc)",
    ]
    for cmd in cmds:
        result = subprocess.run(cmd, shell=True)
        if result.returncode != 0:
            print(f"{RED}Build failed!{NC}")
            sys.exit(1)

    os.makedirs(BIN_DIR, exist_ok=True)
    for binary in ["CapStashd", "CapStash-cli"]:
        shutil.copy2(os.path.join(build_dir, "src", binary),
                     os.path.join(BIN_DIR, binary))
        run(f"strip {os.path.join(BIN_DIR, binary)}")
        os.chmod(os.path.join(BIN_DIR, binary), 0o755)

    shutil.rmtree(build_dir)
    print(f"{GREEN}Build complete!{NC}")


def setup_wallet(cli_cmd, wallet_addr):
    if wallet_addr:
        print(f"{GREEN}Using provided wallet address: {wallet_addr}{NC}")
        print()
        print("NOTE: This address is used as the mining payout destination.")
        print("You do NOT need a wallet on this device - coins accumulate")
        print("at this address and can be spent from whichever device holds")
        print("the actual wallet.")
        return wallet_addr

    # Start daemon to create wallet
    print("Starting daemon to create wallet...")
    run(f"{os.path.join(BIN_DIR, 'CapStashd')} -datadir={DATA_DIR} -daemon",
        check=False)
    time.sleep(5)

    # Wait for RPC
    for _ in range(30):
        if run(f"{cli_cmd} getblockchaininfo", check=False) is not None:
            break
        time.sleep(2)

    run(f'{cli_cmd} createwallet "miner"', check=False)
    addr = run(f'{cli_cmd} -rpcwallet=miner getnewaddress "mining"')

    run(f"{cli_cmd} stop", check=False)
    time.sleep(3)

    if addr:
        print()
        print(f"{GREEN}{'=' * 55}{NC}")
        print(f"{GREEN}  YOUR MINING WALLET ADDRESS:{NC}")
        print(f"{YELLOW}  {addr}{NC}")
        print()
        print(f"  SAVE THIS! Use on all other devices:")
        print(f"  python3 install.py --wallet-address {addr}")
        print(f"{GREEN}{'=' * 55}{NC}")
        print()
    return addr


def main():
    parser = argparse.ArgumentParser(description="CapStash Miner Installer")
    parser.add_argument("-w", "--wallet-address", help="Mining wallet address")
    parser.add_argument("-t", "--target", help="SoC target (e.g. sd888)")
    parser.add_argument("-j", "--threads", type=int, default=-1,
                        help="Mining threads (-1 = all cores)")
    parser.add_argument("--tag", default="CellSwarm", help="Coinbase tag")
    args = parser.parse_args()

    print(f"{CYAN}")
    print("  ╔═══════════════════════════════════════╗")
    print("  ║       CapStash Miner Installer        ║")
    print("  ║         Termux / Android              ║")
    print("  ╚═══════════════════════════════════════╝")
    print(f"{NC}")

    # Detect or use specified target
    target = args.target or detect_soc()
    print(f"{GREEN}Selected target: {target}{NC}")

    if target not in TARGETS:
        print(f"{RED}Unknown target: {target}{NC}")
        print(f"Available: {', '.join(TARGETS)}")
        sys.exit(1)

    # Find or build binaries
    binary_source = find_binaries(target)
    if binary_source:
        print(f"{GREEN}Found pre-built binaries for {target}{NC}")
        os.makedirs(DATA_DIR, exist_ok=True)
        install_binaries_prebuilt(binary_source)
    else:
        print(f"{YELLOW}No pre-built binary for {target}. Building from source...{NC}")
        os.makedirs(DATA_DIR, exist_ok=True)
        install_binaries_source()

    # Write config
    rpc_pass = gen_rpc_password()
    config_path = os.path.join(DATA_DIR, "CapStash.conf")
    with open(config_path, "w") as f:
        f.write(f"""# CapStash Miner Configuration
server=1
daemon=1
rpcuser=miner
rpcpassword={rpc_pass}
rpcallowip=127.0.0.1
rpcbind=127.0.0.1
listen=1
txindex=0
dbcache=256
maxmempool=50
""")
    print(f"{GREEN}Config written to {config_path}{NC}")

    # Setup wallet
    cli_cmd = f"{os.path.join(BIN_DIR, 'CapStash-cli')} -datadir={DATA_DIR}"
    mining_addr = setup_wallet(cli_cmd, args.wallet_address)

    # Save miner config
    miner_conf = os.path.join(INSTALL_DIR, "miner.conf")
    with open(miner_conf, "w") as f:
        f.write(f"MINING_ADDR={mining_addr}\n")
        f.write(f"THREADS={args.threads}\n")
        f.write(f"COINBASE_TAG={args.tag}\n")
        f.write(f"TARGET={target}\n")

    print()
    print(f"{GREEN}=== Installation Complete ==={NC}")
    print(f"  Install dir:  {INSTALL_DIR}")
    print(f"  Target:       {target}")
    print(f"  Address:      {mining_addr}")
    print()
    print("  Commands:")
    print("    bash ~/capstash/run.sh       Start daemon + miner")
    print("    bash ~/capstash/status.sh    Check mining status")
    print("    bash ~/capstash/stop.sh      Stop everything")
    print()
    print(f"{YELLOW}  For clusters: use the same --wallet-address on every device!{NC}")


if __name__ == "__main__":
    main()
