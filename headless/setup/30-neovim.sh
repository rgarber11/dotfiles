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
#
# The marker is written only after verifying the result, because `Lazy! restore`
# exits 0 even when individual plugins fail to check out. Trusting its exit
# status would write the marker over a half-installed state and never retry.
#
# `want` is captured from lazy-lock.json BEFORE running restore, not after:
# when a plugin's clone fails, lazy.nvim prunes that plugin's own entry back
# out of lazy-lock.json as part of the same restore run. Reading the count
# afterward would shrink `want` to match the failure, hiding it.
BOOTSTRAP_MARKER="$HOME/.local/state/dotfiles/nvim-bootstrapped"
if command -v nvim >/dev/null 2>&1 && [ ! -f "$BOOTSTRAP_MARKER" ]; then
  info "bootstrapping neovim plugins (Lazy! restore)"
  want="$(grep -c '": {' "$HOME/.config/nvim/lazy-lock.json" 2>/dev/null || echo 0)"
  # Bounded: this clones dozens of plugin repositories and was the last unbounded
  # network operation in the profile. `|| true` stopped it aborting the install but
  # not hanging it, and a hang here means install.sh never returns and the
  # workspace never reports ready. 900s is deliberately generous -- a first
  # bootstrap pulls every plugin plus treesitter parsers -- and truncation is
  # already handled: the want/got check below sees the short count, warns, and the
  # restore re-runs next start.
  timeout -k 30 900 nvim --headless "+Lazy! restore" +qa >/dev/null 2>&1 || true
  got="$(find "$HOME/.local/share/nvim/lazy" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
  if [ "$want" -gt 0 ] && [ "$got" -ge "$want" ]; then
    # Guarded: an unwritable ~/.local/state would otherwise abort the install on
    # this line, having already done the expensive part successfully. Without the
    # marker the next start just re-runs the restore, which is idempotent.
    touch "$BOOTSTRAP_MARKER" ||
      warn "could not write $BOOTSTRAP_MARKER; the restore will re-run next start"
    info "neovim plugins installed ($got/$want)"
  else
    warn "neovim bootstrap incomplete ($got/$want plugins); will retry next start"
  fi
fi

# lazy.nvim rewrites lazy-lock.json during restore: init.lua bootstraps lazy
# itself with `git clone --branch=stable`, so lazy's own commit is whatever
# stable is today rather than the pinned one, and restore records the
# difference. ~/.config/nvim symlinks into the cloned repo, so that leaves a
# modified tracked file there and the next `coder dotfiles` pull conflicts.
# The desktop's lockfile is canonical, so put it back.
#
# The inner check is its own `if`, not `cmd && info`: when this block is the
# last thing executed in the file (it is), a failed checkout as a bare `&&`
# list stops being exempt from `set -e` and aborts install.sh outright --
# verified by triggering it with a non-git DOTFILES_DIR. Nesting the `if`
# keeps a failed checkout a plain false condition instead.
if ! git -C "$DOTFILES_DIR" diff --quiet -- shared/nvim/lazy-lock.json 2>/dev/null; then
  if git -C "$DOTFILES_DIR" checkout -- shared/nvim/lazy-lock.json 2>/dev/null; then
    info "restored lazy-lock.json (lazy rewrote it during bootstrap)"
  fi
fi
