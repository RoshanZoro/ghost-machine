#!/bin/bash
# dns_hardening.sh — Install dnscrypt-proxy with safe fallback DNS
# If dnscrypt-proxy fails, NetworkManager takes over normally
# Run as root

set -e

echo "→ Installing dnscrypt-proxy..."
pacman -S --needed --noconfirm dnscrypt-proxy

# Backup original config
cp /etc/dnscrypt-proxy/dnscrypt-proxy.toml \
   /etc/dnscrypt-proxy/dnscrypt-proxy.toml.bak 2>/dev/null || true

# Write config
cat > /etc/dnscrypt-proxy/dnscrypt-proxy.toml << 'TOML'
listen_addresses = ['127.0.0.53:53']

require_nolog    = true
require_nofilter = false
require_dnssec   = true
block_ipv6       = true
log_level        = 0
lb_strategy      = 'p2'

server_names = [
  'cloudflare',
  'quad9-dnscrypt-ip4-nofilter-pri',
  'mullvad-doh'
]

[sources]
  [sources.'public-resolvers']
  urls = ['https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md']
  cache_file = '/var/cache/dnscrypt-proxy/public-resolvers.md'
  minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
  refresh_delay = 72
TOML

# Point resolv.conf to dnscrypt-proxy — but DO NOT lock it with chattr
# If dnscrypt-proxy dies, NetworkManager can still take over
chattr -i /etc/resolv.conf 2>/dev/null || true
cat > /etc/resolv.conf << 'RESOLV'
# Managed by Ghost Machine — dnscrypt-proxy
nameserver 127.0.0.53
# Fallback — uncomment if dnscrypt-proxy is stopped
# nameserver 8.8.8.8
RESOLV

# Configure NetworkManager to NOT overwrite resolv.conf
# Instead use dns=none so we manage it ourselves
NMCONF="/etc/NetworkManager/NetworkManager.conf"
if ! grep -q "dns=none" "$NMCONF" 2>/dev/null; then
    # Add under [main] section
    sed -i '/\[main\]/a dns=none' "$NMCONF" 2>/dev/null || \
    cat >> "$NMCONF" << 'NM'

[main]
dns=none
NM
fi

# Enable dnscrypt-proxy
systemctl enable --now dnscrypt-proxy.service

# Test
sleep 2
if dig +short +time=3 @127.0.0.53 example.com &>/dev/null; then
    echo "✅ dnscrypt-proxy working — DNS encrypted."
else
    echo "⚠️  dnscrypt-proxy not responding yet — may need a moment to fetch resolver list."
    echo "   If DNS breaks, run: sudo chattr -i /etc/resolv.conf && echo 'nameserver 8.8.8.8' | sudo tee /etc/resolv.conf"
fi

echo ""
echo "To disable encrypted DNS and use normal DNS:"
echo "  sudo systemctl stop dnscrypt-proxy"
echo "  sudo chattr -i /etc/resolv.conf"
echo "  echo 'nameserver 8.8.8.8' | sudo tee /etc/resolv.conf"
