{
  description = "CLIX System Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    nixosConfigurations.clix = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit self; };
      modules = [
        ./base-configuration.nix
        ./configuration.nix
      ];
    };
  };
}
