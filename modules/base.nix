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

    # Network tools
    iproute2
    dnsutils
    iw
    wirelesstools  # iwconfig
    wpa_supplicant  # required by NetworkManager for WiFi
    openssh

    # Hardware diagnostics
    pciutils  # lspci
    usbutils  # lsusb

    # Development basics
    gnumake
    gcc
    python3
  ];

  # Enable nix flakes
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "clix" ];
  };

  # Allow unfree packages (for some proprietary tools if needed)
  nixpkgs.config.allowUnfree = true;

  # WiFi and hardware firmware (Intel, Realtek, Broadcom, etc.)
  hardware.enableRedistributableFirmware = true;
  hardware.enableAllFirmware = true;

  # Create the clix user
  users.users.clix = {
    isNormalUser = true;
    description = "CLIX User";
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
    initialPassword = "";
    shell = pkgs.bash;
  };

  # Passwordless sudo for clix user
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
