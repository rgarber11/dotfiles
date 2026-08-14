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
