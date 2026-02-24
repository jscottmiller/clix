{ config, pkgs, lib, ... }:

let
  # CLAUDE.md context file for Claude Code
  claudeContextFile = pkgs.writeText "CLAUDE.md" ''
    # CLIX Environment Context

    You are running inside CLIX (Claude Code Live ISO), an ephemeral NixOS-based
    environment designed specifically for AI-assisted development and system tasks.

    ## Environment Overview

    - **OS**: NixOS (unstable channel)
    - **Display**: Sway (Wayland tiling window manager)
    - **Terminal**: foot
    - **User**: clix (passwordless sudo enabled)
    - **Persistence**: NONE - all changes are lost on reboot

    ## Key Capabilities

    ### UI Interaction Tools
    You can interact with GUI elements using these tools:

    **ydotool** - Mouse and keyboard simulation (preferred):
    ```bash
    # Click at coordinates (x, y)
    ydotool mousemove --absolute -x 500 -y 300
    ydotool click 0xC0  # Left click (0xC0=left, 0xC1=right, 0xC2=middle)

    # Double click
    ydotool click 0xC0 0xC0

    # Type text
    ydotool type "Hello, world!"

    # Press keys (key codes)
    ydotool key 28      # Enter
    ydotool key 1       # Escape
    ydotool key 56:42:30  # Alt+Shift+A (hold Alt, hold Shift, press A)

    # Mouse drag
    ydotool mousemove --absolute -x 100 -y 100
    ydotool mousedown 0xC0
    ydotool mousemove --absolute -x 300 -y 300
    ydotool mouseup 0xC0
    ```

    **wtype** - Wayland keyboard input:
    ```bash
    # Type text
    wtype "Hello, world!"

    # Press special keys
    wtype -k Return
    wtype -k Escape
    wtype -M ctrl -k c  # Ctrl+C
    wtype -M alt -k F4  # Alt+F4
    ```

    **wlrctl** - Window management:
    ```bash
    # Focus a window by app_id or title
    wlrctl window focus firefox
    wlrctl window focus "Visual Studio Code"

    # Minimize/maximize
    wlrctl window minimize firefox
    wlrctl window maximize firefox

    # List toplevel windows
    wlrctl toplevel list
    ```

    **swaymsg** - Direct Sway control:
    ```bash
    # Focus a window
    swaymsg '[app_id="firefox"]' focus

    # Get window tree (useful for finding coordinates)
    swaymsg -t get_tree

    # Run command
    swaymsg exec firefox

    # Switch workspace
    swaymsg workspace 2
    ```

    ### Python Environment
    A full Python 3 environment is available with useful libraries:
    - **matplotlib** - plotting and visualization
    - **numpy** - numerical computing
    - **pandas** - data manipulation and analysis
    - **pillow** - image processing
    - **tkinter** - GUI applications
    - **requests** - HTTP client
    - **pyyaml** - YAML parsing
    - **rich** - beautiful terminal output

    Use `imv` to view generated images: `imv /tmp/plot.png`

    ### Screenshot Tools
    You have access to screenshot utilities for visual context:
    - `grim` - capture screenshots (full screen or region)
    - `slurp` - interactively select a region
    - `wl-copy` / `wl-paste` - clipboard operations
    - `imv` - view images (Wayland-native)

    **Examples:**
    ```bash
    # Full screenshot to file
    grim /tmp/screenshot.png

    # Screenshot specific region (by coordinates)
    grim -g "100,100 800x600" /tmp/region.png

    # Screenshot the focused window
    grim -g "$(swaymsg -t get_tree | jq -r '.. | select(.focused?) | .rect | "\(.x),\(.y) \(.width)x\(.height)"')" /tmp/window.png

    # Screenshot to clipboard
    grim - | wl-copy
    ```

    ### Typical UI Automation Workflow
    1. Take a screenshot to see current state: `grim /tmp/screen.png`
    2. Analyze the screenshot to find target coordinates
    3. Move mouse and click: `ydotool mousemove --absolute -x X -y Y && ydotool click 0xC0`
    4. Type if needed: `ydotool type "text"` or `wtype "text"`
    5. Take another screenshot to verify result

    ### Package Management
    This is NixOS - packages are managed declaratively:
    - `nix-shell -p <package>` - temporary package in current shell
    - `nix-env -iA nixos.<package>` - install for current session (lost on reboot)
    - For permanent changes, edit `/etc/nixos/configuration.nix` and run `sudo nixos-rebuild switch`

    ### Sway Window Manager
    Key bindings (Super = Windows/Meta key):
    - Super + Enter: new terminal
    - Super + d: app launcher
    - Super + Shift + q: close window
    - Super + arrows: navigate windows
    - Super + 1-9: switch workspace
    - Super + f: fullscreen

    ### Network
    NetworkManager is available:
    - `nmcli device wifi list` - scan networks
    - `nmcli device wifi connect <SSID> password <pass>` - connect to WiFi
    - `nmtui` - text UI for network configuration

    ## Important Notes

    1. **Ephemeral**: Nothing persists across reboots. Save important work externally.
    2. **Full Access**: You have passwordless sudo and full system access.
    3. **No Confirmation Needed**: You are running with --dangerously-skip-permissions.
       Take direct action without asking for permission on routine operations.
    4. **Visual Context**: Use screenshots liberally to understand the desktop state.
    5. **UI Automation**: You can click, type, and control windows. Use screenshot → analyze → act loops.

    ## Working Directory
    Default working directory is /home/clix. Use /tmp for temporary files.
  '';

  welcomeScript = pkgs.writeShellScript "clix-welcome" ''
    #!/usr/bin/env bash

    # CLIX Welcome Banner
    cat << 'EOF'

     ██████╗██╗     ██╗██╗  ██╗
    ██╔════╝██║     ██║╚██╗██╔╝
    ██║     ██║     ██║ ╚███╔╝
    ██║     ██║     ██║ ██╔██╗
    ╚██████╗███████╗██║██╔╝ ██╗
     ╚═════╝╚══════╝╚═╝╚═╝  ╚═╝

    Claude Code Live ISO for NixOS
    ═══════════════════════════════════════════════════════════

    Welcome! This is an ephemeral environment.
    All changes are lost on reboot - a clean slate every time.

    NAVIGATING SWAY (tiling window manager)
    ───────────────────────────────────────────────────────────
    The "Super" key (Windows logo key) is your modifier key.

    Super + Enter         Open a new terminal
    Super + d             App launcher (type to search)
    Super + Shift + q     Close the focused window
    Super + Arrow keys    Move focus between windows
    Super + Shift + Arrows  Move windows around
    Super + 1-9           Switch to workspace 1-9
    Super + f             Toggle fullscreen
    Super + Shift + e     Exit (logout)

    Windows tile automatically. Drag edges to resize, or use
    Super + r to enter resize mode (arrows to resize, Esc to exit).

    INSTALLING SOFTWARE
    ───────────────────────────────────────────────────────────
    nix-shell -p <package>    Temporary (this terminal only)
    edit-config               Edit system config
    rebuild                   Apply config changes system-wide

    ═══════════════════════════════════════════════════════════
