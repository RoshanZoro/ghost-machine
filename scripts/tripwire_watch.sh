#!/bin/bash
# tripwire_watch.sh — Real-time inotify watcher on critical system paths
# Runs as a daemon via systemd tripwire.service
# Alerts instantly when watched files are accessed or modified

LOG="/var/log/ghost/tripwire.log"
ALERT_LOG="/var/log/ghost/tripwire_alerts.log"
mkdir -p /var/log/ghost

# Directories and files to watch
WATCH_PATHS=(
    "/etc/passwd"
    "/etc/shadow"
    "/etc/sudoers"
    "/etc/hosts"
    "/etc/ssh"
    "/etc/systemd/system"
    "/opt/ghost/scripts"
    "/boot"
    "/root/.ssh"
)

# Honeypot files — any access to these is suspicious
HONEYPOT_FILES=(
    "/root/.aws/credentials"
    "/home/user/.ssh/id_rsa_backup"
    "/etc/ghost_keys.txt"
    "/root/passwords.txt"
    "/home/user/wallet.dat"
)

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Tripwire started." >> "$LOG"

# Create honeypot files with plausible-looking fake content
for HP in "${HONEYPOT_FILES[@]}"; do
    if [ ! -f "$HP" ]; then
        mkdir -p "$(dirname "$HP")"
        case "$HP" in
            *.txt)   echo "# DO NOT SHARE — private keys" > "$HP" ;;
            *.dat)   dd if=/dev/urandom bs=256 count=1 > "$HP" 2>/dev/null ;;
            *credentials) printf "[default]\naws_access_key_id = AKIAIOSFODNN7EXAMPLE\naws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY\n" > "$HP" ;;
            *id_rsa*) ssh-keygen -q -t rsa -b 2048 -f "$HP" -N "" 2>/dev/null || echo "FAKE KEY" > "$HP" ;;
            *) echo "placeholder" > "$HP" ;;
        esac
        chmod 600 "$HP"
    fi
done

alert() {
    local EVENT="$1"
    local FILE="$2"
    local TIMESTAMP
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    local MSG="[$TIMESTAMP] ⚠️  TRIPWIRE: $EVENT → $FILE"

    echo "$MSG" >> "$ALERT_LOG"
    echo "$MSG" >> "$LOG"

    # Desktop notification
    notify-send "⚠️ TRIPWIRE ALERT" "$EVENT: $FILE" 2>/dev/null || true

    # Wall message
    wall "GHOST TRIPWIRE: $EVENT on $FILE"
}

# Build inotifywait argument list
WATCH_ARGS=()
for PATH_ITEM in "${WATCH_PATHS[@]}" "${HONEYPOT_FILES[@]}"; do
    [ -e "$PATH_ITEM" ] && WATCH_ARGS+=("$PATH_ITEM")
done

# Start watching
inotifywait -m -r -e modify,create,delete,move,access \
    --format '%T %w%f %e' \
    --timefmt '%Y-%m-%d %H:%M:%S' \
    "${WATCH_ARGS[@]}" 2>/dev/null | while read -r TIMESTAMP FILEPATH EVENTS; do

    # Honeypot hit — highest severity
    for HP in "${HONEYPOT_FILES[@]}"; do
        if [[ "$FILEPATH" == "$HP"* ]]; then
            alert "HONEYPOT ACCESSED ($EVENTS)" "$FILEPATH"
            break
        fi
    done

    # System file modifications
    case "$FILEPATH" in
        /etc/passwd*|/etc/shadow*|/etc/sudoers*)
            alert "CRITICAL FILE MODIFIED ($EVENTS)" "$FILEPATH" ;;
        /boot/*)
            alert "BOOT PARTITION MODIFIED ($EVENTS)" "$FILEPATH" ;;
        /etc/ssh/*)
            alert "SSH CONFIG CHANGED ($EVENTS)" "$FILEPATH" ;;
        /opt/ghost/scripts/*)
            alert "GHOST SCRIPT MODIFIED ($EVENTS)" "$FILEPATH" ;;
    esac

    echo "[$TIMESTAMP] $EVENTS: $FILEPATH" >> "$LOG"
done
