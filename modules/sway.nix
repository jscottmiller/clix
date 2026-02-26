{ config, pkgs, lib, self, ... }:

let
  # Sway start script with proper environment and logging
  swayStartScript = pkgs.writeShellScript "clix-start-sway" ''
    # Log everything for debugging
    exec > /tmp/sway-start.log 2>&1
    echo "=== Starting sway at $(date) ==="
    echo "User: $(whoami)"
    echo "Home: $HOME"
    echo "XDG_RUNTIME_DIR: $XDG_RUNTIME_DIR"

    # Ensure XDG_RUNTIME_DIR exists
    if [ -z "$XDG_RUNTIME_DIR" ]; then
      export XDG_RUNTIME_DIR="/run/user/$(id -u)"
      echo "Set XDG_RUNTIME_DIR to $XDG_RUNTIME_DIR"
    fi

    # Wayland/Sway environment
    export XDG_SESSION_TYPE=wayland
    export XDG_CURRENT_DESKTOP=sway
    export MOZ_ENABLE_WAYLAND=1

    # Ensure home directory exists
    if [ ! -d "$HOME" ]; then
      echo "Creating home directory $HOME"
      mkdir -p "$HOME"
    fi

    echo "Starting sway..."
    exec dbus-run-session ${pkgs.sway}/bin/sway -d 2>&1
  '';
in
{
  # Unlock encrypted home partition at boot (only after first-boot setup)
  systemd.services.clix-unlock-home = {
    description = "Unlock CLIX encrypted home";
    wantedBy = [ "local-fs.target" ];
    before = [ "local-fs.target" ];
    after = [ "systemd-udev-settle.service" ];
    unitConfig = {
      ConditionPathExists = "/etc/clix/.home-encrypted";
      DefaultDependencies = false;
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      StandardInput = "tty";
      StandardOutput = "tty";
      TTYPath = "/dev/tty1";
      TTYReset = true;
      TTYVHangup = true;
    };
    path = [ pkgs.coreutils pkgs.cryptsetup pkgs.util-linux pkgs.ncurses ];
    script = ''
      # Check if already unlocked
      if [ -b /dev/mapper/clix-home ]; then
        mount /dev/mapper/clix-home /home 2>/dev/null || true
        exit 0
      fi

      # Get the home device
      if [ ! -f /etc/clix/home-device ]; then
        exit 0
      fi

      HOME_DEV=$(cat /etc/clix/home-device)

      if [ ! -b "$HOME_DEV" ]; then
        echo "Home device $HOME_DEV not found"
        exit 1
      fi

      clear
      echo ""
      echo "  ╔═══════════════════════════════════════╗"
      echo "  ║           CLIX - Unlock Home          ║"
      echo "  ╚═══════════════════════════════════════╝"
      echo ""

      for attempt in 1 2 3; do
        echo -n "  Enter encryption password: "
        read -s PASSWORD
        echo ""

        if echo "$PASSWORD" | cryptsetup open "$HOME_DEV" clix-home --key-file=-; then
          echo "  Unlocked!"
          mount /dev/mapper/clix-home /home
          sleep 1
          exit 0
        else
          echo "  Incorrect password. Attempt $attempt of 3."
        fi
      done

      echo "  Too many failed attempts."
      exit 1
    '';
  };

  # Greetd - we manage the config dynamically
  services.greetd.enable = true;

  # Override greetd service entirely to use our dynamic config
  systemd.services.greetd = {
    serviceConfig = {
      ExecStartPre = let
        configScript = pkgs.writeShellScript "clix-greetd-setup" ''
          mkdir -p /run/clix
          if [ -f /etc/clix/.setup-complete ]; then
            # After setup: require login
            cat > /run/clix/greetd.toml << EOF
[terminal]
vt = 1

[default_session]
command = "${pkgs.greetd.greetd}/bin/agreety --cmd ${swayStartScript}"
user = "root"
EOF
            echo "Greetd: configured with login prompt"
          else
            # First boot: auto-login as setup
            cat > /run/clix/greetd.toml << EOF
[terminal]
vt = 1

[default_session]
command = "${swayStartScript}"
user = "setup"
EOF
            echo "Greetd: configured for first boot (setup user)"
          fi
        '';
      in "${configScript}";
      ExecStart = lib.mkForce "${pkgs.greetd.greetd}/bin/greetd --config /run/clix/greetd.toml";
    };
  };


  # Enable Sway
  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    extraPackages = with pkgs; [
      foot              # Terminal
      waybar            # Status bar
      wofi              # App launcher
      mako              # Notifications
      swaylock          # Screen locker
      swayidle          # Idle management
      grim              # Screenshots
      slurp             # Region selection
      wl-clipboard      # Clipboard
      brightnessctl     # Brightness control
      pamixer           # Audio control
      networkmanagerapplet  # Network tray icon & nm-connection-editor
      polkit_gnome          # Polkit auth agent (needed for nm-applet)
      firefox           # Web browser for OAuth sign-in
    ];
  };

  # XDG portal for screen sharing, file dialogs, etc.
  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  # Disable other display managers
  services.xserver.enable = false;

  # Environment variables for Wayland
  environment.sessionVariables = {
    MOZ_ENABLE_WAYLAND = "1";
    XDG_CURRENT_DESKTOP = "sway";
    XDG_SESSION_TYPE = "wayland";
  };

  # Deploy Sway config
  environment.etc."sway/config".source = "${self}/config/sway/config";

  # Deploy Waybar configs
  environment.etc."xdg/waybar/config".source = "${self}/config/waybar/config";
  environment.etc."xdg/waybar/style.css".source = "${self}/config/waybar/style.css";

  # Foot terminal config (larger font)
  environment.etc."xdg/foot/foot.ini".source = "${self}/config/foot/foot.ini";

  # Sway reads from /etc/sway/config if XDG_CONFIG_HOME/sway/config doesn't exist
  # This activation script runs on boot to set up user config directories
  # It handles both the setup user (first boot) and the real user (after setup)
  system.activationScripts.swayConfig = ''
    # Determine the target user
    if [ -f /etc/clix/user ]; then
      TARGET_USER=$(cat /etc/clix/user)
    else
      TARGET_USER="setup"
    fi

    # Get the user's home directory
    USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    if [ -z "$USER_HOME" ] || [ ! -d "$USER_HOME" ]; then
      USER_HOME="/home/$TARGET_USER"
    fi

    # Create config directories
    mkdir -p "$USER_HOME/.config/sway"
    mkdir -p "$USER_HOME/.config/waybar"

    # Link to system configs if user hasn't customized
    if [ ! -e "$USER_HOME/.config/sway/config" ]; then
      ln -sf /etc/sway/config "$USER_HOME/.config/sway/config"
    fi
    if [ ! -e "$USER_HOME/.config/waybar/config" ]; then
      ln -sf /etc/xdg/waybar/config "$USER_HOME/.config/waybar/config"
    fi
    if [ ! -e "$USER_HOME/.config/waybar/style.css" ]; then
      ln -sf /etc/xdg/waybar/style.css "$USER_HOME/.config/waybar/style.css"
    fi

    chown -R "$TARGET_USER:users" "$USER_HOME/.config" 2>/dev/null || true
  '';

  # Polkit for authentication dialogs
  security.polkit.enable = true;

  # D-Bus is required for many desktop features
  services.dbus.enable = true;

  # Enable gvfs for file management
  services.gvfs.enable = true;
}
