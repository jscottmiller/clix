# CLIX - Claude Code Live ISO for NixOS

From the human: Hello! CLIX is my attempt to make a minimal Linux live OS. I've been thinking about what an AI first operating system might look like and, lacking a team of developers, I created a small NixOS environment that boots into Claude Code (in a sense replacing the shell) as a way to toy with this idea. If you think this is fun, interesting, buggy, horrible, whatever, please feel free to politely contribute or reach out. The rest of this project was prompted into existance so caveat emptor.

---

CLIX is a single-user bootable USB system built on NixOS that launches directly into a Sway desktop with Claude Code ready to go. The system automatically logs in as `clix`, with `/home/clix` mounted from a LUKS-encrypted volume—the idea is that you carry your encrypted data on a flash drive or other portable storage. Everything is persistent: installed packages, configuration changes, and your files all survive reboots.

The system includes a FAT32 partition (`CLIX-PUBLIC`) that's readable from Windows and macOS, giving you an easy way to transfer files, pre-configure WiFi networks, or stage Claude settings before booting. Note that the system partition and CLIX-PUBLIC are *not* encrypted—only your home directory is protected. Claude operates with passwordless sudo and pre-approved permissions for common development tasks—this is intentional for a dedicated AI development environment, but you should use CLIX on its own USB drive rather than alongside sensitive data.

---

> **Note: CLIX comes with permissive Claude Code settings**
>
> A default `settings.json` pre-approves common development commands (git, nix, npm, python, standard Unix tools) so Claude can work efficiently without constant confirmation prompts. You should understand the implications:
>
> - **Claude has full system access** with passwordless sudo
> - **Many commands pre-approved** - edit `~/.claude/settings.json` to customize
> - **Designed for dedicated USB drives** - CLIX is an isolated development environment
>
> Edit `clix/claude/settings.json` on the CLIX-PUBLIC partition to customize permissions before first boot.

---

## Features

- **Dynamic first-boot setup**: Wizard partitions your USB based on available space
- **Encrypted /home**: Optional LUKS encryption for credentials and data
- **Persistent**: Changes to the root filesystem survive reboots
- **Minimal**: git, curl, vim - prompt Claude for everything else
- **Live rebuild**: Edit config and `nixos-rebuild switch` without rebooting
- **Sway desktop**: Wayland tiling compositor with auto-login
- **Data partition**: Add WiFi and Claude credentials via Windows-visible FAT32 partition

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
./scripts/docker-build.sh
```

This builds the image in a Docker container - no Nix installation or root access required on the host. The build uses a `clix-nix-cache` volume to cache the Nix store between builds.

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

After the first-boot wizard runs, your USB will have a `CLIX-PUBLIC` partition (FAT32) that you can mount on any computer (Windows, Mac, Linux) to add configuration.

Mount the `CLIX-PUBLIC` partition and add:

### WiFi Regulatory Domain (Required)

Create `clix/network/regdomain` containing your 2-letter country code:

```
US
```

This is required for WiFi to work. Common codes: US, GB, DE, FR, JP, AU, CA.

### WiFi Configuration

Create `clix/network/wifi.nmconnection`:

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

## First Boot Setup

On first boot, after the desktop loads, you'll see a setup wizard that:

1. **Creates your user account**: Username and password
2. **Allocates storage**: Choose how to split remaining USB space between root expansion and encrypted home
3. **Sets up encryption**: Your home directory is encrypted with your password
4. **Reboots**: System is ready to use

### Subsequent Boots

If you chose encryption:
- You'll be prompted for your password on each boot
- After entering the password, the system boots normally

If you skipped encryption, you can encrypt later with:
```bash
sudo clix-encrypt-home
```

### Manual Setup

If you skipped setup on first boot, run:
```bash
sudo clix-setup
```

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

**Temporary (current shell only):**
```bash
nix-shell -p python3 nodejs rustc
```

**Quick install (persistent, survives reboots):**
```bash
nix profile install nixpkgs#obs-studio
nix profile list      # List installed
nix profile remove obs-studio
```

**Declarative install (for packages needing system integration):**
```bash
# Edit /etc/nixos/configuration.nix (you have write permission)
# Add packages to environment.systemPackages, then:
rebuild
```

Some packages like Steam and Docker require system-level configuration. See `docs/guides/` for detailed guides.

## Project Structure

```
clix/
├── flake.nix                 # Main flake definition
├── modules/
│   ├── base.nix              # Essential packages, user, sudo
│   ├── sway.nix              # Sway + greetd auto-login
│   ├── claude-code.nix       # Claude Code + welcome script
│   ├── live-system.nix       # Live rebuild support
│   ├── data-partition.nix    # CLIX-PUBLIC partition import
│   ├── encrypted-home.nix    # LUKS encryption for /home
│   └── first-boot-setup.nix  # First-boot encryption wizard
├── config/
│   ├── nixos/                # Flake shipped to /etc/nixos
│   ├── sway/config           # Sway keybindings
│   └── waybar/               # Status bar config
├── docs/
│   └── packages/             # Package installation guides (Steam, etc.)
├── examples/                 # Example WiFi configs
└── scripts/
    ├── build-image.sh        # Build disk image
    ├── docker-build.sh       # Build using Docker (no root needed)
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
- `encrypted-home.nix`: LUKS encryption settings
- `first-boot-setup.nix`: First-boot wizard behavior

## Partition Layout

The CLIX disk image ships with three partitions. The first-boot wizard expands the root and optionally creates an encrypted home.

### After Writing to USB

| # | Name | Type | Size | Purpose |
|---|------|------|------|---------|
| 1 | CLIX-PUBLIC | FAT32 | 2GB | Config staging, Windows-visible |
| 2 | ESP | FAT32 | 512MB | EFI boot partition |
| 3 | CLIX-ROOT | ext4 | ~8GB | System root, /nix/store |

### After First Boot Setup

| # | Name | Type | Purpose |
|---|------|------|---------|
| 1 | CLIX-PUBLIC | FAT32 | Config staging (Windows-visible), mounted at /mnt/public |
| 2 | ESP | FAT32 | EFI boot partition |
| 3 | CLIX-ROOT | ext4 | System root (expanded to fill available space minus home) |
| 4 | CLIX-HOME | LUKS+ext4 | Encrypted user home directory |

The first-boot wizard lets you choose how to allocate remaining USB space between root expansion and encrypted home.

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for:
- Adding package installation guides
- Development setup
- Release process

## License

MIT
