{
  description = "CLIX - Claude Code Live Image for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: let
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
      # System closure - used by scripts/build-image.sh
      # Build with: nix build .#system
      # Then run: sudo ./scripts/build-image.sh
      system = self.nixosConfigurations.clix.config.system.build.toplevel;

      default = self.packages.${system}.system;
    };
  };
}
