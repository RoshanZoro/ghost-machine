# 🕵️ Ghost Machine — Lenovo T420 Manjaro OPSEC Suite

> **Full anonymization, panic response, identity rotation, intrusion detection, and anti-forensics scripts for Manjaro Linux on a Lenovo ThinkPad T420.**

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
- [Nuclear Wipe Panic Button](#5-nuclear-wipe-panic-button)
- [Tor Routing & DNS Leak Prevention](#6-tor-routing--dns-leak-prevention)
- [RAM Wipe on Shutdown](#7-ram-wipe-on-shutdown)
- [USBGuard — Auto-Block Unknown Devices](#8-usbguard--auto-block-unknown-devices)
- [Webcam & Mic Hardware Kill](#9-webcam--mic-hardware-kill)
- [LUKS Full Disk Encryption](#10-luks-full-disk-encryption)
- [Secure Boot & Firmware Hardening](#11-secure-boot--firmware-hardening)
- [Network Lockdown](#12-network-lockdown)
- [Log & Temp File Wiper](#13-log--temp-file-wiper)
- [DNS Hardening with dnscrypt-proxy](#14-dns-hardening-with-dnscrypt-proxy)
- [Leak Test Suite](#15-leak-test-suite)
- [WiFi Auto-Forget](#16-wifi-auto-forget)
- [Metadata Wiper](#17-metadata-wiper)
- [Intrusion Detection — AIDE + auditd](#18-intrusion-detection--aide--auditd)
- [Tripwire — Real-Time File Watcher](#19-tripwire--real-time-file-watcher)
- [Identity Fingerprint Randomizer](#20-identity-fingerprint-randomizer)
- [Encrypted Swap](#21-encrypted-swap)
- [Browser Hardening](#22-browser-hardening)
- [Physical Tamper Detection](#23-physical-tamper-detection)
- [Self Port Scan](#24-self-port-scan)
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
| Shell | bash |
| Network manager | NetworkManager |

---

## Installation & Setup

```bash
# Clone this repo
git clone https://github.com/RoshanZoro/ghost-machine.git
cd ghost-machine

# Run the master installer
sudo bash install.sh
```

The installer handles all dependencies, copies scripts, enables systemd services, applies kernel hardening, and configures the firewall.

---

## 1. MAC Address Randomization

Randomizes your MAC address every hour with an additional random ±15 minute jitter so traffic patterns are harder to correlate.

**Scripts:** `mac_randomize.sh`, `mac_scheduler.sh`
**Service:** `systemd/mac-randomize.service`

```bash
# Rotate MAC immediately
sudo bash /opt/ghost/scripts/mac_randomize.sh

# Check logs
tail -f /var/log/ghost/mac_changes.log
```

The scheduler runs as a persistent daemon. Each cycle:
1. Brings down each interface
2. Applies a random MAC via `macchanger -r`
3. Brings the interface back up
4. Restarts NetworkManager
5. Sleeps for 3600s ± 900s before repeating

---

## 2. Hostname Randomization

Generates a random plausible-looking hostname (`silent-relay-0847`, `dark-node-3312`) and applies it live without a reboot.

**Script:** `hostname_randomize.sh`

```bash
sudo bash /opt/ghost/scripts/hostname_randomize.sh
```

Also rotates automatically every 6 hours via cron. History logged to `/var/log/ghost/hostname_history.log`.

---

## 3. Panic Button — Immediate Shutdown

One keypress triggers an **immediate forced power-off** via kernel SysRq — no sync, no graceful unmount, no delay.

**Script:** `panic_shutdown.sh`

```bash
# Assign Super+F1 to:
sudo bash /opt/ghost/scripts/panic_shutdown.sh
```

Uses `echo o > /proc/sysrq-trigger` — this is kernel-level and executes in under a second, bypassing all userspace.

**SysRq manual combos:**

| Combo | Action |
|-------|--------|
| `Alt+SysRq+S` | Emergency sync |
| `Alt+SysRq+U` | Remount all read-only |
| `Alt+SysRq+O` | Immediate power off |

---

## 4. Idle Auto-Shutdown (2 Hours)

Monitors X11 idle time and CPU usage. If both remain below threshold for 2 hours, the machine shuts down.

**Script:** `idle_shutdown.sh`
**Service:** `systemd/idle-shutdown.service`

```bash
sudo systemctl status idle-shutdown.service
tail -f /var/log/ghost/idle_shutdown.log
```

Both conditions must be met simultaneously: X idle ≥ 7200s AND CPU usage < 5%. This prevents shutdown during unattended downloads or builds.

---

## 5. Nuclear Wipe Panic Button

> **⚠️ PERMANENT AND IRREVERSIBLE. This destroys ALL data on the system. There is NO recovery.**

Press the assigned hotkey **3 times within 5 seconds** to trigger. Runs `shred` on key directories before `rm -rf /` for forensic resistance. Optional LUKS header erasure (most effective — see script comments).

**Script:** `nuclear_wipe.sh`

```bash
# Assign Super+F2 to:
sudo bash /opt/ghost/scripts/nuclear_wipe.sh
```

> **Forensics note:** `shred` + LUKS header erasure (`cryptsetup erase /dev/sda`) is far more effective than `rm -rf /` alone. Enable the LUKS line in the script for maximum effect.

---

## 6. Tor Routing & DNS Leak Prevention

Routes all traffic through Tor via iptables transparent proxy with a kill switch — if Tor drops, all traffic is **blocked** rather than exposed in plaintext.

**Scripts:** `tor_enable.sh`, `tor_disable.sh`
**Config:** `config/torrc.append`

```bash
# Enable Tor + kill switch
sudo bash /opt/ghost/scripts/tor_enable.sh

# Disable and restore normal routing
sudo bash /opt/ghost/scripts/tor_disable.sh
```

**Tor config additions** (appended to `/etc/tor/torrc`):

```
TransPort 9040
DNSPort 5353
AutomapHostsOnResolve 1
SafeLogging 1
AvoidDiskWrites 1
```

> **Always disable IPv6** when using Tor — IPv6 traffic can bypass Tor entirely. This suite disables it at kernel level.

---

## 7. RAM Wipe on Shutdown

Overwrites free RAM before power-off to prevent cold-boot attacks where an attacker freezes memory chips and reads residual contents.

**Script:** `ram_wipe.sh`
**Service:** `systemd/ram-wipe.service`

```bash
# Install secure-delete for multi-pass wipe
sudo pacman -S secure-delete

sudo systemctl enable ram-wipe.service
```

Uses `dd if=/dev/zero` for speed, then `sdmem -f -l -v` from `secure-delete` for thoroughness.

---

## 8. USBGuard — Auto-Block Unknown Devices

Only pre-authorized USB devices are permitted. Any new device is automatically blocked the moment it's inserted.

**Script:** `usb_monitor.sh`

```bash
# Generate policy from currently trusted devices
sudo usbguard generate-policy > /etc/usbguard/rules.conf
sudo systemctl enable --now usbguard.service

# Live monitor with alerts
sudo bash /opt/ghost/scripts/usb_monitor.sh

# Manage devices
sudo usbguard list-devices
sudo usbguard allow-device <ID>
```

---

## 9. Webcam & Mic Hardware Kill

Unloads the webcam kernel module and mutes the microphone at ALSA, PulseAudio, and PipeWire levels simultaneously.

**Script:** `kill_av.sh`

```bash
sudo bash /opt/ghost/scripts/kill_av.sh

# Re-enable webcam
sudo modprobe uvcvideo

# Unmute mic
pactl set-source-mute @DEFAULT_SOURCE@ 0
```

> **Hardware:** Tape over the T420 lens is still the most reliable webcam kill. The T420's `Fn+F4` physically mutes the mic at hardware level regardless of software state.

---

## 10. LUKS Full Disk Encryption

**Script:** `mount_vault.sh`

```bash
# Create a 2GB encrypted vault container
dd if=/dev/urandom of=/secure/vault.img bs=1M count=2048
cryptsetup luksFormat /secure/vault.img
cryptsetup luksOpen /secure/vault.img ghost_vault
mkfs.ext4 /dev/mapper/ghost_vault

# Open/close vault
sudo bash /opt/ghost/scripts/mount_vault.sh
sudo bash /opt/ghost/scripts/mount_vault.sh close

# Permanently destroy all data (NO RECOVERY)
# cryptsetup erase /dev/sda
```

---

## 11. Secure Boot & Firmware Hardening

### BIOS Settings (T420 — press F1 at boot)

```
Security → Password → Supervisor Password   ← SET THIS FIRST
Security → Security Chip                    → Disabled
Config → Network → Wake on LAN              → Disabled
Config → USB → USB UEFI BIOS Support        → Disabled
Security → Virtualization                   → Disabled (unless needed)
```

### Kernel hardening: `config/99-ghost.conf`

Applied via `sysctl -p`. Key settings:

| Setting | Value | Effect |
|---------|-------|--------|
| `kernel.yama.ptrace_scope` | 2 | Block ptrace between unrelated processes |
| `kernel.dmesg_restrict` | 1 | Hide dmesg from non-root |
| `kernel.randomize_va_space` | 2 | Full ASLR |
| `net.ipv6.conf.all.disable_ipv6` | 1 | Kill IPv6 globally |
| `fs.suid_dumpable` | 0 | No core dumps |

---

## 12. Network Lockdown

### nftables firewall (`config/nftables.conf`)

Default-drop on all inbound. Only established/related connections accepted. Forward chain completely blocked.

```bash
sudo systemctl enable --now nftables.service
sudo nft list ruleset
```

### Disable IPv6 at boot

Added to `GRUB_CMDLINE_LINUX`: `ipv6.disable=1`

---

## 13. Log & Temp File Wiper

Securely wipes system logs, shell history, thumbnail caches, recent file lists, and browser artifacts.

**Script:** `wipe_logs.sh`

```bash
sudo bash /opt/ghost/scripts/wipe_logs.sh
```

Covers: `journalctl`, `/var/log/*.log`, `.bash_history`, `.zsh_history`, `/tmp`, `/var/tmp`, thumbnail caches, `recently-used.xbel`, Firefox/LibreWolf SQLite history. Uses `shred` for overwrite before deletion. Symlinks history files to `/dev/null` to prevent future writes.

---

## 14. DNS Hardening with dnscrypt-proxy

Encrypts all DNS queries using DNS-over-HTTPS. Prevents DNS leaks even when Tor is not active. Makes `/etc/resolv.conf` immutable so NetworkManager cannot override it.

**Script:** `dns_hardening.sh`

```bash
sudo bash /opt/ghost/scripts/dns_hardening.sh
```

**What it does:**
- Installs and configures `dnscrypt-proxy` on `127.0.0.1:53`
- Enforces `require_nolog = true` — only uses no-log resolvers
- Enables `require_dnssec = true` — validates DNS signatures
- Sets `block_ipv6 = true` — no IPv6 DNS leaks
- Uses `lb_strategy = p2` — randomizes resolver selection per query
- Makes `/etc/resolv.conf` immutable with `chattr +i`

```bash
# Verify DNS is encrypted
dig +short @127.0.0.1 example.com
systemctl status dnscrypt-proxy
```

> **Resolvers used:** Cloudflare, Quad9, Mullvad, NextDNS — all no-log, all DoH. Edit `/etc/dnscrypt-proxy/dnscrypt-proxy.toml` to change.

---

## 15. Leak Test Suite

Comprehensive check for DNS leaks, IPv6 leaks, Tor connectivity, open ports, and MAC address randomization status.

**Script:** `leak_test.sh`

```bash
sudo bash /opt/ghost/scripts/leak_test.sh
```

**Checks performed:**

| Check | What it tests |
|-------|--------------|
| IPv6 disabled | Kernel flag + interface addresses |
| DNS via localhost | resolv.conf + dnscrypt-proxy running |
| DNS resolution | Live query through 127.0.0.1 |
| Tor active | Service status + exit node verification |
| Open ports | `ss -tlnp` for external listeners |
| MAC randomized | Locally-administered bit check on all interfaces |

Exit code 0 = all clean. Exit code 1 = failures found. Suitable for cron or pre-session hook.

---

## 16. WiFi Auto-Forget

Deletes all saved WiFi profiles on demand (or on shutdown). Prevents the machine from passively broadcasting known SSID probe requests.

**Script:** `wifi_forget.sh`

```bash
sudo bash /opt/ghost/scripts/wifi_forget.sh
```

Clears both NetworkManager (`/etc/NetworkManager/system-connections/`) and iwd profiles (`/var/lib/iwd/`). Add to shutdown hook or run manually before moving locations.

```bash
# Add to systemd shutdown
# ExecStop=/opt/ghost/scripts/wifi_forget.sh
```

---

## 17. Metadata Wiper

Strips embedded metadata (GPS, author, timestamps, device info, software version) from documents, images, and media files before sharing.

**Script:** `metadata_wipe.sh`

```bash
# Wipe a single file
bash /opt/ghost/scripts/metadata_wipe.sh document.pdf

# Wipe an entire directory recursively
bash /opt/ghost/scripts/metadata_wipe.sh ~/Documents/to_share/
```

Uses `mat2` as primary (handles PDF, DOCX, XLSX, JPG, PNG, MP4, MP3, ZIP and more) with `exiftool` as fallback. Operates in-place — no copy created.

**Supported formats:** JPG, PNG, GIF, PDF, DOCX, XLSX, PPTX, ODT, MP3, MP4, MOV, ZIP, HEIC, TIFF

```bash
sudo pacman -S perl-image-exiftool
pip install mat2 --break-system-packages
```

---

## 18. Intrusion Detection — AIDE + auditd

AIDE hashes all system binaries and configuration files on setup. On each check, it compares current state against the baseline and alerts on any change. `auditd` logs every privileged command and modification to sensitive files.

**Script:** `intrusion_detection.sh`

```bash
# First run — initialize database (takes ~2 minutes)
sudo bash /opt/ghost/scripts/intrusion_detection.sh setup

# Daily check (also runs via cron)
sudo bash /opt/ghost/scripts/intrusion_detection.sh check
```

**AIDE monitors:** `/boot`, `/etc`, `/usr/bin`, `/usr/sbin`, `/usr/lib`, `/opt/ghost`

**auditd rules watch:**
- `/etc/passwd`, `/etc/shadow`, `/etc/sudoers`
- `/etc/NetworkManager`, `/etc/hosts`
- `/etc/systemd/system`
- All root command executions

```bash
# View recent audit events
ausearch -k identity
ausearch -k ghost_scripts
journalctl -u auditd -f
```

---

## 19. Tripwire — Real-Time File Watcher

Uses `inotifywait` to watch critical paths in real time. Generates desktop notifications and wall messages the moment anything is modified. Also deploys **honeypot files** — fake credential files that trigger an alert if anything reads them.

**Script:** `tripwire_watch.sh`
**Service:** `systemd/tripwire.service` (created by `intrusion_detection.sh setup`)

```bash
# Run manually
sudo bash /opt/ghost/scripts/tripwire_watch.sh

# Or via service
sudo systemctl status tripwire.service
tail -f /var/log/ghost/tripwire_alerts.log
```

**Honeypot files deployed:**

| File | Fake content |
|------|-------------|
| `/root/.aws/credentials` | Fake AWS access keys |
| `/home/user/.ssh/id_rsa_backup` | Fake SSH private key |
| `/root/passwords.txt` | Bait text file |
| `/home/user/wallet.dat` | Random binary blob |

Any process that reads these files triggers an immediate alert. Legitimate processes will never touch them.

---

## 20. Identity Fingerprint Randomizer

Rotates all system-level fingerprint components: timezone, locale, clock skew, machine-id, hostname, and MAC address — in a single command.

**Script:** `identity_randomize.sh`

```bash
sudo bash /opt/ghost/scripts/identity_randomize.sh
```

**What gets rotated:**

| Component | Method |
|-----------|--------|
| Timezone | Random from curated pool via `timedatectl` |
| Clock | ±30 second random skew |
| Locale | Random English locale (US/GB/CA/AU) |
| Hostname | Random adjective-noun-number |
| MAC address | `macchanger -r` on all interfaces |
| machine-id | New UUID written to `/etc/machine-id` |

Run before sensitive sessions or add to cron for periodic rotation.

---

## 21. Encrypted Swap

Replaces plaintext swap with a swap partition encrypted with a new random key on every boot. Without this, paged-out RAM contents land on disk in plaintext, bypassing LUKS entirely.

**Script:** `encrypt_swap.sh`

```bash
sudo bash /opt/ghost/scripts/encrypt_swap.sh
# Reboot required
```

Uses `/dev/urandom` as the key source in `/etc/crypttab` — a new random key is generated at every boot, making the swap permanently unrecoverable after shutdown even if the drive is seized.

```
# /etc/crypttab entry created:
cryptswap  /dev/sdaX  /dev/urandom  swap,cipher=aes-xts-plain64,size=256
```

---

## 22. Browser Hardening

Applies `arkenfox user.js` (the most comprehensive Firefox hardening config available) plus Ghost Machine overrides, and creates a post-session wipe script.

**Script:** `browser_harden.sh`

```bash
# Run as your desktop user (not root)
bash /opt/ghost/scripts/browser_harden.sh
```

**Key settings applied:**

| Setting | Effect |
|---------|--------|
| `privacy.resistFingerprinting` | Spoof canvas, fonts, screen size |
| `media.peerconnection.enabled = false` | Disable WebRTC (major leak vector) |
| `network.proxy.socks_remote_dns = true` | DNS through SOCKS proxy (Tor) |
| `privacy.sanitize.sanitizeOnShutdown` | Wipe everything on close |
| Spoofed User-Agent | Common Windows/Firefox string |
| No saved passwords | Disabled at pref level |
| No search suggestions | Prevents keylogging searches |

**Manual steps after running:**
1. Install **uBlock Origin** → enable hard mode
2. Install **NoScript** for per-site JS control
3. Never use the same browser profile for different identities
4. Use **Tor Browser** for maximum anonymity sessions

---

## 23. Physical Tamper Detection

Detects if the laptop has been physically opened by comparing webcam photos of glitter nail polish applied over BIOS screws and case seams. Each glitter pattern is unique and impossible to replicate exactly.

**Script:** `tamper_detect.sh`

```bash
# Setup: apply glitter nail polish, let dry, then:
sudo bash /opt/ghost/scripts/tamper_detect.sh setup

# Check on each boot:
sudo bash /opt/ghost/scripts/tamper_detect.sh check
```

**Physical preparation:**
1. Apply glitter nail polish over every BIOS screw head
2. Apply a streak across case seams and port covers
3. Photograph under consistent lighting immediately
4. Run `setup` to hash and store the baseline image
5. Any disturbance to the glitter pattern changes the hash → alert

> Add `tamper_detect.sh check` to your boot sequence or login script to verify integrity before each session.

---

## 24. Self Port Scan

Runs `nmap -sV -p-` against localhost to audit your open attack surface. Compares against a saved baseline and alerts on any new open ports.

**Script:** `self_scan.sh`

```bash
# Set baseline after initial hardened setup
sudo bash /opt/ghost/scripts/self_scan.sh baseline

# Check for new ports (run via cron weekly)
sudo bash /opt/ghost/scripts/self_scan.sh
```

Any port open externally that wasn't in the baseline triggers a desktop notification and wall message. Useful for catching services that got accidentally started.

---

## Keyboard Shortcut Setup

| Hotkey | Script | Action |
|--------|--------|--------|
| `Super+F1` | `panic_shutdown.sh` | Instant forced power-off |
| `Super+F2` | `nuclear_wipe.sh` | Triple-press nuclear wipe |
| `Super+F3` | `mac_randomize.sh` | Rotate MAC now |
| `Super+F4` | `identity_randomize.sh` | Full identity rotation |
| `Super+F5` | `tor_enable.sh` | Enable Tor + kill switch |
| `Super+F6` | `tor_disable.sh` | Disable Tor |
| `Super+F7` | `kill_av.sh` | Kill webcam + mic |
| `Super+F8` | `wipe_logs.sh` | Wipe logs + history |
| `Super+F9` | `leak_test.sh` | Run leak test suite |
| `Super+F10` | `metadata_wipe.sh` | Wipe metadata (current dir) |

### i3 (`~/.config/i3/config`)

```
bindsym $mod+F1  exec --no-startup-id pkexec /opt/ghost/scripts/panic_shutdown.sh
bindsym $mod+F2  exec --no-startup-id pkexec /opt/ghost/scripts/nuclear_wipe.sh
bindsym $mod+F3  exec --no-startup-id pkexec /opt/ghost/scripts/mac_randomize.sh
bindsym $mod+F4  exec --no-startup-id pkexec /opt/ghost/scripts/identity_randomize.sh
bindsym $mod+shift+F5  exec --no-startup-id pkexec /opt/ghost/scripts/tor_enable.sh
bindsym $mod+shift+F6  exec --no-startup-id pkexec /opt/ghost/scripts/tor_disable.sh
bindsym $mod+F7  exec --no-startup-id pkexec /opt/ghost/scripts/kill_av.sh
bindsym $mod+F8  exec --no-startup-id pkexec /opt/ghost/scripts/wipe_logs.sh
bindsym $mod+F9  exec --no-startup-id pkexec /opt/ghost/scripts/leak_test.sh
bindsym $mod+F10 exec --no-startup-id bash /opt/ghost/scripts/metadata_wipe.sh .
```

---

## Cron & Systemd Scheduling

```
# /etc/cron.d/ghost

# Wipe logs nightly at 3am
0 3 * * * root /opt/ghost/scripts/wipe_logs.sh

# Rotate full identity every 6 hours
0 */6 * * * root /opt/ghost/scripts/identity_randomize.sh

# AIDE integrity check daily at 4am
0 4 * * * root /opt/ghost/scripts/intrusion_detection.sh check

# Self port scan weekly (Sunday 2am)
0 2 * * 0 root /opt/ghost/scripts/self_scan.sh

# Leak test on every boot (add to rc.local or @reboot cron)
@reboot root sleep 30 && /opt/ghost/scripts/leak_test.sh
```

---

## File Structure

```
ghost-machine/
├── README.md
├── install.sh
├── scripts/
│   ├── mac_randomize.sh          # Rotate MAC address
│   ├── mac_scheduler.sh          # Hourly MAC rotation daemon
│   ├── hostname_randomize.sh     # Random hostname
│   ├── identity_randomize.sh     # Full identity rotation (TZ, locale, machine-id)
│   ├── panic_shutdown.sh         # Instant forced power-off
│   ├── nuclear_wipe.sh           # Triple-press shred + rm -rf /
│   ├── idle_shutdown.sh          # 2h idle auto-shutdown
│   ├── tor_enable.sh             # Tor + iptables kill switch
│   ├── tor_disable.sh            # Restore normal routing
│   ├── dns_hardening.sh          # dnscrypt-proxy DoH setup
│   ├── leak_test.sh              # DNS/IPv6/Tor/port leak checker
│   ├── wifi_forget.sh            # Delete all saved WiFi profiles
│   ├── ram_wipe.sh               # Overwrite RAM on shutdown
│   ├── kill_av.sh                # Kill webcam + mic
│   ├── usb_monitor.sh            # USBGuard alert daemon
│   ├── mount_vault.sh            # LUKS vault open/close
│   ├── wipe_logs.sh              # Wipe logs, history, caches
│   ├── metadata_wipe.sh          # Strip file metadata (mat2/exiftool)
│   ├── intrusion_detection.sh    # AIDE + auditd setup and check
│   ├── tripwire_watch.sh         # inotify real-time watcher + honeypots
│   ├── encrypt_swap.sh           # Replace swap with encrypted swap
│   ├── browser_harden.sh         # arkenfox user.js + post-session wipe
│   ├── tamper_detect.sh          # Glitter nail polish photo hash check
│   └── self_scan.sh              # nmap self-audit
├── systemd/
│   ├── mac-randomize.service
│   ├── idle-shutdown.service
│   └── ram-wipe.service
└── config/
    ├── 99-ghost.conf             # sysctl kernel hardening
    ├── nftables.conf             # Default-drop firewall
    ├── ghost.cron                # All cron jobs
    └── torrc.append              # Tor transparent proxy config
```

---

## Quick Reference — Threat Response

| Threat | Response |
|--------|----------|
| Someone approaching | `Super+F1` — instant power cut |
| Device seizure imminent | `Super+F2` (×3) — nuclear wipe |
| Unexpected USB inserted | USBGuard auto-blocks; alert fired |
| Suspicious file change | AIDE/tripwire alert; check logs |
| Unknown open port | self_scan.sh alert; kill the service |
| Before sharing a file | `Super+F10` — wipe metadata |
| Before leaving location | `wifi_forget.sh` — delete WiFi profiles |
| Starting sensitive session | `Super+F5` Tor on → `Super+F9` leak test |
| Ending session | `Super+F8` wipe logs + `Super+F7` kill A/V |

---

## Additional Recommendations

| Topic | Recommendation |
|-------|---------------|
| Browser | LibreWolf + arkenfox, Tor Browser for max anonymity |
| DNS | dnscrypt-proxy (this suite) + Mullvad or Quad9 resolvers |
| VPN | Mullvad (no logs, accepts Monero) — chain before Tor |
| Payments | Monero for anything sensitive |
| Communication | Signal, Briar (P2P mesh), or Session (no phone number) |
| Email | ProtonMail via Tor, or GPG-encrypted with throwaway addresses |
| 2FA | YubiKey hardware token — never SMS |
| Storage | LUKS volumes only, never unencrypted USB |
| Physical | Glitter nail polish on screws; privacy screen filter; Faraday bag for transit |
| Updates | `sudo pacman -Syu` weekly — rolling release = fresh kernels |
| BIOS | Supervisor password set; boot order locked to internal disk |

---

*Ghost Machine — stay invisible.* 🕵️
