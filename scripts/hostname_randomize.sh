#!/bin/bash
cd "$HOME" 2>/dev/null || cd /tmp
# hostname_randomize.sh — Set a random believable hostname

ADJECTIVES=(dark quiet empty broken silent dead cold fast hollow remote amber obsidian crimson static phantom null void buried drifting)
NOUNS=(node station server relay box unit terminal endpoint bridge mesh router cluster proxy signal beacon port module socket pipe)

ADJ=${ADJECTIVES[$RANDOM % ${#ADJECTIVES[@]}]}
NOUN=${NOUNS[$RANDOM % ${#NOUNS[@]}]}
NUM=$(printf '%04d' $((RANDOM % 9999)))

NEW_HOSTNAME="${ADJ}-${NOUN}-${NUM}"

hostnamectl set-hostname "$NEW_HOSTNAME"
sed -i "s/127\.0\.1\.1.*/127.0.1.1\t$NEW_HOSTNAME/" /etc/hosts

if systemctl is-active avahi-daemon > /dev/null 2>&1; then
    systemctl restart avahi-daemon
fi

mkdir -p /var/log/ghost
echo "[$(date)] Hostname changed → $NEW_HOSTNAME"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] $NEW_HOSTNAME" >> /var/log/ghost/hostname_history.log
