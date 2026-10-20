# xentor-toolbox — base shell configuration for zsh.
#
# Installed to ~/.config/xentor-toolbox/shell.zsh and sourced from ~/.zshrc inside a
# managed block. This file is the BASELINE: colours, a few safe aliases, history and
# completion. Nothing personal belongs here — personal aliases go in ~/.shell.local,
# which is sourced after this file and therefore wins.
#
# Reinstalling overwrites this file; never edit it in place.

# --- path -------------------------------------------------------------------
typeset -U path
path=("$HOME/.local/bin" $path)

# --- colours ----------------------------------------------------------------
export CLICOLOR=1
export LESS="-R"
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias diff='diff --color=auto'

# --- base aliases (deliberately boring) -------------------------------------
alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'

# --- modern replacements, only when they are actually installed -------------
if (( $+commands[eza] )); then
  alias ls='eza --group-directories-first'
  alias ll='eza -lah --group-directories-first --git'
  alias tree='eza --tree'
fi
# `cat` is intentionally NOT aliased: overriding it breaks scripts and heredocs.

# --- history ----------------------------------------------------------------
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt hist_ignore_dups hist_ignore_space share_history extended_history

# --- completion -------------------------------------------------------------
autoload -Uz compinit
compinit -i

# --- prompt, only when starship is installed --------------------------------
if (( $+commands[starship] )); then
  eval "$(starship init zsh)"
fi
