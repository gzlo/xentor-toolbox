#!/usr/bin/env bash
# xentor-workstation shared library — print/prompt/run_cmd/log/sudo/backup helpers.
# Sourced by install.sh and every bootstrap module. Pure bash, zero deps.
# Env contract: DRY_RUN, INSTALL_LOG, ACTUAL_HOME, SUDO, VERBOSE.
set -euo pipefail

# --- Colors (no-op when not a TTY) ---
if [[ -t 1 ]]; then
  C_INFO=$'\e[34m'; C_OK=$'\e[32m'; C_WARN=$'\e[33m'; C_ERR=$'\e[31m'; C_RST=$'\e[0m'
else
  C_INFO=''; C_OK=''; C_WARN=''; C_ERR=''; C_RST=''
fi

log_info()    { echo -e "${C_INFO}[INFO]${C_RST}  $*"; }
log_ok()      { echo -e "${C_OK}[OK]${C_RST}    $*"; }
log_warn()    { echo -e "${C_WARN}[WARN]${C_RST}  $*"; }
log_error()   { echo -e "${C_ERR}[ERROR]${C_RST} $*"; }

# Write to the shared audit log (INSTALL_LOG) if set.
audit() {
  local level="$1"; shift
  if [[ -n "${INSTALL_LOG:-}" ]]; then
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level: $*" >> "$INSTALL_LOG"
  fi
}

# ask_yes_no <question> -> exit 0/1. Defaults to No when non-interactive.
ask_yes_no() {
  [[ "${INTERACTIVE:-0}" != "1" ]] && { log_warn "non-interactive: assuming NO for: $1"; return 1; }
  local ans
  printf '%s [y/N] ' "$1" >&2; read -r ans
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

# run_cmd <label> <cmd...> — executes (or prints under DRY_RUN), audits result.
run_cmd() {
  local label="$1"; shift
  audit "RUN  $label: $*"
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log_info "[dry-run] $label: $*"
    return 0
  fi
  if [[ "${VERBOSE:-0}" == "1" ]]; then
    "$@" || { audit "FAIL $label"; log_error "failed: $label"; return 1; }
  else
    "$@" >/dev/null 2>&1 || { audit "FAIL $label"; log_error "failed: $label"; return 1; }
  fi
  audit "DONE $label"
  return 0
}

# sudo wrapper — uses SUDO env (set once by install.sh) or bare when root.
sudo_run() {
  if [[ "${SUDO:-}" == "none" ]]; then
    "$@"
  else
    "$SUDO" "$@"
  fi
}

# backup_and_link <src> <dst> — backup existing target, then symlink. Idempotent.
backup_and_link() {
  local src="$1" dst="$2"
  if [[ -L "$dst" ]]; then
    if [[ "$(readlink -f "$dst")" == "$(readlink -f "$src")" ]]; then
      log_info "already linked: $dst"
      return 0
    fi
    run_cmd "relink $dst" ln -sfn "$src" "$dst" || return 1
    return 0
  fi
  if [[ -e "$dst" ]]; then
    local backup="${dst}.bak.$(date +%Y%m%d%H%M%S)"
    log_warn "backup: $dst -> $backup"
    run_cmd "backup $dst" mv "$dst" "$backup" || return 1
  fi
  mkdir -p "$(dirname "$dst")"
  run_cmd "link $dst" ln -sfn "$src" "$dst" || return 1
}

# expand_sudo — return the sudo prefix (or none) for a target user.
resolve_sudo() {
  if [[ "$(id -u)" -eq 0 ]]; then echo "none"; return 0; fi
  if sudo -n true 2>/dev/null; then echo "sudo -n"; return 0; fi
  if [[ "${INTERACTIVE:-0}" == "1" ]]; then echo "sudo"; return 0; fi
  echo "sudo -n"
}
