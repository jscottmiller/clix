#!/usr/bin/env bash
# Build CLIX image using Docker
# This avoids needing Nix or root on the host system

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${PROJECT_DIR}/result"

echo "=== CLIX Docker Build ==="
echo "Project: $PROJECT_DIR"
echo "Output:  $OUTPUT_DIR"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Run build in Docker container
docker run --rm \
    -v "$PROJECT_DIR:/build:ro" \
    -v "$OUTPUT_DIR:/output" \
    -v "clix-nix-cache:/nix" \
    -w /build \
    nixos/nix:latest \
    bash -c '
        set -euo pipefail

        echo "=== Setting up Nix ==="
        mkdir -p /etc/nix
        echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf

        echo "=== Installing build tools ==="
        nix-env -iA nixpkgs.parted nixpkgs.mtools nixpkgs.dosfstools nixpkgs.e2fsprogs nixpkgs.util-linux nixpkgs.gptfdisk

        echo "=== Building NixOS system ==="
        # Copy source to writable location (needed for nix build)
        cp -r /build /tmp/clix
        cd /tmp/clix

        # Initialize git repo (required for flake)
        git init
        git add -A

        # Build the system
        nix build .#nixosConfigurations.clix.config.system.build.toplevel --out-link result/system

        echo "=== Assembling image ==="
        ./scripts/build-image.sh

        echo "=== Copying output ==="
        cp result/clix.img /output/

        echo ""
        echo "=== Build complete ==="
        ls -lh /output/clix.img
    '

echo ""
echo "Image available at: $OUTPUT_DIR/clix.img"
