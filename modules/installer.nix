{ config, pkgs, lib, ... }:

# CLIX Disk Installer
# Provides the clix-install command, which installs the running CLIX system
# onto a local disk. This is the runtime counterpart to scripts/build-image.sh:
# it lays down the same partition scheme, but sized for a real disk instead of
# a fixed image, and copies the live system closure rather than building one.
#
# Whole-disk only: the target disk is erased. UEFI only, matching
# boot.loader.systemd-boot in live-system.nix.

let
  installerDeps = with pkgs; [
    coreutils
    util-linux          # lsblk, findmnt, blkid, mount, umount, wipefs
    gptfdisk            # sgdisk
    dosfstools          # mkfs.vfat
    e2fsprogs           # mkfs.ext4
    cryptsetup
    rsync
    gnugrep
    gnused
    gawk
    systemd             # udevadm
    nixos-install-tools # nixos-install, nixos-enter
  ];

  clixInstallScript = pkgs.writeShellScriptBin "clix-install" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath installerDeps}:$PATH"

    # Defaults. CLIX-PUBLIC and ESP mirror the image layout, except the ESP is
    # 1G rather than 512M: live-system.nix sets configurationLimit = 10, and ten
    # generations of kernel + initrd do not comfortably fit in 512M.
    PUBLIC_SIZE="2G"
    ESP_SIZE="1G"
    ROOT_SIZE="80G"
    ENCRYPTED_HOME=1
    MIGRATE_HOME=0
    DRY_RUN=0
    ASSUME_YES=0
    TARGET=""

    MNT="/mnt/clix-install"
    MAPPER="clix-home-install"

    usage() {
    cat << 'USAGEEOF'
Usage: clix-install [OPTIONS] /dev/DISK

Installs the running CLIX system onto DISK. The entire disk is erased.

Options:
  --root-size SIZE      Size of CLIX-ROOT (default: 80G)
  --esp-size SIZE       Size of ESP (default: 1G)
  --public-size SIZE    Size of CLIX-PUBLIC (default: 2G)
  --no-encrypted-home   Do not create a LUKS CLIX-HOME; root takes the rest
  --migrate-home        rsync the current /home into the new home partition
  --dry-run             Print the plan and exit without touching the disk
  --yes                 Skip the interactive confirmation
  --help, -h            Show this help

Sizes accept sgdisk suffixes (K, M, G, T).

Example:
  clix-install --root-size 100G --migrate-home /dev/nvme0n1
USAGEEOF
    }

    while [[ $# -gt 0 ]]; do
      case $1 in
        --root-size)        ROOT_SIZE="$2"; shift 2 ;;
        --esp-size)         ESP_SIZE="$2"; shift 2 ;;
        --public-size)      PUBLIC_SIZE="$2"; shift 2 ;;
        --no-encrypted-home) ENCRYPTED_HOME=0; shift ;;
        --migrate-home)     MIGRATE_HOME=1; shift ;;
        --dry-run)          DRY_RUN=1; shift ;;
        --yes)              ASSUME_YES=1; shift ;;
        --help|-h)          usage; exit 0 ;;
        -*)
          echo "Unknown option: $1" >&2
          echo "Run 'clix-install --help' for usage" >&2
          exit 1
          ;;
        *)
          if [ -n "$TARGET" ]; then
            echo "Error: more than one target disk given ($TARGET, $1)" >&2
            exit 1
          fi
          TARGET="$1"; shift
          ;;
      esac
    done

    die() { echo "Error: $*" >&2; exit 1; }

    # Map a disk and partition number to a device node. Devices whose name ends
    # in a digit (nvme0n1, mmcblk0) take a "p" separator; sda-style do not.
    part_of() {
      local disk="$1" num="$2"
      case "$disk" in
        *[0-9]) echo "''${disk}p''${num}" ;;
        *)      echo "''${disk}''${num}" ;;
      esac
    }

    # Walk up the dependency tree from a device to the whole disk holding it.
    # Handles partitions and device-mapper targets (LUKS) alike.
    #
    # -r matters: without it lsblk draws tree art and the disk row comes back as
    # "|-sda" rather than "sda", so every comparison against a disk name silently
    # fails and the in-use guard below never fires.
    disk_of() {
      lsblk -rnso NAME,TYPE "$1" 2>/dev/null | awk '$2 == "disk" { print $1; exit }'
    }

    if [ "$EUID" -ne 0 ]; then
      die "clix-install must be run as root (use sudo)"
    fi

    if [ ! -d /sys/firmware/efi ]; then
      die "not booted in UEFI mode; CLIX uses systemd-boot and cannot install on legacy BIOS"
    fi

    if [ -z "$TARGET" ]; then
      usage >&2
      echo "" >&2
      echo "Available disks:" >&2
      lsblk -d -o NAME,SIZE,TRAN,MODEL >&2
      exit 1
    fi

    [ -b "$TARGET" ] || die "$TARGET is not a block device"

    TARGET_NAME="$(basename "$TARGET")"
    TARGET_TYPE="$(lsblk -ndo TYPE "$TARGET" 2>/dev/null || echo unknown)"
    if [ "$TARGET_TYPE" != "disk" ]; then
      die "$TARGET is a '$TARGET_TYPE', not a whole disk. Pass a disk such as /dev/nvme0n1, not a partition."
    fi

    # Refuse any disk currently backing a mounted filesystem. This is what keeps
    # the installer from eating the live USB it is running from.
    IN_USE=""
    while read -r src; do
      case "$src" in
        /dev/*) ;;
        *) continue ;;
      esac
      # findmnt reports bind and subpath mounts as /dev/sda3[/nix/store];
      # strip the annotation so lsblk is given a real device node.
      src="''${src%%[*}"
      d="$(disk_of "$src" || true)"
      [ -n "$d" ] || continue
      if [ "$d" = "$TARGET_NAME" ]; then
        case " $IN_USE " in
          *" $src "*) ;;
          *) IN_USE="$IN_USE $src" ;;
        esac
      fi
    done < <(findmnt -rno SOURCE | sort -u)

    if [ -n "$IN_USE" ]; then
      echo "Error: $TARGET currently backs mounted filesystems:" >&2
      for m in $IN_USE; do
        echo "  $m -> $(findmnt -rno TARGET "$m" | tr '\n' ' ')" >&2
      done
      echo "" >&2
      die "refusing to erase a disk that is in use (this is almost certainly the disk CLIX is running from)"
    fi

    # Independent second guard. The loop above is the thorough check, but it
    # depends on lsblk output parsing; if that ever breaks again the consequence
    # is erasing the running system, so the disk behind / is also compared
    # directly and cheaply.
    ROOT_SRC="$(findmnt -no SOURCE / | sed 's/\[.*//')"
    ROOT_DISK="$(disk_of "$ROOT_SRC" || true)"
    if [ -n "$ROOT_DISK" ] && [ "$ROOT_DISK" = "$TARGET_NAME" ]; then
      die "$TARGET holds the running root filesystem ($ROOT_SRC); refusing to erase it"
    fi
    if [ -z "$ROOT_DISK" ]; then
      die "could not determine which disk holds the running root filesystem; refusing to continue"
    fi

    SYSTEM_CLOSURE="$(readlink -f /run/current-system)"
    [ -d "$SYSTEM_CLOSURE" ] || die "cannot resolve /run/current-system"

    TARGET_SIZE="$(lsblk -ndo SIZE "$TARGET")"
    TARGET_MODEL="$(lsblk -ndo MODEL "$TARGET" | sed 's/ *$//')"

    echo "CLIX Disk Installer"
    echo "==================="
    echo ""
    echo "Target:   $TARGET ($TARGET_SIZE, $TARGET_MODEL)"
    echo "Closure:  $SYSTEM_CLOSURE"
    echo ""
    echo "Planned layout:"
    echo "  1  CLIX-PUBLIC  FAT32          $PUBLIC_SIZE"
    echo "  2  ESP          FAT32          $ESP_SIZE"
    if [ "$ENCRYPTED_HOME" -eq 1 ]; then
      echo "  3  CLIX-ROOT    ext4           $ROOT_SIZE"
      echo "  4  CLIX-HOME    LUKS2 + ext4   remainder"
    else
      echo "  3  CLIX-ROOT    ext4           remainder"
    fi
    echo ""
    echo "Current contents of $TARGET (to be destroyed):"
    lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL "$TARGET" || true
    echo ""

    if [ "$DRY_RUN" -eq 1 ]; then
      echo "Dry run: nothing was changed."
      exit 0
    fi

    if [ "$ASSUME_YES" -ne 1 ]; then
      echo "This ERASES ALL DATA on $TARGET, including any other operating system."
      echo "Type the disk name ('$TARGET_NAME') to confirm:"
      read -r confirm
      if [ "$confirm" != "$TARGET_NAME" ]; then
        echo "Aborted."
        exit 1
      fi
    fi

    cleanup() {
      set +e
      if mountpoint -q "$MNT/boot"; then umount "$MNT/boot"; fi
      if mountpoint -q "$MNT/home"; then umount "$MNT/home"; fi
      if mountpoint -q "$MNT"; then umount "$MNT"; fi
      if [ -b "/dev/mapper/$MAPPER" ]; then cryptsetup close "$MAPPER"; fi
      rmdir "$MNT" 2>/dev/null
    }
    trap cleanup EXIT

    echo ""
    echo "==> Partitioning $TARGET"
    wipefs -a "$TARGET" >/dev/null
    sgdisk --zap-all "$TARGET" >/dev/null

    # Partition order matches scripts/build-image.sh: CLIX-PUBLIC first so that
    # Windows and macOS mount it by default rather than the ESP.
    sgdisk -n "1:0:+$PUBLIC_SIZE" -t 1:0700 -c 1:CLIX-PUBLIC "$TARGET" >/dev/null
    sgdisk -n "2:0:+$ESP_SIZE"    -t 2:ef00 -c 2:ESP          "$TARGET" >/dev/null
    if [ "$ENCRYPTED_HOME" -eq 1 ]; then
      sgdisk -n "3:0:+$ROOT_SIZE" -t 3:8300 -c 3:CLIX-ROOT    "$TARGET" >/dev/null
      sgdisk -n "4:0:0"           -t 4:8309 -c 4:CLIX-HOME    "$TARGET" >/dev/null
    else
      sgdisk -n "3:0:0"           -t 3:8300 -c 3:CLIX-ROOT    "$TARGET" >/dev/null
    fi

    udevadm settle
    partprobe "$TARGET" 2>/dev/null || true
    udevadm settle

    PUBLIC_PART="$(part_of "$TARGET" 1)"
    ESP_PART="$(part_of "$TARGET" 2)"
    ROOT_PART="$(part_of "$TARGET" 3)"
    HOME_PART="$(part_of "$TARGET" 4)"

    for p in "$PUBLIC_PART" "$ESP_PART" "$ROOT_PART"; do
      [ -b "$p" ] || die "expected partition $p did not appear after partitioning"
    done

    echo "==> Creating filesystems"
    mkfs.vfat -F 32 -n CLIX-PUBLIC "$PUBLIC_PART" >/dev/null
    mkfs.vfat -F 32 -n ESP "$ESP_PART" >/dev/null
    mkfs.ext4 -q -F -L CLIX-ROOT "$ROOT_PART"

    if [ "$ENCRYPTED_HOME" -eq 1 ]; then
      [ -b "$HOME_PART" ] || die "expected home partition $HOME_PART did not appear"
      echo ""
      echo "==> Encrypting CLIX-HOME ($HOME_PART)"
      echo "    Choose a passphrase. You will be prompted for it at every boot."
      cryptsetup luksFormat --type luks2 --label CLIX-HOME "$HOME_PART"
      echo "    Unlocking to create the filesystem..."
      cryptsetup open "$HOME_PART" "$MAPPER"
      mkfs.ext4 -q -F -L CLIX-HOME "/dev/mapper/$MAPPER"
    fi

    echo "==> Mounting target at $MNT"
    mkdir -p "$MNT"
    mount "$ROOT_PART" "$MNT"
    mkdir -p "$MNT/boot"
    mount "$ESP_PART" "$MNT/boot"

    # Seed mutable configuration before nixos-install runs activation. The
    # initUserConfig activation script in live-system.nix only writes a default
    # configuration.nix when none exists, so placing the real one here preserves
    # the user's customizations. Everything else under /etc/nixos is managed by
    # environment.etc and is recreated by activation.
    echo "==> Seeding /etc/nixos and /etc/clix"
    mkdir -p "$MNT/etc/nixos" "$MNT/etc/clix"
    if [ -f /etc/nixos/configuration.nix ]; then
      cp /etc/nixos/configuration.nix "$MNT/etc/nixos/configuration.nix"
    fi
    for f in user .setup-complete; do
      if [ -e "/etc/clix/$f" ]; then
        cp -a "/etc/clix/$f" "$MNT/etc/clix/$f"
      fi
    done

    ROOT_UUID="$(blkid -s UUID -o value "$ROOT_PART")"
    ESP_UUID="$(blkid -s UUID -o value "$ESP_PART")"

    # Pin the installed system's filesystems by UUID. live-system.nix mounts by
    # label (CLIX-ROOT, ESP), which is correct for a portable USB image but
    # ambiguous once an installed disk and a CLIX stick are both attached: the
    # labels are identical and which one wins is undefined. Pinning by UUID also
    # lets canTouchEfiVariables be enabled, so the installed system registers a
    # real NVRAM boot entry instead of relying on the removable-media fallback
    # path at EFI/BOOT/BOOTX64.EFI.
    echo "==> Writing installed-disk.nix (UUID pins)"
    {
      echo "{ config, pkgs, lib, ... }:"
      echo ""
      echo "# Generated by clix-install on $(date -u +%Y-%m-%dT%H:%M:%SZ). Do not edit by hand;"
      echo "# re-running clix-install regenerates it."
      echo "#"
      echo "# Overrides live-system.nix's label-based mounts with UUIDs, so this"
      echo "# installed system never races the identical CLIX-ROOT / ESP labels on a"
      echo "# CLIX USB stick, and enables EFI variable writes now that the system"
      echo "# lives on a fixed internal disk."
      echo "{"
      echo "  fileSystems.\"/\" = lib.mkForce {"
      echo "    device = \"/dev/disk/by-uuid/$ROOT_UUID\";"
      echo "    fsType = \"ext4\";"
      echo "  };"
      echo ""
      echo "  fileSystems.\"/boot\" = lib.mkForce {"
      echo "    device = \"/dev/disk/by-uuid/$ESP_UUID\";"
      echo "    fsType = \"vfat\";"
      echo "  };"
      echo ""
      echo "  boot.loader.efi.canTouchEfiVariables = lib.mkForce true;"
      echo "}"
    } > "$MNT/etc/nixos/installed-disk.nix"

    if [ "$ENCRYPTED_HOME" -eq 1 ]; then
      # encrypted-home.nix and sway.nix unlock /home from this path rather than
      # from fileSystems, so it has to point at the new LUKS container.
      HOME_LUKS_UUID="$(blkid -s UUID -o value "$HOME_PART")"
      echo "/dev/disk/by-uuid/$HOME_LUKS_UUID" > "$MNT/etc/clix/home-device"
    fi

    echo "==> Installing system closure (this takes a while)"
    nixos-install \
      --root "$MNT" \
      --system "$SYSTEM_CLOSURE" \
      --no-root-password \
      --no-channel-copy

    # nixos-install used the prebuilt closure, so installed-disk.nix has not been
    # evaluated yet and the installed generation still mounts by label. Rebuild
    # inside the target to produce a UUID-pinned generation. If this fails (no
    # network for a missing path, for example) the system still boots via the
    # label and the user can run `rebuild` afterwards.
    echo "==> Rebuilding inside target to apply UUID pins"
    if nixos-enter --root "$MNT" -- \
         nixos-rebuild boot --flake /etc/nixos#clix 2>&1 | tail -20; then
      PINNED=1
    else
      PINNED=0
      echo ""
      echo "WARNING: the in-target rebuild failed."
      echo "         The system is installed and bootable, but still mounts by label."
      echo "         Boot it with the CLIX USB removed, then run: rebuild"
    fi

    if [ "$MIGRATE_HOME" -eq 1 ] && [ "$ENCRYPTED_HOME" -eq 1 ]; then
      echo "==> Migrating /home"
      mkdir -p "$MNT/home"
      mount "/dev/mapper/$MAPPER" "$MNT/home"
      rsync -aHAX --info=progress2 /home/ "$MNT/home/"
      umount "$MNT/home"
    fi

    echo "==> Verifying install"
    FAIL=0

    # Takes the label first and the test as remaining arguments, so the test runs
    # as the condition of an if. A bare `[ ... ]` here would abort under set -e
    # instead of being reported as a failed check.
    check() {
      local label="$1"
      shift
      if "$@"; then
        echo "    ok    $label"
      else
        echo "    FAIL  $label"
        FAIL=1
      fi
    }

    # `|| true` keeps a missing entries directory from failing the pipeline
    # under pipefail; wc still reports 0.
    ENTRIES="$(find "$MNT/boot/loader/entries" -name '*.conf' 2>/dev/null | wc -l || true)"

    check "systemd-boot present on ESP" \
      test -e "$MNT/boot/EFI/systemd/systemd-bootx64.efi"
    check "removable-media fallback present" \
      test -e "$MNT/boot/EFI/BOOT/BOOTX64.EFI"
    check "boot entries generated ($ENTRIES)" \
      test "$ENTRIES" -gt 0
    check "system profile symlink resolves" \
      test -e "$MNT/nix/var/nix/profiles/system"

    if [ "$PINNED" -eq 1 ]; then
      check "boot entry references root UUID $ROOT_UUID" \
        grep -rqs "$ROOT_UUID" "$MNT/boot/loader/entries"
    fi

    echo ""
    if [ "$FAIL" -ne 0 ]; then
      echo "Install completed with FAILED checks. Do not remove the USB until you"
      echo "have verified the new system boots."
      exit 1
    fi

    echo "Install complete."
    echo ""
    echo "  Root:  $ROOT_PART (UUID $ROOT_UUID)"
    echo "  ESP:   $ESP_PART (UUID $ESP_UUID)"
    if [ "$ENCRYPTED_HOME" -eq 1 ]; then
      echo "  Home:  $HOME_PART (LUKS2)"
    fi
    echo ""
    echo "Next steps:"
    echo "  1. Reboot and select the new disk in your firmware's boot menu."
    echo "  2. Keep the CLIX USB as a fallback until the install is proven."
    echo "  3. Once satisfied, the USB can be reused; the installed system does"
    echo "     not depend on it."
  '';
in
{
  environment.systemPackages = [ clixInstallScript ];
}
