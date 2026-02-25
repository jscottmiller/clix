{ config, pkgs, lib, ... }:

# First-boot setup wizard for CLIX
# On first boot (fresh install), this:
# 1. Detects available free space on the USB drive
# 2. Asks user how to partition (CLIX-DATA size, CLIX-HOME size)
# 3. Creates and formats partitions
# 4. Optionally encrypts CLIX-HOME with LUKS
# 5. Mounts partitions and continues boot

let
  # Main first-boot wizard script
  firstBootWizard = pkgs.writeShellScript "clix-first-boot-wizard" ''
    set -e
    export PATH="${lib.makeBinPath (with pkgs; [
      coreutils util-linux parted e2fsprogs dosfstools cryptsetup zenity gawk
    ])}:$PATH"

    # Find the boot device (the USB drive we're running from)
    ROOT_DEV=$(findmnt -n -o SOURCE /)
    if [[ "$ROOT_DEV" =~ ^/dev/nvme ]]; then
      DISK=$(echo "$ROOT_DEV" | sed 's/p[0-9]*$//')
    else
      DISK=$(echo "$ROOT_DEV" | sed 's/[0-9]*$//')
    fi

    echo "CLIX First Boot Setup"
    echo "Boot device: $DISK"

    # Check if CLIX-DATA partition already exists
    if blkid -L CLIX-DATA >/dev/null 2>&1; then
      echo "CLIX-DATA partition exists, checking CLIX-HOME..."

      # Check if CLIX-HOME exists
      if blkid -L CLIX-HOME >/dev/null 2>&1 || blkid -L CLIX-HOME-FS >/dev/null 2>&1; then
        echo "Partitions already configured, skipping first-boot setup."
        exit 0
      fi

      # CLIX-DATA exists but CLIX-HOME doesn't - might be partial setup
      # Continue to offer encryption setup
    fi

    # Check for marker file
    if [ -f /etc/clix/.first-boot-complete ]; then
      echo "First boot already completed."
      exit 0
    fi

    # Get disk size and find free space
    DISK_SIZE_BYTES=$(blockdev --getsize64 "$DISK")
    DISK_SIZE_GB=$((DISK_SIZE_BYTES / 1024 / 1024 / 1024))

    # Get end of last partition (in sectors)
    SECTOR_SIZE=$(blockdev --getss "$DISK")
    LAST_PART_END=$(parted -s "$DISK" unit s print | grep "^ [0-9]" | tail -1 | awk '{print $3}' | tr -d 's')

    # Calculate free space (leave 1MB at end for GPT backup)
    FREE_START_SECTOR=$((LAST_PART_END + 1))
    FREE_END_SECTOR=$((DISK_SIZE_BYTES / SECTOR_SIZE - 2048))
    FREE_SECTORS=$((FREE_END_SECTOR - FREE_START_SECTOR))
    FREE_GB=$((FREE_SECTORS * SECTOR_SIZE / 1024 / 1024 / 1024))

    if [ "$FREE_GB" -lt 1 ]; then
      zenity --error \
        --title="Insufficient Space" \
        --text="Not enough free space on the USB drive.\n\nFree space: ''${FREE_GB}GB\nRequired: at least 1GB\n\nThe drive may need to be re-imaged with a larger device." \
        --width=400 2>/dev/null
      exit 1
    fi

    echo "Disk: $DISK (''${DISK_SIZE_GB}GB total, ''${FREE_GB}GB free)"

    # Welcome dialog
    SETUP_CHOICE=$(zenity --list \
      --title="Welcome to CLIX" \
      --text="Welcome to CLIX!\n\nYour USB drive has ''${FREE_GB}GB of free space available.\nThis wizard will set up your data and home partitions.\n\nChoose setup type:" \
      --radiolist \
      --column="Select" --column="Option" --column="Description" \
      TRUE "recommended" "Recommended: 4GB data, rest for home (encrypted)" \
      FALSE "custom" "Custom: Choose sizes and encryption" \
      FALSE "skip" "Skip setup (not recommended)" \
      --width=500 --height=300 2>/dev/null) || exit 1

    if [ "$SETUP_CHOICE" = "skip" ]; then
      mkdir -p /etc/clix
      touch /etc/clix/.first-boot-complete
      zenity --info --text="Setup skipped. You can run 'sudo clix-setup' later." --width=300 2>/dev/null
      exit 0
    fi

    # Determine partition sizes
    if [ "$SETUP_CHOICE" = "recommended" ]; then
      DATA_SIZE_GB=4
      HOME_SIZE_GB=$((FREE_GB - DATA_SIZE_GB))
      ENCRYPT_HOME="yes"
    else
      # Custom setup - ask for sizes
      DATA_SIZE_GB=$(zenity --scale \
        --title="CLIX-DATA Size" \
        --text="How much space for CLIX-DATA? (FAT32, Windows-visible)\n\nUse this for WiFi configs, Claude credentials staging." \
        --min-value=1 --max-value=$((FREE_GB - 1)) --value=4 \
        --width=400 2>/dev/null) || exit 1

      REMAINING=$((FREE_GB - DATA_SIZE_GB))
      HOME_SIZE_GB=$(zenity --scale \
        --title="CLIX-HOME Size" \
        --text="How much space for CLIX-HOME? (Your private data)\n\nRemaining space: ''${REMAINING}GB" \
        --min-value=1 --max-value=$REMAINING --value=$REMAINING \
        --width=400 2>/dev/null) || exit 1

      # Ask about encryption
      if zenity --question \
        --title="Encrypt Home?" \
        --text="Do you want to encrypt CLIX-HOME?\n\nEncryption protects your data if the USB is lost.\nYou'll need to enter a password on each boot." \
        --ok-label="Yes, Encrypt" \
        --cancel-label="No Encryption" \
        --width=400 2>/dev/null; then
        ENCRYPT_HOME="yes"
      else
        ENCRYPT_HOME="no"
      fi
    fi

    # Get encryption password if needed
    if [ "$ENCRYPT_HOME" = "yes" ]; then
      while true; do
        PASS1=$(zenity --password \
          --title="Set Encryption Password" \
          --text="Enter a strong password for CLIX-HOME encryption:" \
          2>/dev/null) || exit 1

        if [ -z "$PASS1" ]; then
          zenity --error --text="Password cannot be empty." --width=250 2>/dev/null
          continue
        fi

        if [ ''${#PASS1} -lt 8 ]; then
          zenity --error --text="Password must be at least 8 characters." --width=250 2>/dev/null
          continue
        fi

        PASS2=$(zenity --password \
          --title="Confirm Password" \
          --text="Confirm your encryption password:" \
          2>/dev/null) || exit 1

        if [ "$PASS1" != "$PASS2" ]; then
          zenity --error --text="Passwords do not match. Try again." --width=250 2>/dev/null
          continue
        fi

        break
      done
    fi

    # Confirm before proceeding
    ENCRYPT_MSG="No"
    [ "$ENCRYPT_HOME" = "yes" ] && ENCRYPT_MSG="Yes"

    if ! zenity --question \
      --title="Confirm Setup" \
      --text="Ready to create partitions:\n\n• CLIX-DATA: ''${DATA_SIZE_GB}GB (FAT32)\n• CLIX-HOME: ''${HOME_SIZE_GB}GB (ext4)\n• Encryption: $ENCRYPT_MSG\n\nThis will use the free space on your USB drive.\nExisting partitions will NOT be modified.\n\nProceed?" \
      --ok-label="Create Partitions" \
      --cancel-label="Cancel" \
      --width=400 2>/dev/null; then
      exit 1
    fi

    # Calculate partition boundaries (in sectors)
    DATA_SECTORS=$((DATA_SIZE_GB * 1024 * 1024 * 1024 / SECTOR_SIZE))
    HOME_SECTORS=$((HOME_SIZE_GB * 1024 * 1024 * 1024 / SECTOR_SIZE))

    # Align to 2048 sector boundaries
    DATA_START=$(( ((FREE_START_SECTOR + 2047) / 2048) * 2048 ))
    DATA_END=$((DATA_START + DATA_SECTORS - 1))
    HOME_START=$(( ((DATA_END + 1 + 2047) / 2048) * 2048 ))
    HOME_END=$((HOME_START + HOME_SECTORS - 1))

    # Create partitions with progress
    (
      echo "10"
      echo "# Creating CLIX-DATA partition..."

      # Get next partition number
      LAST_PART_NUM=$(parted -s "$DISK" print | grep "^ [0-9]" | tail -1 | awk '{print $1}')
      DATA_PART_NUM=$((LAST_PART_NUM + 1))
      HOME_PART_NUM=$((DATA_PART_NUM + 1))

      parted -s "$DISK" mkpart CLIX-DATA fat32 ''${DATA_START}s ''${DATA_END}s

      echo "30"
      echo "# Creating CLIX-HOME partition..."
      parted -s "$DISK" mkpart CLIX-HOME ext4 ''${HOME_START}s ''${HOME_END}s

      # Wait for partition devices to appear
      sleep 2
      partprobe "$DISK"
      sleep 2

      # Determine partition device names
      if [[ "$DISK" =~ nvme ]]; then
        DATA_DEV="''${DISK}p''${DATA_PART_NUM}"
        HOME_DEV="''${DISK}p''${HOME_PART_NUM}"
      else
        DATA_DEV="''${DISK}''${DATA_PART_NUM}"
        HOME_DEV="''${DISK}''${HOME_PART_NUM}"
      fi

      echo "50"
      echo "# Formatting CLIX-DATA (FAT32)..."
      mkfs.vfat -n CLIX-DATA "$DATA_DEV"

      # Create directory structure on CLIX-DATA
      TEMP_MOUNT=$(mktemp -d)
      mount "$DATA_DEV" "$TEMP_MOUNT"
      mkdir -p "$TEMP_MOUNT/claude" "$TEMP_MOUNT/network"
      cat > "$TEMP_MOUNT/README.txt" << 'DATAEOF'
CLIX Data Partition
====================

This partition is read on boot to configure your CLIX system.

WiFi Configuration
------------------
Create: network/wifi.nmconnection
Create: network/regdomain (2-letter country code, e.g., US)

Claude Credentials
------------------
Copy your ~/.claude directory contents to: claude/
DATAEOF
      umount "$TEMP_MOUNT"
      rmdir "$TEMP_MOUNT"

      echo "70"
      if [ "$ENCRYPT_HOME" = "yes" ]; then
        echo "# Encrypting CLIX-HOME partition..."
        echo "$PASS1" | cryptsetup luksFormat --type luks2 --pbkdf argon2id "$HOME_DEV" -
        echo "$PASS1" | cryptsetup open "$HOME_DEV" clix-home -

        echo "85"
        echo "# Formatting encrypted CLIX-HOME (ext4)..."
        mkfs.ext4 -L CLIX-HOME-FS /dev/mapper/clix-home

        # Mount and set up
        mount /dev/mapper/clix-home /home
      else
        echo "# Formatting CLIX-HOME (ext4)..."
        mkfs.ext4 -L CLIX-HOME "$HOME_DEV"
        mount "$HOME_DEV" /home
      fi

      echo "95"
      echo "# Setting up home directory..."
      mkdir -p /home/clix
      chown 1000:100 /home/clix
      chmod 700 /home/clix

      # Create marker file
      mkdir -p /etc/clix
      touch /etc/clix/.first-boot-complete
      [ "$ENCRYPT_HOME" = "yes" ] && touch /etc/clix/.home-encrypted

      echo "100"
    ) | zenity --progress \
        --title="Setting Up CLIX" \
        --text="Preparing..." \
        --percentage=0 \
        --auto-close \
        --no-cancel \
        --width=400 2>/dev/null

    # Clear password from memory
    unset PASS1 PASS2

    # Success message
    zenity --info \
      --title="Setup Complete" \
      --text="CLIX setup complete!\n\nPartitions created:\n• CLIX-DATA: ''${DATA_SIZE_GB}GB\n• CLIX-HOME: ''${HOME_SIZE_GB}GB $([ "$ENCRYPT_HOME" = "yes" ] && echo "(encrypted)")\n\nYou can now use your CLIX system.\nOn future boots$([ "$ENCRYPT_HOME" = "yes" ] && echo ", enter your password when prompted")." \
      --width=400 2>/dev/null
  '';

  # CLI version for manual setup
  manualSetupScript = pkgs.writeShellScriptBin "clix-setup" ''
    exec ${firstBootWizard}
  '';

  # Manual encryption script (for encrypting existing unencrypted home)
  manualEncryptScript = pkgs.writeShellScriptBin "clix-encrypt-home" ''
    set -e
    export PATH="${lib.makeBinPath (with pkgs; [
      coreutils util-linux cryptsetup
    ])}:$PATH"

    HOME_PART=$(blkid -L CLIX-HOME 2>/dev/null || true)

    if [ -z "$HOME_PART" ]; then
      echo "CLIX-HOME partition not found."
      echo "Run 'sudo clix-setup' first to create partitions."
      exit 1
    fi

    if cryptsetup isLuks "$HOME_PART" 2>/dev/null; then
      echo "CLIX-HOME is already encrypted."
      exit 0
    fi

    if [ "$EUID" -ne 0 ]; then
      echo "This script must be run as root (use sudo)."
      exit 1
    fi

    echo "=== CLIX Home Encryption ==="
    echo ""
    echo "This will encrypt your /home partition."
    echo "WARNING: This will ERASE all data on /home!"
    echo ""
    read -p "Type 'yes' to continue: " CONFIRM
    [ "$CONFIRM" != "yes" ] && exit 1

    # Get password
    while true; do
      read -s -p "Enter encryption password: " PASS1
      echo ""
      [ -z "$PASS1" ] && echo "Password cannot be empty." && continue
      [ ''${#PASS1} -lt 8 ] && echo "Password must be at least 8 characters." && continue
      read -s -p "Confirm password: " PASS2
      echo ""
      [ "$PASS1" != "$PASS2" ] && echo "Passwords do not match." && continue
      break
    done

    echo "Unmounting /home..."
    umount /home 2>/dev/null || true

    echo "Encrypting partition..."
    echo "$PASS1" | cryptsetup luksFormat --type luks2 --pbkdf argon2id "$HOME_PART" -

    echo "Opening encrypted partition..."
    echo "$PASS1" | cryptsetup open "$HOME_PART" clix-home -

    echo "Formatting..."
    mkfs.ext4 -L CLIX-HOME-FS /dev/mapper/clix-home

    echo "Mounting..."
    mount /dev/mapper/clix-home /home
    mkdir -p /home/clix
    chown 1000:100 /home/clix
    chmod 700 /home/clix

    mkdir -p /etc/clix
    touch /etc/clix/.home-encrypted

    unset PASS1 PASS2

    echo ""
    echo "Encryption complete!"
    echo "On next boot, you'll be prompted for your password."
  '';
in
{
  environment.systemPackages = [
    manualSetupScript
    manualEncryptScript
    pkgs.zenity
    pkgs.parted
  ];

  # Run first-boot wizard after graphical session starts
  systemd.services.clix-first-boot = {
    description = "CLIX First Boot Setup Wizard";
    wantedBy = [ "graphical.target" ];
    after = [ "graphical.target" ];

    unitConfig = {
      # Don't run if setup already completed
      ConditionPathExists = "!/etc/clix/.first-boot-complete";
    };

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${firstBootWizard}";
      Environment = [
        "DISPLAY=:0"
        "WAYLAND_DISPLAY=wayland-1"
        "XDG_RUNTIME_DIR=/run/user/1000"
      ];
      # Give time for desktop to start
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
    };
  };
}
