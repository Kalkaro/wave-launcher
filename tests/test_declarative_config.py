#!/usr/bin/env python3
"""Regression checks for declarative launcher configuration."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SHELL_QML = ROOT / "shell.qml"
NIX_LIB = ROOT / "nix" / "lib.nix"
HOME_MANAGER_MODULE = ROOT / "nix" / "home-manager.nix"
NIXOS_MODULE = ROOT / "nix" / "nixos.nix"


class DeclarativeConfigTests(unittest.TestCase):
    def test_modules_generate_json_consumed_and_reloaded_by_qml(self) -> None:
        shell = SHELL_QML.read_text(encoding="utf-8")
        nix_lib = NIX_LIB.read_text(encoding="utf-8")
        home_manager = HOME_MANAGER_MODULE.read_text(encoding="utf-8")
        nixos = NIXOS_MODULE.read_text(encoding="utf-8")

        self.assertIn('StandardPaths.locate(StandardPaths.GenericConfigLocation, "wave-launcher/config.json")', shell)
        self.assertIn("watchChanges: true", shell)
        self.assertIn("onFileChanged: reload()", shell)
        self.assertIn("JSON.parse(text)", shell)
        self.assertIn("function refreshConfig()", shell)
        self.assertIn("onTriggered: root.refreshConfig()", shell)
        self.assertIn("Component.onCompleted: refreshConfig()", shell)
        self.assertNotIn('Quickshell.env("WAVE_LAUNCHER_', shell)

        self.assertIn("waveLauncherConfig", nix_lib)
        self.assertNotIn("waveLauncherSessionVariables", nix_lib)
        self.assertIn('xdg.configFile."wave-launcher/config.json".text', home_manager)
        self.assertIn('environment.etc."xdg/wave-launcher/config.json".text', nixos)
        self.assertNotIn("sessionVariables", home_manager)
        self.assertNotIn("sessionVariables", nixos)

    def test_background_rectangle_is_declarative_and_enabled_by_default(self) -> None:
        shell = SHELL_QML.read_text(encoding="utf-8")
        nix_lib = NIX_LIB.read_text(encoding="utf-8")

        self.assertIn("background.enable = lib.mkOption", nix_lib)
        self.assertIn("default = true;", nix_lib)
        self.assertIn("backgroundEnabled = cfg.background.enable;", nix_lib)
        self.assertIn('configValue("backgroundEnabled", true) === true', shell)
        self.assertIn("visible: root.backgroundEnabled", shell)

    def test_falling_letters_are_declarative_and_disabled_by_default(self) -> None:
        shell = SHELL_QML.read_text(encoding="utf-8")
        nix_lib = NIX_LIB.read_text(encoding="utf-8")

        self.assertIn("fall.enable = lib.mkOption", nix_lib)
        self.assertIn("fallLettersEnabled = cfg.fall.enable;", nix_lib)
        self.assertIn('configValue("fallLettersEnabled", false) === true', shell)


if __name__ == "__main__":
    unittest.main()
