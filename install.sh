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
BUILD_USER="${SUDO_USER:-nobody}"

mkdir -p "$INSTALL_DIR"
mkdir -p /var/log/ghost /var/lib/ghost

# ── Helper: install official repo package ────────────────────────────────────
install_pkg() {
    local PKG="$1"
    if pacman -Qi "$PKG" &>/dev/null; then
        echo "  [ok] $PKG (already installed)"
        return 0
    fi
    if pacman -S --needed --noconfirm "$PKG" 2>/dev/null; then
        echo "  [ok] $PKG"
    else
        echo "  [!!] $PKG — not found in official repos"
        ERRORS+=("PACKAGE NOT FOUND: $PKG")
        return 1
    fi
}

# ── Helper: install AUR package — tries yay, paru, then builds from source ───
install_aur() {
    local PKG="$1"

    if pacman -Qi "$PKG" &>/dev/null; then
        echo "  [ok] $PKG (already installed)"
        return 0
    fi

    # Try yay
    if command -v yay &>/dev/null; then
        if sudo -u "$BUILD_USER" yay -S --needed --noconfirm "$PKG" 2>/dev/null; then
            echo "  [ok] $PKG (via yay)"
            return 0
        fi
    fi

    # Try paru
    if command -v paru &>/dev/null; then
        if sudo -u "$BUILD_USER" paru -S --needed --noconfirm "$PKG" 2>/dev/null; then
            echo "  [ok] $PKG (via paru)"
            return 0
        fi
    fi

    # No AUR helper — build directly from AUR git
    echo "  No AUR helper — cloning and building $PKG from AUR..."
    install_pkg "base-devel" 2>/dev/null || true
    install_pkg "git"        2>/dev/null || true

    local BUILD_DIR
    BUILD_DIR=$(mktemp -d /tmp/aur_XXXXXX)
    chown "$BUILD_USER" "$BUILD_DIR"

    if sudo -u "$BUILD_USER" git clone --depth=1 \
        "https://aur.archlinux.org/${PKG}.git" "${BUILD_DIR}/${PKG}" 2>/dev/null; then
        chown -R "$BUILD_USER" "$BUILD_DIR"
        if sudo -u "$BUILD_USER" bash -c \
            "cd '${BUILD_DIR}/${PKG}' && makepkg -si --noconfirm" 2>/dev/null; then
            echo "  [ok] $PKG (built from AUR)"
            rm -rf "$BUILD_DIR"
            return 0
        fi
    fi

    rm -rf "$BUILD_DIR"
    echo "  [!!] $PKG — AUR build failed, see ERRORS summary"
    ERRORS+=("BUILD FAILED: $PKG")
    return 1
}

# ── Helper: install secure-delete with extra upstream fallback ────────────────
install_secure_delete() {
    if pacman -Qi secure-delete &>/dev/null || command -v sdmem &>/dev/null; then
        echo "  [ok] secure-delete (already installed)"
        return 0
    fi

    # Try AUR chain first
    if install_aur "secure-delete"; then
        return 0
    fi

    # Final fallback: build from upstream Fedora source tarball
    echo "  Trying upstream source tarball for secure-delete..."
    install_pkg "gcc" 2>/dev/null || true
    install_pkg "make" 2>/dev/null || true

    local TMP
    TMP=$(mktemp -d /tmp/sdel_XXXXXX)

    local URL="https://src.fedoraproject.org/repo/pkgs/secure-delete/secure_delete-3.1.tar.gz/secure_delete-3.1.tar.gz"

    if curl -fsSL "$URL" -o "$TMP/sd.tar.gz" 2>/dev/null || \
       wget -q    "$URL" -o "$TMP/sd.tar.gz" 2>/dev/null; then

        tar -xzf "$TMP/sd.tar.gz" -C "$TMP" 2>/dev/null
        local SRC
        SRC=$(find "$TMP" -name "Makefile" -maxdepth 3 | head -1 | xargs dirname 2>/dev/null)

        if [ -n "$SRC" ] && make -C "$SRC" 2>/dev/null; then
            for BIN in sdmem srm sfill sswap; do
                [ -f "$SRC/$BIN" ] && install -m 755 "$SRC/$BIN" /usr/local/bin/
            done
            echo "  [ok] secure-delete (built from upstream tarball)"
            rm -rf "$TMP"
            return 0
        fi
    fi

    rm -rf "$TMP"
    echo "  [!!] secure-delete — all methods failed; ram_wipe.sh will use dd fallback"
    ERRORS+=("INFO: secure-delete unavailable — ram wipe uses dd only, still functional")
    return 1
}

# ── Helper: install mat2 — AUR then pip fallback ──────────────────────────────
install_mat2() {
    if command -v mat2 &>/dev/null; then
        echo "  [ok] mat2 (already installed)"
        return 0
    fi

    if install_aur "mat2"; then
        return 0
    fi

    # pip fallback
    echo "  Trying mat2 via pip..."
    if pip install mat2 --break-system-packages 2>/dev/null; then
        echo "  [ok] mat2 (via pip)"
        return 0
    fi

    echo "  [!!] mat2 unavailable — metadata_wipe.sh will fall back to exiftool only"
    ERRORS+=("INFO: mat2 not installed — metadata_wipe.sh uses exiftool only")
    return 1
}

