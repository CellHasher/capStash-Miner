# CapStash Miner for Android (Termux)

Pre-built CapStash CPU miner binaries optimized for 36 Android ARM64 SoC targets. Includes install/run/uninstall scripts for easy deployment on phone clusters.

## Flightsheet (Standalone — No SSH, No Server)

Each phone is a **fully independent solo miner**. No central server, no pool, no cluster orchestration. Just edit the wallet address in `flightsheet.sh` and run it on any phone.

```bash
# In Termux on ANY Android phone:
pkg install -y git
git clone https://github.com/lukewrightmain/capstash-miner.git
cd capstash-miner

# Edit the WALLET line at the top of flightsheet.sh:
#   WALLET="cap1qYOUR_ADDRESS_HERE"

bash flightsheet.sh
```

That's it. It auto-detects the SoC, installs the right binary, syncs the chain, and starts mining. Every phone runs the same flightsheet — same wallet, independent miners.

### How it works (no hosting needed)

```
Phone 1 ──┐                          ┌── finds block ──> reward to YOUR_WALLET
Phone 2 ──┤── p2p network (auto) ────┤── finds block ──> reward to YOUR_WALLET
Phone 3 ──┤                          ├── finds block ──> reward to YOUR_WALLET
Phone N ──┘                          └── ...
```

- Each phone runs its own **full node** — no pool server needed
- Phones discover peers automatically via the CapStash p2p network
- All phones mine to the **same wallet address** — rewards accumulate
- No wallet file needed on mining devices — just the address string
- Phones don't need to know about each other at all

## Quick Start (Script Install)

```bash
# On your Android phone in Termux:
pkg install -y git
git clone https://github.com/lukewrightmain/capstash-miner.git
cd capstash-miner

# First device — creates a new wallet
bash scripts/install.sh

# All other devices — use the same wallet address
bash scripts/install.sh --wallet-address cap1q...YOUR_ADDRESS_HERE

# Start mining
bash ~/capstash/run.sh

# Check status
bash ~/capstash/status.sh
```

## Phone Cluster Setup

**One wallet address works across ALL devices.** The mining address is just a payment destination — you don't need a wallet on every phone. Generate a wallet on one device, copy the address, and use `--wallet-address` on all others. All mining rewards accumulate at that single address.

```bash
# Device 1 (generates wallet):
bash scripts/install.sh --target sd888

# Device 2-N (same address, no wallet needed):
bash scripts/install.sh --wallet-address cap1q6r3xq7skllnkj5a0mh3zt6csk3lyaa3np4vtqt --target sd888
```

### Cluster Deploy (SSH)

```bash
# Deploy to multiple phones over SSH
ADDR="cap1q...YOUR_ADDRESS"
for IP in 10.69.3.79 10.69.3.243 10.69.3.193; do
    ssh -p 8022 $IP "cd ~/capstash-miner && bash scripts/install.sh -w $ADDR -t sd888 && bash ~/capstash/run.sh"
done
```

## config.json (Cluster Config)

For phone clusters, edit `config.json` once and push it to all devices. The miner reads it on startup — no per-device wallet needed.

```json
{
    "wallet_address": "cap1qYOUR_SINGLE_ADDRESS",
    "threads": -1,
    "worker_name": "phone-01",
    "coinbase_tag": "CellSwarm",
    "target": "auto",
    "rpc_port": 8332,
    "dbcache": 256,
    "maxmempool": 50,
    "max_connections": 16,
    "listen": true,
    "addnodes": [],
    "autostart": true
}
```

