# spec-base Preload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every Coder workspace comes up with the spec-base local review layer already linked into `~/.claude` and pinned to the hosted hub on janice.

**Architecture:** One new sourced setup step, `headless/setup/99-spec-base-setup.sh`, numbered last so the git credential store has the longest head start. It clones the fork over HTTPS once into `~/.claude/spec-base-local/checkout` (the PVC keeps it), writes `config.json` with `{"hub":"hosted"}`, then calls the launcher's offline link-only `install` subcommand on every start. The networked `update` runs only under `--upgrade`. Every command is guarded: a failure warns and the rest of the install continues.

**Tech Stack:** bash (sourced under `set -euo pipefail`), the zero-dependency Node launcher at `packages/spec-base-local/bin/spec-base-local.mjs`, the podman container harness in `tests/`.

**Spec:** `docs/specs/2026-08-14-spec-base-preload-design.md`

---

## File Structure

| File | Responsibility |
|------|----------------|
| Create: `headless/setup/99-spec-base-setup.sh` | The whole feature: node guard, hosted pin, clone-once, link. Sourced last by `install.sh`. |
| Modify: `tests/Containerfile` | Node 24 from nodesource, matching the real image. Without it the `≥ 22` guard skips the step and every new assertion passes vacuously. |
| Modify: `tests/run.sh` | A fixture repo + stub launcher, the happy/restart assertions, and a third `install.sh` run that proves the no-credentials path is safe. |
| Modify: `README.md` | A paragraph under *Coder setup*, and a qualification of the "nothing else touches the network" claim. |
| Modify: `docs/specs/2026-08-14-spec-base-preload-design.md` | Status line, once it is implemented. |

Two JSON shapes matter, both verified in `packages/spec-base-local/`:

- `install` (`cmdInstall`) prints `{checkout, linked, relinked, alreadyCorrect, conflicts}` — **top level**.
- `update` (`cmdUpdate`) prints `{checkout, cloned?, ownBranch, upstream, merge, install: {…}}` — **nested**.

So the parser reads `report.install ?? report`.

**Not covered by the harness:** the `--upgrade` branch. Exercising it means running
`install.sh --upgrade`, which re-resolves the latest GitHub release of every tool
in the profile and runs `herdr update` — unauthenticated API calls that make the
run slow and rate-limit flaky, which is why nothing in `tests/` covers `--upgrade`
today. Task 6 verifies that branch by hand instead.

---

### Task 1: Node 24 in the test container

The harness claims to mimic the `dsp-base` image, which runs nodesource Node 24. Noble's `nodejs` package is 18.19, below the launcher's floor — so this has to land before any other test can mean anything.

**Files:**
- Modify: `tests/Containerfile:3-9`

- [ ] **Step 1: Show the current version is too old**

Run:
```bash
podman build -q -t dotfiles-test -f tests/Containerfile tests
podman run --rm dotfiles-test node --version
```
Expected: `v18.19.x` — below 22, which is why the step under test would skip itself.

- [ ] **Step 2: Replace the apt node with nodesource 24**

In `tests/Containerfile`, drop `nodejs npm` from the apt list and add a nodesource layer after it. The apt list line becomes:

```dockerfile
      openssh-client gnupg2 zsh \
```

and immediately after that `RUN` block (before `ARG USER=coder`) add:

```dockerfile
# Node 24 from nodesource, matching coder-dsp-base. Noble's nodejs is 18.19,
# below the 22 floor the spec-base launcher needs -- with the apt version the
# setup step would skip itself and every spec-base assertion below would pass
# without testing anything.
RUN curl -fsSL --max-time 120 https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && node --version | grep -q '^v24\.'
```

The trailing `grep` is not decoration. `curl | bash` under `/bin/sh -c` discards
curl's exit status, and there is a real window — a body truncated after the
vendor script's `install_pre_reqs` (which repopulates the apt lists) but before
`configure_repo` (which writes the nodesource source) — where `apt-get install
nodejs` quietly installs noble's 18.19 and the **build succeeds**. Verified by
building that exact case: unguarded it ships `v18.19.1`, guarded the build exits
1. `--max-time 120` matches the precedent in `headless/setup/40-herdr.sh:12`.

