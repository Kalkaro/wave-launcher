lib: rec {
  mkWaveLauncherOptions =
    {
      packageDefault,
      fontPackagesDefault ? [ ],
      hyprlandKeybindDefault ? null,
    }:
    {
      enable = lib.mkEnableOption "Wave Launcher, a Quickshell application launcher";

      package = lib.mkOption {
        type = lib.types.package;
        default = packageDefault;
        description = "The wave-launcher package to install.";
      };

      font = lib.mkOption {
        type = lib.types.str;
        default = "BigBlueTermPlus Nerd Font";
        example = "JetBrainsMono Nerd Font";
        description = "Font family name used by the launcher UI.";
      };

      fontPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = fontPackagesDefault;
        example = lib.literalExpression "[ pkgs.nerd-fonts.jetbrains-mono ]";
        description = ''
          Font packages installed into fontconfig.
          Set to `[ ]` if the font is already available on the system.
        '';
      };

      wave.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to animate launcher text with a wave effect.";
      };

      scramble.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to animate launcher text with a character scramble effect.";
      };

      fall.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether typed letters fall and interact with launcher surfaces.";
      };

      background.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to show the blurred background rectangle behind launcher text.";
      };

      maxCharacters = lib.mkOption {
        type = lib.types.ints.positive;
        default = 25;
        example = 40;
        description = "Maximum number of characters shown for piped input entries.";
      };

      namespace = lib.mkOption {
        type = lib.types.str;
        default = "wave-launcher";
        example = "my-wave-launcher";
        description = "Layer-shell namespace for the launcher overlay.";
      };

      colors = {
        background = lib.mkOption {
          type = lib.types.str;
          default = "#100e1c";
          example = "#100e1c";
          description = "Background tint used by the center vignette.";
        };

        foreground = lib.mkOption {
          type = lib.types.str;
          default = "#f4ebfc";
          example = "#f4ebfc";
          description = "Primary text color.";
        };

        accent = lib.mkOption {
          type = lib.types.str;
          default = "#c084fc";
          example = "#c084fc";
          description = "Accent color used for 3D text shadows.";
        };
      };

      search = {
        matching = lib.mkOption {
          type = lib.types.enum [
            "normal"
            "fuzzy"
            "prefix"
            "glob"
            "regex"
          ];
          default = "normal";
          description = "Application matching mode (Rofi drun compatible).";
        };

        normalize = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Normalize text before matching.";
        };

        sort = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Sort matched applications.";
        };

        sortingMethod = lib.mkOption {
          type = lib.types.enum [
            "normal"
            "fzf"
          ];
          default = "normal";
          description = "Sorting method when search.sort is enabled.";
        };

        matchFields = lib.mkOption {
          type = lib.types.listOf (
            lib.types.enum [
              "name"
              "generic"
              "exec"
              "categories"
              "keywords"
              "comment"
            ]
          );
          default = [
            "name"
            "generic"
            "exec"
            "categories"
            "keywords"
          ];
          description = "Desktop entry fields to search against.";
        };

        useDrunHistory = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Boost recently launched applications.";
        };

        preferNameMatch = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Prefer name matches over exec-only matches when sorting.";
        };

        drunCache = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "wave-launcher.druncache";
          description = ''
            Launch history cache file name or absolute path.
            When null, uses `wave-launcher.druncache` in the XDG cache directory.
          '';
        };
      };

      hyprlandKeybind = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = hyprlandKeybindDefault;
        example = "SUPER, SPACE";
        description = ''
          Hyprland keybind to launch or toggle the launcher.
          Set to null to disable automatic keybind generation.
        '';
      };

      stylix = {
        enable = lib.mkEnableOption ''
          Use colors from Stylix instead of `programs.wave-launcher.colors`.

          Maps `base05` to text and `base00` to the vignette background and text
          shadow. Requires Stylix to be enabled in your configuration.
        '';
      };
    };

  waveLauncherResolvedCfg =
    cfg: config:
    let
      stylixPalette = lib.attrByPath [ "lib" "stylix" "colors" "withHashtag" ] null config;
    in
    if cfg.stylix.enable && stylixPalette != null then
      cfg
      // {
        colors = {
          background = stylixPalette.base00;
          foreground = stylixPalette.base05;
          accent = stylixPalette.base00;
        };
      }
    else
      cfg;

  waveLauncherConfig =
    cfg:
    let
      inherit (cfg) colors search;
      base = {
        font = cfg.font;
        waveEnabled = cfg.wave.enable;
        scrambleEnabled = cfg.scramble.enable;
        fallLettersEnabled = cfg.fall.enable;
        backgroundEnabled = cfg.background.enable;
        maxCharacters = cfg.maxCharacters;
        namespace = cfg.namespace;
        background = colors.background;
        foreground = colors.foreground;
        accent = colors.accent;
        matching = search.matching;
        normalize = search.normalize;
        sort = search.sort;
        sortingMethod = search.sortingMethod;
        matchFields = builtins.concatStringsSep "," search.matchFields;
        useDrunHistory = search.useDrunHistory;
        preferNameMatch = search.preferNameMatch;
      };
    in
    base
    // (if search.drunCache != null then {
      drunCache = search.drunCache;
    } else { });
}
