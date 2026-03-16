#!/bin/bash
# install.sh — Deploy Ghost Machine scripts, services, and config
# Run as root: sudo bash install.sh

set -e

echo "╔══════════════════════════════════════╗"
echo "║       Ghost Machine Installer        ║"
echo "║     Lenovo T420 / Manjaro Linux      ║"
echo "╚══════════════════════════════════════╝"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "❌ Run as root: sudo bash install.sh"
    exit 1
fi

INSTALL_DIR="/opt/ghost/scripts"
mkdir -p "$INSTALL_DIR"
mkdir -p /var/log/ghost

echo "→ Installing dependencies..."
pacman -S --needed --noconfirm \
    macchanger \
    tor \
    torsocks \
    usbguard \
    bleachbit \
    xautolock \
    xprintidle \
    inotify-tools \
    procps-ng \
    util-linux \
    coreutils \
    nftables \
    sqlite \
    secure-delete

echo "→ Copying scripts..."
cp scripts/*.sh "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR"/*.sh

echo "→ Installing systemd services..."
cp systemd/*.service /etc/systemd/system/
systemctl daemon-reload

echo "→ Enabling services..."
systemctl enable --now mac-randomize.service
systemctl enable --now idle-shutdown.service
systemctl enable ram-wipe.service
systemctl enable --now usbguard.service

echo "→ Applying kernel hardening (sysctl)..."
cp config/99-ghost.conf /etc/sysctl.d/
sysctl -p /etc/sysctl.d/99-ghost.conf

echo "→ Applying firewall (nftables)..."
cp config/nftables.conf /etc/nftables.conf
systemctl enable --now nftables.service

echo "→ Installing cron jobs..."
cp config/ghost.cron /etc/cron.d/ghost
chmod 644 /etc/cron.d/ghost

echo "→ Appending Tor config..."
cat config/torrc.append >> /etc/tor/torrc

echo "→ Disabling IPv6 in GRUB..."
if ! grep -q "ipv6.disable" /etc/default/grub; then
    sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="ipv6.disable=1 /' /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg
    echo "   IPv6 disabled."
else
    echo "   IPv6 already disabled."
fi

echo "→ Disabling shell history for root..."
ln -sf /dev/null /root/.bash_history
grep -q "HISTFILE=/dev/null" /root/.bashrc || echo "HISTFILE=/dev/null" >> /root/.bashrc

echo ""
echo "╔══════════════════════════════════════╗"
echo "║  ✅ Ghost Machine deployed!          ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "⚠️  MANUAL STEPS REQUIRED:"
echo "   1. Set BIOS supervisor password (F1 at boot on T420)"
echo "   2. Assign hotkeys in your DE/WM config:"
echo "      Super+F1 → panic_shutdown.sh"
echo "      Super+F2 → nuclear_wipe.sh  (triple-press)"
echo "      Super+F3 → mac_randomize.sh"
echo "      Super+F4 → hostname_randomize.sh"
echo "      Super+F5 → tor_enable.sh"
echo "      Super+F6 → tor_disable.sh"
echo "      Super+F7 → kill_av.sh"
echo "      Super+F8 → wipe_logs.sh"
echo "   3. Reboot to apply all kernel parameters"
echo ""
