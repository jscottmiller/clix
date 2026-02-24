#!/usr/bin/env bash
# Test CLIX disk image in QEMU VM
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

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

echo "╔════════════════════════════════════════╗"
echo "║  Testing CLIX in QEMU                  ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "Image: $IMG_PATH"
echo ""

# Memory (default 4G, override with $CLIX_MEMORY)
MEMORY="${CLIX_MEMORY:-4G}"

# CPUs (default 2, override with $CLIX_CPUS)
CPUS="${CLIX_CPUS:-2}"

# Find OVMF firmware for UEFI boot
OVMF_PATHS=(
    "/usr/share/OVMF/OVMF_CODE.fd"
    "/usr/share/ovmf/OVMF.fd"
    "/usr/share/edk2/ovmf/OVMF_CODE.fd"
    "/run/libvirt/nix-ovmf/OVMF_CODE.fd"
    "/usr/share/qemu/OVMF.fd"
)

OVMF=""
for path in "${OVMF_PATHS[@]}"; do
    if [ -f "$path" ]; then
        OVMF="$path"
        break
    fi
done

if [ -z "$OVMF" ]; then
    echo "Error: OVMF not found. Install OVMF/UEFI firmware for QEMU."
    echo "On Debian/Ubuntu: sudo apt install ovmf"
    exit 1
fi

echo "Using UEFI: $OVMF"
echo "Starting QEMU with ${MEMORY} RAM, ${CPUS} CPUs..."
echo ""

# Create a temporary copy of the image (so we can write to it)
TMP_IMG=$(mktemp --suffix=.img)
cp "$IMG_PATH" "$TMP_IMG"
chmod +w "$TMP_IMG"
trap "rm -f $TMP_IMG" EXIT

# Build QEMU command
exec qemu-system-x86_64 \
    -enable-kvm \
    -m "$MEMORY" \
    -smp "$CPUS" \
    -drive file="$TMP_IMG",format=raw,if=virtio \
    -bios "$OVMF" \
    -device virtio-vga-gl \
    -display gtk,gl=on \
    -device virtio-net-pci,netdev=net0 \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -usb \
    -device usb-tablet
