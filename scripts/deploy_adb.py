#!/usr/bin/env python3
"""CapStash Miner - ADB Fleet Deployment Script

Pushes install script + config.json to Android devices via ADB,
runs install in Termux, and starts mining automatically.

Environment variables:
    adb_path         Path to adb binary (default: "adb")
    devices          Space-separated list of device serial numbers
    wallet_address   Mining wallet address (required, same for all devices)
    threads          Mining threads per device (default: -1 = all cores)
    additional_flags Comma-separated config overrides (e.g. "tag=CellSwarm,dbcache=128")
    worker_names_json  JSON object mapping device_id -> worker_name
                       e.g. '{"SERIAL1": "phone-01", "SERIAL2": "phone-02"}'
"""
import os, time, subprocess, tempfile, json
from concurrent.futures import ThreadPoolExecutor, as_completed

ADB = os.environ.get("adb_path", "adb")
devices = os.environ.get("devices", "").split()
wallet_address = os.environ.get("wallet_address", "")
threads = os.environ.get("threads", "-1")
additional_flags = os.environ.get("additional_flags", "")
worker_names_raw = os.environ.get("worker_names_json", "")
worker_names = json.loads(worker_names_raw) if worker_names_raw else {}


def parse_flags(flags_str):
    result = {}
    if not flags_str.strip():
        return result
    for flag in flags_str.split(","):
        flag = flag.strip()
        if "=" not in flag:
            continue
        key, value = flag.split("=", 1)
        result[key.strip()] = value.strip()
    return result


extra = parse_flags(additional_flags)

# The install script that gets pushed to each device
# It clones the repo, runs install.sh (which auto-detects SoC and uses
# pre-built binaries — no compilation needed), writes config.json,
# and starts mining.
INSTALL_SCRIPT = r'''#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "[*] Configuring Termux..."
mkdir -p ~/.termux
if ! grep -q "allow-external-apps" ~/.termux/termux.properties 2>/dev/null; then
    echo "allow-external-apps = true" >> ~/.termux/termux.properties
fi

echo "[*] Installing git..."
pkg update -y 2>/dev/null || true
pkg install -y git python3 2>/dev/null || true

echo "[*] Getting CapStash miner..."
if [ -d "$HOME/capstash-miner" ]; then
    cd "$HOME/capstash-miner" && git pull 2>/dev/null || true
else
    git clone https://github.com/lukewrightmain/capstash-miner "$HOME/capstash-miner"
fi

echo "[*] Running installer..."
cd "$HOME/capstash-miner"
bash scripts/install.sh --wallet-address "__WALLET__" --threads __THREADS__ --tag "__TAG__"

echo "[*] Writing config.json..."
cat > "$HOME/capstash/config.json" << 'CONFIGEOF'
__CONFIG_JSON__
CONFIGEOF

echo "[*] Starting miner..."
cd "$HOME/capstash"

# Start daemon
if ! "$HOME/capstash/bin/CapStash-cli" -datadir="$HOME/capstash/data" getblockchaininfo >/dev/null 2>&1; then
    "$HOME/capstash/bin/CapStashd" -datadir="$HOME/capstash/data" -daemon
    sleep 10
fi

# Wait for sync (background — don't block the ADB session)
nohup bash -c '
CLI="$HOME/capstash/bin/CapStash-cli -datadir=$HOME/capstash/data"
while true; do
    IBD=$($CLI getblockchaininfo 2>/dev/null | grep initialblockdownload | grep -c true)
    [ "$IBD" = "0" ] && break
    sleep 15
done
source "$HOME/capstash/miner.conf" 2>/dev/null
$CLI setgenerate true $THREADS "$MINING_ADDR" "$COINBASE_TAG" 2>/dev/null
echo "[OK] Mining started at $(date)" >> "$HOME/capstash/deploy.log"
' > "$HOME/capstash/deploy.log" 2>&1 &

echo "[OK] CapStash installed and syncing!"
echo "[OK] Mining will start automatically after chain sync."
echo "[OK] Check status: capstash-mine status"
'''


