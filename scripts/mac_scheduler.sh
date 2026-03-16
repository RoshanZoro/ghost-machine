#!/bin/bash
# mac_scheduler.sh — Loop with hourly ± random jitter (runs as a daemon)

while true; do
    BASE=3600
    JITTER=$(( (RANDOM % 1800) - 900 ))
    SLEEP_TIME=$(( BASE + JITTER ))

    echo "[$(date)] Next MAC rotation in ${SLEEP_TIME}s (~$(( SLEEP_TIME / 60 )) min)"
    sleep "$SLEEP_TIME"

    bash /opt/ghost/scripts/mac_randomize.sh
done
