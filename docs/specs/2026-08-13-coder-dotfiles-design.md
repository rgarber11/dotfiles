# Coder workspace dotfiles — design

Date: 2026-08-13
Status: approved, not yet implemented

## Goal

Make `rgarber11/dotfiles` installable into a Coder workspace so that
`richard-worktree-2` (template `dsp-base`) comes up with the same Neovim, a
simplified zsh, the owner's git preferences, and herdr — themed catppuccin
rather than solarized.

## Environment (verified 2026-08-13)

| Fact | Value |
|------|-------|
| Workspace | `richard/richard-worktree-2`, template `dsp-base` |
| Image | `registry.janice.voiceerp.net/coder-dsp-base:latest`, Ubuntu 24.04 |
| User | `coder`, uid/gid 1001, NOPASSWD sudo |
| Persistent paths | **only** `/home/coder` (PVC) and `/mnt/dsp-seed` (read-only hostPath). Verified in the pod spec in `main.tf` |
| Ephemeral paths | everything else, `/usr` included — recreated from the image on **every** workspace restart |
| Present | zsh, git, node 24, ripgrep, build-essential, python3, gh, aws, gcloud, uv |
| Absent | nvim, herdr, fzf, fd, cargo, go, luarocks, imagemagick, difftastic, fastfetch |
| Template | `talos-home/coder/templates/dsp-base/main.tf` |
| Dotfiles hook | `registry.coder.com/coder/dotfiles/coder` module, mutable `dotfiles_uri` parameter, runs `coder dotfiles -y` **on every start** |
| Repo | `https://github.com/rgarber11/dotfiles`, public — no credential race on clone |

Coder runs the first executable it finds among `install.sh`, `install`,
`bootstrap.sh`, `bootstrap`, `script/bootstrap`, `setup.sh`, `setup`,
`script/setup`. Without a script it symlinks only top-level dotfiles, which
would not place `nvim/`. So `install.sh` at the repo root owns everything.

Nothing on the Arch desktop is currently symlinked — `~/.zshrc`,
`~/.config/nvim` and friends are hand-synced copies. The repo copy is the newer
one (repo `nvim/lua/plugins/ai.lua` reads `CLAUDE_CODE_OAUTH_TOKEN` from the
environment; the live copy still hardcodes it). Therefore this restructure
cannot break the running desktop, and the repo is treated as canonical.

## 1. Repository layout

```
dotfiles/
├── install.sh                 # profile-aware installer; Coder's entry point
├── profiles/
│   ├── headless.links         # "target<TAB>source" link table
│   └── arch.links
├── shared/                    # used by BOTH profiles
│   ├── nvim/                  # moved verbatim from nvim/, incl. lazy-lock.json
│   ├── git/common.gitconfig   # identity + prefs + aliases; no signing
│   ├── zsh/functions.zsh      # cgt, ffmpeg_all_info, delete_node_modules,
│   │                          #   command_stats, unzip_into, to_qr,
│   │                          #   refresh_git_branch, give_fortune
│   ├── zsh/options.zsh        # setopt / bindkey / correction common to both
│   └── zsh/p10k.zsh           # the 1834-line prompt config, newly committed
├── headless/
│   ├── zshrc
│   ├── zshenv                 # unsets the agent's GIT_AUTHOR_*/GIT_COMMITTER_*
│   ├── gitconfig              # headless-only git overrides
│   ├── herdr.toml             # complete herdr config, theme = "catppuccin"
│   └── setup/
│       ├── 10-packages.sh
│       ├── 20-zsh-plugins.sh
│       ├── 30-neovim.sh
│       ├── 35-difftastic.sh
│       ├── 37-fastfetch.sh
│       ├── 40-herdr.sh
│       └── 50-shell.sh
├── arch/                      # desktop; moved, functionally unchanged
│   ├── zshrc  gitconfig  herdr.toml     # herdr.toml keeps theme = "solarized"
│   └── hypr/ kitty/ alacritty/ anyrun/ swaync/ quickshell/ vicinae/ fontconfig/
├── editors/
│   ├── cpp/                   # clangd, .clang-format, tasks-single-file.json
│   └── js/                    # eslint.config.js, prettier.config.js
└── docs/specs/                # this file
```

