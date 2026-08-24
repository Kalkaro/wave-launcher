#!/usr/bin/env python3
"""Regression checks for the --special random effect option."""

import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = ROOT / "launcher.sh"
SHELL_QML = ROOT / "shell.qml"
NIX_LIB = ROOT / "nix" / "lib.nix"


def run_launcher(tmp: Path, quickshell_body: str) -> tuple[subprocess.CompletedProcess, Path]:
    log = tmp / "calls.log"
    quickshell = tmp / "quickshell"
    quickshell.write_text(quickshell_body, encoding="utf-8")
    quickshell.chmod(quickshell.stat().st_mode | stat.S_IXUSR)

    env = os.environ.copy()
    env["WAVE_LAUNCHER_QS"] = str(quickshell)
    env["WAVE_TEST_LOG"] = str(log)
    result = subprocess.run(
        [str(LAUNCHER), "--special"],
        cwd=ROOT,
        env=env,
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        check=False,
    )
    return result, log


class SpecialCliTests(unittest.TestCase):
    def test_special_uses_special_aware_toggle_for_running_launcher(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            result, log = run_launcher(
                Path(tmpdir),
                "#!/bin/sh\n"
                'printf \'%s\\n\' "$*" >>"$WAVE_TEST_LOG"\n'
                "exit 0\n",
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                log.read_text(encoding="utf-8").splitlines(),
                [f"-p {ROOT} ipc call launcher toggleSpecial"],
            )

    def test_special_uses_special_aware_open_after_starting_launcher(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            result, log = run_launcher(
                Path(tmpdir),
                "#!/bin/sh\n"
                'printf \'%s\\n\' "$*" >>"$WAVE_TEST_LOG"\n'
                'case "$*" in\n'
                "  *\"ipc call launcher toggleSpecial\") exit 1 ;;\n"
                "  *) exit 0 ;;\n"
                "esac\n",
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                log.read_text(encoding="utf-8").splitlines(),
                [
                    f"-p {ROOT} ipc call launcher toggleSpecial",
                    f"-p {ROOT} --daemonize",
                    f"-p {ROOT} ipc call launcher openSpecial",
                ],
            )


class SpecialEffectFrameworkTests(unittest.TestCase):
    def test_ipc_exposes_special_entry_points(self) -> None:
        shell = SHELL_QML.read_text(encoding="utf-8")

        self.assertIn("function toggleSpecial(): void", shell)
        self.assertIn("function openSpecial(): void", shell)
        self.assertIn("root.commandSpecialEnabled = true;", shell)

    def test_effects_are_rolled_from_a_shared_pool_on_open(self) -> None:
        shell = SHELL_QML.read_text(encoding="utf-8")

        self.assertIn('readonly property var specialEffects: ["fall"]', shell)
        self.assertIn("function rollSpecialEffect()", shell)
        self.assertIn("function specialEffectActive(name)", shell)
        self.assertIn("rollSpecialEffect();", shell)
        self.assertIn("Math.random() >= specialEffectChance", shell)
        self.assertIn('specialEffectActive("fall")', shell)

    def test_chance_is_declarative_and_one_percent_by_default(self) -> None:
        shell = SHELL_QML.read_text(encoding="utf-8")
        nix_lib = NIX_LIB.read_text(encoding="utf-8")

        self.assertIn("special.chance = lib.mkOption", nix_lib)
        self.assertIn("default = 0.01;", nix_lib)
        self.assertIn("specialEffectChance = cfg.special.chance;", nix_lib)
        self.assertIn('configValue("specialEffectChance", 0.01)', shell)


if __name__ == "__main__":
    unittest.main()
