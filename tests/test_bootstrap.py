#!/usr/bin/env python3
"""The one-liner: pinned download, checksum verification, and the stdin trap.

Run: python3 -m unittest discover -s tests -v

Each test builds a throwaway release with scripts/dist.sh and serves it through a
file:// base URL, so the download, the checksum and the extraction are real while
nothing touches the network or this repository.
"""

import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]
COPY = ["install.sh", "bootstrap.sh", "VERSION", "catalog", "scripts", "docs", "README.md", "LICENSE"]


def build_release(root):
    """Copy the project into root and build a pinned release there. Returns the copy."""
    dst = root / "src"
    dst.mkdir()
    for entry in COPY:
        src = REPO / entry
        target = dst / entry
        if src.is_dir():
            shutil.copytree(src, target)
        else:
            shutil.copy2(src, target)
    built = subprocess.run(
        ["bash", str(dst / "scripts" / "dist.sh")],
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert built.returncode == 0, built.stderr
    return dst


def run_bootstrap(src, *args, cache_home=None, base_url=None, detach=False):
    env = dict(os.environ)
    env.pop("DISPLAY", None)
    env.pop("WAYLAND_DISPLAY", None)
    env.update({"XT_OS": "fedora", "XT_HEADLESS": "0"})
    env["TOOLBOX_BASE_URL"] = base_url or f"file://{src / 'dist'}"
    if cache_home:
        env["XDG_CACHE_HOME"] = str(cache_home)
    return subprocess.run(
        ["bash", str(src / "bootstrap.sh"), *args],
        cwd=str(src),
        env=env,
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        timeout=180,
        start_new_session=detach,
    )


class PinnedReleaseTest(unittest.TestCase):
    def test_version_matches_the_version_file(self):
        version = (REPO / "VERSION").read_text().strip()
        bootstrap = (REPO / "bootstrap.sh").read_text()
        self.assertIn(f'VERSION="{version}"', bootstrap)

    def test_bootstrap_refuses_to_run_unpinned(self):
        # The shipped bootstrap is pinned by a release; build an unpinned copy to prove
        # the guard still exists and still refuses.
        with tempfile.TemporaryDirectory() as tmp:
            unpinned = pathlib.Path(tmp) / "bootstrap.sh"
            text = (REPO / "bootstrap.sh").read_text()
            text, count = re.subn(r'^SHA256=.*$', 'SHA256="__SHA256__"', text, count=1, flags=re.M)
            self.assertEqual(count, 1, "bootstrap.sh has no SHA256 line to unpin")
            unpinned.write_text(text)

            env = dict(os.environ)
            env.update({"XT_OS": "fedora", "XT_HEADLESS": "0"})
            result = subprocess.run(
                ["bash", str(unpinned), "--dry-run", "--items", "git"],
                cwd=tmp,
                env=env,
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                timeout=180,
            )
        self.assertEqual(result.returncode, 1)
        self.assertIn("not pinned", result.stderr)


class BootstrapTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)
        self.src = build_release(self.root)
        self.cache = self.root / "cache"

    def tearDown(self):
        self.tmp.cleanup()

    def test_verified_download_runs_the_installer(self):
        result = run_bootstrap(self.src, "--dry-run", "--force", "--profile", "minimal", cache_home=self.cache)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("checksum ok", result.stdout)
        self.assertIn("[dry-run] install fresh", result.stdout)

    def test_second_run_uses_the_verified_cached_copy(self):
        first = run_bootstrap(self.src, "--list", cache_home=self.cache)
        self.assertEqual(first.returncode, 0, first.stderr)
        second = run_bootstrap(self.src, "--list", cache_home=self.cache)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertIn("using cached copy", second.stdout)

    def test_tampered_tarball_is_refused_before_anything_runs(self):
        version = (self.src / "VERSION").read_text().strip()
        tarball = self.src / "dist" / f"xentor-toolbox-{version}.tar.gz"
        with tarball.open("ab") as handle:
            handle.write(b"tampered")
        result = run_bootstrap(self.src, "--dry-run", "--force", "--profile", "minimal", cache_home=self.cache)
        self.assertEqual(result.returncode, 1)
        self.assertIn("checksum mismatch", result.stderr)
        self.assertNotIn("plan (", result.stdout)

    def test_help_works_through_the_bootstrap(self):
        result = run_bootstrap(self.src, "--help", cache_home=self.cache)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--items", result.stdout)

    def test_no_terminal_with_arguments_stays_silent_about_it(self):
        result = run_bootstrap(self.src, "--list", cache_home=self.cache, detach=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("/dev/tty", result.stderr)
        self.assertIn("git", result.stdout)

    def test_no_terminal_and_no_arguments_fails_fast_with_a_hint(self):
        result = run_bootstrap(self.src, cache_home=self.cache, detach=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("no terminal available", result.stderr)
        self.assertIn("bash -s --", result.stderr)


if __name__ == "__main__":
    unittest.main()
