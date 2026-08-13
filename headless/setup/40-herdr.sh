#!/usr/bin/env bash
# herdr's own installer drops the binary in ~/.local/bin, which is the PVC, so
# it survives restarts. `herdr update` handles upgrades.
if needs_install herdr; then
  info "installing herdr"
  curl -fsSL --max-time 120 https://herdr.dev/install.sh | sh >/dev/null 2>&1 \
    || warn "herdr install failed"
elif [ "${UPGRADE:-0}" = 1 ]; then
  info "updating herdr"
  herdr update >/dev/null 2>&1 || warn "herdr update failed"
fi
