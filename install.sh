#!/bin/bash
# install.sh — Deploy Ghost Machine scripts, services, and config
# Run as root: sudo bash install.sh

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
ERRORS=()
# The actual desktop user who ran sudo — needed for AUR builds and DE hotkeys
BUILD_USER="${SUDO_USER:-$USER}"
[ "$BUILD_USER" = "root" ] && BUILD_USER=$(who | awk 'NR==1{print $1}')

mkdir -p "$INSTALL_DIR"
mkdir -p /var/log/ghost /var/lib/ghost /var/lib/ghost/tamper

# ═════════════════════════════════════════════════════════════
# HELPERS
# ═════════════════════════════════════════════════════════════

# Sync package DB once at start (stale DB causes "not found" errors)
echo "→ Syncing package database..."
pacman -Sy --noconfirm 2>/dev/null || true

install_pkg() {
    local PKG="$1"
    pacman -Qi "$PKG" &>/dev/null && { echo "  [ok] $PKG"; return 0; }
    if pacman -S --needed --noconfirm "$PKG" 2>/dev/null; then
        echo "  [ok] $PKG"
    else
        echo "  [!!] $PKG — not in repos"
        ERRORS+=("PACKAGE MISSING: $PKG")
        return 1
    fi
}

# AUR: yay → paru → manual makepkg from AUR git
install_aur() {
    local PKG="$1"
    pacman -Qi "$PKG" &>/dev/null && { echo "  [ok] $PKG (already installed)"; return 0; }
    command -v "$PKG" &>/dev/null && { echo "  [ok] $PKG (binary found)"; return 0; }

    # yay
    if command -v yay &>/dev/null; then
        sudo -u "$BUILD_USER" yay -S --needed --noconfirm "$PKG" 2>/dev/null && \
            { echo "  [ok] $PKG (yay)"; return 0; }
    fi
    # paru
    if command -v paru &>/dev/null; then
        sudo -u "$BUILD_USER" paru -S --needed --noconfirm "$PKG" 2>/dev/null && \
            { echo "  [ok] $PKG (paru)"; return 0; }
    fi
    # direct makepkg
    echo "  No AUR helper — building $PKG from AUR directly..."
    pacman -S --needed --noconfirm base-devel git 2>/dev/null || true
    local DIR; DIR=$(mktemp -d /tmp/aur_XXXXXX)
    chown -R "$BUILD_USER" "$DIR"
    if sudo -u "$BUILD_USER" git clone --depth=1 \
        "https://aur.archlinux.org/${PKG}.git" "${DIR}/${PKG}" 2>/dev/null; then
        if sudo -u "$BUILD_USER" bash -c \
            "cd '${DIR}/${PKG}' && makepkg -si --noconfirm" 2>/dev/null; then
            echo "  [ok] $PKG (built from AUR)"
            rm -rf "$DIR"; return 0
        fi
    fi
    rm -rf "$DIR"
    echo "  [!!] $PKG AUR build failed"
    ERRORS+=("AUR BUILD FAILED: $PKG")
    return 1
}

# secure-delete: AUR → upstream tarball compile
install_secure_delete() {
    command -v sdmem &>/dev/null && { echo "  [ok] secure-delete (sdmem found)"; return 0; }
    pacman -Qi secure-delete &>/dev/null && { echo "  [ok] secure-delete"; return 0; }

    install_aur "secure-delete" && return 0

    echo "  Trying upstream tarball build..."
    pacman -S --needed --noconfirm gcc make 2>/dev/null || true
    local TMP; TMP=$(mktemp -d /tmp/sdel_XXXXXX)
    local URL="https://src.fedoraproject.org/repo/pkgs/secure-delete/secure_delete-3.1.tar.gz/secure_delete-3.1.tar.gz"
    if curl -fsSL "$URL" -o "$TMP/sd.tar.gz" 2>/dev/null || \
       wget -q    "$URL" -O "$TMP/sd.tar.gz" 2>/dev/null; then
        tar -xzf "$TMP/sd.tar.gz" -C "$TMP" 2>/dev/null
        local SRC; SRC=$(find "$TMP" -name Makefile -maxdepth 3 | head -1 | xargs -I{} dirname {})
        if [ -n "$SRC" ] && make -C "$SRC" 2>/dev/null; then
            for BIN in sdmem srm sfill sswap; do
                [ -f "$SRC/$BIN" ] && install -m755 "$SRC/$BIN" /usr/local/bin/
            done
            echo "  [ok] secure-delete (upstream tarball)"
            rm -rf "$TMP"; return 0
        fi
    fi
    rm -rf "$TMP"
    echo "  [!!] secure-delete — all methods failed (ram_wipe uses dd fallback)"
    ERRORS+=("INFO: secure-delete unavailable — ram_wipe.sh uses dd only")
    return 1
}