Cleanup folded into the move: `herdr/herdr-client.log`, `herdr/herdr-server.log`
and `herdr/session.json` are currently tracked. Untrack them and add
`*.log`, `session.json`, `*.sock`, `.zshrc.local` to `.gitignore`.

## 2. `install.sh`

Runs on every workspace start, so every step is idempotent and cheap on the
second run.

- **Profile detection.** `$CODER_AGENT_URL` set, or `/mnt/dsp-seed` present →
  `headless`. Otherwise the script refuses and prints usage; installing the
  `arch` profile requires an explicit `--profile arch`. This prevents an
  accidental invocation from clobbering the desktop.
- **Repo location.** `coder dotfiles`' `--repo-dir` default is relative to
  Coder's *global config directory*, not `$HOME`, so the clone lands at
  `~/.config/coderv2/dotfiles` — `~/dotfiles` does not exist in the workspace.
  `install.sh` locates itself via `BASH_SOURCE` and creates a `~/dotfiles`
  symlink to its own directory. Every other file can then refer to
  `~/dotfiles/...` and be correct on both machines, matching the Arch layout
  where the repo genuinely lives there.
- **Linking.** Reads `profiles/<profile>.links`. For each pair, if the target
  is already the correct symlink it is left alone; if it is a real file or
  directory it is moved aside to `<name>.pre-dotfiles` (suffixed `.1`, `.2`, …
  if that name is taken, so a backup is never overwritten). A stale symlink is
  simply removed rather than backed up.
- **Setup steps.** Sources `headless/setup/*.sh` in numeric order. Each guards
  on a version or existence check, so a restart costs roughly two seconds.
- **`--upgrade`.** Re-resolves the latest release of every `~/.local` tool and
  reinstalls anything out of date. Never runs on workspace start; invoked by
  hand via the `dotup` alias. Also `git pull`s each zsh plugin and runs
  `herdr update`.
- `set -euo pipefail`; all output on stdout, which Coder captures into the
  workspace build log.

### Version policy

The persistent/ephemeral split above dictates where each tool comes from.

**apt is for `/usr`-resident system libraries only** — `cmake`, `fzf`,
`fd-find`, `lua5.1`, `liblua5.1-0-dev`, `luarocks`, `imagemagick`,
`libmagickwand-dev`, `python3-pip`, `fortune-mod`, `fortunes`, `cowsay`. These
are wiped and reinstalled on every start; that cost is unavoidable because they
must live in `/usr`.

**User-facing tools install into `~/.local` from upstream release archives** —
Neovim, difftastic, fastfetch (and herdr via its own installer). They persist
on the PVC, so they cost nothing on restart.

PPAs were evaluated and rejected. Because `/usr` is ephemeral, an apt-managed
package is re-downloaded on **every workspace start**, and a PPA additionally
places a third-party host on the critical path of the workspace booting. Facts
gathered 2026-08-13 against refreshed apt lists:

| Source | Finding |
|--------|---------|
| noble `neovim` | 0.9.5 — unusable; the config needs 0.11+ (`vim.uv`, `vim.lsp.enable`, treesitter `main`) |
| `ppa:neovim-ppa/stable` | abandoned: newest 0.7.2, **no noble builds at all** (focal and jammy only) |
| `ppa:neovim-ppa/unstable` | noble at `0.12.0~git202601110810` — a January nightly, *behind* 0.12.4 stable |
| `ppa:zhangsongcui3371/fastfetch` | noble at `2.67.0~noble`, genuinely current — the only good PPA of the set, still rejected for the per-start reinstall |
| noble `difftastic`, `fastfetch` | not packaged |
| noble `tree-sitter-cli` | 0.20.8, far behind current 0.25.x — use npm instead |

