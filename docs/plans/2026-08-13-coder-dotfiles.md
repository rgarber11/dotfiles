# Coder Workspace Dotfiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure `rgarber11/dotfiles` into `shared/` + `arch/` + `headless/` with a profile-aware `install.sh`, so the repo can be used as a Coder `dotfiles_uri` for the `dsp-base` template.

**Architecture:** `install.sh` detects its profile, symlinks files listed in a `profiles/<profile>.links` table, then sources numbered scripts in `headless/setup/`. Only `/home/coder` persists in the workspace, so user-facing tools install into `~/.local` from upstream releases (unpinned) while apt covers `/usr`-resident system libraries only.

**Tech Stack:** bash, zsh, git, podman (test harness), Coder CLI, Ubuntu 24.04.

**Spec:** `docs/specs/2026-08-13-coder-dotfiles-design.md`. Read it before starting.

**Branch:** `coder-dotfiles` (already created; the spec is committed there).

> ## ⚠️ Safety rule for every task
>
> This plan is executed **on the real Arch desktop**, where `$HOME` is
> `/home/rgarber11` and this repo genuinely is `~/dotfiles`. `install.sh` writes
> symlinks into `$HOME`.
>
> **Never invoke `install.sh` against the real `$HOME`.** Once
> `profiles/headless.links` exists, even `CODER_AGENT_URL=x ./install.sh` would
> apply the *headless* profile to the desktop — replacing `~/.zshrc` and
> `~/.config/nvim`. It backs up what it overwrites, but it would still hijack the
> live shell and editor config.
>
> Every host-side invocation must run against a throwaway `$HOME`:
>
> ```bash
> SANDBOX="$(mktemp -d)"
> HOME="$SANDBOX" CODER_AGENT_URL=x ./install.sh 2>&1 | head -30
> rm -rf "$SANDBOX"
> ```
>
> The only exception is the guard test `env -u CODER_AGENT_URL ./install.sh`,
> which exits 2 before touching anything. Anything more thorough belongs in the
> podman harness, which is what it is for.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `install.sh` | Arg parsing, profile detection, `~/dotfiles` symlink, link engine, setup-step driver |
| `profiles/headless.links` | Link table for the Coder workspace |
| `profiles/arch.links` | Link table for the desktop |
| `headless/setup/lib.sh` | Logging helpers, GitHub release resolution, tarball installer |
| `headless/setup/10-packages.sh` | apt system libraries + npm `tree-sitter-cli` |
| `headless/setup/20-zsh-plugins.sh` | Clone/update the five zsh plugins |
| `headless/setup/30-neovim.sh` | Neovim from upstream release + `Lazy! restore` + magick rock |
| `headless/setup/35-difftastic.sh` | difftastic from upstream release |
| `headless/setup/37-fastfetch.sh` | fastfetch from upstream release |
| `headless/setup/40-herdr.sh` | herdr via its installer |
| `headless/setup/45-gitconfig.sh` | Generate `~/.gitconfig`; unset `GIT_*` in bash rc files |
| `headless/setup/50-shell.sh` | `chsh` to zsh; herdr into `/usr/local/bin` |
| `shared/zsh/options.zsh` | setopt/bindkey/history/correction, both profiles |
| `shared/zsh/functions.zsh` | The keeper shell functions, both profiles |
| `shared/zsh/p10k.zsh` | Prompt config, both profiles |
| `shared/git/common.gitconfig` | Identity, prefs, aliases, both profiles |
| `shared/nvim/` | Neovim config, both profiles (moved verbatim) |
| `headless/zshrc`, `headless/zshenv` | Workspace shell |
| `headless/gitconfig`, `headless/herdr.toml` | Workspace-only git + herdr |
| `arch/zshrc`, `arch/gitconfig`, `arch/herdr.toml` | Desktop equivalents |
| `tests/Containerfile`, `tests/run.sh`, `tests/lib.sh` | Podman harness simulating the workspace |

**Why a container harness:** the workspace's `/usr` is ephemeral and `/home/coder` is a PVC. A podman named volume mounted at `/home/coder`, with the container recreated between runs, reproduces that split exactly — which is the only way to catch "installed to the wrong place" and idempotence bugs without restarting the real workspace.

---

## Task 1: Test harness

**Files:**
- Create: `tests/Containerfile`
- Create: `tests/lib.sh`
- Create: `tests/run.sh`

- [ ] **Step 1: Write the container image**

`tests/Containerfile` — mirrors the real `dsp-base` image, including its `rm -rf /var/lib/apt/lists/*` so we catch any missing `apt-get update`:

```dockerfile
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget git sudo tmux vim less jq ripgrep unzip zip \
      build-essential python3 python3-venv pkg-config procps locales \
      openssh-client gnupg2 zsh nodejs npm \
    && rm -rf /var/lib/apt/lists/* \
    && locale-gen en_US.UTF-8
ARG USER=coder
RUN useradd --groups sudo --create-home --shell /bin/bash ${USER} \
    && echo "${USER} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/${USER} \
    && chmod 0440 /etc/sudoers.d/${USER}
USER ${USER}
ENV LANG=en_US.UTF-8
WORKDIR /home/${USER}
```

- [ ] **Step 2: Write the assertion helpers**

`tests/lib.sh`:

```bash
#!/usr/bin/env bash
# Assertion helpers for the dotfiles container harness.

FAILURES=0

pass() { printf '  \033[32mok\033[0m   %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

assert_ok() {   # description, command...
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc (command: $*)"; fi
}

assert_fails() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then fail "$desc (command unexpectedly succeeded: $*)"; else pass "$desc"; fi
}

assert_contains() {   # description, needle, haystack
  case "$3" in
    *"$2"*) pass "$1" ;;
    *)      fail "$1 (missing: $2)" ;;
  esac
}

assert_not_contains() {
  case "$3" in
    *"$2"*) fail "$1 (unexpectedly present: $2)" ;;
    *)      pass "$1" ;;
  esac
}

summary() {
  if [ "$FAILURES" -eq 0 ]; then
    printf '\n\033[32mall checks passed\033[0m\n'; return 0
  fi
  printf '\n\033[31m%d check(s) failed\033[0m\n' "$FAILURES"; return 1
}
```

- [ ] **Step 3: Write the runner**

`tests/run.sh`:

