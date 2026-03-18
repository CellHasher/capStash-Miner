# Building CapStash Miner from Source on Termux

Complete guide for building CapStash Core daemon from source directly on an Android device using Termux.

## Requirements

- Android device (ARM64, 2017 or newer)
- [Termux](https://f-droid.org/en/packages/com.termux/) from F-Droid (NOT Google Play — that version is outdated)
- ~2GB free RAM (swap helps — Termux supports zram)
- ~3GB free storage
- ~30 minutes build time (varies by SoC)

## Step 1: Install Termux Packages

```bash
pkg update -y
pkg install -y \
    git \
    clang \
    make \
    autoconf \
    automake \
    libtool \
    pkg-config \
    python3 \
    boost \
    boost-headers \
    libevent \
    libsqlite
```

## Step 2: Clone CapStash-Core

```bash
mkdir -p ~/build && cd ~/build
git clone https://github.com/CapStash/CapStash-Core.git
cd CapStash-Core
```

## Step 3: Generate Build System

```bash
./autogen.sh
```

## Step 4: Configure

The critical flags for Termux are:
- `EVENT_CFLAGS=" "` `EVENT_PTHREADS_CFLAGS=" "` `SQLITE_CFLAGS=" "` — prevents pkg-config from adding `-I/usr/include` which breaks libc++ header ordering
- `--disable-fuzz-binary` — fuzz code uses `fopencookie()` which doesn't exist on Android/Bionic
- `--without-bdb` — Berkeley DB not available, use SQLite wallet instead

```bash
./configure \
    --without-gui \
    --disable-tests \
    --disable-bench \
    --disable-fuzz-binary \
    --without-bdb \
    CXX=clang++ \
    CC=clang \
    CXXFLAGS="-O2" \
    EVENT_CFLAGS=" " \
    EVENT_PTHREADS_CFLAGS=" " \
    SQLITE_CFLAGS=" "
```

### Optional: Optimize for your SoC

Add CPU-specific flags for better performance:

```bash
# Snapdragon 888 (Cortex-A78 + Cortex-X1)
CXXFLAGS="-O2 -mcpu=cortex-a78 -march=armv8.2-a+crc+crypto+dotprod+fp16"

# Snapdragon 8 Gen 2 (Cortex-X3)
CXXFLAGS="-O2 -mcpu=cortex-x3 -march=armv8.4-a+crc+crypto+dotprod+fp16+i8mm"

# Safe for any 2018+ phone
CXXFLAGS="-O2 -march=armv8.2-a+dotprod+fp16"

# Absolute safest (any 64-bit Android)
CXXFLAGS="-O2 -march=armv8-a"
```

## Step 5: Build

```bash
make -j$(nproc)
```

If you run out of memory, reduce parallelism:

```bash
make -j2
# or even single-threaded:
make -j1
```

### Low-memory optimization

```bash
./configure ... CXXFLAGS="-O2 --param ggc-min-expand=1 --param ggc-min-heapsize=32768"
```

## Step 6: Install

```bash
# Strip debug symbols (172MB -> 11MB)
strip src/CapStashd src/CapStash-cli

# Copy to install location
mkdir -p ~/capstash/bin
cp src/CapStashd src/CapStash-cli ~/capstash/bin/
chmod +x ~/capstash/bin/*
```

## Step 7: Configure and Run

```bash
# Create data directory
mkdir -p ~/capstash/data

# Write config
cat > ~/capstash/data/CapStash.conf << 'EOF'
server=1
daemon=1
rpcuser=miner
rpcpassword=CHANGE_THIS_PASSWORD
rpcallowip=127.0.0.1
rpcbind=127.0.0.1
listen=1
dbcache=256
maxmempool=50
EOF

# Start daemon
~/capstash/bin/CapStashd -datadir=$HOME/capstash/data -daemon

# Wait for it to start, then create wallet
sleep 10
CLI="~/capstash/bin/CapStash-cli -datadir=$HOME/capstash/data"
$CLI createwallet "miner"
$CLI -rpcwallet=miner getnewaddress "mining"
# Save this address!

# Wait for sync (check progress)
$CLI getblockchaininfo

# Start mining (8 threads, replace YOUR_ADDRESS)
$CLI setgenerate true 8 "YOUR_ADDRESS" "MyMiner"

# Check hashrate
$CLI getmininginfo
```

## Troubleshooting

### Error: `<cerrno> tried including <errno.h> but didn't find libc++'s <errno.h>`

This means pkg-config is adding `-I/data/data/com.termux/files/usr/include` to CFLAGS, which breaks C++ header ordering. Fix by blanking out the offending flags:

```bash
./configure ... EVENT_CFLAGS=" " EVENT_PTHREADS_CFLAGS=" " SQLITE_CFLAGS=" "
```

### Error: `unknown type name 'cookie_io_functions_t'`

This is in the fuzz test code. `fopencookie()` is a glibc extension not available on Android. Fix:

```bash
./configure ... --disable-fuzz-binary
```

### Build killed (OOM)

Reduce parallelism or add swap:

```bash
# Reduce threads
make -j1

# Or add swap (requires root)
# Termux usually has zram enabled automatically
```

### `autoconf: command not found` during make

The Makefile is trying to regenerate autotools files. Touch the timestamps:

```bash
find . -name "configure" -exec touch {} +
find . -name "aclocal.m4" -exec touch {} +
sleep 1
find . -name "Makefile.in" -exec touch {} +
find . -name "config.h.in" -exec touch {} +
```

### Daemon crashes on start

Check logs:

```bash
cat ~/capstash/data/debug.log | tail -50
```

Common fix — reduce memory usage:

```bash
# In CapStash.conf:
dbcache=128
maxmempool=30
```

## Cleanup Build Files

```bash
rm -rf ~/build/CapStash-Core
```
