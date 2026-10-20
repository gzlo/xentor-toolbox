# xentor-toolbox

Pick the tools you want. Install only those.

A catalog-driven installer for Fedora, Debian/Ubuntu and Arch: one tool per item,
each with its own "is this already here?" check, driven by a terminal wizard. No
dotfiles, no secrets, no telemetry — it installs tools and gets out of the way.

```bash
curl -fsSL https://raw.githubusercontent.com/gzlo/xentor-toolbox/main/bootstrap.sh | bash
```

That runs the wizard. Prefer to be explicit:

```bash
# a named bundle
curl -fsSL .../bootstrap.sh | bash -s -- --profile minimal

# exactly these tools
curl -fsSL .../bootstrap.sh | bash -s -- --items fresh,btop,ripgrep

# see the catalog first, change nothing
curl -fsSL .../bootstrap.sh | bash -s -- --list
curl -fsSL .../bootstrap.sh | bash -s -- --dry-run --profile dev
```

Or clone it and run `./install.sh` locally.

## Why items instead of a list of packages

A module-based installer is all-or-nothing: asking for one editor drags in a
compiler toolchain, a database client and a desktop stack. Here the unit is the
item, with a `check` that decides skip-vs-install, so:

- `--items fresh` installs fresh and nothing else;
- running it again a week later installs only what is new;
- an item that does not apply to your machine (wrong distro, no graphical session)
  is never offered, and asking for it by name is a clear error instead of a
  half-finished install.

## Profiles

| Profile | What it is |
|---|---|
| `minimal` | git, curl, archivers, search, a monitor, an editor |
| `shell` | zsh, prompt, fuzzy finding, modern CLI replacements |
| `dev` | compilers, runtimes, CLI tooling |
| `ai` | gentle-ai, opencode (+ `claude`/`gemini` behind their own flags) |
| `full` | every item in the catalog |

`--profile full` means "everything this host can take": a Debian VPS silently
skips the items that only exist on Fedora.

## Platform support

| Platform | Status |
|---|---|
| Fedora | primary |
| Debian / Ubuntu | supported for the items that ship there |
| Arch / Manjaro | supported for the items that ship there |
| headless / SSH | supported: GUI items are filtered out |

Detection reads `/etc/os-release` and `$DISPLAY`/`$WAYLAND_DISPLAY`. Override it
with `XT_OS=fedora|debian|arch` and `XT_HEADLESS=0|1`.

## Trust

The bootstrap is deliberately boring:

- it downloads **one pinned release tarball**, never `master`;
- it verifies the tarball's **SHA-256** and refuses to run on a mismatch;
- it extracts into `~/.cache/xentor-toolbox/<version>` so you can read exactly
  what ran, and re-runs reuse the verified copy;
- `sudo` is used only for the steps that need it, item by item;
- `--dry-run` prints the plan and writes nothing.

Read it before piping it. That advice applies to every `curl | bash` on the
internet, including this one: `curl -fsSL .../bootstrap.sh | less`.

## What it does not do

- No dotfiles and no `$HOME` config files: this installs software, it does not
  take over your configuration.
- No secrets, no tokens, no credentials, and nothing read from your environment.
- No telemetry, no analytics, no calling home.
- No uninstaller. Tools installed through your package manager come out through
  your package manager.

## Adding an item

1. Add an `item` block to `catalog/items.sh` — see [docs/catalog.md](docs/catalog.md)
   for the keys, methods and platform gating.
2. Add the id to the `full` profile in `catalog/profiles.sh`.
3. Run the suite:

```bash
python3 -m unittest discover -s tests -v
```

The tests are hermetic: platform detection is forced through `XT_OS`/`XT_HEADLESS`,
`gum` is replaced by a deterministic shim, and everything runs under `--dry-run`.

## Releases

```bash
./scripts/dist.sh          # builds the tarball, prints its sha256, pins it in bootstrap.sh
git tag -a v0.1.0 -m "v0.1.0"
gh release create v0.1.0 dist/xentor-toolbox-0.1.0.tar.gz
```

The tarball is built from the committed tree and excludes `bootstrap.sh`, so the
pinned hash never chases its own tail.

## License

MIT. See [LICENSE](LICENSE).
