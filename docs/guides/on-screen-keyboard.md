# On-Screen Keyboard

## Why Special Configuration?

Touch-screen devices and tablets benefit from an on-screen keyboard. This guide sets up:

- **wvkbd** - A Wayland on-screen keyboard
- **Waybar toggle** - A button to show/hide the keyboard

## Configuration

Add to `/etc/nixos/configuration.nix`:

```nix
{ config, pkgs, lib, ... }:

{
  # On-screen keyboard
  environment.systemPackages = [ pkgs.wvkbd ];
}
```

## Installation Steps

1. Edit the configuration:
   ```bash
   edit-config
   ```

2. Add the configuration above

3. Rebuild the system:
   ```bash
   rebuild
   ```

4. Add wvkbd to sway autostart. Edit `~/.config/sway/config` and add:
   ```
   # Start on-screen keyboard (hidden by default)
   exec wvkbd-mobintl --hidden
   ```

5. Add toggle button to waybar. First, copy the config (it's a symlink by default):
   ```bash
   cp --remove-destination /etc/xdg/waybar/config ~/.config/waybar/config
   cp --remove-destination /etc/xdg/waybar/style.css ~/.config/waybar/style.css
   ```

   Edit `~/.config/waybar/config`:

   In `modules-right`, add `"custom/keyboard"` where you want the button:
   ```json
   "modules-right": ["cpu", "memory", "network", "pulseaudio", "battery", "custom/keyboard", "clock", "tray"],
   ```

   Add the module definition:
   ```json
   "custom/keyboard": {
       "format": "⌨",
       "tooltip-format": "Toggle on-screen keyboard",
       "on-click": "pkill -SIGRTMIN wvkbd-mobintl"
   },
   ```

6. Add styling to `~/.config/waybar/style.css`:
   ```css
   #custom-keyboard {
       background-color: #ffb86c;
       color: #282a36;
       border-radius: 4px;
       padding: 0 10px;
       margin: 0 4px;
       font-size: 15px;
   }

   #custom-keyboard:hover {
       background-color: #f8f8f2;
   }
   ```

7. Restart waybar to apply changes:
   ```bash
   pkill waybar; swaymsg exec waybar
   ```
   Note: `swaymsg reload` only reloads sway config, not waybar.

## Usage

- Click the ⌨ button in waybar to toggle the keyboard
- The keyboard appears at the bottom of the screen
- Tap keys to type, or drag to reposition

## Troubleshooting

### Keyboard doesn't appear
Make sure wvkbd is running:
```bash
pgrep wvkbd-mobintl || wvkbd-mobintl --hidden &
```

### Toggle button doesn't work
The signal only works if wvkbd is running. Check with `pgrep wvkbd-mobintl`.

### Keyboard layout is wrong
wvkbd-mobintl uses a mobile-friendly international layout. For other layouts:
```bash
wvkbd-mobintl --hidden -L 300 # Larger size
```

See `wvkbd-mobintl --help` for options.
