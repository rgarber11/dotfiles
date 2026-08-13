#!/usr/bin/env bash
# Profile-aware dotfiles installer.
#
#   install.sh                 auto-detect (headless only; refuses otherwise)
#   install.sh --profile arch  desktop install, must be explicit
#   install.sh --upgrade       re-resolve latest versions of ~/.local tools
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_DIR
PROFILE=""
export UPGRADE=0

usage() {
  cat <<'EOF'
usage: install.sh [--profile <headless|arch>] [--upgrade]

  --profile   Which profile to install. Auto-detected as "headless" inside a
              Coder workspace; "arch" must always be passed explicitly so this
              can never clobber a desktop by accident.
  --upgrade   Re-resolve the latest release of every ~/.local tool, pull the
              zsh plugins, and run `herdr update`. Never runs automatically.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --profile)   PROFILE="${2:?--profile needs a value}"; shift 2 ;;
    --profile=*) PROFILE="${1#*=}"
                 [ -n "$PROFILE" ] || { echo "install.sh: --profile= needs a value" >&2; exit 2; }
                 shift ;;
    --upgrade)   UPGRADE=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           echo "install.sh: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$PROFILE" ]; then
  if [ -n "${CODER_AGENT_URL:-}" ] || [ -d /mnt/dsp-seed ]; then
    PROFILE=headless
  else
    echo "install.sh: not a Coder workspace." >&2
    echo "Pass --profile arch explicitly to install the desktop profile." >&2
    exit 2
  fi
fi

case "$PROFILE" in
  headless|arch) ;;
  *) echo "install.sh: unknown profile: $PROFILE" >&2; exit 2 ;;
esac

echo "==> dotfiles: profile=$PROFILE dir=$DOTFILES_DIR upgrade=$UPGRADE"

# A stable ~/dotfiles path. `coder dotfiles` clones into Coder's global config
# dir (~/.config/coderv2/dotfiles), not $HOME, so without this every file that
# refers to ~/dotfiles would be wrong in the workspace.
if [ "$DOTFILES_DIR" != "$HOME/dotfiles" ]; then
  if [ -L "$HOME/dotfiles" ] || [ ! -e "$HOME/dotfiles" ]; then
    ln -sfn "$DOTFILES_DIR" "$HOME/dotfiles"
    echo "    ~/dotfiles -> $DOTFILES_DIR"
  else
    echo "    warning: ~/dotfiles exists and is not a symlink; leaving it alone" >&2
  fi
fi

# --- link engine ---------------------------------------------------------

backup_path() {   # echoes an unused backup name for $1
  local base="$1.pre-dotfiles" candidate="$1.pre-dotfiles" n=1
  while [ -e "$candidate" ]; do candidate="$base.$n"; n=$((n + 1)); done
  printf '%s\n' "$candidate"
}

link_one() {   # $1 = target relative to $HOME, $2 = source relative to $DOTFILES_DIR
  local target="$HOME/$1" source="$DOTFILES_DIR/$2" backup
  if [ ! -e "$source" ]; then
    echo "    missing source, skipping: $source" >&2
    return 0
  fi
  mkdir -p "$(dirname "$target")"
  # readlink -f on a symlink through a now-missing directory can print nothing;
  # an empty-vs-nonempty comparison then correctly falls through as "not our
  # link" and gets relinked below.
  if [ -L "$target" ] && [ "$(readlink -f "$target")" = "$(readlink -f "$source")" ]; then
    return 0
  fi
  if [ -L "$target" ]; then
    rm "$target"                       # stale link, nothing worth keeping
  elif [ -e "$target" ]; then
    backup="$(backup_path "$target")"
    mv "$target" "$backup"
    echo "    backed up $target -> $backup"
  fi
  ln -s "$source" "$target"
  echo "    linked $1 -> $2"
}

# Table parsing uses default IFS word-splitting: paths must not contain
# whitespace. .links files are curated by us, not user input, so this is a
# safe assumption -- just don't introduce a space in one.
apply_links() {
  local table="$DOTFILES_DIR/profiles/$PROFILE.links" target source
  [ -f "$table" ] || { echo "install.sh: no link table at $table" >&2; exit 1; }
  echo "==> linking"
  while read -r target source; do
    case "$target" in ''|\#*) continue ;; esac
    link_one "$target" "$source"
  done < "$table"
}

apply_links

# --- setup steps ---------------------------------------------------------

if [ "$PROFILE" = headless ]; then
  echo "==> setup"
  # shellcheck source=headless/setup/lib.sh
  source "$DOTFILES_DIR/headless/setup/lib.sh"
  for step in "$DOTFILES_DIR/headless/setup/"[0-9]*.sh; do
    [ -e "$step" ] || continue
    echo "==> $(basename "$step")"
    # shellcheck source=/dev/null
    source "$step"
  done
fi

echo "==> dotfiles: done"
