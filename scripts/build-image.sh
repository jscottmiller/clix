#!/usr/bin/env bash
# CLIX Image Builder
# Creates a bootable USB image with:
#   - ESP (512MB, FAT32) - EFI boot
#   - CLIX-PUBLIC (2GB, FAT32) - Windows/Mac readable staging area
#   - CLIX-ROOT (8GB, ext4) - NixOS system (expandable at first boot)
#
# IMPORTANT: Run with sudo for correct file ownership:
#   sudo ./scripts/build-image.sh

set -euo pipefail

# Enable Nix experimental features (flakes, nix-command)
export NIX_CONFIG="experimental-features = nix-command flakes"

# Ensure nix is in PATH (needed when running via sudo)
if ! command -v nix &>/dev/null; then
    for nixbin in /nix/var/nix/profiles/default/bin /run/current-system/sw/bin ~/.nix-profile/bin; do
        if [[ -d "$nixbin" ]]; then
            export PATH="$nixbin:$PATH"
        fi
    done
fi

# Verify nix is available
if ! command -v nix &>/dev/null; then
    echo "Error: 'nix' not found in PATH. Is Nix installed?" >&2
    exit 1
fi

# Warn if not running as root (file ownership will be wrong)
if [[ $EUID -ne 0 ]]; then
    echo "WARNING: Not running as root. File ownership in image may be incorrect." >&2
    echo "         NetworkManager plugins may fail to load." >&2
    echo "         Consider: sudo $0 $*" >&2
    echo ""
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Configuration
ESP_SIZE_MB=512
DATA_SIZE_MB=2048
ROOT_SIZE_MB=8192
TOTAL_SIZE_MB=$((ESP_SIZE_MB + DATA_SIZE_MB + ROOT_SIZE_MB + 2))  # +2 for GPT overhead

IMAGE_NAME="clix.img"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${PROJECT_DIR}/result"
WORK_DIR="${OUTPUT_DIR}/work"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[CLIX]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# Check for required tools
check_requirements() {
    local missing=()
    for cmd in nix parted mtools mcopy mmd mformat mkfs.ext4 dd sfdisk; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        # Try to get them from nix
        log "Getting required tools via nix-shell..."
        exec nix-shell -p mtools dosfstools e2fsprogs util-linux parted --run "$0 $*"
    fi
}

# Build NixOS system
build_system() {
    log "Building NixOS system..."
    nix build "${PROJECT_DIR}#nixosConfigurations.clix.config.system.build.toplevel" \
        --out-link "${OUTPUT_DIR}/system"
}

# Create individual partition images
create_partition_images() {
    log "Creating partition images..."
    mkdir -p "$WORK_DIR"

    # ESP partition image
    log "Creating ESP image (${ESP_SIZE_MB}MB)..."
    truncate -s "${ESP_SIZE_MB}M" "$WORK_DIR/esp.img"
    mformat -F -v ESP -i "$WORK_DIR/esp.img" ::

    # CLIX-PUBLIC partition image
    log "Creating CLIX-PUBLIC image (${DATA_SIZE_MB}MB)..."
    truncate -s "${DATA_SIZE_MB}M" "$WORK_DIR/data.img"
    mformat -F -v CLIX-PUBLIC -i "$WORK_DIR/data.img" ::

    # CLIX-ROOT partition - we'll create this after populating a directory
    log "Creating CLIX-ROOT staging directory..."
    mkdir -p "$WORK_DIR/root"
}

# Populate CLIX-PUBLIC partition using mtools
populate_data_partition() {
    log "Populating CLIX-PUBLIC partition..."

    # Create clix directory with subdirectories
    mmd -i "$WORK_DIR/data.img" ::clix
    mmd -i "$WORK_DIR/data.img" ::clix/claude ::clix/network

    # Create README at root
    cat > "$WORK_DIR/README.txt" << 'DATAEOF'
CLIX Public Partition
=====================

This partition is readable from Windows, Mac, and Linux.
Place configuration files in the clix/ folder.

WiFi Configuration
------------------
Create: clix/network/wifi.nmconnection

Example wifi.nmconnection:
[connection]
id=MyWiFi
type=wifi

[wifi]
ssid=MyWiFi

[wifi-security]
key-mgmt=wpa-psk
psk=mypassword

[ipv4]
method=auto

[ipv6]
method=auto

Create: clix/network/regdomain
Contents: Your 2-letter country code (e.g., US, GB, DE)

Claude Credentials
------------------
Copy your Claude credentials to: clix/claude/
(Contents of ~/.claude from an existing installation)

DATAEOF

    mcopy -i "$WORK_DIR/data.img" "$WORK_DIR/README.txt" ::README.txt
    rm "$WORK_DIR/README.txt"
}

