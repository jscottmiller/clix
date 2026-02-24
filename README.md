# CLIX - Claude Code Live ISO for NixOS

> *"Fight for the users."*

A bootable NixOS USB that boots into a minimal Sway desktop running Claude Code. Users "prompt their desktop into existence."

---

> **WARNING: CLIX runs Claude Code with `--dangerously-skip-permissions`**
>
> This means Claude can execute ANY command without asking for confirmation - including installing software, modifying files, running scripts, and accessing the network. This is intentional for the "prompt your desktop into existence" experience, but you should understand the implications:
>
> - **Claude has full system access** with passwordless sudo
> - **No confirmation prompts** for file edits, bash commands, or other actions
> - **Only use on isolated systems** - CLIX is designed for dedicated USB drives
>
> Do not use CLIX for sensitive work or on systems with access to sensitive resources.

---

## Features

- **Persistent**: Changes to the root filesystem survive reboots
- **Minimal**: git, curl, vim - prompt Claude for everything else
- **Live rebuild**: Edit config and `nixos-rebuild switch` without rebooting
- **Sway desktop**: Wayland tiling compositor with auto-login
- **Pre-configured data partition**: Add WiFi and Claude credentials before booting

## Quick Start

### Prerequisites

**On NixOS**: You're good to go.

**On Debian/Ubuntu/other Linux**:

```bash
# Install Nix (multi-user daemon mode)
sh <(curl -L https://nixos.org/nix/install) --daemon

# Log out and back in, then enable flakes
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

Nix installs to `/nix` and doesn't touch your system packages. To uninstall later: `sudo rm -rf /nix`.

### Build the Disk Image

```bash
./scripts/build-iso.sh
```

Or directly:

```bash
nix build .#image
```

The disk image will be at `result/clix.img`.

### Test in VM

```bash
./scripts/test-vm.sh
```

Requires QEMU, KVM, and OVMF. Override defaults with environment variables:

```bash
CLIX_MEMORY=8G CLIX_CPUS=4 ./scripts/test-vm.sh
```

### Write to USB

```bash
./scripts/write-usb.sh /dev/sdX
```

**Warning**: This erases the target device. The script has safety checks but double-check your device path.

## Pre-configuring WiFi and Claude Credentials

The disk image includes a `CLIX-DATA` partition (FAT32) that you can mount on any computer (Windows, Mac, Linux) to add configuration before booting.

After writing to USB, mount the `CLIX-DATA` partition and add:

### WiFi Regulatory Domain (Required)

Create `network/regdomain` containing your 2-letter country code:

```
US
```

This is required for WiFi to work. Common codes: US, GB, DE, FR, JP, AU, CA.

### WiFi Configuration

Create `network/wifi.nmconnection`:

```ini
[connection]
id=MyWiFi
type=wifi

[wifi]
ssid=MyNetworkName

[wifi-security]
key-mgmt=wpa-psk
psk=MyPassword

[ipv4]
method=auto

[ipv6]
method=auto
```

### Claude Authentication

On first boot, run `claude` and sign in through Firefox. Your credentials will be saved for future sessions.

## Usage

On boot, you'll land in a Sway desktop with a terminal showing the CLIX welcome screen. Press Enter to start Claude Code.

### Keybindings

The **Super key** (Windows logo key) is your modifier.

| Key | Action |
|-----|--------|
| `Super+Enter` | New terminal |
| `Super+c` | New Claude Code terminal |
| `Super+d` | App launcher (wofi) |
| `Super+Shift+q` | Close window |
| `Super+Arrow keys` | Move focus |
| `Super+Shift+Arrows` | Move windows |
| `Super+1-9` | Switch workspace |
| `Super+Shift+1-9` | Move window to workspace |
| `Super+f` | Fullscreen |
| `Super+r` | Resize mode (arrows to resize, Esc to exit) |
| `Super+Shift+e` | Exit Sway |

### Installing Packages

Temporary (current shell only):
```bash
nix-shell -p python3 nodejs rustc
```

Persistent (survives reboots):
```bash
edit-config    # Opens /etc/nixos/configuration.nix
# Add packages to environment.systemPackages
rebuild        # Applies changes
```

## Project Structure

```
clix/
├── flake.nix                 # Main flake definition
├── modules/
│   ├── base.nix              # Essential packages, user, sudo
│   ├── sway.nix              # Sway + greetd auto-login
│   ├── claude-code.nix       # Claude Code + welcome script
│   ├── live-system.nix       # Live rebuild support
│   └── data-partition.nix    # CLIX-DATA partition import
├── config/
│   ├── sway/config           # Sway keybindings
│   └── waybar/               # Status bar config
└── scripts/
    ├── build-iso.sh          # Build disk image (or ISO with --iso)
    ├── test-vm.sh            # Test in QEMU
    └── write-usb.sh          # Write to USB drive
```

## Customization

Edit the modules in `modules/` to customize:

- `base.nix`: Default packages, user settings, fonts
- `sway.nix`: Desktop environment, keybindings
- `claude-code.nix`: Welcome message, auto-start behavior
- `live-system.nix`: Live rebuild configuration
- `data-partition.nix`: Data import behavior

## Building ISO Instead

If you prefer an ISO (e.g., for CD/DVD or compatibility):

```bash
./scripts/build-iso.sh --iso
# or
nix build .#iso
```

Note: The ISO doesn't include the data partition feature.

## License

MIT
