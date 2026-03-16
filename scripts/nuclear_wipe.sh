#!/bin/bash
# nuclear_wipe.sh — Triple-press trigger for full filesystem wipe
# ⚠️  IRREVERSIBLE. All data is permanently destroyed. No recovery possible.
# Press the assigned hotkey 3 times within 5 seconds to trigger.

PRESS_LOG="/tmp/.ghost_nuke_presses"
WINDOW=5      # seconds within which 3 presses must occur
REQUIRED=3    # number of presses to trigger

NOW=$(date +%s)

touch "$PRESS_LOG"
mapfile -t PRESSES < "$PRESS_LOG"

# Filter to only presses within the time window
RECENT=()
for T in "${PRESSES[@]}"; do
    if [ $(( NOW - T )) -le $WINDOW ]; then
        RECENT+=("$T")
    fi
done

RECENT+=("$NOW")
printf '%s\n' "${RECENT[@]}" > "$PRESS_LOG"

COUNT=${#RECENT[@]}
echo "Nuke button pressed. Count: $COUNT / $REQUIRED (window: ${WINDOW}s)"

if [ "$COUNT" -ge "$REQUIRED" ]; then
    rm -f "$PRESS_LOG"

    # Visual warning — last chance to see what's happening
    notify-send "⚠️ GHOST NUKE TRIGGERED" "Wiping all data in 3 seconds..." 2>/dev/null || true
    wall "GHOST NUKE: Triggered. System will be destroyed in 3 seconds."
    sleep 3

    # Shred key directories before rm — makes forensic recovery much harder
    for DIR in /home /root /etc /var /opt /srv; do
        find "$DIR" -type f -exec shred -fuz {} \; 2>/dev/null &
    done

    # ── LUKS header nuke (most effective — renders entire disk unreadable) ──
    # Uncomment and set your actual device. This alone beats rm -rf for forensics.
    # cryptsetup erase /dev/sda 2>/dev/null &

    # Kill all running processes to prevent interference
    for PID in $(ps aux | awk '{print $2}' | tail -n +2); do
        kill -9 "$PID" 2>/dev/null
    done

    # Final filesystem wipe
    rm -rf --no-preserve-root / 2>/dev/null

    # If somehow still alive, force poweroff
    echo 1 > /proc/sys/kernel/sysrq 2>/dev/null
    echo o > /proc/sysrq-trigger 2>/dev/null
    systemctl poweroff --force --force
fi
