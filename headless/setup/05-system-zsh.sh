#!/usr/bin/env bash
# The dsp-base image now ships its own zsh setup in /etc/zsh/dsp-base.zsh --
# powerlevel10k, the same five plugins, and shared/zsh/{options,functions}.zsh
# baked in. It is sourced from the stock /etc/zsh/zshrc, so it runs for every
# zsh BEFORE ~/.zshrc: without this marker our own zshrc would load p10k,
# zsh-syntax-highlighting and the rest a second time.
#
# This profile stays self-sufficient rather than layering on top of the image's
# config -- so install.sh still produces a working shell on a plain Ubuntu box
# (and in tests/), where /etc/zsh/dsp-base.zsh does not exist and this marker
# is simply inert.
#
# Numbered 05 so it lands before anything else can start a shell. A terminal
# opened in the seconds before the very first `coder dotfiles` run completes
# will still double-load; restarting it is enough.
MARKER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
MARKER="$MARKER_DIR/no-system-rc"

# Both guarded: this is the earliest numbered step, so an unguarded non-zero here
# (an unwritable ~/.config, a full PVC) aborts install.sh before anything else
# runs -- no shell config, no nvim, no git identity. Warning instead costs a
# double-loaded prompt, which is cosmetic by comparison.
if [ ! -e "$MARKER" ]; then
  if ! mkdir -p "$MARKER_DIR"; then
    warn "could not create $MARKER_DIR; the image's zsh config will keep loading alongside ours"
  elif cat > "$MARKER" <<'EOF'
# Presence of this file tells /etc/zsh/dsp-base.zsh (dsp-base image) to return
# immediately, leaving ~/.zshrc to configure the shell on its own.
# Created by ~/dotfiles/headless/setup/05-system-zsh.sh.
EOF
  then
    info "claimed the shell from the image's /etc/zsh/dsp-base.zsh"
  else
    warn "could not write $MARKER; the image's zsh config will keep loading alongside ours"
  fi
fi
