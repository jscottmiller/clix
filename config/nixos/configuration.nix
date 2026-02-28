# CLIX User Configuration
# Edit this file and run `rebuild` to apply changes.

{ config, pkgs, lib, ... }:

{
  # Add your custom packages here
  environment.systemPackages = with pkgs; [
    # example: python3 neovim tmux
  ];

  # Add custom services or configuration below
  # services.someService.enable = true;
}
