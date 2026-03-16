#!/bin/bash
# wipe_logs.sh — Secure wipe of logs, history, temp files, and browser artifacts

echo "[$(date)] Starting log wipe..."

# Systemd journal
journalctl --vacuum-time=1s 2>/dev/null && echo "Journal: wiped"

# System log files
find /var/log -type f -name "*.log" -exec shred -fuz {} \; 2>/dev/null
find /var/log -type f -name "*.gz" -delete 2>/dev/null
echo "System logs: wiped"

# User history files
for USER_HOME in /home/* /root; do
    [ -d "$USER_HOME" ] || continue
    USERNAME=$(basename "$USER_HOME")

    for HISTFILE in .bash_history .zsh_history .python_history .lesshst .wget-hsts .node_repl_history .mysql_history .psql_history; do
        if [ -f "$USER_HOME/$HISTFILE" ]; then
            shred -fuz "$USER_HOME/$HISTFILE" 2>/dev/null
        fi
        # Symlink to /dev/null to prevent future writes
        ln -sf /dev/null "$USER_HOME/$HISTFILE" 2>/dev/null
    done

    echo "History files: wiped for $USERNAME"
done

# Temp directories
rm -rf /tmp/* /var/tmp/* 2>/dev/null && echo "Temp dirs: cleared"

# Thumbnail caches
find /home -path "*/.cache/thumbnails" -type d -exec rm -rf {} + 2>/dev/null
rm -rf /root/.cache/thumbnails 2>/dev/null
echo "Thumbnails: cleared"

# Recent files (GNOME/GTK)
find /home -name "recently-used.xbel" -exec shred -fuz {} \; 2>/dev/null
find /root -name "recently-used.xbel" -exec shred -fuz {} \; 2>/dev/null
echo "Recent files: cleared"

# Firefox/LibreWolf browsing history via SQLite
find /home /root -name "places.sqlite" 2>/dev/null | while read -r DB; do
    sqlite3 "$DB" "DELETE FROM moz_historyvisits; DELETE FROM moz_inputhistory;" 2>/dev/null && \
        echo "Browser history: cleared ($DB)"
done

# BleachBit deep clean
if command -v bleachbit &>/dev/null; then
    bleachbit --clean \
        system.cache \
        system.tmp \
        system.trash \
        bash.history \
        journald.clean \
        thumbnails.cache 2>/dev/null
    echo "BleachBit: complete"
fi

echo "[$(date)] Log wipe complete."