- [ ] **Step 2b: Assert the version in the harness too**

The build guard cannot catch a `~/.local/bin/node` shadowing the image's node, or
someone deleting the guard. Mirror what this repo already does for noble's chafa
1.14 (`tests/run.sh:92-95`, commit 68d7e2c): assert the *version*, not the
presence, when a distro version is the hazard. In the `CHECKS` heredoc add

```bash
echo "node=$(node --version)"
```

and with the other first-install assertions:

```bash
assert_contains "node is nodesource 24, not noble's 18.19" "node=v24." "$CHECKS"
```

That probe sits after the heredoc's `export PATH="$HOME/.local/bin:$PATH"`, so it
asserts the node the setup steps actually resolve rather than only what the image
shipped.

- [ ] **Step 2c: Fix the comment this change falsifies**

`headless/setup/10-packages.sh:46` says npm's default prefix is the root-owned
`/usr/local`. Under nodesource the prefix derives from node's location and is
`/usr` — confirm with `podman run --rm dotfiles-test npm config get prefix`, then
correct the path only. The surrounding reasoning and its conclusion (`--prefix
~/.local` is still right, because both are root-owned and both sit on ephemeral
`/usr`) stand unchanged.

- [ ] **Step 3: Verify**

Run:
```bash
podman build -q -t dotfiles-test -f tests/Containerfile tests
podman run --rm dotfiles-test node --version
```
Expected: `v24.` prefix.

- [ ] **Step 4: Confirm nothing else broke**

Run: `./tests/run.sh`
Expected: `all checks passed`. (`10-packages.sh` uses `npm install -g --prefix ~/.local`; nodesource ships npm, so `tree-sitter` still installs.)

- [ ] **Step 5: Commit**

```bash
git add tests/Containerfile
git commit -m "test: node 24 in the harness, matching the workspace image"
```

---

### Task 2: The step survives a repo it cannot reach

Failure first, because it is the risk the design accepts: the clone gets one attempt and no wait, so the common case on a fresh workspace is a credential that has not been written yet. A workspace must still boot.

**Files:**
- Modify: `tests/run.sh` (new `nocreds_run` function + assertions, before `summary`)
- Create: `headless/setup/99-spec-base-setup.sh`

- [ ] **Step 1: Write the failing test**

In `tests/run.sh`, add this function directly after `install_run()`:

```bash
# A third install run, isolated by CLAUDE_CONFIG_DIR, with a repo that cannot
# exist. This is the harness's only way to reproduce a fresh workspace whose git
# credentials are not written yet: the clone must fail, warn, and leave nothing
# behind -- and install.sh must still finish, or a boot with no credentials would
# leave the workspace with no shell.
nocreds_run() {
  in_workspace <<'SH'
set -e
export CLAUDE_CONFIG_DIR=/tmp/claude-nocreds
export SPEC_BASE_REPO=/nonexistent/spec-base.git
export SPEC_BASE_BRANCH=main
~/.config/coderv2/dotfiles/install.sh
echo "nocreds_checkout=$([ -d /tmp/claude-nocreds/spec-base-local/checkout ] && echo present || echo absent)"
SH
}
```

And immediately before the final `summary` call:

```bash
echo
echo "=== third install (unreachable spec-base repo, isolated claude dir) ==="
NOCREDS="$(nocreds_run 2>&1)" || { echo "$NOCREDS"; echo "install failed without spec-base credentials"; exit 1; }
echo "$NOCREDS" | tail -20

assert_contains "install.sh finishes when the spec-base repo is unreachable" \
  "==> dotfiles: done" "$NOCREDS"
assert_contains "an unreachable spec-base repo warns instead of aborting" \
  "spec-base: clone failed" "$NOCREDS"
# A partial checkout would satisfy the "does it exist" idempotence check forever,
# so a failed clone must leave the directory absent, not merely broken.
assert_contains "a failed clone leaves no checkout behind" \
  "nocreds_checkout=absent" "$NOCREDS"
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `./tests/run.sh`
Expected: the first assertion passes (nothing runs yet, so `install.sh` finishes), and these two FAIL:
```
  FAIL an unreachable spec-base repo warns instead of aborting (missing: spec-base: clone failed)
