# Preloading the spec-base local review layer — design

Date: 2026-08-14
Status: approved, not yet implemented

## Goal

Every Coder workspace comes up with the **local** spec-base review layer already
installed: the `spec-base-local` skill plus the five `/spec-base*` commands, wired
to the hosted hub on janice. That fork keeps spec-base's viewer — quote-anchored
comments, element pins on artifacts, versioned documents — but asks every human
gate as a native `AskUserQuestion` in the terminal instead of a hub-posted form.

The reason that matters is mechanical, not cosmetic: agent monitors like herdr
infer state from the session transcript, so the hub's in-flight `wait` reads as
"working" and Claude Code fires no needs-input notification. A native question is
a real needs-input state — the monitor shows blocked and the notification
arrives.

Today the layer is installed by hand, per machine, from a clone. A fresh
workspace has none of it.

## Environment (verified 2026-08-14)

| Fact | Value |
|------|-------|
| Fork | branch `rgarber/feat/local-questioning` of `PhoeniciaLabsOrg/spec-base`, pushed |
| Launcher | `packages/spec-base-local/bin/spec-base-local.mjs`, **zero dependencies** — no `npm install` to run it |
| Node needed | ≥ 22. The image ships **24** (`build/Dockerfile`, nodesource `setup_24.x`) |
| Claude Code | already global in the image (`npm i -g @anthropic-ai/claude-code`) |
| Git credentials | HTTPS only, from Coder external auth → `git-credential-store` + `gh auth login`. **There is no SSH key in a workspace** |
| Credential race | `docs/coder.md`: the dotfiles script and the main startup script "run independently, so a private repo may be cloned before `~/.git-credentials` is written" |
| Container runtime | none — the workspace is a k8s pod, no podman or docker |
| Persistence | `$HOME` is the PVC, so `~/.claude` and everything under it survives restarts; `/usr` does not |
| Hosted hub | `https://spec-base.janice.voiceerp.net`, the launcher's `DEFAULT_HOSTED_URL` |
| Template docs | `talos-home/docs/coder.md`, image `coder/templates/dsp-base/build/Dockerfile` |

Two of those facts decide the whole design. **No SSH key** means the fork's own
default clone URL (`git@github.com:…`) cannot work here, so the step clones over
HTTPS. **No container runtime** means the local hub cannot run at all, so the
layer must be pinned to hosted mode — which conveniently also makes the
launcher's `update` skip its image pull.

## Scope

Headless profile only. The arch desktop already has the layer installed by hand,
and `install.sh` runs setup steps for `headless` alone — extending them to `arch`
would mean building a setup runner for a profile that has never had one, for no
gain here.

## 1. The step

`headless/setup/99-spec-base-setup.sh`, deliberately numbered **last** — after
`50-shell.sh`. It cannot synchronise with the startup script that writes the git
credentials, but running last gives that script the longest head start within the
dotfiles run, which is the cheapest thing that improves the odds on a fresh
workspace.

Tunables at the top, so the branch is a one-line change when the fork merges to
main:

```sh
REPO="${SPEC_BASE_REPO:-https://github.com/PhoeniciaLabsOrg/spec-base.git}"
BRANCH="${SPEC_BASE_BRANCH:-rgarber/feat/local-questioning}"
ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/spec-base-local"
LAUNCHER="$ROOT/checkout/packages/spec-base-local/bin/spec-base-local.mjs"
```

`ROOT` derives from `CLAUDE_CONFIG_DIR` with the same precedence
`config.mjs:claudeDir()` uses, so the installer and the launcher can never
disagree about where things live. It is also what makes the failure-path test
below isolatable.

The step is **sourced** into `install.sh` under `set -euo pipefail`, so every
command is guarded and every failure is a `warn` that leaves the rest of the
install running. No step in this repo uses a bare `return` from a sourced file;
this one keeps to nested `if` guards for the same reason.

Flow:

1. **Node guard.** `node` on `PATH` and major ≥ 22, else `warn` and do nothing.
   The image is 24, so this only fires if the headless profile is run on a
   thinner box.
2. **Pin hosted mode.** Write `$ROOT/config.json` as `{"hub": "hosted"}` **only
   if the file is absent**. There is no container runtime in the pod, so local
   mode cannot work; but a file that already exists was written by hand, so it is
   left alone — and a `warn` if it says `local`, because that configuration
   cannot work here. Same non-clobbering ethos as `backup_path` and the
   `no-system-rc` marker.
3. **Clone if missing.** One attempt, no waiting for credentials. On failure,
   `rm -rf` the partial checkout and `warn`. Removing it is the point: the
   idempotence check in step 4 is "does the checkout exist", so a half-populated
   tree left behind would be reported as installed forever — the trap
   `install_tarball` already guards against for tarballs. Because a failed clone
   leaves nothing, the **next** workspace start retries automatically.