**No versions are pinned.** Each installer resolves the newest upstream release
at first install, because the desktop is Arch and therefore rolling — a pin
would guarantee the workspace falls behind it. Once installed, a tool is left
alone until `dotup` is run, keeping the network off the boot path entirely.

## 3. Neovim

Requirement: behave identically to the Arch machine.

- **Latest upstream stable, unpinned.** Resolve the newest `neovim/neovim`
  release tag, download the official `nvim-linux-x86_64.tar.gz` into
  `~/.local/opt/nvim-<version>`, and symlink `~/.local/bin/nvim`. Skipped
  entirely when `nvim` is already present; `dotup` re-resolves and upgrades.
  On the PVC, so it survives stops. (Desktop is at 0.12.4 as of 2026-08-13.)
- `shared/nvim` → `~/.config/nvim`. Same files, same `lazy-lock.json`.
- **Bootstrap with `nvim --headless "+Lazy! restore" +qa`**, guarded by a
  marker file. `restore` — not `sync` — installs the exact 60 plugin revisions
  recorded in the lockfile, which is what makes parity literal rather than
  approximate.
- **apt** (per the §2 version policy): `cmake`, `fd-find`, `fzf`, `lua5.1`,
  `liblua5.1-0-dev`, `luarocks`, `imagemagick`, `libmagickwand-dev`,
  `python3-pip`. Symlink `~/.local/bin/fd` → `fdfind` (Ubuntu renames the
  binary). Note noble ships ImageMagick 6, not 7; the `magick` rock binds to
  MagickWand and supports both.
- **npm**: `tree-sitter-cli` — nvim-treesitter's `main` branch needs it to build
  several parsers, and noble's `tree-sitter-cli` 0.20.8 is too old.
- **luarocks**: `luarocks --lua-version=5.1 --local install magick` (unpinned;
  desktop is at 1.6.0). `init.lua` already appends
  `~/.luarocks/share/lua/5.1` to `package.path`, so image.nvim resolves it with
  no config change.
- **Deliberately omitted**: TeX Live and a JDK. `vimtex` and `nvim-java` still
  load — both are `ft`-gated — they simply have no backend until a `.tex` or
  `.java` file is opened, which costs nothing.
- Mason installs clangd, rust_analyzer, lua_ls, texlab, eslint, stylua, ruff,
  isort, shfmt and clang-format itself; none of them need cargo or a JDK.
- **Clipboard**: the workspace has no X or Wayland display. Neovim 0.12's
  built-in OSC-52 provider carries yanks back to the local terminal.
- **Theme is the one deliberate divergence** (added 2026-08-13 after workspace
  testing): the workspace uses catppuccin mocha, the desktop keeps
  solarized-osaka. `init.lua` detects the workspace via `/mnt/dsp-seed` — a
  hostPath mount that exists only there, and so more reliable than
  `$CODER_AGENT_URL`, which depends on whatever launched nvim having inherited
  the agent's environment — with the env var as fallback.

  Both colorschemes are installed on **both** machines, gated with
  `lazy = headless` and `lazy = not headless` so only one loads. That is
  deliberate: `enabled = headless` would stop the desktop installing
  catppuccin, so the workspace would add its entry to `lazy-lock.json` at
  runtime and `30-neovim.sh` would revert it as an unwanted modification,
  losing the pin on every restart. Installing both keeps one lockfile valid for
  both profiles.
- **First-launch cost**: `Lazy! restore` clones and checks out plugins but does
  not build treesitter parsers (`:TSUpdate` is a no-op on an empty parser dir)
  or complete image.nvim's hererocks step. Both happen on the first real `nvim`
  launch, which is therefore slow.
- `keymap.lua:119` calls `hyprland-keymap-picker` inside a `pcall`, so it is
  already inert off Hyprland. No change needed.

## 4. zsh

Five plugins, installed by plain `git clone` into
`~/.local/share/zsh/plugins` (on the PVC; `20-zsh-plugins.sh` clones only what
is missing, and can `git pull` each in a loop to update).

