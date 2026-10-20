#!/usr/bin/env python3
"""The `full` profile must cover the whole catalog, or it stops meaning anything.

Run: python3 -m unittest discover -s tests -v
"""

import os
import pathlib
import re
import subprocess
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]
INSTALL = REPO / "install.sh"

INSTALL_LINE = re.compile(r"^\[dry-run\] install (\S+)$")
LIST_LINE = re.compile(r"^([^\t]+)\t([^\t]+)\t([^\t]+)\t(installed|missing)$")


def run(*args, os_name="fedora", headless="0"):
    env = dict(os.environ)
    env.pop("DISPLAY", None)
    env.pop("WAYLAND_DISPLAY", None)
    env.update({"XT_OS": os_name, "XT_HEADLESS": headless})
    return subprocess.run(
        ["bash", str(INSTALL), *args],
        cwd=str(REPO),
        env=env,
        input="",
        capture_output=True,
        text=True,
        timeout=180,
    )


def planned(result):
    return [
        INSTALL_LINE.match(line.strip()).group(1)
        for line in result.stdout.splitlines()
        if INSTALL_LINE.match(line.strip())
    ]


def listed(result):
    return [
        LIST_LINE.match(line.strip()).group(1)
        for line in result.stdout.splitlines()
        if LIST_LINE.match(line.strip())
    ]


class FullProfileCoverageTest(unittest.TestCase):
    def test_full_profile_covers_every_available_item(self):
        listed_ids = listed(run("--list"))
        self.assertTrue(listed_ids, "--list reported no items")
        planned_ids = planned(run("--dry-run", "--force", "--profile", "full", "--claude", "--gemini"))
        self.assertEqual(sorted(listed_ids), sorted(planned_ids), "the full profile and the catalog disagree")

    def test_full_profile_follows_the_platform(self):
        listed_ids = listed(run("--list", os_name="alpine"))
        planned_ids = planned(
            run("--dry-run", "--force", "--profile", "full", "--claude", "--gemini", os_name="alpine")
        )
        self.assertEqual(sorted(listed_ids), sorted(planned_ids))
        self.assertNotIn("git", planned_ids, "a package item must not survive an unsupported platform")


if __name__ == "__main__":
    unittest.main()
