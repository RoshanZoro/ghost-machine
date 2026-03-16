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
#    - aide       → aide (community)
#    - xautolock  → xorg-xautolock (correct name in Arch repos)
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
    xorg-xautolock \
    xprintidle \
    inotify-tools \
    procps-ng \
    util-linux \
    coreutils \
    nftables \
    sqlite \
    aide \
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
    fswebcam
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

for SVC in mac-randomize idle-shutdown; do
    systemctl enable --now "${SVC}.service" 2>/dev/null && \
        echo "  [ok] ${SVC}.service" || \
        ERRORS+=("SERVICE FAILED: ${SVC}.service")
done
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
# 12. Hotkeys (auto-detect DE and configure)
# ═════════════════════════════════════════════════════════════
echo ""
echo "→ Configuring hotkeys for $BUILD_USER..."
if [ -f "$INSTALL_DIR/hotkeys_setup.sh" ]; then
    sudo -u "$BUILD_USER" bash "$INSTALL_DIR/hotkeys_setup.sh" 2>/dev/null && \
        echo "  Hotkeys configured." || \
        echo "  [!!] Hotkey setup failed — run manually: bash $INSTALL_DIR/hotkeys_setup.sh"
fi

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
