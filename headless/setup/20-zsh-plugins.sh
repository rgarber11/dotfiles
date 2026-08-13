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

mkdir -p "$ZSH_PLUGIN_DIR"
for url in "${ZSH_PLUGINS[@]}"; do
  name="$(basename "$url")"
  dir="$ZSH_PLUGIN_DIR/$name"
  if [ -d "$dir/.git" ]; then
    if [ "${UPGRADE:-0}" = 1 ]; then
      info "updating $name"
      git -C "$dir" pull --quiet --ff-only || warn "could not update $name"
    fi
  else
    # An interrupted clone leaves a directory with no .git, and git refuses to
    # clone into a non-empty directory -- which would fail identically on every
    # subsequent workspace start. Nothing in there is worth keeping, so clear it.
    if [ -d "$dir" ]; then
      warn "removing incomplete $name checkout"
      rm -rf "$dir"
    fi
    info "cloning $name"
    git clone --depth=1 --quiet "$url" "$dir" || warn "could not clone $name"
  fi
done
