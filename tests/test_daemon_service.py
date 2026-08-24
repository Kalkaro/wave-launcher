#!/usr/bin/env python3
"""Checks for the --daemon mode and the systemd user units that call it."""

import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = ROOT / "launcher.sh"
HOME_MANAGER_MODULE = ROOT / "nix" / "home-manager.nix"
NIXOS_MODULE = ROOT / "nix" / "nixos.nix"


class DaemonServiceTests(unittest.TestCase):
    def test_daemon_runs_quickshell_in_the_foreground(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            log = tmp / "calls.log"
            quickshell = tmp / "quickshell"
            quickshell.write_text(
                "#!/bin/sh\n"
                'printf \'%s\\n\' "$*" >>"$WAVE_TEST_LOG"\n'
                "exit 0\n",
                encoding="utf-8",
            )
            quickshell.chmod(quickshell.stat().st_mode | stat.S_IXUSR)

            env = os.environ.copy()
            env["WAVE_LAUNCHER_QS"] = str(quickshell)
            env["WAVE_TEST_LOG"] = str(log)
            result = subprocess.run(
                [str(LAUNCHER), "--daemon"],
                cwd=ROOT,
                env=env,
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                log.read_text(encoding="utf-8").splitlines(),
                [f"-p {ROOT} --no-duplicate"],
                "--daemon must not daemonize; systemd owns the process",
            )

    def test_modules_define_a_graphical_session_user_service(self) -> None:
        for module in (HOME_MANAGER_MODULE, NIXOS_MODULE):
            with self.subTest(module=module.name):
                source = module.read_text(encoding="utf-8")
                self.assertIn(
                    "systemd.user.services.wave-launcher",
                    source,
                    "module must define the launcher user service",
                )
                self.assertIn(
                    "--daemon",
                    source,
                    "the unit must start the launcher in foreground daemon mode",
                )
                self.assertIn(
                    "cfg.service.enable",
                    source,
                    "the unit must honour programs.wave-launcher.service.enable",
                )
                self.assertIn(
                    "graphical-session.target",
                    source,
                    "the unit must be bound to the graphical session",
                )


if __name__ == "__main__":
    unittest.main()