| Field | Description | Default |
|-------|-------------|---------|
| `wallet_address` | **Required.** Mining payout address. Same address on all phones. | `""` |
| `threads` | CPU threads for mining. `-1` = all cores. | `-1` |
| `worker_name` | Identifies this device in logs. Set per phone (e.g. `phone-01`). | auto-detect |
| `coinbase_tag` | Text embedded in mined blocks. | `"CellSwarm"` |
| `target` | SoC build to use. `"auto"` = detect. | `"auto"` |
| `rpc_port` | Local RPC port for daemon. | `8332` |
| `dbcache` | MB of RAM for UTXO cache. Use 128 for 4-6GB phones. | `256` |
| `maxmempool` | MB for mempool. | `50` |
| `max_connections` | Max peer connections. | `16` |
| `listen` | Accept inbound connections. | `true` |
| `addnodes` | Extra peers to connect to. | `[]` |
| `autostart` | Start mining after sync. `false` = sync only. | `true` |

### How the wallet works

- **No wallet needed on mining devices.** The `wallet_address` is just a destination baked into the coinbase transaction.
- Generate a wallet **once** on any device (or desktop). Copy the address.
- All phones mine to that one address. Coins accumulate there.
- Only the device with the actual wallet file can **spend** the coins.
- To create a wallet: run `bash scripts/install.sh` without `--wallet-address` on one device.

### Cluster deploy with config.json

```bash
# 1. Edit config.json with your wallet address
# 2. Push to all phones:
for IP in 10.69.3.79 10.69.3.243 10.69.3.193; do
    scp -P 8022 config.json $IP:~/capstash/config.json
    ssh -p 8022 $IP "bash ~/capstash/launcher.sh"
done
```

### Update config on running devices

```bash
# Push new config (e.g. change threads)
scp -P 8022 config.json phone-ip:~/capstash/config.json
# Restart miner to pick up changes
ssh -p 8022 phone-ip "bash ~/capstash/stop.sh && bash ~/capstash/launcher.sh"
```

See `config.example.json` for a fully commented example.

## Supported Targets (36 SoC Builds)

### Qualcomm Snapdragon
| Target | SoC | Example Devices |
|--------|-----|-----------------|
| `sd821` | Snapdragon 821 | Pixel 1, OnePlus 3T, LG G6 |
| `sd835` | Snapdragon 835 | Galaxy S8, Pixel 2, OnePlus 5 |
| `sd845` | Snapdragon 845 | Galaxy S9, Pixel 3, OnePlus 6 |
| `sd855` | Snapdragon 855 | Galaxy S10, Pixel 4, OnePlus 7 Pro |
| `sd865` | Snapdragon 865 | Galaxy S20, OnePlus 8 |
| `sd888` | Snapdragon 888 (A78) | Galaxy S21/Z Fold3, OnePlus 9 |
| `sd888_x1` | Snapdragon 888 (X1) | Galaxy Z Fold3 (tuned for prime core) |
| `sd8gen1` | Snapdragon 8 Gen 1 | Galaxy S22, OnePlus 10 Pro |
| `sd8plusgen1` | Snapdragon 8+ Gen 1 | Galaxy Z Fold4, ROG Phone 6 |
| `sd8gen2` | Snapdragon 8 Gen 2 | Galaxy S23, OnePlus 11 |
| `sd8gen3` | Snapdragon 8 Gen 3 | Galaxy S24, OnePlus 12 |
| `sd8elite` | Snapdragon 8 Elite | Galaxy S25, OnePlus 13 |
| `sd765` | Snapdragon 765G | Pixel 5, Samsung A52 5G |
| `sd7plusgen3` | Snapdragon 7+ Gen 3 | Mid-range 2024 |

### Samsung Exynos
| Target | SoC | Example Devices |
|--------|-----|-----------------|
| `exynos8895` | Exynos 8895 | Galaxy S8 (international) |
| `exynos9810` | Exynos 9810 | Galaxy S9 (international) |
| `exynos9820` | Exynos 9820 | Galaxy S10 (international) |
| `exynos990` | Exynos 990 | Galaxy S20 (international) |
| `exynos2100` | Exynos 2100 | Galaxy S21 (international) |
| `exynos2200` | Exynos 2200 | Galaxy S22 (international) |
| `exynos2400` | Exynos 2400 | Galaxy S24 (international) |

