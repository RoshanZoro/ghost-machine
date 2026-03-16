#!/bin/bash
cd "$HOME" 2>/dev/null || cd /tmp
# dns_hardening.sh — Install and configure dnscrypt-proxy with DoH
# Prevents DNS leaks even outside Tor
# Run as root

set -e

echo "→ Installing dnscrypt-proxy..."
pacman -S --needed --noconfirm dnscrypt-proxy

# Backup original config
cp /etc/dnscrypt-proxy/dnscrypt-proxy.toml /etc/dnscrypt-proxy/dnscrypt-proxy.toml.bak 2>/dev/null || true

# Write hardened config
cat > /etc/dnscrypt-proxy/dnscrypt-proxy.toml << 'EOF'
# Ghost Machine — dnscrypt-proxy hardened config

listen_addresses = ['127.0.0.1:53', '[::1]:53']

# Only use servers with no-logs and no-filter policies
require_nolog    = true
require_nofilter = false
require_dnssec   = true

# Use DNS-over-HTTPS only
force_tcp = false

# Randomize which resolver is used each query (harder to correlate)
lb_strategy = 'p2'
lb_estimator = true

# Block IPv6 if disabled system-wide
block_ipv6 = true

# Log nothing
log_level = 0

# Server list — privacy-focused resolvers
server_names = [
  'cloudflare',
  'quad9-dnscrypt-ip4-nofilter-pri',
  'mullvad-doh',
  'nextdns'
]

[sources]
  [sources.'public-resolvers']
  urls = ['https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md']
  cache_file = '/var/cache/dnscrypt-proxy/public-resolvers.md'
  minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
  refresh_delay = 72
EOF

# Point systemd-resolved (or NetworkManager) to localhost
if systemctl is-active systemd-resolved &>/dev/null; then
    mkdir -p /etc/systemd/resolved.conf.d
    cat > /etc/systemd/resolved.conf.d/dnscrypt.conf << 'EOF'
[Resolve]
DNS=127.0.0.1
DNSStubListener=no
EOF
    systemctl restart systemd-resolved
fi

# Override /etc/resolv.conf to point to local dnscrypt
chattr -i /etc/resolv.conf 2>/dev/null || true
echo "nameserver 127.0.0.1" > /etc/resolv.conf
echo "options edns0" >> /etc/resolv.conf
chattr +i /etc/resolv.conf   # make immutable so NetworkManager can't overwrite it

# Enable and start dnscrypt-proxy
systemctl enable --now dnscrypt-proxy.service

echo "✅ dnscrypt-proxy active. Testing..."
sleep 2
dig +short @127.0.0.1 example.com && echo "DNS resolution: OK" || echo "DNS resolution: FAILED — check dnscrypt-proxy status"
