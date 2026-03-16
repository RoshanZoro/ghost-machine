#!/bin/bash
# hotkeys_setup.sh — Configure Ghost Machine hotkeys
# Run as your DESKTOP USER (not root)

GHOST="/opt/ghost/scripts"

# ── 1. Install xbindkeys + xterm if missing ───────────────────────────────────
for PKG in xbindkeys xterm; do
    if ! command -v "$PKG" &>/dev/null; then
        echo "→ Installing $PKG..."
        sudo pacman -S --needed --noconfirm "$PKG" 2>/dev/null || true
    fi
done

# ── 2. sudoers rule so scripts run without password prompt ────────────────────
if [ ! -f /etc/sudoers.d/ghost ]; then
    echo "→ Writing sudoers rule (no password prompt for ghost scripts)..."
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
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/dns_hardening.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/intrusion_detection.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/tamper_detect.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/self_scan.sh
${USER} ALL=(ALL) NOPASSWD: ${GHOST}/ram_wipe.sh
${USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl poweroff
${USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl poweroff --force --force
${USER} ALL=(ALL) NOPASSWD: /sbin/poweroff
SUDOERS
    sudo chmod 440 /etc/sudoers.d/ghost
    echo "  done."
fi

# ── 3. xbindkeys as universal fallback (works on any DE) ─────────────────────
XBINDKEYS_RC="$HOME/.xbindkeysrc"
cat > "$XBINDKEYS_RC" << XBRC
# Ghost Machine hotkeys

# Super+F1 — Panic shutdown (no window — fires instantly)
"sudo ${GHOST}/panic_shutdown.sh"
  Super + F1

# Super+F2 — Nuclear wipe (triple press in 5s)
"xterm -title 'GHOST NUKE' -bg black -fg red -e sudo ${GHOST}/nuclear_wipe.sh"
  Super + F2

# Super+F3 — Rotate MAC
"xterm -title 'Ghost: MAC' -bg black -fg green -e sudo ${GHOST}/mac_randomize.sh"
  Super + F3

# Super+F4 — Full identity rotation
"xterm -title 'Ghost: Identity' -bg black -fg cyan -e sudo ${GHOST}/identity_randomize.sh"
  Super + F4

# Super+F5 — Tor ON
"xterm -title 'Ghost: Tor ON' -bg black -fg green -e sudo ${GHOST}/tor_enable.sh"
  Super + F5

# Super+F6 — Tor OFF
"xterm -title 'Ghost: Tor OFF' -bg black -fg yellow -e sudo ${GHOST}/tor_disable.sh"
  Super + F6

# Super+F7 — Kill webcam + mic
"xterm -title 'Ghost: A/V Kill' -bg black -fg red -e sudo ${GHOST}/kill_av.sh"
  Super + F7

# Super+F8 — Wipe logs
"xterm -title 'Ghost: Wipe' -bg black -fg magenta -e sudo ${GHOST}/wipe_logs.sh"
  Super + F8

# Super+F9 — Leak test
"xterm -title 'Ghost: Leak Test' -bg black -fg cyan -e sudo ${GHOST}/leak_test.sh"
  Super + F9

# Super+F10 — Metadata wipe (home dir)
"xterm -title 'Ghost: Metadata' -bg black -fg yellow -e sudo ${GHOST}/metadata_wipe.sh \${HOME}"
  Super + F10

# Super+F11 — WiFi forget
"xterm -title 'Ghost: WiFi Forget' -bg black -fg red -e sudo ${GHOST}/wifi_forget.sh"
  Super + F11

# Super+F12 — Vault
"xterm -title 'Ghost: Vault' -bg black -fg cyan -e sudo ${GHOST}/mount_vault.sh"
  Super + F12
XBRC

# Kill old xbindkeys, start fresh
pkill -x xbindkeys 2>/dev/null; sleep 0.3
xbindkeys
echo "→ xbindkeys started — hotkeys active now via xbindkeys."

# ── 4. XFCE keyboard shortcuts — direct XML write ─────────────────────────────
XFCE_KB_DIR="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
XFCE_KB_FILE="$XFCE_KB_DIR/xfce4-keyboard-shortcuts.xml"

if [ -d "$XFCE_KB_DIR" ] || [ -n "$XFCE_VERSION" ] || pgrep -x xfce4-session &>/dev/null || pgrep -x xfwm4 &>/dev/null; then
    echo "→ XFCE detected — writing keyboard shortcuts XML..."
    mkdir -p "$XFCE_KB_DIR"

    # If file exists, back it up
    [ -f "$XFCE_KB_FILE" ] && cp "$XFCE_KB_FILE" "${XFCE_KB_FILE}.bak"

    cat > "$XFCE_KB_FILE" << 'XFCEXML'
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xfce4-keyboard-shortcuts" version="1.0">
  <property name="commands" type="empty">
    <property name="default" type="empty">
      <property name="&lt;Alt&gt;F2" type="string" value="xfrun4"/>
      <property name="&lt;Alt&gt;F3" type="string" value="xfce4-appfinder"/>
    </property>
    <property name="custom" type="empty">
      <property name="&lt;Alt&gt;F2" type="string" value="xfrun4"/>
      <property name="&lt;Alt&gt;F3" type="string" value="xfce4-appfinder"/>
      <property name="override" type="bool" value="true"/>

      <!-- Ghost Machine Hotkeys -->
      <property name="&lt;Super&gt;F1" type="string" value="sudo /opt/ghost/scripts/panic_shutdown.sh"/>
      <property name="&lt;Super&gt;F2" type="string" value="xterm -title 'GHOST NUKE' -bg black -fg red -e sudo /opt/ghost/scripts/nuclear_wipe.sh"/>
      <property name="&lt;Super&gt;F3" type="string" value="xterm -title 'Ghost: MAC' -bg black -fg green -e sudo /opt/ghost/scripts/mac_randomize.sh"/>
      <property name="&lt;Super&gt;F4" type="string" value="xterm -title 'Ghost: Identity' -bg black -fg cyan -e sudo /opt/ghost/scripts/identity_randomize.sh"/>
      <property name="&lt;Super&gt;F5" type="string" value="xterm -title 'Ghost: Tor ON' -bg black -fg green -e sudo /opt/ghost/scripts/tor_enable.sh"/>
      <property name="&lt;Super&gt;F6" type="string" value="xterm -title 'Ghost: Tor OFF' -bg black -fg yellow -e sudo /opt/ghost/scripts/tor_disable.sh"/>
      <property name="&lt;Super&gt;F7" type="string" value="xterm -title 'Ghost: AV Kill' -bg black -fg red -e sudo /opt/ghost/scripts/kill_av.sh"/>
      <property name="&lt;Super&gt;F8" type="string" value="xterm -title 'Ghost: Wipe' -bg black -fg magenta -e sudo /opt/ghost/scripts/wipe_logs.sh"/>
      <property name="&lt;Super&gt;F9" type="string" value="xterm -title 'Ghost: Leak Test' -bg black -fg cyan -e sudo /opt/ghost/scripts/leak_test.sh"/>
      <property name="&lt;Super&gt;F10" type="string" value="xterm -title 'Ghost: Metadata' -bg black -fg yellow -e sudo /opt/ghost/scripts/metadata_wipe.sh $HOME"/>
      <property name="&lt;Super&gt;F11" type="string" value="xterm -title 'Ghost: WiFi Forget' -bg black -fg red -e sudo /opt/ghost/scripts/wifi_forget.sh"/>
      <property name="&lt;Super&gt;F12" type="string" value="xterm -title 'Ghost: Vault' -bg black -fg cyan -e sudo /opt/ghost/scripts/mount_vault.sh"/>
    </property>
  </property>
  <property name="xfwm4" type="empty">
    <property name="default" type="empty">
      <property name="&lt;Alt&gt;F4" type="string" value="close_window_key"/>
      <property name="&lt;Alt&gt;F6" type="string" value="stick_window_key"/>
      <property name="&lt;Alt&gt;F7" type="string" value="move_window_key"/>
      <property name="&lt;Alt&gt;F8" type="string" value="resize_window_key"/>
      <property name="&lt;Alt&gt;F9" type="string" value="hide_window_key"/>
      <property name="&lt;Alt&gt;F10" type="string" value="maximize_window_key"/>
      <property name="&lt;Alt&gt;F11" type="string" value="fullscreen_key"/>
      <property name="&lt;Alt&gt;F12" type="string" value="above_key"/>
      <property name="&lt;Alt&gt;Delete" type="string" value="del_workspace_key"/>
      <property name="&lt;Alt&gt;Insert" type="string" value="add_workspace_key"/>
      <property name="&lt;Alt&gt;Tab" type="string" value="cycle_windows_key"/>
      <property name="&lt;Shift&gt;&lt;Alt&gt;Tab" type="string" value="cycle_reverse_windows_key"/>
      <property name="&lt;Super&gt;Tab" type="string" value="switch_window_key"/>
    </property>
    <property name="custom" type="empty">
      <property name="override" type="bool" value="true"/>
      <property name="&lt;Alt&gt;F4" type="string" value="close_window_key"/>
      <property name="&lt;Alt&gt;F10" type="string" value="maximize_window_key"/>
      <property name="&lt;Alt&gt;Tab" type="string" value="cycle_windows_key"/>
    </property>
  </property>
</channel>
XFCEXML

    # Tell XFCE to reload its keyboard shortcuts live (no logout needed)
    if command -v xfconf-query &>/dev/null; then
        # Touch a property to force xfconfd to re-read the file
        xfconf-query -c xfce4-keyboard-shortcuts \
            -p "/commands/custom/<Super>F9" \
            -s "xterm -title 'Ghost: Leak Test' -bg black -fg cyan -e sudo /opt/ghost/scripts/leak_test.sh" \
            --create -t string 2>/dev/null || \
        xfconf-query -c xfce4-keyboard-shortcuts \
            -p "/commands/custom/<Super>F9" \
            -s "xterm -title 'Ghost: Leak Test' -bg black -fg cyan -e sudo /opt/ghost/scripts/leak_test.sh" 2>/dev/null || true
        echo "  XFCE shortcuts reloaded via xfconf-query."
    fi

    # Use xfconf-query to set each shortcut directly (most reliable method)
    echo "  Setting shortcuts via xfconf-query..."
    declare -A SHORTCUTS=(
        ["<Super>F1"]="sudo /opt/ghost/scripts/panic_shutdown.sh"
        ["<Super>F2"]="xterm -title 'GHOST NUKE' -bg black -fg red -e sudo /opt/ghost/scripts/nuclear_wipe.sh"
        ["<Super>F3"]="xterm -title 'Ghost: MAC' -bg black -fg green -e sudo /opt/ghost/scripts/mac_randomize.sh"
        ["<Super>F4"]="xterm -title 'Ghost: Identity' -bg black -fg cyan -e sudo /opt/ghost/scripts/identity_randomize.sh"
        ["<Super>F5"]="xterm -title 'Ghost: Tor ON' -bg black -fg green -e sudo /opt/ghost/scripts/tor_enable.sh"
        ["<Super>F6"]="xterm -title 'Ghost: Tor OFF' -bg black -fg yellow -e sudo /opt/ghost/scripts/tor_disable.sh"
        ["<Super>F7"]="xterm -title 'Ghost: AV Kill' -bg black -fg red -e sudo /opt/ghost/scripts/kill_av.sh"
        ["<Super>F8"]="xterm -title 'Ghost: Wipe' -bg black -fg magenta -e sudo /opt/ghost/scripts/wipe_logs.sh"
        ["<Super>F9"]="xterm -title 'Ghost: Leak Test' -bg black -fg cyan -e sudo /opt/ghost/scripts/leak_test.sh"
        ["<Super>F10"]="xterm -title 'Ghost: Metadata' -bg black -fg yellow -e sudo /opt/ghost/scripts/metadata_wipe.sh \$HOME"
        ["<Super>F11"]="xterm -title 'Ghost: WiFi Forget' -bg black -fg red -e sudo /opt/ghost/scripts/wifi_forget.sh"
        ["<Super>F12"]="xterm -title 'Ghost: Vault' -bg black -fg cyan -e sudo /opt/ghost/scripts/mount_vault.sh"
    )

    for KEY in "${!SHORTCUTS[@]}"; do
        CMD="${SHORTCUTS[$KEY]}"
        PROP="/commands/custom/${KEY}"
        # Try update first, then create
        xfconf-query -c xfce4-keyboard-shortcuts -p "$PROP" -s "$CMD" 2>/dev/null || \
        xfconf-query -c xfce4-keyboard-shortcuts -p "$PROP" -s "$CMD" --create -t string 2>/dev/null || true
    done

    echo "✅ XFCE shortcuts written. They are active immediately — no logout needed."
    echo "   You can verify in: Settings → Keyboard → Application Shortcuts"
fi

# ── 5. Autostart xbindkeys on login (backup for any WM) ──────────────────────
AUTOSTART_DIR="$HOME/.config/autostart"
mkdir -p "$AUTOSTART_DIR"
cat > "$AUTOSTART_DIR/ghost-xbindkeys.desktop" << DESKTOP
[Desktop Entry]
Type=Application
Name=Ghost Machine Hotkeys
Exec=xbindkeys
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Comment=Ghost Machine hotkey daemon
DESKTOP

grep -q "xbindkeys" "$HOME/.xprofile" 2>/dev/null || \
    echo "xbindkeys &" >> "$HOME/.xprofile"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " ✅ Ghost Machine hotkeys configured"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Super+F1   Panic shutdown (instant)"
echo " Super+F2   Nuclear wipe  (press 3× in 5s)"
echo " Super+F3   Rotate MAC"
echo " Super+F4   Full identity rotation"
echo " Super+F5   Tor ON + kill switch"
echo " Super+F6   Tor OFF"
echo " Super+F7   Kill webcam + mic"
echo " Super+F8   Wipe logs + history"
echo " Super+F9   Leak test"
echo " Super+F10  Metadata wipe"
echo " Super+F11  WiFi forget"
echo " Super+F12  Vault open/close"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Test now: press Super+F9 for leak test"
echo " Check in XFCE: Settings → Keyboard → Application Shortcuts"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
