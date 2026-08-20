{ self }:
{ config, lib, pkgs, ... }:
let
  inherit (import ./lib.nix lib)
    mkWaveLauncherOptions
    waveLauncherConfig
    waveLauncherResolvedCfg
    ;

  cfg = config.programs.wave-launcher;
in
{
  options.programs.wave-launcher = mkWaveLauncherOptions {
    packageDefault = self.packages.${pkgs.system}.default;
    fontPackagesDefault = [ pkgs.nerd-fonts.bigblue-terminal ];
    hyprlandKeybindDefault = null;
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          !cfg.stylix.enable
          || lib.attrByPath [ "lib" "stylix" "colors" "withHashtag" ] null config != null;
        message =
          "programs.wave-launcher.stylix.enable requires Stylix (import stylix.nixosModules.stylix and set stylix.enable = true).";
      }
    ];

    environment.systemPackages = [ cfg.package ];
    environment.etc."xdg/wave-launcher/config.json".text = builtins.toJSON (
      waveLauncherConfig (waveLauncherResolvedCfg cfg config)
    );
    fonts.packages = cfg.fontPackages;
  };
}
