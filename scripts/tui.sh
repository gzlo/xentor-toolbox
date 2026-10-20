#!/usr/bin/env bash
# scripts/tui.sh — interactive wizard. gum drives the rich flow; a numbered menu is
# the fallback for a server, a bare SSH session or a host without gum.
# Sourced by install.sh after its globals exist. Fills the global SELECTION array.
#
# Design rule: the user must always be able to SEE what can be installed before
# choosing. Nothing is hidden behind a category, and an empty selection returns to
# the menu instead of ending the run.
#
# Menu lines are "<value>  <label>": every parser takes the first whitespace-delimited
# field, so a menu entry and its bare value are interchangeable.

tui_has_gum() { command -v gum >/dev/null 2>&1; }

tui_field() { printf '%s' "${1%%[[:space:]]*}"; }

# tui_item_line <id> — one line per item, informative enough to choose from.
tui_item_line() {
  local id="$1" state=""
  catalog_item_installed "$id" && state=" ✔ installed"
  printf '%s  %-22s %-14s %s%s' \
    "$id" "${ITEM_LABEL[$id]:-$id}" "[${ITEM_CATEGORY[$id]}]" "${ITEM_DESC[$id]:-}" "$state"
}

tui_visible_ids() {
  local id
  for id in "${CATALOG_ORDER[@]}"; do
    catalog_item_visible "$id" || continue
    printf '%s\n' "$id"
  done
}

# tui_catalog_text — the full catalog as a readable table, descriptions included.
tui_catalog_text() {
  local id state
  printf 'xentor-toolbox — %s, %s — %s items available here\n\n' \
    "$PLATFORM" "$([[ "$HEADLESS" == "1" ]] && printf headless || printf graphical)" \
    "$(tui_visible_ids | wc -l | tr -d ' ')"
  printf '%-24s %-11s %-10s %s\n' "ID" "CATEGORY" "STATE" "WHAT IT IS"
  for id in "${CATALOG_ORDER[@]}"; do
    catalog_item_visible "$id" || continue
    if catalog_item_installed "$id"; then state="installed"; else state="missing"; fi
    printf '%-24s %-11s %-10s %s\n' "$id" "${ITEM_CATEGORY[$id]}" "$state" "${ITEM_DESC[$id]:-$id}"
  done
  printf '\nNot listed = does not support %s (or needs a graphical session).\n' "$PLATFORM"
  printf 'Profiles: '
  printf '%s ' "${PROFILE_ORDER[@]}"
  printf '\n'
}

tui_show_catalog() {
  local text
  text="$(tui_catalog_text)"
  if tui_has_gum && gum pager --help >/dev/null 2>&1; then
    printf '%s\n' "$text" | gum pager
  else
    printf '%s\n' "$text"
    printf 'Press enter to go back… ' >&2
    read -r _
  fi
}

# tui_confirm — one explicit confirmation before anything is installed.
tui_confirm() {
  local count="${#SELECTION[@]}"
  [[ "$count" -gt 0 ]] || return 1
  [[ "${YES:-0}" == "1" ]] && return 0

  if tui_has_gum; then
    gum confirm --default=false "INSTALL $count item(s) for real now: ${SELECTION[*]}?"
    return $?
  fi

  local answer
  printf 'Install %s item(s): %s? [y/N] ' "$count" "${SELECTION[*]}" >&2
  read -r answer
  [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

# --- gum flow ---------------------------------------------------------------

# tui_gum_pick_items — one screen with every available item. Returns 1 when the
# human backs out, and never returns "empty" as a terminal state.
tui_gum_pick_items() {
  local id picked line collected=""
  local -a lines=()

  for id in "${CATALOG_ORDER[@]}"; do
    catalog_item_visible "$id" || continue
    lines+=("$(tui_item_line "$id")")
  done
  [[ ${#lines[@]} -gt 0 ]] || { log_warn "no items available on $PLATFORM"; return 1; }

  while true; do
    picked="$(gum choose --no-limit --height 22 \
      --header "space toggles an item · enter confirms · esc goes back" "${lines[@]}")" || return 1

    if [[ -z "${picked//[[:space:]]/}" ]]; then
      log_warn "nothing picked — use space to toggle at least one item, or esc to go back"
      gum confirm --default=true "Pick again?" || return 1
      continue
    fi

    collected=""
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      collected+="$(tui_field "$line")"$'\n'
    done <<< "$picked"
    append_lines "$collected"
    return 0
  done
}

tui_gum_pick_profile() {
  local name picked
  local -a lines=()
  for name in "${PROFILE_ORDER[@]}"; do
    lines+=("$(printf '%s  %-14s %d items — %s' \
      "$name" "${PROFILE_LABEL[$name]}" \
      "$(catalog_select_profile "$name" | wc -l | tr -d ' ')" "${PROFILE_DESC[$name]}")")
  done

  picked="$(gum choose --height 12 --header "profile (esc goes back)" "${lines[@]}")" || return 1
  name="$(tui_field "$picked")"
  local out
  out="$(catalog_select_profile "$name")" || exit 2
  if [[ -z "${out//[[:space:]]/}" ]]; then
    log_warn "profile '$name' has no items available on $PLATFORM"
    return 1
  fi
  append_lines "$out"
}

tui_gum_flow() {
  local action
  while true; do
    action="$(gum choose --height 12 \
      --header "xentor-toolbox — $PLATFORM, $(tui_visible_ids | wc -l | tr -d ' ') items available" \
      "items    pick what to install" \
      "profile  install a named bundle" \
      "preview  pick anything and see the plan — installs NOTHING" \
      "catalog  see everything available, with descriptions" \
      "quit     exit without installing")" || return 1

    case "$(tui_field "$action")" in
      items)   tui_gum_pick_items && return 0 ;;
      profile) tui_gum_pick_profile && return 0 ;;
      preview) TUI_PREVIEW=1; tui_gum_pick_items && return 0 ;;
      catalog) tui_show_catalog ;;
      quit)    return 1 ;;
      *)       log_warn "unknown action: $action" ;;
    esac
  done
}