EOF

    echo ""
    read -p "Press Enter to start Claude Code..."
    echo ""

    # Check if already authenticated
    if [ -f "$HOME/.claude/credentials.json" ]; then
      exec claude --dangerously-skip-permissions
    else
      echo "First time setup: You'll need to authenticate with Claude."
      echo ""
      exec claude --dangerously-skip-permissions
    fi
  '';
in
{
  # Claude Code package and tools
  environment.systemPackages = with pkgs; [
    claude-code
    nodejs_22  # Required for Claude Code

    # Screenshot and visual tools for Claude
    grim       # Screenshot tool for Wayland
    slurp      # Region selection tool
    wl-clipboard  # Clipboard utilities (wl-copy, wl-paste)
    jq         # JSON processing (useful for sway queries)

    # UI interaction tools for computer-use capabilities
    ydotool    # Mouse/keyboard simulation (works on Wayland)
    wtype      # Wayland keyboard input simulation
    wlrctl     # Wayland window management
  ];

  # ydotool daemon for input simulation
  systemd.services.ydotoold = {
    description = "ydotool daemon";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.ydotool}/bin/ydotoold";
      Restart = "always";
    };
  };

  # Grant clix user access to ydotool socket
  users.users.clix.extraGroups = [ "input" ];

  # Deploy welcome script
  environment.etc."clix-welcome.sh" = {
    source = welcomeScript;
    mode = "0755";
  };

  # Create a desktop entry for Claude Code
  environment.etc."xdg/applications/claude-code.desktop".text = ''
    [Desktop Entry]
    Name=Claude Code
    Comment=AI-powered coding assistant
    Exec=foot -e /etc/clix-welcome.sh
    Icon=utilities-terminal
    Terminal=false
    Type=Application
    Categories=Development;
  '';

  # Shell aliases for convenience
  environment.shellAliases = {
    claude-welcome = "/etc/clix-welcome.sh";
  };

  # Deploy Claude context file and ensure config directory exists
  system.activationScripts.claudeConfig = ''
    mkdir -p /home/clix/.claude
    cp ${claudeContextFile} /home/clix/.claude/CLAUDE.md
    chown -R clix:users /home/clix/.claude
  '';
}