# Populate ESP with bootloader
populate_esp() {
    log "Populating ESP with bootloader..."

    local system_path
    system_path=$(readlink -f "${OUTPUT_DIR}/system")

    # Create directory structure
    mmd -i "$WORK_DIR/esp.img" ::EFI
    mmd -i "$WORK_DIR/esp.img" ::EFI/BOOT
    mmd -i "$WORK_DIR/esp.img" ::EFI/systemd
    mmd -i "$WORK_DIR/esp.img" ::EFI/nixos
    mmd -i "$WORK_DIR/esp.img" ::loader
    mmd -i "$WORK_DIR/esp.img" ::loader/entries

    # Find systemd-boot EFI binary
    local systemd_boot
    systemd_boot=$(find -L "$system_path" -name "systemd-bootx64.efi" 2>/dev/null | head -1)
    if [[ -z "$systemd_boot" ]]; then
        # Look in the nix store directly
        systemd_boot=$(find /nix/store -maxdepth 2 -path "*systemd-*/lib/systemd/boot/efi/systemd-bootx64.efi" 2>/dev/null | head -1)
    fi

    if [[ -n "$systemd_boot" ]]; then
        mcopy -i "$WORK_DIR/esp.img" "$systemd_boot" ::EFI/BOOT/BOOTX64.EFI
        mcopy -i "$WORK_DIR/esp.img" "$systemd_boot" ::EFI/systemd/systemd-bootx64.efi
    else
        error "Could not find systemd-boot EFI binary"
    fi

    # Kernel and initrd are directly linked from the system path
    local kernel="$system_path/kernel"
    local initrd="$system_path/initrd"

    if [[ ! -e "$kernel" ]]; then
        error "Could not find kernel at $kernel"
    fi
    if [[ ! -e "$initrd" ]]; then
        error "Could not find initrd at $initrd"
    fi

    log "Copying kernel and initrd to ESP..."
    mcopy -i "$WORK_DIR/esp.img" "$kernel" ::EFI/nixos/kernel
    mcopy -i "$WORK_DIR/esp.img" "$initrd" ::EFI/nixos/initrd

    # Create loader.conf
    cat > "$WORK_DIR/loader.conf" << 'EOF'
timeout 3
default clix
editor no
EOF
    mcopy -i "$WORK_DIR/esp.img" "$WORK_DIR/loader.conf" ::loader/loader.conf
    rm "$WORK_DIR/loader.conf"

    # Create boot entry
    cat > "$WORK_DIR/clix.conf" << EOF
title CLIX
linux /EFI/nixos/kernel
initrd /EFI/nixos/initrd
options init=${system_path}/init root=LABEL=CLIX-ROOT rootwait rw
EOF
    mcopy -i "$WORK_DIR/esp.img" "$WORK_DIR/clix.conf" ::loader/entries/clix.conf
    rm "$WORK_DIR/clix.conf"

    # Debug boot entry - enables systemd debug shell on tty9 (Ctrl+Alt+F9)
    cat > "$WORK_DIR/clix-debug.conf" << EOF
title CLIX (Debug - tty9 shell)
linux /EFI/nixos/kernel
initrd /EFI/nixos/initrd
options init=${system_path}/init root=LABEL=CLIX-ROOT rootwait rw systemd.debug_shell=1
EOF
    mcopy -i "$WORK_DIR/esp.img" "$WORK_DIR/clix-debug.conf" ::loader/entries/clix-debug.conf
    rm "$WORK_DIR/clix-debug.conf"
}

