#!/usr/bin/env bash
# xentor-toolbox — pick the tools you want, install only those.
#   ./install.sh                                  interactive wizard
#   ./install.sh --profile minimal                install a bundle
#   ./install.sh --items fresh,btop               install exactly these items
#   ./install.sh --list                           TSV: id, category, platforms, state
#   ./install.sh --dry-run --items fresh          print the plan, change nothing
#   ./install.sh --help
set -euo pipefail

TB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TB_DIR
# shellcheck source=scripts/lib.sh
source "$TB_DIR/scripts/lib.sh"
# shellcheck source=scripts/catalog.sh
source "$TB_DIR/scripts/catalog.sh"
# shellcheck source=scripts/engine.sh
source "$TB_DIR/scripts/engine.sh"
# shellcheck source=scripts/tui.sh
source "$TB_DIR/scripts/tui.sh"

ITEMS_ARG=""
PROFILE_ARG=""
DRY_RUN=0
FORCE=0
VERBOSE=0
CLAUDE=0
GEMINI=0
INTERACTIVE=0
YES=0
DO_TUI=0
DO_LIST=0
DO_LIST_PROFILES=0
DO_HELP=0

# Resolved, ordered, de-duplicated item ids.
SELECTION=()

usage() {
  cat <<'EOF'
xentor-toolbox — pick items, install only those.

Usage:
  ./install.sh [options]

Selection:
  --items <id,id>        Install exactly these catalog items (see --list).
  --profile <name>       Install a named bundle: minimal, shell, dev, ai, full
                         (see --list-profiles).

Output and control:
  --list                 Print the catalog as TSV:
                         id, category, platforms, installed|missing
  --list-profiles        Print the available profiles as TSV: name, label
  --dry-run              Print the plan and make no changes.
  --tui                  Force the interactive wizard (also runs without a TTY).
  --yes                  Skip the wizard confirmation prompt.
  --force                Install even when the item's check already passes.
  --verbose              Print the exact command of every item before running it.
  --claude               Enable the gated items that need --claude.
  --gemini               Enable the gated items that need --gemini.
  --help                 Show this help.

With no selection and a terminal, the interactive wizard runs.

Platform detection: XT_OS (fedora|debian|arch) and XT_HEADLESS (0|1) override
autodetection. Items that do not support the current platform, and GUI items on a
headless host, are hidden from --list and rejected when requested with --items.

Exit codes: 0 success, 1 runtime failure, 2 usage or unknown selection.
EOF
}

die_usage() { printf '[ERROR] %s\n' "$*" >&2; exit 2; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --items)         [[ $# -ge 2 ]] || die_usage "--items needs a value"; ITEMS_ARG="$2"; shift 2 ;;
      --profile)       [[ $# -ge 2 ]] || die_usage "--profile needs a value"; PROFILE_ARG="$2"; shift 2 ;;
      --list)          DO_LIST=1; shift ;;
      --list-profiles) DO_LIST_PROFILES=1; shift ;;
      --dry-run)       DRY_RUN=1; shift ;;
      --tui)           DO_TUI=1; shift ;;
      --yes|-y)        YES=1; shift ;;
      --force)         FORCE=1; shift ;;
      --verbose)       VERBOSE=1; shift ;;
      --claude)        CLAUDE=1; shift ;;
      --gemini)        GEMINI=1; shift ;;
      --help|-h)       DO_HELP=1; shift ;;
      *)               die_usage "unknown option: $1" ;;
    esac
  done
}

# append_lines <newline-separated ids> — append non-empty lines to SELECTION.
append_lines() {
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    SELECTION+=("$line")
  done <<< "${1:-}"
}

# resolve_selection — union of --items and --profile, validated and ordered.
resolve_selection() {
  local out name
  local -a profiles=()

  if [[ -n "$ITEMS_ARG" ]]; then
    out="$(catalog_select_items "$ITEMS_ARG")" || exit 2
    append_lines "$out"
  fi

  if [[ -n "$PROFILE_ARG" ]]; then
    IFS=',' read -ra profiles <<< "$PROFILE_ARG"
    for name in "${profiles[@]}"; do
      name="${name// /}"
      [[ -n "$name" ]] || continue
      out="$(catalog_select_profile "$name")" || exit 2
      append_lines "$out"
    done
  fi

  [[ ${#SELECTION[@]} -gt 0 ]] || die_usage "nothing selected — use --items or --profile"
}

main() {
  parse_args "$@"

  if ((DO_HELP)); then usage; exit 0; fi

  catalog_load
  catalog_detect_platform

  if [[ "$(id -u)" -eq 0 ]]; then SUDO="none"; else SUDO="sudo"; fi
  ACTUAL_HOME="${SUDO_USER:+$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6 || true)}"
  : "${ACTUAL_HOME:=$HOME}"
  export SUDO ACTUAL_HOME

  if ((DO_LIST)); then catalog_print_list; exit 0; fi
  if ((DO_LIST_PROFILES)); then catalog_print_profiles; exit 0; fi

  if [[ -z "$ITEMS_ARG" && -z "$PROFILE_ARG" ]]; then
    if ((DO_TUI)) || { [[ -t 0 && -t 1 ]]; }; then
      INTERACTIVE=1
      tui_select || exit 0
    else
      die_usage "no selection and no terminal — use --items or --profile (see --help)"
    fi
  else
    resolve_selection
  fi

  local out
  out="$(catalog_order_selected "${SELECTION[@]}")" || exit 2
  SELECTION=()
  append_lines "$out"
  [[ ${#SELECTION[@]} -gt 0 ]] || die_usage "nothing selected — use --items or --profile"

  export DRY_RUN FORCE VERBOSE CLAUDE GEMINI INTERACTIVE YES SUDO ACTUAL_HOME PLATFORM HEADLESS PKG_MGR

  if [[ "$DRY_RUN" != "1" ]]; then
    mkdir -p "$TB_DIR/logs" "$TB_DIR/tmp"
    INSTALL_LOG="$TB_DIR/logs/run-$(date +%Y%m%d-%H%M%S).log"
    export INSTALL_LOG
    log_info "log: $INSTALL_LOG"
  fi

  engine_run "${SELECTION[@]}"

  # Housekeeping after a real run only: no logs, no tmp churn on --dry-run.
  if [[ "$DRY_RUN" != "1" ]]; then
    SUMMARY_SELECTED="${#SELECTION[@]}"
    export SUMMARY_SELECTED
    bash "$TB_DIR/scripts/summary.sh" || log_warn "summary reported issues"
  fi
}

main "$@"
