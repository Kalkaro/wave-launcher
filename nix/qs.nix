# Drop-in Home Manager module for nixos-config/modules/qs/
#
# flake.nix:
#   inputs.wave-launcher.url = "github:Kalkaro/wave-launcher";
#
# modules/qs/default.nix (or home.nix):
#   imports = [ inputs.wave-launcher.homeManagerModules.qs ];
#
# Override defaults under programs.wave-launcher in your config as needed.

{ self }:
{ config, lib, pkgs, ... }:
{
  imports = [ (import ./home-manager.nix { inherit self; }) ];

  programs.wave-launcher = {
    enable = lib.mkDefault true;
    stylix.enable = lib.mkDefault true;
    fontPackages = lib.mkDefault [ pkgs.nerd-fonts.bigblue-terminal ];
    hyprlandKeybind = lib.mkDefault "SUPER, SPACE";
  };
}
