{ config, pkgs, lib, ... }:

# This module handles the encrypted /home partition:
# - On first boot: partition doesn't exist yet (first-boot-setup.nix creates it)
# - After setup: prompts for password, unlocks LUKS, mounts /home
# - Runs before display manager so autologin works after unlock

let
  # Script to unlock and mount encrypted /home
  mountHomeScript = pkgs.writeShellScript "clix-mount-home" ''
    set -e
    export PATH="${lib.makeBinPath (with pkgs; [ util-linux cryptsetup coreutils systemd ])}:$PATH"

    MOUNT_POINT="/home"
    MAPPER_NAME="clix-home"

    # Check if already mounted
    if mountpoint -q "$MOUNT_POINT"; then
      echo "/home already mounted"
      exit 0
    fi

    # Check if setup has been completed
    if [ ! -f /etc/clix/.setup-complete ]; then
      echo "CLIX setup not complete - /home will not be mounted"
      echo "First-boot wizard will run after graphical session starts"
      exit 0
    fi

    # Get the home partition device
    if [ ! -f /etc/clix/home-device ]; then
      echo "ERROR: /etc/clix/home-device not found"
      echo "Setup may be incomplete - try running clix-setup"
      exit 1
    fi

    HOME_DEV=$(cat /etc/clix/home-device)

    if [ ! -b "$HOME_DEV" ]; then
      echo "ERROR: Home device $HOME_DEV does not exist"
      exit 1
    fi

    echo "CLIX: Unlocking encrypted home partition..."

    # Check if LUKS container is already open
    if [ ! -b "/dev/mapper/$MAPPER_NAME" ]; then
      # Prompt for password
      # Use systemd-ask-password which integrates with plymouth if available
      PASSWORD=$(systemd-ask-password --timeout=0 --id=clix-home "Enter passphrase to unlock your data:")

      if [ -z "$PASSWORD" ]; then
        echo "ERROR: No password provided"
        exit 1
      fi

      # Try to open the LUKS container
      if ! echo "$PASSWORD" | cryptsetup open "$HOME_DEV" "$MAPPER_NAME" -; then
        echo "ERROR: Failed to unlock encrypted home"
        echo "Wrong password or corrupted LUKS header"
        exit 1
      fi

      # Clear password from memory
      unset PASSWORD
    fi

    # Mount the decrypted filesystem
    echo "CLIX: Mounting /home..."
    mount "/dev/mapper/$MAPPER_NAME" "$MOUNT_POINT"

    # Ensure user's home directory exists with correct permissions
    if [ -f /etc/clix/user ]; then
      USERNAME=$(cat /etc/clix/user)
      if [ -n "$USERNAME" ] && [ ! -d "$MOUNT_POINT/$USERNAME" ]; then
        mkdir -p "$MOUNT_POINT/$USERNAME"
        chown 1000:100 "$MOUNT_POINT/$USERNAME"
        chmod 700 "$MOUNT_POINT/$USERNAME"
      fi
    fi

    echo "CLIX: Encrypted home mounted successfully"
  '';

  # Script to unmount /home cleanly (for shutdown)
  unmountHomeScript = pkgs.writeShellScript "clix-unmount-home" ''
    export PATH="${lib.makeBinPath (with pkgs; [ util-linux cryptsetup ])}:$PATH"

    MAPPER_NAME="clix-home"
    MOUNT_POINT="/home"

    # Unmount if mounted
    if mountpoint -q "$MOUNT_POINT"; then
      echo "CLIX: Unmounting /home..."
      umount "$MOUNT_POINT" || umount -l "$MOUNT_POINT"
    fi

    # Close LUKS container if open
    if [ -b "/dev/mapper/$MAPPER_NAME" ]; then
      echo "CLIX: Closing encrypted volume..."
      cryptsetup close "$MAPPER_NAME"
    fi

    echo "CLIX: Encrypted home closed"
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

  # Systemd service to unlock and mount encrypted /home
  # Runs early in boot, before display manager
  systemd.services.clix-mount-home = {
    description = "Unlock and mount CLIX encrypted home";
    wantedBy = [ "local-fs.target" ];
    before = [ "local-fs.target" "display-manager.service" "greetd.service" ];
    after = [ "systemd-udev-settle.service" "systemd-ask-password-console.service" ];
    wants = [ "systemd-ask-password-console.service" ];

    unitConfig = {
      DefaultDependencies = false;
      # Only run if setup has been completed
      ConditionPathExists = "/etc/clix/.setup-complete";
    };

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${mountHomeScript}";
      ExecStop = "${unmountHomeScript}";
      # TTY access for password prompt
      StandardInput = "tty";
      StandardOutput = "tty";
      TTYPath = "/dev/console";
      TTYReset = true;
      TTYVHangup = true;
    };
  };

  # Ensure display manager waits for /home to be mounted
  systemd.services.greetd = lib.mkIf config.services.greetd.enable {
    after = [ "clix-mount-home.service" ];
    wants = [ "clix-mount-home.service" ];
  };

  # Clean unmount on shutdown
  systemd.services.clix-unmount-home-shutdown = {
    description = "Close CLIX encrypted home on shutdown";
    wantedBy = [ "shutdown.target" "reboot.target" ];
    before = [ "shutdown.target" "reboot.target" ];
    after = [ "final.target" ];

    unitConfig = {
      DefaultDependencies = false;
    };

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${unmountHomeScript}";
    };
  };
}