### Google Tensor
| Target | SoC | Example Devices |
|--------|-----|-----------------|
| `tensor_g1` | Tensor G1 | Pixel 6/6 Pro |
| `tensor_g2` | Tensor G2 | Pixel 7/7 Pro |
| `tensor_g3` | Tensor G3 | Pixel 8/8 Pro |
| `tensor_g4` | Tensor G4 | Pixel 9 |

### Huawei Kirin
| Target | SoC | Example Devices |
|--------|-----|-----------------|
| `kirin970` | Kirin 970 | Mate 10, P20 |
| `kirin980` | Kirin 980 | Mate 20, P30 |
| `kirin990` | Kirin 990 | Mate 30, P40 |

### MediaTek
| Target | SoC | Example Devices |
|--------|-----|-----------------|
| `dimensity1000` | Dimensity 1000 | Redmi K30, OPPO Reno3 |
| `dimensity1200` | Dimensity 1200 | Realme GT, POCO F3 GT |
| `dimensity9000` | Dimensity 9000 | OPPO Find X5 Pro |
| `dimensity9200` | Dimensity 9200 | vivo X90, OPPO Find X6 |
| `helio_p60` | Helio P60 | Budget 2018 devices |

### Generic (Safe Fallbacks)
| Target | Architecture | Use When |
|--------|-------------|----------|
| `generic_v8` | ARMv8.0-A | Any 64-bit Android (2014+) |
| `generic_v82` | ARMv8.2-A | Any 2018+ flagship |
| `generic_v82_i8mm` | ARMv8.2-A+i8mm | Any 2022+ device |

> **Don't know your SoC?** Use `generic_v82` — it works on any 2018+ phone. The installer auto-detects your SoC if you don't specify `--target`.

## Commands

```bash
bash ~/capstash/run.sh        # Start daemon + miner
bash ~/capstash/status.sh     # Check hashrate, blocks found, sync status
bash ~/capstash/stop.sh       # Stop miner + daemon
```

### Manual RPC

```bash
CLI="~/capstash/bin/CapStash-cli -datadir=~/capstash/data"

# Mining control
$CLI setgenerate true 8 "YOUR_ADDRESS" "MyTag"   # Start mining (8 threads)
$CLI setgenerate false                             # Stop mining
$CLI getmininginfo                                 # Hashrate, difficulty, blocks found

# Wallet
$CLI -rpcwallet=miner getbalance                   # Check balance
$CLI -rpcwallet=miner listunspent                  # List UTXOs
$CLI -rpcwallet=miner sendtoaddress "ADDR" 1.0     # Send coins

# Network
$CLI getblockchaininfo                             # Sync status
$CLI getpeerinfo                                   # Connected peers
$CLI getnetworkinfo                                # Network stats
```

## Building from Source on Termux

See [docs/TERMUX_BUILD.md](docs/TERMUX_BUILD.md) for full instructions.

### Quick build:

```bash
# Install dependencies
pkg update -y
pkg install -y git clang make autoconf automake libtool pkg-config \
    python3 boost boost-headers libevent libsqlite

# Clone and build
git clone https://github.com/CapStash/CapStash-Core.git
cd CapStash-Core
./autogen.sh
./configure --without-gui --disable-tests --disable-bench --disable-fuzz-binary \
    --without-bdb CXX=clang++ CC=clang CXXFLAGS="-O2" \
    EVENT_CFLAGS=" " EVENT_PTHREADS_CFLAGS=" " SQLITE_CFLAGS=" "
make -j$(nproc)

# Binaries in src/CapStashd and src/CapStash-cli
strip src/CapStashd src/CapStash-cli
```

## Uninstall

```bash
bash scripts/uninstall.sh
# or
python3 scripts/uninstall.py
```

## Performance

Tested on Snapdragon 888 (Galaxy Z Fold3):

| Threads | Hashrate |
|---------|----------|
| 4 (big cores) | ~2.5 MH/s |
| 8 (all cores) | ~4.5 MH/s |

Hashrate is stable with minimal thermal throttling over extended periods.

## License

CapStash Core is released under the MIT license. See [source/COPYING](source/COPYING).