No plugin manager. For a fixed set of five, a manager's value — resolution and
lazy-loading across a churning list — does not apply, and it would add startup
cost plus a layer of indirection. `dotup` (below) handles updates with a
`git pull` loop.

`headless/zshrc` defines **`dotup`** as `~/dotfiles/install.sh --upgrade`: the
single command that re-resolves the latest Neovim, difftastic and fastfetch,
pulls each zsh plugin, and runs `herdr update`. Nothing else ever touches the
network on a workspace start.

**Source order is load-bearing:**

```
p10k instant prompt
  → zsh-completions   (adds to fpath, must precede compinit)
  → compinit
  → powerlevel10k
  → zsh-autosuggestions
  → zsh-syntax-highlighting
  → zsh-history-substring-search   (must come after syntax-highlighting)
```

Arrow-key bindings for history-substring-search are set after it loads.

**Kept** in `headless/zshrc`: `EDITOR=nvim`; `PATH` containing `~/.local/bin`,
`~/bin` and `/usr/games` (appended — Debian/Ubuntu put `fortune` and `cowsay`
there and it is not on the default PATH, so without it `give_fortune` silently
no-ops; appended rather than prepended so nothing in `/usr/games` shadows a
real tool); `NODE_OPTIONS`; `setopt autocd extendedglob`;
`unsetopt beep nomatch notify`; `bindkey -e` plus the Alt-arrow word-motion
bindings; `ENABLE_CORRECTION` / `setopt correct` / `CORRECT_IGNORE` /
`CORRECT_IGNORE_FILE`; `ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE`; and
`source shared/zsh/functions.zsh`.

**Dropped**: oh-my-zsh and its plugin list; the pacman `rehash_precmd` hook;
`new_mirrorlist`; the `kitten ssh` alias; `ANDROID_HOME` and `monitor_app`;
nvm; `gpt_code` and `herdr_remote` (both drive kitty remote control from the
client side and are meaningless on the server).

**Two fixes carried in:**

1. The `fortune | cowsay` greeting moves to the **end** of `.zshrc`, preserving
   the desktop behaviour of greeting every interactive shell. It currently runs
   on line 2, *before* the p10k instant-prompt block — exactly the case that
   block warns about.
2. `give_fortune` gains a fallback to `fortune -a` when the `ru` database is
   absent — Ubuntu ships no Russian fortunes package.

fastfetch is **not** wired into the greeting; it is installed for manual use
only (see §6).

An untracked `~/.zshrc.local` is sourced last, as the escape hatch for
machine-local environment such as `CLAUDE_CODE_OAUTH_TOKEN`.

## 5. gitconfig

`~/.gitconfig` is a **generated real file, never a symlink.**

The template's startup script runs `git config --global credential.helper store`.
If `~/.gitconfig` were a symlink into the repo, git would write credentials into
the tracked working tree, leaving the repo permanently dirty and in conflict
with the next `coder dotfiles` pull.

Generated content:

```ini
# generated by dotfiles install.sh -- edit shared/git/common.gitconfig instead
[include]
	path = ~/dotfiles/shared/git/common.gitconfig
[include]
	path = ~/dotfiles/headless/gitconfig
```

Regenerated only when that marker line is missing, so anything the template
appends survives restarts. This mirrors the marker-line trick the template
already uses for `~/.aws/config`.

### Identity

Identity is owned by the repo, not by the workspace. `shared/git/common.gitconfig`
sets it for **both** profiles, since it is the same on each:

```ini
[user]
	name = Richard Garber
	email = 9834847+rgarber11@users.noreply.github.com
```

This displaces two wrong sources. `/mnt/dsp-seed/gitconfig` currently contains
`Matthew Hyland <matthew@voiceerp.com>`, and the startup script copies it into
`~/.gitconfig` whenever that file does not yet exist — a race the dotfiles
script can lose. Generating `~/.gitconfig` with the include block removes that
path entirely, so no seed fallback logic is needed.

### Beating the environment variables

The agent's `env` block in `main.tf` exports:

