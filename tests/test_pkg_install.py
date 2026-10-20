#!/usr/bin/env python3
"""The package-manager path, executed for real against a fake manager.

Run: python3 -m unittest discover -s tests -v

This is the regression test for a defect the dry-run suites could not see: the engine
compared PKG_MGR (dnf|apt|pacman) against platform names (fedora|debian|arch), so no
pkg item could ever install. Everything ran under --dry-run, so nothing noticed.

A fake `apt-get`/`dnf` on PATH records its arguments, which proves the right command
and the right package name reached the manager without installing anything.
"""

import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]
COPIED = ["install.sh", "catalog", "scripts"]

FAKE_SUDO = """#!/bin/sh
exec "$@"
"""


def build_installer(root):
    for entry in COPIED:
        src = REPO / entry
        dst = root / entry
        if src.is_dir():
            shutil.copytree(src, dst)
        else:
            shutil.copy2(src, dst)
    (root / "install.sh").chmod(0o755)


def fake_manager(root, name, exit_code=0):
    log = root / f"{name}.log"
    script = root / "fake-bin" / name
    script.parent.mkdir(exist_ok=True)
    script.write_text(f'#!/bin/sh\nprintf "%s\\n" "$*" >> "{log}"\nexit {exit_code}\n')
    script.chmod(0o755)
    sudo = root / "fake-bin" / "sudo"
    sudo.write_text(FAKE_SUDO)
    sudo.chmod(0o755)
    return log


class PackageInstallTest(unittest.TestCase):
    def run_item(self, os_name, manager, *, manager_exit=0):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            build_installer(root)
            log = fake_manager(root, manager, exit_code=manager_exit)
            env = dict(os.environ)
            env.pop("DISPLAY", None)
            env.pop("WAYLAND_DISPLAY", None)
            env.update({"XT_OS": os_name, "XT_HEADLESS": "1"})
            env["PATH"] = f"{root / 'fake-bin'}{os.pathsep}{env.get('PATH', '')}"
            result = subprocess.run(
                ["bash", str(root / "install.sh"), "--items", "make", "--force"],
                cwd=str(root),
                env=env,
                input="",
                capture_output=True,
                text=True,
                timeout=180,
            )
            recorded = log.read_text().strip() if log.exists() else ""
            run_logs = list((root / "logs").rglob("run-*.log"))
            audit = "".join(p.read_text() for p in run_logs)
            return result, recorded, audit

    def test_debian_installs_through_apt(self):
        result, recorded, audit = self.run_item("debian", "apt-get")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(recorded, "install -y make")
        self.assertIn("DONE make", audit)

    def test_fedora_installs_through_dnf(self):
        result, recorded, _ = self.run_item("fedora", "dnf")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(recorded, "install -y make")

    def test_a_missing_manager_fails_before_installing_anything(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            build_installer(root)
            env = dict(os.environ)
            env.pop("DISPLAY", None)
            env.pop("WAYLAND_DISPLAY", None)
            env.update({"XT_OS": "debian", "XT_HEADLESS": "1"})
            result = subprocess.run(
                ["bash", str(root / "install.sh"), "--items", "make", "--force"],
                cwd=str(root),
                env=env,
                input="",
                capture_output=True,
                text=True,
                timeout=180,
            )
        self.assertEqual(result.returncode, 1)
        self.assertIn("refusing to start", result.stdout)
        self.assertIn("apt-get", result.stdout)
        self.assertNotIn("==> make", result.stdout, "the item must not run after a failed preflight")

    def test_a_failing_manager_halts_and_names_the_right_undo_command(self):
        result, recorded, audit = self.run_item("debian", "apt-get", manager_exit=1)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(recorded, "install -y make", "the manager must still be called")
        self.assertIn("apt-get remove", result.stdout)
        self.assertNotIn("dnf history undo", result.stdout)
        self.assertIn("FAIL make", audit)


if __name__ == "__main__":
    unittest.main()
