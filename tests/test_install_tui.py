#!/usr/bin/env python3
"""Contract tests for the interactive wizard.

Run: python3 -m unittest discover -s tests -v

gum is replaced by a deterministic shim that answers one canned menu line per
call, and the gum-less path is exercised with a PATH that contains only the
binaries install.sh actually needs. Nothing is installed: every run is --dry-run.

The wizard must always show what can be installed, and an empty selection must
return to the menu instead of ending the run.
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
  pager) cat ;;
  choose)
    n=$((n + 1))
    printf '%s' "$n" > "$counter"
    sed -n "${n}p" "$queue" | { IFS= read -r line || true; printf '%b\\n' "$line"; }
    ;;
  *) exit 0 ;;
esac
"""

# Minimal binary set the installer needs, so the gum-less path can run without /usr/bin.
GUM_FREE_BINARIES = ["bash", "dirname", "sed", "head", "tr", "id", "getent", "cut", "wc"]

MINIMAL = ["git", "curl", "wget", "unzip", "tar", "gzip", "btop", "ripgrep", "fd", "jq", "zsh", "zsh-default", "shell-baseline", "starship", "fresh"]


def planned(result):
    return [
        INSTALL_LINE.match(line.strip()).group(1)
        for line in result.stdout.splitlines()
        if INSTALL_LINE.match(line.strip())
    ]


def run_tui(answers, *, gum=True, confirm=0, stdin_text="", os_name="fedora", dry_run=True):
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

        args = ["bash", str(INSTALL), "--tui", "--force"]
        if dry_run:
            args.insert(3, "--dry-run")
        return subprocess.run(
            args,
            cwd=str(REPO),
            env=env,
            input=stdin_text,
            capture_output=True,
            text=True,
            timeout=180,
        )


class GumWizardTest(unittest.TestCase):
    def test_items_flow_lists_every_item_and_plans_the_picked_one(self):
        result = run_tui(["items", "fresh  Fresh [editor] Terminal code editor"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(planned(result), ["fresh"])

    def test_profile_flow_plans_the_profile_items(self):
        result = run_tui(["profile", "minimal"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(planned(result), MINIMAL)

    def test_catalog_action_shows_descriptions(self):
        result = run_tui(["catalog", "quit"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("WHAT IT IS", result.stdout)
        self.assertIn("Version control", result.stdout)
        self.assertIn("items available here", result.stdout)

    def test_empty_selection_returns_to_the_menu_instead_of_exiting(self):
        # items -> enter with nothing toggled -> decline "Pick again?" -> quit
        result = run_tui(["items", "", "quit"], confirm=1)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("nothing picked", result.stdout)
        self.assertEqual(planned(result), [])

    def test_preview_action_plans_without_installing(self):
        result = run_tui(["preview", "fresh  Fresh [editor] Terminal code editor"], dry_run=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("preview mode", result.stdout)
        self.assertEqual(planned(result), ["fresh"])
        self.assertIn("no changes made (dry-run)", result.stdout)

    def test_quit_installs_nothing(self):
        result = run_tui(["quit"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(planned(result), [])

    def test_declined_confirmation_installs_nothing(self):
        result = run_tui(["items", "fresh"], confirm=1)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(planned(result), [])
        self.assertIn("cancelled", result.stdout)


class FallbackWizardTest(unittest.TestCase):
    def test_without_gum_items_are_listed_and_pickable_by_number(self):
        result = run_tui([], gum=False, stdin_text="i\n1\ny\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(planned(result), ["git"])
        self.assertIn("Available on fedora", result.stderr)

    def test_without_gum_a_range_picks_several_items(self):
        result = run_tui([], gum=False, stdin_text="i\n1-3\ny\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(planned(result), ["git", "curl", "wget"])

    def test_without_gum_a_profile_still_works(self):
        result = run_tui([], gum=False, stdin_text="1\ny\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(planned(result), MINIMAL)

    def test_without_gum_the_catalog_is_visible(self):
        result = run_tui([], gum=False, stdin_text="c\n\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("WHAT IT IS", result.stdout)
        self.assertEqual(planned(result), [])

    def test_without_gum_a_declined_confirmation_installs_nothing(self):
        result = run_tui([], gum=False, stdin_text="1\nn\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(planned(result), [])

    def test_without_gum_an_invalid_choice_exits_2(self):
        result = run_tui([], gum=False, stdin_text="99\n")
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