```bash
#!/usr/bin/env bash
# Runs install.sh in a container that mimics a dsp-base workspace.
#
#   ./tests/run.sh          fresh volume, install, assert, simulate restart, assert again
#   ./tests/run.sh --keep   reuse the existing volume (faster iteration)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
IMAGE=dotfiles-test
VOLUME=dotfiles-test-home
# shellcheck source=tests/lib.sh
source "$HERE/lib.sh"

[ "${1:-}" = "--keep" ] || podman volume rm -f "$VOLUME" >/dev/null 2>&1 || true
podman volume create "$VOLUME" >/dev/null 2>&1 || true
podman build -q -t "$IMAGE" -f "$HERE/Containerfile" "$HERE" >/dev/null

# Each invocation is a NEW container on the SAME volume: /usr resets, $HOME persists.
in_workspace() {
  # The GIT_* values mimic what the Coder agent exports. They are deliberately
  # WRONG so the identity assertions actually prove .zshenv/.bashrc beat them;
  # without these the test would pass even if the unset were missing entirely.
  podman run --rm -i \
    -v "$VOLUME:/home/coder" \
    -v "$REPO:/repo:ro" \
    -e CODER_AGENT_URL=http://fake.invalid \
    -e GIT_AUTHOR_NAME="Wrong Person" \
    -e GIT_AUTHOR_EMAIL=wrong@example.com \
    -e GIT_COMMITTER_NAME="Wrong Person" \
    -e GIT_COMMITTER_EMAIL=wrong@example.com \
    "$IMAGE" bash -s
}

install_run() {
  in_workspace <<'SH'
set -e
# Reproduce what `coder dotfiles` does: clone into Coder's global config dir.
mkdir -p ~/.config/coderv2
rm -rf ~/.config/coderv2/dotfiles
cp -r /repo ~/.config/coderv2/dotfiles
chmod +x ~/.config/coderv2/dotfiles/install.sh
~/.config/coderv2/dotfiles/install.sh
SH
}

echo "=== first install (fresh home) ==="
FIRST="$(install_run 2>&1)" || { echo "$FIRST"; echo "install failed"; exit 1; }
echo "$FIRST" | tail -20

echo
echo "=== assertions after first install ==="
CHECKS="$(in_workspace <<'SH'
export PATH="$HOME/.local/bin:$PATH"
echo "nvim=$(command -v nvim || echo none)"
echo "difft=$(command -v difft || echo none)"
echo "fastfetch=$(command -v fastfetch || echo none)"
echo "herdr=$(command -v herdr || echo none)"
echo "zshrc=$(readlink -f ~/.zshrc || echo none)"
echo "nvimcfg=$(readlink -f ~/.config/nvim || echo none)"
echo "gitconfig_first_line=$(head -1 ~/.gitconfig 2>/dev/null)"
echo "git_email=$(git config --get user.email)"
echo "zsh_ident=$(zsh -ic 'git var GIT_AUTHOR_IDENT' 2>/dev/null | tail -1)"
echo "bash_ident=$(bash -lc 'git var GIT_AUTHOR_IDENT' 2>/dev/null | tail -1)"
echo "shell=$(getent passwd coder | cut -d: -f7)"
echo "repo_status=$(git -C ~/.config/coderv2/dotfiles status --porcelain | wc -l)"
SH
)"
echo "$CHECKS"

assert_not_contains "nvim installed"      "nvim=none"      "$CHECKS"
assert_not_contains "difftastic installed" "difft=none"    "$CHECKS"
assert_not_contains "fastfetch installed" "fastfetch=none" "$CHECKS"
assert_not_contains "herdr installed"     "herdr=none"     "$CHECKS"
assert_contains "nvim is under ~/.local"  "nvim=/home/coder/.local/bin/nvim" "$CHECKS"
assert_contains "gitconfig is generated"  "gitconfig_first_line=# generated by dotfiles install.sh" "$CHECKS"
assert_contains "zsh identity beats the agent env" \
  "zsh_ident=Richard Garber <9834847+rgarber11@users.noreply.github.com>" "$CHECKS"
assert_contains "bash identity beats the agent env" \
  "bash_ident=Richard Garber <9834847+rgarber11@users.noreply.github.com>" "$CHECKS"
assert_not_contains "the wrong address never wins" "wrong@example.com" "$CHECKS"
assert_contains "login shell is zsh"      "shell=/usr/bin/zsh" "$CHECKS"
assert_contains "dotfiles repo is clean"  "repo_status=0" "$CHECKS"

echo
echo "=== second install (new container, same home: simulates restart) ==="
SECOND="$(install_run 2>&1)" || { echo "$SECOND"; echo "second install failed"; exit 1; }
echo "$SECOND" | tail -20

echo
echo "=== assertions after restart ==="
assert_not_contains "neovim not re-downloaded"    "downloading nvim"      "$SECOND"
assert_not_contains "difftastic not re-downloaded" "downloading difft"     "$SECOND"
assert_not_contains "fastfetch not re-downloaded" "downloading fastfetch" "$SECOND"
assert_not_contains "herdr not reinstalled"       "installing herdr"      "$SECOND"

AFTER="$(in_workspace <<'SH'
export PATH="$HOME/.local/bin:$PATH"
echo "nvim=$(command -v nvim || echo none)"
echo "shell=$(getent passwd coder | cut -d: -f7)"
echo "backups=$(ls -d ~/*.pre-dotfiles* 2>/dev/null | wc -l)"
echo "bashrc_blocks=$(grep -c 'dotfiles: coder git identity' ~/.bashrc)"
SH
)"
echo "$AFTER"
assert_contains "nvim survived the restart" "nvim=/home/coder/.local/bin/nvim" "$AFTER"
assert_contains "chsh re-applied after restart" "shell=/usr/bin/zsh" "$AFTER"
assert_contains "no duplicate bashrc block" "bashrc_blocks=1" "$AFTER"

summary
```

- [ ] **Step 4: Make them executable and confirm the harness itself runs**

```bash
chmod +x tests/run.sh
shellcheck tests/run.sh tests/lib.sh
podman build -t dotfiles-test -f tests/Containerfile tests/
```
Expected: shellcheck clean; image builds.

- [ ] **Step 5: Run it to verify it fails**

Run: `./tests/run.sh`
Expected: FAIL — `install.sh` does not exist yet, so the first install errors out. This is the red state the rest of the plan turns green.

- [ ] **Step 6: Commit**

```bash
git add tests/
git commit -m "test: podman harness simulating a dsp-base workspace"
```

---

## Task 2: Restructure the repository

No behavior change — pure moves, so a `git mv`-only commit stays reviewable.

**Files:**
- Move: everything listed below
- Modify: `.gitignore`

- [ ] **Step 1: Create the directory skeleton**

```bash
mkdir -p shared/zsh shared/git headless/setup profiles arch editors
```