```

- [ ] **Step 3: Write the step — guard, hosted pin, clone**

Create `headless/setup/99-spec-base-setup.sh`:

```bash
#!/usr/bin/env bash
# The spec-base local review layer: the spec-base-local skill plus five
# /spec-base* commands, symlinked into ~/.claude. It is a fork branch that asks
# every human gate as a native Claude Code question instead of a hub-posted form,
# which is what makes an agent monitor see a blocked session and notify.
#
# HTTPS, not the fork's default git@github.com: URL -- a workspace has no SSH key,
# only the HTTPS credentials Coder's external auth writes into
# git-credential-store. This step is numbered last because it cannot synchronise
# with the startup script that writes them: running last is simply the longest
# head start available inside a dotfiles run.
#
# Hosted mode is pinned because the workspace is a k8s pod with no podman or
# docker, so the local hub cannot run at all. It also keeps the launcher's update
# away from the container image entirely.

SPEC_BASE_REPO="${SPEC_BASE_REPO:-https://github.com/PhoeniciaLabsOrg/spec-base.git}"
SPEC_BASE_BRANCH="${SPEC_BASE_BRANCH:-rgarber/feat/local-questioning}"
# Same precedence as the launcher's own claudeDir(), so the installer and the
# launcher can never disagree about where any of this lives.
spec_base_root="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/spec-base-local"
spec_base_checkout="$spec_base_root/checkout"
spec_base_launcher="$spec_base_checkout/packages/spec-base-local/bin/spec-base-local.mjs"

# The launcher has zero dependencies but needs node 22+; the image ships 24.
spec_base_node=0
if command -v node >/dev/null 2>&1; then
  spec_base_major="$(node --version)"          # v24.5.0
  spec_base_major="${spec_base_major#v}"
  spec_base_major="${spec_base_major%%.*}"
  case "$spec_base_major" in
    ''|*[!0-9]*) ;;
    *) [ "$spec_base_major" -ge 22 ] && spec_base_node=1 ;;
  esac
fi

if [ "$spec_base_node" != 1 ]; then
  warn "spec-base: node 22+ not found; skipping the local review layer"
else
  mkdir -p "$spec_base_root"

  # Written only when absent: a file that already exists was written by hand, and
  # silently overwriting a deliberate choice is worse than saying it cannot work.
  if [ ! -e "$spec_base_root/config.json" ]; then
    printf '{\n  "hub": "hosted"\n}\n' > "$spec_base_root/config.json"
    info "spec-base: pinned the hosted hub"
  elif grep -q '"local"' "$spec_base_root/config.json" 2>/dev/null; then
    warn "spec-base: config.json asks for the local hub, which needs podman or docker"
  fi

  if [ ! -d "$spec_base_checkout/.git" ]; then
    info "spec-base: cloning $SPEC_BASE_BRANCH"
    # One attempt, no waiting for credentials. On failure this leaves NOTHING
    # behind: the existence of the checkout is the idempotence check below, so a
    # half-populated tree would read as installed forever (the same trap
    # install_tarball guards against). Leaving nothing means the next workspace
    # start retries by itself.
    if ! git clone --quiet --branch "$SPEC_BASE_BRANCH" "$SPEC_BASE_REPO" "$spec_base_checkout"; then
      rm -rf "$spec_base_checkout"
      warn "spec-base: clone failed (git credentials not written yet?); retrying next start"
    fi
  fi
fi
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./tests/run.sh`
Expected: `all checks passed`, including
```
  ok   an unreachable spec-base repo warns instead of aborting
  ok   a failed clone leaves no checkout behind
