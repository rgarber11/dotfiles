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

`dotup` inside the workspace re-resolves the latest Neovim, difftastic,
fastfetch and chafa, pulls the zsh plugins, runs `herdr update`, and updates
spec-base (see below). Every start otherwise touches the network only for apt
to top up whatever `/usr` lost on restart, and for the spec-base clone below
until it succeeds once.

The `dsp-base` image ships a zsh setup of its own — powerlevel10k, the same five
plugins, and copies of `shared/zsh/{options,functions}.zsh` — sourced from
`/etc/zsh/zshrc`, so before `~/.zshrc`. `headless/setup/05-system-zsh.sh` drops
`~/.config/zsh/no-system-rc`, which makes it stand down and leaves this profile
in sole charge; without it every plugin would load twice. The profile stays
self-sufficient rather than layering onto the image's config, so `install.sh`
still produces a working shell on a plain Ubuntu box — the steps the image has
made redundant (terminfo, chafa, fastfetch, most of the apt packages, `chsh`)
all guard on the tool being absent and simply go quiet there.

`headless/setup/99-spec-base-setup.sh` preloads the spec-base local review
layer — six symlinks in total: `~/.claude/skills/spec-base-local` plus five
`/spec-base*` commands — out of a managed clone at
`~/.claude/spec-base-local/checkout`. That clone happens once — `$HOME` is the
PVC — and later starts only re-link, which needs no network. It is pinned to
the hosted hub on janice (`config.json`, written only if absent) because a
workspace is a k8s pod with no podman or docker, so the local hub cannot run
there.

The clone gets one attempt and does not wait, which is why the step is
numbered last: git credentials come from Coder's external auth via an
independent startup script, so running last gives that script the longest head
start. The step also needs node 22+, which the image has and noble does not, and
warns rather than installing one. It clones into a staging directory and moves that into place
only on success: the only installed-check is whether the checkout path
exists, so a half-built tree there would read as installed forever. A failed
or interrupted clone just warns, and the next start retries. `dotup` (or
`/spec-base-update` in a session) fast-forwards the branch and merges
`origin/main`, keeping the launcher, skill and commands current; a normal
start never does.

## Testing

`./tests/run.sh` runs `install.sh` in a podman container that mimics the
`dsp-base` image *before* the shell config was baked into it, using a named
volume for `/home/coder` so the persistent-`$HOME`/ephemeral-`/usr` split is
reproduced faithfully. That the opt-out marker actually suppresses the image's
config is verified against the real image, which the harness does not pull.

See `docs/specs/2026-08-13-coder-dotfiles-design.md` for the full design.

All of my dotfiles

1. **Neovim**: My config is based on an old version of [Kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim). However, it has been thoroughly changed, and now doesn't really resemble its ancestor. Quite maximalist, so is very batteries included.
2. **Hyprland**: My current WM. Relies on [Hyprnvidia](https://github.com/rgarber11/small_scripts/tree/master/hyprnvidia) for Optimus, and calls into scripts in the [nwg_panel folder](nwg-panel/executors/keyboard_layout.py). Also uses `nwg-panel`, `nwg-dock-hyprland`, `anyrun`, `hypridle`, `hyprlock`, etc. Beyond that, I think these are some pretty sane defaults.
3. **Nwg-Panel**: Custom executors for switching Hyprland Keyboard Layouts, night-light and icons for numlock and capslock. Solarized Tray menu, but not the panel itself, since it looks wrong then to me. Requires [`hyprsunset`](https://github.com/hyprwm/hyprsunset) for night color.  
   _Note:_ I have an executor for when CapsLock is _on_, and one for when Numlock is _off_. Sue me.
4. **NWG-Dock-Hyprland**, **Anyrun**: Mostly cosmetic changes to make them _solarized_
5. **Kitty** is my current terminal. I have not changed much, aside from using a solarized theme.
6. **Alacritty** is my backup terminal. All I've done is changed themes.
7. **Zsh**: Shared options and functions (including the cowsay fortune greeting, with a proper split on English and Russian fortunes — note: the in-built `fortune -n 30% a -n 70% b` did not work for me) live in `shared/zsh/` and get sourced by both profiles. `arch/zshrc` is still oh-my-zsh-based, plugins and all. `headless/zshrc` is oh-my-zsh-free: it git-clones five plain plugins (powerlevel10k, zsh-autosuggestions, zsh-syntax-highlighting, zsh-history-substring-search, zsh-completions) straight from upstream instead.
8. **Komorebi**: ~~My preferred tiling window manager for Windows. My dislike for gaps is on display here as well. The rest is mostly default config (I might want to change the shortcuts to match Hyprland at some point). `applications.yaml` contains my attempt at managing Mullvad VPN, which at this point is a failure (so not upstream).~~ (Deprecated due to license change: Currently switched to [Whim](https://github.com/dalyIsaac/Whim))
9. **SwayNC**: Simple Notification Center and Daemon. I did my best to solarize it.
