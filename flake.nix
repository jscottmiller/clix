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
        ./modules/encrypted-home.nix
        ./modules/first-boot-setup.nix
      ];
    };

    packages.${system} = {
      # Minimal disk image - just ESP + nixos root
      # First boot will create CLIX-DATA and CLIX-HOME partitions
      # based on available space and user preferences
      image = nixos-generators.nixosGenerate {
        inherit system;
        specialArgs = { inherit self; };
        modules = [
          ./modules/base.nix
          ./modules/sway.nix
          ./modules/claude-code.nix
          ./modules/live-system.nix
          ./modules/data-partition.nix
          ./modules/encrypted-home.nix
          ./modules/first-boot-setup.nix
        ];
        format = "raw-efi";
      };

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
          ./modules/encrypted-home.nix
          ./modules/first-boot-setup.nix
        ];
      }).config.system.build.isoImage;

      default = self.packages.${system}.image;
    };
  };
}
