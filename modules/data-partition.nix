{ config, pkgs, lib, ... }:

# This module handles the CLIX-DATA partition:
# - Mounts it on boot (if it exists)
# - Imports WiFi credentials to NetworkManager
# - Imports Claude credentials to user home
# Note: CLIX-DATA is created by first-boot-setup.nix wizard
# On first boot before setup, this service simply exits gracefully

let
  importScript = pkgs.writeShellScript "clix-import-data" ''
    export PATH="${pkgs.util-linux}/bin:${pkgs.coreutils}/bin:${pkgs.iw}/bin:$PATH"
    set -e
    DATA_MOUNT="/mnt/clix-data"

    echo "CLIX: Looking for data partition..."

    # Find CLIX-DATA partition by label
    # This partition is created by the first-boot wizard
    DATA_DEV=$(blkid -L CLIX-DATA 2>/dev/null || true)

    if [ -z "$DATA_DEV" ]; then
      echo "CLIX: CLIX-DATA partition not found (first boot?), skipping import"
      exit 0
    fi

    # Verify the partition exists
    if [ ! -b "$DATA_DEV" ]; then
      echo "CLIX: Data partition $DATA_DEV not a block device, skipping import"
      exit 0
    fi

    echo "CLIX: Found data partition at $DATA_DEV"

    # Mount the data partition
    mkdir -p "$DATA_MOUNT"
    mount -o ro "$DATA_DEV" "$DATA_MOUNT"

    # Set wireless regulatory domain (must happen before NetworkManager)
    if [ -f "$DATA_MOUNT/network/regdomain" ]; then
      REGDOMAIN=$(cat "$DATA_MOUNT/network/regdomain" | tr -d '[:space:]')
      if [ -n "$REGDOMAIN" ]; then
        echo "CLIX: Setting wireless regulatory domain to $REGDOMAIN"
        iw reg set "$REGDOMAIN" || echo "CLIX: Warning - failed to set regdomain"
      fi
    fi

    # Import NetworkManager connections
    if [ -d "$DATA_MOUNT/network" ]; then
      echo "CLIX: Importing network configurations..."
      for conn in "$DATA_MOUNT/network"/*.nmconnection; do
        if [ -f "$conn" ]; then
          name=$(basename "$conn")
          echo "CLIX: Importing network config: $name"
          cp "$conn" /etc/NetworkManager/system-connections/
          chmod 600 /etc/NetworkManager/system-connections/"$name"
        fi
      done
      # Reload NetworkManager to pick up new connections
      nmcli connection reload 2>/dev/null || true
    fi

    # Import Claude credentials (using cp -rT to include dotfiles)
    if [ -d "$DATA_MOUNT/claude" ] && [ -n "$(ls -A "$DATA_MOUNT/claude" 2>/dev/null)" ]; then
      echo "CLIX: Importing Claude credentials..."
      mkdir -p /home/clix/.claude
      cp -rT "$DATA_MOUNT/claude" /home/clix/.claude/
      chown -R clix:users /home/clix/.claude
      chmod 700 /home/clix/.claude
      find /home/clix/.claude -type f -exec chmod 600 {} \;
    fi

    # Unmount
    umount "$DATA_MOUNT"
    rmdir "$DATA_MOUNT"

    echo "CLIX: Data import complete"
  '';
in
{
  # Run import script early in boot (after /home is mounted, if available)
  systemd.services.clix-import-data = {
    description = "Import CLIX data from data partition";
    wantedBy = [ "multi-user.target" ];
    before = [ "network-online.target" "display-manager.service" ];
    # Wait for /home mount attempt (may not exist on first boot)
    after = [ "local-fs.target" "clix-mount-home.service" ];
    wants = [ "clix-mount-home.service" ];  # soft dependency - don't fail if missing
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${importScript}";
      RemainAfterExit = true;
    };
  };

  # Make sure NetworkManager waits for our import
  systemd.services.NetworkManager = {
    after = [ "clix-import-data.service" ];
  };

  # Ensure blkid is available
  environment.systemPackages = with pkgs; [
    util-linux  # for blkid
  ];
}
