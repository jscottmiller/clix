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
  # Greetd with sway - runs as setup user
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${swayStartScript}";
        user = "setup";
      };
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
