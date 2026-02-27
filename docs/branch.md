# Branch: feature/first-boot-wizard

## Purpose

Add first-boot setup wizard with LUKS-encrypted home partition and dynamic user creation.

## Status

**WiFi is FIXED** - Root cause identified and resolved.

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

## WiFi Problem (RESOLVED)

**Solution:** Build script must run as root (`sudo ./scripts/build-image.sh`) to ensure correct file ownership for NetworkManager plugins.

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

---

## Debug Log

### Session: 2026-02-26

**Goal**: Find root cause of WiFi "unmanaged" issue

**Starting point**:
- `main` at `6ee2672` = working WiFi
- `feature/first-boot-wizard` at `937f5a5` = broken WiFi
- 4 commits between them

**Approach**: Diff analysis + runtime diagnostics

#### Attempt 1: Build broken image for diagnostics

Built image from `feature/first-boot-wizard` (937f5a5) - 9.1GB

**Key diff findings** (WiFi-related):
1. `base.nix`: Changed `networking.wireless.enable` from `mkDefault true` → `mkForce false`
2. `data-partition.nix`: Added `NetworkManager.service` to `before` list
3. `live-system.nix`: Added `boot.initrd.systemd.enable = true`

**Diagnostics to run on booted image:**
```bash
nmcli device status
which wpa_supplicant
cat /etc/NetworkManager/NetworkManager.conf
journalctl -u clix-import-data
ls -la /etc/NetworkManager/system-connections/
journalctl -u NetworkManager | head -50
systemctl status wpa_supplicant
```

**Results:**

| Command | Output |
|---------|--------|
| `nmcli device status` | `wlp2s0` wifi **unavailable** (not unmanaged!) |
| `which wpa_supplicant` | `/run/current-system/sw/bin/wpa_supplicant` (exists) |
| `cat /etc/NetworkManager/NetworkManager.conf` | Correct config: `wifi.backend=wpa_supplicant`, `unmanaged-devices=null` in `[keyfile]` |
| `journalctl -u clix-import-data` | **No entries** - service didn't log/run |
| `ls /etc/NetworkManager/system-connections/` | `Frankfurt.nmconnection` present (227 bytes) |
| `journalctl -u NetworkManager` | **No entries** |
| `systemctl status wpa_supplicant` | **"Unit could not be found"** |

**Analysis:**

The problem is clear now:
1. `networking.wireless.enable = lib.mkForce false` removes the wpa_supplicant **service**
2. The wpa_supplicant **binary** exists (in systemPackages) but that's not enough
3. NetworkManager.conf says `wifi.backend=wpa_supplicant` but there's no service to use
4. Result: WiFi device shows "unavailable" because NM can't initialize the WiFi backend

**Root cause:** NetworkManager needs wpa_supplicant.service running, not just the binary

**Fix options:**
1. Set `networking.wireless.enable = true` (re-enable the service)
2. Or use iwd backend instead: `networking.networkmanager.wifi.backend = "iwd"`

#### Attempt 2: Re-enable wpa_supplicant service

Changed `base.nix`:
```nix
# Before (broken)
networking.wireless.enable = lib.mkForce false;

# After (fix)
networking.wireless.enable = lib.mkDefault true;
```

Built new image (9.1GB) - testing...

**Results (with sudo):**

| Component | Status |
|-----------|--------|
| `wpa_supplicant` | active, "Successfully initialized" |
| `NetworkManager` | active, but **plugin warnings** |
| `clix-import-data` | **SUCCESS** - found /dev/sda1, set regdomain=US, imported Frankfurt.nmconnection |
| `blkid` | CLIX-DATA on /dev/sda1, CLIX-ROOT on /dev/sda3 |
| `nmcli device status` | wlp2s0 = **unmanaged** |

**NEW FINDING - NetworkManager plugin errors:**
```
<warn> plugin: skip invalid file /nix/store/.../networkmanager-1.56.0/lib/NetworkManager/...
       file has invalid owner (should be root)
```

Multiple plugins being skipped because nix store files aren't owned by root. This may be breaking WiFi functionality.

**Service timing (correct order):**
- 06:22:04 - clix-import-data starts
- 06:22:05 - wpa_supplicant starts, clix-import-data finishes
- 06:22:08 - NetworkManager starts

Import runs BEFORE NetworkManager - ordering is correct.

#### ROOT CAUSE IDENTIFIED: File Ownership in Build Process

**The actual problem:**
```
-r-xr-xr-x 1 setup 1000 ... libnm-device-plugin-wifi.so
```

NetworkManager plugins are owned by `setup:1000` instead of `root`. NetworkManager requires plugins to be owned by root for security, so it skips them:
```
<warn> plugin: skip invalid file .../libnm-device-plugin-wifi.so
       file has invalid owner (should be root)
```

**WiFi plugin is skipped → NetworkManager can't manage WiFi → device shows "unmanaged"**

**Why this happens:**

The manual `build-image.sh` script does image assembly outside the Nix sandbox:
```bash
mkdir -p "$root_dir/nix/store"                              # Created as current user
nix copy --to "local?root=$root_dir" "$system_path"         # Copies with current user's ownership
mkfs.ext4 -d "$root_dir" root.img                           # Preserves those ownerships
```

When run as non-root, files get UID 1000 (the build user), which maps to `setup` on the booted system.

**Main branch uses nixos-generators** which builds inside a Nix derivation (sandboxed as root), so ownership is correct.

**Fix:** Run build as root:
```bash
sudo rm -rf result && sudo ./scripts/build-image.sh
```

#### Attempt 3: Build with sudo - SUCCESS

Built with `sudo ./scripts/build-image.sh`

**Result: WiFi connects successfully!**

**Fix applied:**
1. Updated `scripts/build-image.sh` to:
   - Set `NIX_CONFIG` with experimental features
   - Find nix in common paths when running via sudo
   - Warn if not running as root
   - Remove internal sudo calls (script should be run as root)
2. Updated `README.md` to document running build with sudo

**Root cause confirmed:** File ownership. When built as non-root, nix store files get UID 1000 ownership, causing NetworkManager to skip plugins for security reasons.
