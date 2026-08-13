#!/usr/bin/env bash
# herdr's own installer drops the binary in ~/.local/bin, which is the PVC, so
# it survives restarts.
#
# Deliberately `command -v` rather than needs_install: needs_install collapses
# "absent" and "--upgrade was passed" into one true, which is right for the
# tarball tools (no self-update, so upgrading IS reinstalling) but wrong here --
# herdr ships its own updater, and collapsing the two made this branch reinstall
# from scratch on every --upgrade while `herdr update` never ran at all.
if ! command -v herdr >/dev/null 2>&1; then
  info "installing herdr"
  curl -fsSL --max-time 120 https://herdr.dev/install.sh | sh >/dev/null 2>&1 \
    || warn "herdr install failed"
elif [ "${UPGRADE:-0}" = 1 ]; then
  info "updating herdr"
  herdr update >/dev/null 2>&1 || warn "herdr update failed"
fi
