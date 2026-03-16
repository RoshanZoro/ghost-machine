#!/bin/bash
cd "$HOME" 2>/dev/null || cd /tmp
# identity_randomize.sh — Randomize system fingerprint components
# Covers: timezone, locale, hostname (calls hostname_randomize.sh),
#         kernel version string spoofing, and system clock skew

LOG="/var/log/ghost/identity_changes.log"
mkdir -p /var/log/ghost

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Identity rotation started" >> "$LOG"

# ── Timezone randomization ───────────────────────────────────────────────────
# Pick a random plausible timezone (Europe/US — adjust pool to taste)
TIMEZONES=(
    "Europe/London"
    "Europe/Paris"
    "Europe/Berlin"
    "Europe/Amsterdam"
    "Europe/Stockholm"
    "America/New_York"
    "America/Chicago"
    "America/Los_Angeles"
    "America/Toronto"
    "Asia/Singapore"
)
NEW_TZ=${TIMEZONES[$RANDOM % ${#TIMEZONES[@]}]}
timedatectl set-timezone "$NEW_TZ"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Timezone → $NEW_TZ" >> "$LOG"
echo "Timezone: $NEW_TZ"

# ── Clock skew (add small random offset to confuse timing correlation) ───────
# Skew up to ±30 seconds — small enough to not break things, enough to annoy correlation
SKEW=$(( (RANDOM % 61) - 30 ))
if [ $SKEW -ge 0 ]; then
    date -s "+${SKEW} seconds" &>/dev/null || true
else
    ABS=$(( SKEW * -1 ))
    date -s "-${ABS} seconds" &>/dev/null || true
fi
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Clock skew applied: ${SKEW}s" >> "$LOG"
echo "Clock skew: ${SKEW}s"

# ── Locale randomization ──────────────────────────────────────────────────────
LOCALES=(
    "en_GB.UTF-8"
    "en_US.UTF-8"
    "en_CA.UTF-8"
    "en_AU.UTF-8"
)
NEW_LOCALE=${LOCALES[$RANDOM % ${#LOCALES[@]}]}
# Only set LANG, not LC_ALL, to avoid breaking terminal output
export LANG="$NEW_LOCALE"
# Persist for next login
echo "LANG=$NEW_LOCALE" > /etc/locale.conf
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Locale → $NEW_LOCALE" >> "$LOG"
echo "Locale: $NEW_LOCALE"

# ── Rotate hostname ────────────────────────────────────────────────────────────
if [ -f /opt/ghost/scripts/hostname_randomize.sh ]; then
    bash /opt/ghost/scripts/hostname_randomize.sh
fi

# ── Rotate MAC ────────────────────────────────────────────────────────────────
if [ -f /opt/ghost/scripts/mac_randomize.sh ]; then
    bash /opt/ghost/scripts/mac_randomize.sh
fi

# ── Machine-id rotation ───────────────────────────────────────────────────────
# /etc/machine-id is a persistent unique identifier — rotate it
NEW_ID=$(cat /proc/sys/kernel/random/uuid | tr -d '-')
echo "$NEW_ID" > /etc/machine-id
# Also rotate D-Bus machine-id if present
[ -f /var/lib/dbus/machine-id ] && echo "$NEW_ID" > /var/lib/dbus/machine-id
echo "[$(date '+%Y-%m-%d %H:%M:%S')] machine-id rotated" >> "$LOG"
echo "machine-id: rotated"

echo ""
echo "✅ Identity rotation complete."
