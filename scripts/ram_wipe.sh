#!/bin/bash
cd "$HOME" 2>/dev/null || cd /tmp
# ram_wipe.sh — Overwrite free RAM on shutdown to prevent cold-boot attacks

echo "Wiping free RAM..."

MEM_FREE_KB=$(grep MemFree /proc/meminfo | awk '{print $2}')
MEM_FREE_MB=$(( MEM_FREE_KB / 1024 - 64 ))  # Leave 64MB headroom

if [ "$MEM_FREE_MB" -gt 0 ]; then
    echo "Filling ${MEM_FREE_MB}MB of free RAM with zeros..."
    dd if=/dev/zero of=/dev/shm/ramwipe bs=1M count="$MEM_FREE_MB" 2>/dev/null
    sync
    rm -f /dev/shm/ramwipe
fi

# sdmem from secure-delete package — more thorough multi-pass wipe
# Install: sudo pacman -S secure-delete
if command -v sdmem &>/dev/null; then
    echo "Running sdmem multi-pass wipe..."
    sdmem -f -l -v
fi

echo "RAM wipe complete."
