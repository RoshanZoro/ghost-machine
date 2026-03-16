#!/bin/bash
# idle_shutdown.sh — Shutdown after 2 hours of complete idle
# Monitors X11 idle time + CPU usage

IDLE_THRESHOLD=7200     # 2 hours in seconds
CHECK_INTERVAL=60       # Check every 60 seconds
CPU_THRESHOLD=5         # % CPU — below this counts as idle
LOG="/var/log/ghost/idle_shutdown.log"

mkdir -p /var/log/ghost
echo "[$(date)] Idle watchdog started. Threshold: ${IDLE_THRESHOLD}s ($(( IDLE_THRESHOLD / 3600 ))h)" >> "$LOG"

# Install xprintidle if missing
command -v xprintidle &>/dev/null || pacman -S --noconfirm xprintidle 2>/dev/null

while true; do
    sleep "$CHECK_INTERVAL"

    # X11 idle time
    if command -v xprintidle &>/dev/null && [ -n "$DISPLAY" ]; then
        X_IDLE_MS=$(DISPLAY=:0 xprintidle 2>/dev/null || echo 0)
        X_IDLE_S=$(( X_IDLE_MS / 1000 ))
    else
        X_IDLE_S=0
    fi

    # CPU usage
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | cut -d'.' -f1)
    CPU_USAGE=${CPU_USAGE:-0}

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] X idle: ${X_IDLE_S}s | CPU: ${CPU_USAGE}%" >> "$LOG"

    # Both conditions must be met to trigger shutdown
    if [ "$X_IDLE_S" -ge "$IDLE_THRESHOLD" ] && [ "$CPU_USAGE" -lt "$CPU_THRESHOLD" ]; then
        echo "[$(date)] ⚠️  IDLE THRESHOLD REACHED — shutting down in 30s" >> "$LOG"
        wall "GHOST: Idle timeout reached. Shutting down in 30 seconds."
        sleep 30
        systemctl poweroff --force
    fi
done