```

- [ ] **Step 5: Commit**

```bash
git add headless/setup/99-spec-base-setup.sh tests/run.sh
git commit -m "feat: clone the spec-base review layer, pinned to the hosted hub"
```

---

### Task 3: Linking, proven against a fixture

The private fork cannot be cloned from the harness, so the test stands in a local git repo holding a stub launcher. That is the right boundary: this proves *our* wiring — which subcommand runs, with what environment — while the launcher's own behaviour is covered by `packages/spec-base-local/test/`.

**Files:**
- Modify: `tests/run.sh` (fixture inside `install_run`, assertions in the `CHECKS` block)
- Modify: `headless/setup/99-spec-base-setup.sh` (append the link block)

- [ ] **Step 1: Write the failing test — fixture and assertions**

In `tests/run.sh`, inside `install_run()`'s heredoc, insert this **before** the `REPO_STATUS_BEFORE=` line:

```bash
# The real spec-base repo is private and this container has no credentials, so
# the setup step is pointed at a local git repo instead. Cloning a path needs no
# credentials. It holds only a stub launcher that logs its argv and prints the
# real launcher's JSON shape, which is exactly the seam worth testing here: which
# subcommand the step chooses. The launcher itself has its own test suite.
FIXTURE=~/.cache/spec-base-fixture
if [ ! -d "$FIXTURE/.git" ]; then
  mkdir -p "$FIXTURE/packages/spec-base-local/bin"
  cat > "$FIXTURE/packages/spec-base-local/bin/spec-base-local.mjs" <<'STUB'
#!/usr/bin/env node
import { appendFileSync } from 'node:fs';
appendFileSync(`${process.env.HOME}/spec-base-stub.log`, `${process.argv.slice(2).join(' ')}\n`);
// cmdInstall spreads install()'s fields at the top level; cmdUpdate nests them
// under "install". This mimics the install shape, which is what a normal start
// invokes.
console.log(
  JSON.stringify({
    checkout: 'stub',
    linked: ['skills/spec-base-local'],
    relinked: [],
    alreadyCorrect: [],
    conflicts: [],
  }),
);
STUB
  git -C "$FIXTURE" init -q -b main
  git -C "$FIXTURE" add -A
  git -C "$FIXTURE" -c user.email=t@example.com -c user.name=T commit -qm fixture
fi
export SPEC_BASE_REPO="$FIXTURE"
export SPEC_BASE_BRANCH=main
```

Then in the `CHECKS` heredoc (the fresh-container assertions after the first install), add:

```bash
echo "spec_checkout=$([ -d ~/.claude/spec-base-local/checkout/.git ] && echo present || echo absent)"
echo "spec_hub=$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.env.HOME + "/.claude/spec-base-local/config.json", "utf8")).hub)' 2>/dev/null || echo none)"
# The last line, not the whole file: the log persists on the volume across runs.
echo "spec_argv=$(tail -1 ~/spec-base-stub.log 2>/dev/null)"
```

and after the existing `assert_*` calls for the first install:

```bash
assert_contains "the spec-base checkout is cloned" "spec_checkout=present" "$CHECKS"
assert_contains "the hub is pinned to hosted" "spec_hub=hosted" "$CHECKS"
# A normal start must never run the networked update: it fetches and merges
# origin/main, which is upgrade-only work in this repo.
assert_contains "a normal start links only" "spec_argv=install" "$CHECKS"
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `./tests/run.sh`
Expected: the clone and hub assertions pass (Task 2 built those), and this FAILS because nothing invokes the launcher yet:
```
  FAIL a normal start links only (missing: spec_argv=install)
```

- [ ] **Step 3: Append the link block to the step**

At the end of `headless/setup/99-spec-base-setup.sh`, inside the existing `else` branch (after the clone block), add:

