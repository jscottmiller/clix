{ config, pkgs, lib, ... }:

let
  # CLAUDE.md context file for Claude Code
  claudeContextFile = pkgs.writeText "CLAUDE.md" ''
    # CLIX Environment Context

    You are running inside CLIX (Claude Code Live ISO), a persistent NixOS-based
    environment designed specifically for AI-assisted development and system tasks.

    ## Environment Overview

    - **OS**: NixOS (unstable channel)
    - **Display**: Sway (Wayland tiling window manager)
    - **Terminal**: foot
    - **User**: Custom (created at first boot, passwordless sudo enabled)
    - **Persistence**: Full - changes to the root filesystem persist across reboots

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
    Python 3 is available with common packages pre-installed:
    - **matplotlib** - plotting and visualization
    - **numpy** - numerical computing
    - **pandas** - data manipulation
    - **pillow** - image processing
    - **requests** - HTTP client
    - **tkinter** - GUI applications
    - **pyyaml** - YAML parsing
    - **rich** - pretty terminal output

    For additional packages, use nix-shell:
    ```bash
    nix-shell -p python3Packages.scipy python3Packages.scikit-learn
    ```

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
    This is NixOS - always use nix for packages, never pip/npm/cargo install globally.

    **Temporary (current shell only):**
    ```bash
    nix-shell -p nodejs ripgrep ffmpeg    # Get packages for current shell
    ```

    **Quick install (survives reboot):**
    ```bash
    nix profile install nixpkgs#obs-studio   # Install a package
    nix profile list                          # List installed packages
    nix profile remove obs-studio             # Remove a package
    ```

    **Declarative install (the NixOS way):**
    ```bash
    # Edit /etc/nixos/configuration.nix (you have write permission)
    # Add packages to environment.systemPackages, then:
    rebuild
    ```

    **If rebuild fails with missing store paths:**
    The flake.lock pins a specific nixpkgs version from when CLIX was built.
    If that version is stale, update it first:
    ```bash
    sudo nix flake update /etc/nixos
    rebuild
    ```

    **When to use which:**
    - `nix profile install` - Quick, simple packages (most CLI tools, apps)
    - `edit-config` + `rebuild` - Packages needing system integration (Steam, Docker, etc.)

    **Special packages requiring system config:**
    Some packages need `programs.X.enable = true` in configuration.nix.
    See `/etc/nixos/docs/packages/` for detailed guides (Steam, Docker, etc.).

    Quick examples:
    ```nix
    programs.steam.enable = true;       # Gaming (see docs/packages/steam.md)
    virtualisation.docker.enable = true; # Containers
    ```

    **Search for packages:**
    ```bash
    nix search nixpkgs <name>
    ```

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

    ### Public Partition
    The CLIX-PUBLIC partition is mounted at `/mnt/public`. This FAT32 partition is:
    - **Readable from Windows/Mac** - mount the USB to access files
    - **Shared storage** - place files here to access from other computers
    - **WiFi config staging** - add `.nmconnection` files to `clix/network/`
    - **NOT encrypted** - don't store sensitive data here

    Use for transferring files, scripts, or data between CLIX and other systems.

    ### Installing to Local Disk
    CLIX can be installed to an internal drive. Tools available:
    - `parted` / `sgdisk` - partition the target disk
    - `mkfs.vfat` - format EFI partition (FAT32)
    - `mkfs.ext4` - format root partition
    - `nixos-generate-config` - generate hardware config
    - `nixos-install` - install NixOS to mounted root

    **Typical workflow:**
    ```bash
    # 1. Identify target disk
    lsblk

    # 2. Partition (example: /dev/nvme0n1)
    sudo parted /dev/nvme0n1 -- mklabel gpt
    sudo parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 512MiB
    sudo parted /dev/nvme0n1 -- set 1 esp on
    sudo parted /dev/nvme0n1 -- mkpart primary 512MiB 100%

    # 3. Format
    sudo mkfs.fat -F 32 -n ESP /dev/nvme0n1p1
    sudo mkfs.ext4 -L nixos /dev/nvme0n1p2

    # 4. Mount
    sudo mount /dev/nvme0n1p2 /mnt
    sudo mkdir -p /mnt/boot
    sudo mount /dev/nvme0n1p1 /mnt/boot

    # 5. Generate and install
    sudo nixos-generate-config --root /mnt
    # Edit /mnt/etc/nixos/configuration.nix as needed
    sudo nixos-install
    ```

    ## Session Journal

    Maintain a journal to preserve context across sessions. Write observations,
    user preferences, project notes, and useful context.

    **Location:** `~/.clix/journal/YYYY-MM/DD.md`

    **At session start:**
    ```bash
    # Read recent entries for context
    rg -l . ~/.clix/journal/ 2>/dev/null | tail -5 | xargs cat 2>/dev/null
    ```

    **During/after session:**
    ```bash
    # Create today's entry (append mode)
    mkdir -p ~/.clix/journal/$(date +%Y-%m)
    cat >> ~/.clix/journal/$(date +%Y-%m)/$(date +%d).md << 'EOF'

    ## Session $(date +%H:%M)
    - [observations, preferences learned, project context, etc.]
    EOF
    ```

    **Search past entries:**
    ```bash
    rg "pattern" ~/.clix/journal/
    ```

    Keep entries concise. Focus on: user preferences, project context, learned patterns,
    unfinished tasks, and anything useful for future sessions.

    ## Important Notes

    1. **Persistent Storage**: Changes to the filesystem persist across reboots. This includes
       installed packages (via nix profile), configuration changes, and user files.
    2. **Full Access**: You have passwordless sudo and full system access.
    3. **Pre-approved Commands**: Common shell and development commands are pre-approved in
       ~/.claude/settings.json. You can run git, nix, npm, python, and standard Unix tools
       without confirmation. Edit settings.json to customize permissions.
    4. **Visual Context**: Use screenshots liberally to understand the desktop state.
    5. **UI Automation**: You can click, type, and control windows. Use screenshot → analyze → act loops.
    6. **Editing System Files**: Files like `/etc/nixos/configuration.nix` are owned by root.
       Use `sudo tee` via Bash to write them:
       ```bash
       echo 'content' | sudo tee /etc/nixos/configuration.nix
       # Or for appending:
       echo 'programs.steam.enable = true;' | sudo tee -a /etc/nixos/configuration.nix
       ```

    ## Working Directory
    Default working directory is your home folder. Use /tmp for temporary files.
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

    Welcome! Changes to this system persist across reboots.
    Your files, packages, and credentials are saved to disk.

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
    if [ ! -f "$HOME/.claude/.credentials.json" ]; then
      echo "First time setup: You'll need to authenticate with Claude."
      echo ""
    fi

    # Handle shutdown signals gracefully
    trap 'echo "Shutting down..."; exit 0' SIGTERM SIGINT SIGHUP

    # Run Claude in a loop - restarts if it exits or is closed
    # Permissions are configured via ~/.claude/settings.json
    while true; do
      claude
      EXIT_CODE=$?
      # Exit if claude was killed by signal (128+signal) or shutdown is happening
      [ $EXIT_CODE -gt 128 ] && exit 0
      echo ""
      echo "Claude exited. Restarting in 2 seconds... (Ctrl+C to stop)"
      sleep 2 &
      wait $! 2>/dev/null || exit 0  # Exit if sleep is interrupted
    done
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
    wtype      # Wayland keyboard input simulation
    wlrctl     # Wayland window management
    # ydotool installed via programs.ydotool.enable below
  ];

  # ydotool for input simulation (handles daemon + socket permissions)
  programs.ydotool.enable = true;

  # Grant setup user access to ydotool socket
  # (The real user created at first boot is added to ydotool group by useradd)
  users.users.setup.extraGroups = [ "ydotool" ];

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

  # Deploy Claude context file to /etc for first-boot wizard to copy
  environment.etc."claude-context/CLAUDE.md" = {
    source = claudeContextFile;
    mode = "0644";
  };

  # NOTE: CLAUDE.md deployment is handled in:
  # - First boot: modules/first-boot-setup.nix (in the wizard)
  # - Subsequent boots: modules/first-boot-setup.nix (in autostartScript, after encrypted home unlock)
}