```hcl
GIT_AUTHOR_NAME     = data.coder_workspace_owner.me.full_name
GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
GIT_COMMITTER_NAME  = data.coder_workspace_owner.me.full_name
GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
```

**Git resolves these before `user.email`**, so setting the config alone does
nothing. Verified on the live workspace 2026-08-13:

```
git config --get user.email  → 9834847+rgarber11@users.noreply.github.com
git var GIT_AUTHOR_IDENT     → Richard Garber <rg.1029384756@gmail.com>
```

Every commit made in that workspace is currently authored with the Coder
account's gmail address.

Fix, entirely within the dotfiles repo:

- `headless/zshenv` → `~/.zshenv`, containing only
  `unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL`.
  `.zshenv` is sourced by *every* zsh invocation — interactive, login and
  non-interactive alike — so this covers `coder ssh <ws> <cmd>` as well as
  terminals. It must stay minimal for that reason, and must not touch
  `GIT_SSH_COMMAND` or `GIT_ASKPASS`, which Coder relies on.
- `install.sh` appends the same `unset` line to `~/.bashrc` and `~/.profile`
  inside a marked block, added only when the marker is absent so the files are
  never duplicated or clobbered.

**Known coverage gap.** A process spawned directly by the Coder agent with no
shell in between — some code-server tasks, agent auto-start — still inherits
the gmail address. Closing it completely means deleting those four lines from
`main.tf` and running `coder templates push`, which is out of scope here (see
§11). Accepted deliberately: every human shell and every agent launched from
one is covered.

`shared/git/common.gitconfig` otherwise captures the **live** desktop config,
which is ahead of the repo's stale `.gitconfig`:

- `core.autocrlf = input`
- `push.autoSetupRemote = true`
- `rerere.enabled = true`
- `diff.external = difft`
- aliases: `pushf`, `append-commit`, `force-pull`, `staash`, `lg`, `lgb`,
  `force-rebase`

**Omitted** per the requirement: `commit.gpgsign`, `gpg.format`,
`user.signingkey`. Also omitted as machine-specific: `credential.helper`
(the template sets `store`), `maintenance.repo`, and the git-lfs filters.

## 6. difftastic and fastfetch

Neither is packaged for noble. Both follow the §2 policy: newest upstream
release, unpinned, into `~/.local`.

**difftastic** — `35-difftastic.sh` resolves the latest `Wilfred/difftastic`
release and installs `difft-x86_64-unknown-linux-gnu.tar.gz` to
`~/.local/bin/difft`. Skipped when `difft` is already present. Desktop is at
0.70.0.

Its own step rather than part of the Neovim step, because
`diff.external = difft` in `common.gitconfig` depends on it — a missing binary
would break every `git diff` in the workspace.

**fastfetch** — `37-fastfetch.sh` resolves the latest
`fastfetch-cli/fastfetch` release and extracts
`fastfetch-linux-amd64.tar.gz` to `~/.local/opt/fastfetch-<version>`, symlinked
at `~/.local/bin/fastfetch`. Desktop is at 2.67.0.

Explicitly **not** the `.deb` and **not** the PPA. `dpkg` and apt both install
into `/usr`, which is ephemeral, so either would be discarded and reinstalled
on every workspace start. The tarball lands on the PVC and installs once.

Use the plain build; the `-polyfilled` variant exists for glibc older than this
image's 2.39.

No config to sync — there is no `~/.config/fastfetch` on the desktop, so the
workspace uses the stock preset. Not run automatically from any rc file; it is
installed for manual invocation only.

## 7. herdr

- **Install**: `curl -fsSL https://herdr.dev/install.sh | sh`, which places the
  binary in `~/.local/bin`. Skipped when already present; `herdr update`
  handles later upgrades.
