#!/usr/bin/env bash
# Atlassian CLI (acli). Upstream's Linux install is an apt repo or a bare
# binary at a `latest` URL; the binary goes straight into ~/.local/bin, which
# is the PVC, so it is downloaded once rather than on every start like apt.
# There is no tag to pin, so --upgrade just fetches `latest` again.
if needs_install acli; then
  info "downloading acli"
  # The temp file sits next to its destination so the final mv is a rename:
  # a failed or interrupted download never leaves a truncated acli on PATH.
  acli_tmp="$(mktemp "$HOME/.local/bin/.acli.XXXXXX")" || acli_tmp=""
  if [ -z "$acli_tmp" ]; then
    warn "acli: could not create a temp file in ~/.local/bin"
  elif curl -fsSL --max-time 300 -o "$acli_tmp" \
         https://acli.atlassian.com/linux/latest/acli_linux_amd64/acli &&
       chmod 755 "$acli_tmp" && "$acli_tmp" --version >/dev/null 2>&1 &&
       mv -f "$acli_tmp" "$HOME/.local/bin/acli"; then
    info "installed $(acli --version 2>/dev/null)"
  else
    warn "acli install failed"
    rm -f "$acli_tmp"
  fi
  unset acli_tmp
fi

# Log in on every start from the workspace's ATLASSIAN_CLI_* variables, so a
# rotated token takes effect on the next restart. The token is piped in from
# printf, a builtin, so it never appears in a process's argv.
if command -v acli >/dev/null 2>&1; then
  if [ -z "${ATLASSIAN_CLI_SITE:-}" ] || [ -z "${ATLASSIAN_CLI_EMAIL:-}" ] ||
     [ -z "${ATLASSIAN_CLI_API_TOKEN:-}" ]; then
    info "acli: ATLASSIAN_CLI_SITE, _EMAIL or _API_TOKEN unset; skipping jira login"
  elif printf '%s\n' "$ATLASSIAN_CLI_API_TOKEN" |
       acli jira auth login --site "$ATLASSIAN_CLI_SITE" \
         --email "$ATLASSIAN_CLI_EMAIL" --token >/dev/null 2>&1; then
    info "acli: logged in to jira at $ATLASSIAN_CLI_SITE"
  else
    warn "acli: jira login to $ATLASSIAN_CLI_SITE failed"
  fi
fi
