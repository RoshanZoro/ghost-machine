#!/bin/bash
# hotkeys_setup.sh — Configure Ghost Machine hotkeys via xbindkeys
# Works on ANY DE/WM (XFCE, KDE, GNOME, i3, Openbox, bare X11, etc.)
# Run as your DESKTOP USER (not root)

GHOST="/opt/ghost/scripts"

# ── 1. Install xbindkeys if missing ──────────────────────────────────────────
if ! command -v xbindkeys &>/dev/null; then
    echo "→ Installing xbindkeys..."
    sudo pacman -S --needed --noconfirm xbindkeys 2>/dev/null || {
        echo "  [!!] Could not install xbindkeys — run: sudo pacman -S xbindkeys"
        exit 1
    }
fi

# ── 2. Install xterm for script output windows ───────────────────────────────
if ! command -v xterm &>/dev/null; then
    echo "→ Installing xterm (used to show script output)..."
    sudo pacman -S --needed --noconfirm xterm 2>/dev/null || true
fi

# ── 3. Write polkit rule so scripts run as root WITHOUT password prompt ───────
POLKIT_RULE="/etc/polkit-1/rules.d/49-ghost.rules"
if [ ! -f "$POLKIT_RULE" ]; then
    echo "→ Writing polkit rule (allows ghost scripts to run as root without password)..."
    sudo tee "$POLKIT_RULE" > /dev/null << 'POLKIT'
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.policykit.exec" &&
        action.lookup("program").indexOf("/opt/ghost/scripts/") === 0 &&
        subject.local && subject.active) {
        return polkit.Result.YES;
    }
});
POLKIT
    echo "  Polkit rule written."
fi

# ── 4. Also write a sudoers rule as fallback ──────────────────────────────────
SUDOERS_FILE="/etc/sudoers.d/ghost"
if [ ! -f "$SUDOERS_FILE" ]; then
    echo "→ Writing sudoers rule..."
    sudo tee "$SUDOERS_FILE" > /dev/null << SUDOERS
