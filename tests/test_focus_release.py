#!/usr/bin/env python3
"""Regression checks for launcher focus and pointer release."""

from pathlib import Path
import re
import unittest


SHELL_QML = Path(__file__).resolve().parents[1] / "shell.qml"


class FocusReleaseTests(unittest.TestCase):
    def test_closing_launcher_makes_visible_overlay_click_through(self) -> None:
        source = SHELL_QML.read_text(encoding="utf-8")

        self.assertRegex(
            source,
            re.compile(r"mask:\s*root\.launcherOpen\s*\?\s*null\s*:\s*clickThroughMask"),
            "The full-screen overlay must use an empty input mask while its close animation remains visible",
        )
        self.assertRegex(
            source,
            re.compile(r"Region\s*\{\s*id:\s*clickThroughMask\s*\}"),
            "clickThroughMask must be an empty Region so pointer events reach windows underneath",
        )


if __name__ == "__main__":
    unittest.main()
