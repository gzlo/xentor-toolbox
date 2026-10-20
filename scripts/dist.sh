#!/usr/bin/env bash
# scripts/dist.sh — build the release tarball, print its SHA-256 and pin that hash into
# bootstrap.sh. Run this before tagging: the tarball holds what is committed, so build
# it from a clean tree, pin, commit the pin, then tag and attach the tarball.
#
# Reproducible on purpose: sorted entries, fixed mtime and numeric owner, so rebuilding
# the same tree yields the same hash.
set -euo pipefail

TB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(cat "$TB_DIR/VERSION")"
NAME="xentor-toolbox-${VERSION}"
OUT="$TB_DIR/dist"

command -v sha256sum >/dev/null 2>&1 || { echo "[ERROR] sha256sum is required" >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT/$NAME"

for entry in install.sh scripts catalog shell docs README.md LICENSE VERSION; do
  [[ -e "$TB_DIR/$entry" ]] || { echo "[ERROR] missing $entry" >&2; exit 1; }
  cp -a "$TB_DIR/$entry" "$OUT/$NAME/"
done

tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
  -czf "$OUT/$NAME.tar.gz" -C "$OUT" "$NAME"

SHASUM="$(sha256sum "$OUT/$NAME.tar.gz" | cut -d' ' -f1)"
printf '%s\n' "$SHASUM"

python3 - "$TB_DIR/bootstrap.sh" "$SHASUM" <<'PY'
import pathlib, re, sys
path, shasum = pathlib.Path(sys.argv[1]), sys.argv[2]
text = path.read_text()
new, count = re.subn(r'^SHA256=.*$', f'SHA256="{shasum}"', text, count=1, flags=re.M)
if count != 1:
    raise SystemExit("could not find the SHA256 line in bootstrap.sh")
path.write_text(new)
PY

rm -rf "$OUT/$NAME"
echo "pinned into bootstrap.sh: $SHASUM"
echo "tarball: $OUT/$NAME.tar.gz"
