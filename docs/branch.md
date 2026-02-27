# Branch: feature/first-boot-wizard

## Purpose

Add first-boot setup wizard with LUKS-encrypted home partition and dynamic user creation.

## Status

**WiFi is broken** - NetworkManager connection profiles placed on CLIX-DATA partition are not being applied. The interface shows as "unmanaged".

## Base State

- **main branch**: Working WiFi, boots successfully (commit `6ee2672`)
- **This branch**: First-boot wizard features added, but WiFi broken

## Commits on This Branch

| Commit | Description |
|--------|-------------|
| `82394cb` | Add dynamic first-boot partition wizard |
| `bf7c76a` | WIP: First-boot wizard with user creation |
| `befdb4e` | Add LUKS unlock and dynamic user switching for second boot |
| `937f5a5` | Fix WiFi management and improve boot process |

## Key Changes

### New Modules
- `modules/encrypted-home.nix` - LUKS unlock and /home mounting
- `modules/first-boot-setup.nix` - Zenity-based setup wizard

### Modified Modules
- `modules/live-system.nix` - Boot settings, systemd initrd option
- `modules/data-partition.nix` - Service ordering changes, NetworkManager dependencies
- `modules/base.nix` - User setup, `networking.wireless.enable` configuration
- `modules/sway.nix` - Greetd integration, autostart changes

### Build System
- `flake.nix` - Significant changes (removed nixos-generators?)
- `scripts/build-image.sh` - Manual image assembly with DATA partition

## WiFi Problem

### Expected Behavior
1. User places `*.nmconnection` file on CLIX-DATA partition
2. `clix-import-data` service copies it to `/etc/NetworkManager/system-connections/`
3. NetworkManager connects automatically

### Actual Behavior
- Interface shows as "unmanaged" (state 10)
- Connections are not applied

### Example nmconnection File
```ini
[connection]
id=Frankfurt
uuid=6f81d29f-dad7-4d26-9cc6-a3435410d616
type=wifi
autoconnect=true

[wifi]
mode=infrastructure
ssid=Frankfurt

[wifi-security]
key-mgmt=wpa-psk
psk=3128528889

[ipv4]
method=auto

[ipv6]
method=auto
```

## Previous Investigation

### What We Tried
1. Disabled standalone wpa_supplicant (`networking.wireless.enable = false`) - "plugin missing" error
2. Switched to iwd backend - still unmanaged
3. Reverted to wpa_supplicant (`networking.wireless.enable = lib.mkDefault true`) - still broken
4. Disabled systemd initrd (`boot.initrd.systemd.enable = false`) - still broken

### Suspected Causes

1. **Configuration conflict** in `base.nix`:
   ```nix
   networking.networkmanager.enable = true;
   networking.wireless.enable = lib.mkDefault true;  # standalone wpa_supplicant
   ```
   NetworkManager manages wpa_supplicant internally; the standalone service may claim devices first.

2. **Service ordering** in `data-partition.nix`:
   ```nix
   systemd.services.NetworkManager = {
     after = [ "clix-import-data.service" ];
   };
   ```
   May delay NetworkManager enough for wpa_supplicant to grab devices.

3. **nixpkgs version changes** - The flake.lock differs between main and this branch, possibly changing NetworkManager module behavior.

## Next Steps

1. Bisect the commits to find which one breaks WiFi
2. Compare NetworkManager.conf between main and this branch
3. Test with `networking.wireless.enable = false` and ensure wpa_supplicant package is available
4. Review service ordering and dependencies

## Files Changed

```
 PLAN.md                      | 150 +++
 README.md                    |  66 +-
 config/foot/foot.ini         |  29 +++
 config/sway/config           |   4 +-
 flake.lock                   |  37 ---
 flake.nix                    | 174 +--
 modules/base.nix             |  43 +-
 modules/claude-code.nix      |  28 +-
 modules/data-partition.nix   |  74 +--
 modules/encrypted-home.nix   | 180 +++
 modules/first-boot-setup.nix | 503 +++
 modules/live-system.nix      |  30 +++
 modules/sway.nix             | 189 ++-
 scripts/build-image.sh       | 331 ++-
 scripts/write-usb.sh         |  11 +-
 15 files changed, +1528, -321
```