def build_config_json(device_id):
    """Build per-device config.json"""
    worker = worker_names.get(device_id, device_id[:12])
    config = {
        "wallet_address": wallet_address,
        "threads": int(threads) if threads.lstrip("-").isdigit() else -1,
        "worker_name": worker,
        "coinbase_tag": extra.get("tag", "CellSwarm"),
        "target": extra.get("target", "auto"),
        "rpc_port": int(extra.get("rpc_port", 8332)),
        "rpc_user": "miner",
        "rpc_password": "",
        "max_connections": int(extra.get("max_connections", 16)),
        "dbcache": int(extra.get("dbcache", 256)),
        "maxmempool": int(extra.get("maxmempool", 50)),
        "listen": True,
        "txindex": False,
        "addnodes": [],
        "autostart": True
    }
    return json.dumps(config, indent=4)


def install_on_device(device_id, script_content):
    try:
        print(f"[{device_id}] Starting installation...")

        # Build per-device script with config
        config_json = build_config_json(device_id)
        script = script_content.replace("__CONFIG_JSON__", config_json)

        # Write to temp file
        with tempfile.NamedTemporaryFile(
            mode='w', encoding='utf-8', newline='\n',
            delete=False, suffix='.sh'
        ) as f:
            f.write(script)
            local_path = f.name

        device_path = "/data/local/tmp/capstash_install.sh"

        # Kill existing Termux to get clean state
        subprocess.run(
            f"{ADB} -s {device_id} shell am force-stop com.termux",
            shell=True, capture_output=True
        )
        time.sleep(1)

        # Push script
        subprocess.run(
            f'{ADB} -s {device_id} push "{local_path}" "{device_path}"',
            shell=True, check=True, capture_output=True
        )
        subprocess.run(
            f"{ADB} -s {device_id} shell chmod 755 {device_path}",
            shell=True, check=True, capture_output=True
        )

        # Launch Termux
        subprocess.run(
            f"{ADB} -s {device_id} shell am start -n com.termux/com.termux.app.TermuxActivity",
            shell=True, capture_output=True
        )
        time.sleep(8)

        # Type command into Termux (use %s for space in 'input text')
        cmd = "bash%s/data/local/tmp/capstash_install.sh"
        subprocess.run(
            f'{ADB} -s {device_id} shell input text "{cmd}"',
            shell=True, capture_output=True
        )
        time.sleep(0.5)
        subprocess.run(
            f"{ADB} -s {device_id} shell input keyevent 66",
            shell=True, capture_output=True
        )

        os.unlink(local_path)
        worker = worker_names.get(device_id, device_id[:12])
        print(f"[{device_id}] ({worker}) Install started!")
        return f"[{device_id}] Success"

    except Exception as e:
        print(f"[{device_id}] Error: {e}")
        return f"[{device_id}] Error: {e}"


def main():
    if not devices:
        print("No devices specified. Set $devices env var.")
        return

    if not wallet_address:
        print("ERROR: No wallet_address specified!")
        return

    tag = extra.get("tag", "CellSwarm")

    # Prepare the install script template
    script = INSTALL_SCRIPT
    script = script.replace("__WALLET__", wallet_address)
    script = script.replace("__THREADS__", threads)
    script = script.replace("__TAG__", tag)

    print(f"Deploying CapStash miner to {len(devices)} device(s)")
    print(f"  Wallet:  {wallet_address[:8]}...{wallet_address[-6:]}")
    print(f"  Threads: {threads}")
    print(f"  Tag:     {tag}")
    if worker_names:
        print(f"  Workers: {json.dumps(worker_names)}")
    print()

    with ThreadPoolExecutor(max_workers=min(len(devices), 8)) as executor:
        futures = {
            executor.submit(install_on_device, d, script): d
            for d in devices
        }
        for future in as_completed(futures):
            device_id = futures[future]
            try:
                print(future.result())
            except Exception as exc:
                print(f"[{device_id}] Exception: {exc}")

    print()
    print("Install commands sent to all devices.")
    print("Pre-built binaries are used — install takes ~2 minutes (mostly chain sync).")
    print("Mining starts automatically after sync completes.")
    print()
    print("Check status later:")
    for d in devices:
        worker = worker_names.get(d, d[:12])
        print(f"  {ADB} -s {d} shell 'bash ~/capstash/status.sh'  # {worker}")


if __name__ == "__main__":
    main()
