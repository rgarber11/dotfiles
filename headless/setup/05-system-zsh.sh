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

if [ ! -e "$MARKER" ]; then
  mkdir -p "$MARKER_DIR"
  cat > "$MARKER" <<'EOF'
# Presence of this file tells /etc/zsh/dsp-base.zsh (dsp-base image) to return
# immediately, leaving ~/.zshrc to configure the shell on its own.
# Created by ~/dotfiles/headless/setup/05-system-zsh.sh.
EOF
  info "claimed the shell from the image's /etc/zsh/dsp-base.zsh"
fi
