#!/usr/bin/env bash
# Neovim from upstream releases into ~/.local (the PVC), never apt: noble ships
# 0.9.5, neovim-ppa/stable has no noble builds at all, and neovim-ppa/unstable
# is a nightly behind current stable. Unpinned, because the desktop is Arch and
# a pin would guarantee the workspace falls behind it.

if needs_install nvim; then
  tag="$(latest_release_tag neovim/neovim)"
  if [ -z "$tag" ]; then
    warn "could not resolve a neovim release; leaving nvim alone"
  else
    # Name must be `nvim`, not `neovim`: install_tarball names the symlink in
    # ~/.local/bin after it.
    install_tarball nvim "$tag" \
      "https://github.com/neovim/neovim/releases/download/$tag/nvim-linux-x86_64.tar.gz" \
      "bin/nvim" 1 || warn "neovim install failed"
  fi
fi

# image.nvim needs the magick rock; init.lua already puts ~/.luarocks on
# package.path, so nothing in the config changes.
if ! luarocks --lua-version=5.1 --local list magick 2>/dev/null | grep -q magick; then
  info "luarocks: installing magick"
  luarocks --lua-version=5.1 --local install magick >/dev/null 2>&1 \
    || warn "magick rock install failed (image.nvim will not render)"
fi

# Install the exact plugin revisions from lazy-lock.json. `restore`, not `sync`
# -- that is what makes parity with the desktop literal rather than approximate.
BOOTSTRAP_MARKER="$HOME/.local/state/dotfiles/nvim-bootstrapped"
if command -v nvim >/dev/null 2>&1 && [ ! -f "$BOOTSTRAP_MARKER" ]; then
  info "bootstrapping neovim plugins (Lazy! restore)"
  if nvim --headless "+Lazy! restore" +qa >/dev/null 2>&1; then
    touch "$BOOTSTRAP_MARKER"
    info "neovim plugins installed"
  else
    warn "Lazy! restore failed; run it by hand and check :Lazy"
  fi
fi
