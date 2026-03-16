#!/bin/bash
# tor_enable.sh — Route all traffic through Tor with iptables kill switch
# If Tor drops, all traffic is blocked rather than exposed

TOR_UID=$(id -u debian-tor 2>/dev/null || id -u tor 2>/dev/null || echo 0)
TOR_PORT=9040
LO_IFACE="lo"
NON_TOR="192.168.0.0/16 10.0.0.0/8 172.16.0.0/12"

echo "Enabling Tor transparent proxy with kill switch..."

# Flush existing rules
iptables -F
iptables -t nat -F
iptables -t mangle -F

# Allow established connections and loopback
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i "$LO_IFACE" -j ACCEPT

# Allow Tor process to bypass (prevents routing loop)
iptables -t nat -A OUTPUT -m owner --uid-owner "$TOR_UID" -j RETURN
iptables -A OUTPUT -m owner --uid-owner "$TOR_UID" -j ACCEPT

# Allow LAN traffic without Tor
for RANGE in $NON_TOR; do
    iptables -t nat -A OUTPUT -d "$RANGE" -j RETURN
    iptables -A OUTPUT -d "$RANGE" -j ACCEPT
done

# Redirect DNS through Tor
iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports 5353
iptables -t nat -A OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports 5353

# Redirect all TCP through Tor transparent proxy
iptables -t nat -A OUTPUT -p tcp --syn -j REDIRECT --to-ports "$TOR_PORT"

# KILL SWITCH: Block anything not going through Tor
iptables -A OUTPUT -m owner --uid-owner "$TOR_UID" -j ACCEPT
iptables -A OUTPUT -o "$LO_IFACE" -j ACCEPT
iptables -A OUTPUT -j REJECT

systemctl start tor
echo "✅ Tor routing active. Kill switch engaged. All non-Tor traffic blocked."
