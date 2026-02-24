{ config, pkgs, lib, self, ... }:

{
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

  # Auto-login via greetd
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.sway}/bin/sway";
        user = "clix";
      };
      initial_session = {
        command = "${pkgs.sway}/bin/sway";
        user = "clix";
      };
    };
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

  # Sway reads from /etc/sway/config if XDG_CONFIG_HOME/sway/config doesn't exist
  # But we also need to set up the user config directory
  system.activationScripts.swayConfig = ''
    mkdir -p /home/clix/.config/sway
    mkdir -p /home/clix/.config/waybar

    # Link to system configs if user hasn't customized
    if [ ! -e /home/clix/.config/sway/config ]; then
      ln -sf /etc/sway/config /home/clix/.config/sway/config
    fi
    if [ ! -e /home/clix/.config/waybar/config ]; then
      ln -sf /etc/xdg/waybar/config /home/clix/.config/waybar/config
    fi
    if [ ! -e /home/clix/.config/waybar/style.css ]; then
      ln -sf /etc/xdg/waybar/style.css /home/clix/.config/waybar/style.css
    fi

    chown -R clix:users /home/clix/.config
  '';

  # Polkit for authentication dialogs
  security.polkit.enable = true;

  # D-Bus is required for many desktop features
  services.dbus.enable = true;

  # Enable gvfs for file management
  services.gvfs.enable = true;
}
