#!/bin/bash
# hotkeys_setup.sh — Set XFCE Application Shortcuts for Ghost Machine
# Run as your DESKTOP USER (not root): bash hotkeys_setup.sh

GHOST="/opt/ghost/scripts"

# ── 1. sudoers so scripts don't prompt for password ───────────────────────────
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
    echo "  done."
fi

# ── 2. Install xterm if missing (used to show script output) ──────────────────
command -v xterm &>/dev/null || sudo pacman -S --needed --noconfirm xterm 2>/dev/null

# ── 3. Kill xfconfd so it re-reads from disk cleanly ─────────────────────────
echo "→ Restarting xfconfd..."
pkill -x xfconfd 2>/dev/null
sleep 1

# ── 4. Set every shortcut via xfconf-query ────────────────────────────────────
# This writes directly into xfconfd's database — guaranteed to show in the UI
echo "→ Writing shortcuts via xfconf-query..."

set_shortcut() {
    local KEY="$1"
    local CMD="$2"
    local PROP="/commands/custom/${KEY}"

    # Delete first to avoid stale type conflicts, then create fresh
    xfconf-query -c xfce4-keyboard-shortcuts -p "$PROP" -r 2>/dev/null || true
    xfconf-query -c xfce4-keyboard-shortcuts -p "$PROP" --create -t string -s "$CMD"

    if [ $? -eq 0 ]; then
        echo "  ✅ $KEY"
    else
        echo "  ❌ $KEY — xfconf-query failed"
    fi
}

set_shortcut "<Super>F1"  "sudo ${GHOST}/panic_shutdown.sh"
set_shortcut "<Super>F2"  "xterm -title 'GHOST NUKE' -bg black -fg red -e sudo ${GHOST}/nuclear_wipe.sh"
set_shortcut "<Super>F3"  "xterm -title 'Ghost: MAC' -bg black -fg green -e sudo ${GHOST}/mac_randomize.sh"
set_shortcut "<Super>F4"  "xterm -title 'Ghost: Identity' -bg black -fg cyan -e sudo ${GHOST}/identity_randomize.sh"
set_shortcut "<Super>F5"  "xterm -title 'Ghost: Tor ON' -bg black -fg green -e sudo ${GHOST}/tor_enable.sh"
set_shortcut "<Super>F6"  "xterm -title 'Ghost: Tor OFF' -bg black -fg yellow -e sudo ${GHOST}/tor_disable.sh"
set_shortcut "<Super>F7"  "xterm -title 'Ghost: AV Kill' -bg black -fg red -e sudo ${GHOST}/kill_av.sh"
set_shortcut "<Super>F8"  "xterm -title 'Ghost: Wipe' -bg black -fg magenta -e sudo ${GHOST}/wipe_logs.sh"
set_shortcut "<Super>F9"  "xterm -title 'Ghost: Leak Test' -bg black -fg cyan -e sudo ${GHOST}/leak_test.sh"
set_shortcut "<Super>F10" "xterm -title 'Ghost: Metadata' -bg black -fg yellow -e sudo ${GHOST}/metadata_wipe.sh \$HOME"
set_shortcut "<Super>F11" "xterm -title 'Ghost: WiFi Forget' -bg black -fg red -e sudo ${GHOST}/wifi_forget.sh"
set_shortcut "<Super>F12" "xterm -title 'Ghost: Vault' -bg black -fg cyan -e sudo ${GHOST}/mount_vault.sh"

# ── 5. Verify they actually landed ───────────────────────────────────────────
echo ""
echo "→ Verifying..."
FOUND=$(xfconf-query -c xfce4-keyboard-shortcuts -l 2>/dev/null | grep -c "Super.*F[0-9]")
echo "  Found $FOUND Ghost shortcuts in xfconfd."

if [ "$FOUND" -gt 0 ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " ✅ Done! Open Settings → Keyboard →"
    echo "    Application Shortcuts to confirm."
    echo ""
    echo " Super+F1   Panic shutdown (instant)"
    echo " Super+F2   Nuclear wipe  (3× in 5s)"
    echo " Super+F3   Rotate MAC"
    echo " Super+F4   Full identity rotation"
    echo " Super+F5   Tor ON"
    echo " Super+F6   Tor OFF"
    echo " Super+F7   Kill webcam + mic"
    echo " Super+F8   Wipe logs"
    echo " Super+F9   Leak test"
    echo " Super+F10  Metadata wipe"
    echo " Super+F11  WiFi forget"
    echo " Super+F12  Vault"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
    echo ""
    echo "  ❌ xfconf-query wrote 0 shortcuts."
    echo "     Is xfconf-query installed? Try: sudo pacman -S xfconf"
    echo ""
    echo "  Falling back to xbindkeys instead..."

    sudo pacman -S --needed --noconfirm xbindkeys 2>/dev/null || true
    pkill -x xbindkeys 2>/dev/null; sleep 0.2

    cat > "$HOME/.xbindkeysrc" << XBRC
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

    xbindkeys && echo "  ✅ xbindkeys running — hotkeys active (won't show in XFCE UI but will work)"

    # Autostart xbindkeys on login
    mkdir -p "$HOME/.config/autostart"
    cat > "$HOME/.config/autostart/ghost-xbindkeys.desktop" << DESK
[Desktop Entry]
Type=Application
Name=Ghost Hotkeys
Exec=xbindkeys
X-GNOME-Autostart-enabled=true
DESK
fi
