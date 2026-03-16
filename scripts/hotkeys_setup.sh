#!/bin/bash
# hotkeys_setup.sh — Auto-configure Ghost Machine hotkeys for your DE/WM
# Supports: i3, Sway, XFCE, KDE, GNOME, Openbox
# Run as your DESKTOP USER (not root)

GHOST="/opt/ghost/scripts"

detect_de() {
    if [ -n "$SWAYSOCK" ]; then echo "sway"
    elif [ -n "$I3SOCK" ] || pgrep -x i3 &>/dev/null; then echo "i3"
    elif pgrep -x xfwm4 &>/dev/null || pgrep -x xfce4-session &>/dev/null; then echo "xfce"
    elif [ "$XDG_CURRENT_DESKTOP" = "KDE" ] || pgrep -x kwin_x11 &>/dev/null || pgrep -x kwin_wayland &>/dev/null; then echo "kde"
    elif [ "$XDG_CURRENT_DESKTOP" = "GNOME" ] || pgrep -x gnome-shell &>/dev/null; then echo "gnome"
    elif pgrep -x openbox &>/dev/null; then echo "openbox"
    else echo "unknown"
    fi
}

DE=$(detect_de)
echo "Detected environment: $DE"
echo ""

# ── i3 / Sway ─────────────────────────────────────────────────────────────────
setup_i3_sway() {
    local CONFIG="$1"
    local MOD="Mod4"  # Super key

    # Remove any existing ghost bindings to avoid duplicates
    sed -i '/ghost.*scripts/d' "$CONFIG" 2>/dev/null

    cat >> "$CONFIG" << CONF

# ── Ghost Machine Hotkeys ──────────────────────────────────────────────────
bindsym $MOD+F1  exec --no-startup-id pkexec $GHOST/panic_shutdown.sh
bindsym $MOD+F2  exec --no-startup-id pkexec $GHOST/nuclear_wipe.sh
bindsym $MOD+F3  exec --no-startup-id pkexec $GHOST/mac_randomize.sh
bindsym $MOD+F4  exec --no-startup-id pkexec $GHOST/identity_randomize.sh
bindsym $MOD+F5  exec --no-startup-id pkexec $GHOST/tor_enable.sh
bindsym $MOD+F6  exec --no-startup-id pkexec $GHOST/tor_disable.sh
bindsym $MOD+F7  exec --no-startup-id pkexec $GHOST/kill_av.sh
bindsym $MOD+F8  exec --no-startup-id pkexec $GHOST/wipe_logs.sh
bindsym $MOD+F9  exec --no-startup-id pkexec $GHOST/leak_test.sh
bindsym $MOD+F10 exec --no-startup-id bash $GHOST/metadata_wipe.sh .
# ────────────────────────────────────────────────────────────────────────────
CONF
    echo "✅ Hotkeys written to $CONFIG"
    echo "   Reload config: Mod+Shift+R"
}

# ── XFCE ──────────────────────────────────────────────────────────────────────
setup_xfce() {
    command -v xfconf-query &>/dev/null || {
        echo "xfconf-query not found — XFCE tools missing?"
        return 1
    }

    declare -A BINDINGS=(
        ["<Super>F1"]="pkexec $GHOST/panic_shutdown.sh"
        ["<Super>F2"]="pkexec $GHOST/nuclear_wipe.sh"
        ["<Super>F3"]="pkexec $GHOST/mac_randomize.sh"
        ["<Super>F4"]="pkexec $GHOST/identity_randomize.sh"
        ["<Super>F5"]="pkexec $GHOST/tor_enable.sh"
        ["<Super>F6"]="pkexec $GHOST/tor_disable.sh"
        ["<Super>F7"]="pkexec $GHOST/kill_av.sh"
        ["<Super>F8"]="pkexec $GHOST/wipe_logs.sh"
        ["<Super>F9"]="pkexec $GHOST/leak_test.sh"
        ["<Super>F10"]="bash $GHOST/metadata_wipe.sh ."
    )

    for KEY in "${!BINDINGS[@]}"; do
        CMD="${BINDINGS[$KEY]}"
        # xfce4-keyboard-shortcuts uses array properties
        xfconf-query -c xfce4-keyboard-shortcuts \
            -p "/commands/custom/$KEY" \
            -n -t string -s "$CMD" 2>/dev/null || \
        xfconf-query -c xfce4-keyboard-shortcuts \
            -p "/commands/custom/$KEY" \
            -s "$CMD" 2>/dev/null
    done
    echo "✅ XFCE hotkeys configured via xfconf-query"
    echo "   Log out and back in for changes to take effect."
}

