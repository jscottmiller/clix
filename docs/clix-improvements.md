# CLIX Quality of Life Improvements

**Date:** 2026-02-28
**Based on:** Real-world usage session — installing packages, running apps, window management.

---

## Problems Found

### 1. `rebuild` command fails — broken flake reference

The flake at `/etc/nixos/flake.nix` imports:
```nix
/run/current-system/configuration.nix
```
This path does **not exist** in the current system's store path (`/nix/store/350979b...`). The base system was built without embedding a `configuration.nix` in the output, so the flake can never evaluate.

### 2. `rebuild` doesn't pass `--impure`

Even if the file existed, `/run` is an absolute path which requires `--impure` for flake evaluation. The `rebuild` script runs:
```bash
sudo nixos-rebuild switch --flake .#clix
```
It should be:
```bash
sudo nixos-rebuild switch --flake .#clix --impure
```

### 3. `nix-env` doesn't work either

No channels are configured, so `nix-env -iA nixos.pkg` and `nixpkgs.pkg` both fail with "attribute not found."

### 4. `configuration.nix` comments are misleading

The file says `Edit this file and run 'rebuild' to apply changes` but this workflow is completely non-functional.

### 5. What actually worked

```bash
nix profile install nixpkgs#obs-studio
```
This is persistent across reboots but isn't documented anywhere in the CLIX setup. Users (and Claude) would naturally follow the `configuration.nix` + `rebuild` path and hit a wall.

---

## Recommended Fixes for the CLIX Image

### Fix A: Make the flake work (preferred)

The base system configuration needs to be available at a stable path. Options:

1. **Embed the base config in the store and symlink it:**
   During image build, copy the base `configuration.nix` to a known store path and create a symlink:
   ```bash
   ln -s /nix/store/<hash>-clix-base-config/configuration.nix /etc/nixos/base-configuration.nix
   ```
   Then reference it in the flake as a relative import or use `builtins.path`.

2. **Ship the base config as a regular file:**
   Place a copy of the base system config at `/etc/nixos/base-configuration.nix` (a real file, not a store symlink). Update the flake to:
   ```nix
   modules = [
     ./base-configuration.nix
     ./configuration.nix
   ];
   ```
   This avoids the `/run` path entirely and works in pure evaluation mode.

3. **Use `--impure` in the rebuild script** as a quick fix:
   ```bash
   sudo nixos-rebuild switch --flake .#clix --impure
   ```
   This alone doesn't fix the missing file, but it's needed regardless if absolute paths are used.

### Fix B: Make `nix-env` work as a fallback

Add a channel so `nix-env -iA nixpkgs.obs-studio` works:
```bash
nix-channel --add https://nixos.org/channels/nixos-unstable nixpkgs
nix-channel --update
```

### Fix C: Update the `rebuild` script

At minimum, add `--impure` and better error handling:
```bash
#!/usr/bin/env bash
set -e

echo "Rebuilding CLIX system..."

if [ ! -f /etc/nixos/flake.nix ]; then
  echo "Error: /etc/nixos/flake.nix not found"
  exit 1
fi

cd /etc/nixos
sudo nixos-rebuild switch --flake .#clix --impure "$@"

echo "Rebuild complete!"
```

### Fix D: Document `nix profile` as the easy path

If the flake rebuild workflow is complex to fix, at least update `configuration.nix` comments and CLAUDE.md to mention:
```bash
# To install packages permanently:
nix profile install nixpkgs#package-name

# To list installed:
nix profile list

# To remove:
nix profile remove package-name
```

---

## Priority

**Fix A option 2** (ship base config as a real file) is the cleanest solution — it makes the documented workflow actually work, requires no `--impure` flag, and is straightforward to implement in the image build process.

As a quick win, **Fix D** (document `nix profile`) costs nothing and immediately unblocks users.

---

## Additional: Sway Claude Terminal Window Rules

### 5. Claude terminal window rules don't apply and aren't wanted

The sway config has special rules for `app_id="claude-terminal"`:
```
for_window [app_id="claude-terminal"] {
    move left
    resize set width 30 ppt
    sticky enable
}
```

**Problems:**
- The rules don't appear to be applied — the terminal launches at full width, suggesting it's not using the `claude-terminal` app_id.
- Even if they worked, forcing 30% width and sticky behavior is opinionated and unwanted. Users prefer the default tiling behavior where Sway manages window placement normally.

**Recommendation:** Remove the `for_window [app_id="claude-terminal"]` block entirely. Let the Claude terminal behave like any other window. Users can tile/resize as they see fit with standard Sway keybindings.

---

## Claude Code Permissions (`~/.claude/settings.json`)

### 6. Permission rules are too narrow, causing frequent approval prompts

The default `settings.json` ships with rules like `Bash(pkill *)`, `Bash(nix-shell *)`, etc. These only match commands that **start** with that exact word. In practice, Claude frequently runs:

- **Compound commands:** `pkill -f app; sleep 0.3; nix-shell -p pkg --run "cmd"` — doesn't match any single rule
- **sudo commands:** `sudo nixos-rebuild ...`, `sudo sed ...` — no `sudo` rule existed at all
- **Missing utilities:** `ssh-keygen`, `ssh`, `scp`, `readlink`, `uname`, `lscpu`, `which`, `type`, `sleep`, `cd`, `imv`, `lspci`, `lsusb`, `disown`

This results in constant permission prompts for routine operations, which is especially friction-heavy on a single-user system with passwordless sudo.

**Changes made:**
1. Added `Bash(sudo *)` — this is a single-user system with passwordless sudo; blocking sudo just creates friction
2. Consolidated `Bash(nix search/build/run *)` into `Bash(nix *)` — covers `nix profile`, `nix flake`, `nix develop`, etc.
3. Added missing utilities: `ssh`, `ssh-keygen`, `scp`, `readlink`, `uname`, `lscpu`, `lspci`, `lsusb`, `which`, `type`, `sleep`, `cd`, `disown`, `imv`
4. Broadened `Bash(systemctl status *)` to `Bash(systemctl *)` — no reason to limit to status-only on a user-owned system

**Recommendation for the base image:** Ship the updated permissions list. The current defaults are designed for a shared/cautious environment, not a personal AI development system where the user has full root access.

**Remaining limitation:** Compound commands (`cmd1 && cmd2`) still won't match if `cmd1` isn't in the allow list. There's no wildcard-anywhere pattern support, so the `sudo *` rule is the practical workaround — most compound commands can be prefixed with sudo or will start with an allowed command.

---

## On-Screen Keyboard (wvkbd)

### 7. Key popup/preview is annoying and can't be disabled

The on-screen keyboard (`wvkbd-mobintl` v0.19.4) shows a popup preview of each key above the keyboard when touched. This is distracting and there's no CLI flag or config option to turn it off — the behavior is hardcoded in `keyboard.c`.

**Current launch command in sway config:**
```
exec wvkbd-mobintl --hidden -L 300
```

**Recommendation:** Either:
1. Patch wvkbd upstream to add a `--no-popup` flag (remove/guard the popup drawing in `keyboard.c` lines ~633-648)
2. Ship a patched build of wvkbd in the CLIX image with the popup disabled
3. Consider switching to an alternative OSK (squeekboard, maliit) that doesn't have this behavior
