#!/usr/bin/env bash
# Five plugins, plain git clones. No plugin manager: for a fixed set this small
# a manager only adds startup cost and indirection. ~/.local is the PVC, so
# these clone once and persist; `dotup` pulls them.

ZSH_PLUGIN_DIR="$HOME/.local/share/zsh/plugins"
ZSH_PLUGINS=(
  https://github.com/romkatv/powerlevel10k
  https://github.com/zsh-users/zsh-completions
  https://github.com/zsh-users/zsh-autosuggestions
  https://github.com/zsh-users/zsh-syntax-highlighting
  https://github.com/zsh-users/zsh-history-substring-search
)

# Every git call below is bounded and guarded, for the same reason the curl calls
# in lib.sh carry --max-time: this file is sourced into install.sh under
# `set -euo pipefail`, so one unguarded failure aborts the whole install and the
# workspace comes up with no shell config at all. git has no built-in timeout, and
# an egress that drops packets rather than resetting them makes a clone hang
# forever rather than fail -- so `timeout` supplies the bound, and its exit 124
# lands in the existing warn branches.
if ! mkdir -p "$ZSH_PLUGIN_DIR"; then
  warn "could not create $ZSH_PLUGIN_DIR; skipping the zsh plugins"
else
  for url in "${ZSH_PLUGINS[@]}"; do
    name="$(basename "$url")"
    dir="$ZSH_PLUGIN_DIR/$name"
    if [ -d "$dir/.git" ]; then
      if [ "${UPGRADE:-0}" = 1 ]; then
        info "updating $name"
        timeout 120 git -C "$dir" pull --quiet --ff-only || warn "could not update $name"
      fi
    else
      # An interrupted clone leaves a directory with no .git, and git refuses to
      # clone into a non-empty directory -- which would fail identically on every
      # subsequent workspace start. Nothing in there is worth keeping, so clear it.
      if [ -d "$dir" ]; then
        warn "removing incomplete $name checkout"
        # || true: a directory this user cannot remove (an ownership shift on the
        # PVC) would otherwise abort the install here. The clone below then fails
        # on the non-empty directory and warns, which is the right outcome.
        rm -rf "$dir" || true
      fi
      info "cloning $name"
      timeout 120 git clone --depth=1 --quiet "$url" "$dir" || warn "could not clone $name"
    fi
  done
fi
