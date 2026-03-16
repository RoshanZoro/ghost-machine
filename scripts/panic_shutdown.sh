#!/bin/bash
# panic_shutdown.sh — Immediate forced power cut
# Assign to a hotkey for instant emergency shutdown

# Enable SysRq
echo 1 > /proc/sys/kernel/sysrq

# Kernel-level immediate power off (bypasses everything)
echo o > /proc/sysrq-trigger

# Fallback: systemd double-force
systemctl poweroff --force --force

# Nuclear fallback
/sbin/poweroff -f
