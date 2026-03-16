#!/bin/bash
# encrypt_swap.sh — Replace plaintext swap with encrypted swap
# Prevents RAM contents from landing on disk in plaintext
# Run once as root — WILL disable existing swap temporarily

set -e

echo "⚠️  This will replace your existing swap with an encrypted swap."
echo "   Any data currently in swap will be lost."
read -rp "Continue? (yes/no): " CONFIRM
[ "$CONFIRM" = "yes" ] || { echo "Aborted."; exit 0; }

# Find existing swap partition
SWAP_DEV=$(swapon --show=NAME --noheadings 2>/dev/null | head -1)

if [ -z "$SWAP_DEV" ]; then
    echo "No active swap found. Looking for swap in /etc/fstab..."
    SWAP_DEV=$(grep '\sswap\s' /etc/fstab | grep -v '^#' | awk '{print $1}' | head -1)
fi

if [ -z "$SWAP_DEV" ]; then
    echo "No swap partition found. Creating a swap file instead..."
    SWAP_FILE="/swapfile"
    dd if=/dev/zero of="$SWAP_FILE" bs=1M count=2048
    chmod 600 "$SWAP_FILE"
    SWAP_DEV="$SWAP_FILE"
fi

echo "Using swap device: $SWAP_DEV"

# Disable current swap
swapoff -a

# Remove old swap entries from /etc/fstab
sed -i '/\sswap\s/d' /etc/fstab

# Add encrypted swap via crypttab (re-encrypted with random key on each boot)
SWAP_NAME="cryptswap"

# Add to /etc/crypttab — /dev/urandom key = new random key every boot
echo "$SWAP_NAME  $SWAP_DEV  /dev/urandom  swap,cipher=aes-xts-plain64,size=256" >> /etc/crypttab

# Add encrypted swap to /etc/fstab
echo "/dev/mapper/$SWAP_NAME  none  swap  defaults  0 0" >> /etc/fstab

# Re-generate initramfs so crypttab is picked up at boot
echo "→ Regenerating initramfs..."
mkinitcpio -P

echo ""
echo "✅ Encrypted swap configured."
echo "   Changes take effect after reboot."
echo "   The swap is re-encrypted with a new random key on every boot."
echo "   There is no key to steal — even a pulled drive won't expose swap contents."
