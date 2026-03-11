# Steam

## Why Special Configuration?

Steam requires an FHS (Filesystem Hierarchy Standard) compatibility environment. NixOS doesn't follow FHS by default, so Steam must be enabled via system configuration which sets up:

- A bubblewrap FHS sandbox wrapper
- 32-bit graphics drivers (many games are 32-bit)
- Proper library paths for game binaries

A simple `nix profile install nixpkgs#steam` will not work.

## Configuration

Add to `/etc/nixos/configuration.nix`:

```nix
{ config, pkgs, lib, ... }:

{
  # Steam with FHS sandbox and 32-bit graphics support
  programs.steam.enable = true;
  programs.steam.remotePlay.openFirewall = true;  # Optional: for streaming
  hardware.graphics.enable32Bit = true;

  # If you have an NVIDIA GPU, also add:
  # hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable;
}
```

## Installation Steps

1. Edit the configuration:
   ```bash
   # Claude can edit directly, or use:
   edit-config
   ```

2. Add the configuration above

3. Rebuild the system:
   ```bash
   rebuild
   ```

   If rebuild fails with missing store paths, update the flake first:
   ```bash
   sudo nix flake update /etc/nixos
   rebuild
   ```

4. Launch Steam:
   ```bash
   steam
   ```

## Troubleshooting

### "Missing 32-bit libraries"
Ensure `hardware.graphics.enable32Bit = true;` is in your config and rebuild.

### Steam doesn't launch / black screen
Check if you need proprietary graphics drivers. For NVIDIA:
```nix
services.xserver.videoDrivers = [ "nvidia" ];
hardware.nvidia.modesetting.enable = true;
```

### Game crashes immediately
Some games need additional libraries. Try running from terminal to see errors:
```bash
steam-run ./game-binary
```

### Proton/Wine games don't work
Enable Steam Play for all titles in Steam settings, or add:
```nix
programs.steam.gamescopeSession.enable = true;
```
