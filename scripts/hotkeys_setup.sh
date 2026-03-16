#!/bin/bash
cd "$HOME" 2>/dev/null || cd /tmp
# hotkeys_setup.sh — Ghost Machine hotkeys
# Run as normal user (NOT sudo): bash hotkeys_setup.sh

GHOST="/opt/ghost/scripts"

if [ "$EUID" -eq 0 ]; then
    echo "❌ Do NOT run with sudo. Run as your normal user: bash $0"
    exit 1
fi

echo "→ Installing xbindkeys and xterm..."
sudo pacman -S --needed --noconfirm xbindkeys xterm

# ── sudoers: no password prompts ─────────────────────────────────────────────
if [ ! -f /etc/sudoers.d/ghost ]; then
    echo "→ Writing sudoers rule..."
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

# ── Write ~/.xbindkeysrc ──────────────────────────────────────────────────────
echo "→ Writing ~/.xbindkeysrc..."
cat > "$HOME/.xbindkeysrc" << XBRC
# Ghost Machine hotkeys — Mod4 = Super/Windows key

"sudo ${GHOST}/panic_shutdown.sh"
  Mod4+F1

"cd /tmp && xterm -title 'GHOST NUKE' -bg black -fg red -fa Monospace -fs 11 -e sudo ${GHOST}/nuclear_wipe.sh"
  Mod4+F2

"cd /tmp && xterm -title 'Ghost: MAC' -bg black -fg green -fa Monospace -fs 11 -e sudo ${GHOST}/mac_randomize.sh"
  Mod4+F3

"cd /tmp && xterm -title 'Ghost: Identity' -bg black -fg cyan -fa Monospace -fs 11 -e sudo ${GHOST}/identity_randomize.sh"
  Mod4+F4

"cd /tmp && xterm -title 'Ghost: Tor ON' -bg black -fg green -fa Monospace -fs 11 -e sudo ${GHOST}/tor_enable.sh"
  Mod4+F5

"cd /tmp && xterm -title 'Ghost: Tor OFF' -bg black -fg yellow -fa Monospace -fs 11 -e sudo ${GHOST}/tor_disable.sh"
  Mod4+F6

"cd /tmp && xterm -title 'Ghost: AV Kill' -bg black -fg red -fa Monospace -fs 11 -e sudo ${GHOST}/kill_av.sh"
  Mod4+F7

"cd /tmp && xterm -title 'Ghost: Wipe' -bg black -fg magenta -fa Monospace -fs 11 -e sudo ${GHOST}/wipe_logs.sh"
  Mod4+F8

"cd /tmp && xterm -title 'Ghost: Leak Test' -bg black -fg cyan -fa Monospace -fs 11 -e sudo ${GHOST}/leak_test.sh"
  Mod4+F9

"cd /tmp && xterm -title 'Ghost: Metadata' -bg black -fg yellow -fa Monospace -fs 11 -e sudo ${GHOST}/metadata_wipe.sh ${HOME}"
  Mod4+F10

"cd /tmp && xterm -title 'Ghost: WiFi Forget' -bg black -fg red -fa Monospace -fs 11 -e sudo ${GHOST}/wifi_forget.sh"
  Mod4+F11

"cd /tmp && xterm -title 'Ghost: Vault' -bg black -fg cyan -fa Monospace -fs 11 -e sudo ${GHOST}/mount_vault.sh"
  Mod4+F12
XBRC

# ── XFCE autostart — most reliable method for XFCE ───────────────────────────
# This runs xbindkeys every single login before the desktop loads
echo "→ Writing XFCE autostart entry..."
mkdir -p "$HOME/.config/autostart"
cat > "$HOME/.config/autostart/ghost-xbindkeys.desktop" << DESKTOP
[Desktop Entry]
Type=Application
Name=Ghost Machine Hotkeys
Exec=xbindkeys
Hidden=false
X-GNOME-Autostart-enabled=true
Comment=Ghost Machine hotkey daemon
DESKTOP

# ── xfce4-session — register as a saved session app ──────────────────────────
# XFCE also restores apps from its session — add xbindkeys there too
XFCE_SESSION="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml"
if [ -f "$XFCE_SESSION" ]; then
    if ! grep -q "xbindkeys" "$XFCE_SESSION"; then
        # Insert before </channel>
        sed -i 's|</channel>|  <property name="Client0_Command" type="array">\n    <value type="string" value="xbindkeys"/>\n  </property>\n</channel>|' "$XFCE_SESSION" 2>/dev/null || true
    fi
fi

# ── .xprofile — catches login managers that don't use autostart ──────────────
grep -q "xbindkeys" "$HOME/.xprofile" 2>/dev/null || echo "xbindkeys &" >> "$HOME/.xprofile"

# ── Start xbindkeys right now ─────────────────────────────────────────────────
echo "→ Starting xbindkeys..."
pkill -x xbindkeys 2>/dev/null
sleep 0.3
xbindkeys

sleep 0.5
if pgrep -x xbindkeys > /dev/null; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " ✅ xbindkeys running — hotkeys LIVE NOW"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " Test: press Super+F3 — MAC rotate window"
    echo " Will auto-start on every login."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
    echo "❌ xbindkeys failed. Run: xbindkeys --nodaemon --verbose"
fi
