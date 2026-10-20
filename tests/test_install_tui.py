#!/usr/bin/env python3
"""Contract tests for the interactive wizard.

Run: python3 -m unittest discover -s tests -v

gum is replaced by a deterministic shim that answers one canned menu line per
call, and the gum-less path is exercised with a PATH that contains only the
binaries install.sh actually needs. Nothing is installed: every run is --dry-run.
"""

import os
import pathlib
import re
import subprocess
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]
INSTALL = REPO / "install.sh"

INSTALL_LINE = re.compile(r"^\[dry-run\] install (\S+)$")

FAKE_GUM = """#!/usr/bin/env bash
set -u
queue="${FAKE_GUM_QUEUE:?}"
counter="${FAKE_GUM_COUNTER:?}"
n=0
[[ -f "$counter" ]] && n="$(cat "$counter")"
cmd="${1:-}"
case "$cmd" in
  confirm) exit "${FAKE_GUM_CONFIRM:-0}" ;;
  choose)
    n=$((n + 1))
    printf '%s' "$n" > "$counter"
    sed -n "${n}p" "$queue" | { IFS= read -r line || true; printf '%b\\n' "$line"; }
    ;;
  *) exit 0 ;;
esac
"""

# Minimal binary set the installer needs, so the gum-less path can run without /usr/bin.
GUM_FREE_BINARIES = ["bash", "dirname", "sed", "head", "tr", "id", "getent", "cut"]

MINIMAL = ["git", "curl", "wget", "unzip", "tar", "gzip", "btop", "ripgrep", "fd", "jq", "fresh"]

ANSWERS_PROFILE = ["profile", "minimal"]
ANSWERS_CATEGORY = ["by-category", "editor", "fresh"]
ANSWERS_QUIT = ["quit"]


def planned(result):
    return [
        INSTALL_LINE.match(line.strip()).group(1)
        for line in result.stdout.splitlines()
        if INSTALL_LINE.match(line.strip())
    ]


def run_tui(answers, *, gum=True, confirm=0, stdin_text="", os_name="fedora"):
    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = pathlib.Path(tmp)
        queue = tmp_dir / "queue"
        queue.write_text("\n".join(answers) + "\n")
        counter = tmp_dir / "counter"

        env = dict(os.environ)
        env.pop("DISPLAY", None)
        env.pop("WAYLAND_DISPLAY", None)
        env.update(
            {
                "XT_OS": os_name,
                "XT_HEADLESS": "0",
                "FAKE_GUM_QUEUE": str(queue),
                "FAKE_GUM_COUNTER": str(counter),
                "FAKE_GUM_CONFIRM": str(confirm),
            }
        )

        bindir = tmp_dir / "bin"
        bindir.mkdir()
        if gum:
            shim = bindir / "gum"
            shim.write_text(FAKE_GUM)
            shim.chmod(0o755)
            env["PATH"] = f"{bindir}{os.pathsep}{env.get('PATH', '')}"
        else:
            for name in GUM_FREE_BINARIES:
                target = pathlib.Path("/usr/bin") / name
                if not target.exists():
                    target = pathlib.Path("/bin") / name
                (bindir / name).symlink_to(target)
            env["PATH"] = str(bindir)

        return subprocess.run(
            ["bash", str(INSTALL), "--tui", "--dry-run", "--force"],
            cwd=str(REPO),
            env=env,
            input=stdin_text,
            capture_output=True,
            text=True,
            timeout=180,
        )


class GumWizardTest(unittest.TestCase):
    def test_profile_flow_plans_the_profile_items(self):
        result = run_tui(ANSWERS_PROFILE)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(planned(result), MINIMAL)

    def test_category_flow_plans_only_the_picked_items(self):
        result = run_tui(ANSWERS_CATEGORY)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(planned(result), ["fresh"])

    def test_quit_installs_nothing(self):
        result = run_tui(ANSWERS_QUIT)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(planned(result), [])

    def test_declined_confirmation_installs_nothing(self):
        result = run_tui(ANSWERS_PROFILE, confirm=1)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(planned(result), [])
        self.assertIn("cancelled", result.stdout)


class FallbackWizardTest(unittest.TestCase):
    def test_without_gum_the_numbered_menu_still_works(self):
        result = run_tui([], gum=False, stdin_text="1\ny\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(planned(result), MINIMAL)

    def test_without_gum_a_declined_confirmation_installs_nothing(self):
        result = run_tui([], gum=False, stdin_text="1\nn\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(planned(result), [])

    def test_without_gum_an_invalid_choice_exits_2(self):
        result = run_tui([], gum=False, stdin_text="99\n")
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
