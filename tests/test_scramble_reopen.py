#!/usr/bin/env python3
"""Regression checks for interrupted launcher scramble animations."""

from pathlib import Path
import re
import unittest


SHELL_QML = Path(__file__).resolve().parents[1] / "shell.qml"


class ScrambleReopenTests(unittest.TestCase):
    def test_reopening_clears_interrupted_quit_state_before_rescheduling(self) -> None:
        source = SHELL_QML.read_text(encoding="utf-8")
        reopen_branch = re.search(
            r"function onLauncherOpenChanged\(\) \{\s*"
            r"if \(root\.launcherOpen\) \{(?P<body>.*?)"
            r"\}\s*else if \(charScrambleModel\.count > 0\)",
            source,
            re.DOTALL,
        )

        if reopen_branch is None:
            self.fail("launcher-open scramble handler must exist")
        body = reopen_branch.group("body")
        clear_index = body.find("appNameContainer.clearScramble();")
        schedule_index = body.find("appNameContainer.scheduleScramble(centerMenu.appNameStr);")
        self.assertGreaterEqual(clear_index, 0, "reopen must clear held quit-animation slots")
        self.assertGreater(schedule_index, clear_index, "reopen must reschedule only after clearing quit state")


if __name__ == "__main__":
    unittest.main()
