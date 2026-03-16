#!/bin/bash
cd "$HOME" 2>/dev/null || cd /tmp
# mount_vault.sh — Open and mount an encrypted LUKS vault container

VAULT_IMG="/secure/vault.img"
VAULT_NAME="ghost_vault"
MOUNT_POINT="/mnt/vault"

# Unmount mode
if [ "$1" = "close" ]; then
    umount "$MOUNT_POINT" 2>/dev/null && echo "Unmounted."
    cryptsetup luksClose "$VAULT_NAME" 2>/dev/null && echo "Vault closed."
    exit 0
fi

mkdir -p "$MOUNT_POINT"

if [ ! -f "$VAULT_IMG" ]; then
    echo "Vault image not found at $VAULT_IMG"
    echo "Create one with:"
    echo "  dd if=/dev/urandom of=$VAULT_IMG bs=1M count=2048"
    echo "  cryptsetup luksFormat $VAULT_IMG"
    echo "  cryptsetup luksOpen $VAULT_IMG $VAULT_NAME"
    echo "  mkfs.ext4 /dev/mapper/$VAULT_NAME"
    exit 1
fi

cryptsetup luksOpen "$VAULT_IMG" "$VAULT_NAME" && \
    mount /dev/mapper/"$VAULT_NAME" "$MOUNT_POINT" && \
    echo "✅ Vault mounted at $MOUNT_POINT" || \
    echo "❌ Failed to open vault."

echo "To close: sudo bash mount_vault.sh close"
