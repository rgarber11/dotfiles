#!/usr/bin/env bash
# noble ships chafa 1.14, which predates --probe; without probing, chafa guesses
# the terminal's cell pixel size and gets it wrong over ssh, so images render
# too narrow. Upstream publishes static x86_64 builds, so take those.
#
# Version comes from upstream's directory listing rather than the GitHub API:
# the GitHub releases carry source only, and the filenames add a build-revision
# suffix after the version that we shouldn't hardcode.
#
# `|| true` on the assignment: under a network failure, curl produces no
# output, so grep finds no match and exits 1; with pipefail (set by our
# caller) that non-zero becomes the pipeline's status, and a bare failing
# command substitution in an assignment aborts the script under `set -e` --
# verified by hand, this is not hypothetical. `|| true` keeps that failure a
# plain empty `chafa_file`, handled below, instead of taking down the whole
# install.
if needs_install chafa; then
  chafa_file="$(curl -fsSL --max-time 20 https://hpjansson.org/chafa/releases/static/ 2>/dev/null \
    | grep -oE 'chafa-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-x86_64-linux-gnu\.tar\.gz' \
    | sort -V | tail -1)" || true
  if [ -z "$chafa_file" ]; then
    warn "could not resolve a chafa build; falling back to the system chafa"
  else
    chafa_ver="${chafa_file#chafa-}"
    chafa_ver="${chafa_ver%-x86_64-linux-gnu.tar.gz}"
    install_tarball chafa "$chafa_ver" \
      "https://hpjansson.org/chafa/releases/static/$chafa_file" \
      "chafa" 1 || warn "chafa install failed; to_qr may render at the wrong size"
  fi
fi
