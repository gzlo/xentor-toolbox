# catalog/items.sh — the install catalog. One `item` call per installable tool.
#
# Keys (all optional unless marked):
#   label=      human name
#   desc=       one-line description
#   category=   REQUIRED. base | shell | editor | dev | ai | container
#   platforms=  space-separated: fedora debian arch, or "any" (default: any)
#   method=     pkg | script | binary | go | cargo | npm | pipx | flatpak | custom | manual
#   gui=        1 when the item needs a graphical session (hidden/rejected when headless)
#   check=      shell test that proves the item is installed, e.g. "command -v fresh"
#   deps=       space-separated item ids that must be planned before this one
#   install=    shell command run when the check fails (all methods but pkg/manual)
#   hint=       message printed for method=manual
#   gate=       opt-in flag name: claude | gemini (item runs only with the flag)
#   pkg_fedora= / pkg_debian= / pkg_arch=   package name(s) for method=pkg
#
# Declaration order is the default execution order. Only tools that actually
# install something belong here: a `manual` item is a hint, and hints are noise
# in a tool meant to work for anyone.

# --- base -------------------------------------------------------------------

item git label="Git" desc="Version control" category=base platforms="fedora debian arch" \
  method=pkg pkg_fedora=git pkg_debian=git pkg_arch=git check="command -v git"

item curl label="curl" desc="HTTP client" category=base platforms="fedora debian arch" \
  method=pkg pkg_fedora=curl pkg_debian=curl pkg_arch=curl check="command -v curl"

item wget label="wget" desc="HTTP downloader" category=base platforms="fedora debian arch" \
  method=pkg pkg_fedora=wget pkg_debian=wget pkg_arch=wget check="command -v wget"

item zip label="zip" desc="zip archiver" category=base platforms="fedora debian arch" \
  method=pkg pkg_fedora=zip pkg_debian=zip pkg_arch=zip check="command -v zip"

item unzip label="unzip" desc="zip extractor" category=base platforms="fedora debian arch" \
  method=pkg pkg_fedora=unzip pkg_debian=unzip pkg_arch=unzip check="command -v unzip"

item tar label="tar" desc="tar archiver" category=base platforms="fedora debian arch" \
  method=pkg pkg_fedora=tar pkg_debian=tar pkg_arch=tar check="command -v tar"

item gzip label="gzip" desc="gzip compressor" category=base platforms="fedora debian arch" \
  method=pkg pkg_fedora=gzip pkg_debian=gzip pkg_arch=gzip check="command -v gzip"

item xz label="xz" desc="xz compressor" category=base platforms="fedora debian arch" \
  method=pkg pkg_fedora=xz pkg_debian=xz-utils pkg_arch=xz check="command -v xz"

item make label="make" desc="Build automation" category=base platforms="fedora debian arch" \
  method=pkg pkg_fedora=make pkg_debian=make pkg_arch=make check="command -v make"

item cmake label="CMake" desc="Build system" category=base platforms="fedora debian arch" \
  method=pkg pkg_fedora=cmake pkg_debian=cmake pkg_arch=cmake check="command -v cmake"

item gcc label="GCC" desc="C compiler" category=base platforms="fedora debian arch" \
  method=pkg pkg_fedora=gcc pkg_debian=gcc pkg_arch=gcc check="command -v gcc"

item gcc-cxx label="GCC C++" desc="C++ compiler" category=base platforms="fedora debian arch" \
  method=pkg pkg_fedora=gcc-c++ pkg_debian=g++ pkg_arch=gcc check="command -v g++"

item htop label="htop" desc="Process monitor" category=base platforms="fedora debian arch" \
  method=pkg pkg_fedora=htop pkg_debian=htop pkg_arch=htop check="command -v htop"

item btop label="btop" desc="Interactive system monitor" category=base platforms="fedora debian arch" \
  method=pkg pkg_fedora=btop pkg_debian=btop pkg_arch=btop check="command -v btop"

