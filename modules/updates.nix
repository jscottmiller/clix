{ config, pkgs, lib, ... }:

# CLIX Update Module
# Provides clix-update and clix-apply commands for manual updates from GitHub releases

let
  # Version string - this gets stamped at build time
  # The first release should tag as v1.0.0
  clixVersion = "v1.0.0";

  updateDeps = with pkgs; [
    coreutils
    curl
    jq
    gnutar
    gzip
    diffutils
    gnused
  ];

  # Check for updates from GitHub releases
  clixUpdateScript = pkgs.writeShellScriptBin "clix-update" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath updateDeps}:$PATH"

    CLIX_DIR="/var/lib/clix"
    VERSION_FILE="$CLIX_DIR/version"
    REPO="jscottmiller/clix"

    # Ensure clix directory exists
    if [ ! -d "$CLIX_DIR" ]; then
      echo "Error: $CLIX_DIR does not exist. Is CLIX properly installed?"
      exit 1
    fi

    # Get current version
    current=""
    if [ -f "$VERSION_FILE" ]; then
      current=$(cat "$VERSION_FILE")
    else
      current="unknown"
    fi

    echo "Current version: $current"
    echo ""
    echo "Checking for updates..."

    # Check latest release via GitHub API
    api_response=$(curl -s "https://api.github.com/repos/$REPO/releases/latest")

    # Check for API errors
    if echo "$api_response" | jq -e '.message' >/dev/null 2>&1; then
      message=$(echo "$api_response" | jq -r '.message')
      echo "GitHub API error: $message"
      exit 1
    fi

    latest=$(echo "$api_response" | jq -r '.tag_name')

    if [ -z "$latest" ] || [ "$latest" = "null" ]; then
      echo "No releases found for $REPO"
      echo ""
      echo "If this is a fresh install, the first release hasn't been published yet."
      exit 0
    fi

    if [ "$current" = "$latest" ]; then
      echo ""
      echo "CLIX is up to date ($current)"
      exit 0
    fi

    echo ""
    echo "Update available: $current -> $latest"
    echo ""
    echo "Downloading release..."

    # Download and extract to temp location
    tmpdir=$(mktemp -d)
    trap "rm -rf $tmpdir" EXIT

    tarball_url="https://github.com/$REPO/archive/refs/tags/$latest.tar.gz"

    if ! curl -sL "$tarball_url" | tar xz -C "$tmpdir"; then
      echo "Error: Failed to download release tarball"
      exit 1
    fi

    # The extracted directory name removes the 'v' prefix from tag
    extracted_dir="$tmpdir/clix-''${latest#v}"

    if [ ! -d "$extracted_dir" ]; then
      echo "Error: Expected directory $extracted_dir not found"
      ls -la "$tmpdir"
      exit 1
    fi

    echo ""
    echo "=== Changes in $latest ==="
    echo ""

    # Show diff between current repo and new version
    if [ -d "$CLIX_DIR/repo" ]; then
      # Compare directories, showing changed files
      diff -rq "$CLIX_DIR/repo" "$extracted_dir" 2>/dev/null | head -50 || true
      echo ""

      # Show detailed diff for .nix files (the important stuff)
      for f in $(find "$extracted_dir" -name "*.nix" -type f); do
        rel_path="''${f#$extracted_dir/}"
        old_file="$CLIX_DIR/repo/$rel_path"
        if [ -f "$old_file" ]; then
          if ! diff -q "$old_file" "$f" >/dev/null 2>&1; then
            echo "--- $rel_path ---"
            diff -u "$old_file" "$f" | head -30 || true
            echo ""
          fi
        else
          echo "+++ NEW: $rel_path"
        fi
      done
    else
      echo "No existing repo to compare (first update)"
    fi

    echo ""
    echo "==========================================="
    echo ""
    echo "Review the changes above."
    echo "Run 'clix-apply' to install this update."
    echo ""

    # Stage the update
    rm -rf "$CLIX_DIR/staging"
    mv "$extracted_dir" "$CLIX_DIR/staging"
    echo "$latest" > "$CLIX_DIR/staging-version"

    # Keep tmpdir cleanup from removing staging
    trap - EXIT
    rm -rf "$tmpdir"

    echo "Update staged. Run 'clix-apply' when ready."
  '';

  # Apply a staged update
  clixApplyScript = pkgs.writeShellScriptBin "clix-apply" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath updateDeps}:$PATH"

    CLIX_DIR="/var/lib/clix"

    if [ ! -d "$CLIX_DIR/staging" ]; then
      echo "No staged update found."
      echo "Run 'clix-update' first to check for updates."
      exit 1
    fi

    if [ ! -f "$CLIX_DIR/staging-version" ]; then
      echo "Error: staging-version file missing"
      exit 1
    fi

    version=$(cat "$CLIX_DIR/staging-version")
    echo "Applying CLIX $version..."
    echo ""

    # Backup current repo (if exists)
    if [ -d "$CLIX_DIR/repo" ]; then
      rm -rf "$CLIX_DIR/repo.bak"
      mv "$CLIX_DIR/repo" "$CLIX_DIR/repo.bak"
    fi

    # Install staging as new repo
    mv "$CLIX_DIR/staging" "$CLIX_DIR/repo"

    # The rebuild flake is at config/nixos/ - it imports user's configuration.nix
    REBUILD_FLAKE="$CLIX_DIR/repo/config/nixos"

    # Preserve user's configuration.nix
    if [ -f /etc/nixos/configuration.nix ]; then
      cp /etc/nixos/configuration.nix "$REBUILD_FLAKE/configuration.nix"
    fi

    # Copy the lock file from current system to ensure reproducibility
    if [ -f /etc/nixos/flake.lock ]; then
      cp /etc/nixos/flake.lock "$REBUILD_FLAKE/flake.lock"
    fi

    echo "Running nixos-rebuild switch..."
    echo ""

    if nixos-rebuild switch --flake "$REBUILD_FLAKE#clix"; then
      echo ""
      echo "$version" > "$CLIX_DIR/version"
      rm -rf "$CLIX_DIR/repo.bak" "$CLIX_DIR/staging-version"
      echo "Update complete! Now running CLIX $version"
      echo ""
      echo "Note: A reboot is recommended to ensure all changes take effect."
    else
      echo ""
      echo "Rebuild failed. Rolling back..."
      rm -rf "$CLIX_DIR/repo"
      if [ -d "$CLIX_DIR/repo.bak" ]; then
        mv "$CLIX_DIR/repo.bak" "$CLIX_DIR/repo"
      fi
      rm -f "$CLIX_DIR/staging-version"
      echo "Rollback complete. Previous version restored."
      exit 1
    fi
  '';

  # Show current version
  clixVersionScript = pkgs.writeShellScriptBin "clix-version" ''
    VERSION_FILE="/var/lib/clix/version"
    BUILD_VERSION="${clixVersion}"

    if [ -f "$VERSION_FILE" ]; then
      echo "CLIX $(cat "$VERSION_FILE")"
    else
      echo "CLIX $BUILD_VERSION (not yet updated)"
    fi
  '';

in
{
  environment.systemPackages = [
    clixUpdateScript
    clixApplyScript
    clixVersionScript
    pkgs.curl
    pkgs.jq
  ];

  # Create /var/lib/clix directory with proper permissions
  systemd.tmpfiles.rules = [
    "d /var/lib/clix 0755 root root -"
  ];

  # Initialize version file on first boot if not present
  system.activationScripts.initClixVersion = ''
    if [ ! -f /var/lib/clix/version ]; then
      mkdir -p /var/lib/clix
      echo "${clixVersion}" > /var/lib/clix/version
    fi
  '';

  # Store build-time version in /etc for reference
  environment.etc."clix-version".text = clixVersion;
}
