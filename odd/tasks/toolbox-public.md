# toolbox-public — a public, credential-free tool catalog with a one-liner

Split the catalog installer built in `xentor-workstation` into a public repository
that anyone can run with one line, containing tools only: no personal hardware
items, no dotfiles, no secrets, and a bootstrap that verifies what it downloads.

## Specs

S1 — **One-liner entry point.** `curl -fsSL <url> | bash` must work, like the
reference the user named: *"algo como lo que tiene este repositorio:
curl -fsSL christitus.com/linux | sh"*.

S2 — **It is a pool of tools, selectable one by one.** *"tener un pool de tools
que pueda ser un repo público"*: the catalog is the product; the user picks items
or a bundle.

S3 — **Clean and shareable.** *"sin credenciales ni nada algo limpio que pueda
recomendar a muchos usuarios"*: no secrets, no tokens, nothing read from the
user's environment, no telemetry, no config takeover.

S4 — **Pinned and verified.** The bootstrap downloads one pinned release tarball,
verifies its SHA-256, and refuses to run on a mismatch. It never executes code
from a moving branch.

S5 — **The stdin trap.** `curl | bash` gives the script the pipe as stdin, so the
wizard cannot read a keystroke. The bootstrap reattaches the controlling
terminal, and fails fast with a usable hint when there is none.

S6 — **Curated, portable catalog.** Only tools that actually install something,
with per-platform package names; personal/hardware items stay out. Profiles:
`minimal`, `shell`, `dev`, `ai`, `full`.

S7 — **Hermetic tests.** Platform and headless detection forced through
`XT_OS`/`XT_HEADLESS`, gum replaced by a shim, the download served from `file://`,
and every run under `--dry-run` so nothing is installed.

## Design decisions (fixed)

- New repository `gzlo/xentor-toolbox`, MIT, public. `xentor-workstation` and
  `xentor-dotfiles` stay private and untouched: the public repo carries no
  personal history to audit.
- The installer core (`install.sh`, `scripts/{catalog,engine,tui,lib}.sh`) is the
  one proven in the workstation branch, minus the legacy `--modules` map.
- `scripts/dist.sh` builds a reproducible tarball (sorted entries, fixed mtime,
  numeric owner) and pins its SHA-256 into `bootstrap.sh`. The tarball excludes
  `bootstrap.sh`, so the pin never chases its own tail.
- The verified copy is extracted into `~/.cache/xentor-toolbox/<version>`, so a
  user can read exactly what ran and re-runs reuse it.
- `manual` (hint-only) items are excluded: advice is noise for a stranger.
- Dropped from the public catalog: ML4W, Hyprland, NVIDIA, CUDA, flatpaks,
  `dotfiles`, `secrets`, `doctl`, `gnome-tweaks`, `dokploy-cli`, `shopify-cli`,
  and the Docker engine itself (its per-distro repo setup is a separate decision;
  `lazydocker` stays).

## Tasks

| ID | Task | Specs | Route | Commit |
|----|------|-------|-------|--------|
| T1 | Scaffold, curated 44-item catalog, profiles, adapted core scripts | S2,S6 | inline | initial |
| T2 | `bootstrap.sh` + `scripts/dist.sh` | S1,S4,S5 | inline | initial |
| T3 | Four ported suites + `test_bootstrap.py` (31 tests) | S7 | inline | initial |
| T4 | README (EN), `docs/catalog.md`, this document | S3 | inline | initial |
| T5 | Public repo, push, release `v0.1.0` with tarball asset and pinned sha | S1,S4 | inline | release commit |

## Delivery

Single initial commit plus one release commit that pins the tarball hash, then tag
`v0.1.0`. The bootstrap is verified end to end through the real public URL before
the release is announced.

## Log

L1 (user, verbatim): "una de las cosas que quiero lograr es que el repo se pueda
hacer con mis configuraciones algo como lo que tiene este repositorio :
curl -fsSL christitus.com/linux | sh tener un pool de tools que pueda ser unrepo
púbico que me permita hacer algo como esto pero teniendo en cuenta mi sistema sin
credenciales ni nada algo limpio que pueda recomendar a muchso usuarios"

L2 (decision, user): scope = "Solo herramientas: repo público nuevo". Tools only;
personal items and dotfiles stay in the private repos; no history audit needed.

L3 (context, parent): the catalog core already exists in `xentor-workstation`
(branch `feat/install-wizard`, PRs #2-#6). Both existing repos are private, so a
public one-liner cannot live in them.
