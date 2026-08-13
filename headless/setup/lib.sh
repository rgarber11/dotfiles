#!/usr/bin/env bash
# Helpers for the numbered setup steps. Sourced by install.sh before them.

info() { echo "    $*"; }
warn() { echo "    warning: $*" >&2; }

# True when a tool should be (re)installed: absent, or --upgrade was passed.
needs_install() {   # $1 = command name
  [ "${UPGRADE:-0}" = 1 ] && return 0
  ! command -v "$1" >/dev/null 2>&1
}

# Newest release tag for a GitHub repo, e.g. latest_release_tag neovim/neovim
latest_release_tag() {   # $1 = owner/repo
  local auth=()
  [ -n "${GH_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GH_TOKEN")
  curl -fsSL --max-time 20 "${auth[@]}" \
      "https://api.github.com/repos/$1/releases/latest" 2>/dev/null \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -1
}

# Download a .tar.gz into ~/.local/opt/<name>-<tag> and link one binary.
# Never partially installs: extracts to a temp dir and moves into place.
#
# $5 (strip) matters: archives that wrap everything in a top-level directory
# need 1, but a flat archive holding a bare binary needs 0 -- stripping a
# component there would discard the only file in the tarball.
install_tarball() {   # $1 name  $2 tag  $3 url  $4 binary-path-in-archive  $5 strip (default 1)
  local name="$1" tag="$2" url="$3" binpath="$4" strip="${5:-1}"
  local dest="$HOME/.local/opt/$name-$tag" tmp
  if [ -x "$dest/$binpath" ]; then
    ln -sfn "$dest/$binpath" "$HOME/.local/bin/$name"
    info "$name $tag already installed"
    return 0
  fi
  info "downloading $name $tag"
  tmp="$(mktemp -d)"
  if ! curl -fsSL --max-time 300 "$url" | tar -xz -C "$tmp" --strip-components="$strip"; then
    warn "failed to download $name from $url"
    rm -rf "$tmp"
    return 1
  fi
  mkdir -p "$HOME/.local/opt" "$HOME/.local/bin"
  rm -rf "$dest"
  mv "$tmp" "$dest"
  ln -sfn "$dest/$binpath" "$HOME/.local/bin/$name"
  info "installed $name $tag"
}

mkdir -p "$HOME/.local/bin" "$HOME/.local/opt" "$HOME/.local/state/dotfiles"
