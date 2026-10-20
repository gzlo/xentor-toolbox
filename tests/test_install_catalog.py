#!/usr/bin/env python3
"""Contract tests for the catalog-driven installer.

Run: python3 -m unittest discover -s tests -v

The suite is hermetic: platform/headless detection is forced through XT_OS and
XT_HEADLESS, and every assertion drives the public CLI with --dry-run or --list,
so nothing is ever installed and sudo is never needed.
"""

import os
import pathlib
import re
import subprocess
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]
INSTALL = REPO / "install.sh"

# A spread of catalog items across categories and platforms.
SAMPLE_ITEMS = ["git", "btop", "fresh", "zsh", "starship", "nvim", "lazydocker", "opencode"]
# `minimal` in catalog order.
MINIMAL = ["git", "curl", "wget", "unzip", "tar", "gzip", "btop", "ripgrep", "fd", "jq", "zsh", "zsh-default", "shell-baseline", "fresh"]

INSTALL_LINE = re.compile(r"^\[dry-run\] install (\S+)$")
SKIP_LINE = re.compile(r"^\[dry-run\] skip (\S+) \(already installed\)$")
LIST_LINE = re.compile(r"^([^\t]+)\t([^\t]+)\t([^\t]+)\t(installed|missing)$")


def snapshot(path):
    if not path.exists():
        return []
    return sorted(str(p.relative_to(path)) for p in path.rglob("*"))


def run(*args, os_name="fedora", headless="0", path_prefix=None):
    env = dict(os.environ)
    env.pop("DISPLAY", None)
    env.pop("WAYLAND_DISPLAY", None)
    env.update({"XT_OS": os_name, "XT_HEADLESS": headless})
    if path_prefix:
        env["PATH"] = f"{path_prefix}{os.pathsep}{env.get('PATH', '')}"
    return subprocess.run(
        ["bash", str(INSTALL), *args],
        cwd=str(REPO),
        env=env,
        input="",
        capture_output=True,
        text=True,
        timeout=180,
    )


def listed_ids(result):
    return [
        LIST_LINE.match(line.strip()).group(1)
        for line in result.stdout.splitlines()
        if LIST_LINE.match(line.strip())
    ]


def planned_installs(result):
    return [
        INSTALL_LINE.match(line.strip()).group(1)
        for line in result.stdout.splitlines()
        if INSTALL_LINE.match(line.strip())
    ]


def skipped(result):
    return [
        SKIP_LINE.match(line.strip()).group(1)
        for line in result.stdout.splitlines()
        if SKIP_LINE.match(line.strip())
    ]


class CatalogListTest(unittest.TestCase):
    def test_list_reports_every_catalog_item_with_state(self):
        result = run("--list")
        self.assertEqual(result.returncode, 0, result.stderr)
        ids = listed_ids(result)
        for item_id in SAMPLE_ITEMS:
            self.assertIn(item_id, ids, f"{item_id} missing from --list")
        for line in result.stdout.splitlines():
            if line.strip():
                self.assertRegex(line.strip(), LIST_LINE)

    def test_list_profiles_reports_every_profile(self):
        result = run("--list-profiles")
        self.assertEqual(result.returncode, 0, result.stderr)
        names = [line.split("\t")[0] for line in result.stdout.splitlines() if line.strip()]
        self.assertEqual(names, ["minimal", "shell", "dev", "ai", "full"])


class SelectionTest(unittest.TestCase):
    def test_dry_run_installs_only_the_selected_item(self):
        result = run("--dry-run", "--force", "--items", "fresh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(planned_installs(result), ["fresh"])

    def test_profile_plan_matches_profile_membership_in_catalog_order(self):
        result = run("--dry-run", "--force", "--profile", "minimal")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(planned_installs(result), MINIMAL)

    def test_profile_and_items_union_without_duplicates(self):
        result = run("--dry-run", "--force", "--profile", "minimal", "--items", "fresh,fresh")
        self.assertEqual(result.returncode, 0, result.stderr)
        planned = planned_installs(result)
        self.assertEqual(len(planned), len(set(planned)), "duplicate items in plan")
        self.assertIn("fresh", planned)

    def test_already_installed_item_is_skipped_not_planned(self):
        with tempfile.TemporaryDirectory() as fake_bin:
            fake_git = pathlib.Path(fake_bin) / "git"
            fake_git.write_text("#!/bin/sh\nexit 0\n")
            fake_git.chmod(0o755)
            result = run("--dry-run", "--items", "git", path_prefix=fake_bin)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(skipped(result), ["git"])
        self.assertEqual(planned_installs(result), [])


class PlatformGateTest(unittest.TestCase):
    def test_debian_hides_fedora_only_items_and_keeps_agnostic_ones(self):
        result = run("--list", os_name="debian")
        self.assertEqual(result.returncode, 0, result.stderr)
        ids = listed_ids(result)
        self.assertNotIn("starship", ids)
        self.assertIn("fresh", ids)

    def test_selecting_an_unavailable_item_fails_with_its_name(self):
        result = run("--dry-run", "--items", "starship", os_name="debian")
        self.assertEqual(result.returncode, 2)
        self.assertIn("starship", result.stderr)


class UsageTest(unittest.TestCase):
    def test_unknown_item_exits_2_naming_it(self):
        result = run("--dry-run", "--items", "nope")
        self.assertEqual(result.returncode, 2)
        self.assertIn("nope", result.stderr)

    def test_unknown_profile_exits_2_naming_it(self):
        result = run("--dry-run", "--profile", "nope")
        self.assertEqual(result.returncode, 2)
        self.assertIn("nope", result.stderr)

    def test_unknown_option_exits_2(self):
        result = run("--nonsense")
        self.assertEqual(result.returncode, 2)

    def test_no_selection_without_a_terminal_exits_2(self):
        result = run()
        self.assertEqual(result.returncode, 2)
        self.assertIn("no terminal", result.stderr)

    def test_help_documents_the_scripted_surface(self):
        result = run("--help")
        self.assertEqual(result.returncode, 0, result.stderr)
        for flag in ("--items", "--profile", "--list", "--dry-run", "--tui", "--yes"):
            self.assertIn(flag, result.stdout)


class NoMutationTest(unittest.TestCase):
    def test_dry_run_writes_nothing(self):
        before = (snapshot(REPO / "logs"), snapshot(REPO / "tmp"))
        result = run("--dry-run", "--force", "--profile", "full", "--claude", "--gemini")
        after = (snapshot(REPO / "logs"), snapshot(REPO / "tmp"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, after, "dry-run mutated logs/ or tmp/")
        self.assertIn("no changes made (dry-run)", result.stdout)


if __name__ == "__main__":
    unittest.main()
