#!/usr/bin/env bash
# System libraries that must live in /usr. These are wiped with the container
# filesystem on every workspace restart, so this reinstalls each start -- that
# cost is unavoidable and is exactly why user-facing tools go to ~/.local.

APT_PACKAGES=(
  cmake fd-find fzf
  lua5.1 liblua5.1-0-dev luarocks
  imagemagick libmagickwand-dev
  python3-pip
  fortune-mod fortunes cowsay
  qrencode btop file
)

missing=()
for pkg in "${APT_PACKAGES[@]}"; do
  dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
done

if [ ${#missing[@]} -gt 0 ]; then
  info "apt: installing ${missing[*]}"
  # The image clears /var/lib/apt/lists, so an update is mandatory here.
  #
  # Both apt calls are guarded: this file is sourced into install.sh under
  # `set -euo pipefail`, so an unguarded failure would abort the entire install
  # rather than just this step -- leaving the workspace with no nvim, no zsh
  # plugins, no herdr and bash as the login shell, over a transient mirror blip.
  if sudo apt-get update -qq; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "${missing[@]}" ||
      warn "apt: some packages failed to install (${missing[*]}); continuing"
  else
    warn "apt: update failed; skipping package install this start"
  fi
else
  info "apt: all packages present"
fi

# Ubuntu ships fd as fdfind to avoid a name clash.
if command -v fdfind >/dev/null 2>&1 && [ ! -e "$HOME/.local/bin/fd" ]; then
  # if/else, not `|| warn` with the info after it: the info line used to be
  # reachable only because a failed ln aborted, so guarding the ln without moving
  # the info made the failure path print a warning and "linked fd -> fdfind"
  # together. Unguarded, a read-only ~/.local/bin aborts the whole install over a
  # convenience symlink.
  if ln -sfn "$(command -v fdfind)" "$HOME/.local/bin/fd"; then
    info "linked fd -> fdfind"
  else
    warn "could not link fd -> fdfind"
  fi
fi

# noble's tree-sitter-cli is 0.20.8; nvim-treesitter's main branch needs current.
# --prefix ~/.local rather than a global install: npm's default prefix is the
# root-owned /usr (EACCES as the coder user), and /usr is rebuilt from the
# image on every restart, so a global install would silently reinstall forever.
# ~/.local is the PVC, so this happens once.
if needs_install tree-sitter; then
  info "npm: installing tree-sitter-cli into ~/.local"
  npm install -g --prefix "$HOME/.local" tree-sitter-cli >/dev/null 2>&1 ||
    warn "tree-sitter-cli install failed"
fi
