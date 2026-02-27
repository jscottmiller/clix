#!/usr/bin/env bash
# Write CLIX disk image to USB drive
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

# Check for device argument
if [ $# -lt 1 ]; then
    echo "Usage: $0 /dev/sdX"
    echo ""
    echo "Available devices:"
    lsblk -d -o NAME,SIZE,MODEL,TRAN | grep -E "usb|NAME" || lsblk -d -o NAME,SIZE,MODEL
    exit 1
fi

DEVICE="$1"

# Safety checks
if [ ! -b "$DEVICE" ]; then
    echo "Error: $DEVICE is not a block device"
    exit 1
fi

if [[ "$DEVICE" == *"nvme"*"n"[0-9]"p"* ]] || [[ "$DEVICE" == *"sda"* ]]; then
    echo "Warning: $DEVICE looks like a system disk!"
    echo "Are you SURE this is your USB drive? (type 'yes' to continue)"
    read -r confirm
    if [ "$confirm" != "yes" ]; then
        echo "Aborted."
        exit 1
    fi
fi

# Find the image
IMG_PATH=""
if [ -f result/clix.img ]; then
    IMG_PATH="result/clix.img"
elif [ -f result/nixos.img ]; then
    IMG_PATH="result/nixos.img"
fi

if [ -z "$IMG_PATH" ]; then
    echo "Error: No disk image found. Run ./scripts/build-iso.sh first"
    exit 1
fi

IMG_SIZE=$(du -h "$IMG_PATH" | cut -f1)

echo "╔════════════════════════════════════════╗"
echo "║  Writing CLIX to USB                   ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "Image: $IMG_PATH ($IMG_SIZE)"
echo "Device: $DEVICE"
echo ""

# Show device info
echo "Device info:"
lsblk "$DEVICE" -o NAME,SIZE,MODEL,MOUNTPOINT 2>/dev/null || true
echo ""

# Confirm
echo "This will ERASE ALL DATA on $DEVICE"
echo "Type 'yes' to continue:"
read -r confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

# Unmount any mounted partitions
echo ""
echo "Unmounting partitions..."
for part in "${DEVICE}"*; do
    if mountpoint -q "$part" 2>/dev/null || mount | grep -q "$part"; then
        sudo umount "$part" 2>/dev/null || true
    fi
done

# Write the image
echo ""
echo "Writing image to $DEVICE..."
echo "This may take several minutes..."
echo ""

sudo dd if="$IMG_PATH" of="$DEVICE" bs=4M status=progress conv=fsync

echo ""
echo "Syncing..."
sync

echo ""
echo "╔════════════════════════════════════════╗"
echo "║  Done! USB is ready to boot.           ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "Current partition layout:"
echo "  1. ESP (FAT32)   - EFI boot"
echo "  2. nixos (ext4)  - System root"
echo ""
echo "On first boot, a setup wizard will:"
echo "  - Detect free space on your USB"
echo "  - Create CLIX-DATA (FAT32) and CLIX-HOME partitions"
echo "  - Optionally encrypt CLIX-HOME with LUKS"
echo ""
echo "After setup, you can mount CLIX-DATA on any computer"
echo "to add WiFi config (network/*.nmconnection) or Claude"
echo "credentials (claude/)."
