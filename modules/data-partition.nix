{ config, pkgs, lib, ... }:

# This module handles the CLIX-PUBLIC partition:
# - CLIX-PUBLIC is baked into the image (always exists)
# - Mounted persistently at /mnt/public
# - On each boot, imports WiFi credentials to NetworkManager
# - Claude credentials are handled separately in first-boot-setup.nix
#   (after encrypted home is unlocked)

let
  importScript = pkgs.writeShellScript "clix-import-data" ''
    export PATH="${lib.makeBinPath (with pkgs; [ util-linux coreutils iw networkmanager ])}:$PATH"
    set -e
    DATA_MOUNT="/mnt/public"

    echo "CLIX: Looking for public partition..."

    # Wait for mount (handled by systemd, but may take a moment)
    if ! mountpoint -q "$DATA_MOUNT" 2>/dev/null; then
      echo "CLIX: Waiting for CLIX-PUBLIC mount..."
      sleep 2
      if ! mountpoint -q "$DATA_MOUNT" 2>/dev/null; then
        echo "CLIX: CLIX-PUBLIC not mounted at $DATA_MOUNT"
        exit 0
      fi
    fi

    echo "CLIX: CLIX-PUBLIC mounted at $DATA_MOUNT"

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

    # NOTE: Claude credentials are imported by autostartScript in first-boot-setup.nix
    # after the encrypted home partition is unlocked.

    echo "CLIX: Data import complete"
  '';
in
{
  # Mount CLIX-PUBLIC persistently at /mnt/public
  fileSystems."/mnt/public" = {
    device = "/dev/disk/by-label/CLIX-PUBLIC";
    fsType = "vfat";
    options = [
      "nofail"           # Don't fail boot if not present
      "x-systemd.device-timeout=5"  # Don't wait too long
      "uid=1000"         # Owner is first user (clix)
      "gid=100"          # Group is users
      "umask=002"        # rwxrwxr-x permissions
    ];
  };

  # Run import script early in boot
  systemd.services.clix-import-data = {
    description = "Import CLIX data from data partition";
    wantedBy = [ "multi-user.target" ];
    before = [ "network-online.target" "display-manager.service" "NetworkManager.service" ];
    after = [ "local-fs.target" "mnt-public.mount" ];

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