- [ ] **Step 2: Move shared and editor configs**

```bash
git mv nvim shared/nvim
git mv cpp editors/cpp
git mv js editors/js
```

- [ ] **Step 3: Move the Arch-only configs**

```bash
for d in hypr kitty alacritty anyrun swaync quickshell vicinae fontconfig; do
  git mv "$d" "arch/$d"
done
git mv .zshrc arch/zshrc
git mv .gitconfig arch/gitconfig
```

- [ ] **Step 4: Untrack herdr runtime junk, keep the config**

```bash
git mv herdr/config.toml arch/herdr.toml
git rm --cached herdr/herdr-client.log herdr/herdr-server.log herdr/session.json herdr/.plugins.lock
rm -rf herdr
```

- [ ] **Step 5: Extend `.gitignore`**

Append to `.gitignore`:

```gitignore
# herdr runtime state
*.log
*.sock
session.json
.plugins.lock

# machine-local shell overrides
.zshrc.local

# installer backups
*.pre-dotfiles
*.pre-dotfiles.*
```

- [ ] **Step 6: Verify nothing was lost**

```bash
git status --short
git ls-files | wc -l
```
Expected: only renames (`R`) and the four deletions; 96 tracked files (100 minus the 4 untracked runtime files).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor: split repo into shared/, arch/, editors/"
```

---

## Task 3: `install.sh` core

**Files:**
- Create: `install.sh`

- [ ] **Step 1: Write the script**

```bash
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
    --profile=*) PROFILE="${1#*=}"; shift ;;
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
```

- [ ] **Step 2: Make it executable and lint it**

```bash
chmod +x install.sh
shellcheck install.sh
```
Expected: no warnings. `install.sh` must be executable — Coder skips non-executable install scripts.

- [ ] **Step 3: Verify the safety guard**

```bash
env -u CODER_AGENT_URL ./install.sh; echo "exit=$?"
```
Expected: exits 2 with "not a Coder workspace." — the desktop is never touched implicitly.

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "feat: profile-aware install.sh with link engine"
```

---

## Task 4: Link tables

**Files:**
- Create: `profiles/headless.links`
- Create: `profiles/arch.links`

- [ ] **Step 1: Write the headless table**

`profiles/headless.links` — columns are `<target relative to $HOME>` and `<source relative to repo root>`, whitespace-separated:

```
# target                       source
.zshrc                         headless/zshrc
.zshenv                        headless/zshenv
.p10k.zsh                      shared/zsh/p10k.zsh
.config/nvim                   shared/nvim
.config/herdr/config.toml      headless/herdr.toml
.clang-format                  editors/cpp/.clang-format
```

Note `~/.gitconfig` is deliberately absent: it is generated by `45-gitconfig.sh`, not linked, so the template's `credential.helper` write cannot dirty the repo.

- [ ] **Step 2: Write the arch table**

`profiles/arch.links`:

```
# target                       source
.zshrc                         arch/zshrc
.gitconfig                     arch/gitconfig
.p10k.zsh                      shared/zsh/p10k.zsh
.config/nvim                   shared/nvim
.config/herdr/config.toml      arch/herdr.toml
.config/hypr                   arch/hypr
.config/kitty                  arch/kitty
.config/alacritty              arch/alacritty
.config/anyrun                 arch/anyrun
.config/swaync                 arch/swaync
.config/quickshell             arch/quickshell
.config/vicinae                arch/vicinae
.config/fontconfig             arch/fontconfig
.clang-format                  editors/cpp/.clang-format
```

- [ ] **Step 3: Verify the parser handles comments and blanks**

Against a throwaway `$HOME` — see the safety rule at the top of this plan. Run
against the real `$HOME` and this would symlink the desktop's `~/.zshrc` and
`~/.config/nvim` into the headless profile.

```bash
SANDBOX="$(mktemp -d)"
HOME="$SANDBOX" CODER_AGENT_URL=x ./install.sh 2>&1 | head -30
find "$SANDBOX" -maxdepth 2 | head -20
rm -rf "$SANDBOX"
```
Expected: `==> linking`, then "missing source, skipping" for sources later tasks create (`headless/zshrc`, `shared/zsh/p10k.zsh`, …), `linked .config/nvim -> shared/nvim` and `linked .clang-format -> editors/cpp/.clang-format` for the two that already exist, and no parse errors. The `find` confirms links landed in the sandbox, not in the real home.

- [ ] **Step 4: Commit**

```bash
git add profiles/
git commit -m "feat: link tables for headless and arch profiles"
```

---

## Task 5: Shared zsh options and functions

**Files:**
- Create: `shared/zsh/options.zsh`
- Create: `shared/zsh/functions.zsh`

- [ ] **Step 1: Write the options file**

`shared/zsh/options.zsh`:

```zsh
# Shell options shared by every profile. Sourced from each profile's .zshrc.

setopt autocd extendedglob
unsetopt beep nomatch notify

bindkey -e
# Standard xterm Alt+arrow sequences -> Emacs word motion.
bindkey -M emacs '\e[1;3C' forward-word
bindkey -M emacs '\e[1;3D' backward-word

# History. oh-my-zsh used to supply all of this; without it zsh saves nothing
# at all. extended_history is load-bearing beyond taste: command_stats() parses
# the `: <epoch>:<elapsed>;<command>` form out of ~/.zsh_history and returns
# nothing without it.
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt extended_history inc_append_history share_history
setopt hist_ignore_dups hist_ignore_space hist_verify

# Spelling correction, minus the parts that fight tooling directories.
ENABLE_CORRECTION="true"
setopt nocorrectall
setopt correct
CORRECT_IGNORE=".sst|.expo"
CORRECT_IGNORE_FILE=".ssh|.expo"
```

- [ ] **Step 2: Write the functions file**

`shared/zsh/functions.zsh` — lifted from the old `.zshrc`, with `give_fortune` made portable:

