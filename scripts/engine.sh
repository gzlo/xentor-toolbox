#!/usr/bin/env bash
# scripts/engine.sh — plan and execute catalog items.
# Sourced by install.sh after scripts/catalog.sh. Honors DRY_RUN, FORCE, VERBOSE,
# CLAUDE, GEMINI, SUDO and ACTUAL_HOME from the environment.

engine_summary_line() {
  printf 'platform=%s pkg=%s headless=%s force=%s dry-run=%s' \
    "$PLATFORM" "${PKG_MGR:-none}" "$HEADLESS" "${FORCE:-0}" "${DRY_RUN:-0}"
}

# engine_install_pkg <id> — install through the platform package manager.
# engine_install_pkg <id> — install through the platform package manager.
# PLATFORM (fedora|debian|arch) selects the package name; PKG_MGR (dnf|apt|pacman)
# selects the command. They are different keys and must never be compared to each
# other: doing that silently broke every pkg item.
engine_install_pkg() {
  local id="$1" pkg=""
  case "$PLATFORM" in
    fedora) pkg="${ITEM_PKG_FEDORA[$id]:-}" ;;
    debian) pkg="${ITEM_PKG_DEBIAN[$id]:-}" ;;
    arch)   pkg="${ITEM_PKG_ARCH[$id]:-}" ;;
    *)
      log_error "item '$id': no package mapping for platform '$PLATFORM'"
      return 1
      ;;
  esac
  [[ -n "$pkg" ]] || { log_error "item '$id': no package name for '$PLATFORM'"; return 1; }
  # $pkg may hold several space-separated names ("rust cargo"); splitting is intended.
  # shellcheck disable=SC2086
  case "$PKG_MGR" in
    dnf) sudo_run dnf install -y $pkg ;;
    apt) sudo_run env DEBIAN_FRONTEND=noninteractive apt-get install -y $pkg ;;
    pacman) sudo_run pacman -S --noconfirm --needed $pkg ;;
    *)
      log_error "item '$id': no usable package manager on '$PLATFORM' (expected dnf, apt or pacman)"
      return 1
      ;;
  esac
}

# engine_rollback_hint — name the undo command of the manager actually in use.
engine_rollback_hint() {
  case "$PKG_MGR" in
    dnf) printf "'dnf history undo'" ;;
    apt) printf "'apt-get remove <package>'" ;;
    pacman) printf "'pacman -R <package>'" ;;
    *) printf "your package manager" ;;
  esac
}

# engine_install <id> — run one item's install step.
engine_install() {
  local id="$1"
  local method="${ITEM_METHOD[$id]}"
  local script="${ITEM_INSTALL[$id]:-}"

  case "$method" in
    pkg) engine_install_pkg "$id" ;;
    manual)
      log_warn "manual: $id — ${ITEM_HINT[$id]:-see upstream documentation}"
      return 0
      ;;
    *)
      [[ -n "$script" ]] || { log_error "item '$id' has no install command"; return 1; }
      [[ "${VERBOSE:-0}" == "1" ]] && log_info "    \$ $script"
      # The child sources lib.sh so items may use sudo_run/log_* like the installers did.
      bash -c "source \"\$TB_DIR/scripts/lib.sh\"; $script"
      ;;
  esac
}

engine_gate_open() {
  local id="$1" gate="${ITEM_GATE[$id]:-}"
  [[ -n "$gate" ]] || return 0
  case "$gate" in
    claude) [[ "${CLAUDE:-0}" == "1" ]] ;;
    gemini) [[ "${GEMINI:-0}" == "1" ]] ;;
    *) log_warn "item '$id' declares unknown gate '$gate' — ignoring"; return 0 ;;
  esac
}

# engine_item <id> — skip-or-install one item. Never called under DRY_RUN.
engine_item() {
  local id="$1"

  if ! engine_gate_open "$id"; then
    log_info "skip $id (opt-in: --${ITEM_GATE[$id]})"
    audit "SKIP $id (gate)"
    return 0
  fi

  if [[ "${ITEM_METHOD[$id]}" == "manual" ]]; then
    audit "MANUAL $id"
    engine_install "$id"
    return 0
  fi

  if [[ "${FORCE:-0}" != "1" ]] && catalog_item_installed "$id"; then
    log_ok "$id already installed — skipping"
    audit "SKIP $id"
    return 0
  fi

  log_info "==> $id (${ITEM_LABEL[$id]:-$id})"
  audit "START $id"
  if ! engine_install "$id"; then
    audit "FAIL $id"
    return 1
  fi
  audit "DONE $id"
  log_ok "$id done"
}

# engine_run <ids...> — plan, then either print (dry-run) or execute in order.
engine_run() {
  local -a ids=("$@")
  local id

  log_info "plan (${#ids[@]} items): ${ids[*]:-}"
  log_info "$(engine_summary_line)"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    for id in "${ids[@]}"; do
      if ! engine_gate_open "$id"; then
        printf '[dry-run] skip %s (opt-in: --%s)\n' "$id" "${ITEM_GATE[$id]}"
        continue
      fi
      if [[ "${ITEM_METHOD[$id]}" == "manual" ]]; then
        printf '[dry-run] manual %s: %s\n' "$id" "${ITEM_HINT[$id]:-see upstream documentation}"
        continue
      fi
      if [[ "${FORCE:-0}" != "1" ]] && catalog_item_installed "$id"; then
        printf '[dry-run] skip %s (already installed)\n' "$id"
        continue
      fi
      printf '[dry-run] install %s\n' "$id"
    done
    printf 'no changes made (dry-run)\n'
    return 0
  fi

  for id in "${ids[@]}"; do
    if ! engine_item "$id"; then
      log_error "item '$id' failed — halting run."
      log_error "Rollback: see ${INSTALL_LOG:-the run log}; undo package changes with $(engine_rollback_hint)."
      return 1
    fi
  done

  log_ok "install complete."
}