```bash
  if [ ! -f "$spec_base_launcher" ]; then
    : # the clone above already warned; nothing to link
  else
    # `install` is link-only: no network, no git repo, no hub. `update` also
    # fast-forwards this branch and merges origin/main, so it is upgrade-only --
    # the rule every other step in this profile follows. /spec-base-update inside
    # a session is the other way to get it.
    if [ "${UPGRADE:-0}" = 1 ]; then
      spec_base_cmd=(update --hosted --repo "$SPEC_BASE_REPO" --branch "$SPEC_BASE_BRANCH")
    else
      spec_base_cmd=(install)
    fi
    if spec_base_report="$(node "$spec_base_launcher" "${spec_base_cmd[@]}")"; then
      # node -e and not jq: node is a hard requirement two lines up, jq is not
      # guaranteed anywhere. `install` spreads its counts at the top level while
      # `update` nests them under "install", so accept either.
      spec_base_counts="$(node -e '
        const r = JSON.parse(require("fs").readFileSync(0, "utf8"));
        const i = r.install ?? r;
        const n = (a) => (a ?? []).length;
        console.log(`${n(i.linked)} ${n(i.relinked)} ${n(i.alreadyCorrect)} ${n(i.conflicts)}`);
      ' <<<"$spec_base_report" 2>/dev/null)" || spec_base_counts=""
      if [ -n "$spec_base_counts" ]; then
        read -r spec_base_new spec_base_re spec_base_ok spec_base_bad <<<"$spec_base_counts"
        info "spec-base: linked $spec_base_new, relinked $spec_base_re, already correct $spec_base_ok"
        [ "$spec_base_bad" = 0 ] ||
          warn "spec-base: $spec_base_bad link(s) skipped; something in ~/.claude is not a symlink"
      else
        info "spec-base: ${spec_base_cmd[0]} finished"
      fi
    else
      warn "spec-base: ${spec_base_cmd[0]} failed; run /spec-base-update in a session"
    fi
  fi
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./tests/run.sh`
Expected: `all checks passed`, and the first-install output contains
```
    spec-base: linked 1, relinked 0, already correct 0
```

- [ ] **Step 5: Commit**

```bash
git add headless/setup/99-spec-base-setup.sh tests/run.sh
git commit -m "feat: link the spec-base skill and commands on every start"
```

---

### Task 4: The restart path

`$HOME` is a PVC, so the second start must not re-clone and must not rewrite a `config.json` that is already there. This is the behaviour that keeps a workspace boot off the network.

**Files:**
- Modify: `tests/run.sh` (the `AFTER` block and its assertions)

- [ ] **Step 1: Write the test**

In the `AFTER` heredoc (the post-restart assertions), add:

```bash
echo "spec_argv=$(tail -1 ~/spec-base-stub.log 2>/dev/null)"
echo "spec_clones=$(grep -c '^' ~/spec-base-stub.log 2>/dev/null || echo 0)"
echo "spec_hub=$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.env.HOME + "/.claude/spec-base-local/config.json", "utf8")).hub)' 2>/dev/null || echo none)"
```

and after the existing restart assertions:

```bash
assert_not_contains "the spec-base checkout is not re-cloned" "spec-base: cloning" "$SECOND"
assert_contains "the restart re-links" "spec_argv=install" "$AFTER"
# One line per install.sh run: two runs, two invocations, no extra work.
assert_contains "the launcher ran once per start" "spec_clones=2" "$AFTER"
assert_contains "the hosted pin survives the restart" "spec_hub=hosted" "$AFTER"
```

- [ ] **Step 2: Run the tests**

Run: `./tests/run.sh`
Expected: `all checks passed`. These are regression guards over behaviour Tasks 2 and 3 already built — if `spec_clones=2` fails with a higher number, something is invoking the launcher more than once per start.

- [ ] **Step 3: Commit**

```bash
git add tests/run.sh
git commit -m "test: assert the spec-base layer survives a restart without re-cloning"
```

---

### Task 5: Docs

**Files:**
- Modify: `README.md:12-33` (the *Coder setup* section)
- Modify: `docs/specs/2026-08-14-spec-base-preload-design.md:4`

- [ ] **Step 1: Qualify the network claim**