# --- numbered fallback ------------------------------------------------------

tui_fallback_items() {
  local id answer token collected=""
  local -a ids=() tokens=()
  local i=1

  mapfile -t ids < <(tui_visible_ids)
  [[ ${#ids[@]} -gt 0 ]] || { log_warn "no items available on $PLATFORM"; return 1; }

  {
    printf 'Available on %s:\n' "$PLATFORM"
    for id in "${ids[@]}"; do
      printf '  %2d) %s\n' "$i" "$(tui_item_line "$id")"
      ((i++))
    done
  } >&2

  printf 'Pick (e.g. 1,4,7-9, or all) > ' >&2
  read -r answer
  [[ -n "$answer" ]] || return 1

  if [[ "$answer" == "all" ]]; then
    append_lines "$(printf '%s\n' "${ids[@]}")"
    return 0
  fi

  IFS=',' read -ra tokens <<< "$answer"
  for token in "${tokens[@]}"; do
    token="${token// /}"
    [[ -n "$token" ]] || continue
    if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      local from=$((10#${BASH_REMATCH[1]})) to=$((10#${BASH_REMATCH[2]})) n
      for ((n = from; n <= to; n++)); do
        ((n >= 1 && n <= ${#ids[@]})) || { printf '[ERROR] no item %s\n' "$n" >&2; exit 2; }
        collected+="${ids[$((n - 1))]}"$'\n'
      done
    elif [[ "$token" =~ ^[0-9]+$ ]]; then
      local index=$((10#$token))
      ((index >= 1 && index <= ${#ids[@]})) || { printf '[ERROR] no item %s\n' "$index" >&2; exit 2; }
      collected+="${ids[$((index - 1))]}"$'\n'
    else
      printf '[ERROR] invalid selection: %s\n' "$token" >&2
      exit 2
    fi
  done

  append_lines "$collected"
}

tui_fallback_flow() {
  local i=1 name answer pick index
  local -a names=() tokens=()

  {
    printf 'xentor-toolbox — %s, %s, %s items available:\n' "$PLATFORM" \
      "$([[ "$HEADLESS" == "1" ]] && printf headless || printf graphical)" \
      "$(tui_visible_ids | wc -l | tr -d ' ')"
    for name in "${PROFILE_ORDER[@]}"; do
      names+=("$name")
      printf '  %2d) %-16s %s\n' "$i" "$name" "${PROFILE_LABEL[$name]} — ${PROFILE_DESC[$name]}"
      ((i++))
    done
    printf '   i) pick individual items\n'
    printf '   c) see everything available\n'
    printf '   q) exit\n'
  } >&2

  printf 'Select (number, i, c, q, or comma-separated numbers) > ' >&2
  read -r answer
  [[ -n "$answer" ]] || return 1

  case "${answer// /}" in
    q|quit) return 1 ;;
    i|items) tui_fallback_items; return $? ;;
    p|preview) TUI_PREVIEW=1; tui_fallback_items; return $? ;;
    c|catalog) tui_show_catalog; return 1 ;;
  esac

  IFS=',' read -ra tokens <<< "$answer"
  local out
  for pick in "${tokens[@]}"; do
    pick="${pick// /}"
    [[ -n "$pick" ]] || continue
    [[ "$pick" =~ ^[0-9]+$ ]] || { printf '[ERROR] invalid selection: %s\n' "$pick" >&2; exit 2; }
    index=$((10#$pick))
    ((index >= 1 && index <= ${#names[@]})) || { printf '[ERROR] no profile %s\n' "$pick" >&2; exit 2; }
    out="$(catalog_select_profile "${names[$((index - 1))]}")" || exit 2
    append_lines "$out"
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

  if [[ "${TUI_PREVIEW:-0}" == "1" ]]; then
    DRY_RUN=1
    log_info "preview mode: showing the plan for the selection, nothing will be installed"
    return 0
  fi

  if ! tui_confirm; then
    log_info "cancelled — nothing installed"
    return 1
  fi
  return 0
}