# mat2: AUR → pip
# pamac: Manjaro's built-in AUR helper — use it if available
install_aur_pamac_first() {
    local PKG="$1"
    pacman -Qi "$PKG" &>/dev/null && { echo "  [ok] $PKG (already installed)"; return 0; }
    # pamac is Manjaro's default — try it first, no sudo needed
    if command -v pamac &>/dev/null; then
        pamac build --no-confirm "$PKG" 2>/dev/null &&             { echo "  [ok] $PKG (pamac)"; return 0; }
    fi
    # Fall through to generic install_aur
    install_aur "$PKG"
}

# aide: AUR on Manjaro (package name is just "aide")
install_aide() {
    if pacman -Qi aide &>/dev/null || command -v aide &>/dev/null; then
        echo "  [ok] aide (already installed)"; return 0
    fi
    echo "  Installing aide (AUR)..."
    install_aur_pamac_first "aide" && return 0
    echo "  [!!] aide not installed — intrusion_detection.sh will warn on first run"
    ERRORS+=("INFO: aide unavailable — run: yay -S aide  or  pamac build aide")
    return 1
}

# fswebcam: AUR only — used by tamper_detect.sh (ffmpeg is the primary fallback)
install_fswebcam() {
    if pacman -Qi fswebcam &>/dev/null || command -v fswebcam &>/dev/null; then
        echo "  [ok] fswebcam (already installed)"; return 0
    fi
    echo "  Installing fswebcam (AUR)..."
    install_aur_pamac_first "fswebcam" && return 0
    echo "  [!!] fswebcam not installed — tamper_detect.sh will use ffmpeg instead (already installed)"
    ERRORS+=("INFO: fswebcam unavailable — tamper_detect.sh uses ffmpeg fallback (fine)")
    return 1
}

# xautolock: AUR only — used for auto screen lock. xss-lock is already installed as replacement.
install_xautolock() {
    if pacman -Qi xautolock &>/dev/null || command -v xautolock &>/dev/null; then
        echo "  [ok] xautolock (already installed)"; return 0
    fi
    echo "  Installing xautolock (AUR)..."
    install_aur_pamac_first "xautolock" && return 0
    # xss-lock is the official-repo alternative and is already installed
    echo "  [!!] xautolock not installed — xss-lock is available as replacement"
    ERRORS+=("INFO: xautolock unavailable — xss-lock installed instead (same purpose)")
    return 1
}

install_mat2() {
    command -v mat2 &>/dev/null && { echo "  [ok] mat2"; return 0; }
    install_aur "mat2" && return 0
    pip install mat2 --break-system-packages 2>/dev/null && \
        { echo "  [ok] mat2 (pip)"; return 0; }
    echo "  [!!] mat2 unavailable — metadata_wipe.sh uses exiftool only"
    ERRORS+=("INFO: mat2 unavailable — exiftool fallback active")
    return 1
}

# LibreWolf: AUR (librewolf-bin is fastest, avoids full compile)
install_librewolf() {
    command -v librewolf &>/dev/null && { echo "  [ok] LibreWolf (already installed)"; return 0; }
    pacman -Qi librewolf &>/dev/null || pacman -Qi librewolf-bin &>/dev/null && \
        { echo "  [ok] LibreWolf"; return 0; }

    echo "  Installing LibreWolf..."
    # Try librewolf-bin first (pre-compiled, much faster)
    install_aur "librewolf-bin" && return 0
    # Fallback to source build
    install_aur "librewolf" && return 0
    echo "  [!!] LibreWolf install failed"
    ERRORS+=("BROWSER: LibreWolf not installed — install manually: yay -S librewolf-bin")
    return 1
}

