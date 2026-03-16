#!/bin/bash
cd "$HOME" 2>/dev/null || cd /tmp
# tor_disable.sh — Restore normal routing

echo "=== Ghost Machine: Tor Disable ==="
echo ""

echo "→ Flushing iptables rules..."
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

echo "→ Stopping Tor..."
systemctl stop tor

echo ""
echo "✅ Tor disabled. Normal routing restored."
echo "   Your real IP is now exposed."
