{ config, pkgs, lib, ... }:

{
  # Basic system settings
  networking.hostName = "clix";
  time.timeZone = "UTC";

  # Enable networking
  networking.networkmanager.enable = true;

  # wpa_supplicant service needed by NetworkManager for WiFi
  networking.wireless.enable = lib.mkDefault true;

  # Essential packages - minimal set, user prompts for the rest
  environment.systemPackages = with pkgs; [
    # Core tools
    git
    curl
    wget
    vim
    nano

    # System utilities
    htop
    file
    tree
    less
    unzip
    zip
    gnutar
    gzip
    ripgrep
    fd
    bat       # syntax-highlighted cat
    fzf       # fuzzy finder
    jq        # JSON processing
    imv       # image viewer (Wayland-native)

    # Network tools
    iproute2
    dnsutils
    iw
    wirelesstools  # iwconfig
    wpa_supplicant  # required by NetworkManager for WiFi

    # Hardware diagnostics
    pciutils  # lspci
    usbutils  # lsusb

    # Disk and installation tools
    parted          # partition editor
    gptfdisk        # GPT tools (sgdisk, gdisk)
    dosfstools      # FAT32 formatting (mkfs.vfat)
    e2fsprogs       # ext4 formatting (mkfs.ext4)
    nixos-install-tools  # nixos-install, nixos-generate-config

    # Development basics
    gnumake
    gcc
    (python3.withPackages (ps: with ps; [
      # Package management
      pip

      # Data & visualization
      matplotlib
      numpy
      pandas
      pillow

      # GUI & apps
      tkinter

      # Utilities
      requests
      pyyaml
      rich        # pretty terminal output
    ]))
  ];

  # Enable nix flakes
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    # Trust wheel group for nix operations
    trusted-users = [ "root" "@wheel" ];
  };

  # Allow unfree packages (for some proprietary tools if needed)
  nixpkgs.config.allowUnfree = true;

  # WiFi and hardware firmware (Intel, Realtek, Broadcom, etc.)
  hardware.enableRedistributableFirmware = true;
  hardware.enableAllFirmware = true;

  # Allow mutable users - the real user is created at first boot
  users.mutableUsers = true;

  # Setup user - used only during first-boot wizard
  # After setup, a real user is created and this account is disabled
  users.users.setup = {
    isNormalUser = true;
    uid = 1000;  # Fixed UID for consistency
    description = "CLIX Setup";
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
    hashedPassword = "$6$SrkbSIutIhbKnw6P$61lSUqCqqbuULHckuKmWLPWHW3YNrDHtOUT78bhUK4PyFmU7PY3gYzrKv1UQ1XndGws6n7Wl8uxzSjR3dpUxT.";  # password: clix
    shell = pkgs.bash;
  };

  # Root password (unlocks root account) - password: clix
  users.users.root.hashedPassword = "$6$SrkbSIutIhbKnw6P$61lSUqCqqbuULHckuKmWLPWHW3YNrDHtOUT78bhUK4PyFmU7PY3gYzrKv1UQ1XndGws6n7Wl8uxzSjR3dpUxT.";

  # Autologin on TTY2 for debugging (Ctrl+Alt+F2)
  # Use setup user since root might be locked
  systemd.services."autovt@tty2" = {
    description = "Debug terminal on tty2";
    after = [ "systemd-user-sessions.service" "plymouth-quit-wait.service" "getty-pre.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "idle";
      ExecStart = "${pkgs.util-linux}/bin/agetty --autologin setup --noclear tty2 $TERM";
      Restart = "always";
      TTYPath = "/dev/tty2";
      TTYReset = "yes";
      TTYVHangup = "yes";
      StandardInput = "tty";
      StandardOutput = "tty";
    };
  };

  # Passwordless sudo for wheel group (setup user and future user)
  security.sudo.wheelNeedsPassword = false;

  # Enable sound with pipewire
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # Basic fonts
  fonts.packages = with pkgs; [
    dejavu_fonts
    liberation_ttf
    noto-fonts
    noto-fonts-color-emoji
    fira-code
    fira-code-symbols
    nerd-fonts.fira-code
    nerd-fonts.jetbrains-mono
  ];

  # System version
  system.stateVersion = "24.11";
}
