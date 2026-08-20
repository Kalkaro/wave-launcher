#!/usr/bin/env python3
"""Regression checks for the --fall command-line option."""

import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = ROOT / "launcher.sh"


class FallCliTests(unittest.TestCase):
    def test_fall_uses_fall_aware_toggle_for_running_launcher(self) -> None:
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
                [str(LAUNCHER), "--fall"],
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
                [f"-p {ROOT} ipc call launcher toggleFall"],
            )

    def test_fall_uses_fall_aware_open_after_starting_launcher(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            log = tmp / "calls.log"
            quickshell = tmp / "quickshell"
            quickshell.write_text(
                "#!/bin/sh\n"
                'printf \'%s\\n\' "$*" >>"$WAVE_TEST_LOG"\n'
                'case "$*" in\n'
                "  *\"ipc call launcher toggleFall\") exit 1 ;;\n"
                "  *) exit 0 ;;\n"
                "esac\n",
                encoding="utf-8",
            )
            quickshell.chmod(quickshell.stat().st_mode | stat.S_IXUSR)

            env = os.environ.copy()
            env["WAVE_LAUNCHER_QS"] = str(quickshell)
            env["WAVE_TEST_LOG"] = str(log)
            result = subprocess.run(
                [str(LAUNCHER), "--fall"],
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
                [
                    f"-p {ROOT} ipc call launcher toggleFall",
                    f"-p {ROOT} --daemonize",
                    f"-p {ROOT} ipc call launcher openFall",
                ],
            )


if __name__ == "__main__":
    unittest.main()