4. **Link.** `node "$LAUNCHER" install` — the launcher's link-only subcommand
   (`requireGit: false`, no hub needed, no network). It relinks
   `~/.claude/skills/spec-base-local` and the five `~/.claude/commands/spec-base*.md`,
   which is what makes this idempotent across restarts. Its JSON report is parsed
   with `node -e` — guaranteed present here, unlike `jq`.

   Reporting, amended after review: the steady-state boot (nothing linked, nothing
   relinked) says `spec-base: 6 links already correct`, so it reads at a glance like
   its neighbours — `nvim v0.11 already installed`, `apt: all packages present` —
   rather than three numbers the reader has to add up. A boot that changed something
   keeps the full `linked N, relinked N, already correct N`. A non-empty `conflicts`
   array becomes a `warn` **naming the paths**, not just counting them: a conflict
   means a real file is sitting where a symlink belongs, so the layer is partly
   broken, and a bare count leaves the user to go find which of six links failed.
5. **`--upgrade` only.** `node "$LAUNCHER" update --hosted --repo "$REPO" --branch "$BRANCH"`,
   which fast-forwards the fork branch, merges `origin/main` for coworkers' hub
   and viewer fixes, and relinks. Never on a normal start: that matches
   `--upgrade`'s documented "never runs automatically" and keeps ordinary boots
   off the network. `/spec-base-update` inside a session remains the other way to
   do it.

Nothing is added to `zshrc` or `zshenv`. `config.json` pins the hub for
non-interactive sessions too — `coder ssh`, agent processes — which an exported
`SPEC_BASE_LOCAL_HUB` would not reliably cover.

## 2. What lands where

```
~/.claude/spec-base-local/
├── checkout/            the managed clone (cloned once; the PVC keeps it)
├── config.json          {"hub": "hosted"}
├── data/  logs/  state.json   created by the launcher as needed
~/.claude/skills/spec-base-local     -> checkout/skills/spec-base-local
~/.claude/commands/spec-base*.md     -> checkout/commands/*.md   (5 files)
```

Six symlinks, all inside `~/.claude`. Nothing is written into any repo you work
in, and nothing in `dotfiles` is modified — `tests/run.sh` already asserts
`repo_status_delta=0`.

## 3. Tests

`tests/run.sh` runs `install.sh` in a container with **no** GitHub credentials, so
the real private clone can never be exercised there. What it can prove is that the
step's wiring is right and that its failure path is safe.

1. **Node 24 in `tests/Containerfile`** via nodesource, matching the real image.
   Noble ships 18.19, so without this the `≥ 22` guard skips the step and every
   assertion below would pass vacuously. Worth doing on its own merits: the
   harness claims to mimic the image.
2. **Happy path against a fixture.** The container builds a throwaway git repo
   holding only `packages/spec-base-local/bin/spec-base-local.mjs` — a stub that
   appends its argv to a log and prints the real launcher's JSON shape — and the
   run passes `SPEC_BASE_REPO=<that path>`. Git clones a local path with no
   credentials, so it works offline. Assert: the checkout exists with a `.git`,
   `config.json` reads `hosted`, and the stub was invoked with **`install`**, not
   `update`. This deliberately stops at our boundary; the launcher has its own
   suite in `packages/spec-base-local/test/`.

   Be honest about what that boundary costs: the suite asserts **invocation, never
   outcome**. A launcher whose `install` silently no-ops passes everything here, so
   nothing automated proves a single symlink appears — the manual `ls -l` in §3's
   checklist is the only check of that, and it must stay a named manual step rather
   than quietly reading as covered.

   The stub can emit the nested `update` report shape and rejects an unrecognised
   subcommand, so the parser's `report.install ?? report` line and our flag spelling
   are *available* to cover — but no assertion drives the `update` path yet, so today
   that branch is verified by hand (§3's manual checklist) rather than mechanically.
   The conflicts branch **is** covered, and dearly earned: it shipped uncovered for
   one round and immediately hid a real bug — `c.link` resolves to
   `String.prototype.link`, a legacy Annex B method present on every string, so the
   intended string fallback never fired and the warn printed a JS function body. The
   lesson generalises: the branches worth a fixture knob are exactly the ones that
   only run when something is already wrong.
3. **Restart path** — a new container on the same volume: no second clone, the
   stub gets `install` again, and `config.json` is not rewritten.
4. **Failure path**, the honest test of clone-once-and-warn: a run with a bogus
   `SPEC_BASE_REPO` and `CLAUDE_CONFIG_DIR=/tmp/claude-nocreds` must leave
   `install.sh` at exit 0, print a warning, and leave **no** checkout directory
   behind. That is "a fresh workspace with no credentials still boots, and the
   next start recovers" as an assertion rather than a hope.

**Manual, once, in a real workspace** — nothing in the harness can cover these:

- `node ~/.claude/spec-base-local/checkout/packages/spec-base-local/bin/spec-base-local.mjs doctor`
  reports hosted mode.
- `/spec-base` and friends appear in a fresh Claude Code session.
- `spec-base.janice.voiceerp.net` resolves and answers **from inside the pod**.
  This is the one open risk: it does not affect install, since linking is purely
  local, but it decides whether the layer works at runtime.

## 4. Docs

A paragraph under README's *Coder setup*: what lands where, that the first start
clones once and later starts only relink, that `dotup` is what merges
`origin/main`, and why hosted is the only mode available in a pod. That section
currently ends "Nothing else touches the network on a workspace start", which
this change makes false on first boot, so it gets qualified rather than left
standing.
