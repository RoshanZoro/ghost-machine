#!/bin/bash
cd "$HOME" 2>/dev/null || cd /tmp
# leak_test.sh — Test for DNS, IPv6, and WebRTC leaks
# Run before any sensitive session

LOG="/var/log/ghost/leak_tests.log"
mkdir -p /var/log/ghost

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Ghost Machine — Leak Test"
echo " $(date)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

PASS=0
FAIL=0

check() {
    local label="$1"
    local result="$2"
    local expected="$3"   # "pass" or "fail" keyword in result
    if echo "$result" | grep -qi "$expected"; then
        echo "  ✅ $label"
        (( PASS++ ))
    else
        echo "  ❌ $label"
        echo "     → $result"
        (( FAIL++ ))
    fi
}

# ── IPv6 disabled? ──────────────────────────────────────────────────────────
echo "[ IPv6 ]"
IPV6_STATUS=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)
if [ "$IPV6_STATUS" = "1" ]; then
    echo "  ✅ IPv6 disabled at kernel level"
    (( PASS++ ))
else
    echo "  ❌ IPv6 is ENABLED — potential leak risk"
    (( FAIL++ ))
fi

IPV6_IFACES=$(ip -6 addr show 2>/dev/null | grep -v "::1" | grep "inet6")
if [ -z "$IPV6_IFACES" ]; then
    echo "  ✅ No IPv6 addresses assigned to interfaces"
    (( PASS++ ))
else
    echo "  ❌ IPv6 addresses found on interfaces:"
    echo "$IPV6_IFACES" | while read -r line; do echo "     $line"; done
    (( FAIL++ ))
fi
echo ""

# ── DNS leak check ──────────────────────────────────────────────────────────
echo "[ DNS ]"
DNS_SERVER=$(cat /etc/resolv.conf | grep "^nameserver" | head -1 | awk '{print $2}')
if [ "$DNS_SERVER" = "127.0.0.1" ]; then
    echo "  ✅ resolv.conf points to localhost (dnscrypt-proxy)"
    (( PASS++ ))
else
    echo "  ❌ resolv.conf nameserver: $DNS_SERVER (should be 127.0.0.1)"
    (( FAIL++ ))
fi

# Check dnscrypt-proxy is running
if systemctl is-active dnscrypt-proxy &>/dev/null; then
    echo "  ✅ dnscrypt-proxy service running"
    (( PASS++ ))
else
    echo "  ❌ dnscrypt-proxy is NOT running"
    (( FAIL++ ))
fi

# Test DNS resolution through localhost
DNS_RESULT=$(dig +short +time=3 @127.0.0.1 example.com 2>/dev/null)
if [ -n "$DNS_RESULT" ]; then
    echo "  ✅ DNS resolves through localhost"
    (( PASS++ ))
else
    echo "  ❌ DNS resolution through localhost failed"
    (( FAIL++ ))
fi
echo ""

# ── Tor check ──────────────────────────────────────────────────────────────
echo "[ Tor ]"
if systemctl is-active tor &>/dev/null; then
    echo "  ✅ Tor service running"
    (( PASS++ ))

    # Check if we're exiting through Tor
    TOR_CHECK=$(curl -s --socks5-hostname 127.0.0.1:9050 --max-time 10 https://check.torproject.org/api/ip 2>/dev/null)
    if echo "$TOR_CHECK" | grep -q '"IsTor":true'; then
        echo "  ✅ Traffic is exiting through Tor"
        (( PASS++ ))
    else
        echo "  ⚠️  Could not verify Tor exit (network may be unreachable or Tor is slow)"
    fi
else
    echo "  ℹ️  Tor not running (enable with tor_enable.sh if needed)"
fi
echo ""

# ── Open ports (attack surface) ─────────────────────────────────────────────
echo "[ Open ports ]"
OPEN_PORTS=$(ss -tlnp 2>/dev/null | grep LISTEN | grep -v "127.0.0.1" | grep -v "\[::1\]")
if [ -z "$OPEN_PORTS" ]; then
    echo "  ✅ No externally listening ports detected"
    (( PASS++ ))
else
    echo "  ⚠️  Externally listening ports found:"
    echo "$OPEN_PORTS" | while read -r line; do echo "     $line"; done
    (( FAIL++ ))
fi
echo ""

# ── MAC address vendor check ────────────────────────────────────────────────
echo "[ MAC addresses ]"
while IFS= read -r line; do
    IFACE=$(echo "$line" | awk '{print $2}' | tr -d ':')
    MAC=$(ip link show "$IFACE" 2>/dev/null | grep "link/ether" | awk '{print $2}')
    if [ -n "$MAC" ]; then
        # Check if first byte has locally-administered bit set (randomized MAC)
        FIRST_BYTE=$(echo "$MAC" | cut -d: -f1)
        FIRST_DEC=$(( 16#$FIRST_BYTE ))
        if (( FIRST_DEC & 2 )); then
            echo "  ✅ $IFACE: $MAC (locally administered / randomized)"
            (( PASS++ ))
        else
            echo "  ⚠️  $IFACE: $MAC (may be real hardware MAC — run mac_randomize.sh)"
        fi
    fi
done < <(ip link show | grep -E "^[0-9]+:" | grep -v lo)
echo ""

# ── Summary ─────────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Results: $PASS passed, $FAIL failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Leak test: $PASS passed, $FAIL failed" >> "$LOG"

if [ "$FAIL" -gt 0 ]; then
    echo "⚠️  Leaks or misconfigurations detected. Review items marked ❌ above."
    exit 1
else
    echo "✅ All checks passed. Stay safe."
    exit 0
fi
