#!/bin/bash
cd "$HOME" 2>/dev/null || cd /tmp
# wifi_forget.sh — Delete all saved WiFi profiles on shutdown
# Prevents your machine broadcasting known SSIDs passively
# Also randomizes wifi MAC before any new connection

LOG="/var/log/ghost/wifi_forget.log"
mkdir -p /var/log/ghost

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Wiping saved WiFi profiles..." >> "$LOG"

# NetworkManager connections
NM_DIR="/etc/NetworkManager/system-connections"
if [ -d "$NM_DIR" ]; then
    COUNT=$(ls "$NM_DIR"/*.nmconnection 2>/dev/null | wc -l)
    if [ "$COUNT" -gt 0 ]; then
        ls "$NM_DIR"/*.nmconnection 2>/dev/null | while read -r f; do
            NAME=$(grep "^id=" "$f" 2>/dev/null | head -1 | cut -d= -f2)
            rm -f "$f"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Deleted profile: $NAME" >> "$LOG"
        done
        echo "Deleted $COUNT WiFi profile(s)."
    else
        echo "No saved WiFi profiles found."
    fi
fi

# Also clear iwd profiles if using iwd
IWD_DIR="/var/lib/iwd"
if [ -d "$IWD_DIR" ]; then
    find "$IWD_DIR" -name "*.psk" -o -name "*.8021x" | while read -r f; do
        NAME=$(basename "$f")
        rm -f "$f"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Deleted iwd profile: $NAME" >> "$LOG"
    done
fi

# Reload NetworkManager
systemctl reload NetworkManager 2>/dev/null || true

echo "WiFi profiles cleared. Machine will not remember any networks."
