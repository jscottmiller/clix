{
  description = "CLIX - Claude Code Live ISO for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};

    # Create a FAT32 data partition image using mtools (no root required)
    dataPartitionImage = pkgs.runCommand "clix-data-partition" {
      nativeBuildInputs = with pkgs; [ dosfstools mtools ];
    } ''
      # Create 64MB FAT32 image
      truncate -s 64M $out

      # Format as FAT32
      mkfs.vfat -n CLIX-DATA $out

      # Create directories and files using mtools
      mmd -i $out ::claude
      mmd -i $out ::network

      # Create README
      cat > readme.txt << 'EOF'
CLIX Data Partition
====================

This partition is read on boot to configure your CLIX system.

WiFi Regulatory Domain
----------------------
Create a file: network/regdomain

Contents should be your 2-letter country code (e.g., US, DE, GB, JP).
This is required for WiFi to work properly.

WiFi Configuration
------------------
Create a file: network/wifi.nmconnection

Example contents:
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

Claude Credentials
------------------
Copy your ~/.claude directory contents to: claude/

The system will import these on boot.
EOF
      mcopy -i $out readme.txt ::README.txt
      rm readme.txt
    '';

  in {
    nixosConfigurations.clix = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit self; };
      modules = [
        ./modules/base.nix
        ./modules/sway.nix
        ./modules/claude-code.nix
        ./modules/live-system.nix
        ./modules/data-partition.nix
      ];
    };

    packages.${system} = {
      # Raw disk image (base)
      disk-image = nixos-generators.nixosGenerate {
        inherit system;
        specialArgs = { inherit self; };
        modules = [
          ./modules/base.nix
          ./modules/sway.nix
          ./modules/claude-code.nix
          ./modules/live-system.nix
          ./modules/data-partition.nix
        ];
        format = "raw-efi";
      };

      # Combined image with data partition FIRST (for Windows visibility)
      image = pkgs.runCommand "clix-image" {
        nativeBuildInputs = with pkgs; [ gptfdisk util-linux ];
      } ''
        mkdir -p $out

        BASE_IMG="${self.packages.${system}.disk-image}/nixos.img"
        DATA_IMG="${dataPartitionImage}"

        # Get base image size and partition info
        BASE_SIZE=$(stat -c%s "$BASE_IMG")
        DATA_SIZE=$(stat -c%s "$DATA_IMG")

        # Get partition offsets and sizes from base image (in sectors, 512 bytes each)
        # Partition 1 = EFI, Partition 2 = root
        EFI_START=$(sgdisk -i 1 "$BASE_IMG" | grep "First sector" | awk '{print $3}')
        EFI_END=$(sgdisk -i 1 "$BASE_IMG" | grep "Last sector" | awk '{print $3}')
        EFI_SIZE=$((EFI_END - EFI_START + 1))

        ROOT_START=$(sgdisk -i 2 "$BASE_IMG" | grep "First sector" | awk '{print $3}')
        ROOT_END=$(sgdisk -i 2 "$BASE_IMG" | grep "Last sector" | awk '{print $3}')
        ROOT_SIZE=$((ROOT_END - ROOT_START + 1))

        # Data partition size in sectors (64MB = 131072 sectors)
        DATA_SECTORS=$((DATA_SIZE / 512))

        # Create new image: GPT header (2048 sectors) + DATA + EFI + ROOT + GPT backup (34 sectors)
        # Align partitions to 2048 sector boundaries
        NEW_DATA_START=2048
        NEW_DATA_END=$((NEW_DATA_START + DATA_SECTORS - 1))

        NEW_EFI_START=$(( ((NEW_DATA_END + 1 + 2047) / 2048) * 2048 ))
        NEW_EFI_END=$((NEW_EFI_START + EFI_SIZE - 1))

        NEW_ROOT_START=$(( ((NEW_EFI_END + 1 + 2047) / 2048) * 2048 ))
        NEW_ROOT_END=$((NEW_ROOT_START + ROOT_SIZE - 1))

        # Total size with some padding for backup GPT
        TOTAL_SECTORS=$((NEW_ROOT_END + 2048))
        TOTAL_SIZE=$((TOTAL_SECTORS * 512))

        echo "Creating new image layout:"
        echo "  Data partition: sectors $NEW_DATA_START - $NEW_DATA_END"
        echo "  EFI partition:  sectors $NEW_EFI_START - $NEW_EFI_END"
        echo "  Root partition: sectors $NEW_ROOT_START - $NEW_ROOT_END"
        echo "  Total size: $((TOTAL_SIZE / 1024 / 1024)) MB"

        # Create the new image
        truncate -s $TOTAL_SIZE $out/clix.img

        # Create GPT with partitions in new order
        sgdisk --clear \
          --new=1:$NEW_DATA_START:$NEW_DATA_END --typecode=1:0700 --change-name=1:CLIX-DATA \
          --new=2:$NEW_EFI_START:$NEW_EFI_END --typecode=2:EF00 --change-name=2:ESP \
          --new=3:$NEW_ROOT_START:$NEW_ROOT_END --typecode=3:8300 --change-name=3:nixos \
          $out/clix.img

        # Copy partition contents
        echo "Copying data partition..."
        dd if="$DATA_IMG" of=$out/clix.img bs=512 seek=$NEW_DATA_START conv=notrunc status=progress

        echo "Copying EFI partition..."
        dd if="$BASE_IMG" of=$out/clix.img bs=512 skip=$EFI_START seek=$NEW_EFI_START count=$EFI_SIZE conv=notrunc status=progress

        echo "Copying root partition..."
        dd if="$BASE_IMG" of=$out/clix.img bs=512 skip=$ROOT_START seek=$NEW_ROOT_START count=$ROOT_SIZE conv=notrunc status=progress

        chmod -w $out/clix.img
        echo "Done! Image created at $out/clix.img"
      '';

      # Also keep ISO available for those who want it
      iso = (nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit self; };
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          ./modules/base.nix
          ./modules/sway.nix
          ./modules/claude-code.nix
          ./modules/live-system.nix
          ./modules/data-partition.nix
        ];
      }).config.system.build.isoImage;

      default = self.packages.${system}.image;
    };
  };
}
