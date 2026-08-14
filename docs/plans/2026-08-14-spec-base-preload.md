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
Expected: exactly one FAIL, and `1 check(s) failed`:
```
  FAIL an unreachable spec-base repo warns instead of aborting (missing: spec-base: clone failed)
```
The other two pass trivially at this point — with no step file, `install.sh` finishes
and nothing ever creates a checkout. Only the warn assertion can go red, and that
is the red run to look for.

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

#### Shipped: review-driven deviations from the code above

Code review found four Important defects in the prescribed text above and one
regression in the first fix for them. **`headless/setup/99-spec-base-setup.sh` as
committed is the source of truth**, not the block above; these are the deltas and
why each was necessary. Anyone re-deriving this work should write the shipped
shape, not the original.

1. **`spec_base_major="$(node --version)"` could abort the whole install.** A bare
   assignment from a command substitution inherits that command's status, so a
   `node` that exists but is broken (bad shared library, wrong arch, OOM) tripped
   `set -e` — `command -v node` had already succeeded, so the guard did not help.
   This is the exact trap `lib.sh:14-18` documents for `latest_release_tag`.
   Shipped: `"$(node --version 2>/dev/null)" || spec_base_major=""`, which falls
   through the existing `''` case.
2. **The clone could block on an interactive credential prompt.** `credential.helper
   = store` with no `~/.git-credentials` falls through to `/dev/tty`. At boot there
   is no tty so it fails, but a hand-run `dotup` in a terminal would stall
   indefinitely. Shipped: `GIT_TERMINAL_PROMPT=0` on the clone, making "one attempt,
   no waiting" structural.
