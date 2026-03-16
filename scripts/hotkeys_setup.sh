#!/bin/bash
# hotkeys_setup.sh — Ghost Machine hotkeys via xbindkeys
# Bypasses XFCE entirely — works 100% reliably
# Run as your DESKTOP USER: bash hotkeys_setup.sh

GHOST="/opt/ghost/scripts"

echo "→ Installing xbindkeys and xterm..."
sudo pacman -S --needed --noconfirm xbindkeys xterm xfconf

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
# Ghost Machine hotkeys

"sudo ${GHOST}/panic_shutdown.sh"
  Super + F1

"xterm -title 'GHOST NUKE' -bg black -fg red -e sudo ${GHOST}/nuclear_wipe.sh"
  Super + F2

"xterm -title 'Ghost: MAC' -bg black -fg green -e sudo ${GHOST}/mac_randomize.sh"
  Super + F3

"xterm -title 'Ghost: Identity' -bg black -fg cyan -e sudo ${GHOST}/identity_randomize.sh"
  Super + F4

"xterm -title 'Ghost: Tor ON' -bg black -fg green -e sudo ${GHOST}/tor_enable.sh"
  Super + F5

"xterm -title 'Ghost: Tor OFF' -bg black -fg yellow -e sudo ${GHOST}/tor_disable.sh"
  Super + F6

"xterm -title 'Ghost: AV Kill' -bg black -fg red -e sudo ${GHOST}/kill_av.sh"
  Super + F7

"xterm -title 'Ghost: Wipe' -bg black -fg magenta -e sudo ${GHOST}/wipe_logs.sh"
  Super + F8

"xterm -title 'Ghost: Leak Test' -bg black -fg cyan -e sudo ${GHOST}/leak_test.sh"
  Super + F9

"xterm -title 'Ghost: Metadata' -bg black -fg yellow -e sudo ${GHOST}/metadata_wipe.sh \$HOME"
  Super + F10

"xterm -title 'Ghost: WiFi Forget' -bg black -fg red -e sudo ${GHOST}/wifi_forget.sh"
  Super + F11

"xterm -title 'Ghost: Vault' -bg black -fg cyan -e sudo ${GHOST}/mount_vault.sh"
  Super + F12
XBRC
echo "  Written."

# ── Start xbindkeys now ───────────────────────────────────────────────────────
echo "→ Starting xbindkeys..."
pkill -x xbindkeys 2>/dev/null
sleep 0.5
xbindkeys

if pgrep -x xbindkeys > /dev/null; then
    echo "  ✅ xbindkeys running — hotkeys are LIVE NOW."
else
    echo "  ❌ xbindkeys failed to start."
    echo "     Try running manually: xbindkeys --verbose"
    exit 1
fi

# ── Autostart on every login ──────────────────────────────────────────────────
echo "→ Setting up autostart..."

# Method 1: XFCE autostart (shows in Session and Startup settings)
AUTOSTART="$HOME/.config/autostart/ghost-xbindkeys.desktop"
mkdir -p "$HOME/.config/autostart"
cat > "$AUTOSTART" << DESKTOP
[Desktop Entry]
Type=Application
Name=Ghost Machine Hotkeys
Exec=xbindkeys
Hidden=false
X-GNOME-Autostart-enabled=true
Comment=Ghost Machine hotkey daemon
DESKTOP
echo "  Autostart .desktop written."

# Method 2: xfce4-session autostart via xfconf
xfconf-query -c xfce4-session \
    -p "/startup/Ghost-Hotkeys/enabled" \
    --create -t bool -s true 2>/dev/null || true
xfconf-query -c xfce4-session \
    -p "/startup/Ghost-Hotkeys/command" \
    --create -t string -s "xbindkeys" 2>/dev/null || true

# Method 3: ~/.xprofile (catches bare WM starts and some DMs)
if ! grep -q "xbindkeys" "$HOME/.xprofile" 2>/dev/null; then
    echo "xbindkeys &" >> "$HOME/.xprofile"
    echo "  Added to ~/.xprofile."
fi

# ── Now ALSO try xfconf-query for XFCE Application Shortcuts ─────────────────
# Even if it fails, xbindkeys already handles everything above
echo ""
echo "→ Also trying to add to XFCE Application Shortcuts..."

try_xfconf() {
    local KEY="$1"
    local CMD="$2"
    local PROP="/commands/custom/${KEY}"
    xfconf-query -c xfce4-keyboard-shortcuts -p "$PROP" -r 2>/dev/null
    xfconf-query -c xfce4-keyboard-shortcuts -p "$PROP" --create -t string -s "$CMD" 2>/dev/null && \
        echo "  ✅ xfconf: $KEY" || \
        echo "  ℹ️  xfconf: $KEY (skipped — xbindkeys handles it anyway)"
}

try_xfconf "<Super>F1"  "sudo ${GHOST}/panic_shutdown.sh"
try_xfconf "<Super>F2"  "xterm -title 'GHOST NUKE' -bg black -fg red -e sudo ${GHOST}/nuclear_wipe.sh"
try_xfconf "<Super>F3"  "xterm -title 'Ghost: MAC' -bg black -fg green -e sudo ${GHOST}/mac_randomize.sh"
try_xfconf "<Super>F4"  "xterm -title 'Ghost: Identity' -bg black -fg cyan -e sudo ${GHOST}/identity_randomize.sh"
try_xfconf "<Super>F5"  "xterm -title 'Ghost: Tor ON' -bg black -fg green -e sudo ${GHOST}/tor_enable.sh"
try_xfconf "<Super>F6"  "xterm -title 'Ghost: Tor OFF' -bg black -fg yellow -e sudo ${GHOST}/tor_disable.sh"
try_xfconf "<Super>F7"  "xterm -title 'Ghost: AV Kill' -bg black -fg red -e sudo ${GHOST}/kill_av.sh"
try_xfconf "<Super>F8"  "xterm -title 'Ghost: Wipe' -bg black -fg magenta -e sudo ${GHOST}/wipe_logs.sh"
try_xfconf "<Super>F9"  "xterm -title 'Ghost: Leak Test' -bg black -fg cyan -e sudo ${GHOST}/leak_test.sh"
try_xfconf "<Super>F10" "xterm -title 'Ghost: Metadata' -bg black -fg yellow -e sudo ${GHOST}/metadata_wipe.sh \$HOME"
try_xfconf "<Super>F11" "xterm -title 'Ghost: WiFi Forget' -bg black -fg red -e sudo ${GHOST}/wifi_forget.sh"
try_xfconf "<Super>F12" "xterm -title 'Ghost: Vault' -bg black -fg cyan -e sudo ${GHOST}/mount_vault.sh"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " ✅ Hotkeys are active RIGHT NOW via xbindkeys."
echo "    They will survive reboots automatically."
echo ""
echo " Super+F3  → test it now (rotates MAC)"
echo " Super+F9  → leak test"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
