#!/usr/bin/env bash
# scripts/summary.sh — post-run housekeeping: empty tmp/, archive the run logs, print a
# short summary. Run by install.sh only after a real, successful install (never on
# --dry-run).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -d "$TB_DIR/tmp" ]]; then
  rm -rf "${TB_DIR:?}/tmp"/* 2>/dev/null || true
  log_ok "tmp/ emptied"
fi

if [[ -d "$TB_DIR/logs" ]]; then
  ts="$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$TB_DIR/logs/archive/$ts"
  if compgen -G "$TB_DIR/logs/run-*.log" >/dev/null; then
    mv "$TB_DIR"/logs/run-*.log "$TB_DIR/logs/archive/$ts/"
    log_ok "logs archived -> logs/archive/$ts/"
  else
    log_info "no run logs to archive"
  fi
fi

echo
log_ok "=== xentor-toolbox summary ==="
log_ok "items selected: ${SUMMARY_SELECTED:-see log}"
echo
log_ok "Done. Reload your shell: exec \$SHELL"