# Populate root filesystem
populate_root() {
    log "Populating root filesystem..."

    local system_path
    system_path=$(readlink -f "${OUTPUT_DIR}/system")
    local root_dir="$WORK_DIR/root"

    # Create directory structure
    mkdir -p "$root_dir"/{nix/store,nix/var/nix/profiles,etc,run,home,boot,tmp,var}

    # Copy the nix store closure
    log "Copying NixOS store (this may take a while)..."
    nix copy --to "local?root=$root_dir" "$system_path" --no-check-sigs

    # Create system profile
    ln -sf "$system_path" "$root_dir/nix/var/nix/profiles/system"

    # Create required symlinks and directories
    ln -sf /run "$root_dir/var/run"
    mkdir -p "$root_dir/etc/nixos"
    mkdir -p "$root_dir/etc/clix"

    # Create home directories for users (PAM needs these to exist)
    mkdir -p "$root_dir/home/setup"
    mkdir -p "$root_dir/root"

    log "Creating root filesystem image (${ROOT_SIZE_MB}MB)..."
    # Use mke2fs with -d to create and populate in one step
    mkfs.ext4 -L CLIX-ROOT -d "$root_dir" "$WORK_DIR/root.img" "${ROOT_SIZE_MB}M"
}

# Assemble final image
assemble_image() {
    log "Assembling final disk image..."

    # Partition order: CLIX-PUBLIC first (so Windows mounts it by default), then ESP, then ROOT
    local sector_size=512
    local data_start_mb=1
    local data_end_mb=$((data_start_mb + DATA_SIZE_MB))
    local esp_start_mb=$data_end_mb
    local esp_end_mb=$((esp_start_mb + ESP_SIZE_MB))
    local root_start_mb=$esp_end_mb
    local root_end_mb=$((root_start_mb + ROOT_SIZE_MB))

    # Create the final image
    truncate -s "${TOTAL_SIZE_MB}M" "${OUTPUT_DIR}/${IMAGE_NAME}"

    # Create GPT partition table
    log "Creating partition table..."
    parted -s "${OUTPUT_DIR}/${IMAGE_NAME}" mklabel gpt
    parted -s "${OUTPUT_DIR}/${IMAGE_NAME}" mkpart CLIX-PUBLIC fat32 "${data_start_mb}MiB" "${data_end_mb}MiB"
    parted -s "${OUTPUT_DIR}/${IMAGE_NAME}" mkpart ESP fat32 "${esp_start_mb}MiB" "${esp_end_mb}MiB"
    parted -s "${OUTPUT_DIR}/${IMAGE_NAME}" set 2 esp on
    parted -s "${OUTPUT_DIR}/${IMAGE_NAME}" mkpart CLIX-ROOT ext4 "${root_start_mb}MiB" "${root_end_mb}MiB"

    log "Writing partition images..."
    # Write CLIX-PUBLIC (partition 1)
    dd if="$WORK_DIR/data.img" of="${OUTPUT_DIR}/${IMAGE_NAME}" bs=1M seek=$data_start_mb conv=notrunc status=none

    # Write ESP (partition 2)
    dd if="$WORK_DIR/esp.img" of="${OUTPUT_DIR}/${IMAGE_NAME}" bs=1M seek=$esp_start_mb conv=notrunc status=none

    # Write CLIX-ROOT (partition 3)
    dd if="$WORK_DIR/root.img" of="${OUTPUT_DIR}/${IMAGE_NAME}" bs=1M seek=$root_start_mb conv=notrunc status=none

    log "Partition table:"
    parted -s "${OUTPUT_DIR}/${IMAGE_NAME}" print
}

# Cleanup
cleanup() {
    if [[ -d "$WORK_DIR" ]]; then
        log "Cleaning up work directory..."
        rm -rf "$WORK_DIR"
    fi
}

# Main
main() {
    log "CLIX Image Builder"
    log "=================="

    # Clean up any stale work directory from failed previous builds
    if [[ -d "$WORK_DIR" ]]; then
        log "Cleaning stale work directory..."
        rm -rf "$WORK_DIR" || {
            error "Cannot clean work directory. Please run: sudo rm -rf $WORK_DIR"
        }
    fi

    check_requirements
    build_system
    create_partition_images
    populate_data_partition
    populate_esp
    populate_root
    assemble_image
    cleanup

    log "Image built successfully: ${OUTPUT_DIR}/${IMAGE_NAME}"
    log "Size: $(du -h "${OUTPUT_DIR}/${IMAGE_NAME}" | cut -f1)"
    log ""
    log "To write to USB (Linux):"
    log "  sudo dd if=${OUTPUT_DIR}/${IMAGE_NAME} of=/dev/sdX bs=4M status=progress"
    log ""
    log "Or use Win32DiskImager / Rufus / balenaEtcher on Windows/Mac"
}

main "$@"
