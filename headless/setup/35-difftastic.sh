#!/usr/bin/env bash
# difftastic is not packaged for noble. Upstream release into ~/.local.
if needs_install difft; then
  tag="$(latest_release_tag Wilfred/difftastic)"
  if [ -z "$tag" ]; then
    warn "could not resolve a difftastic release; git diff.external will be broken"
  else
    # strip=0: the difftastic archive is flat, holding a bare `difft` binary.
    install_tarball difft "$tag" \
      "https://github.com/Wilfred/difftastic/releases/download/$tag/difft-x86_64-unknown-linux-gnu.tar.gz" \
      "difft" 0 || warn "difftastic install failed"
  fi
fi