# ── Helper: run a labelled step, collect failures ─────────────────────────────
run_step() {
    local LABEL="$1"; shift
    echo "→ $LABEL..."
    if "$@"; then
        echo "  done."
    else
        echo "  [!!] Failed: $LABEL"
        ERRORS+=("STEP FAILED: $LABEL")
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 1. Official repo packages
# ═══════════════════════════════════════════════════════════════════════════════
echo "→ Installing official repo packages..."
for PKG in \
    macchanger tor torsocks usbguard bleachbit \
    xautolock xprintidle inotify-tools \
    procps-ng util-linux coreutils nftables \
    sqlite aide audit nmap curl git base-devel \
    bind perl-image-exiftool dnscrypt-proxy gcc make
do
    install_pkg "$PKG"
done

# ═══════════════════════════════════════════════════════════════════════════════
# 2. AUR / special packages
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "→ Installing AUR packages (with build fallback)..."
install_secure_delete
install_mat2

# ═══════════════════════════════════════════════════════════════════════════════
# 3. Copy scripts
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
run_step "Copying scripts to $INSTALL_DIR" bash -c "
    cp scripts/*.sh '$INSTALL_DIR/' &&
    chmod +x '$INSTALL_DIR'/*.sh
"

# ═══════════════════════════════════════════════════════════════════════════════
# 4. Systemd services
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "→ Installing systemd services..."
cp systemd/*.service /etc/systemd/system/
systemctl daemon-reload

for SVC in mac-randomize idle-shutdown; do
    if systemctl enable --now "${SVC}.service" 2>/dev/null; then
        echo "  [ok] ${SVC}.service"
    else
        ERRORS+=("SERVICE FAILED: ${SVC}.service")
    fi
done

# ram-wipe activates at shutdown only — just enable, don't start
systemctl enable ram-wipe.service 2>/dev/null && \
    echo "  [ok] ram-wipe.service (activates at shutdown)" || \
    ERRORS+=("SERVICE FAILED: ram-wipe.service")

# USBGuard — generate policy from currently connected devices first
if [ ! -s /etc/usbguard/rules.conf ]; then
    echo "  Generating USBGuard policy from current devices..."
    usbguard generate-policy > /etc/usbguard/rules.conf 2>/dev/null || true
fi
systemctl enable --now usbguard.service 2>/dev/null && \
    echo "  [ok] usbguard.service" || \
    echo "  [!!] usbguard failed to start (non-fatal, may need reboot)"

# ═══════════════════════════════════════════════════════════════════════════════
# 5. Kernel hardening
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
run_step "Applying sysctl kernel hardening" bash -c "
    cp config/99-ghost.conf /etc/sysctl.d/ &&
    sysctl --quiet -p /etc/sysctl.d/99-ghost.conf
"

# ═══════════════════════════════════════════════════════════════════════════════
# 6. Firewall
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
run_step "Applying nftables firewall" bash -c "
    cp config/nftables.conf /etc/nftables.conf &&
    systemctl enable --now nftables.service
"

# ═══════════════════════════════════════════════════════════════════════════════
# 7. Cron jobs
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
run_step "Installing cron jobs" bash -c "
    cp config/ghost.cron /etc/cron.d/ghost &&
    chmod 644 /etc/cron.d/ghost
"

# ═══════════════════════════════════════════════════════════════════════════════
# 8. Tor config
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "→ Configuring Tor..."
if [ -f /etc/tor/torrc ]; then
    if ! grep -q "TransPort 9040" /etc/tor/torrc; then
        cat config/torrc.append >> /etc/tor/torrc
        echo "  Tor config appended."
    else
        echo "  Tor config already applied."
    fi
else
    ERRORS+=("SKIPPED: /etc/tor/torrc not found — Tor may not have installed correctly")
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 9. IPv6 disable in GRUB
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "→ Disabling IPv6 in GRUB..."
if ! grep -q "ipv6.disable" /etc/default/grub; then
    sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="ipv6.disable=1 /' /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null && \
        echo "  IPv6 disabled in GRUB." || \
        ERRORS+=("GRUB update failed — run manually: sudo grub-mkconfig -o /boot/grub/grub.cfg")
else
    echo "  IPv6 already disabled."
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 10. Shell history lockout
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "→ Disabling shell history for root..."
ln -sf /dev/null /root/.bash_history
grep -q "HISTFILE=/dev/null" /root/.bashrc 2>/dev/null || \
    echo "HISTFILE=/dev/null" >> /root/.bashrc
echo "  done."

# ═══════════════════════════════════════════════════════════════════════════════
# 11. dnscrypt-proxy
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "→ Configuring dnscrypt-proxy..."
if pacman -Qi dnscrypt-proxy &>/dev/null; then
    bash "$INSTALL_DIR/dns_hardening.sh" 2>/dev/null && \
        echo "  dnscrypt-proxy configured." || \
        echo "  [!!] dnscrypt-proxy config failed — run dns_hardening.sh manually"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
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

echo "⚠️  RUN THESE ONCE AFTER INSTALL:"
echo "   sudo bash /opt/ghost/scripts/intrusion_detection.sh setup"
echo "   sudo bash /opt/ghost/scripts/encrypt_swap.sh"
echo "   sudo bash /opt/ghost/scripts/self_scan.sh baseline"
echo "   bash /opt/ghost/scripts/browser_harden.sh        (as your user, not root)"
echo "   sudo bash /opt/ghost/scripts/tamper_detect.sh setup"
echo ""
echo "⚠️  ASSIGN HOTKEYS IN YOUR DE/WM:"
echo "   Super+F1  → panic_shutdown.sh"
echo "   Super+F2  → nuclear_wipe.sh   (triple-press)"
echo "   Super+F3  → mac_randomize.sh"
echo "   Super+F4  → identity_randomize.sh"
echo "   Super+F5  → tor_enable.sh"
echo "   Super+F6  → tor_disable.sh"
echo "   Super+F7  → kill_av.sh"
echo "   Super+F8  → wipe_logs.sh"
echo "   Super+F9  → leak_test.sh"
echo "   Super+F10 → metadata_wipe.sh"
echo ""
echo "   Then reboot to apply all kernel parameters."
echo ""
