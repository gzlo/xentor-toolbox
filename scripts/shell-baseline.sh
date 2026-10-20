#!/usr/bin/env bash
# scripts/shell-baseline.sh — install the base zsh configuration without taking over
# the user's dotfiles.
#
# It touches exactly three things:
#   ~/.config/xentor-toolbox/shell.zsh   the baseline file (overwritten on reinstall)
#   ~/.zshrc                             one managed block between markers, nothing else
#   ~/.shell.local                       created only when missing, mode 600, never edited
#
# Every step is idempotent; re-running replaces the block instead of appending a second.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="${ACTUAL_HOME:-$HOME}/.config/xentor-toolbox"
TARGET_FILE="$TARGET_DIR/shell.zsh"
ZSHRC="${ACTUAL_HOME:-$HOME}/.zshrc"
SHELL_LOCAL="${ACTUAL_HOME:-$HOME}/.shell.local"

START_MARKER="# >>> xentor-toolbox >>>"
END_MARKER="# <<< xentor-toolbox <<<"

read -r -d '' BLOCK <<EOF || true
$START_MARKER
# Managed by xentor-toolbox. Edits inside this block are overwritten on reinstall.
# Personal aliases, exports and functions belong in ~/.shell.local (sourced last).
[ -f "\$HOME/.config/xentor-toolbox/shell.zsh" ] && source "\$HOME/.config/xentor-toolbox/shell.zsh"
[ -f "\$HOME/.shell.local" ] && source "\$HOME/.shell.local"
$END_MARKER
EOF

install_baseline_file() {
  mkdir -p "$TARGET_DIR"
  install -m 644 "$TB_DIR/shell/base.zsh" "$TARGET_FILE"
  log_ok "baseline written to $TARGET_FILE"
}

install_block() {
  local tmp
  touch "$ZSHRC"
  tmp="$(mktemp "${ZSHRC}.XXXXXX")"
  # Drop any previous block, keep everything else byte for byte.
  awk -v start="$START_MARKER" -v end="$END_MARKER" '
    $0 == start { skip = 1; next }
    $0 == end   { skip = 0; next }
    !skip       { print }
  ' "$ZSHRC" > "$tmp"
  # Never leave a trailing blank line before our block.
  if [[ -s "$tmp" ]] && [[ -z "$(tail -c 1 "$tmp")" ]]; then :; fi
  printf '\n%s\n' "$BLOCK" >> "$tmp"
  chmod --reference="$ZSHRC" "$tmp" 2>/dev/null || chmod 644 "$tmp"
  mv "$tmp" "$ZSHRC"
  log_ok "managed block installed in $ZSHRC"
}

install_shell_local() {
  if [[ -e "$SHELL_LOCAL" ]]; then
    log_ok "$SHELL_LOCAL already exists — left untouched"
    return 0
  fi
  cat > "$SHELL_LOCAL" <<'EOF'
# ~/.shell.local — personal aliases, exports and functions.
#
# Sourced by ~/.zshrc after the xentor-toolbox baseline, so anything here wins.
# Never managed by the installer: create it once and edit it freely.

# alias gs='git status --short --branch'
# export EDITOR=fresh
EOF
  chmod 600 "$SHELL_LOCAL"
  log_ok "$SHELL_LOCAL created (0600) — put your personal aliases here"
}

case "${1:-install}" in
  install)
    install_baseline_file
    install_block
    install_shell_local
    ;;
  *)
    printf '[ERROR] usage: shell-baseline.sh install\n' >&2
    exit 2
    ;;
esac
