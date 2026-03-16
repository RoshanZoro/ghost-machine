#!/bin/bash
cd "$HOME" 2>/dev/null || cd /tmp
# usb_monitor.sh — Alert and log when unknown USB devices are blocked by USBGuard
# Requires usbguard to be running

mkdir -p /var/log/ghost

echo "USB monitor started. Watching for blocked devices..."

usbguard watch | while read -r LINE; do
    if echo "$LINE" | grep -q "block"; then
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$TIMESTAMP] BLOCKED USB: $LINE" >> /var/log/ghost/usb_events.log
        notify-send "⚠️ USB DEVICE BLOCKED" "$LINE" 2>/dev/null || \
            wall "GHOST: Unknown USB device was blocked. Check /var/log/ghost/usb_events.log"
    fi
done
