#!/usr/bin/env python3
"""The shell baseline: zsh gets a sane configuration without taking over dotfiles.

Run: python3 -m unittest discover -s tests -v

Every case runs against a throwaway HOME, so the real ~/.zshrc is never touched.
The contract: one managed block, user content preserved, ~/.shell.local created once
and never edited afterwards.
"""

import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]
COPIED = ["install.sh", "catalog", "scripts", "shell"]
START = "# >>> xentor-toolbox >>>"
END = "# <<< xentor-toolbox <<<"


def run_script(home, cwd):
    env = dict(os.environ)
    env.update({"HOME": str(home), "ACTUAL_HOME": str(home)})
    return subprocess.run(
        ["bash", str(cwd / "scripts" / "shell-baseline.sh"), "install"],
        cwd=str(cwd),
        env=env,
        input="",
        capture_output=True,
        text=True,
        timeout=120,
    )


class ShellBaselineTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.repo = self.root / "repo"
        self.repo.mkdir()
        for entry in COPIED:
            src = REPO / entry
            dst = self.repo / entry
            if src.is_dir():
                shutil.copytree(src, dst)
            else:
                shutil.copy2(src, dst)

    def tearDown(self):
        self.tmp.cleanup()

    def zshrc(self):
        return (self.home / ".zshrc").read_text()

    def test_installs_the_baseline_file(self):
        result = run_script(self.home, self.repo)
        self.assertEqual(result.returncode, 0, result.stderr)
        installed = self.home / ".config/xentor-toolbox/shell.zsh"
        self.assertTrue(installed.is_file())
        self.assertEqual(installed.read_text(), (self.repo / "shell/base.zsh").read_text())

    def test_block_is_installed_once_and_sources_both_files_in_order(self):
        run_script(self.home, self.repo)
        text = self.zshrc()
        self.assertEqual(text.count(START), 1)
        self.assertEqual(text.count(END), 1)
        source_baseline = text.index('[ -f "$HOME/.config/xentor-toolbox/shell.zsh" ]')
        source_local = text.index('[ -f "$HOME/.shell.local" ]')
        self.assertLess(source_baseline, source_local, "~/.shell.local must be sourced last")

    def test_existing_zshrc_content_is_preserved(self):
        (self.home / ".zshrc").write_text("export MY_OWN_SETTING=1\n")
        run_script(self.home, self.repo)
        text = self.zshrc()
        self.assertIn("export MY_OWN_SETTING=1", text)
        self.assertEqual(text.count(START), 1)

    def test_rerun_replaces_the_block_instead_of_appending(self):
        run_script(self.home, self.repo)
        run_script(self.home, self.repo)
        text = self.zshrc()
        self.assertEqual(text.count(START), 1, "the block was appended twice")
        self.assertEqual(text.count(END), 1)

    def test_shell_local_is_created_private(self):
        run_script(self.home, self.repo)
        local = self.home / ".shell.local"
        self.assertTrue(local.is_file())
        self.assertEqual(local.stat().st_mode & 0o777, 0o600)

    def test_existing_shell_local_is_never_edited(self):
        local = self.home / ".shell.local"
        local.write_text("alias mine='echo personal'\n")
        local.chmod(0o600)
        run_script(self.home, self.repo)
        self.assertEqual(local.read_text(), "alias mine='echo personal'\n")


class ShellBaselineItemTest(unittest.TestCase):
    """The item wiring: selecting shell-baseline runs the script for the real HOME."""

    def test_item_runs_end_to_end_against_a_throwaway_home(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            home = root / "home"
            home.mkdir()
            repo = root / "repo"
            repo.mkdir()
            for entry in COPIED:
                src = REPO / entry
                dst = repo / entry
                if src.is_dir():
                    shutil.copytree(src, dst)
                else:
                    shutil.copy2(src, dst)
            (repo / "install.sh").chmod(0o755)

            env = dict(os.environ)
            env.pop("DISPLAY", None)
            env.pop("WAYLAND_DISPLAY", None)
            env.update({"HOME": str(home), "XT_OS": "fedora", "XT_HEADLESS": "1"})

            result = subprocess.run(
                ["bash", str(repo / "install.sh"), "--items", "shell-baseline", "--force"],
                cwd=str(repo),
                env=env,
                input="",
                capture_output=True,
                text=True,
                timeout=180,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue((home / ".config/xentor-toolbox/shell.zsh").is_file())
            self.assertIn(START, (home / ".zshrc").read_text())
            self.assertTrue((home / ".shell.local").is_file())


class ZshIsBaselineTest(unittest.TestCase):
    """zsh must come out as the primary shell in every bundle, not as an extra."""

    def test_every_profile_installs_zsh_and_makes_it_default(self):
        env = dict(os.environ)
        env.update({"XT_OS": "fedora", "XT_HEADLESS": "1"})
        for profile in ("minimal", "shell", "dev", "ai", "full"):
            result = subprocess.run(
                ["bash", str(REPO / "install.sh"), "--dry-run", "--force", "--profile", profile],
                cwd=str(REPO),
                env=env,
                input="",
                capture_output=True,
                text=True,
                timeout=180,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            planned = [
                line.split()[-1]
                for line in result.stdout.splitlines()
                if line.startswith("[dry-run] install ")
            ]
            self.assertIn("zsh", planned, f"{profile} does not install zsh")
            self.assertIn("zsh-default", planned, f"{profile} does not make zsh the default shell")
            self.assertIn("shell-baseline", planned, f"{profile} does not install the shell baseline")


if __name__ == "__main__":
    unittest.main()