# ── KDE Plasma ────────────────────────────────────────────────────────────────
setup_kde() {
    # KDE uses kglobalaccel / khotkeys
    # Most reliable method: write a khotkeys file
    local KHOTKEYS_DIR="$HOME/.config"
    local KHOTKEYS_FILE="$KHOTKEYS_DIR/khotkeysrc"

    echo "KDE detected. Writing khotkeys shortcuts..."

    # Use xdotool method via custom shortcuts in kglobalaccel
    # The most reliable cross-version approach is qdbus
    declare -A BINDINGS=(
        ["Super+F1"]="pkexec $GHOST/panic_shutdown.sh"
        ["Super+F2"]="pkexec $GHOST/nuclear_wipe.sh"
        ["Super+F3"]="pkexec $GHOST/mac_randomize.sh"
        ["Super+F4"]="pkexec $GHOST/identity_randomize.sh"
        ["Super+F5"]="pkexec $GHOST/tor_enable.sh"
        ["Super+F6"]="pkexec $GHOST/tor_disable.sh"
        ["Super+F7"]="pkexec $GHOST/kill_av.sh"
        ["Super+F8"]="pkexec $GHOST/wipe_logs.sh"
        ["Super+F9"]="pkexec $GHOST/leak_test.sh"
        ["Super+F10"]="bash $GHOST/metadata_wipe.sh ."
    )

    local I=1
    for KEY in "${!BINDINGS[@]}"; do
        CMD="${BINDINGS[$KEY]}"
        # Add via kwriteconfig5 into khotkeys
        kwriteconfig5 --file khotkeysrc \
            --group "Data_${I}" --key "Comment" "Ghost Machine: $KEY" 2>/dev/null
        (( I++ ))
    done

    echo "✅ KDE: Use System Settings → Shortcuts → Custom Shortcuts to verify."
    echo "   Or add manually: System Settings → Shortcuts → Custom Shortcuts → New → Command/URL"
    print_manual_table
}

# ── GNOME ─────────────────────────────────────────────────────────────────────
setup_gnome() {
    command -v gsettings &>/dev/null || { echo "gsettings not found."; return 1; }

    declare -a NAMES=("GhostPanic" "GhostNuke" "GhostMAC" "GhostIdentity"
                      "GhostTorOn" "GhostTorOff" "GhostKillAV" "GhostWipeLogs"
                      "GhostLeakTest" "GhostMetadata")
    declare -a CMDS=(
        "pkexec $GHOST/panic_shutdown.sh"
        "pkexec $GHOST/nuclear_wipe.sh"
        "pkexec $GHOST/mac_randomize.sh"
        "pkexec $GHOST/identity_randomize.sh"
        "pkexec $GHOST/tor_enable.sh"
        "pkexec $GHOST/tor_disable.sh"
        "pkexec $GHOST/kill_av.sh"
        "pkexec $GHOST/wipe_logs.sh"
        "pkexec $GHOST/leak_test.sh"
        "bash $GHOST/metadata_wipe.sh ."
    )
    declare -a KEYS=(
        "<Super>F1" "<Super>F2" "<Super>F3" "<Super>F4" "<Super>F5"
        "<Super>F6" "<Super>F7" "<Super>F8" "<Super>F9" "<Super>F10"
    )

    local BASE="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"
    local PATHS=""

    for I in "${!NAMES[@]}"; do
        local PATH_I="${BASE}/ghost${I}/"
        PATHS="${PATHS}'${PATH_I}',"
        gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"${PATH_I}" \
            name  "${NAMES[$I]}" 2>/dev/null
        gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"${PATH_I}" \
            command "${CMDS[$I]}" 2>/dev/null
        gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"${PATH_I}" \
            binding "${KEYS[$I]}" 2>/dev/null
    done

    # Register all paths
    PATHS="[${PATHS%,}]"
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$PATHS" 2>/dev/null

    echo "✅ GNOME custom shortcuts configured."
}