```zsh
# Shell functions shared by every profile. Sourced from each profile's .zshrc.

# cd to the root of the current git worktree.
cgt() {
  cd "$(git rev-parse --show-toplevel)" || return
}

# Every stream and container field ffprobe knows about, as JSON.
ffmpeg_all_info() {
  ffprobe -v quiet -of json -show_entries stream:format -show_chapters file:"$1"
}

delete_node_modules() {
  echo -n "Are you sure you want to delete all node_modules directories (CHECK THE DIRECTORY YOU'RE IN!!!)? (y/n): "
  read REPLY
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    return 1
  fi
  find . -name "node_modules" -type d -prune -exec rm -rf '{}' \;
}

# Frequency of subcommands used with $1, e.g. `command_stats git`.
# Depends on extended_history being set in options.zsh.
command_stats() {
  local uname_output=$(uname -s)
  local awk_column=""
  local grep_command=""
  case "${uname_output}" in
  Linux*)
    awk_column="{ print \"$1 \"\$3 }"
    grep_command="[[:digit:]];$1[ \n]"
    ;;
  Darwin*)
    awk_column="{ print \"$1 \"\$2 }"
    grep_command="^$1[ \n]"
    ;;
  *)
    echo "Unsupported OS: ${uname_output}"
    return 1
    ;;
  esac
  grep -E "$grep_command" ~/.zsh_history | awk "$awk_column" | sort | uniq -c | sort -nr
}

# Unzip into a directory named after the archive rather than the cwd.
unzip_into() {
  unzip "$1" -d "${1:t:r}"
}

to_qr() {
  if [[ -n "$1" ]]; then
    qrencode -o - "$1" | chafa -f kitty -
  elif [[ ! -t 0 ]]; then
    cat | qrencode -o - | chafa -f kitty -
  else
    echo "Usage: to_qr <string> (or pipe input to it)"
    return 1
  fi
}

refresh_git_branch() {
  declare -a commits
  commits=$(git rev-list HEAD)
  local branches_that_head_has=$(git branch --contains HEAD)
  for commit in $commits; do
    branches=$(git branch --contains $commit)
    echo "$branches"
    for branch in $branches; do
      if [[ $branches_that_head_has == *"$branch"* ]]; then
        continue
      fi
      echo "$branch"
      break 2
    done
  done
}

# 30% Russian fortunes where that database exists. Ubuntu ships no fortunes-ru,
# so fall back rather than printing an error into every new shell.
give_fortune() {
  (( $+commands[fortune] )) || return 0
  (( $+commands[cowsay] )) || return 0
  if (( RANDOM % 10 < 3 )) && fortune -f 2>&1 | grep -qw ru; then
    fortune ru | cowsay
  else
    fortune -a | cowsay
  fi
}
```

- [ ] **Step 3: Verify both files parse under zsh**

```bash
zsh -n shared/zsh/options.zsh && zsh -n shared/zsh/functions.zsh && echo PARSE_OK
```
Expected: `PARSE_OK`.

- [ ] **Step 4: Verify the fortune fallback logic in isolation**

```bash
zsh -c 'source shared/zsh/functions.zsh; give_fortune; echo "exit=$?"'
```
Expected: a cowsay fortune (this machine has both), `exit=0`. On a box without `fortune` it must print nothing and still exit 0.

- [ ] **Step 5: Commit**

```bash
git add shared/zsh/
git commit -m "feat: extract shared zsh options and functions"
```

---

## Task 6: Headless zsh files

**Files:**
- Create: `shared/zsh/p10k.zsh` (copied from `~/.p10k.zsh`)
- Create: `headless/zshrc`
- Create: `headless/zshenv`

- [ ] **Step 1: Commit the prompt config**

```bash
cp ~/.p10k.zsh shared/zsh/p10k.zsh
wc -l shared/zsh/p10k.zsh
```
Expected: 1834 lines.

- [ ] **Step 2: Write `headless/zshenv`**

```zsh
# Runs for EVERY zsh invocation, interactive or not. Keep it minimal.
#
# The Coder agent exports GIT_AUTHOR_*/GIT_COMMITTER_* from the workspace
# owner's Coder account email, and git resolves those ahead of user.email --
# so without this, shared/git/common.gitconfig would have no effect and every
# commit would carry the wrong address.
#
# Do NOT unset GIT_SSH_COMMAND or GIT_ASKPASS: Coder relies on both.
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
```

- [ ] **Step 3: Write `headless/zshrc`**

```zsh
# ~/.zshrc -- Coder workspace (headless profile). Managed by ~/dotfiles.
# Machine-local overrides belong in ~/.zshrc.local, which is gitignored.

# Powerlevel10k instant prompt. Must stay near the top; anything that writes to
# the console (the greeting, notably) has to come after it.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export EDITOR=nvim
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
export NODE_OPTIONS="--max_old_space_size=8196 --stack-trace-limit=1000"

ZSH_PLUGIN_DIR="$HOME/.local/share/zsh/plugins"

# zsh-completions has to extend fpath before compinit runs.
fpath=("$ZSH_PLUGIN_DIR/zsh-completions/src" "$HOME/.local/share/zsh/site-functions" $fpath)
autoload -Uz compinit && compinit
zstyle :compinstall filename "$HOME/.zshrc"

source "$HOME/dotfiles/shared/zsh/options.zsh"
source "$HOME/dotfiles/shared/zsh/functions.zsh"

# Prompt.
source "$ZSH_PLUGIN_DIR/powerlevel10k/powerlevel10k.zsh-theme"
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Plugin order is load-bearing: autosuggestions, then syntax-highlighting,
# then history-substring-search LAST -- it must bind after highlighting loads.
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=23'
source "$ZSH_PLUGIN_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh"
source "$ZSH_PLUGIN_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
source "$ZSH_PLUGIN_DIR/zsh-history-substring-search/zsh-history-substring-search.zsh"
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
bindkey -M emacs '^P' history-substring-search-up
bindkey -M emacs '^N' history-substring-search-down

# Re-resolve the latest nvim/difft/fastfetch, pull zsh plugins, update herdr.
alias dotup="$HOME/dotfiles/install.sh --upgrade"

[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

# Greeting last: it writes to the console, so it has to follow instant prompt.
give_fortune
```

- [ ] **Step 4: Verify it parses**

```bash
zsh -n headless/zshrc && zsh -n headless/zshenv && echo PARSE_OK
```
Expected: `PARSE_OK`.

- [ ] **Step 5: Commit**

```bash
git add shared/zsh/p10k.zsh headless/zshrc headless/zshenv
git commit -m "feat: headless zshrc, zshenv, and committed p10k config"
```

---

## Task 7: Setup library

**Files:**
- Create: `headless/setup/lib.sh`

- [ ] **Step 1: Write the library**

```bash
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
```

The `downloading <name>` string is what `tests/run.sh` asserts is *absent* on the second run.

- [ ] **Step 2: Lint**

```bash
shellcheck headless/setup/lib.sh
```
Expected: clean.

- [ ] **Step 3: Verify release resolution works**

```bash
bash -c 'source headless/setup/lib.sh; latest_release_tag neovim/neovim'
```
Expected: a tag such as `v0.12.4`.

- [ ] **Step 4: Commit**

