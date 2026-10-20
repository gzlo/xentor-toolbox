#!/usr/bin/env python3
"""The real (non dry-run) execution path, exercised safely.

Run: python3 -m unittest discover -s tests -v

The installer is copied into a throwaway directory and driven with an item whose
check passes, so the run executes the engine, the audit log and the summary
housekeeping without installing anything and without touching this repository.
"""

import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]
COPIED = ["install.sh", "catalog", "scripts"]


def build_copy(tmp_dir):
    for entry in COPIED:
        src = REPO / entry
        dst = tmp_dir / entry
        if src.is_dir():
            shutil.copytree(src, dst)
        else:
            shutil.copy2(src, dst)
    (tmp_dir / "install.sh").chmod(0o755)


class RealRunTest(unittest.TestCase):
    def test_a_run_with_everything_already_installed_does_not_install(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = pathlib.Path(tmp)
            build_copy(tmp_dir)

            fake_bin = tmp_dir / "fake-bin"
            fake_bin.mkdir()
            fake_git = fake_bin / "git"
            fake_git.write_text("#!/bin/sh\nexit 0\n")
            fake_git.chmod(0o755)

            env = dict(os.environ)
            env.update({"XT_OS": "fedora", "XT_HEADLESS": "0"})
            env["PATH"] = f"{fake_bin}{os.pathsep}{env.get('PATH', '')}"

            result = subprocess.run(
                ["bash", str(tmp_dir / "install.sh"), "--items", "git"],
                cwd=str(tmp_dir),
                env=env,
                input="",
                capture_output=True,
                text=True,
                timeout=180,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("already installed", result.stdout)
            self.assertIn("install complete", result.stdout)

            logs = list((tmp_dir / "logs").rglob("run-*.log"))
            self.assertTrue(logs, "a real run must leave a log file")
            log_text = "".join(p.read_text() for p in logs)
            self.assertIn("SKIP git", log_text)


if __name__ == "__main__":
    unittest.main()
