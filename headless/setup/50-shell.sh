#!/usr/bin/env bash
# /etc/passwd comes from the image, not the PVC, so the shell change does not
# survive a restart and has to be re-applied on every start.
#
# id -un rather than $USER: install.sh runs from Coder's startup script with no
# login shell, so $USER is simply unset -- and under `set -u` the reference on
# the chsh line aborts the entire install at its last step, after everything
# else has already succeeded. id -un also cannot be stale or inherited wrong.
USER_NAME="$(id -un)"
ZSH_PATH="$(command -v zsh || true)"
if [ -n "$ZSH_PATH" ] && [ "$(getent passwd "$USER_NAME" | cut -d: -f7)" != "$ZSH_PATH" ]; then
  info "setting login shell to $ZSH_PATH"
  sudo chsh -s "$ZSH_PATH" "$USER_NAME" || warn "chsh failed"
fi

# `herdr --remote` reaches the server over a non-interactive ssh channel that
# never sources .zshrc, so a ~/.local/bin-only install would leave
# `herdr --remote <ws>.coder` failing with "command not found".
if [ -x "$HOME/.local/bin/herdr" ] && [ ! -e /usr/local/bin/herdr ]; then
  if sudo ln -sfn "$HOME/.local/bin/herdr" /usr/local/bin/herdr; then
    info "linked herdr into /usr/local/bin"
  else
    warn "could not link herdr into /usr/local/bin"
  fi
fi