```bash
git add headless/setup/lib.sh
git commit -m "feat: setup library for release resolution and tarball installs"
```

---

## Task 8: System packages

**Files:**
- Create: `headless/setup/10-packages.sh`

- [ ] **Step 1: Write the step**

```bash
# System libraries that must live in /usr. These are wiped with the container
# filesystem on every workspace restart, so this reinstalls each start -- that
# cost is unavoidable and is exactly why user-facing tools go to ~/.local.

APT_PACKAGES=(
  cmake fd-find fzf
  lua5.1 liblua5.1-0-dev luarocks
  imagemagick libmagickwand-dev
  python3-pip
  fortune-mod fortunes cowsay
  qrencode chafa
)

missing=()
for pkg in "${APT_PACKAGES[@]}"; do
  dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
done

if [ ${#missing[@]} -gt 0 ]; then
  info "apt: installing ${missing[*]}"
  # The image clears /var/lib/apt/lists, so an update is mandatory here.
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "${missing[@]}"
else
  info "apt: all packages present"
fi

# Ubuntu ships fd as fdfind to avoid a name clash.
if command -v fdfind >/dev/null 2>&1 && [ ! -e "$HOME/.local/bin/fd" ]; then
  ln -sfn "$(command -v fdfind)" "$HOME/.local/bin/fd"
  info "linked fd -> fdfind"
fi

# noble's tree-sitter-cli is 0.20.8; nvim-treesitter's main branch needs current.
if needs_install tree-sitter; then
  info "npm: installing tree-sitter-cli"
  npm install -g tree-sitter-cli >/dev/null 2>&1 || warn "tree-sitter-cli install failed"
fi
```

- [ ] **Step 2: Lint**

```bash
shellcheck -x headless/setup/10-packages.sh
```
Expected: clean (`-x` lets it follow the `lib.sh` source from `install.sh`).

- [ ] **Step 3: Commit**

```bash
git add headless/setup/10-packages.sh
git commit -m "feat: apt and npm system package step"
```

---

## Task 9: zsh plugins

**Files:**
- Create: `headless/setup/20-zsh-plugins.sh`

- [ ] **Step 1: Write the step**

```bash
# Five plugins, plain git clones. No plugin manager: for a fixed set this small
# a manager only adds startup cost and indirection. ~/.local is the PVC, so
# these clone once and persist; `dotup` pulls them.

ZSH_PLUGIN_DIR="$HOME/.local/share/zsh/plugins"
ZSH_PLUGINS=(
  https://github.com/romkatv/powerlevel10k
  https://github.com/zsh-users/zsh-completions
  https://github.com/zsh-users/zsh-autosuggestions
  https://github.com/zsh-users/zsh-syntax-highlighting
  https://github.com/zsh-users/zsh-history-substring-search
)

mkdir -p "$ZSH_PLUGIN_DIR"
for url in "${ZSH_PLUGINS[@]}"; do
  name="$(basename "$url")"
  dir="$ZSH_PLUGIN_DIR/$name"
  if [ -d "$dir/.git" ]; then
    if [ "${UPGRADE:-0}" = 1 ]; then
      info "updating $name"
      git -C "$dir" pull --quiet --ff-only || warn "could not update $name"
    fi
  else
    info "cloning $name"
    git clone --depth=1 --quiet "$url" "$dir" || warn "could not clone $name"
  fi
done
```

- [ ] **Step 2: Lint**

```bash
shellcheck -x headless/setup/20-zsh-plugins.sh
```
Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add headless/setup/20-zsh-plugins.sh
git commit -m "feat: zsh plugin install step"
```

---

## Task 10: Neovim

**Files:**
- Create: `headless/setup/30-neovim.sh`

- [ ] **Step 1: Write the step**

```bash
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
```

- [ ] **Step 2: Lint**

```bash
shellcheck -x headless/setup/30-neovim.sh
```
Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add headless/setup/30-neovim.sh
git commit -m "feat: neovim install and plugin bootstrap step"
```

---

## Task 11: difftastic and fastfetch

**Files:**
- Create: `headless/setup/35-difftastic.sh`
- Create: `headless/setup/37-fastfetch.sh`

- [ ] **Step 1: Write the difftastic step**

`headless/setup/35-difftastic.sh` — its own step because `diff.external = difft` in `common.gitconfig` depends on it; a missing binary breaks every `git diff`:

```bash
# difftastic is not packaged for noble. Upstream release into ~/.local.
if needs_install difft; then
  tag="$(latest_release_tag Wilfred/difftastic)"
  if [ -z "$tag" ]; then
    warn "could not resolve a difftastic release; git diff.external will be broken"
  else
    # strip=0: the difftastic archive is flat, holding a bare `difft` binary.
    install_tarball difft "$tag" \
      "https://github.com/Wilfred/difftastic/releases/download/$tag/difft-x86_64-unknown-linux-gnu.tar.gz" \
      "difft" 0 || warn "difftastic install failed"
  fi
fi
```

- [ ] **Step 2: Write the fastfetch step**

`headless/setup/37-fastfetch.sh`:

```bash
# fastfetch is not in noble (it lands in 24.10). Deliberately the tarball and
# not the .deb or the zhangsongcui3371 PPA: both install into /usr, which is
# ephemeral, so either would be discarded and re-downloaded on every start.
# Installed for manual use; nothing sources it from an rc file.
if needs_install fastfetch; then
  tag="$(latest_release_tag fastfetch-cli/fastfetch)"
  if [ -z "$tag" ]; then
    warn "could not resolve a fastfetch release"
  else
    install_tarball fastfetch "$tag" \
      "https://github.com/fastfetch-cli/fastfetch/releases/download/$tag/fastfetch-linux-amd64.tar.gz" \
      "usr/bin/fastfetch" 1 || warn "fastfetch install failed"
  fi
fi
```

- [ ] **Step 3: Confirm the archive layout matches the binary paths**

The `install_tarball` calls above assume `difft` sits at the archive root and `fastfetch` at `usr/bin/fastfetch` after `--strip-components=1`. Verify before trusting them:

```bash
curl -fsSL "https://github.com/Wilfred/difftastic/releases/latest/download/difft-x86_64-unknown-linux-gnu.tar.gz" | tar -tz | head
curl -fsSL "https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-amd64.tar.gz" | tar -tz | head
```
Expected: difftastic lists a bare `difft`; fastfetch lists `fastfetch-<version>/usr/bin/fastfetch`. If either differs, correct the fourth argument to `install_tarball` before committing.

- [ ] **Step 4: Lint**