# Tor Browser: torbrowser-launcher is in official Manjaro repos
install_tor_browser() {
    command -v torbrowser-launcher &>/dev/null && \
        { echo "  [ok] Tor Browser launcher (already installed)"; return 0; }
    pacman -Qi torbrowser-launcher &>/dev/null && \
        { echo "  [ok] torbrowser-launcher"; return 0; }

    echo "  Installing Tor Browser launcher..."
    # torbrowser-launcher is in Manjaro community repos
    if pacman -S --needed --noconfirm torbrowser-launcher 2>/dev/null; then
        echo "  [ok] torbrowser-launcher"
        echo "  Run 'torbrowser-launcher' as your user to complete Tor Browser setup."
        return 0
    fi
    # AUR fallback
    install_aur "torbrowser-launcher" && return 0
    echo "  [!!] Tor Browser launcher not installed"
    ERRORS+=("BROWSER: torbrowser-launcher not installed — install manually: pacman -S torbrowser-launcher")
    return 1
}

run_step() {
    local LABEL="$1"; shift
    echo "→ $LABEL..."
    if "$@" 2>/dev/null; then echo "  done."
    else
        echo "  [!!] Failed: $LABEL"
        ERRORS+=("STEP FAILED: $LABEL")
    fi
}

# ═════════════════════════════════════════════════════════════
# 1. Official repo packages
#    Correct Manjaro/Arch package names verified:
#    - aide       → AUR only, handled separately
#    - xautolock  → AUR only; replaced with xss-lock (official repos)
#    - xprintidle → xprintidle (community)
# ═════════════════════════════════════════════════════════════
echo ""
echo "→ Installing official repo packages..."
for PKG in \
    macchanger \
    tor \
    torsocks \
    usbguard \
    bleachbit \
    xss-lock \
    xprintidle \
    inotify-tools \
    procps-ng \
    util-linux \
    coreutils \
    nftables \
    sqlite \
    audit \
    nmap \
    curl \
    wget \
    git \
    base-devel \
    bind \
    perl-image-exiftool \
    dnscrypt-proxy \
    gcc \
    make \
    python-pip \
    ffmpeg \
    xbindkeys \
    xterm
do
    install_pkg "$PKG"
done

# ═════════════════════════════════════════════════════════════
# 2. AUR / special packages
# ═════════════════════════════════════════════════════════════
echo ""
echo "→ Installing AUR and special packages..."
install_secure_delete
install_mat2
install_librewolf
install_tor_browser
install_aide
install_fswebcam
install_xautolock

