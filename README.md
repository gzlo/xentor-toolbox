# xentor-toolbox

Pick the tools you want. Install only those.

A catalog-driven installer for Fedora, Debian/Ubuntu and Arch: one tool per item,
each with its own "is this already here?" check, driven by a terminal wizard. It
installs tools plus a minimal, reversible shell baseline — no secrets, no telemetry,
and it never rewrites your dotfiles.

```bash
curl -fsSL https://raw.githubusercontent.com/gzlo/xentor-toolbox/v0.3.0/bootstrap.sh | bash
```

The URL points at a **tag**, not at `main`: the entry point is immutable. Any fix
to the bootstrap itself ships as a patch release, so what you audit today is what
runs tomorrow.

That runs the wizard. Its `preview` action picks items and shows the plan without
installing anything — use it before a first real run. Prefer to be explicit:

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
| `minimal` | git, curl, archivers, search, a monitor, zsh + shell baseline, an editor |
| `shell` | the above plus prompt, fuzzy finding, modern CLI replacements and herdr |
| `dev` | compilers, runtimes, CLI tooling |
| `ai` | AI toolchain (+ `claude`/`gemini` behind their own flags) |
| `full` | every item in the catalog |

**zsh and a blue prompt are the base in every profile.** Every bundle installs `zsh`,
makes it the login shell, installs the shell baseline and installs starship with a
blue prompt, so you never end up on a machine with tools, no shell and no prompt.
starship comes from the native package on Fedora and Arch, and from the official
binary on anything else — no package required.

`--items` stays exact by design: it installs only what you name. Add
`--with-baseline` to keep the guarantee there too — it also works on its own
(`./install.sh --with-baseline` installs just the shell setup).

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

## What it changes on your machine

Exactly four things, all reversible, all inspectable:

| Path | What happens |
|---|---|
| login shell | set to `zsh` with `chsh` (skipped when already zsh) |
| `~/.config/xentor-toolbox/shell.zsh` | the baseline: colours, a few safe aliases, history, completion, starship prompt. Overwritten on reinstall |
| `~/.config/starship.toml` | the default blue prompt, written **only when you have no prompt config**; yours is never touched |
| `~/.zshrc` | **one managed block** between `# >>> xentor-toolbox >>>` markers. Everything outside the markers is untouched |
| `~/.shell.local` | created once (mode 600) and **never edited again**: your aliases, exports and functions, sourced last so they win |

Everything else is package-manager work or a binary in `~/.local/bin`.

A run that cannot work never starts: if a selected package item needs a manager that
is not installed here (for example `XT_OS=debian` on a host without `apt`), the
installer refuses before touching anything and tells you which items are affected.

## Personalisation

Put your own shortcuts in `~/.shell.local`:

```bash
# ~/.shell.local
alias gs='git status --short --branch'
alias k='herdr'
export EDITOR=fresh
```

The baseline is deliberately boring: `ll`, `la`, `..`, coloured `ls`/`grep`/`diff`,
history with de-duplication and shared history, and `compinit`.

The prompt is blue out of the box (`#86BBD8` character, `#33658A` branch) and needs no
Nerd Font. Want your own? Edit `~/.config/starship.toml` — the installer never
overwrites an existing file, and `STARSHIP_CONFIG` still wins if you point it
elsewhere.

## Terminal multiplexer

This setup uses **herdr**, not tmux: `herdr` is an item in the catalog and is part of
the `shell` profile. If you prefer tmux, install it yourself — the installer does not
pick a second multiplexer.

## What it does not do

- No dotfiles manager: one managed block in `~/.zshrc`, nothing else.
- No secrets, no tokens, no credentials, and nothing read from your environment.
- No telemetry, no analytics, no calling home.
- No uninstaller. Tools installed through your package manager come out through
  your package manager; delete the shell baseline and its block if you want it gone.

## Adding an item

1. Add an `item` block to `catalog/items.sh` — see [docs/catalog.md](docs/catalog.md)
   for the keys, methods and platform gating. Multi-step items get a script under
   `scripts/` (see `shell-baseline.sh` for the pattern).
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
