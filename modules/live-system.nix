{ config, pkgs, lib, self, ... }:

let
  # self is passed from the flake and always points to the flake directory
  # Works both during initial build (project root) and rebuild (/etc/nixos)

  rebuildScript = pkgs.writeShellScriptBin "rebuild" ''
    #!/usr/bin/env bash
    set -e

    echo "Rebuilding CLIX system..."
    echo ""

    if [ ! -f /etc/nixos/flake.nix ]; then
      echo "Error: /etc/nixos/flake.nix not found"
      exit 1
    fi

    sudo nixos-rebuild switch --flake /etc/nixos#clix

    echo ""
    echo "Rebuild complete!"
  '';

  editConfigScript = pkgs.writeShellScriptBin "edit-config" ''
    #!/usr/bin/env bash
    sudo ''${EDITOR:-vim} /etc/nixos/configuration.nix
  '';
in
{
  # Add rebuild tools to system packages
  environment.systemPackages = [
    rebuildScript
    editConfigScript
  ];

  # Shell aliases
  environment.shellAliases = {
    rebuild = "rebuild";
    edit-config = "edit-config";
  };

  # Ship the complete /etc/nixos directory structure
  # Files are shipped to both their target location AND their source path,
  # so that rebuilds from /etc/nixos/ can find the sources.
  environment.etc = {
    # Flake files - ship to /etc/nixos/ (where they're used)
    "nixos/flake.nix" = {
      source = "${self}/config/nixos/flake.nix";
      mode = "0644";
    };
    "nixos/flake.lock" = {
      source = "${self}/flake.lock";
      mode = "0644";
    };
    "nixos/base-configuration.nix" = {
      source = "${self}/config/nixos/base-configuration.nix";
      mode = "0644";
    };

    # Also ship to source paths so rebuilds from /etc/nixos/ work
    # (${self} = /etc/nixos/ during rebuild, so sources need to exist there)
    "nixos/config/nixos/flake.nix" = {
      source = "${self}/config/nixos/flake.nix";
      mode = "0644";
    };
    "nixos/config/nixos/base-configuration.nix" = {
      source = "${self}/config/nixos/base-configuration.nix";
      mode = "0644";
    };

    # User-editable configuration (only create if doesn't exist)
    # Handled by activation script below

    # Ship all modules
    "nixos/modules/base.nix" = {
      source = "${self}/modules/base.nix";
      mode = "0644";
    };
    "nixos/modules/sway.nix" = {
      source = "${self}/modules/sway.nix";
      mode = "0644";
    };
    "nixos/modules/claude-code.nix" = {
      source = "${self}/modules/claude-code.nix";
      mode = "0644";
    };
    "nixos/modules/live-system.nix" = {
      source = "${self}/modules/live-system.nix";
      mode = "0644";
    };
    "nixos/modules/data-partition.nix" = {
      source = "${self}/modules/data-partition.nix";
      mode = "0644";
    };
    "nixos/modules/encrypted-home.nix" = {
      source = "${self}/modules/encrypted-home.nix";
      mode = "0644";
    };
    "nixos/modules/first-boot-setup.nix" = {
      source = "${self}/modules/first-boot-setup.nix";
      mode = "0644";
    };

    # Config files referenced by modules
    "nixos/config/sway/config" = {
      source = "${self}/config/sway/config";
      mode = "0644";
    };
    "nixos/config/waybar/config" = {
      source = "${self}/config/waybar/config";
      mode = "0644";
    };
    "nixos/config/waybar/style.css" = {
      source = "${self}/config/waybar/style.css";
      mode = "0644";
    };
    "nixos/config/foot/foot.ini" = {
      source = "${self}/config/foot/foot.ini";
      mode = "0644";
    };

    # Package installation guides
    "nixos/docs/packages/README.md" = {
      source = "${self}/docs/packages/README.md";
      mode = "0644";
    };
    "nixos/docs/packages/steam.md" = {
      source = "${self}/docs/packages/steam.md";
      mode = "0644";
    };
  };

  # Create user configuration.nix on first boot (mutable, not managed by etc)
  system.activationScripts.initUserConfig = ''
    if [ ! -f /etc/nixos/configuration.nix ]; then
      cat > /etc/nixos/configuration.nix << 'CONFIGEOF'
# CLIX User Configuration
# Edit this file and run `rebuild` to apply changes.

{ config, pkgs, lib, ... }:

{
  # Add your custom packages here
  environment.systemPackages = with pkgs; [
    # example: python3 neovim tmux
  ];

  # Add custom services or configuration below
  # services.someService.enable = true;
}
CONFIGEOF
      chmod 644 /etc/nixos/configuration.nix
    fi

    # Make configuration.nix owned by the CLIX user (if setup is complete)
    if [ -f /etc/clix/user ]; then
      USERNAME=$(cat /etc/clix/user)
      chown "$USERNAME:users" /etc/nixos/configuration.nix 2>/dev/null || true
    fi
  '';

  # System branding for boot menu
  system.nixos.distroName = "CLIX";  # Changes "NixOS" to "CLIX" in boot entries
  system.nixos.label = "CLIX";       # Additional label in boot entry description

  # Boot settings
  boot = {
    # systemd-boot for UEFI
    loader.systemd-boot.enable = true;
    loader.systemd-boot.configurationLimit = 10;
    loader.systemd-boot.sortKey = "clix";
    loader.efi.canTouchEfiVariables = false;

    # Debug boot entry - declared here, paths filled in by extraInstallCommands
    # Enables systemd debug shell on tty9 (Ctrl+Alt+F9)
    loader.systemd-boot.extraEntries = {
      "clix-debug.conf" = ''
        title CLIX (Debug - tty9 shell)
        linux __KERNEL__
        initrd __INITRD__
        options __OPTIONS__ systemd.debug_shell=1
      '';
    };

    # Fill in dynamic paths from the generated boot entry
    loader.systemd-boot.extraInstallCommands = ''
      DEBUG_ENTRY="/boot/loader/entries/clix-debug.conf"

      # Find the latest generation entry (any pattern)
      LATEST=$(ls -t /boot/loader/entries/*generation*.conf 2>/dev/null | head -1)

      if [ -n "$LATEST" ] && [ -f "$LATEST" ] && [ -f "$DEBUG_ENTRY" ]; then
        # Extract paths from the generated entry
        KERNEL=$(grep '^linux' "$LATEST" | awk '{print $2}')
        INITRD=$(grep '^initrd' "$LATEST" | awk '{print $2}')
        OPTIONS=$(grep '^options' "$LATEST" | sed 's/^options //')

        # Fill in the placeholders
        sed -i \
          -e "s|__KERNEL__|$KERNEL|" \
          -e "s|__INITRD__|$INITRD|" \
          -e "s|__OPTIONS__|$OPTIONS|" \
          "$DEBUG_ENTRY"
      fi
    '';

    # RAM-based /tmp
    tmp.useTmpfs = true;

    # Kernel parameters
    kernelParams = [
      "console=ttyS0,115200"  # Serial console for VM debugging
      "console=tty0"
      "rootwait"              # Wait indefinitely for root device (USB can be slow)
    ];

    # Initrd settings
    initrd = {
      # Use systemd in initrd for better LUKS password prompts
      systemd.enable = true;

      # USB storage modules - essential for booting from USB
      availableKernelModules = [
        "usb_storage"
        "uas"           # USB Attached SCSI
        "sd_mod"        # SCSI disk
        "ehci_pci"      # USB 2.0
        "xhci_pci"      # USB 3.0
        "ahci"          # SATA (for some USB-SATA bridges)
        "usbhid"        # USB HID (keyboards)
      ];
    };
  };

  # Filesystem configuration for live USB
  fileSystems."/" = {
    device = "/dev/disk/by-label/CLIX-ROOT";
    fsType = "ext4";
    options = [ "x-systemd.device-timeout=0" ];  # Wait indefinitely for USB
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };

  # Enable memory compression for better performance
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  # Documentation for offline use
  documentation = {
    enable = true;
    man.enable = true;
    nixos.enable = true;
  };

  # Don't start a getty on tty1 - we use graphical login
  services.getty.autologinUser = lib.mkForce null;

  # System version
  system.stateVersion = "24.11";
}
