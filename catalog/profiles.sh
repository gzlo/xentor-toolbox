# catalog/profiles.sh — named bundles of item ids. A profile is data, never a code path.
# `items=` lists ids in reading order; the engine still executes in catalog order with
# deps honored. A profile silently drops items that are unavailable on this host
# (wrong platform, GUI item on a headless machine), while an explicit --items request
# for such an item is an error.

profile minimal \
  label="Minimal" \
  desc="the essentials: git, curl, archivers, search, a monitor and an editor" \
  items="git curl wget unzip tar gzip jq ripgrep fd btop zsh zsh-default shell-baseline fresh"

profile shell \
  label="Shell" \
  desc="zsh, prompt, fuzzy finding and modern CLI replacements" \
  items="zsh zsh-default shell-baseline starship fzf zoxide eza bat herdr"

profile dev \
  label="Dev" \
  desc="compilers, runtimes and CLI tooling" \
  items="git curl wget unzip jq ripgrep fd btop htop make cmake gcc gcc-cxx python3 nodejs golang rust pipx gh nvim fresh zsh zsh-default shell-baseline starship fzf zoxide eza bat herdr lazygit cloudflared pnpm"

profile ai \
  label="AI" \
  desc="AI coding toolchain (claude and gemini stay opt-in behind their flags)" \
  items="zsh zsh-default shell-baseline gentle-ai opencode claude gemini"

profile full \
  label="Full" \
  desc="every item declared in the catalog" \
  items="git curl wget zip unzip tar gzip xz make cmake gcc gcc-cxx htop btop ripgrep fd jq fastfetch zsh zsh-default shell-baseline starship fzf zoxide eza bat herdr fresh nvim gh golang nodejs python3 rust pipx lazygit posting git-filter-repo cloudflared pnpm wrangler gentle-ai opencode claude gemini lazydocker"