- **Config**: `~/.config/herdr/config.toml` → `headless/herdr.toml`. TOML has no
  include mechanism, so `arch/herdr.toml` and `headless/herdr.toml` are two
  complete 14-line files differing only in `[theme] name`; there is no shared
  base fragment to merge. Current settings verbatim — `onboarding = false`,
  `ui.toast.delivery = "system"`,
  `ui.show_agent_labels_on_pane_borders = true`,
  `ui.agent_panel_sort = "spaces"`, `experimental.kitty_graphics = true` — with
  `[theme] name = "catppuccin"`. Verified against the 0.8.0 binary that
  `catppuccin` is the exact built-in name; `catppuccin-latte` is the light
  variant, available if `auto_switch` is ever enabled.
- **`sudo ln -sf` into `/usr/local/bin`.** `herdr --remote` reaches the server
  over a non-interactive ssh channel that never sources `.zshrc`; a
  `~/.local/bin`-only install would leave
  `herdr --remote richard-worktree-2.coder` failing with "command not found".

## 8. Login shell

`50-shell.sh` runs `sudo chsh -s "$(command -v zsh)" coder` on **every** start —
`/etc/passwd` comes from the image, not the PVC, so the change does not persist
across restarts. This covers `coder ssh`, the web terminal, and code-server's
integrated terminal.

## 9. Wiring

The template already carries the dotfiles module; no `main.tf` change and no
`templates push` are required. One-time, per workspace:

```
coder update richard-worktree-2 \
  --parameter dotfiles_uri=https://github.com/rgarber11/dotfiles
```

The parameter is mutable and carries forward across builds.

## 10. Verification

Over `coder ssh richard-worktree-2`:

| Check | Expected |
|-------|----------|
| `getent passwd coder` | shell is `/usr/bin/zsh` |
| `nvim --version` | latest upstream stable (≥ 0.12.4) |
| `nvim --headless "+Lazy! check" +qa` | no drift against `lazy-lock.json` |
| `nvim --headless "+checkhealth image" +qa` | magick rock found |
| `command -v herdr` in a non-interactive shell | resolves via `/usr/local/bin` |
| `difft --version` | latest upstream (≥ 0.70.0) |
| `fastfetch --version` | latest upstream (≥ 2.67.0) |
| `command -v nvim difft fastfetch` | all under `~/.local`, none under `/usr` |
| open an interactive session | cowsay greeting appears, no p10k instant-prompt warning |
| `git config --get alias.lg` | returns the graph format |
| `git var GIT_AUTHOR_IDENT` | `Richard Garber <9834847+rgarber11@users.noreply.github.com>` |
| `coder ssh richard-worktree-2 -- git var GIT_AUTHOR_IDENT` | same — proves `.zshenv` covers non-interactive shells |
| `git -C ~/dotfiles status --short` | clean (proves nothing wrote into the repo) |

Then, from the desktop: `herdr --remote richard-worktree-2.coder` connects.

Finally, stop and restart the workspace once and re-run the table — this is the
only way to prove the idempotence and the `chsh`/gitconfig-marker behavior.
The restart is also what proves the version policy: `nvim`, `difft` and
`fastfetch` must still be present with **no** re-download in the start log,
while the apt packages are expected to reinstall. Time the second start; if it
is not markedly faster than the first, something is re-fetching that shouldn't.

Separately, run `dotup` once and confirm it upgrades in place without
disturbing `~/.config/nvim` or the plugin lockfile.

## 11. Out of scope

- TeX Live and JDK toolchains.
- Any change to the Arch WM configs beyond relocating them.
- Any git history rewrite. The committed `ANTHROPIC_AUTH_TOKEN` in the current
  `.zshrc` is a placeholder, not a live credential; `gpt_code` does not exist in
  the headless profile regardless.
- Changes to `talos-home`. Noted as the one outstanding follow-up: deleting the
  four `GIT_AUTHOR_*` / `GIT_COMMITTER_*` lines from the `coder_agent.main` env
  block in `coder/templates/dsp-base/main.tf` (then `coder templates push`)
  would close the identity coverage gap in §5 completely, and would let the
  `~/.zshenv` unset go away. Decided against for now to keep this change inside
  the dotfiles repo.
