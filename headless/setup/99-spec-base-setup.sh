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
  # A bare assignment from a command substitution inherits that command's exit
  # status, and this file runs under install.sh's `set -euo pipefail`: a node
  # binary that exists but is broken (bad shared library, wrong arch, OOM) would
  # otherwise abort the whole install right here. Falling back to "" sends it
  # through the same '' case below as node being absent.
  spec_base_major="$(node --version 2>/dev/null)" || spec_base_major=""
  spec_base_major="${spec_base_major#v}"          # v24.5.0 -> 24.5.0
  spec_base_major="${spec_base_major%%.*}"
  case "$spec_base_major" in
    ''|*[!0-9]*) ;;
    *) [ "$spec_base_major" -ge 22 ] && spec_base_node=1 ;;
  esac
fi

if [ "$spec_base_node" != 1 ]; then
  warn "spec-base: node 22+ not found; skipping the local review layer"
elif ! mkdir -p "$spec_base_root"; then
  # A mid-file `set -e` abort never reaches the trailing `:` at the bottom, so
  # this has to be its own guard rather than relying on that to save it.
  warn "spec-base: cannot create $spec_base_root; skipping the local review layer"
else
  # Written only when absent: a file that already exists was written by hand, and
  # silently overwriting a deliberate choice is worse than saying it cannot work.
  if [ ! -e "$spec_base_root/config.json" ]; then
    # A read-only or full PVC makes this redirect fail; that must warn, not
    # abort the install the way an unguarded `>` would under `set -e`.
    if printf '{\n  "hub": "hosted"\n}\n' > "$spec_base_root/config.json"; then
      info "spec-base: pinned the hosted hub"
    else
      warn "spec-base: could not write $spec_base_root/config.json"
    fi
  else
    # node is a hard requirement ten lines up, so use it to parse instead of
    # grepping for "local" -- a substring match would false-positive on any
    # value containing it, e.g. a "path": "/local/x" key.
    spec_base_hub="$(node -e '
      const f = process.argv[1];
      try {
        console.log(JSON.parse(require("fs").readFileSync(f, "utf8")).hub ?? "");
      } catch {
        console.log("unreadable");
      }
    ' "$spec_base_root/config.json" 2>/dev/null)" || spec_base_hub="unreadable"
    case "$spec_base_hub" in
      local) warn "spec-base: config.json asks for the local hub, which needs podman or docker; delete it to restore the hosted pin" ;;
      # Not "the launcher will fail on it": the launcher's readJsonFile swallows the
      # parse error and returns {}, so resolveHub falls back to its "local" default
      # -- which cannot work in a pod. It degrades quietly rather than failing, so
      # this warn is the only signal, and it has to name the remedy.
      unreadable) warn "spec-base: $spec_base_root/config.json is not readable JSON, so the hosted pin will not apply; delete it and re-run to restore it" ;;
    esac
  fi

  # rmdir refuses a non-empty directory, so this recovers from an interrupted
  # teardown or a stray mkdir without being able to delete anything real.
  if [ -d "$spec_base_checkout" ]; then
    rmdir "$spec_base_checkout" 2>/dev/null || true
  fi

  # -e, not -d .git: a worktree-style checkout keeps `.git` as a regular file, and
  # reading that as "not installed" would delete a working tree below.
  if [ ! -e "$spec_base_checkout" ]; then
    info "spec-base: cloning $SPEC_BASE_BRANCH"
    # Clone to a temp path and move into place, the same way install_tarball
    # never half-installs a tarball. Nothing at $spec_base_checkout is ever
    # deleted, and a clone killed partway (OOM in a memory-limited pod) leaves
    # only .checkout.tmp -- so the next start still sees "not installed" and
    # retries, instead of reading "installed" over a broken tree forever.
    #
    # One attempt, no waiting for credentials: they come from a startup script
    # that runs independently of this one. GIT_TERMINAL_PROMPT=0 keeps a manual
    # `dotup` from stalling on a username prompt instead of failing.
    # Both rm -rf calls are `|| true`: a leftover staging dir this user cannot
    # delete (a PVC whose ~/.claude ownership shifted, a read-only volume) would
    # otherwise be an unguarded non-zero and abort install.sh -- note mkdir -p on
    # an existing root returns 0, so the guard above does not catch it. Ignoring
    # the failure leaves the clone to fail on the non-empty directory instead,
    # which warns and retries next start like any other clone failure.
    spec_base_tmp="$spec_base_root/.checkout.tmp"
    rm -rf "$spec_base_tmp" || true
    if GIT_TERMINAL_PROMPT=0 git clone --quiet --branch "$SPEC_BASE_BRANCH" \
         "$SPEC_BASE_REPO" "$spec_base_tmp"; then
      mv "$spec_base_tmp" "$spec_base_checkout" ||
        warn "spec-base: could not move the clone into place; retrying next start"
    else
      rm -rf "$spec_base_tmp" || true
      warn "spec-base: clone failed (git credentials not written yet?); retrying next start"
    fi
  elif [ ! -e "$spec_base_checkout/.git" ]; then
    # Something that is not a clone is sitting in the way. Deleting it is not
    # ours to do, and saying nothing would look like a successful install.
    warn "spec-base: $spec_base_checkout exists but is not a git checkout; move it aside or delete it, then re-run"
  fi

  # -e .git, not just "did the clone block above run": a checkout that is
  # absent, or present but not a git repo, was already warned about above --
  # warning again here would just be noise. But a checkout that IS a valid git
  # repo and still has no launcher at this path (upstream restructured, or a
  # clone that landed with a broken tree) has never been warned about, and
  # silently skipping the link step would look like a successful install.
  if [ ! -e "$spec_base_checkout/.git" ]; then
    : # absent or not-a-checkout: the block above already warned
  elif [ ! -f "$spec_base_launcher" ]; then
    warn "spec-base: $spec_base_checkout has no launcher at packages/spec-base-local/bin/spec-base-local.mjs; delete it and re-run to reclone"
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
    # $spec_base_report captures only stdout; the launcher's stderr (a stack
    # trace on failure) flows straight to the console, same as git clone's
    # above -- worth more in a failure boot log than success-path silence
    # would be worth in return.
    if spec_base_report="$(node "$spec_base_launcher" "${spec_base_cmd[@]}")"; then
      # node -e and not jq: node is a hard requirement two lines up, jq is not
      # guaranteed anywhere. `install` spreads its counts at the top level while
      # `update` nests them under "install", so accept either.
      # shellcheck disable=SC2016 # the ${...} below are JS template-literal
      # interpolations, not shell expansions -- the single quotes are correct.
      spec_base_output="$(node -e '
        const r = JSON.parse(require("fs").readFileSync(0, "utf8"));
        const i = r.install ?? r;
        const n = (a) => (a ?? []).length;
        console.log(`${n(i.linked)} ${n(i.relinked)} ${n(i.alreadyCorrect)} ${n(i.conflicts)}`);
        // String.prototype.link is a legacy Annex B method every string
        // already has, so a bare-string conflict entry has a non-nullish
        // .link (a function) and "??" never falls through to it -- hence the
        // typeof guard instead of a plain "c.link ?? c".
        const p = (c) => (c && typeof c === "object" ? (c.link ?? JSON.stringify(c)) : String(c));
        console.log((i.conflicts ?? []).map(p).join(" "));
      ' <<<"$spec_base_report" 2>/dev/null)" || spec_base_output=""
      if [ -n "$spec_base_output" ]; then
        # mapfile, not a `... | tail -1` pipeline: under `set -o pipefail` a
        # failing pipe stage there would be an unguarded top-level command and
        # abort the install. mapfile always returns 0, even reading a single
        # line or an empty here-string.
        mapfile -t spec_base_lines <<<"$spec_base_output"
        # Guarded like [1] just below even though a non-empty $spec_base_output
        # always yields at least one element: the guarantee lives five lines
        # away, and an empty array here would be a set -u abort, not a fallback.
        spec_base_counts="${spec_base_lines[0]:-}"
        spec_base_conflicts="${spec_base_lines[1]:-}"
        read -r spec_base_new spec_base_re spec_base_ok spec_base_bad <<<"$spec_base_counts"
        if [ "$spec_base_new" = 0 ] && [ "$spec_base_re" = 0 ] && [ "$spec_base_ok" = 0 ] && [ "$spec_base_bad" = 0 ]; then
          # Every count zero means the launcher linked nothing at all, not that
          # a healthy restart found nothing new -- worth a warn, not the same
          # info line a restart with N already-correct links would print.
          warn "spec-base: linked nothing at all; the local review layer is not installed"
        elif [ "$spec_base_new" = 0 ] && [ "$spec_base_re" = 0 ] && [ "$spec_base_ok" != 0 ]; then
          # The ok != 0 test matters: with conflicts present but nothing correct,
          # this branch would otherwise print "0 links already correct" -- a
          # sentence whose own number contradicts its verb. Falling through to the
          # triple below states all three counts instead, and the conflict warn
          # follows it. A partial state (4 correct, 2 conflicted) still lands here,
          # which is the most useful thing this line can say.
          info "spec-base: $spec_base_ok links already correct"
        else
          info "spec-base: linked $spec_base_new, relinked $spec_base_re, already correct $spec_base_ok"
        fi
        if [ -n "$spec_base_conflicts" ]; then
          warn "spec-base: $spec_base_bad link(s) not linked (something there is not a symlink): $spec_base_conflicts; move them aside and re-run"
        fi
      else
        info "spec-base: ${spec_base_cmd[0]} finished"
      fi
    else
      warn "spec-base: ${spec_base_cmd[0]} failed; re-run \`node $spec_base_launcher install\` (the offline link step) for the error"
    fi
  fi
fi

# A failing command anywhere in this file aborts install.sh under `set -e`;
# separately, `source` returns the status of the last command run -- so keep a
# `:` last, or a branch that ends in a false test would abort the install.
:
