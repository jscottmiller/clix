{ config, pkgs, lib, ... }:

# This module handles the CLIX-DATA partition:
# - Mounts it on boot
# - Imports WiFi credentials to NetworkManager
# - Imports Claude credentials to user home

let
  importScript = pkgs.writeShellScript "clix-import-data" ''
    export PATH="${pkgs.util-linux}/bin:${pkgs.coreutils}/bin:${pkgs.iw}/bin:$PATH"
    set -e
    DATA_MOUNT="/mnt/clix-data"

    echo "CLIX: Looking for data partition..."

    # Find the data partition by looking at the boot device
    # Layout: partition 1 = CLIX-DATA, partition 2 = EFI, partition 3 = root
    # This is more reliable than blkid label lookup during early boot

    # Get the root device and strip partition number to find base device
    ROOT_DEV=$(findmnt -n -o SOURCE /)
    echo "CLIX: Root device is $ROOT_DEV"

    # Handle both /dev/sdX3 and /dev/nvme0n1p3 style names
    if [[ "$ROOT_DEV" =~ ^/dev/nvme ]]; then
      BASE_DEV=$(echo "$ROOT_DEV" | sed 's/p[0-9]*$//')
      DATA_DEV="''${BASE_DEV}p1"
    elif [[ "$ROOT_DEV" =~ ^/dev/sd ]]; then
      BASE_DEV=$(echo "$ROOT_DEV" | sed 's/[0-9]*$//')
      DATA_DEV="''${BASE_DEV}1"
    else
      echo "CLIX: Unknown device naming scheme for $ROOT_DEV, trying blkid fallback..."
      DATA_DEV=$(blkid -L CLIX-DATA 2>/dev/null || true)
    fi

    echo "CLIX: Looking for data partition at $DATA_DEV"

    # Verify the partition exists and is FAT
    if [ ! -b "$DATA_DEV" ]; then
      echo "CLIX: Data partition $DATA_DEV not found, skipping import"
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
  # Run import script early in boot
  systemd.services.clix-import-data = {
    description = "Import CLIX data from data partition";
    wantedBy = [ "multi-user.target" ];
    before = [ "network-online.target" "display-manager.service" ];
    after = [ "local-fs.target" ];
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