3. **The `-d .git` guard paired with an unconditional `rm -rf` could delete a tree
   that was not ours.** Three verified consequences: a hand-populated `checkout/`
   with no `.git` got destroyed; a worktree-style `.git` *file* read as "not
   installed" and a working tree got deleted; and a clone SIGKILLed partway left a
   partial `.git` that `rm -rf` never reached, so every later start read
   "installed" over a broken tree. Shipped: clone into a sibling
   `.checkout.tmp` and `mv` into place (a same-directory `rename(2)`, so unlike
   `install_tarball`'s cross-filesystem case it cannot half-move), guard on `-e`,
   and an `elif` that warns and leaves a non-git occupant alone rather than
   deleting it.
4. **`rmdir` before the guard**, because change 3 regressed the case where an empty
   `checkout/` used to self-heal — `git clone` succeeds into an empty directory, so
   the old guard cloned straight in. `rmdir` refuses a non-empty directory, so it
   recovers from an interrupted teardown without being able to delete content.
5. **The third assertion could not fail.** git cleans up its own failed clone of a
   nonexistent path, so `nocreds_checkout=absent` was true before the step existed
   and stayed true if the cleanup were deleted. Its comment now claims only what it
   proves, and a fourth assertion pre-seeds a leftover `.checkout.tmp` and asserts
   it is cleared. Note even that covers only the *post*-clone `rm -rf`; the
   pre-clone one is observable only when a clone succeeds, which needs Task 3's
   fixture — see Task 3 Step 1b.
6. Minors, all shipped: guarded `mkdir -p` and the `config.json` redirect (both
   abort paths on a full or read-only PVC); a `node -e` JSON parse replacing
   `grep '"local"'`, which false-positived on any value containing `local`, plus a
   warn for malformed JSON; a warn on a failed `mv`; `chmod 644` to match the
   sibling steps; a trailing `:` so the sourced file's exit status is structural;
   and actionable remedies in both warnings.

The invariant behind most of these: a step **sourced** into `install.sh` under
`set -euo pipefail` must have no command that can fail unguarded, because aborting
the install means a workspace with no shell, no nvim and no git identity. The
trailing `:` protects only the file's *exit status* — a mid-file failure aborts
immediately and never reaches it, which is why each guard is its own `if`.

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

- [ ] **Step 1b: Cover the pre-clone cleanup, which only a succeeding clone can show**

Task 2's `nocreds_tmp=absent` assertion is satisfied by the *post*-clone `rm -rf`
alone: delete the pre-clone one and it still passes. The pre-clone `rm -rf` is
load-bearing for a different case — with a leftover `.checkout.tmp` present, an
otherwise-succeeding `git clone` refuses outright ("destination path already exists
and is not an empty directory"), so without that line the step would fail on every
start forever. That is only observable where a clone succeeds, which is here.

In `install_run`'s heredoc, after the fixture is built and before `install.sh` runs:

```bash
# A leftover temp dir from a clone killed partway through must be cleared, not
# tripped over: git refuses to clone into a non-empty directory, so without the
# pre-clone rm -rf the step would fail on every start from here on.
mkdir -p ~/.claude/spec-base-local/.checkout.tmp
echo junk > ~/.claude/spec-base-local/.checkout.tmp/junk
```

and in the `CHECKS` heredoc plus assertions:

```bash
echo "spec_junk=$([ -e ~/.claude/spec-base-local/checkout/junk ] && echo present || echo absent)"
```

```bash
assert_contains "a leftover temp dir does not block a good clone" "spec_checkout=present" "$CHECKS"
assert_contains "the leftover temp dir is not adopted as the checkout" "spec_junk=absent" "$CHECKS"
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

#### Shipped: review-driven deviations from the code above

As with Task 2, **the committed `headless/setup/99-spec-base-setup.sh` is the source
of truth**, not the block above. Deltas:

1. **The plan's `if [ ! -f "$spec_base_launcher" ]; then : # already warned` was
   silent in a state nothing else warns about** — a checkout that exists and is a
   valid git repo but has no launcher at that path (upstream restructure, broken
   partial clone), including the worktree-style `.git`-file case the clone block
   deliberately accepts in silence. Shipped: a three-way split keyed on `.git`, so
   that state gets its own warning and only genuinely already-warned states stay
   quiet.
2. **`warn "… run /spec-base-update in a session"` was dead-end advice.** The five
   `/spec-base*` commands are created *by* the invocation that just failed, so on
   first boot they do not exist. Shipped: the remedy names the shell command
   (`node <launcher> install`) instead.
3. **Conflicts are reported by path, not by count**, and the steady-state `info`
   collapses to `N links already correct`. Both were the design's prescription
   rather than implementer choices, so the design doc was amended alongside.
4. **`# shellcheck disable=SC2016`** above the `node -e` block: the JS template
   literals inside single quotes are a genuine false positive. Precedent:
   `bin/fasterfetch`.
5. **Test fixes:** one of the two `spec_checkout=present` assertions was an exact
   duplicate and was dropped; `spec_junk=absent` could not fail under any plausible
   mutation and was retargeted to `.checkout.tmp` being absent after a *successful*
   clone (which a `cp`-instead-of-`mv` mutation does falsify); the pre-seed is now
   gated on the checkout being absent, so it cannot litter the post-restart state;
   and the fixture is rebuilt unconditionally so `--keep` cannot test a stale stub.
6. **Stub upgraded** to emit the nested `update` report shape and to `exit 2` on an
   unrecognised subcommand, giving the parser's `report.install ?? report` line and
   our flag spelling mechanical coverage.

Declined for now, recorded so they are not lost: converting the node and `mkdir`
guards to early `return`s (verified to work from a sourced step, and it would
unindent ~110 lines and retire the trailing `:`, but it rewrites Task 2's reviewed
code and would need its state enumeration re-run); a stub knob to synthesise
conflicts, so the new per-path warn ships untested; and a bash NUL-byte warning that
can reach the boot log without affecting the parse.

---

### Task 4: The restart path

`$HOME` is a PVC, so the second start must not re-clone and must not rewrite a `config.json` that is already there. This is the behaviour that keeps a workspace boot off the network.

**Files:**
- Modify: `tests/run.sh` (the `AFTER` block and its assertions)

- [ ] **Step 1: Write the test**

In the `AFTER` heredoc (the post-restart assertions), add:

The stub log lives on the PVC, so counting its lines only means "one invocation per
start" on a fresh volume — under `./tests/run.sh --keep` a leftover log inflates the
count and fails for no reason. Truncate it at the top of `install_run` (before
`install.sh`) so the count is always of this suite run:

```bash
: > ~/spec-base-stub.log
```

Then, in the `AFTER` heredoc:

```bash
echo "spec_argv=$(tail -1 ~/spec-base-stub.log 2>/dev/null)"
echo "spec_clones=$(grep -c '^' ~/spec-base-stub.log 2>/dev/null || echo 0)"
echo "spec_hub=$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.env.HOME + "/.claude/spec-base-local/config.json", "utf8")).hub)' 2>/dev/null || echo none)"
```

and after the existing restart assertions:

```bash
assert_not_contains "the spec-base checkout is not re-cloned" "spec-base: cloning" "$SECOND"
assert_contains "the restart re-links" "spec_argv=install" "$AFTER"
# Truncated at the top of each install_run, so this counts invocations within the
# restart alone: exactly one. Catches a step that calls the launcher twice per
# start, and unlike a cumulative count it holds under --keep too.
assert_contains "the launcher ran once per start" "spec_clones=1" "$AFTER"
assert_contains "the hosted pin survives the restart" "spec_hub=hosted" "$AFTER"
```

- [ ] **Step 2: Run the tests**

Run: `./tests/run.sh`
Expected: `all checks passed`. These are regression guards over behaviour Tasks 2 and 3 already built — if `spec_clones` comes back higher than 1, something is invoking the launcher more than once per start.

Note the truncation in Task 3's `install_run` must land before this, or the count is cumulative and this assertion reads 2 on a fresh volume and something else under `--keep`.

- [ ] **Step 3: Commit**

```bash
git add tests/run.sh
git commit -m "test: assert the spec-base layer survives a restart without re-cloning"
```

#### Shipped: review-driven deviations from the code above

1. **`assert_contains "spec_hub=hosted" "$AFTER"` could not fail.** The step only
   ever writes `{"hub": "hosted"}`, so "not rewritten" and "rewritten identically"
   are indistinguishable — make the write unconditional and the assertion stays
   green. Shipped: the restart seeds `config.json` with `custom-marker` (a value the
   production path can never produce) and asserts *that* survives, which does go red
   under the unconditional-write mutation. The seed is driven by a positional
   `install_run restart` argument rather than an env var, because an exported
   `SEED_HUB_MARKER` in a developer's shell would seed the wrong call *and* disable
   the self-heal below — they share one `if`/`elif`.
2. **The marker self-heals.** An aborted run (Ctrl-C, a genuine second-install
   failure) would otherwise leave `custom-marker` on the volume, and the next
   `--keep` run would fail `spec_hub=hosted` with nothing pointing at the cause. The
   next install now removes a `config.json` that literally contains the marker —
   and only that, so a real hand-written config is never destroyed.
3. **Every new assertion is newline-anchored.** `assert_contains` is a plain
   substring glob, so `spec_clones=1` also matched `13` and `100` — and "the
   launcher loops once per link instead of once per start" lands squarely in that
   window. Anchoring on the trailing newline follows the precedent the `greeting=`
   assertion already set in this harness. Demonstrated: the unanchored form passes a
   faked 13-line log, the anchored form fails it.
4. **`assert_not_contains "spec-base: cloning"` gained a positive control.** That
   string exists in exactly two places — the assertion and the step's `info` line —
   so rewording the log line would leave the check vacuously green forever. A
   companion assertion requires the string to appear in `$NOCREDS`, where the clone
   path is always reached (its `CLAUDE_CONFIG_DIR` lives in the container
   filesystem, not the volume, so it is empty in every mode). Demonstrated by
   renaming the log line: the control fails, the original stayed green.
5. **A failed restore now fails the suite**, rather than printing a marker only a
   human reading a green run's dump would notice.
6. **The per-start invocation count is asserted on both starts**, not just the
   restart, and `wc -l` replaced `grep -c '^' || echo 0` — `grep -c` prints `0` *and*
   exits 1 on an empty file, so the fallback double-printed and garbled the output
   in exactly the failure case worth debugging.

Recorded, not done: a simpler `assert_not_contains "spec-base: pinned the hosted hub"
"$SECOND"` would have tested the same guard with no volume mutation at all, since the
step prints that line only on the write path. Asserting on state rather than log text
is more durable, so the shipped version stands — but it is the cheaper shape if this
is ever revisited. Also recorded: `tests/run.sh`'s fixture builder (a Node stub inside
a nested heredoc) is the part that most wants extracting to `tests/fixtures/`, and the
`--upgrade` path is what will force it.

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
