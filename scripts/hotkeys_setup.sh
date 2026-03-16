#!/bin/bash
# hotkeys_setup.sh — Ghost Machine hotkeys
# Run as normal user (NOT sudo): bash hotkeys_setup.sh

GHOST="/opt/ghost/scripts"

if [ "$EUID" -eq 0 ]; then
    echo "❌ Do NOT run with sudo. Run as your normal user:"
    echo "   bash $0"
    exit 1
fi

# ── sudoers ───────────────────────────────────────────────────────────────────
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

# ── Write ~/.xbindkeysrc — Mod4 is the correct name for the Super/Windows key ─
echo "→ Writing ~/.xbindkeysrc..."
cat > "$HOME/.xbindkeysrc" << 'XBRC'
# Ghost Machine hotkeys
# Mod4 = Super / Windows key

"sudo /opt/ghost/scripts/panic_shutdown.sh"
  Mod4+F1

"xterm -title 'GHOST NUKE' -bg black -fg red -e sudo /opt/ghost/scripts/nuclear_wipe.sh"
  Mod4+F2

"xterm -title 'Ghost: MAC' -bg black -fg green -e sudo /opt/ghost/scripts/mac_randomize.sh"
  Mod4+F3

"xterm -title 'Ghost: Identity' -bg black -fg cyan -e sudo /opt/ghost/scripts/identity_randomize.sh"
  Mod4+F4

"xterm -title 'Ghost: Tor ON' -bg black -fg green -e sudo /opt/ghost/scripts/tor_enable.sh"
  Mod4+F5

"xterm -title 'Ghost: Tor OFF' -bg black -fg yellow -e sudo /opt/ghost/scripts/tor_disable.sh"
  Mod4+F6

"xterm -title 'Ghost: AV Kill' -bg black -fg red -e sudo /opt/ghost/scripts/kill_av.sh"
  Mod4+F7

"xterm -title 'Ghost: Wipe' -bg black -fg magenta -e sudo /opt/ghost/scripts/wipe_logs.sh"
  Mod4+F8

"xterm -title 'Ghost: Leak Test' -bg black -fg cyan -e sudo /opt/ghost/scripts/leak_test.sh"
  Mod4+F9

"xterm -title 'Ghost: Metadata' -bg black -fg yellow -e sudo /opt/ghost/scripts/metadata_wipe.sh /home/roshan"
  Mod4+F10

"xterm -title 'Ghost: WiFi Forget' -bg black -fg red -e sudo /opt/ghost/scripts/wifi_forget.sh"
  Mod4+F11

"xterm -title 'Ghost: Vault' -bg black -fg cyan -e sudo /opt/ghost/scripts/mount_vault.sh"
  Mod4+F12
XBRC

echo "  Written."

# ── Validate ──────────────────────────────────────────────────────────────────
echo "→ Validating config..."
VALIDATE=$(xbindkeys --nodaemon --verbose 2>&1 &
sleep 1
kill %1 2>/dev/null)

ERRORS=$(echo "$VALIDATE" | grep -i "error\|unknown key")
if [ -n "$ERRORS" ]; then
    echo "  ❌ Still errors after fix:"
    echo "$ERRORS"
    echo ""
    echo "  Trying raw keycodes as fallback..."
    # m:0x40 = Mod4, keycodes: F1=67 F2=68 F3=69 F4=70 F5=71 F6=72
    #                           F7=73 F8=74 F9=75 F10=76 F11=95 F12=96
    cat > "$HOME/.xbindkeysrc" << 'XBRC2'
# Ghost Machine hotkeys — raw keycodes

"sudo /opt/ghost/scripts/panic_shutdown.sh"
  m:0x40 + c:67

"xterm -title 'GHOST NUKE' -bg black -fg red -e sudo /opt/ghost/scripts/nuclear_wipe.sh"
  m:0x40 + c:68

"xterm -title 'Ghost: MAC' -bg black -fg green -e sudo /opt/ghost/scripts/mac_randomize.sh"
  m:0x40 + c:69

"xterm -title 'Ghost: Identity' -bg black -fg cyan -e sudo /opt/ghost/scripts/identity_randomize.sh"
  m:0x40 + c:70

"xterm -title 'Ghost: Tor ON' -bg black -fg green -e sudo /opt/ghost/scripts/tor_enable.sh"
  m:0x40 + c:71

"xterm -title 'Ghost: Tor OFF' -bg black -fg yellow -e sudo /opt/ghost/scripts/tor_disable.sh"
  m:0x40 + c:72

"xterm -title 'Ghost: AV Kill' -bg black -fg red -e sudo /opt/ghost/scripts/kill_av.sh"
  m:0x40 + c:73

"xterm -title 'Ghost: Wipe' -bg black -fg magenta -e sudo /opt/ghost/scripts/wipe_logs.sh"
  m:0x40 + c:74

"xterm -title 'Ghost: Leak Test' -bg black -fg cyan -e sudo /opt/ghost/scripts/leak_test.sh"
  m:0x40 + c:75

"xterm -title 'Ghost: Metadata' -bg black -fg yellow -e sudo /opt/ghost/scripts/metadata_wipe.sh /home/roshan"
  m:0x40 + c:76

"xterm -title 'Ghost: WiFi Forget' -bg black -fg red -e sudo /opt/ghost/scripts/wifi_forget.sh"
  m:0x40 + c:95

"xterm -title 'Ghost: Vault' -bg black -fg cyan -e sudo /opt/ghost/scripts/mount_vault.sh"
  m:0x40 + c:96
XBRC2
    echo "  Raw keycode config written."
fi

# ── Start xbindkeys ───────────────────────────────────────────────────────────
echo "→ Starting xbindkeys..."
pkill -x xbindkeys 2>/dev/null
sleep 0.5
xbindkeys

sleep 1
if pgrep -x xbindkeys > /dev/null; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " ✅ xbindkeys running — hotkeys are LIVE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " Super+F3  → Rotate MAC  (test this now)"
    echo " Super+F9  → Leak test"
    echo " Super+F1  → Panic shutdown"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
    echo "❌ xbindkeys still won't start. Run this and paste output:"
    echo "   xbindkeys --nodaemon --verbose"
fi

# ── Autostart ─────────────────────────────────────────────────────────────────
mkdir -p "$HOME/.config/autostart"
cat > "$HOME/.config/autostart/ghost-xbindkeys.desktop" << 'DESKTOP'
[Desktop Entry]
Type=Application
Name=Ghost Machine Hotkeys
Exec=xbindkeys
Hidden=false
X-GNOME-Autostart-enabled=true
DESKTOP

grep -q "xbindkeys" "$HOME/.xprofile" 2>/dev/null || echo "xbindkeys &" >> "$HOME/.xprofile"
echo "→ Autostart configured — hotkeys will survive reboots."