item ripgrep label="ripgrep" desc="Recursive grep" category=base platforms="fedora debian arch" \
  method=pkg pkg_fedora=ripgrep pkg_debian=ripgrep pkg_arch=ripgrep check="command -v rg"

item fd label="fd" desc="Fast file finder" category=base platforms="fedora debian arch" \
  method=pkg pkg_fedora=fd-find pkg_debian=fd-find pkg_arch=fd check="command -v fdfind || command -v fd"

item jq label="jq" desc="JSON processor" category=base platforms="fedora debian arch" \
  method=pkg pkg_fedora=jq pkg_debian=jq pkg_arch=jq check="command -v jq"

item fastfetch label="fastfetch" desc="System information" category=base platforms="fedora debian arch" \
  method=pkg pkg_fedora=fastfetch pkg_debian=fastfetch pkg_arch=fastfetch check="command -v fastfetch"

# --- shell ------------------------------------------------------------------

item zsh label="Zsh" desc="Interactive shell" category=shell platforms="fedora debian arch" \
  method=pkg pkg_fedora=zsh pkg_debian=zsh pkg_arch=zsh check="command -v zsh"

item zsh-default label="Zsh as default" desc="chsh the login shell to zsh" category=shell \
  platforms="fedora debian arch" method=custom \
  check='[[ "$(getent passwd "$(id -un)" | cut -d: -f7)" == */zsh ]]' \
  deps="zsh" install='sudo_run chsh -s "$(command -v zsh)" "$(id -un)"'

item starship label="Starship" desc="Shell prompt" category=shell platforms="fedora arch" \
  method=pkg pkg_fedora=starship pkg_arch=starship check="command -v starship"

item fzf label="fzf" desc="Fuzzy finder" category=shell platforms="fedora debian arch" \
  method=pkg pkg_fedora=fzf pkg_debian=fzf pkg_arch=fzf check="command -v fzf"

item zoxide label="zoxide" desc="Smarter cd" category=shell platforms="fedora debian arch" \
  method=pkg pkg_fedora=zoxide pkg_debian=zoxide pkg_arch=zoxide check="command -v zoxide"

item eza label="eza" desc="ls replacement" category=shell platforms="fedora debian arch" \
  method=pkg pkg_fedora=eza pkg_debian=eza pkg_arch=eza check="command -v eza"

item bat label="bat" desc="cat with syntax highlighting" category=shell platforms="fedora debian arch" \
  method=pkg pkg_fedora=bat pkg_debian=bat pkg_arch=bat check="command -v bat || command -v batcat"

# --- editor -----------------------------------------------------------------

item fresh label="Fresh" desc="Terminal code editor" category=editor platforms="any" \
  method=script check="command -v fresh" \
  install='FRESH_INSTALL_DIR="$ACTUAL_HOME/.local/share/fresh-editor" FRESH_BIN_DIR="$ACTUAL_HOME/.local/bin" sh -c "$(curl -fsSL https://raw.githubusercontent.com/sinelaw/fresh/refs/heads/master/scripts/install.sh)"'

item nvim label="Neovim" desc="Latest stable AppImage into ~/.local/bin" category=editor \
  platforms="any" method=binary check="command -v nvim" \
  install='mkdir -p "$ACTUAL_HOME/.local/bin"; curl -fL -o "$ACTUAL_HOME/.local/bin/nvim" "https://github.com/neovim/neovim/releases/download/stable/nvim.appimage" && chmod +x "$ACTUAL_HOME/.local/bin/nvim"'

# --- dev --------------------------------------------------------------------

item gh label="GitHub CLI" desc="GitHub from the terminal" category=dev platforms="fedora debian arch" \
  method=pkg pkg_fedora=gh pkg_debian=gh pkg_arch=github-cli check="command -v gh"

