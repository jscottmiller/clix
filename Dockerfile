# CLIX Builder Image
#
# Build the image:
#   docker build -t clix-builder .
#
# Build CLIX (mounts source, outputs to ./result):
#   docker run --rm -v $(pwd):/build -v $(pwd)/result:/output -w /build clix-builder
#
# Interactive shell:
#   docker run --rm -it -v $(pwd):/build -w /build clix-builder bash

FROM nixos/nix:latest

# Enable flakes
RUN mkdir -p /etc/nix && \
    echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf

# Install build dependencies
RUN nix-env -iA \
    nixpkgs.parted \
    nixpkgs.mtools \
    nixpkgs.dosfstools \
    nixpkgs.e2fsprogs \
    nixpkgs.util-linux \
    nixpkgs.gptfdisk \
    nixpkgs.bash

WORKDIR /build

# Default command: build the image
CMD ["bash", "-c", "\
    echo '=== Building NixOS system ===' && \
    nix build .#nixosConfigurations.clix-live.config.system.build.toplevel --out-link result/system && \
    echo '=== Assembling image ===' && \
    ./scripts/build-image.sh && \
    if [ -d /output ]; then \
        cp result/clix.img /output/ && \
        echo '=== Done: /output/clix.img ===' && \
        ls -lh /output/clix.img; \
    else \
        echo '=== Done: result/clix.img ===' && \
        ls -lh result/clix.img; \
    fi \
"]
