#!/usr/bin/env bash
# fastfetch is not in noble (it lands in 24.10). Deliberately the tarball and
# not the .deb or the zhangsongcui3371 PPA: both install into /usr, which is
# ephemeral, so either would be discarded and re-downloaded on every start.
# Installed for manual use; nothing sources it from an rc file.
if needs_install fastfetch; then
  tag="$(latest_release_tag fastfetch-cli/fastfetch)"
  if [ -z "$tag" ]; then
    warn "could not resolve a fastfetch release"
  else
    install_tarball fastfetch "$tag" \
      "https://github.com/fastfetch-cli/fastfetch/releases/download/$tag/fastfetch-linux-amd64.tar.gz" \
      "usr/bin/fastfetch" 1 || warn "fastfetch install failed"
  fi
fi