```bash
shellcheck -x headless/setup/35-difftastic.sh headless/setup/37-fastfetch.sh
```
Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add headless/setup/35-difftastic.sh headless/setup/37-fastfetch.sh
git commit -m "feat: difftastic and fastfetch install steps"
```

---

## Task 12: herdr

**Files:**
- Create: `headless/setup/40-herdr.sh`
- Create: `headless/herdr.toml`
- Modify: `arch/herdr.toml`

- [ ] **Step 1: Write the headless herdr config**

`headless/herdr.toml` — the desktop config with the theme swapped. TOML has no include mechanism, so this is a complete file rather than a fragment:

```toml
onboarding = false

[theme]
name = "catppuccin"
auto_switch = false

[ui.toast]
delivery = "system"

[ui]
show_agent_labels_on_pane_borders = true
agent_panel_sort = "spaces"

[experimental]
kitty_graphics = true
```

- [ ] **Step 2: Confirm `arch/herdr.toml` is unchanged apart from its location**

```bash
git show HEAD:arch/herdr.toml | head -4
```
Expected: still `name = "solarized"`. The desktop theme does not change.

- [ ] **Step 3: Write the install step**

`headless/setup/40-herdr.sh`:

```bash
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
```

- [ ] **Step 4: Lint**

```bash
shellcheck -x headless/setup/40-herdr.sh
```
Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add headless/setup/40-herdr.sh headless/herdr.toml
git commit -m "feat: herdr install step and catppuccin workspace config"
```

---

## Task 13: git configuration

**Files:**
- Create: `shared/git/common.gitconfig`
- Create: `headless/gitconfig`
- Create: `headless/setup/45-gitconfig.sh`

- [ ] **Step 1: Write the shared config**

`shared/git/common.gitconfig` — captures the live desktop config, which is ahead of the repo's old `.gitconfig`:

```ini
# Shared by every profile. Signing lives in arch/gitconfig only.
[user]
	name = Richard Garber
	email = 9834847+rgarber11@users.noreply.github.com
[core]
	autocrlf = input
[push]
	autoSetupRemote = true
[rerere]
	enabled = true
[diff]
	external = difft
[alias]
	pushf = push --force-with-lease
	append-commit = commit --amend --date=now --no-edit
	force-pull = pull --rebase --autostash
	staash = stash --include-untracked
	lg = log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold green)(%ar)%C(reset) %C(white)%s%C(reset) %C(dim white)- %an%C(reset)%C(auto)%d%C(reset)' --all
	lgb = log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold cyan)%aD%C(reset) %C(bold green)(%ar)%C(reset)%C(auto)%d%C(reset)%n          %C(white)%s%C(reset) %C(dim white)- %an%C(reset)'
	force-rebase = !f() { git rebase --onto "$1" 'HEAD^'; }; f
```

- [ ] **Step 2: Write the headless overrides**

`headless/gitconfig`:

```ini
# Coder workspace only. No commit signing: the workspace has no signing key,
# and the requirement is explicitly unsigned commits here.
[credential]
	helper = store
```

- [ ] **Step 3: Write the generation step**

`headless/setup/45-gitconfig.sh`:

```bash
# ~/.gitconfig is GENERATED, never symlinked. The template's startup script runs
# `git config --global credential.helper store`; against a symlink that write
# would land inside the tracked repo, leaving it permanently dirty and in
# conflict with the next `coder dotfiles` pull.
#
# Regenerated only when the marker is missing, so anything the template appends
# survives restarts -- the same trick the template uses for ~/.aws/config.

GITCONFIG="$HOME/.gitconfig"
MARKER="# generated by dotfiles install.sh"

if [ ! -f "$GITCONFIG" ] || ! head -1 "$GITCONFIG" | grep -qF "$MARKER"; then
  if [ -f "$GITCONFIG" ]; then
    mv "$GITCONFIG" "$(backup_path "$GITCONFIG")"
    info "backed up pre-existing ~/.gitconfig"
  fi
  cat > "$GITCONFIG" <<EOF
$MARKER -- edit shared/git/common.gitconfig instead
[include]
	path = $HOME/dotfiles/shared/git/common.gitconfig
[include]
	path = $HOME/dotfiles/headless/gitconfig
EOF
  info "generated ~/.gitconfig"
fi

# Git resolves GIT_AUTHOR_*/GIT_COMMITTER_* ahead of user.email, and the Coder
# agent exports them from the account email. ~/.zshenv covers every zsh; these
# blocks cover bash. A process spawned by the agent with no shell in between is
# a known, accepted gap -- see the spec, section 5.
BLOCK_START="# >>> dotfiles: coder git identity >>>"
BLOCK_END="# <<< dotfiles: coder git identity <<<"
for rc in "$HOME/.bashrc" "$HOME/.profile"; do
  [ -f "$rc" ] || touch "$rc"
  if ! grep -qF "$BLOCK_START" "$rc"; then
    cat >> "$rc" <<EOF

$BLOCK_START
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
$BLOCK_END
EOF
    info "added git identity block to $(basename "$rc")"
  fi
done
```

`backup_path` comes from `install.sh`, which sources this file, so it is in scope.

- [ ] **Step 4: Lint**

```bash
shellcheck -x headless/setup/45-gitconfig.sh
```
Expected: clean.

- [ ] **Step 5: Verify the aliases parse as git expects**

```bash
git config -f shared/git/common.gitconfig --get alias.lg
git config -f shared/git/common.gitconfig --get user.email
```
Expected: the full graph format string; `9834847+rgarber11@users.noreply.github.com`.

- [ ] **Step 6: Commit**

```bash
git add shared/git/ headless/gitconfig headless/setup/45-gitconfig.sh
git commit -m "feat: shared git config and generated ~/.gitconfig step"
```

---

## Task 14: Login shell and herdr on PATH

**Files:**
- Create: `headless/setup/50-shell.sh`

- [ ] **Step 1: Write the step**

```bash
# /etc/passwd comes from the image, not the PVC, so the shell change does not
# survive a restart and has to be re-applied on every start.
ZSH_PATH="$(command -v zsh || true)"
if [ -n "$ZSH_PATH" ] && [ "$(getent passwd "$USER" | cut -d: -f7)" != "$ZSH_PATH" ]; then
  info "setting login shell to $ZSH_PATH"
  sudo chsh -s "$ZSH_PATH" "$USER" || warn "chsh failed"
fi

# `herdr --remote` reaches the server over a non-interactive ssh channel that
# never sources .zshrc, so a ~/.local/bin-only install would leave
# `herdr --remote <ws>.coder` failing with "command not found".
if [ -x "$HOME/.local/bin/herdr" ] && [ ! -e /usr/local/bin/herdr ]; then
  sudo ln -sfn "$HOME/.local/bin/herdr" /usr/local/bin/herdr \
    && info "linked herdr into /usr/local/bin" \
    || warn "could not link herdr into /usr/local/bin"
fi
```

