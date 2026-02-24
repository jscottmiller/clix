#!/usr/bin/env bash
# Build the CLIX disk image
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "╔════════════════════════════════════════╗"
echo "║  Building CLIX Disk Image              ║"
echo "╚════════════════════════════════════════╝"
echo ""

# Default to disk image, but allow building ISO with --iso flag
if [ "${1:-}" = "--iso" ]; then
    echo "Building ISO..."
    nix build .#iso --show-trace

    ISO_PATH=$(find result/iso -name "*.iso" 2>/dev/null | head -1)
    if [ -n "$ISO_PATH" ]; then
        ISO_SIZE=$(du -h "$ISO_PATH" | cut -f1)
        echo ""
        echo "ISO: $ISO_PATH"
        echo "Size: $ISO_SIZE"
    fi
else
    echo "Building disk image (with CLIX-DATA partition)..."
    nix build .#image --show-trace

    echo ""
    echo "Build complete!"
    echo ""

    if [ -f result/clix.img ]; then
        IMG_SIZE=$(du -h result/clix.img | cut -f1)
        echo "Image: result/clix.img"
        echo "Size: $IMG_SIZE"
        echo ""
        echo "To test in VM:   ./scripts/test-vm.sh"
        echo "To write to USB: ./scripts/write-usb.sh /dev/sdX"
    fi
fi
