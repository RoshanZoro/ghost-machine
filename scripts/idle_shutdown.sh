#!/bin/bash
cd "$HOME" 2>/dev/null || cd /tmp
# idle_shutdown.sh — Shutdown after 2 hours of complete idle

IDLE_THRESHOLD=7200
CHECK_INTERVAL=60
CPU_THRESHOLD=5
LOG="/var/log/ghost/idle_shutdown.log"

mkdir -p /var/log/ghost
echo "[$(date)] Idle watchdog started." >> "$LOG"

while true; do
    sleep "$CHECK_INTERVAL"

    # Get X idle time — skip if xprintidle not available or no display
    X_IDLE_S=0
    if command -v xprintidle &>/dev/null && [ -n "$DISPLAY" ]; then
        X_IDLE_MS=$(DISPLAY=:0 xprintidle 2>/dev/null || echo 0)
        X_IDLE_S=$(( X_IDLE_MS / 1000 ))
    else
        # No xprintidle — use last X input time from /proc as fallback
        # If we can't measure idle, don't shut down
        continue
    fi

    CPU_USAGE=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $2}' | cut -d'.' -f1)
    CPU_USAGE=${CPU_USAGE:-0}

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] X idle: ${X_IDLE_S}s | CPU: ${CPU_USAGE}%" >> "$LOG"

    if [ "$X_IDLE_S" -ge "$IDLE_THRESHOLD" ] && [ "$CPU_USAGE" -lt "$CPU_THRESHOLD" ]; then
        echo "[$(date)] Idle threshold reached — shutting down in 30s" >> "$LOG"
        wall "GHOST: Idle timeout. Shutting down in 30 seconds."
        sleep 30
        systemctl poweroff --force
    fi
done