- [ ] **Step 2: Lint**

```bash
shellcheck -x headless/setup/50-shell.sh
```
Expected: clean.

- [ ] **Step 3: Run the full harness — this is the first end-to-end green**

Run: `./tests/run.sh`
Expected: `all checks passed`. In particular the restart pass must show no `downloading ...` lines and `shell=/usr/bin/zsh`.

If anything fails, fix it before committing — this is the gate the whole plan builds toward.

- [ ] **Step 4: Commit**

```bash
git add headless/setup/50-shell.sh
git commit -m "feat: login shell and herdr PATH step"
```

---

## Task 15: `--upgrade`

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Confirm the flag already threads through**

`UPGRADE` is exported by `install.sh` (Task 3) and consulted by `needs_install` (Task 7), `20-zsh-plugins.sh` (Task 9) and `40-herdr.sh` (Task 12). No new code is needed for the mechanism; verify it end to end rather than assuming.

- [ ] **Step 2: Verify upgrade actually re-resolves**

```bash
./tests/run.sh --keep
podman run --rm -v dotfiles-test-home:/home/coder -v "$PWD:/repo:ro" \
  -e CODER_AGENT_URL=http://fake.invalid dotfiles-test \
  bash -lc '~/.config/coderv2/dotfiles/install.sh --upgrade 2>&1 | tail -30'
```
Expected: the run reports `already installed` for tools at current versions and `updating`/`pulling` for the zsh plugins — not a full reinstall, and no errors.

- [ ] **Step 3: Verify the alias resolves**

```bash
podman run --rm -v dotfiles-test-home:/home/coder dotfiles-test \
  zsh -ic 'alias dotup'
```
Expected: `dotup='/home/coder/dotfiles/install.sh --upgrade'`.

- [ ] **Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: upgrade path corrections"
```
Skip this commit if steps 2 and 3 passed with no changes.

---

## Task 16: Arch profile

The desktop keeps oh-my-zsh; only the shared pieces are factored out. This task changes nothing on the running machine until `install.sh --profile arch` is run deliberately.

**Files:**
- Modify: `arch/zshrc`
- Modify: `arch/gitconfig`

- [ ] **Step 1: Rewrite `arch/zshrc` to use the shared files**

Replace the function definitions (old lines 69-178) and the option/bindkey block (old lines 28-35, 181-184) with two `source` lines, keeping everything Arch-specific. The result:

```zsh
#!/bin/zsh
# Powerlevel10k instant prompt. Keep near the top; console output goes below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
ZSH_THEME="powerlevel10k/powerlevel10k"

plugins=(git archlinux colorize common-aliases zsh-interactive-cd)
export ZSH="$HOME/.oh-my-zsh"
source $ZSH/oh-my-zsh.sh

source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme

fpath=(~/.local/share/zsh/site-functions $fpath)
zstyle :compinstall filename "$HOME/.zshrc"
autoload -Uz compinit
compinit
autoload -Uz add-zsh-hook

source "$HOME/dotfiles/shared/zsh/options.zsh"
source "$HOME/dotfiles/shared/zsh/functions.zsh"

# Pick up newly installed pacman binaries without a manual rehash.
rehash_precmd() {
  if [[ -a /var/cache/zsh/pacman ]]; then
    local paccache_time="$(date -r /var/cache/zsh/pacman +%s%N)"
    if (( zshcache_time < paccache_time )); then
      rehash
      zshcache_time="$paccache_time"
    fi
  fi
}
add-zsh-hook -Uz precmd rehash_precmd

ZSH_COLORIZE_STYLE="colorful"
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=23'
[[ "$(cat /proc/$PPID/comm)" =~ "kitty" ]] && alias ssh="kitten ssh"
export EDITOR=nvim
export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH:$HOME/Android/Sdk/platform-tools:$HOME/Android/Sdk/emulator
export ANDROID_HOME="$HOME/Android/Sdk"
export NODE_OPTIONS="--max_old_space_size=8196 --stack-trace-limit=1000"

