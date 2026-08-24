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
    hyprlandKeybindDefault = "SUPER, SPACE";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isLinux;
        message = "programs.wave-launcher is only supported on Linux.";
      }
      {
        assertion =
          !cfg.stylix.enable
          || lib.attrByPath [ "lib" "stylix" "colors" "withHashtag" ] null config != null;
        message =
          "programs.wave-launcher.stylix.enable requires Stylix (import stylix.homeModules.stylix and set stylix.enable = true).";
      }
    ];

    home.packages = [ cfg.package ] ++ cfg.fontPackages;

    xdg.configFile."wave-launcher/config.json".text = builtins.toJSON (
      waveLauncherConfig (waveLauncherResolvedCfg cfg config)
    );

    fonts.fontconfig.enable = lib.mkIf (cfg.fontPackages != [ ]) (lib.mkDefault true);

    systemd.user.services.wave-launcher = lib.mkIf cfg.service.enable {
      Unit = {
        Description = "Wave Launcher (Quickshell application launcher)";
        Documentation = "https://github.com/Kalkaro/wave-launcher";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };

      Service = {
        ExecStart = "${lib.getExe cfg.package} --daemon";
        Restart = "on-failure";
        RestartSec = 1;
        Slice = "session.slice";
      };

      Install.WantedBy = [ "graphical-session.target" ];
    };

    wayland.windowManager.hyprland.settings = lib.mkIf (cfg.hyprlandKeybind != null) {
      bind = lib.mkAfter [
        "${cfg.hyprlandKeybind}, exec, ${lib.getExe cfg.package}"
      ];
    };
  };
}
