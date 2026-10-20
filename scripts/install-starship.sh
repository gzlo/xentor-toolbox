#!/usr/bin/env bash
# scripts/install-starship.sh — install starship on every supported platform.
#
# Native package on Fedora and Arch (upgrades with the system). Everywhere else the
# official musl release binary goes into ~/.local/bin: no root, no package, and it
# works on Debian/Ubuntu where starship has no package.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

install_from_binary() {
  local machine target tmp url
  machine="$(uname -m)"
  case "$machine" in
    x86_64|amd64) target="x86_64-unknown-linux-musl" ;;
    aarch64|arm64) target="aarch64-unknown-linux-musl" ;;
    *)
      log_error "starship: no prebuilt binary for architecture '$machine'"
      return 1
      ;;
  esac

  command -v curl >/dev/null 2>&1 || { log_error "starship: curl is required"; return 1; }
  command -v tar >/dev/null 2>&1 || { log_error "starship: tar is required"; return 1; }

  url="https://github.com/starship/starship/releases/latest/download/starship-${target}.tar.gz"
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  log_info "downloading starship ($target)"
  curl -fsSL -o "$tmp/starship.tar.gz" "$url" || { log_error "starship download failed: $url"; return 1; }
  tar -xzf "$tmp/starship.tar.gz" -C "$tmp" || { log_error "starship: could not extract the archive"; return 1; }
  mkdir -p "$ACTUAL_HOME/.local/bin"
  install -m 755 "$tmp/starship" "$ACTUAL_HOME/.local/bin/starship"
  log_ok "starship installed to $ACTUAL_HOME/.local/bin/starship"
}

case "$PLATFORM" in
  fedora)
    sudo_run dnf install -y starship
    ;;
  arch)
    sudo_run pacman -S --noconfirm --needed starship
    ;;
  *)
    install_from_binary
    ;;
esac
