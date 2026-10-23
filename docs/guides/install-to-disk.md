# Install to Disk

## Why Special Configuration?

CLIX ships as a raw disk image sized for a USB stick, and several of its
defaults are deliberately tuned for removable media:

- `fileSystems."/"` and `fileSystems."/boot"` mount **by label**
  (`CLIX-ROOT`, `ESP`) so one image boots on any machine.
- `boot.loader.efi.canTouchEfiVariables = false`, so systemd-boot never writes
  the host's NVRAM and the stick stays portable.
- Root is mounted with `x-systemd.device-timeout=0` and the kernel gets
  `rootwait`, because USB enumeration is slow.

Copying the image onto an internal disk with `dd` carries all of that over, and
two of the three then work against you. Label-based mounting becomes ambiguous
the moment an installed disk and a CLIX stick are both attached — the labels are
identical and which one the kernel picks is undefined. And with EFI variable
writes disabled, the installed system never registers a boot entry; it only
boots at all because systemd-boot also writes the removable-media fallback at
`EFI/BOOT/BOOTX64.EFI`.

`clix-install` handles both, so an installed system is a first-class install
rather than a cloned stick.

Running from a USB stick is also the single largest performance constraint on
CLIX. A typical USB 3 flash drive sustains single-digit MB/s on the small random
reads that dominate Nix store access, against hundreds of MB/s for an NVMe SSD.
Installing to an internal disk is usually a much larger improvement than any
amount of software tuning.

## Usage

`clix-install` is included in the system; no configuration is needed.

```bash
# See what would happen without touching the disk
sudo clix-install --dry-run /dev/nvme0n1

# Install, giving root 100G and the remainder to an encrypted /home
sudo clix-install --root-size 100G --migrate-home /dev/nvme0n1
```

List candidate disks by running it with no target:

```bash
sudo clix-install
```

### Options

| Option | Default | Effect |
|---|---|---|
| `--root-size SIZE` | `80G` | Size of `CLIX-ROOT` |
| `--esp-size SIZE` | `1G` | Size of the ESP |
| `--public-size SIZE` | `2G` | Size of `CLIX-PUBLIC` |
| `--no-encrypted-home` | off | Skip LUKS `CLIX-HOME`; root takes the rest |
| `--migrate-home` | off | `rsync` the current `/home` into the new home |
| `--dry-run` | off | Print the plan and exit |
| `--yes` | off | Skip the interactive confirmation |

Sizes accept `sgdisk` suffixes (`K`, `M`, `G`, `T`).

## Partition Layout

The layout mirrors `scripts/build-image.sh`, including putting `CLIX-PUBLIC`
first so Windows and macOS mount it by default rather than the ESP:

| # | Label | Filesystem | Size |
|---|---|---|---|
| 1 | `CLIX-PUBLIC` | FAT32 | `--public-size` |
| 2 | `ESP` | FAT32 | `--esp-size` |
| 3 | `CLIX-ROOT` | ext4 | `--root-size` |
| 4 | `CLIX-HOME` | LUKS2 + ext4 | remainder |

The ESP defaults to 1G rather than the image's 512M because
`live-system.nix` sets `configurationLimit = 10`, and ten generations of kernel
and initrd do not comfortably fit in 512M.

## What It Writes

The installer copies the **running** system closure rather than building a new
one, so the installed system is exactly what you were using. Afterwards it:

1. Seeds `/etc/nixos/configuration.nix` from the live system, so your
   customizations survive. Everything else under `/etc/nixos` is managed by
   `environment.etc` and is recreated by activation.
2. Copies `/etc/clix/user` and `/etc/clix/.setup-complete`, so the first-boot
   wizard does not run again, and points `/etc/clix/home-device` at the new LUKS
   container.
3. Generates `/etc/nixos/installed-disk.nix`, which pins `/` and `/boot` to
   UUIDs with `lib.mkForce` and enables `canTouchEfiVariables`. Both flakes
   import it when present, and `clix-apply` preserves it across CLIX updates
   alongside `configuration.nix`.
4. Runs `nixos-rebuild boot` inside the target so the installed generation
   mounts by UUID from the very first boot.
5. Verifies the ESP has systemd-boot, that boot entries were generated, that the
   system profile resolves, and that the generated entry really references the
   new root UUID.

## Safety

The installer refuses to erase any disk that currently backs a mounted
filesystem, which is what stops it eating the stick it is running from. It
reports every such mount, including LUKS mappers and the `/nix/store` bind
mount. The disk holding `/` is additionally checked on its own, so a regression
in the general check cannot be fatal. It also requires UEFI, rejects partitions
passed where a whole disk is expected, and requires you to type the disk name to
confirm.

## Post-Install

1. Reboot and pick the new disk in your firmware's boot menu.
2. Keep the CLIX USB until the install is proven.
3. Once satisfied, the stick can be reused — the installed system does not
   depend on it.

## Troubleshooting

**The in-target rebuild failed.** The system is still installed and bootable,
but mounts by label. Boot it with the CLIX USB removed, then run `rebuild` to
apply the UUID pins.

**Firmware does not list the new disk.** The in-target rebuild is what registers
the NVRAM entry. If it did not run, boot once via the fallback path (often
offered as "UEFI OS" or the disk name) and run `rebuild`.

**Two CLIX disks attached and the wrong one boots.** Expected before the UUID
pins are applied, since both carry the `CLIX-ROOT` label. Boot with only one
attached and run `rebuild`.

**`/home` does not unlock.** Check that `/etc/clix/home-device` points at the
new LUKS container:

```bash
cat /etc/clix/home-device
sudo cryptsetup luksUUID /dev/nvme0n1p4
```
