{
  description = "CLIX - Claude Code Live Image for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};

    # Version derived from git - use rev if clean, "dirty" otherwise
    # For tagged releases, this gets overridden by the tag
    clixVersion = self.shortRev or self.dirtyShortRev or "dev";

  in {
    nixosConfigurations.clix = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit self clixVersion; };
      modules = [
        ./modules/base.nix
        ./modules/sway.nix
        ./modules/claude-code.nix
        ./modules/live-system.nix
        ./modules/data-partition.nix
        ./modules/encrypted-home.nix
        ./modules/first-boot-setup.nix
        ./modules/updates.nix
      ];
    };

    packages.${system} = {
      # System closure - used by scripts/build-image.sh
      # Build with: ./scripts/docker-build.sh
      system = self.nixosConfigurations.clix.config.system.build.toplevel;

      default = self.packages.${system}.system;
    };
  };
}
