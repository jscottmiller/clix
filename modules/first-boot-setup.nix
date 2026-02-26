{ config, pkgs, lib, ... }:

# First-boot setup wizard for CLIX
# On first boot (fresh install), this:
# 1. Collects username and password
# 2. Asks how to allocate free space (root expansion vs encrypted home)
# 3. Expands root partition
# 4. Creates encrypted home partition
# 5. Creates user account
# 6. Reboots into normal operation

let
  # Dependencies for the wizard
  wizardDeps = with pkgs; [
    coreutils
    util-linux
    parted
    cloud-utils  # for growpart
    e2fsprogs
    cryptsetup
    zenity
    gawk
    shadow  # for useradd, passwd
    gnused
  ];

  # Main first-boot wizard script
  # Runs from sway autostart via sudo, so display is already available
  firstBootWizard = pkgs.writeShellScript "clix-first-boot-wizard" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath wizardDeps}:$PATH"

    exec > >(tee -a /tmp/clix-first-boot.log) 2>&1
    echo "=== CLIX First Boot Wizard $(date) ==="

    # Check for marker file - don't run if setup already completed
    if [ -f /etc/clix/.setup-complete ]; then
      echo "Setup already completed."
      exit 0
    fi

    # Find the boot device (the USB drive we're running from)
    ROOT_DEV=$(findmnt -n -o SOURCE /)
    if [ -z "$ROOT_DEV" ]; then
      zenity --error --title="Error" --text="Could not determine root device." --width=300
      exit 1
    fi

    # Determine disk device from partition
    if [[ "$ROOT_DEV" =~ ^/dev/nvme ]]; then
      DISK=$(echo "$ROOT_DEV" | sed 's/p[0-9]*$//')
      ROOT_PART_NUM=$(echo "$ROOT_DEV" | sed 's/.*p//')
    else
      DISK=$(echo "$ROOT_DEV" | sed 's/[0-9]*$//')
      ROOT_PART_NUM=$(echo "$ROOT_DEV" | sed 's/[^0-9]*//g')
    fi

    echo "Boot device: $DISK, root partition: $ROOT_PART_NUM"

    # Fix GPT to use full disk (important when image is written to larger drive)
    echo "Checking GPT..."
    echo "Fix" | parted ---pretend-input-tty "$DISK" print 2>/dev/null || true
    partprobe "$DISK" 2>/dev/null || true
    sleep 1

    # Get disk size and calculate free space
    DISK_SIZE_BYTES=$(blockdev --getsize64 "$DISK")
    DISK_SIZE_GB=$((DISK_SIZE_BYTES / 1024 / 1024 / 1024))

    # Get end of root partition
    SECTOR_SIZE=$(blockdev --getss "$DISK")
    ROOT_END_SECTOR=$(parted -s "$DISK" unit s print | grep "^ *$ROOT_PART_NUM " | awk '{print $3}' | tr -d 's')

    # Calculate free space
    TOTAL_SECTORS=$((DISK_SIZE_BYTES / SECTOR_SIZE))
    FREE_SECTORS=$((TOTAL_SECTORS - ROOT_END_SECTOR - 2048))  # Leave space for GPT backup
    FREE_GB=$((FREE_SECTORS * SECTOR_SIZE / 1024 / 1024 / 1024))

    echo "Disk: ''${DISK_SIZE_GB}GB total, ''${FREE_GB}GB free after current partitions"

    if [ "$FREE_GB" -lt 1 ]; then
      zenity --error \
        --title="Insufficient Space" \
        --text="Not enough free space on the drive.\n\nFree space: ''${FREE_GB}GB\nRequired: at least 1GB\n\nPlease use a larger USB drive." \
        --width=400
      exit 1
    fi

    # ===== WELCOME SCREEN =====
    zenity --info \
      --title="Welcome to CLIX" \
      --text="Welcome to CLIX!\n\nThis wizard will set up your system:\n\n• Create your user account\n• Set up encrypted storage for your data\n• Configure the system for your use\n\nYour USB drive has ''${FREE_GB}GB of free space available." \
      --width=450

    # ===== USERNAME INPUT =====
    while true; do
      USERNAME=$(zenity --entry \
        --title="Create User Account" \
        --text="Choose a username:\n\n(lowercase letters, numbers, and underscores only)" \
        --entry-text="" \
        --width=400) || exit 1

      # Validate username
      if [ -z "$USERNAME" ]; then
        zenity --error --text="Username cannot be empty." --width=250
        continue
      fi

      if ! echo "$USERNAME" | grep -qE '^[a-z_][a-z0-9_-]*$'; then
        zenity --error --text="Invalid username.\n\nMust start with a letter or underscore,\nand contain only lowercase letters, numbers,\nunderscores, and hyphens." --width=350
        continue
      fi

      if [ ''${#USERNAME} -gt 32 ]; then
        zenity --error --text="Username too long (max 32 characters)." --width=250
        continue
      fi

      # Check if user already exists
      if getent passwd "$USERNAME" >/dev/null 2>&1; then
        zenity --error --text="Username '$USERNAME' already exists." --width=250
        continue
      fi

      break
    done

    echo "Username: $USERNAME"

    # ===== PASSWORD INPUT =====
    while true; do
      PASSWORD=$(zenity --password \
        --title="Set Password" \
        --text="Enter a password for $USERNAME:\n\n(This will also be used to encrypt your data)" \
        --width=400) || exit 1

      if [ -z "$PASSWORD" ]; then
        zenity --error --text="Password cannot be empty." --width=250
        continue
      fi

      if [ ''${#PASSWORD} -lt 8 ]; then
        zenity --error --text="Password must be at least 8 characters." --width=250
        continue
      fi

      PASSWORD2=$(zenity --password \
        --title="Confirm Password" \
        --text="Confirm your password:" \
        --width=400) || exit 1

      if [ "$PASSWORD" != "$PASSWORD2" ]; then
        zenity --error --text="Passwords do not match. Try again." --width=250
        continue
      fi

      break
    done

    # ===== STORAGE ALLOCATION =====
    # Leave at least 10GB for encrypted home
    MAX_ROOT_EXPAND=$((FREE_GB - 10))
    [ "$MAX_ROOT_EXPAND" -lt 0 ] && MAX_ROOT_EXPAND=0

    # Default: 16GB for root expansion, rest for home
    DEFAULT_ROOT_EXPAND=16
    [ "$DEFAULT_ROOT_EXPAND" -gt "$MAX_ROOT_EXPAND" ] && DEFAULT_ROOT_EXPAND=$MAX_ROOT_EXPAND

    ROOT_EXPAND_GB=$(zenity --scale \
      --title="Storage Allocation" \
      --text="Add space to system partition (for packages):\n\nCurrent: 8GB, Max addition: ''${MAX_ROOT_EXPAND}GB\nRemaining space goes to encrypted home." \
      --min-value=0 \
      --max-value=$MAX_ROOT_EXPAND \
      --value=$DEFAULT_ROOT_EXPAND \
      --width=450) || exit 1

    HOME_SIZE_GB=$((FREE_GB - ROOT_EXPAND_GB))

    echo "Root expansion: +''${ROOT_EXPAND_GB}GB (total: $((8 + ROOT_EXPAND_GB))GB), Home size: ''${HOME_SIZE_GB}GB"

    # ===== CONFIRMATION =====
    if ! zenity --question \
      --title="Confirm Setup" \
      --text="Ready to set up your system:\n\n• Username: $USERNAME\n• System partition: $((8 + ROOT_EXPAND_GB))GB (+''${ROOT_EXPAND_GB}GB)\n• Encrypted home: ''${HOME_SIZE_GB}GB\n\nThis will modify your USB drive.\nExisting system data will be preserved.\n\nProceed?" \
      --ok-label="Set Up System" \
      --cancel-label="Cancel" \
      --width=400; then
      exit 1
    fi

    # ===== EXECUTE SETUP =====
    (
      echo "5"
      echo "# Preparing..."
      mkdir -p /etc/clix

      echo "10"
      echo "# Expanding root partition..."

      if [ "$ROOT_EXPAND_GB" -gt 0 ]; then
        # Calculate target size for root partition in sectors
        EXPAND_SECTORS=$((ROOT_EXPAND_GB * 1024 * 1024 * 1024 / SECTOR_SIZE))
        NEW_ROOT_END=$((ROOT_END_SECTOR + EXPAND_SECTORS))

        echo "Expanding root from sector $ROOT_END_SECTOR to $NEW_ROOT_END"

        # Use parted to resize partition (growpart has issues)
        parted -s ---pretend-input-tty "$DISK" resizepart "$ROOT_PART_NUM" "''${NEW_ROOT_END}s" <<< "Yes" || {
          echo "Warning: Could not expand root partition, continuing..."
        }

        # Update ROOT_END_SECTOR for home partition calculation
        ROOT_END_SECTOR=$NEW_ROOT_END

        # Refresh kernel partition table
        partprobe "$DISK"
        sleep 2

        # Resize filesystem to fill partition
        echo "15"
        echo "# Resizing filesystem..."
        resize2fs "$ROOT_DEV" || echo "Warning: resize2fs had issues, continuing..."
      fi

      echo "20"
      echo "# Creating home partition..."

      # Home partition starts right after root, aligned to 1MB
      HOME_START_SECTOR=$(( ((ROOT_END_SECTOR + 2048) / 2048) * 2048 ))
      HOME_END_SECTOR=$((TOTAL_SECTORS - 2048))  # Leave space for GPT backup

      echo "Creating home partition from sector $HOME_START_SECTOR to $HOME_END_SECTOR"

      # Get next partition number
      LAST_PART_NUM=$(parted -s "$DISK" print | grep "^ [0-9]" | tail -1 | awk '{print $1}')
      HOME_PART_NUM=$((LAST_PART_NUM + 1))

      parted -s "$DISK" mkpart CLIX-HOME ext4 "''${HOME_START_SECTOR}s" "''${HOME_END_SECTOR}s"

      # Wait for partition device
      sleep 2
      partprobe "$DISK"
      sleep 2

      # Determine home partition device name
      if [[ "$DISK" =~ nvme ]]; then
        HOME_DEV="''${DISK}p''${HOME_PART_NUM}"
      else
        HOME_DEV="''${DISK}''${HOME_PART_NUM}"
      fi

      echo "Home device: $HOME_DEV"

      # Wait for device to appear
      for i in 1 2 3 4 5; do
        [ -b "$HOME_DEV" ] && break
        echo "Waiting for $HOME_DEV..."
        sleep 2
        partprobe "$DISK"
      done

      if [ ! -b "$HOME_DEV" ]; then
        echo "ERROR: $HOME_DEV does not exist!"
        exit 1
      fi

      echo "40"
      echo "# Setting up encryption..."

      # Format as LUKS (use printf to avoid echo issues with special chars)
      # Write password to temp file to avoid pipe issues
      PASS_FILE=$(mktemp)
      printf '%s' "$PASSWORD" > "$PASS_FILE"

      echo "Running cryptsetup luksFormat..."
      if ! cryptsetup luksFormat --type luks2 --pbkdf argon2id --key-file="$PASS_FILE" "$HOME_DEV" --batch-mode; then
        echo "ERROR: cryptsetup luksFormat failed!"
        rm -f "$PASS_FILE"
        exit 1
      fi

      echo "50"
      echo "# Opening encrypted volume..."
      if ! cryptsetup open --key-file="$PASS_FILE" "$HOME_DEV" clix-home; then
        echo "ERROR: cryptsetup open failed!"
        rm -f "$PASS_FILE"
        exit 1
      fi

      rm -f "$PASS_FILE"

      echo "60"
      echo "# Formatting home filesystem..."
      if ! mkfs.ext4 -L CLIX-HOME /dev/mapper/clix-home; then
        echo "ERROR: mkfs.ext4 failed!"
        exit 1
      fi

      echo "70"
      echo "# Mounting home..."
      if ! mount /dev/mapper/clix-home /home; then
        echo "ERROR: mount failed!"
        exit 1
      fi

      echo "75"
      echo "# Creating user account..."

      # Create the user with appropriate groups
      # Don't specify UID (setup user has 1000), use proper NixOS shell path
      useradd -m -G wheel,networkmanager,video,audio -s ${pkgs.bash}/bin/bash "$USERNAME"

      # Set password
      echo "$USERNAME:$PASSWORD" | chpasswd

      # Set up home directory permissions
      chmod 700 "/home/$USERNAME"

      echo "85"
      echo "# Configuring system..."

      # Save username for greetd and other services
      echo "$USERNAME" > /etc/clix/user

      # Mark setup as complete
      touch /etc/clix/.setup-complete
      touch /etc/clix/.home-encrypted

      # Store the home partition device for boot scripts
      echo "$HOME_DEV" > /etc/clix/home-device

      echo "90"
      echo "# Setting up user environment..."

      # Create user config directories
      mkdir -p "/home/$USERNAME/.config/sway"
      mkdir -p "/home/$USERNAME/.config/waybar"
      mkdir -p "/home/$USERNAME/.claude"

      # Link system configs
      ln -sf /etc/sway/config "/home/$USERNAME/.config/sway/config"
      ln -sf /etc/xdg/waybar/config "/home/$USERNAME/.config/waybar/config"
      ln -sf /etc/xdg/waybar/style.css "/home/$USERNAME/.config/waybar/style.css"

      chown -R "$USERNAME:users" "/home/$USERNAME"

      # Import any staged Claude credentials from CLIX-DATA
      if blkid -L CLIX-DATA >/dev/null 2>&1; then
        DATA_DEV=$(blkid -L CLIX-DATA)
        TEMP_MOUNT=$(mktemp -d)
        mount -o ro "$DATA_DEV" "$TEMP_MOUNT" || true

        if [ -d "$TEMP_MOUNT/claude" ] && [ -n "$(ls -A "$TEMP_MOUNT/claude" 2>/dev/null)" ]; then
          cp -rT "$TEMP_MOUNT/claude" "/home/$USERNAME/.claude/"
          chown -R "$USERNAME:users" "/home/$USERNAME/.claude"
          chmod 700 "/home/$USERNAME/.claude"
        fi

        umount "$TEMP_MOUNT" || true
        rmdir "$TEMP_MOUNT" || true
      fi

      echo "95"
      echo "# Finalizing..."

      # Note: We don't lock the setup user here.
      # After reboot, greetd will automatically use the new user
      # based on /etc/clix/user

      echo "100"
    ) | zenity --progress \
        --title="Setting Up CLIX" \
        --text="Preparing..." \
        --percentage=0 \
        --auto-close \
        --no-cancel \
        --width=400

    # Clear password from memory
    unset PASSWORD PASSWORD2

    # Success message
    zenity --info \
      --title="Setup Complete!" \
      --text="Your CLIX system is ready!\n\n• Username: $USERNAME\n• Encrypted home: ''${HOME_SIZE_GB}GB\n\nThe system will now reboot.\n\nOn each boot, you'll enter your password\nto unlock your encrypted data." \
      --width=400

    # Reboot
    systemctl reboot
  '';

  # CLI version for manual setup
  manualSetupScript = pkgs.writeShellScriptBin "clix-setup" ''
    if [ "$EUID" -ne 0 ]; then
      echo "This script must be run as root (use sudo)."
      exit 1
    fi
    exec ${firstBootWizard}
  '';

  # Factory reset script - wipe user and return to setup mode
  factoryResetScript = pkgs.writeShellScriptBin "clix-factory-reset" ''
    set -e
    export PATH="${lib.makeBinPath (with pkgs; [ coreutils util-linux cryptsetup ])}:$PATH"

    if [ "$EUID" -ne 0 ]; then
      echo "This script must be run as root (use sudo)."
      exit 1
    fi

    echo "=== CLIX Factory Reset ==="
    echo ""
    echo "WARNING: This will:"
    echo "  - Delete your user account"
    echo "  - Wipe your encrypted home partition"
    echo "  - Return the system to first-boot state"
    echo ""
    echo "All your data will be PERMANENTLY LOST!"
    echo ""
    read -p "Type 'RESET' to confirm: " CONFIRM

    if [ "$CONFIRM" != "RESET" ]; then
      echo "Aborted."
      exit 1
    fi

    echo ""
    echo "Resetting system..."

    # Get current user
    if [ -f /etc/clix/user ]; then
      CURRENT_USER=$(cat /etc/clix/user)

      # Kill user processes
      pkill -u "$CURRENT_USER" 2>/dev/null || true
      sleep 2

      # Delete user
      userdel -r "$CURRENT_USER" 2>/dev/null || true
    fi

    # Close and wipe encrypted home
    if [ -b /dev/mapper/clix-home ]; then
      umount /home 2>/dev/null || true
      cryptsetup close clix-home
    fi

    # Wipe home partition header
    if [ -f /etc/clix/home-device ]; then
      HOME_DEV=$(cat /etc/clix/home-device)
      dd if=/dev/zero of="$HOME_DEV" bs=1M count=10 2>/dev/null || true
    fi

    # Remove setup markers
    rm -f /etc/clix/.setup-complete
    rm -f /etc/clix/.home-encrypted
    rm -f /etc/clix/user
    rm -f /etc/clix/home-device

    # Re-enable setup user
    usermod -U setup 2>/dev/null || true
    usermod -e "" setup 2>/dev/null || true

    echo ""
    echo "Factory reset complete."
    echo "The system will now reboot to the setup wizard."
    echo ""
    read -p "Press Enter to reboot..."

    systemctl reboot
  '';

  # Autostart script - runs from sway config
  # Checks if setup is complete, runs wizard if not, otherwise starts Claude terminal
  autostartScript = pkgs.writeShellScript "clix-autostart" ''
    #!/usr/bin/env bash

    if [ ! -f /etc/clix/.setup-complete ]; then
      # First boot - run setup wizard with sudo
      # Use -E to preserve WAYLAND_DISPLAY and other env vars for zenity
      sudo -E ${firstBootWizard}
    else
      # Setup complete - start Claude terminal
      exec foot --app-id=claude-terminal -e /etc/clix-welcome.sh
    fi
  '';

in
{
  environment.systemPackages = [
    manualSetupScript
    factoryResetScript
    pkgs.zenity
    pkgs.parted
    pkgs.cloud-utils  # for growpart
  ];

  # Deploy autostart script
  environment.etc."clix-autostart.sh" = {
    source = autostartScript;
    mode = "0755";
  };
}