[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

alias new_mirrorlist="reflector -n 50 -c US --delay 0.25 -f 20 --sort rate > mirrorlist.new"

monitor_app() {
  adb logcat --pid=$(adb shell pidof com.voiceerp.voiceerp)
}

gpt_code() {
  local original_kitty_colors
  original_kitty_colors=$(kitty @ get-colors) || return
  {
    kitty @ set-colors  "~/.config/kitty/kitty-themes/Catppuccin-Mocha.conf"
    kitty @ set-tab-title "GPT Code"
     env \
      CLAUDE_CONFIG_DIR="$HOME/.config/claude-other/" \
      ANTHROPIC_BASE_URL="http://127.0.0.1:8317" \
      ENABLE_CLAUDEAI_MCP_SERVERS=false \
      DISABLE_TELEMETRY=1 \
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
      ANTHROPIC_AUTH_TOKEN="${ANTHROPIC_AUTH_TOKEN:-}" \
      ANTHROPIC_DEFAULT_OPUS_MODEL="gpt-5.6-sol" \
      ANTHROPIC_DEFAULT_SONNET_MODEL="gpt-5.6-terra" \
      ANTHROPIC_DEFAULT_HAIKU_MODEL="gpt-5.6-luna" \
      claude --model gpt-5.6-sol
  } always {
    kitty @ set-colors <(print -r -- "$original_kitty_colors")
    kitty @ set-tab-title ""
  }
}

herdr_remote() {
  local original_kitty_colors
  original_kitty_colors=$(kitty @ get-colors) || return
  {
    kitty @ set-colors "~/.config/kitty/kitty-themes/Catppuccin-Mocha.conf"
    herdr --remote richard-worktree-2.coder
  } always {
    kitty @ set-colors <(print -r -- "$original_kitty_colors")
  }
}

. /usr/share/nvm/init-nvm.sh

[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

give_fortune
```

Two changes beyond the extraction: the greeting moves from line 2 to the end (it was firing before the instant-prompt block), and `gpt_code`'s token now reads from the environment so it can live in the untracked `~/.zshrc.local`.

- [ ] **Step 2: Add signing back to the Arch git config**

The Arch profile links `~/.gitconfig` straight to `arch/gitconfig` (unlike headless, which generates the file), so this one file has to pull in the shared config itself. Replace `arch/gitconfig` entirely with:

```ini
# Desktop git config. Identity, prefs and aliases live in the shared file;
# only signing and the credential helper are Arch-specific.
[include]
	path = /home/rgarber11/dotfiles/shared/git/common.gitconfig
[user]
	signingkey = /home/rgarber11/.ssh/id_rsa.pub
[commit]
	gpgsign = true
[gpg]
	format = ssh
[credential]
	helper = cache
```

The `[include]` must come first: later settings win in git, so putting it at the top lets the Arch-specific keys override the shared ones rather than the reverse.

- [ ] **Step 3: Verify the Arch zshrc parses**

```bash
zsh -n arch/zshrc && echo PARSE_OK
git config -f arch/gitconfig --get commit.gpgsign
```
Expected: `PARSE_OK`; `true`.

- [ ] **Step 4: Commit**

```bash
git add arch/
git commit -m "refactor: arch profile sources shared zsh and git config"
```

---

## Task 17: README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace the intro and add an install section**

Prepend to `README.md`, above the existing numbered list:

```markdown
# Dotfiles

Two profiles share one repo:

- **`arch/`** — the Hyprland desktop. Install with `./install.sh --profile arch`
  (always explicit, so it can never run by accident).
- **`headless/`** — Coder workspaces. Installed automatically by
  `coder dotfiles`, which runs `install.sh` on every workspace start.
- **`shared/`** — Neovim, zsh functions and options, the p10k prompt, and the
  git identity/aliases used by both.

## Coder setup

One-time, per workspace:

```
coder update <workspace> --parameter dotfiles_uri=https://github.com/rgarber11/dotfiles
```

`dotup` inside the workspace re-resolves the latest Neovim, difftastic and
fastfetch, pulls the zsh plugins, and runs `herdr update`. Nothing else touches
the network on a workspace start.

## Testing

`./tests/run.sh` runs `install.sh` in a podman container that mimics the
`dsp-base` image, using a named volume for `/home/coder` so the
persistent-`$HOME`/ephemeral-`/usr` split is reproduced faithfully.

See `docs/specs/2026-08-13-coder-dotfiles-design.md` for the full design.
```

Update item 7 of the existing list, which describes the `.zshrc` as "a mess" that "needs updating" — that is no longer accurate for either profile.

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: document profiles, coder setup, and the test harness"
```

---

## Task 18: Deploy and verify on the real workspace

The container harness cannot prove the Coder integration itself — only a real workspace can.

**Files:** none (operational)

- [ ] **Step 1: Push the branch**

```bash
git push -u origin coder-dotfiles
```

- [ ] **Step 2: Point the workspace at the branch**

`coder dotfiles` clones the default branch unless told otherwise, so test from the branch before merging:

```bash
coder update richard-worktree-2 \
  --parameter dotfiles_uri="https://github.com/rgarber11/dotfiles"
```

Then inside the workspace, to test the branch specifically before it is merged:

```bash
coder ssh richard-worktree-2 -- \
  'coder dotfiles -y --branch coder-dotfiles https://github.com/rgarber11/dotfiles'
```

- [ ] **Step 3: Run the verification table from the spec**

```bash
coder ssh richard-worktree-2 -- bash -lc '
  getent passwd coder | cut -d: -f7
  export PATH="$HOME/.local/bin:$PATH"
  nvim --version | head -1
  difft --version
  fastfetch --version | head -1
  command -v nvim difft fastfetch herdr
  git config --get alias.lg
  git var GIT_AUTHOR_IDENT
  git -C ~/.config/coderv2/dotfiles status --porcelain | wc -l
'
```

Expected: shell `/usr/bin/zsh`; nvim ≥ 0.12.4; difft ≥ 0.70.0; fastfetch ≥ 2.67.0; all four binaries under `~/.local` (herdr additionally at `/usr/local/bin`); the `lg` format string; identity `Richard Garber <9834847+rgarber11@users.noreply.github.com>`; `0` modified files in the repo.

- [ ] **Step 4: Verify the non-interactive identity path**

```bash
coder ssh richard-worktree-2 -- git var GIT_AUTHOR_IDENT
```
Expected: the noreply address. This is the check that proves `~/.zshenv` covers non-interactive shells — the whole reason it is `.zshenv` and not `.zshrc`.

- [ ] **Step 5: Verify Neovim plugin parity**

```bash
coder ssh richard-worktree-2 -- bash -lc \
  'export PATH="$HOME/.local/bin:$PATH"; nvim --headless "+Lazy! check" +qa'
coder ssh richard-worktree-2 -- bash -lc \
  'export PATH="$HOME/.local/bin:$PATH"; nvim --headless "+checkhealth image" +qa 2>&1 | grep -i magick'
```
Expected: no drift against `lazy-lock.json`; magick rock found.

- [ ] **Step 6: Restart and re-verify — the idempotence gate**

```bash
coder stop -y richard-worktree-2
coder start -y richard-worktree-2
coder ssh richard-worktree-2 -- 'tail -60 ~/startup.log'
```

Re-run steps 3 and 4. Expected: everything still passes; the start log shows apt reinstalling (expected, `/usr` is ephemeral) but **no** `downloading neovim/difftastic/fastfetch` and no `installing herdr`. Time both starts; the second must be markedly faster, or something is re-fetching that shouldn't be.

- [ ] **Step 7: Verify herdr end to end from the desktop**

```bash
herdr --remote richard-worktree-2.coder
```
Expected: connects, and the UI is catppuccin rather than solarized.

- [ ] **Step 8: Run `dotup` once**

```bash
coder ssh richard-worktree-2 -- zsh -ic 'dotup'
```
Expected: completes without error, and `~/.config/nvim` plus `lazy-lock.json` are untouched afterwards.

- [ ] **Step 9: Merge**

```bash
git checkout main
git merge --no-ff coder-dotfiles
git push origin main
```

---

## Notes and known wrinkles

- **`:Lazy update` in the workspace writes `lazy-lock.json` into the cloned repo**, leaving it dirty and liable to conflict with the next `coder dotfiles` pull. The `git status --porcelain` check in Task 18 Step 3 catches this. If it becomes a nuisance, the fix is to update plugins on the desktop and let the workspace `restore` from the committed lockfile.
- **`diff.external = difft` makes `git diff` output non-machine-readable.** This matches the desktop, so it is intentional, but any script parsing `git diff` in the workspace needs `--no-ext-diff`.
- **The identity coverage gap** (a process spawned by the Coder agent with no shell in between) is accepted, documented in spec §5, and closable later by deleting four lines from `main.tf`.
