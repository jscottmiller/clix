# CLIX First Boot Redesign Plan

## Overview

Transform CLIX from "create partitions at first boot" to "expand and configure at first boot" with proper user creation and encrypted home.

## Target Architecture

**Image (baked in at build time):**
```
[ ESP ] [ CLIX-DATA (FAT32) ] [ NixOS root ]
  512MB      512MB               ~8GB
```

**First boot flow:**
1. Boots into setup mode (minimal auto-login session)
2. Wizard collects: username, password, space allocation
3. System: expands root, creates encrypted home, creates user, configures autologin
4. Reboot into normal operation

**Normal boot flow:**
1. LUKS password prompt (unlocks home)
2. Autologin to user session

---

## Phase 1: Custom Image Generation

**Goal:** Build an image with three partitions baked in.

**Change:** Create custom image build script that:
1. Builds NixOS system closure
2. Creates GPT disk image with:
   - **ESP** (~512MB, FAT32, EFI boot)
   - **CLIX-DATA** (~512MB, FAT32, labeled, pre-populated with README + directory structure)
   - **NixOS root** (~8GB, ext4, labeled CLIX-ROOT)
3. Installs bootloader and system

**Files:**
- `scripts/build-image.sh` - Custom image builder
- `flake.nix` - Update package definition

---

## Phase 2: Setup Mode Boot Flow

**Goal:** First boot enters a setup wizard, subsequent boots autologin.

**Approach:**
- Create a `setup` user that exists in the base image
- Greetd autologins to `setup` user on first boot
- Setup wizard runs automatically in that session
- After setup: create real user, update greetd, reboot

**Detection:** Check for marker file `/etc/clix/.setup-complete`

**Files:**
- `modules/base.nix` - Add `setup` user
- `modules/sway.nix` - Conditional autostart
- `modules/first-boot-setup.nix` - Rewrite

---

## Phase 3: First Boot Wizard (Rewrite)

**Goal:** Collect user info, configure system.

**Wizard flow:**
1. Welcome + username/password input
2. Storage allocation slider (root expansion vs encrypted home)
3. Progress display during setup

**Actions performed:**
1. Expand root partition (`growpart` + `resize2fs`)
2. Create LUKS partition in remaining space
3. Format LUKS container as ext4 (label: CLIX-HOME)
4. Create user account (`useradd`, set password)
5. Update greetd config for autologin
6. Create marker file
7. Reboot

---

## Phase 4: LUKS Unlock at Boot

**Goal:** Prompt for password at boot, then autologin.

**Flow:**
1. System boots (root mounts fine, no encryption)
2. `clix-unlock-home.service` runs before display manager
3. Prompts for LUKS password via `systemd-ask-password`
4. Opens LUKS container, mounts `/home`
5. Display manager starts, autologin occurs

---

## Phase 5: Dynamic User Configuration

**Goal:** User created at runtime persists across reboots.

**Approach:**
- `users.mutableUsers = true`
- User created with `useradd` at first boot
- Greetd config updated to autologin correct user

---

## Phase 6: Cleanup & Polish

- Remove old wizard logic
- Update CLIX-DATA import script (partition now always exists)
- Add `clix-reset` script for factory reset
- Testing

---

## File Summary

| File | Action |
|------|--------|
| `scripts/build-image.sh` | Create - custom image builder |
| `flake.nix` | Modify - use custom builder |
| `modules/base.nix` | Modify - setup user, mutableUsers |
| `modules/first-boot-setup.nix` | Rewrite - new wizard |
| `modules/encrypted-home.nix` | Modify - boot unlock flow |
| `modules/data-partition.nix` | Simplify - partition always exists |
| `modules/sway.nix` | Modify - conditional autostart |

---

## Status

- [x] Phase 1: Custom Image Generation
- [x] Phase 2: Setup Mode Boot Flow
- [x] Phase 3: First Boot Wizard
- [x] Phase 4: LUKS Unlock at Boot
- [x] Phase 5: Dynamic User Configuration
- [x] Phase 6: Cleanup & Polish

## Implementation Complete

All phases implemented. Files modified:
- `scripts/build-image.sh` - Created custom image builder
- `flake.nix` - Simplified, removed nixos-generators dependency
- `modules/base.nix` - Added setup user, enabled mutableUsers
- `modules/sway.nix` - Dynamic user selection via greetd wrapper
- `modules/first-boot-setup.nix` - Complete rewrite with new wizard
- `modules/encrypted-home.nix` - Updated for boot-time LUKS unlock
- `modules/data-partition.nix` - Simplified for always-present partition
- `modules/claude-code.nix` - Updated for dynamic user
