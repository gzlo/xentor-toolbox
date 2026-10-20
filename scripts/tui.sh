#!/usr/bin/env bash
# scripts/tui.sh — interactive wizard. gum drives the rich flow; a numbered menu is
# the fallback for a server, a bare SSH session or a host without gum.
# Sourced by install.sh after its globals exist. Fills the global SELECTION array.
#
# Menu lines are "<value>  <label>": every parser takes the first whitespace-delimited
# field, so a menu entry and its bare value are interchangeable.

tui_has_gum() { command -v gum >/dev/null 2>&1; }

tui_field() { printf '%s' "${1%%[[:space:]]*}"; }

# tui_visible_categories — unique categories, in catalog order.
tui_visible_categories() {
  local id cat
  local -A seen=()
  for id in "${CATALOG_ORDER[@]}"; do
    catalog_item_visible "$id" || continue
    cat="${ITEM_CATEGORY[$id]}"
    [[ -n "${seen[$cat]:-}" ]] && continue
    seen[$cat]=1
    printf '%s\n' "$cat"
  done
}

tui_item_line() {
  local id="$1"
  if catalog_item_installed "$id"; then
    printf '%s  %s (installed)' "$id" "${ITEM_LABEL[$id]:-$id}"
  else
    printf '%s  %s' "$id" "${ITEM_LABEL[$id]:-$id}"
  fi
}

tui_print_state() {
  local id category platforms state
  printf '  %-14s %-10s %s\n' "id" "category" "state"
  while IFS=$'\t' read -r id category platforms state; do
    printf '  %-14s %-10s %s\n' "$id" "$category" "$state"
  done < <(catalog_print_list)
}

# tui_confirm — one explicit confirmation before anything is installed.
tui_confirm() {
  local count="${#SELECTION[@]}"
  [[ "$count" -gt 0 ]] || return 1

  if [[ "${YES:-0}" == "1" ]]; then
    return 0
  fi

  if tui_has_gum; then
    gum confirm "Install $count item(s): ${SELECTION[*]}?"
    return $?
  fi

  local answer
  printf 'Install %s item(s): %s? [y/N] ' "$count" "${SELECTION[*]}" >&2
  read -r answer
  [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

# --- gum flow ---------------------------------------------------------------

tui_gum_pick_category_items() {
  local category="$1" id line collected=""
  local -a lines=()

  for id in "${CATALOG_ORDER[@]}"; do
    catalog_item_visible "$id" || continue
    [[ "${ITEM_CATEGORY[$id]}" == "$category" ]] || continue
    lines+=("$(tui_item_line "$id")")
  done
  [[ ${#lines[@]} -gt 0 ]] || return 0

  local picked
  picked="$(gum choose --no-limit --header "$category" "${lines[@]}")" || return 1
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    collected+="$(tui_field "$line")"$'\n'
  done <<< "$picked"
  append_lines "$collected"
}

tui_gum_flow() {
  local action picked line name
  local -a lines=()

  while true; do
    action="$(gum choose --header "xentor-workstation — what next?" \
      "profile  install a named bundle" \
      "by-category  pick items, category by category" \
      "state  show what is installed and what is missing" \
      "quit  exit without installing")" || return 1
    action="$(tui_field "$action")"

    case "$action" in
      profile)
        lines=()
        for name in "${PROFILE_ORDER[@]}"; do
          lines+=("$(printf '%s  %s' "$name" "${PROFILE_LABEL[$name]}")")
        done
        picked="$(gum choose --header "profile" "${lines[@]}")" || return 1
        name="$(tui_field "$picked")"
        local out
        out="$(catalog_select_profile "$name")" || exit 2
        append_lines "$out"
        return 0
        ;;
      by-category)
        local -a categories=()
        mapfile -t categories < <(tui_visible_categories)
        picked="$(gum choose --no-limit --header "categories" "${categories[@]}")" || return 1
        [[ -n "$picked" ]] || { log_warn "nothing picked"; return 1; }
        while IFS= read -r line; do
          [[ -n "$line" ]] || continue
          tui_gum_pick_category_items "$(tui_field "$line")" || return 1
        done <<< "$picked"
        return 0
        ;;
      state)
        tui_print_state
        continue
        ;;
      quit)
        return 1
        ;;
      *)
        log_warn "unknown action: $action"
        ;;
    esac
  done
}

# --- numbered fallback ------------------------------------------------------

tui_fallback_flow() {
  local i=1 name answer pick index
  local -a names=() tokens=() picks=()

  {
    printf 'xentor-workstation (%s, %s) — profiles:\n' "$PLATFORM" \
      "$([[ "$HEADLESS" == "1" ]] && printf headless || printf graphical)"
    for name in "${PROFILE_ORDER[@]}"; do
      names+=("$name")
      printf '  %2d) %-16s %s\n' "$i" "$name" "${PROFILE_LABEL[$name]} — ${PROFILE_DESC[$name]}"
      ((i++))
    done
    printf '  %2d) %-16s type item ids (see --list)\n' "$i" "custom"
    printf '  %2d) %-16s exit\n' "$((i + 1))" "quit"
  } >&2

  printf 'Select (comma-separated numbers) > ' >&2
  read -r answer
  [[ -n "$answer" ]] || return 1

  IFS=',' read -ra tokens <<< "$answer"
  local out
  for pick in "${tokens[@]}"; do
    pick="${pick// /}"
    [[ -n "$pick" ]] || continue
    [[ "$pick" =~ ^[0-9]+$ ]] || { printf '[ERROR] invalid selection: %s\n' "$pick" >&2; exit 2; }
    index=$((10#$pick))
    if ((index == i)); then
      printf 'Item ids (comma-separated) > ' >&2
      local ids
      read -r ids
      out="$(catalog_select_items "$ids")" || exit 2
      append_lines "$out"
    elif ((index == i + 1)); then
      return 1
    elif ((index >= 1 && index < i)); then
      out="$(catalog_select_profile "${names[$((index - 1))]}")" || exit 2
      append_lines "$out"
    else
      printf '[ERROR] invalid selection: %s\n' "$pick" >&2
      exit 2
    fi
  done
  return 0
}

# --- entry point ------------------------------------------------------------

# tui_select — populate SELECTION and get one confirmation. Returns 1 when the
# human cancels, 2 (via exit) on an invalid choice.
tui_select() {
  if tui_has_gum; then
    tui_gum_flow || { log_info "nothing selected — exiting"; return 1; }
  else
    tui_fallback_flow || { log_info "nothing selected — exiting"; return 1; }
  fi

  [[ ${#SELECTION[@]} -gt 0 ]] || { log_warn "nothing selected — exiting"; return 1; }

  if ! tui_confirm; then
    log_info "cancelled — nothing installed"
    return 1
  fi
  return 0
}
