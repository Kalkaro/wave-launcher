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

    def test_interrupted_shrink_clamps_stale_retraction_index(self) -> None:
        source = SHELL_QML.read_text(encoding="utf-8")
        retract_function = re.search(
            r"function tryRetractNext\(now\) \{(?P<body>.*?)"
            r"\n\s*function tryRevealNext",
            source,
            re.DOTALL,
        )

        if retract_function is None:
            self.fail("letter-retraction handler must exist")
        body = retract_function.group("body")
        clamp_index = body.find(
            "pendingRetractIndex = Math.min(pendingRetractIndex, charScrambleModel.count - 1);"
        )
        access_index = body.find("charScrambleModel.get(pendingRetractIndex)")
        self.assertGreaterEqual(clamp_index, 0, "interrupted shrink must clamp its stale model index")
        self.assertGreater(access_index, clamp_index, "model access must happen only after clamping")


if __name__ == "__main__":
    unittest.main()
