#!/bin/bash
cd "$HOME" 2>/dev/null || cd /tmp
# tor_enable.sh — Route all traffic through Tor with iptables kill switch

echo "=== Ghost Machine: Tor Enable ==="
echo ""

# Check dependencies
if ! command -v iptables &>/dev/null; then
    echo "❌ iptables not found. Install with: sudo pacman -S iptables"
    exit 1
fi

if ! systemctl is-enabled tor &>/dev/null; then
    echo "❌ Tor service not found. Install with: sudo pacman -S tor"
    exit 1
fi

TOR_UID=$(id -u tor 2>/dev/null || id -u debian-tor 2>/dev/null)
if [ -z "$TOR_UID" ]; then
    echo "❌ Tor user not found — is tor installed?"
    echo "   Run: sudo pacman -S tor"
    exit 1
fi

TOR_PORT=9040
LO_IFACE="lo"
NON_TOR="192.168.0.0/16 10.0.0.0/8 172.16.0.0/12"

echo "→ Flushing existing iptables rules..."
iptables -F
iptables -t nat -F
iptables -t mangle -F

echo "→ Setting up Tor transparent proxy (uid=$TOR_UID)..."

iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i "$LO_IFACE" -j ACCEPT

iptables -t nat -A OUTPUT -m owner --uid-owner "$TOR_UID" -j RETURN
iptables -A OUTPUT -m owner --uid-owner "$TOR_UID" -j ACCEPT

for RANGE in $NON_TOR; do
    iptables -t nat -A OUTPUT -d "$RANGE" -j RETURN
    iptables -A OUTPUT -d "$RANGE" -j ACCEPT
done

iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports 5353
iptables -t nat -A OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports 5353
iptables -t nat -A OUTPUT -p tcp --syn -j REDIRECT --to-ports "$TOR_PORT"

iptables -A OUTPUT -m owner --uid-owner "$TOR_UID" -j ACCEPT
iptables -A OUTPUT -o "$LO_IFACE" -j ACCEPT
iptables -A OUTPUT -j REJECT

echo "→ Starting Tor..."
systemctl start tor

sleep 3
if systemctl is-active tor &>/dev/null; then
    echo ""
    echo "✅ Tor is running — kill switch active."
    echo "   All traffic now routes through Tor."
    echo "   Test: curl --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip"
else
    echo "❌ Tor failed to start."
    systemctl status tor --no-pager | tail -10
fi
