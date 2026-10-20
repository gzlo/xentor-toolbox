#!/usr/bin/env bash
# scripts/catalog.sh — catalog DSL, loader, platform detection, selection and ordering.
# Sourced by install.sh after scripts/lib.sh. Sets CATALOG_ORDER, ITEM_*, PROFILE_*,
# PLATFORM, PKG_MGR and HEADLESS. Pure bash, no runtime dependencies.

CATALOG_DIR="${CATALOG_DIR:-${TB_DIR:?TB_DIR must be set}/catalog}"

declare -gA ITEM_LABEL=() ITEM_DESC=() ITEM_CATEGORY=() ITEM_PLATFORMS=() ITEM_METHOD=()
declare -gA ITEM_GUI=() ITEM_CHECK=() ITEM_DEPS=() ITEM_INSTALL=() ITEM_HINT=() ITEM_GATE=()
declare -gA ITEM_PKG_FEDORA=() ITEM_PKG_DEBIAN=() ITEM_PKG_ARCH=()
declare -ga CATALOG_ORDER=()

declare -gA PROFILE_LABEL=() PROFILE_DESC=() PROFILE_ITEMS=()
declare -ga PROFILE_ORDER=()

PLATFORM=""
PKG_MGR=""
HEADLESS="0"

# Catalog diagnostics go to stderr: they are usage errors, not progress output.
catalog_fail() { printf '[ERROR] %s\n' "$*" >&2; }

# --- DSL -------------------------------------------------------------------

# item <id> key=value ... — see catalog/items.sh for the key reference.
item() {
  local id="${1:-}"
  [[ -n "$id" ]] || { catalog_fail "catalog: item() without an id"; return 1; }
  [[ -z "${ITEM_LABEL[$id]:-}" ]] || { catalog_fail "catalog: duplicate item '$id'"; return 1; }
  shift

  local label="" desc="" category="" platforms="any" method="custom" gui="0"
  local check="" deps="" install="" hint="" gate=""
  local pkg_fedora="" pkg_debian="" pkg_arch=""
  local kv key value
  for kv in "$@"; do
    key="${kv%%=*}"
    value="${kv#*=}"
    case "$key" in
      label|desc|category|platforms|method|gui|check|deps|install|hint|gate|pkg_fedora|pkg_debian|pkg_arch)
        printf -v "$key" '%s' "$value"
        ;;
      *)
        catalog_fail "catalog: unknown key '$key' in item '$id'"
        return 1
        ;;
    esac
  done

  [[ -n "$category" ]] || { catalog_fail "catalog: item '$id' has no category"; return 1; }
  case "$method" in
    pkg|script|binary|go|cargo|npm|pipx|flatpak|custom|manual) ;;
    *) catalog_fail "catalog: item '$id' has unknown method '$method'"; return 1 ;;
  esac
  case "$gui" in
    0|1) ;;
    *) catalog_fail "catalog: item '$id' has a non-boolean gui value '$gui'"; return 1 ;;
  esac

  ITEM_LABEL[$id]="$label"
  ITEM_DESC[$id]="$desc"
  ITEM_CATEGORY[$id]="$category"
  ITEM_PLATFORMS[$id]="$platforms"
  ITEM_METHOD[$id]="$method"
  ITEM_GUI[$id]="$gui"
  ITEM_CHECK[$id]="$check"
  ITEM_DEPS[$id]="$deps"
  ITEM_INSTALL[$id]="$install"
  ITEM_HINT[$id]="$hint"
  ITEM_GATE[$id]="$gate"
  ITEM_PKG_FEDORA[$id]="$pkg_fedora"
  ITEM_PKG_DEBIAN[$id]="$pkg_debian"
  ITEM_PKG_ARCH[$id]="$pkg_arch"
  CATALOG_ORDER+=("$id")
}

profile() {
  local name="${1:-}"
  [[ -n "$name" ]] || { catalog_fail "catalog: profile() without a name"; return 1; }
  [[ -z "${PROFILE_LABEL[$name]:-}" ]] || { catalog_fail "catalog: duplicate profile '$name'"; return 1; }
  shift

  local label="" desc="" items=""
  local kv key value
  for kv in "$@"; do
    key="${kv%%=*}"
    value="${kv#*=}"
    case "$key" in
      label|desc|items) printf -v "$key" '%s' "$value" ;;
      *) catalog_fail "catalog: unknown key '$key' in profile '$name'"; return 1 ;;
    esac
  done

  PROFILE_LABEL[$name]="${label:-$name}"
  PROFILE_DESC[$name]="$desc"
  PROFILE_ITEMS[$name]="$items"
  PROFILE_ORDER+=("$name")
}

# --- Loading ---------------------------------------------------------------

catalog_load() {
  local f
  for f in items.sh profiles.sh; do
    [[ -r "$CATALOG_DIR/$f" ]] || { catalog_fail "catalog: missing $CATALOG_DIR/$f"; return 1; }
    # shellcheck disable=SC1090
    source "$CATALOG_DIR/$f" || return 1
  done
  ((${#CATALOG_ORDER[@]} > 0)) || { catalog_fail "catalog: no items declared"; return 1; }
  catalog_validate_refs
}

catalog_validate_refs() {
  local name id ok=0
  for name in "${PROFILE_ORDER[@]}"; do
    for id in ${PROFILE_ITEMS[$name]}; do
      [[ -n "${ITEM_LABEL[$id]:-}" ]] || { catalog_fail "catalog: profile '$name' references unknown item '$id'"; ok=1; }
    done
  done
  ((ok == 0))
}

# --- Platform detection ----------------------------------------------------

catalog_detect_platform() {
  if [[ -n "${XT_OS:-}" ]]; then
    PLATFORM="$XT_OS"
  elif [[ -r /etc/os-release ]]; then
    local distro_id
    distro_id="$(sed -n 's/^ID=//p' /etc/os-release | head -1 | tr -d '"')"
    case "$distro_id" in
      fedora) PLATFORM=fedora ;;
      debian|ubuntu|linuxmint|pop) PLATFORM=debian ;;
      arch|manjaro|endeavouros) PLATFORM=arch ;;
      *) PLATFORM="${distro_id:-unknown}" ;;
    esac
  else
    PLATFORM=unknown
  fi

  case "$PLATFORM" in
    fedora) PKG_MGR=dnf ;;
    debian) PKG_MGR=apt ;;
    arch) PKG_MGR=pacman ;;
    *) PKG_MGR="" ;;
  esac

  if [[ -n "${XT_HEADLESS:-}" ]]; then
    HEADLESS="$XT_HEADLESS"
  elif [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
    HEADLESS=0
  else
    HEADLESS=1
  fi
}

