# 🕵️ Ghost Machine — Lenovo T420 Manjaro OPSEC Suite

> **Full anonymization, panic response, and identity rotation scripts for Manjaro Linux on a Lenovo ThinkPad T420.**

---

## ⚠️ Legal Disclaimer

These scripts are for **legal security research, penetration testing, privacy protection, and personal operational security** on hardware you own. The authors assume no liability for misuse. The nuclear wipe scripts are **irreversible** — test nothing on a machine you care about before you understand exactly what each script does. You've been warned.

---

## 📋 Table of Contents

- [System Overview](#system-overview)
- [Installation & Setup](#installation--setup)
- [MAC Address Randomization](#1-mac-address-randomization)
- [Hostname Randomization](#2-hostname-randomization)
- [Panic Button — Immediate Shutdown](#3-panic-button--immediate-shutdown)
- [Idle Auto-Shutdown (2 Hours)](#4-idle-auto-shutdown-2-hours)
- [Nuclear Wipe Panic Button](#5-nuclear-wipe-panic-button-rm--rf-)
- [Tor Routing & DNS Leak Prevention](#6-tor-routing--dns-leak-prevention)
- [RAM Wipe on Shutdown](#7-ram-wipe-on-shutdown)
- [USB Guard — Auto-Block Unknown Devices](#8-usbguard--auto-block-unknown-devices)
- [Webcam & Mic Hardware Kill](#9-webcam--mic-hardware-kill)
- [LUKS Full Disk Encryption Setup](#10-luks-full-disk-encryption)
- [Secure Boot & Firmware Hardening](#11-secure-boot--firmware-hardening)
- [Network Lockdown](#12-network-lockdown)
- [Log & Temp File Wiper](#13-log--temp-file-wiper)
- [Keyboard Shortcut Setup](#keyboard-shortcut-setup)
- [Cron & Systemd Scheduling](#cron--systemd-scheduling)
- [File Structure](#file-structure)

---

## System Overview

| Component | Value |
|-----------|-------|
| Hardware | Lenovo ThinkPad T420 |
| OS | Manjaro Linux (rolling) |
| Init system | systemd |
| Shell | bash / zsh |
| Network manager | NetworkManager |

---

## Installation & Setup

```bash
# Clone this repo
git clone https://github.com/youruser/ghost-machine.git
cd ghost-machine

# Install all dependencies
sudo pacman -S --needed \
  macchanger \
  tor \
  torsocks \
  usbguard \
  bleachbit \
  xautolock \
  inotify-tools \
  procps-ng \
  util-linux \
  coreutils

# Make all scripts executable
chmod +x scripts/*.sh

# Run the master installer
sudo bash install.sh
```

---

## 1. MAC Address Randomization

Randomizes your MAC address every hour with an additional random ±15 minute jitter so traffic patterns are harder to correlate.

### `scripts/mac_randomize.sh`

```bash
#!/bin/bash
# mac_randomize.sh — Randomize MAC address with jitter
# Run as root via systemd timer

LOG="/var/log/ghost/mac_changes.log"
mkdir -p /var/log/ghost

# Detect all physical network interfaces (skip loopback)
INTERFACES=$(ip link show | awk -F': ' '/^[0-9]+: [^lo]/{print $2}' | sed 's/@.*//')

for IFACE in $INTERFACES; do
    # Bring interface down
    ip link set "$IFACE" down 2>/dev/null || continue

    # Randomize MAC
    macchanger -r "$IFACE" > /dev/null 2>&1

    # Get new MAC for logging
    NEW_MAC=$(macchanger -s "$IFACE" | awk '/Current/{print $3}')

    # Bring interface back up
    ip link set "$IFACE" up 2>/dev/null

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $IFACE → $NEW_MAC" >> "$LOG"
    echo "MAC randomized: $IFACE → $NEW_MAC"
done

# Restart NetworkManager to reconnect cleanly
systemctl restart NetworkManager
sleep 3
echo "NetworkManager restarted."
```

### `scripts/mac_scheduler.sh`

```bash
#!/bin/bash
# mac_scheduler.sh — Loop with hourly ± random jitter (runs as a daemon)

while true; do
    # Base interval: 3600s (1 hour)
    BASE=3600
    # Jitter: ±900s (±15 minutes)
    JITTER=$(( (RANDOM % 1800) - 900 ))
    SLEEP_TIME=$(( BASE + JITTER ))

    echo "[$(date)] Next MAC rotation in ${SLEEP_TIME}s"
    sleep "$SLEEP_TIME"

    bash /opt/ghost/scripts/mac_randomize.sh
done
```

### Systemd Service: `/etc/systemd/system/mac-randomize.service`

```ini
[Unit]
Description=MAC Address Randomizer with Jitter
After=network.target

[Service]
Type=simple
ExecStart=/opt/ghost/scripts/mac_scheduler.sh
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
```

```bash
# Enable and start
sudo systemctl enable --now mac-randomize.service

# Check logs
journalctl -u mac-randomize.service -f
```

---

## 2. Hostname Randomization

Generates a random plausible-looking hostname and applies it immediately without reboot.

### `scripts/hostname_randomize.sh`

```bash
#!/bin/bash
# hostname_randomize.sh — Set a random believable hostname

# Word lists for generating realistic-looking hostnames
ADJECTIVES=(dark quiet empty broken silent dead cold fast hollow remote)
NOUNS=(node station server relay box unit terminal endpoint bridge mesh)
COLORS=(black grey silver carbon slate cobalt onyx ash bone chrome)

# Pick random parts
ADJ=${ADJECTIVES[$RANDOM % ${#ADJECTIVES[@]}]}
NOUN=${NOUNS[$RANDOM % ${#NOUNS[@]}]}
NUM=$(printf '%04d' $((RANDOM % 9999)))

NEW_HOSTNAME="${ADJ}-${NOUN}-${NUM}"

# Apply hostname
hostnamectl set-hostname "$NEW_HOSTNAME"

# Update /etc/hosts to prevent sudo delays
sed -i "s/127\.0\.1\.1.*/127.0.1.1\t$NEW_HOSTNAME/" /etc/hosts

# Update mDNS/avahi if running
if systemctl is-active avahi-daemon > /dev/null 2>&1; then
    systemctl restart avahi-daemon
fi

echo "[$(date)] Hostname changed → $NEW_HOSTNAME"
echo "$NEW_HOSTNAME" >> /var/log/ghost/hostname_history.log
```

```bash
# Run manually
sudo bash /opt/ghost/scripts/hostname_randomize.sh

# Or add to mac_randomize.sh for combined rotation
```

---

## 3. Panic Button — Immediate Shutdown

One keypress triggers an **immediate forced power-off** — no sync, no graceful unmount. Gone in under a second.

### `scripts/panic_shutdown.sh`

```bash
#!/bin/bash
# panic_shutdown.sh — Immediate forced power cut
# Assign to a hotkey (see Keyboard Shortcut Setup)

# Optional: sync first if you have 200ms to spare
# sync

# Force immediate power-off via SysRq (kernel-level, bypasses everything)
echo 1 > /proc/sys/kernel/sysrq
echo o > /proc/sysrq-trigger

# Fallback: systemd forced poweroff
systemctl poweroff --force --force

# Nuclear fallback
/sbin/poweroff -f
```

### SysRq-Based Instant Wipe Combo

The Linux **SysRq REISUB** sequence is your friend. For immediate shutdown:

```bash
# Enable SysRq permanently
echo "kernel.sysrq = 1" >> /etc/sysctl.d/99-ghost.conf
sysctl -p /etc/sysctl.d/99-ghost.conf
```

| Key Combo | Action |
|-----------|--------|
| `Alt+SysRq+S` | Emergency sync |
| `Alt+SysRq+U` | Remount all filesystems read-only |
| `Alt+SysRq+O` | Immediate power off |

---

## 4. Idle Auto-Shutdown (2 Hours)

Monitors for 2 hours of complete inactivity (no keyboard, mouse, or CPU usage). If the machine goes cold, it shuts down.

### `scripts/idle_shutdown.sh`

```bash
#!/bin/bash
# idle_shutdown.sh — Shutdown after 2 hours of idle
# Checks X11 idle time via xprintidle, with CPU usage fallback

IDLE_THRESHOLD=7200      # 2 hours in seconds
CHECK_INTERVAL=60        # Check every 60 seconds
CPU_THRESHOLD=5          # % CPU usage — below this counts as idle
LOG="/var/log/ghost/idle_shutdown.log"

mkdir -p /var/log/ghost

echo "[$(date)] Idle watchdog started. Threshold: ${IDLE_THRESHOLD}s" >> "$LOG"

# Install xprintidle if not present
command -v xprintidle &>/dev/null || pacman -S --noconfirm xprintidle

while true; do
    sleep "$CHECK_INTERVAL"

    # X11 idle time in milliseconds
    if command -v xprintidle &>/dev/null && [ -n "$DISPLAY" ]; then
        X_IDLE_MS=$(DISPLAY=:0 xprintidle 2>/dev/null || echo 0)
        X_IDLE_S=$(( X_IDLE_MS / 1000 ))
    else
        X_IDLE_S=0
    fi

    # CPU usage over last interval
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | cut -d'.' -f1)
    CPU_USAGE=${CPU_USAGE:-0}

    echo "[$(date)] X idle: ${X_IDLE_S}s | CPU: ${CPU_USAGE}%" >> "$LOG"

    # Only shutdown if BOTH X idle threshold met AND CPU is quiet
    if [ "$X_IDLE_S" -ge "$IDLE_THRESHOLD" ] && [ "$CPU_USAGE" -lt "$CPU_THRESHOLD" ]; then
        echo "[$(date)] ⚠️  IDLE THRESHOLD REACHED — shutting down" >> "$LOG"
        wall "GHOST: Idle timeout reached. Shutting down in 30 seconds."
        sleep 30
        systemctl poweroff --force
    fi
done
```

### Systemd Service: `/etc/systemd/system/idle-shutdown.service`

```ini
[Unit]
Description=Idle Auto-Shutdown (2h)
After=graphical.target

[Service]
Type=simple
ExecStart=/opt/ghost/scripts/idle_shutdown.sh
Restart=always
RestartSec=30
Environment=DISPLAY=:0
User=root

[Install]
WantedBy=graphical.target
```

```bash
sudo systemctl enable --now idle-shutdown.service
```

---

## 5. Nuclear Wipe Panic Button (`rm -rf /`)

> **⚠️ PERMANENT AND IRREVERSIBLE. This destroys ALL data on the system. There is NO recovery. Use only if capture/compromise is imminent.**

This script listens for **3 rapid successive keypresses** of the configured hotkey. On the third press within a 5-second window, it triggers a full filesystem wipe.

### `scripts/nuclear_wipe.sh`

```bash
#!/bin/bash
# nuclear_wipe.sh — Triple-press trigger for full filesystem wipe
# IRREVERSIBLE. All data is permanently destroyed.

TRIGGER_FILE="/tmp/.ghost_nuke_trigger"
PRESS_LOG="/tmp/.ghost_nuke_presses"
WINDOW=5       # seconds between presses to count as a sequence
REQUIRED=3     # number of presses required

NOW=$(date +%s)

# Read existing press timestamps
touch "$PRESS_LOG"
mapfile -t PRESSES < "$PRESS_LOG"

# Filter presses within the time window
RECENT=()
for T in "${PRESSES[@]}"; do
    if [ $(( NOW - T )) -le $WINDOW ]; then
        RECENT+=("$T")
    fi
done

# Add current press
RECENT+=("$NOW")
printf '%s\n' "${RECENT[@]}" > "$PRESS_LOG"

COUNT=${#RECENT[@]}
echo "Nuke button pressed. Count: $COUNT / $REQUIRED"

if [ "$COUNT" -ge "$REQUIRED" ]; then
    # Clear the press log immediately
    rm -f "$PRESS_LOG"

    # POINT OF NO RETURN — visual confirmation
    notify-send "⚠️ GHOST NUKE" "TRIGGERED — wiping in 3 seconds" 2>/dev/null || true
    sleep 3

    # Overwrite key system directories before rm
    # This makes forensic recovery significantly harder
    for DIR in /home /root /etc /var /tmp /opt; do
        find "$DIR" -type f -exec shred -fuz {} \; 2>/dev/null &
    done

    # Wipe LUKS header if encrypted (renders disk unreadable even with password)
    # Uncomment and set your device — this alone makes the disk permanently unreadable
    # cryptsetup erase /dev/sda 2>/dev/null &

    # Kill all processes to prevent writes
    for PID in $(ps aux | awk '{print $2}' | tail -n +2); do
        kill -9 "$PID" 2>/dev/null
    done

    # The final wipe
    rm -rf --no-preserve-root / 2>/dev/null

    # If still alive somehow, force poweroff
    echo 1 > /proc/sys/kernel/sysrq 2>/dev/null
    echo o > /proc/sysrq-trigger 2>/dev/null
    systemctl poweroff --force --force
fi
```

> **Security note:** `shred` + LUKS header erasure before `rm -rf /` is far more forensically secure than `rm` alone. Consider using `cryptsetup erase` on your LUKS device instead of or in addition to the `rm`.

---

## 6. Tor Routing & DNS Leak Prevention

Force all traffic through Tor with a kill switch — if Tor goes down, traffic is blocked rather than exposed.

### `scripts/tor_enable.sh`

```bash
#!/bin/bash
# tor_enable.sh — Route all traffic through Tor with iptables kill switch

TOR_UID=$(id -u debian-tor 2>/dev/null || id -u tor 2>/dev/null || echo 0)
TOR_PORT=9040
DNS_PORT=5353
LO_IFACE="lo"
NON_TOR="192.168.0.0/16 10.0.0.0/8 172.16.0.0/12"

echo "Enabling Tor transparent proxy with kill switch..."

# Flush existing rules
iptables -F
iptables -t nat -F
iptables -t mangle -F

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i "$LO_IFACE" -j ACCEPT

# Allow Tor process to bypass (prevent loop)
iptables -t nat -A OUTPUT -m owner --uid-owner "$TOR_UID" -j RETURN
iptables -A OUTPUT -m owner --uid-owner "$TOR_UID" -j ACCEPT

# Allow LAN without Tor (adjust if you want LAN through Tor too)
for RANGE in $NON_TOR; do
    iptables -t nat -A OUTPUT -d "$RANGE" -j RETURN
    iptables -A OUTPUT -d "$RANGE" -j ACCEPT
done

# Redirect DNS to Tor DNS port
iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports "$DNS_PORT"
iptables -t nat -A OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports "$DNS_PORT"

# Redirect all TCP to Tor transparent proxy
iptables -t nat -A OUTPUT -p tcp --syn -j REDIRECT --to-ports "$TOR_PORT"

# KILL SWITCH: Block anything that doesn't go through Tor
iptables -A OUTPUT -m owner --uid-owner "$TOR_UID" -j ACCEPT
iptables -A OUTPUT -o "$LO_IFACE" -j ACCEPT
iptables -A OUTPUT -j REJECT

echo "Tor routing active. Kill switch engaged."
systemctl start tor
```

### `scripts/tor_disable.sh`

```bash
#!/bin/bash
# tor_disable.sh — Restore normal routing

iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
systemctl stop tor
echo "Tor disabled. Normal routing restored."
```

### Tor Config: `/etc/tor/torrc` additions

```
# Transparent proxy
TransPort 9040
DNSPort 5353
AutomapHostsOnResolve 1

# Performance
CircuitBuildTimeout 10
LearnCircuitBuildTimeout 0
MaxCircuitDirtiness 600

# Hardening
SafeLogging 1
AvoidDiskWrites 1
```

---

## 7. RAM Wipe on Shutdown

Overwrites RAM contents during shutdown to prevent cold-boot attacks.

### `scripts/ram_wipe.sh`

```bash
#!/bin/bash
# ram_wipe.sh — Overwrite free RAM on shutdown using /dev/shm stress

echo "Wiping free RAM..."

# Method 1: Fill memory with zeros using dd
MEM_FREE_KB=$(grep MemFree /proc/meminfo | awk '{print $2}')
MEM_FREE_MB=$(( MEM_FREE_KB / 1024 - 64 ))  # Leave 64MB headroom

if [ "$MEM_FREE_MB" -gt 0 ]; then
    dd if=/dev/zero of=/dev/shm/ramwipe bs=1M count="$MEM_FREE_MB" 2>/dev/null
    sync
    rm -f /dev/shm/ramwipe
fi

# Method 2: sdmem (secure-delete package) — more thorough
if command -v sdmem &>/dev/null; then
    sdmem -f -l -v
fi

echo "RAM wipe complete."
```

### Systemd Service: `/etc/systemd/system/ram-wipe.service`

```ini
[Unit]
Description=RAM Wipe on Shutdown
DefaultDependencies=no
Before=shutdown.target reboot.target halt.target

[Service]
Type=oneshot
ExecStart=/opt/ghost/scripts/ram_wipe.sh
TimeoutStartSec=120

[Install]
WantedBy=shutdown.target halt.target reboot.target
```

```bash
sudo pacman -S secure-delete   # provides sdmem
sudo systemctl enable ram-wipe.service
```

---

## 8. USBGuard — Auto-Block Unknown Devices

Only pre-authorized USB devices are allowed. Any new device is automatically blocked.

```bash
# Install and configure USBGuard
sudo pacman -S usbguard

# Generate a policy from currently connected devices
sudo usbguard generate-policy > /etc/usbguard/rules.conf

# Block all new devices by default
echo 'IPCAllowedUsers=root' >> /etc/usbguard/usbguard-daemon.conf

# Enable
sudo systemctl enable --now usbguard.service

# View blocked devices
sudo usbguard list-devices

# Allow a specific device (get ID from list-devices output)
sudo usbguard allow-device <ID>

# Block a device
sudo usbguard block-device <ID>
```

### `scripts/usb_monitor.sh`

```bash
#!/bin/bash
# usb_monitor.sh — Alert and log when unknown USB is inserted

usbguard watch | while read -r LINE; do
    if echo "$LINE" | grep -q "block"; do
        DEVICE=$(echo "$LINE" | grep -oP 'id \K[^\s]+')
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$TIMESTAMP] BLOCKED USB: $LINE" >> /var/log/ghost/usb_events.log
        notify-send "⚠️ USB BLOCKED" "$LINE" 2>/dev/null || wall "GHOST: Unknown USB device blocked: $DEVICE"
    fi
done
```

---

## 9. Webcam & Mic Hardware Kill

### Software Kill (instant toggle)

```bash
# Disable webcam
sudo modprobe -r uvcvideo

# Re-enable webcam  
sudo modprobe uvcvideo

# Permanently disable webcam (adds to module blacklist)
echo "blacklist uvcvideo" | sudo tee /etc/modprobe.d/disable-webcam.conf

# Disable microphone
amixer set Capture nocap
pactl set-source-mute @DEFAULT_SOURCE@ 1

# Enable mic
pactl set-source-mute @DEFAULT_SOURCE@ 0
```

### `scripts/kill_av.sh`

```bash
#!/bin/bash
# kill_av.sh — Kill webcam and mic in one shot

# Unload webcam kernel module
modprobe -r uvcvideo 2>/dev/null && echo "Webcam: OFF" || echo "Webcam: already off"

# Mute microphone at ALSA level
amixer -q set Capture nocap 2>/dev/null

# Mute at PulseAudio level
pactl set-source-mute @DEFAULT_SOURCE@ 1 2>/dev/null

# Mute at PipeWire level (if using PipeWire)
wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 1 2>/dev/null

echo "Audio/Video input: ALL MUTED"
```

> **Hardware kill:** The T420's ThinkPad has a physical mic mute button (Fn+F4). For the webcam, a piece of opaque tape over the lens is still the most reliable method.

---

## 10. LUKS Full Disk Encryption

> Best set up at install time. These notes are for reference or adding a second encrypted container.

```bash
# Create encrypted container (file-based)
dd if=/dev/urandom of=/secure/vault.img bs=1M count=2048   # 2GB container
cryptsetup luksFormat /secure/vault.img

# Open container
cryptsetup luksOpen /secure/vault.img ghost_vault

# Format and mount
mkfs.ext4 /dev/mapper/ghost_vault
mount /dev/mapper/ghost_vault /mnt/vault

# Close container
umount /mnt/vault
cryptsetup luksClose ghost_vault

# Nuke LUKS header (renders disk permanently unreadable — NO RECOVERY)
# cryptsetup erase /dev/sda
```

### `scripts/mount_vault.sh`

```bash
#!/bin/bash
# mount_vault.sh — Open and mount encrypted vault

VAULT_IMG="/secure/vault.img"
VAULT_NAME="ghost_vault"
MOUNT_POINT="/mnt/vault"

mkdir -p "$MOUNT_POINT"
cryptsetup luksOpen "$VAULT_IMG" "$VAULT_NAME" && \
  mount /dev/mapper/"$VAULT_NAME" "$MOUNT_POINT" && \
  echo "Vault mounted at $MOUNT_POINT" || \
  echo "Failed to mount vault."
```

---

## 11. Secure Boot & Firmware Hardening

### BIOS Settings (T420 specific)

Enter BIOS: `F1` at boot

```
Security → Password → Set Supervisor Password   ← REQUIRED
Security → Security Chip → Disabled             ← prevent TPM attacks
Security → Virtualization → Disabled            ← unless you need VMs
Config → Network → Wake on LAN → Disabled
Config → USB → USB UEFI BIOS Support → Disabled ← boot from USB only with password
Security → Secure Boot → Enabled (if using UEFI)
```

### Kernel Hardening: `/etc/sysctl.d/99-ghost.conf`

```ini
# Disable SysRq except for specific combos (see panic_shutdown.sh)
kernel.sysrq = 1

# Prevent core dumps
fs.suid_dumpable = 0
kernel.core_pattern = |/bin/false

# Restrict dmesg to root
kernel.dmesg_restrict = 1

# Restrict ptrace to own children
kernel.yama.ptrace_scope = 2

# Disable magic SysRq broadcast
kernel.printk = 3 3 3 3

# Network hardening
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.disable_ipv6 = 1       # Disable IPv6 if using Tor (leaks!)
net.ipv4.conf.all.log_martians = 1

# Randomize virtual address space
kernel.randomize_va_space = 2
```

```bash
sudo sysctl -p /etc/sysctl.d/99-ghost.conf
```

---

## 12. Network Lockdown

### Firewall Setup (nftables)

```bash
sudo pacman -S nftables
```

### `/etc/nftables.conf`

```nft
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        # Allow loopback
        iifname "lo" accept

        # Allow established/related
        ct state established,related accept

        # Drop invalid
        ct state invalid drop

        # Allow ICMP (optional — comment out for stealth)
        # ip protocol icmp accept

        # Drop everything else
        drop
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
    }

    chain output {
        type filter hook output priority 0; policy accept;
        # Add output restrictions here when Tor kill switch is active
    }
}
```

```bash
sudo systemctl enable --now nftables.service
```

### Disable IPv6 Globally

```bash
# Add to /etc/default/grub GRUB_CMDLINE_LINUX
# ipv6.disable=1

sudo grub-mkconfig -o /boot/grub/grub.cfg
```

---

## 13. Log & Temp File Wiper

Clears logs, bash history, temp files, and browser artifacts.

### `scripts/wipe_logs.sh`

```bash
#!/bin/bash
# wipe_logs.sh — Secure wipe of logs and temp artifacts

echo "Starting log wipe..."

# System logs
journalctl --vacuum-time=1s 2>/dev/null
find /var/log -type f -name "*.log" -exec shred -fuz {} \; 2>/dev/null
find /var/log -type f -name "*.gz" -delete 2>/dev/null

# User history files
for USER_HOME in /home/* /root; do
    [ -d "$USER_HOME" ] || continue
    shred -fuz "$USER_HOME/.bash_history" 2>/dev/null
    shred -fuz "$USER_HOME/.zsh_history" 2>/dev/null
    shred -fuz "$USER_HOME/.python_history" 2>/dev/null
    shred -fuz "$USER_HOME/.lesshst" 2>/dev/null
    shred -fuz "$USER_HOME/.wget-hsts" 2>/dev/null
    ln -sf /dev/null "$USER_HOME/.bash_history" 2>/dev/null
    ln -sf /dev/null "$USER_HOME/.zsh_history" 2>/dev/null
done

# Temp directories
rm -rf /tmp/* /var/tmp/* 2>/dev/null

# Thumbnail cache
rm -rf ~/.cache/thumbnails/* 2>/dev/null

# Recent files (GNOME/GTK)
rm -f ~/.local/share/recently-used.xbel 2>/dev/null
rm -rf ~/.local/share/recently-used.xbel.* 2>/dev/null

# Firefox/LibreWolf artifacts
find ~/.mozilla -name "*.sqlite" -exec sqlite3 {} "DELETE FROM moz_historyvisits;" \; 2>/dev/null

# BleachBit deep clean (if installed)
if command -v bleachbit &>/dev/null; then
    bleachbit --clean \
        system.cache \
        system.tmp \
        system.trash \
        bash.history \
        journald.clean \
        thumbnails.cache 2>/dev/null
fi

echo "Log wipe complete. $(date)"
```

```bash
# Run automatically on logout — add to /etc/profile.d/wipe_on_logout.sh
echo "bash /opt/ghost/scripts/wipe_logs.sh" >> /etc/profile.d/wipe_on_logout.sh
```

---

## Keyboard Shortcut Setup

Set these in your desktop environment (XFCE, KDE, GNOME, i3):

| Hotkey | Script | Action |
|--------|--------|--------|
| `Super+F1` | `panic_shutdown.sh` | Instant forced power-off |
| `Super+F2` | `nuclear_wipe.sh` | Triple-press nuke trigger |
| `Super+F3` | `mac_randomize.sh` | Rotate MAC now |
| `Super+F4` | `hostname_randomize.sh` | Rotate hostname now |
| `Super+F5` | `tor_enable.sh` | Enable Tor routing |
| `Super+F6` | `tor_disable.sh` | Disable Tor routing |
| `Super+F7` | `kill_av.sh` | Kill webcam + mic |
| `Super+F8` | `wipe_logs.sh` | Wipe logs + history |

### XFCE (`~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml`)

```xml
<property name="&lt;Super&gt;F1" type="string" value="pkexec /opt/ghost/scripts/panic_shutdown.sh"/>
<property name="&lt;Super&gt;F2" type="string" value="pkexec /opt/ghost/scripts/nuclear_wipe.sh"/>
<property name="&lt;Super&gt;F3" type="string" value="pkexec /opt/ghost/scripts/mac_randomize.sh"/>
```

### i3 (`~/.config/i3/config`)

```
bindsym $mod+F1 exec --no-startup-id pkexec /opt/ghost/scripts/panic_shutdown.sh
bindsym $mod+F2 exec --no-startup-id pkexec /opt/ghost/scripts/nuclear_wipe.sh
bindsym $mod+F3 exec --no-startup-id pkexec /opt/ghost/scripts/mac_randomize.sh
bindsym $mod+F4 exec --no-startup-id pkexec /opt/ghost/scripts/hostname_randomize.sh
bindsym $mod+F5 exec --no-startup-id pkexec /opt/ghost/scripts/tor_enable.sh
bindsym $mod+F6 exec --no-startup-id pkexec /opt/ghost/scripts/tor_disable.sh
bindsym $mod+F7 exec --no-startup-id pkexec /opt/ghost/scripts/kill_av.sh
bindsym $mod+F8 exec --no-startup-id pkexec /opt/ghost/scripts/wipe_logs.sh
```

---

## Cron & Systemd Scheduling

```bash
# /etc/cron.d/ghost — system-level cron jobs

# Wipe logs every night at 3am
0 3 * * * root /opt/ghost/scripts/wipe_logs.sh >> /var/log/ghost/cron.log 2>&1

# Rotate hostname every 6 hours
0 */6 * * * root /opt/ghost/scripts/hostname_randomize.sh >> /var/log/ghost/cron.log 2>&1

# MAC rotation is handled by systemd service (with jitter)
```

---

## Master Installer: `install.sh`

```bash
#!/bin/bash
# install.sh — Deploy all ghost scripts and services

set -e

INSTALL_DIR="/opt/ghost/scripts"
mkdir -p "$INSTALL_DIR"
mkdir -p /var/log/ghost

# Copy scripts
cp scripts/*.sh "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR"/*.sh

# Install systemd services
cp systemd/*.service /etc/systemd/system/
systemctl daemon-reload

# Enable services
systemctl enable --now mac-randomize.service
systemctl enable --now idle-shutdown.service
systemctl enable ram-wipe.service
systemctl enable usbguard.service

# Apply sysctl hardening
cp config/99-ghost.conf /etc/sysctl.d/
sysctl -p /etc/sysctl.d/99-ghost.conf

# Apply nftables firewall
cp config/nftables.conf /etc/nftables.conf
systemctl enable --now nftables.service

# Install cron jobs
cp config/ghost.cron /etc/cron.d/ghost

# Disable IPv6
if ! grep -q "ipv6.disable" /etc/default/grub; then
    sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="ipv6.disable=1 /' /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg
fi

echo ""
echo "✅ Ghost Machine deployed successfully."
echo "   Reboot recommended to apply all kernel parameters."
echo ""
echo "⚠️  REMINDER: Set a BIOS supervisor password on the T420."
echo "⚠️  REMINDER: Assign hotkeys in your DE/WM config."
```

---

## File Structure

```
ghost-machine/
├── README.md
├── install.sh
├── scripts/
│   ├── mac_randomize.sh
│   ├── mac_scheduler.sh
│   ├── hostname_randomize.sh
│   ├── panic_shutdown.sh
│   ├── nuclear_wipe.sh
│   ├── idle_shutdown.sh
│   ├── tor_enable.sh
│   ├── tor_disable.sh
│   ├── ram_wipe.sh
│   ├── kill_av.sh
│   ├── mount_vault.sh
│   ├── usb_monitor.sh
│   └── wipe_logs.sh
├── systemd/
│   ├── mac-randomize.service
│   ├── idle-shutdown.service
│   └── ram-wipe.service
└── config/
    ├── 99-ghost.conf       (sysctl hardening)
    ├── nftables.conf       (firewall)
    ├── ghost.cron          (cron jobs)
    └── torrc.append        (Tor configuration additions)
```

---

## Additional Recommendations

| Topic | Recommendation |
|-------|---------------|
| Browser | LibreWolf or Tor Browser — never Chromium |
| DNS | Use `dnscrypt-proxy` with DoH/DoT, never plain DNS |
| VPN | Mullvad (no logs, accepts cash/Monero) |
| Payments | Monero for anything sensitive |
| Communication | Signal (mobile), Briar (P2P), or Session |
| Email | ProtonMail via Tor, or self-hosted with GPG |
| 2FA | Hardware key (YubiKey), never SMS |
| Storage | Only encrypted LUKS volumes, never unencrypted USB |
| Updates | `sudo pacman -Syu` weekly — rolling release means fresh kernels |
| Physical | Lock screen before stepping away; use xautolock (5 min) |
| BIOS | Supervisor password set; boot order: internal disk only |

---

*Ghost Machine — stay invisible.* 🕵️
