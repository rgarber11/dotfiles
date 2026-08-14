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
else
  mkdir -p "$spec_base_root"

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
      unreadable) warn "spec-base: $spec_base_root/config.json is not readable JSON; the launcher will fail on it" ;;
    esac
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
    spec_base_tmp="$spec_base_root/.checkout.tmp"
    rm -rf "$spec_base_tmp"
    if GIT_TERMINAL_PROMPT=0 git clone --quiet --branch "$SPEC_BASE_BRANCH" \
         "$SPEC_BASE_REPO" "$spec_base_tmp"; then
      mv "$spec_base_tmp" "$spec_base_checkout"
    else
      rm -rf "$spec_base_tmp"
      warn "spec-base: clone failed (git credentials not written yet?); retrying next start"
    fi
  elif [ ! -e "$spec_base_checkout/.git" ]; then
    # Something that is not a clone is sitting in the way. Deleting it is not
    # ours to do, and saying nothing would look like a successful install.
    warn "spec-base: $spec_base_checkout exists but is not a git checkout; leaving it alone"
  fi
fi

# install.sh sources this file and `set -e`s on a nonzero exit from the last
# command run, not just a failing command anywhere in it. Every branch above
# happens to end in 0, but that's fragile against Task 3 appending more to this
# file -- so make the exit status structural instead of accidental.
:
