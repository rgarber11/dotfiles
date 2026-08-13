#!/usr/bin/env bash
# /etc/passwd comes from the image, not the PVC, so the shell change does not
# survive a restart and has to be re-applied on every start.
ZSH_PATH="$(command -v zsh || true)"
if [ -n "$ZSH_PATH" ] && [ "$(getent passwd "$USER" | cut -d: -f7)" != "$ZSH_PATH" ]; then
  info "setting login shell to $ZSH_PATH"
  sudo chsh -s "$ZSH_PATH" "$USER" || warn "chsh failed"
fi

# `herdr --remote` reaches the server over a non-interactive ssh channel that
# never sources .zshrc, so a ~/.local/bin-only install would leave
# `herdr --remote <ws>.coder` failing with "command not found".
if [ -x "$HOME/.local/bin/herdr" ] && [ ! -e /usr/local/bin/herdr ]; then
  # info() is a bare `echo`, which cannot fail here, so this is not the
  # classic `A && B || C` trap where a failing B would also run C.
  # shellcheck disable=SC2015
  sudo ln -sfn "$HOME/.local/bin/herdr" /usr/local/bin/herdr \
    && info "linked herdr into /usr/local/bin" \
    || warn "could not link herdr into /usr/local/bin"
fi