item golang label="Go" desc="Go toolchain" category=dev platforms="fedora debian arch" \
  method=pkg pkg_fedora=golang pkg_debian=golang pkg_arch=go check="command -v go"

item nodejs label="Node.js" desc="JavaScript runtime" category=dev platforms="fedora debian arch" \
  method=pkg pkg_fedora=nodejs pkg_debian=nodejs pkg_arch=nodejs check="command -v node"

item python3 label="Python 3" desc="Python runtime" category=dev platforms="fedora debian arch" \
  method=pkg pkg_fedora=python3 pkg_debian=python3 pkg_arch=python check="command -v python3"

item rust label="Rust" desc="rustc + cargo" category=dev platforms="fedora debian arch" \
  method=pkg pkg_fedora="rust cargo" pkg_debian="rustc cargo" pkg_arch=rust check="command -v cargo"

item pipx label="pipx" desc="Isolated Python apps" category=dev platforms="fedora debian arch" \
  method=pkg pkg_fedora=pipx pkg_debian=pipx pkg_arch=python-pipx check="command -v pipx"

item lazygit label="lazygit" desc="Terminal git UI" category=dev platforms="any" \
  method=go deps="golang" check="command -v lazygit" \
  install='go install github.com/jesseduffield/lazygit@latest'

item posting label="posting" desc="Terminal API client" category=dev platforms="any" \
  method=pipx deps="pipx" check="command -v posting" install='pipx install posting'

item git-filter-repo label="git-filter-repo" desc="History rewriting" category=dev platforms="any" \
  method=pipx deps="pipx" check="command -v git-filter-repo" install='pipx install git-filter-repo'

item cloudflared label="cloudflared" desc="Cloudflare Tunnel client" category=dev platforms="any" \
  method=binary check="command -v cloudflared" \
  install='mkdir -p "$ACTUAL_HOME/.local/bin"; ver="$(curl -fsSL https://api.github.com/repos/cloudflare/cloudflared/releases/latest | grep -m1 "\"tag_name\"" | cut -d\" -f4)"; curl -fL -o "$ACTUAL_HOME/.local/bin/cloudflared" "https://github.com/cloudflare/cloudflared/releases/download/${ver}/cloudflared-linux-amd64" && chmod +x "$ACTUAL_HOME/.local/bin/cloudflared"'

item pnpm label="pnpm" desc="Package manager" category=dev platforms="any" \
  method=npm deps="nodejs" check="command -v pnpm" install='sudo_run npm install -g pnpm'

item wrangler label="wrangler" desc="Cloudflare Workers CLI" category=dev platforms="any" \
  method=npm deps="nodejs" check="command -v wrangler" install='sudo_run npm install -g wrangler'

# --- ai ---------------------------------------------------------------------

item gentle-ai label="gentle-ai" desc="AI coding harness (official binary installer)" category=ai \
  platforms="any" method=script check="command -v gentle-ai" \
  install='curl -fsSL https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/scripts/install.sh | bash -s -- --method binary --dir "$ACTUAL_HOME/.local/bin"'

item opencode label="opencode" desc="Terminal AI coding agent" category=ai platforms="any" \
  method=script check="command -v opencode" install='curl -fsSL https://opencode.ai/install | bash'

item claude label="Claude Code" desc="Anthropic CLI (opt-in: --claude)" category=ai \
  platforms="any" method=script gate=claude check="command -v claude" \
  install='curl -fsSL https://claude.ai/install.sh | bash'

item gemini label="Gemini CLI" desc="Google CLI (opt-in: --gemini)" category=ai \
  platforms="any" method=npm gate=gemini deps="nodejs" check="command -v gemini" \
  install='sudo_run npm install -g @google/gemini-cli'

# --- container --------------------------------------------------------------

item lazydocker label="lazydocker" desc="Terminal Docker UI (needs Docker already installed)" \
  category=container platforms="any" method=go deps="golang" check="command -v lazydocker" \
  install='go install github.com/jesseduffield/lazydocker@latest'