# --- Item queries ----------------------------------------------------------

catalog_item_known() { [[ -n "${ITEM_LABEL[${1:-}]:-}" ]]; }

catalog_platform_ok() {
  local id="$1" entry
  local platforms="${ITEM_PLATFORMS[$id]}"
  [[ "$platforms" == "any" ]] && return 0
  for entry in $platforms; do
    [[ "$entry" == "$PLATFORM" ]] && return 0
  done
  return 1
}

# catalog_unavailable_reason <id> — prints why an item cannot run here; empty when it can.
catalog_unavailable_reason() {
  local id="$1"
  if [[ "$HEADLESS" == "1" && "${ITEM_GUI[$id]}" == "1" ]]; then
    printf 'requires a graphical session (headless host)'
    return 0
  fi
  if ! catalog_platform_ok "$id"; then
    printf 'supports only: %s (this host: %s)' "${ITEM_PLATFORMS[$id]}" "$PLATFORM"
    return 0
  fi
  return 0
}

catalog_item_visible() {
  local id="${1:-}"
  catalog_item_known "$id" || return 1
  [[ "$HEADLESS" == "1" && "${ITEM_GUI[$id]}" == "1" ]] && return 1
  catalog_platform_ok "$id"
}

catalog_item_installed() {
  local id="$1" check="${ITEM_CHECK[$id]:-}"
  [[ -n "$check" ]] || return 1
  bash -c "$check" >/dev/null 2>&1
}

catalog_item_state() {
  if catalog_item_installed "$1"; then printf 'installed'; else printf 'missing'; fi
}

# --- Selection -------------------------------------------------------------

# catalog_select_items <comma list> — explicit ids; an unusable id is an error.
catalog_select_items() {
  local list="$1" id
  local -a parts=()
  IFS=',' read -ra parts <<< "$list"
  for id in "${parts[@]}"; do
    id="${id// /}"
    [[ -n "$id" ]] || continue
    catalog_item_known "$id" || { catalog_fail "unknown item: '$id' (try --list)"; return 1; }
    if ! catalog_item_visible "$id"; then
      catalog_fail "item '$id' is not available here: $(catalog_unavailable_reason "$id")"
      return 1
    fi
    printf '%s\n' "$id"
  done
}

# catalog_select_profile <name> — a bundle silently drops what does not apply here.
catalog_select_profile() {
  local name="$1" id
  [[ -n "${PROFILE_LABEL[$name]:-}" ]] || { catalog_fail "unknown profile: '$name' (try --list-profiles)"; return 1; }
  for id in ${PROFILE_ITEMS[$name]}; do
    catalog_item_visible "$id" && printf '%s\n' "$id"
  done
  return 0
}

# catalog_order_selected <ids...> — catalog order, de-duplicated, deps first.
catalog_order_selected() {
  local -a wanted=("$@")
  local -a selected=() out=()
  local -A picked=() emitted=()
  local id dep ready progressed

  [[ ${#wanted[@]} -eq 0 ]] && return 0

  for id in "${CATALOG_ORDER[@]}"; do
    local arg
    for arg in "${wanted[@]}"; do
      [[ "$id" == "$arg" ]] || continue
      [[ -n "${picked[$id]:-}" ]] && continue
      picked[$id]=1
      selected+=("$id")
    done
  done

  while ((${#out[@]} < ${#selected[@]})); do
    progressed=0
    for id in "${selected[@]}"; do
      [[ -n "${emitted[$id]:-}" ]] && continue
      ready=1
      for dep in ${ITEM_DEPS[$id]:-}; do
        # A dependency outside the selection is ordering-only information.
        if [[ -n "${picked[$dep]:-}" && -z "${emitted[$dep]:-}" ]]; then
          ready=0
          break
        fi
      done
      if ((ready == 1)); then
        out+=("$id")
        emitted[$id]=1
        progressed=1
      fi
    done
    if ((progressed == 0)); then
      # Dependency cycle: emit the remainder in catalog order rather than looping.
      for id in "${selected[@]}"; do
        [[ -n "${emitted[$id]:-}" ]] && continue
        out+=("$id")
        emitted[$id]=1
      done
    fi
  done

  [[ ${#out[@]} -eq 0 ]] || printf '%s\n' "${out[@]}"
}

catalog_print_list() {
  local id
  for id in "${CATALOG_ORDER[@]}"; do
    catalog_item_visible "$id" || continue
    printf '%s\t%s\t%s\t%s\n' \
      "$id" "${ITEM_CATEGORY[$id]}" "${ITEM_PLATFORMS[$id]}" "$(catalog_item_state "$id")"
  done
}

catalog_print_profiles() {
  local name
  for name in "${PROFILE_ORDER[@]}"; do
    printf '%s\t%s\n' "$name" "${PROFILE_LABEL[$name]}"
  done
}
