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
# Echoes the tag, or nothing. Deliberately always returns 0: install.sh runs
# under `set -euo pipefail`, where a bare TAG="$(latest_release_tag ...)"
# assignment inherits this pipeline's status, so a rate-limit or network blip
# would abort the whole install and stop the workspace booting. Callers test
# for an empty string instead.
latest_release_tag() {   # $1 = owner/repo
  local auth=()
  [ -n "${GH_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GH_TOKEN")
  curl -fsSL --max-time 20 "${auth[@]}" \
      "https://api.github.com/repos/$1/releases/latest" 2>/dev/null \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -1
  return 0
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
  # mv across filesystems is copy-then-unlink, so an interrupted move can leave
  # $dest partly populated. If $binpath happened to land, the idempotence check
  # above would report "already installed" over a broken tree forever -- so tear
  # down a failed move rather than leaving it to be found later.
  if ! mv "$tmp" "$dest"; then
    warn "failed to install $name (move failed)"
    rm -rf "$dest" "$tmp"
    return 1
  fi
  ln -sfn "$dest/$binpath" "$HOME/.local/bin/$name"
  info "installed $name $tag"
}

# Every tool this repo installs lands in ~/.local/bin, but install.sh runs from
# Coder's startup script with no login shell, so that directory is not on PATH.
# Without this, needs_install reports every tool missing on every start --
# re-resolving GitHub releases and re-running installers that already succeeded.
export PATH="$HOME/.local/bin:$PATH"

# Guarded, even though a failure here means most steps below will fail anyway:
# this file is sourced before any of them, so an unguarded non-zero (a full or
# read-only PVC) aborts install.sh before a single step runs -- no shell config,
# no git identity, nothing. Warning and letting the steps fail one at a time,
# each with its own message, is strictly more diagnosable than one silent exit.
mkdir -p "$HOME/.local/bin" "$HOME/.local/opt" "$HOME/.local/state/dotfiles" ||
  warn "could not create the ~/.local directories; most steps below will fail"
