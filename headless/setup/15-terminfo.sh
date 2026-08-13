#!/usr/bin/env bash
# Ubuntu doesn't ship xterm-ghostty, so a ghostty client connecting to this
# workspace lands on a $TERM the remote can't resolve -- which breaks p10k's
# prompt and zsh line editing. ~/.terminfo is on the PVC, so compiling it once
# survives restarts and this is a no-op on every later start.
if ! infocmp xterm-ghostty >/dev/null 2>&1; then
  if tic -x -o "$HOME/.terminfo" "$DOTFILES_DIR/headless/terminfo/xterm-ghostty.ti" 2>/dev/null; then
    info "compiled xterm-ghostty terminfo into ~/.terminfo"
  else
    warn "could not compile xterm-ghostty terminfo; ghostty sessions may render poorly"
  fi
fi
