#!/bin/bash
# hotkeys_setup.sh — Ghost Machine hotkeys
# Run as normal user (NOT sudo): bash hotkeys_setup.sh

GHOST="/opt/ghost/scripts"

if [ "$EUID" -eq 0 ]; then
    echo "❌ Do NOT run with sudo. Run as: bash $0"
    exit 1
fi

echo "→ Installing xbindkeys and xterm..."
sudo pacman -S --needed --noconfirm xbindkeys xterm

# sudoers
if [ ! -f /etc/sudoers.d/ghost ]; then
    sudo tee /etc/sudoers.d/ghost > /dev/null << SUDOERS
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/panic_shutdown.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/nuclear_wipe.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/mac_randomize.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/identity_randomize.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/tor_enable.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/tor_disable.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/kill_av.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/wipe_logs.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/leak_test.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/metadata_wipe.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/wifi_forget.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/mount_vault.sh
${USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl poweroff
${USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl poweroff --force --force
${USER} ALL=(ALL) NOPASSWD: /sbin/poweroff
SUDOERS
    sudo chmod 440 /etc/sudoers.d/ghost
fi

# Write .xbindkeysrc — exactly the format that worked
echo "→ Writing ~/.xbindkeysrc..."
cat > "$HOME/.xbindkeysrc" << XBRC
# Ghost Machine hotkeys — Mod4 = Super/Windows key

"sudo ${GHOST}/panic_shutdown.sh"
  Mod4+F1

"xterm -title 'GHOST NUKE' -bg black -fg red -fa Monospace -fs 11 -e bash -c 'sudo ${GHOST}/nuclear_wipe.sh; read -p \"Press Enter to close...\"'"
  Mod4+F2

"xterm -title 'Ghost: MAC' -bg black -fg green -fa Monospace -fs 11 -e bash -c 'sudo ${GHOST}/mac_randomize.sh; read -p \"Press Enter to close...\"'"
  Mod4+F3

"xterm -title 'Ghost: Identity' -bg black -fg cyan -fa Monospace -fs 11 -e bash -c 'sudo ${GHOST}/identity_randomize.sh; read -p \"Press Enter to close...\"'"
  Mod4+F4

"xterm -title 'Ghost: Tor ON' -bg black -fg green -fa Monospace -fs 11 -e bash -c 'sudo ${GHOST}/tor_enable.sh; read -p \"Press Enter to close...\"'"
  Mod4+shift+F5

"xterm -title 'Ghost: Tor OFF' -bg black -fg yellow -fa Monospace -fs 11 -e bash -c 'sudo ${GHOST}/tor_disable.sh; read -p \"Press Enter to close...\"'"
  Mod4+shift+F6

"xterm -title 'Ghost: AV Kill' -bg black -fg red -fa Monospace -fs 11 -e bash -c 'sudo ${GHOST}/kill_av.sh; read -p \"Press Enter to close...\"'"
  Mod4+F7

"xterm -title 'Ghost: Wipe' -bg black -fg magenta -fa Monospace -fs 11 -e bash -c 'sudo ${GHOST}/wipe_logs.sh; read -p \"Press Enter to close...\"'"
  Mod4+F8

"xterm -title 'Ghost: Leak Test' -bg black -fg cyan -fa Monospace -fs 11 -e bash -c 'sudo ${GHOST}/leak_test.sh; read -p \"Press Enter to close...\"'"
  Mod4+F9

"xterm -title 'Ghost: Metadata' -bg black -fg yellow -fa Monospace -fs 11 -e bash -c 'sudo ${GHOST}/metadata_wipe.sh ${HOME}; read -p \"Press Enter to close...\"'"
  Mod4+F10

"xterm -title 'Ghost: WiFi Forget' -bg black -fg red -fa Monospace -fs 11 -e bash -c 'sudo ${GHOST}/wifi_forget.sh; read -p \"Press Enter to close...\"'"
  Mod4+F11

"xterm -title 'Ghost: Vault' -bg black -fg cyan -fa Monospace -fs 11 -e bash -c 'sudo ${GHOST}/mount_vault.sh; read -p \"Press Enter to close...\"'"
  Mod4+F12
XBRC

# Autostart
mkdir -p "$HOME/.config/autostart"
cat > "$HOME/.config/autostart/ghost-xbindkeys.desktop" << DESKTOP
[Desktop Entry]
Type=Application
Name=Ghost Machine Hotkeys
Exec=xbindkeys
Hidden=false
X-GNOME-Autostart-enabled=true
DESKTOP

grep -q "xbindkeys" "$HOME/.xprofile" 2>/dev/null || echo "xbindkeys &" >> "$HOME/.xprofile"

# Start xbindkeys
echo "→ Starting xbindkeys..."
pkill -x xbindkeys 2>/dev/null
sleep 0.3
xbindkeys

sleep 0.5
if pgrep -x xbindkeys > /dev/null; then
    echo "✅ xbindkeys running — press Super+F3 to test"
else
    echo "❌ xbindkeys failed — run: xbindkeys --nodaemon --verbose"
fi