# ═════════════════════════════════════════════════════════════
# 3. Copy scripts
# ═════════════════════════════════════════════════════════════
echo ""
run_step "Copying scripts to $INSTALL_DIR" bash -c "
    cp scripts/*.sh '$INSTALL_DIR/' &&
    chmod +x '$INSTALL_DIR'/*.sh
"

# ═════════════════════════════════════════════════════════════
# 4. Systemd services
# ═════════════════════════════════════════════════════════════
echo ""
echo "→ Installing systemd services..."
cp systemd/*.service /etc/systemd/system/
systemctl daemon-reload

# mac-randomize: start immediately
systemctl enable --now mac-randomize.service 2>/dev/null && \
    echo "  [ok] mac-randomize.service" || \
    ERRORS+=("SERVICE FAILED: mac-randomize.service")

# idle-shutdown: enable only — starts automatically after next login
# Do NOT start now — it requires a live graphical session
systemctl enable idle-shutdown.service 2>/dev/null && \
    echo "  [ok] idle-shutdown.service (starts after next login)" || \
    ERRORS+=("SERVICE FAILED: idle-shutdown.service")
systemctl enable ram-wipe.service 2>/dev/null && \
    echo "  [ok] ram-wipe.service (activates at shutdown)" || \
    ERRORS+=("SERVICE FAILED: ram-wipe.service")

# USBGuard — generate policy from currently plugged-in devices
if [ ! -s /etc/usbguard/rules.conf ]; then
    echo "  Generating USBGuard policy..."
    usbguard generate-policy > /etc/usbguard/rules.conf 2>/dev/null || true
fi
systemctl enable --now usbguard.service 2>/dev/null && \
    echo "  [ok] usbguard.service" || \
    echo "  [!!] usbguard failed to start (may need reboot)"

# ═════════════════════════════════════════════════════════════
# 5. Kernel hardening
# ═════════════════════════════════════════════════════════════
echo ""
run_step "Applying sysctl kernel hardening" bash -c "
    cp config/99-ghost.conf /etc/sysctl.d/ &&
    sysctl --quiet -p /etc/sysctl.d/99-ghost.conf
"

# ═════════════════════════════════════════════════════════════
# 6. Firewall
# ═════════════════════════════════════════════════════════════
echo ""
run_step "Applying nftables firewall" bash -c "
    cp config/nftables.conf /etc/nftables.conf &&
    systemctl enable --now nftables.service
"

# ═════════════════════════════════════════════════════════════
# 7. Cron jobs
# ═════════════════════════════════════════════════════════════
echo ""
run_step "Installing cron jobs" bash -c "
    cp config/ghost.cron /etc/cron.d/ghost &&
    chmod 644 /etc/cron.d/ghost
"

# ═════════════════════════════════════════════════════════════
# 8. Tor config
# ═════════════════════════════════════════════════════════════
echo ""
echo "→ Configuring Tor..."
if [ -f /etc/tor/torrc ]; then
    if ! grep -q "TransPort 9040" /etc/tor/torrc; then
        cat config/torrc.append >> /etc/tor/torrc
        echo "  Tor config appended."
    else
        echo "  Tor config already applied, skipping."
    fi
else
    ERRORS+=("SKIPPED: /etc/tor/torrc missing — Tor may not have installed")
fi

# ═════════════════════════════════════════════════════════════
# 9. Disable IPv6 in GRUB
# ═════════════════════════════════════════════════════════════
echo ""
echo "→ Disabling IPv6 in GRUB..."
if ! grep -q "ipv6.disable" /etc/default/grub; then
    sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="ipv6.disable=1 /' /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null && \
        echo "  IPv6 disabled in GRUB." || \
        ERRORS+=("GRUB update failed — run: sudo grub-mkconfig -o /boot/grub/grub.cfg")
else
    echo "  IPv6 already disabled."
fi

# ═════════════════════════════════════════════════════════════
# 10. Shell history lockout
# ═════════════════════════════════════════════════════════════
echo ""
echo "→ Disabling shell history for root..."
ln -sf /dev/null /root/.bash_history
grep -q "HISTFILE=/dev/null" /root/.bashrc 2>/dev/null || \
    echo "HISTFILE=/dev/null" >> /root/.bashrc
# Also disable for the desktop user
USER_HOME=$(eval echo "~$BUILD_USER")
[ -f "$USER_HOME/.bashrc" ] && \
    grep -q "HISTFILE=/dev/null" "$USER_HOME/.bashrc" || \
    echo "HISTFILE=/dev/null" >> "$USER_HOME/.bashrc" 2>/dev/null || true
[ -f "$USER_HOME/.zshrc" ] && \
    grep -q "HISTFILE=/dev/null" "$USER_HOME/.zshrc" || \
    echo "HISTFILE=/dev/null" >> "$USER_HOME/.zshrc" 2>/dev/null || true
echo "  done."

# ═════════════════════════════════════════════════════════════
# 11. dnscrypt-proxy
# ═════════════════════════════════════════════════════════════
echo ""
echo "→ Configuring dnscrypt-proxy..."
if pacman -Qi dnscrypt-proxy &>/dev/null; then
    bash "$INSTALL_DIR/dns_hardening.sh" 2>/dev/null && \
        echo "  dnscrypt-proxy configured." || \
        echo "  [!!] dnscrypt-proxy config failed — run dns_hardening.sh manually"
fi

# ═════════════════════════════════════════════════════════════
# 12. Hotkeys — write files as desktop user, autostart on login
#     xbindkeys CANNOT be started from this root installer session.
#     We write all the files here; xbindkeys starts automatically
#     on the user's next login via the autostart .desktop entry.
# ═════════════════════════════════════════════════════════════
echo ""
echo "→ Configuring hotkeys for $BUILD_USER..."

USER_HOME=$(eval echo "~$BUILD_USER")
GHOST_DIR="$INSTALL_DIR"

# Write .xbindkeysrc with correct Mod4 key names and Monospace font
cat > "$USER_HOME/.xbindkeysrc" << XBRC
# Ghost Machine hotkeys — Mod4 = Super/Windows key

"sudo ${GHOST_DIR}/panic_shutdown.sh"
  Mod4+F1

"xterm -title 'GHOST NUKE' -bg black -fg red -fa Monospace -fs 11 -e sudo ${GHOST_DIR}/nuclear_wipe.sh"
  Mod4+F2

"xterm -title 'Ghost: MAC' -bg black -fg green -fa Monospace -fs 11 -e sudo ${GHOST_DIR}/mac_randomize.sh"
  Mod4+F3

"xterm -title 'Ghost: Identity' -bg black -fg cyan -fa Monospace -fs 11 -e sudo ${GHOST_DIR}/identity_randomize.sh"
  Mod4+F4

"xterm -title 'Ghost: Tor ON' -bg black -fg green -fa Monospace -fs 11 -e sudo ${GHOST_DIR}/tor_enable.sh"
  Mod4+F5

"xterm -title 'Ghost: Tor OFF' -bg black -fg yellow -fa Monospace -fs 11 -e sudo ${GHOST_DIR}/tor_disable.sh"
  Mod4+F6

"xterm -title 'Ghost: AV Kill' -bg black -fg red -fa Monospace -fs 11 -e sudo ${GHOST_DIR}/kill_av.sh"
  Mod4+F7

"xterm -title 'Ghost: Wipe' -bg black -fg magenta -fa Monospace -fs 11 -e sudo ${GHOST_DIR}/wipe_logs.sh"
  Mod4+F8

"xterm -title 'Ghost: Leak Test' -bg black -fg cyan -fa Monospace -fs 11 -e sudo ${GHOST_DIR}/leak_test.sh"
  Mod4+F9

"xterm -title 'Ghost: Metadata' -bg black -fg yellow -fa Monospace -fs 11 -e sudo ${GHOST_DIR}/metadata_wipe.sh ${USER_HOME}"
  Mod4+F10

"xterm -title 'Ghost: WiFi Forget' -bg black -fg red -fa Monospace -fs 11 -e sudo ${GHOST_DIR}/wifi_forget.sh"
  Mod4+F11

"xterm -title 'Ghost: Vault' -bg black -fg cyan -fa Monospace -fs 11 -e sudo ${GHOST_DIR}/mount_vault.sh"
  Mod4+F12
XBRC
chown "$BUILD_USER" "$USER_HOME/.xbindkeysrc"
echo "  .xbindkeysrc written."

# sudoers: ghost scripts run without password prompt
if [ ! -f /etc/sudoers.d/ghost ]; then
    cat > /etc/sudoers.d/ghost << SUDOERS
${BUILD_USER} ALL=(ALL) NOPASSWD: ${GHOST_DIR}/panic_shutdown.sh
${BUILD_USER} ALL=(ALL) NOPASSWD: ${GHOST_DIR}/nuclear_wipe.sh
${BUILD_USER} ALL=(ALL) NOPASSWD: ${GHOST_DIR}/mac_randomize.sh
${BUILD_USER} ALL=(ALL) NOPASSWD: ${GHOST_DIR}/identity_randomize.sh
${BUILD_USER} ALL=(ALL) NOPASSWD: ${GHOST_DIR}/tor_enable.sh
${BUILD_USER} ALL=(ALL) NOPASSWD: ${GHOST_DIR}/tor_disable.sh
${BUILD_USER} ALL=(ALL) NOPASSWD: ${GHOST_DIR}/kill_av.sh
${BUILD_USER} ALL=(ALL) NOPASSWD: ${GHOST_DIR}/wipe_logs.sh
${BUILD_USER} ALL=(ALL) NOPASSWD: ${GHOST_DIR}/leak_test.sh
${BUILD_USER} ALL=(ALL) NOPASSWD: ${GHOST_DIR}/metadata_wipe.sh
${BUILD_USER} ALL=(ALL) NOPASSWD: ${GHOST_DIR}/wifi_forget.sh
${BUILD_USER} ALL=(ALL) NOPASSWD: ${GHOST_DIR}/mount_vault.sh
${BUILD_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl poweroff
${BUILD_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl poweroff --force --force
${BUILD_USER} ALL=(ALL) NOPASSWD: /sbin/poweroff
SUDOERS
    chmod 440 /etc/sudoers.d/ghost
    echo "  sudoers rule written."
fi

# XFCE autostart .desktop — starts xbindkeys on every login automatically
AUTOSTART_DIR="$USER_HOME/.config/autostart"
mkdir -p "$AUTOSTART_DIR"
cat > "$AUTOSTART_DIR/ghost-xbindkeys.desktop" << DESKTOP
[Desktop Entry]
Type=Application
Name=Ghost Machine Hotkeys
Exec=xbindkeys
Hidden=false
X-GNOME-Autostart-enabled=true
Comment=Ghost Machine hotkey daemon
DESKTOP
chown -R "$BUILD_USER" "$AUTOSTART_DIR"

# .xprofile fallback
grep -q "xbindkeys" "$USER_HOME/.xprofile" 2>/dev/null ||     echo "xbindkeys &" >> "$USER_HOME/.xprofile" 2>/dev/null || true

echo "  Autostart configured."
echo "  ✅ Hotkeys will start automatically on next login."
echo "  ℹ️  To activate NOW without rebooting, run as $BUILD_USER: xbindkeys"

# ═════════════════════════════════════════════════════════════
# Summary
# ═════════════════════════════════════════════════════════════
echo ""
echo "╔══════════════════════════════════════════╗"
if [ ${#ERRORS[@]} -eq 0 ]; then
    echo "║  ✅ Ghost Machine deployed — all clean!  ║"
else
    echo "║  ⚠️  Ghost Machine deployed with warnings ║"
fi
echo "╚══════════════════════════════════════════╝"
echo ""

if [ ${#ERRORS[@]} -gt 0 ]; then
    echo "Warnings / notes:"
    for ERR in "${ERRORS[@]}"; do
        echo "  • $ERR"
    done
    echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " RUN THESE ONCE (as root) after reboot:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  sudo bash $INSTALL_DIR/intrusion_detection.sh setup"
echo "  sudo bash $INSTALL_DIR/encrypt_swap.sh"
echo "  sudo bash $INSTALL_DIR/self_scan.sh baseline"
echo "  sudo bash $INSTALL_DIR/tamper_detect.sh setup"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " RUN THESE ONCE (as your user):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  bash $INSTALL_DIR/browser_harden.sh"
echo "  torbrowser-launcher   (completes Tor Browser setup)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " HOTKEYS (Super = Windows key):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Super+F1  → Panic shutdown (instant)"
echo "  Super+F2  → Nuclear wipe   (press 3× fast)"
echo "  Super+F3  → Rotate MAC"
echo "  Super+F4  → Full identity rotation"
echo "  Super+F5  → Enable Tor + kill switch"
echo "  Super+F6  → Disable Tor"
echo "  Super+F7  → Kill webcam + mic"
echo "  Super+F8  → Wipe logs + history"
echo "  Super+F9  → Run leak test"
echo "  Super+F10 → Wipe metadata (current dir)"
echo ""
echo "  ⚠️  Set BIOS supervisor password: press F1 at boot"
echo "  ⚠️  Reboot now to apply all kernel parameters"
echo ""
