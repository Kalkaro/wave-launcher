{
  description = "Minimalist Quickshell application launcher with a wavy center app name";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      home-manager,
      ...
    }:
    let
      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));

      version = self.shortRev or "unstable";

      sourceFilter =
        path: type:
        let
          name = baseNameOf path;
        in
        !(name == ".git" || name == "flake.nix" || name == "flake.lock" || name == ".gitignore" || name == ".qmlls.ini");

      mkPackage = pkgs:
        let
          inherit (pkgs) lib stdenvNoCC;
          qs = lib.getExe pkgs.quickshell;
        in
        stdenvNoCC.mkDerivation {
          pname = "wave-launcher";
          inherit version;

          src = lib.cleanSourceWith {
            src = self;
            name = "wave-launcher-src";
            filter = sourceFilter;
          };

          installPhase = ''
            runHook preInstall

            launcherRoot="$out/share/wave-launcher"
            mkdir -p "$launcherRoot/licenses" "$out/bin"
            cp -- shell.qml rofi-search.js "$launcherRoot/"
            cp -- LICENSE "$launcherRoot/"
            cp -- licenses/* "$launcherRoot/licenses/"

            cp -- launcher.sh "$out/bin/wave-launcher"
            substituteInPlace "$out/bin/wave-launcher" \
              --replace-fail 'launcher_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)' "launcher_dir=\"$launcherRoot\"" \
              --replace-fail 'qs_bin=''${WAVE_LAUNCHER_QS:-qs}' 'qs_bin="${qs}"'

            chmod +x "$out/bin/wave-launcher"

            runHook postInstall
          '';

          meta = with lib; {
            description = "Minimalist Quickshell application launcher with a wavy center app name";
            homepage = "https://github.com/${self.owner or "Kalkaro"}/${self.repo or "wave-launcher"}";
            license = licenses.mit;
            maintainers = [ ];
            platforms = platforms.linux;
            mainProgram = "wave-launcher";
          };
        };
    in
    {
      overlays.default = final: prev: {
        wave-launcher = mkPackage final;
      };

      packages = forAllSystems (pkgs: {
        default = mkPackage pkgs;
      });

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = "${self.packages.${pkgs.system}.default}/bin/wave-launcher";
        };
      });

      devShells = forAllSystems (
        pkgs:
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              quickshell
              (mkPackage pkgs)
              nerd-fonts.bigblue-terminal
            ];
            shellHook = ''
              echo "Wave Launcher dev shell"
              echo "  wave-launcher      toggle/open the packaged launcher"
              echo "  qs -p \$PWD         run from this checkout (non-Nix workflow)"
            '';
          };
        }
      );

      homeManagerModules.default = import ./nix/home-manager.nix { inherit self; };
      homeManagerModules.qs = import ./nix/qs.nix { inherit self; };

      nixosModules.default = import ./nix/nixos.nix { inherit self; };

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
