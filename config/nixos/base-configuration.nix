# CLIX Base Configuration
# This file contains the core system configuration.
# DO NOT EDIT - changes here will be overwritten on system updates.
# Use configuration.nix for your customizations.

{ config, pkgs, lib, ... }:

{
  imports = [
    ./modules/base.nix
    ./modules/sway.nix
    ./modules/claude-code.nix
    ./modules/live-system.nix
    ./modules/data-partition.nix
    ./modules/encrypted-home.nix
    ./modules/first-boot-setup.nix
    ./modules/updates.nix
  ];
}
