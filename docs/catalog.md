# Catalog reference

The installer is data-driven: `catalog/` declares what can be installed and
`install.sh` + `scripts/` decide what to run. No tool is hardcoded in a script.

```
bootstrap.sh            the one-liner: pinned download, checksum, then install.sh
install.sh              CLI: parse args, resolve the selection, hand it to the engine
catalog/items.sh        the items
catalog/profiles.sh     named bundles
scripts/catalog.sh      DSL, loader, platform detection, visibility, ordering
scripts/engine.sh       plan and execute items
scripts/tui.sh          wizard (gum) and numbered fallback
scripts/summary.sh      post-run housekeeping
scripts/dist.sh         release tarball + checksum pin
scripts/lib.sh          logging, sudo, audit, backup helpers
```

## Item DSL

One `item` call per tool:

```bash
item fresh \
  label="Fresh" \
  desc="Terminal code editor" \
  category=editor \
  platforms="any" \
  method=script \
  check="command -v fresh" \
  install='FRESH_INSTALL_DIR=... sh -c "$(curl -fsSL .../install.sh)"'
```

| Key | Required | Meaning |
|---|---|---|
| `label` | | Human name shown in the wizard |
| `desc` | | One-line description |
| `category` | yes | `base`, `shell`, `editor`, `dev`, `ai`, `container` |
| `platforms` | | space-separated `fedora debian arch`, or `any` (default) |
| `method` | | `pkg` (default `custom`) — see below |
| `gui` | | `1` when the item needs a graphical session |
| `check` | | shell test that proves the item is installed |
| `deps` | | item ids to order before this one |
| `install` | | shell command for every method except `pkg` and `manual` |
| `hint` | | message printed for `manual` items |
| `gate` | | opt-in flag: `claude` or `gemini` |
| `pkg_fedora` / `pkg_debian` / `pkg_arch` | `pkg` | package name(s) per platform; several names may be space-separated |

Declaration order is the default execution order. `deps` only constrains items
that are part of the same selection; a dependency outside the selection is
ordering information, not an implicit install.

Only tools that actually install something belong in the public catalog: a
`manual` item that just prints advice is noise for a stranger running this.

## Methods

| Method | Behavior |
|---|---|
| `pkg` | installs `pkg_<platform>` through dnf / apt-get / pacman |
| `script` | runs `install` (usually an upstream installer) |
| `binary` | runs `install` (downloads a pinned or latest binary into `~/.local/bin`) |
| `go` / `cargo` / `npm` / `pipx` | run `install`; the method documents the toolchain the item needs |
| `flatpak` | runs `install` |
| `custom` | runs `install`; anything that needs more than one step |
| `manual` | prints `hint`, never fails the run |

`install` strings are evaluated by a child bash that first sources
`scripts/lib.sh`, so they may use `sudo_run`, `log_*` and the exported
`$TB_DIR`, `$ACTUAL_HOME`, `$SUDO` environment. Quote them with **single quotes**
when they reference those variables, or the value expands at catalog load time.

## Platform and headless gating

Detection: `/etc/os-release` → `fedora` | `debian` (Ubuntu, Mint, Pop) | `arch`
(Manjaro, EndeavourOS); `$DISPLAY`/`$WAYLAND_DISPLAY` → graphical vs headless.

Overrides (also what the tests use):

```bash
XT_OS=debian XT_HEADLESS=1 ./install.sh --list
```

- An item whose `platforms` does not include the host is **hidden** from `--list`
  and from the wizard.
- A `gui=1` item is hidden when the host is headless.
- `--items` naming an unavailable item is a **usage error** (exit 2) that names
  the item and the reason.
- A **profile silently drops** items that are unavailable here.

## Portability notes

- Debian renamed a few binaries: `fd` is `fdfind` and `bat` is `batcat` there, so
  those items check for either name.
- Package availability differs; an item that has no package for your platform
  simply does not appear in `--list`.

## The shell baseline

`shell-baseline` (with `zsh` and `zsh-default`) is the only item that writes to your
home directory. It installs `~/.config/xentor-toolbox/shell.zsh`, adds one managed
block to `~/.zshrc` and creates `~/.shell.local` (0600) once. It is part of every
profile, and `--with-baseline` adds it to an explicit `--items` selection.

## Adding an item

1. Add the `item` block to `catalog/items.sh` with a `check` that is true exactly
   when the tool is usable.
2. Add the id to the `full` profile in `catalog/profiles.sh` — the completeness
   test fails otherwise.
3. If the tool needs a sibling tool first, declare `deps`.
4. Run `python3 -m unittest discover -s tests -v`.
