{ config, pkgs, lib, ... }:

# This module handles the CLIX-PUBLIC partition:
# - CLIX-PUBLIC is baked into the image (always exists)
# - On each boot, imports WiFi credentials to NetworkManager
# - After setup, imports Claude credentials to user home

let
  importScript = pkgs.writeShellScript "clix-import-data" ''
    export PATH="${lib.makeBinPath (with pkgs; [ util-linux coreutils iw networkmanager ])}:$PATH"
    set -e
    DATA_MOUNT="/mnt/clix-public"

    echo "CLIX: Looking for public partition..."

    # Find CLIX-PUBLIC partition by label
    DATA_DEV=$(blkid -L CLIX-PUBLIC 2>/dev/null || true)

    if [ -z "$DATA_DEV" ]; then
      echo "CLIX: CLIX-PUBLIC partition not found"
      exit 0
    fi

    if [ ! -b "$DATA_DEV" ]; then
      echo "CLIX: Data partition $DATA_DEV not a block device"
      exit 0
    fi

    echo "CLIX: Found data partition at $DATA_DEV"

    # Mount the data partition (read-only)
    mkdir -p "$DATA_MOUNT"
    if ! mount -o ro "$DATA_DEV" "$DATA_MOUNT"; then
      echo "CLIX: Failed to mount data partition"
      rmdir "$DATA_MOUNT" 2>/dev/null || true
      exit 0
    fi

    # Set wireless regulatory domain (must happen before NetworkManager)
    if [ -f "$DATA_MOUNT/clix/network/regdomain" ]; then
      REGDOMAIN=$(cat "$DATA_MOUNT/clix/network/regdomain" | tr -d '[:space:]')
      if [ -n "$REGDOMAIN" ]; then
        echo "CLIX: Setting wireless regulatory domain to $REGDOMAIN"
        iw reg set "$REGDOMAIN" || echo "CLIX: Warning - failed to set regdomain"
      fi
    fi

    # Import NetworkManager connections
    if [ -d "$DATA_MOUNT/clix/network" ]; then
      echo "CLIX: Checking for network configurations..."
      mkdir -p /etc/NetworkManager/system-connections
      for conn in "$DATA_MOUNT/clix/network"/*.nmconnection; do
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

    # Import Claude credentials if user is set up
    if [ -f /etc/clix/user ] && [ -f /etc/clix/.setup-complete ]; then
      USERNAME=$(cat /etc/clix/user)
      USER_HOME="/home/$USERNAME"

      if [ -d "$DATA_MOUNT/clix/claude" ] && [ -n "$(ls -A "$DATA_MOUNT/clix/claude" 2>/dev/null)" ]; then
        echo "CLIX: Importing Claude credentials for $USERNAME..."
        mkdir -p "$USER_HOME/.claude"
        cp -rT "$DATA_MOUNT/clix/claude" "$USER_HOME/.claude/"
        chown -R "$USERNAME:users" "$USER_HOME/.claude"
        chmod 700 "$USER_HOME/.claude"
        find "$USER_HOME/.claude" -type f -exec chmod 600 {} \;
      fi
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
    before = [ "network-online.target" "display-manager.service" "NetworkManager.service" ];
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

  # Ensure required tools are available
  environment.systemPackages = with pkgs; [
    util-linux  # for blkid
  ];
}
