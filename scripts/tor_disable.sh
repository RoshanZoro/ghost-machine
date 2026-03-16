#!/bin/bash
cd "$HOME" 2>/dev/null || cd /tmp
# tor_disable.sh — Restore normal routing, disable Tor

iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

systemctl stop tor
echo "Tor disabled. Normal routing restored."
