#!/bin/bash
# mac_randomize.sh — Randomize MAC address with jitter
# Run as root via systemd timer

LOG="/var/log/ghost/mac_changes.log"
mkdir -p /var/log/ghost

# Detect all physical network interfaces (skip loopback)
INTERFACES=$(ip link show | awk -F': ' '/^[0-9]+: [^lo]/{print $2}' | sed 's/@.*//')

for IFACE in $INTERFACES; do
    ip link set "$IFACE" down 2>/dev/null || continue
    macchanger -r "$IFACE" > /dev/null 2>&1
    NEW_MAC=$(macchanger -s "$IFACE" | awk '/Current/{print $3}')
    ip link set "$IFACE" up 2>/dev/null
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $IFACE → $NEW_MAC" >> "$LOG"
    echo "MAC randomized: $IFACE → $NEW_MAC"
done

systemctl restart NetworkManager
sleep 3
echo "NetworkManager restarted."
