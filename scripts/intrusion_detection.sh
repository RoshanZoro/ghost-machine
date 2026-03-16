#!/bin/bash
cd "$HOME" 2>/dev/null || cd /tmp
# intrusion_detection.sh — Setup and run AIDE + auditd filesystem integrity checks
# AIDE: hashes all system binaries and alerts on changes
# Run setup once, then check daily via cron

MODE="${1:-check}"   # "setup" or "check"
LOG="/var/log/ghost/intrusion.log"
mkdir -p /var/log/ghost

setup_aide() {
    echo "→ Installing AIDE and auditd..."
    pacman -S --needed --noconfirm aide audit

    # Write AIDE config
    cat > /etc/aide.conf << 'EOF'
# AIDE config — Ghost Machine
database_in=file:/var/lib/aide/aide.db
database_out=file:/var/lib/aide/aide.db.new
database_new=file:/var/lib/aide/aide.db.new
gzip_dbout=yes
report_url=file:/var/log/ghost/aide_report.txt

# What to check
PERMS = p+u+g+acl+selinux+xattrs
CONTENT = sha512+rmd160+whirlpool
FULL = PERMS+CONTENT+n+i+l+ftype

# Directories to monitor
/boot          FULL
/etc           FULL
/usr/bin       FULL
/usr/sbin      FULL
/usr/lib       FULL
/opt/ghost     FULL

# Ignore volatile paths
!/var/log
!/var/lib/aide
!/tmp
!/proc
!/sys
!/dev
!/run
EOF

    echo "→ Initializing AIDE database (this takes a minute)..."
    aide --init --config /etc/aide.conf
    mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
    echo "✅ AIDE database initialized."

    # Setup auditd rules
    echo "→ Configuring auditd rules..."
    cat > /etc/audit/rules.d/ghost.rules << 'EOF'
# Monitor script directory
-w /opt/ghost/scripts -p wa -k ghost_scripts

# Monitor passwd and shadow
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/sudoers -p wa -k sudoers

# Monitor network config
-w /etc/NetworkManager -p wa -k network_config
-w /etc/hosts -p wa -k network_config

# Monitor systemd services
-w /etc/systemd/system -p wa -k systemd

# Log all privileged commands
-a always,exit -F arch=b64 -S execve -F euid=0 -k root_commands

# Immutable (optional — requires reboot to change rules)
# -e 2
EOF

    systemctl enable --now auditd.service
    augenrules --load
    echo "✅ auditd configured."

    # Setup inotify tripwire on critical dirs
    cat > /etc/systemd/system/tripwire.service << 'EOF'
[Unit]
Description=Ghost Tripwire — inotify monitor on critical paths
After=multi-user.target

[Service]
Type=simple
ExecStart=/opt/ghost/scripts/tripwire_watch.sh
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable --now tripwire.service
    echo "✅ Tripwire service enabled."
}

run_check() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Running AIDE integrity check..." >> "$LOG"
    echo "Running AIDE integrity check..."

    REPORT="/var/log/ghost/aide_report.txt"
    aide --check --config /etc/aide.conf 2>&1
    EXIT=$?

    if [ $EXIT -eq 0 ]; then
        echo "✅ AIDE: No changes detected."
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] AIDE: CLEAN" >> "$LOG"
    elif [ $EXIT -eq 1 ]; then
        echo "⚠️  AIDE: Changes detected! Review $REPORT"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] AIDE: CHANGES DETECTED — see $REPORT" >> "$LOG"
        # Alert desktop
        notify-send "⚠️ INTRUSION ALERT" "AIDE detected filesystem changes. Check $REPORT" 2>/dev/null || \
            wall "GHOST: AIDE detected filesystem changes. Review $REPORT immediately."
    else
        echo "❌ AIDE check failed (exit $EXIT). Check config."
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] AIDE: ERROR exit=$EXIT" >> "$LOG"
    fi

    # Also dump recent auditd alerts
    echo ""
    echo "Recent audit events (last 20):"
    ausearch -k ghost_scripts -k identity -k sudoers 2>/dev/null | tail -40 || \
        echo "(auditd not running or no events)"
}

case "$MODE" in
    setup) setup_aide ;;
    check) run_check ;;
    *)
        echo "Usage: $0 [setup|check]"
        echo "  setup — install AIDE, auditd, tripwire (run once)"
        echo "  check — run integrity check and report"
        exit 1
        ;;
esac
