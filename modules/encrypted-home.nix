{ config, pkgs, lib, ... }:

# This module handles the CLIX-HOME partition:
# - On first boot: partition doesn't exist yet (first-boot-setup.nix creates it)
# - After setup: mounts /home from CLIX-HOME (encrypted or plain)
# - Supports both LUKS encrypted and unencrypted states

let
  # Script to mount /home if CLIX-HOME partition exists
  mountHomeScript = pkgs.writeShellScript "clix-mount-home" ''
    set -e
    export PATH="${lib.makeBinPath (with pkgs; [ util-linux cryptsetup coreutils ])}:$PATH"

    MOUNT_POINT="/home"

    # Check if already mounted
    if mountpoint -q "$MOUNT_POINT"; then
      echo "/home already mounted"
      exit 0
    fi

    # Try to find CLIX-HOME partition by label
    # It might be CLIX-HOME (unencrypted) or the underlying device for encrypted
    HOME_PART=$(blkid -L CLIX-HOME 2>/dev/null || true)

    # If not found, check if we have an encrypted home (CLIX-HOME-FS inside LUKS)
    if [ -z "$HOME_PART" ]; then
      # Look for any partition that might be LUKS-encrypted CLIX-HOME
      # by checking for CLIX-HOME-FS label on mapper devices
      if [ -b "/dev/mapper/clix-home" ]; then
        echo "LUKS container already open, mounting..."
        mount /dev/mapper/clix-home "$MOUNT_POINT"
        exit 0
      fi

      # No CLIX-HOME partition found - first boot, wizard will create it
      echo "CLIX-HOME partition not found - waiting for first-boot setup"
      exit 0
    fi

    # Check if it's a LUKS container
    if cryptsetup isLuks "$HOME_PART" 2>/dev/null; then
      echo "CLIX-HOME is encrypted, opening LUKS container..."

      # Check if already unlocked
      if [ ! -b "/dev/mapper/clix-home" ]; then
        # Prompt for password via systemd-ask-password
        ${pkgs.systemd}/bin/systemd-ask-password --timeout=0 "Enter passphrase for CLIX-HOME:" | \
          cryptsetup open "$HOME_PART" clix-home -
      fi

      mount "/dev/mapper/clix-home" "$MOUNT_POINT"
      echo "Mounted encrypted /home"
    else
      echo "CLIX-HOME is not encrypted, mounting directly..."
      mount "$HOME_PART" "$MOUNT_POINT"
      echo "Mounted unencrypted /home"
    fi

    # Ensure clix user home exists with correct permissions
    if [ ! -d "$MOUNT_POINT/clix" ]; then
      mkdir -p "$MOUNT_POINT/clix"
    fi
    chown 1000:100 "$MOUNT_POINT/clix"
    chmod 700 "$MOUNT_POINT/clix"
  '';

  # Script to unmount /home cleanly
  unmountHomeScript = pkgs.writeShellScript "clix-unmount-home" ''
    export PATH="${lib.makeBinPath (with pkgs; [ util-linux cryptsetup ])}:$PATH"

    MAPPER_NAME="clix-home"
    MOUNT_POINT="/home"

    if mountpoint -q "$MOUNT_POINT"; then
      umount "$MOUNT_POINT"
    fi

    if [ -b "/dev/mapper/$MAPPER_NAME" ]; then
      cryptsetup close "$MAPPER_NAME"
    fi
  '';
in
{
  # LUKS support in initrd for early boot
  boot.initrd = {
    availableKernelModules = [
      "dm_crypt"
      "dm_mod"
      "cryptd"
      "aes"
      "aes_generic"
      "xts"
      "sha256"
      "sha512"
    ];
    kernelModules = [ "dm_crypt" ];
  };

  # Cryptsetup available in system
  environment.systemPackages = with pkgs; [
    cryptsetup
  ];

  # Systemd service to mount /home (handles LUKS, plain ext4, or missing partition)
  systemd.services.clix-mount-home = {
    description = "Mount CLIX-HOME partition";
    wantedBy = [ "local-fs.target" ];
    before = [ "local-fs.target" ];
    after = [ "systemd-udev-settle.service" ];

    unitConfig = {
      DefaultDependencies = false;
    };

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${mountHomeScript}";
      ExecStop = "${unmountHomeScript}";
      StandardInput = "tty";
      StandardOutput = "tty";
      TTYPath = "/dev/console";
      TTYReset = true;
    };
  };

  # Ensure display manager waits for /home mount attempt
  systemd.services.greetd = lib.mkIf config.services.greetd.enable {
    after = [ "clix-mount-home.service" ];
    wants = [ "clix-mount-home.service" ];
  };
}
