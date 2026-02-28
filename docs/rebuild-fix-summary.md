# CLIX Rebuild Workflow Fix

## The Problem

The `rebuild` command doesn't work. Users (and Claude) naturally try:

```bash
edit-config    # Opens /etc/nixos/configuration.nix
rebuild        # Fails!
```

### Why It Fails

1. **Missing file**: The flake at `/etc/nixos/flake.nix` imports `/run/current-system/configuration.nix`, but this path doesn't exist. The base system config was never embedded in the image.

2. **Missing --impure flag**: Even if the file existed, `/run` is an absolute path requiring `--impure` for flake evaluation.

## Current State

- `/etc/nixos/flake.nix` - exists, references non-existent file
- `/etc/nixos/configuration.nix` - exists, user-editable layer
- `/run/current-system/configuration.nix` - **does not exist**
- `rebuild` script runs `nixos-rebuild switch --flake .#clix` (no --impure)

## Proposed Fix

Ship the base system configuration as a real file alongside the user config:

```
/etc/nixos/
├── flake.nix              # Flake definition
├── base-configuration.nix # NEW: Base system (read-only reference)
└── configuration.nix      # User customizations
```

### Changes Required

**1. Update flake.nix to import both configs:**

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }: {
    nixosConfigurations.clix = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./base-configuration.nix  # System base (from image build)
        ./configuration.nix       # User customizations
      ];
    };
  };
}
```

**2. Create base-configuration.nix during image build:**

This file should contain the core CLIX modules that make the system work:
- All the modules from modules/*.nix
- Hardware detection
- Boot configuration

**3. Update rebuild script to add --impure (optional safety net):**

```bash
sudo nixos-rebuild switch --flake .#clix --impure
```

## Impact

- `rebuild` command works as documented
- Users can add packages to configuration.nix and rebuild
- Claude can help users customize their system
- Matches what configuration.nix comments promise

## Questions to Consider

1. Should base-configuration.nix be a copy of the modules, or import them from a store path?
2. How do we generate base-configuration.nix during the image build?
3. Should we symlink to store paths or copy actual files?

## Alternative: Document nix profile only

If fixing rebuild is complex, we could:
- Remove the rebuild/configuration.nix workflow entirely
- Only document `nix profile install` for permanent packages
- Simpler but less "NixOS-like"
