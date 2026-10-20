#!/usr/bin/env bash
# xentor-toolbox bootstrap — the only script you are meant to pipe into bash:
#
#   curl -fsSL https://raw.githubusercontent.com/gzlo/xentor-toolbox/main/bootstrap.sh | bash
#   curl -fsSL ... | bash -s -- --profile minimal
#   curl -fsSL ... | bash -s -- --list
#
# It downloads one pinned release tarball, verifies its SHA-256, extracts it into the
# user cache and hands over to the installer. It never runs code from a moving branch.
set -euo pipefail

VERSION="0.1.2"
BASE_URL="${TOOLBOX_BASE_URL:-https://github.com/gzlo/xentor-toolbox/releases/download/v${VERSION}}"
TARBALL="xentor-toolbox-${VERSION}.tar.gz"
# Pinned by scripts/dist.sh at release time. A placeholder here means "not released yet"
# and the bootstrap refuses to run.
SHA256="c9ca2ae0295ce21d180f9e7177327f1beb460dfa161de264ded125bc24106ee5"

die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
info() { printf '[INFO]  %s\n' "$*"; }

# `curl | bash` gives the script the pipe as stdin, so the wizard could never read a
# keystroke. Reattach the controlling terminal when there is one.
if [[ ! -t 0 ]]; then
  # Probe in a subshell so a missing terminal cannot leak a redirection error.
  if ( : </dev/tty ) 2>/dev/null; then
    exec 0</dev/tty
  else
    case " $* " in
      *" --items "*|*" --profile "*|*" --list "*|*" --list-profiles "*|*" --dry-run "*|*" --help "*|*" -h "*) ;;
      *) die "no terminal available and no selection given. Pipe it with arguments instead, e.g.: curl -fsSL <url> | bash -s -- --profile minimal" ;;
    esac
  fi
fi

[[ "$SHA256" != "__SHA256__" ]] || die "this bootstrap is not pinned to a release yet — download the installer from a tagged release instead"

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required (coreutils)"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/xentor-toolbox/${VERSION}"
install_dir="$cache_dir/xentor-toolbox-${VERSION}"
mkdir -p "$cache_dir"

if [[ ! -f "$install_dir/install.sh" ]]; then
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' EXIT

  info "downloading xentor-toolbox ${VERSION}"
  curl -fsSL -o "$workdir/$TARBALL" "$BASE_URL/$TARBALL" \
    || die "download failed: $BASE_URL/$TARBALL"

  actual="$(sha256sum "$workdir/$TARBALL" | cut -d' ' -f1)"
  if [[ "$actual" != "$SHA256" ]]; then
    die "checksum mismatch — refusing to run. expected ${SHA256}, got ${actual}"
  fi
  info "checksum ok"

  tar -xzf "$workdir/$TARBALL" -C "$cache_dir" || die "could not extract $TARBALL"
  [[ -f "$install_dir/install.sh" ]] || die "unexpected archive layout: install.sh not found"
else
  info "using cached copy at $install_dir"
fi

bash "$install_dir/install.sh" "$@"
