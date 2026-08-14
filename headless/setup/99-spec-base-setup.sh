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
    rm -rf "$spec_base_tmp" || warn "spec-base: could not clear $spec_base_tmp"
    # timeout, because GIT_TERMINAL_PROMPT=0 closes the prompt stall but not the
    # network one: git has no built-in timeout, and an egress that drops packets
    # rather than resetting them makes a clone hang instead of fail. A hang here
    # means install.sh never returns and the workspace never reports ready, so
    # this is the one failure mode that outranks the clone not happening at all.
    # 300s matches lib.sh's --max-time for a comparable transfer; -k 10 covers a
    # git that ignores SIGTERM. Exit 124 lands in the existing warn branch.
    if GIT_TERMINAL_PROMPT=0 timeout -k 10 300 git clone --quiet --branch "$SPEC_BASE_BRANCH" \
         "$SPEC_BASE_REPO" "$spec_base_tmp"; then
      mv "$spec_base_tmp" "$spec_base_checkout" ||
        warn "spec-base: could not move the clone into place; retrying next start"
    else
      rm -rf "$spec_base_tmp" || warn "spec-base: could not clear $spec_base_tmp"
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
    # SPEC_BASE_BRANCH governs the clone only: an existing checkout keeps whatever
    # branch it is on, because the launcher's update pulls the checkout's own HEAD.
    # So changing the default here does nothing on a PVC that has already cloned --
    # which is exactly what will happen when the fork merges to main. Say so rather
    # than let it drift silently. Offline: rev-parse reads .git, nothing else.
    spec_base_head="$(git -C "$spec_base_checkout" rev-parse --abbrev-ref HEAD 2>/dev/null)" ||
      spec_base_head=""
    case "$spec_base_head" in
      ""|"$SPEC_BASE_BRANCH") ;;
      # rev-parse --abbrev-ref prints the literal "HEAD" for a detached checkout
      # and still exits 0, so without this arm the warn would name "HEAD" as if it
      # were a branch. Worth its own sentence: the launcher's pullOwnBranch would
      # go on to run `git pull --ff-only origin HEAD`, which is not what anyone
      # means by an update.
      HEAD)
        warn "spec-base: $spec_base_checkout is on a detached HEAD, so an update cannot fast-forward it; check it out onto $SPEC_BASE_BRANCH or delete it to reclone" ;;
      *)
        warn "spec-base: the checkout is on $spec_base_head, not $SPEC_BASE_BRANCH; that only governs new clones, so switch it in $spec_base_checkout or delete it to reclone" ;;
    esac

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
    # GIT_TERMINAL_PROMPT=0 here for the same reason the clone sets it: `update`
    # shells out to git fetch/pull/merge, the launcher never sets it, and a
    # hand-run `dotup` in a terminal would otherwise stall on a username prompt
    # instead of failing and warning.
    # Bounded for the same reason as the clone above: `update` shells out to git
    # fetch/pull/merge, so it inherits the same hang-instead-of-fail risk, and a
    # hang at this step blocks the whole startup script. `install` is offline and
    # finishes in milliseconds, so the bound only ever bites the update path.
    if spec_base_report="$(GIT_TERMINAL_PROMPT=0 timeout -k 10 300 node "$spec_base_launcher" "${spec_base_cmd[@]}")"; then
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
        //
        // Carry the reason the launcher itself reported: it emits either "exists
        // and is not a symlink" or "target missing: <path>", which need different
        // fixes, so naming one of them for both would misdiagnose half the cases.
        // Joined with "; " because a reason contains spaces.
        const p = (c) => {
          if (!c || typeof c !== "object") return String(c);
          if (!c.link) return JSON.stringify(c);
          return c.reason ? `${c.link} (${c.reason})` : c.link;
        };
        console.log((i.conflicts ?? []).map(p).join("; "));
        // Third line: trouble only `update` can report. These live at the top
        // level of its report, never under .install, and the counts cannot show
        // them -- so without this a dotup whose fetch died or whose origin/main
        // merge conflicted printed a cheerful "6 links already correct" and
        // nothing else. Tokens, not git messages, so the shell can split them
        // one per warn without worrying about embedded spaces.
        const t = [];
        if (r.ownBranch?.failed) t.push("pull-failed");
        if (r.ownBranch?.dirty || r.merge?.dirty) t.push("dirty");
        if (r.upstream?.fetchFailed) t.push("fetch-failed");
        if (r.merge?.conflict) t.push("merge-conflict");
        console.log(t.join(" "));
        // Fourth line: the upstream files the skill depends on, when a merge
        // changed them. skillDrift exists so the skill gets updated
        // deliberately rather than silently, and it only populates on a merge that
        // succeeded -- the path the tokens above stay quiet about, so staying quiet
        // here too would defeat the whole point of it. Paths are repo-relative and
        // space-free (they come from a fixed WATCHED list), so one line is enough.
        console.log((r.drift?.files ?? []).join(" "));
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
        spec_base_trouble="${spec_base_lines[2]:-}"
        spec_base_drift="${spec_base_lines[3]:-}"
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
        # Each entry carries the launcher's own reason, so this no longer asserts
        # which of the two it was: "exists and is not a symlink" wants the file
        # moved aside, "target missing" means the checkout is incomplete and wants
        # a reclone. Saying one for both sent half the cases the wrong way.
        if [ -n "$spec_base_conflicts" ]; then
          warn "spec-base: $spec_base_bad link(s) not created: $spec_base_conflicts -- resolve those paths and re-run"
        fi
        # Only `update` can populate these, and only `dotup` runs update -- but
        # when it does, a failed fetch or a conflicted merge is the whole point of
        # having run it, and the link counts above say nothing about either.
        if [ -n "$spec_base_trouble" ]; then
          read -ra spec_base_troubles <<<"$spec_base_trouble"
          for spec_base_t in "${spec_base_troubles[@]}"; do
            case "$spec_base_t" in
              pull-failed)
                warn "spec-base: could not fast-forward $SPEC_BASE_BRANCH; the skill and commands are the version already on disk" ;;
              dirty)
                # Not "nothing was pulled": merge.dirty can be set on its own, when
                # a pull succeeded and left the tree dirty (a smudge filter, a
                # submodule pointer). The merge is the part that is always skipped.
                warn "spec-base: the checkout has uncommitted changes, so the origin/main merge was skipped; commit or discard them in $spec_base_checkout" ;;
              fetch-failed)
                warn "spec-base: could not fetch origin/main; coworkers' fixes were not merged" ;;
              merge-conflict)
                warn "spec-base: origin/main conflicts with $SPEC_BASE_BRANCH; the merge was aborted, so resolve it by hand in $spec_base_checkout" ;;
            esac
          done
        fi
        if [ -n "$spec_base_drift" ]; then
          warn "spec-base: origin/main changed files this skill depends on ($spec_base_drift); re-read them before trusting the skill's instructions"
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
