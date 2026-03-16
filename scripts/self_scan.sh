#!/bin/bash
cd "$HOME" 2>/dev/null || cd /tmp
# self_scan.sh — Run nmap against localhost to audit open attack surface
# Alerts if any unexpected ports are open
# Run manually or via cron

LOG="/var/log/ghost/self_scan.log"
BASELINE="/var/lib/ghost/port_baseline.txt"
mkdir -p /var/log/ghost /var/lib/ghost

command -v nmap &>/dev/null || pacman -S --needed --noconfirm nmap

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Self-scan started" >> "$LOG"
echo "Running nmap self-scan..."

# Full TCP scan of localhost + external interface
SCAN_RESULT=$(nmap -sV -p- --open -T4 127.0.0.1 2>/dev/null)
OPEN_PORTS=$(echo "$SCAN_RESULT" | grep "^[0-9]" | grep "open")

if [ "$1" = "baseline" ]; then
    echo "$OPEN_PORTS" > "$BASELINE"
    echo "✅ Baseline saved to $BASELINE"
    echo "$OPEN_PORTS"
    exit 0
fi

echo "Open ports:"
echo "$OPEN_PORTS"
echo ""

# Compare against baseline if it exists
if [ -f "$BASELINE" ]; then
    NEW_PORTS=$(comm -23 <(echo "$OPEN_PORTS" | sort) <(sort "$BASELINE"))
    if [ -n "$NEW_PORTS" ]; then
        echo "⚠️  NEW PORTS DETECTED (not in baseline):"
        echo "$NEW_PORTS"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] NEW PORTS: $NEW_PORTS" >> "$LOG"
        notify-send "⚠️ NEW OPEN PORT" "$NEW_PORTS" 2>/dev/null || \
            wall "GHOST: New open port detected: $NEW_PORTS"
    else
        echo "✅ No new ports since baseline."
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Port scan: clean" >> "$LOG"
    fi
else
    echo "No baseline found. Run: $0 baseline to set one."
fi
