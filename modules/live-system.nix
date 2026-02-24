{ config, pkgs, lib, ... }:

let
  # Editable configuration template for /etc/nixos
  editableConfig = pkgs.writeText "configuration.nix" ''
    # CLIX Live Configuration
    # Edit this file and run `rebuild` to apply changes.
    #
    # This configuration extends the base CLIX system.
    # Add packages, services, or other NixOS options here.

    { config, pkgs, lib, ... }:

    {
      # Add your custom packages here
      environment.systemPackages = with pkgs; [
        # Example: python3 neovim tmux
      ];

      # Add custom services or configuration below
      # services.someService.enable = true;

      # Don't modify this line
      system.stateVersion = "24.11";
    }
  '';

  editableFlake = pkgs.writeText "flake.nix" ''
    {
      description = "CLIX Live Configuration";

      inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
      };

      outputs = { self, nixpkgs }: {
        nixosConfigurations.clix = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            # Import the running system's configuration
            /run/current-system/configuration.nix

            # Your customizations
            ./configuration.nix
          ];
        };
      };
    }
  '';

  rebuildScript = pkgs.writeShellScriptBin "rebuild" ''
    #!/usr/bin/env bash
    set -e

    echo "Rebuilding CLIX system..."
    echo ""

    if [ ! -f /etc/nixos/flake.nix ]; then
      echo "Error: /etc/nixos/flake.nix not found"
      echo "Run 'sudo clix-init-config' to initialize"
      exit 1
    fi

    cd /etc/nixos
    sudo nixos-rebuild switch --flake .#clix

    echo ""
    echo "Rebuild complete!"
  '';

  editConfigScript = pkgs.writeShellScriptBin "edit-config" ''
    #!/usr/bin/env bash
    ''${EDITOR:-vim} /etc/nixos/configuration.nix
  '';

  initConfigScript = pkgs.writeShellScriptBin "clix-init-config" ''
    #!/usr/bin/env bash
    set -e

    echo "Initializing /etc/nixos configuration..."

    mkdir -p /etc/nixos

    if [ ! -f /etc/nixos/configuration.nix ]; then
      cp ${editableConfig} /etc/nixos/configuration.nix
      chmod 644 /etc/nixos/configuration.nix
      echo "Created /etc/nixos/configuration.nix"
    else
      echo "/etc/nixos/configuration.nix already exists, skipping"
    fi

    if [ ! -f /etc/nixos/flake.nix ]; then
      cp ${editableFlake} /etc/nixos/flake.nix
      chmod 644 /etc/nixos/flake.nix
      echo "Created /etc/nixos/flake.nix"
    else
      echo "/etc/nixos/flake.nix already exists, skipping"
    fi

    echo ""
    echo "Configuration initialized!"
    echo "Edit with: edit-config"
    echo "Apply with: rebuild"
  '';
in
{
  # Add rebuild tools to system packages
  environment.systemPackages = [
    rebuildScript
    editConfigScript
    initConfigScript
  ];

  # Shell aliases
  environment.shellAliases = {
    rebuild = "rebuild";
    edit-config = "edit-config";
  };

  # Initialize /etc/nixos on boot
  system.activationScripts.initNixosConfig = ''
    # Initialize editable config on first boot
    if [ ! -f /etc/nixos/configuration.nix ]; then
      ${initConfigScript}/bin/clix-init-config || true
    fi
  '';

  # Boot settings
  boot = {
    # systemd-boot for UEFI
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = false;

    # RAM-based /tmp
    tmp.useTmpfs = true;

    # Kernel parameters
    kernelParams = [
      "console=ttyS0,115200"  # Serial console for VM debugging
      "console=tty0"
    ];
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