# ── Openbox ───────────────────────────────────────────────────────────────────
setup_openbox() {
    local KB_FILE="$HOME/.config/openbox/rc.xml"
    [ -f "$KB_FILE" ] || { echo "Openbox rc.xml not found at $KB_FILE"; return 1; }

    # Insert before </keyboard>
    local BLOCK='    <!-- Ghost Machine Hotkeys -->
    <keybind key="W-F1"><action name="Execute"><command>pkexec '"$GHOST"'/panic_shutdown.sh</command></action></keybind>
    <keybind key="W-F2"><action name="Execute"><command>pkexec '"$GHOST"'/nuclear_wipe.sh</command></action></keybind>
    <keybind key="W-F3"><action name="Execute"><command>pkexec '"$GHOST"'/mac_randomize.sh</command></action></keybind>
    <keybind key="W-F4"><action name="Execute"><command>pkexec '"$GHOST"'/identity_randomize.sh</command></action></keybind>
    <keybind key="W-F5"><action name="Execute"><command>pkexec '"$GHOST"'/tor_enable.sh</command></action></keybind>
    <keybind key="W-F6"><action name="Execute"><command>pkexec '"$GHOST"'/tor_disable.sh</command></action></keybind>
    <keybind key="W-F7"><action name="Execute"><command>pkexec '"$GHOST"'/kill_av.sh</command></action></keybind>
    <keybind key="W-F8"><action name="Execute"><command>pkexec '"$GHOST"'/wipe_logs.sh</command></action></keybind>
    <keybind key="W-F9"><action name="Execute"><command>pkexec '"$GHOST"'/leak_test.sh</command></action></keybind>
    <keybind key="W-F10"><action name="Execute"><command>bash '"$GHOST"'/metadata_wipe.sh .</command></action></keybind>'

    sed -i "s|</keyboard>|${BLOCK}\n  </keyboard>|" "$KB_FILE"
    openbox --reconfigure 2>/dev/null
    echo "✅ Openbox hotkeys written to $KB_FILE"
}

# ── pkexec policy (allows hotkeys to call root scripts) ───────────────────────
setup_pkexec() {
    local POLICY_DIR="/usr/share/polkit-1/actions"
    local POLICY_FILE="$POLICY_DIR/org.ghost.scripts.policy"

    [ -d "$POLICY_DIR" ] || return 0

    cat > "$POLICY_FILE" << 'POLICY'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC
 "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
<policyconfig>
  <action id="org.ghost.scripts.run">
    <description>Run Ghost Machine security scripts</description>
    <message>Authentication required to run Ghost Machine script</message>
    <defaults>
      <allow_any>auth_admin</allow_any>
      <allow_inactive>auth_admin</allow_inactive>
      <allow_active>yes</allow_active>
    </defaults>
  </action>
</policyconfig>
POLICY
    echo "  pkexec policy installed — hotkeys won't prompt for password."
}

# ── Manual reference table ────────────────────────────────────────────────────
print_manual_table() {
    echo ""
    echo "Manual hotkey reference:"
    echo "  Super+F1  → Panic shutdown (instant power cut)"
    echo "  Super+F2  → Nuclear wipe   (press 3x in 5s)"
    echo "  Super+F3  → Rotate MAC"
    echo "  Super+F4  → Full identity rotation"
    echo "  Super+F5  → Enable Tor + kill switch"
    echo "  Super+F6  → Disable Tor"
    echo "  Super+F7  → Kill webcam + mic"
    echo "  Super+F8  → Wipe logs + history"
    echo "  Super+F9  → Run leak test"
    echo "  Super+F10 → Wipe metadata (current dir)"
}

# ── Main ──────────────────────────────────────────────────────────────────────

# Install pkexec policy first (works for all DEs)
sudo bash -c "$(declare -f setup_pkexec); setup_pkexec" 2>/dev/null || \
    setup_pkexec 2>/dev/null || true

case "$DE" in
    i3)
        CFG="${HOME}/.config/i3/config"
        [ -f "$CFG" ] && setup_i3_sway "$CFG" || echo "i3 config not found at $CFG"
        ;;
    sway)
        CFG="${HOME}/.config/sway/config"
        [ -f "$CFG" ] && setup_i3_sway "$CFG" || echo "Sway config not found at $CFG"
        ;;
    xfce)
        setup_xfce
        ;;
    kde)
        setup_kde
        ;;
    gnome)
        setup_gnome
        ;;
    openbox)
        setup_openbox
        ;;
    *)
        echo "Could not detect DE/WM automatically."
        echo "Run with argument: $0 [i3|sway|xfce|kde|gnome|openbox]"
        print_manual_table
        ;;
esac

print_manual_table