In `README.md`, the *Coder setup* section currently ends its `dotup` paragraph with "Nothing else touches the network on a workspace start." Replace that sentence with:

```markdown
Nothing else touches the network on a workspace start, except the one-time
spec-base clone below.
```

- [ ] **Step 2: Add the spec-base paragraph**

Append to the *Coder setup* section, after the `dsp-base` zsh paragraph:

```markdown
`headless/setup/99-spec-base-setup.sh` preloads the spec-base local review
layer: `~/.claude/skills/spec-base-local` plus five `/spec-base*` commands,
symlinked out of a managed clone at `~/.claude/spec-base-local/checkout`. That
clone happens once — `$HOME` is the PVC — and later starts only re-link, which
needs no network. It is pinned to the hosted hub on janice
(`config.json`, written only if absent) because a workspace is a k8s pod with no
podman or docker, so the local hub cannot run there.

The clone gets one attempt and does not wait, which is why the step is numbered
last: the git credentials come from Coder's external auth via a startup script
that runs independently of this one. If they are not written yet the clone
fails, warns, leaves nothing behind, and the next workspace start picks it up.
`dotup` (or `/spec-base-update` inside a session) is what fast-forwards the
branch and merges `origin/main` for coworkers' viewer fixes; a normal start
never does.
```

- [ ] **Step 3: Flip the spec status**

In `docs/specs/2026-08-14-spec-base-preload-design.md`, change line 4:

```markdown
Status: implemented 2026-08-14
```

- [ ] **Step 4: Commit**

```bash
git add README.md docs/specs/2026-08-14-spec-base-preload-design.md
git commit -m "docs: record the preloaded spec-base review layer"
```

---

### Task 6: Verification

- [ ] **Step 1: Full harness, from a clean volume**

Run: `./tests/run.sh`
Expected: `all checks passed`, with no `FAIL` lines anywhere in the output.

- [ ] **Step 2: Lint the new step**

Run: `shellcheck -x -s bash headless/setup/99-spec-base-setup.sh`
Expected: no output. The file is sourced, so `info`/`warn`/`UPGRADE` come from `headless/setup/lib.sh`; if shellcheck reports them undefined, add `# shellcheck source=headless/setup/lib.sh` above a `source` guard comment rather than disabling the check. If `shellcheck` is not installed, say so instead of skipping silently.

- [ ] **Step 3: Confirm the dotfiles clone stays clean**

Run: `git status --porcelain`
Expected: empty. Everything is committed, and `tests/run.sh` already asserts `repo_status_delta=0` inside the container.

- [ ] **Step 4: Manual verification in a real workspace** (cannot be containerised — report the actual output, do not assume)

```bash
# in a fresh workspace, after a start
node ~/.claude/spec-base-local/checkout/packages/spec-base-local/bin/spec-base-local.mjs doctor
```
Expected: hub mode `hosted`.

```bash
ls -l ~/.claude/skills/spec-base-local ~/.claude/commands/spec-base*.md
```
Expected: six symlinks into `~/.claude/spec-base-local/checkout`.

- [ ] **Step 5: Manual verification of the upgrade branch** (the gap the harness leaves)

Run, in a real workspace:
```bash
UPGRADE=1 bash -c '
  set -euo pipefail
  source ~/dotfiles/headless/setup/lib.sh
  source ~/dotfiles/headless/setup/99-spec-base-setup.sh
'
```
Expected: `spec-base: linked 0, relinked 0, already correct 6` and no warning. This
sources only the one step, so it exercises the `update --hosted` path without
re-resolving every other tool's release. It does fetch and merge `origin/main`, so
expect it to take a few seconds.

Then start a Claude Code session and confirm `/spec-base` is listed, and check the one open risk from the spec — that the pod can reach the hub:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://spec-base.janice.voiceerp.net/
```
Expected: a 2xx or 3xx. A DNS failure here does not affect the install (linking is local) but means the layer cannot work at runtime, and is worth reporting back rather than treating as done.