# Ghost Machine — allow desktop user to run ghost scripts without password
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/panic_shutdown.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/nuclear_wipe.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/mac_randomize.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/mac_scheduler.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/identity_randomize.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/tor_enable.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/tor_disable.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/kill_av.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/wipe_logs.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/leak_test.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/metadata_wipe.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/dns_hardening.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/wifi_forget.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/intrusion_detection.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/tamper_detect.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/self_scan.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/ram_wipe.sh
${USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl poweroff
${USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl poweroff --force
${USER} ALL=(ALL) NOPASSWD: /sbin/poweroff
SUDOERS
    sudo chmod 440 "$SUDOERS_FILE"
    echo "  Sudoers rule written."
fi

# ── 5. Write .xbindkeysrc ────────────────────────────────────────────────────
XBINDKEYS_RC="$HOME/.xbindkeysrc"
echo "→ Writing $XBINDKEYS_RC..."

cat > "$XBINDKEYS_RC" << XBRC
# Ghost Machine hotkeys — managed by hotkeys_setup.sh
# Uses xterm to show output. Close the window when done.

# Super+F1 — Panic shutdown (INSTANT — no window, fires immediately)
"sudo ${GHOST}/panic_shutdown.sh"
  Super + F1

# Super+F2 — Nuclear wipe (triple-press trigger)
"xterm -title 'GHOST NUKE' -bg black -fg red -e sudo ${GHOST}/nuclear_wipe.sh"
  Super + F2

# Super+F3 — Rotate MAC address
"xterm -title 'Ghost: MAC Rotate' -bg black -fg green -e sudo ${GHOST}/mac_randomize.sh"
  Super + F3

# Super+F4 — Full identity rotation
"xterm -title 'Ghost: Identity' -bg black -fg cyan -e sudo ${GHOST}/identity_randomize.sh"
  Super + F4

# Super+F5 — Enable Tor + kill switch
"xterm -title 'Ghost: Tor ON' -bg black -fg green -e sudo ${GHOST}/tor_enable.sh"
  Super + F5

# Super+F6 — Disable Tor
"xterm -title 'Ghost: Tor OFF' -bg black -fg yellow -e sudo ${GHOST}/tor_disable.sh"
  Super + F6

# Super+F7 — Kill webcam + mic
"xterm -title 'Ghost: A/V Kill' -bg black -fg red -e sudo ${GHOST}/kill_av.sh"
  Super + F7

# Super+F8 — Wipe logs + history
"xterm -title 'Ghost: Wipe Logs' -bg black -fg magenta -e sudo ${GHOST}/wipe_logs.sh"
  Super + F8

# Super+F9 — Run leak test
"xterm -title 'Ghost: Leak Test' -bg black -fg cyan -e sudo ${GHOST}/leak_test.sh"
  Super + F9

# Super+F10 — Wipe metadata in current dir
"xterm -title 'Ghost: Metadata Wipe' -bg black -fg yellow -e sudo ${GHOST}/metadata_wipe.sh \${HOME}"
  Super + F10

# Super+F11 — WiFi forget all profiles
"xterm -title 'Ghost: WiFi Forget' -bg black -fg red -e sudo ${GHOST}/wifi_forget.sh"
  Super + F11

# Super+F12 — Mount/unmount encrypted vault
"xterm -title 'Ghost: Vault' -bg black -fg cyan -e sudo ${GHOST}/mount_vault.sh"
  Super + F12
XBRC

echo "  Written."

# ── 6. Kill any existing xbindkeys, start fresh ───────────────────────────────
echo "→ Starting xbindkeys..."
pkill -x xbindkeys 2>/dev/null || true
sleep 0.5
xbindkeys 2>/dev/null &
disown

# Verify it started
sleep 1
if pgrep -x xbindkeys &>/dev/null; then
    echo "  xbindkeys running — hotkeys active NOW."
else
    echo "  [!!] xbindkeys failed to start."
    echo "       Try running manually: xbindkeys --verbose"
    exit 1
fi

# ── 7. Make xbindkeys start automatically on login ────────────────────────────
echo "→ Adding xbindkeys to autostart..."

# Method A: ~/.config/autostart (works for XFCE, KDE, GNOME, most DEs)
AUTOSTART_DIR="$HOME/.config/autostart"
mkdir -p "$AUTOSTART_DIR"
cat > "$AUTOSTART_DIR/xbindkeys.desktop" << DESKTOP
[Desktop Entry]
Type=Application
Name=xbindkeys
Exec=xbindkeys
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Comment=Ghost Machine hotkey daemon
DESKTOP
echo "  Autostart entry written to $AUTOSTART_DIR/xbindkeys.desktop"

# Method B: ~/.xinitrc / ~/.xprofile fallback (bare WMs like i3 that don't use autostart)
for RC in "$HOME/.xprofile" "$HOME/.xinitrc"; do
    if [ -f "$RC" ] || echo "$RC" | grep -q "xprofile"; then
        if ! grep -q "xbindkeys" "$RC" 2>/dev/null; then
            echo "xbindkeys &" >> "$RC"
            echo "  Added xbindkeys to $RC"
        fi
    fi
done

# Always write .xprofile since it's the most universal
if ! grep -q "xbindkeys" "$HOME/.xprofile" 2>/dev/null; then
    echo "xbindkeys &" >> "$HOME/.xprofile"
    echo "  Added to ~/.xprofile"
fi

# ── 8. Test a binding ─────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " ✅ Ghost Machine hotkeys are ACTIVE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo " Super+F1   Panic shutdown    (instant, no window)"
echo " Super+F2   Nuclear wipe      (press 3× in 5s)"
echo " Super+F3   Rotate MAC"
echo " Super+F4   Identity rotation"
echo " Super+F5   Tor ON"
echo " Super+F6   Tor OFF"
echo " Super+F7   Kill webcam + mic"
echo " Super+F8   Wipe logs"
echo " Super+F9   Leak test"
echo " Super+F10  Metadata wipe"
echo " Super+F11  WiFi forget"
echo " Super+F12  Vault open/close"
echo ""
echo " Test now — press Super+F9 to run leak test."
echo " If hotkeys stop working after reboot, run:"
echo "   xbindkeys"
echo ""
