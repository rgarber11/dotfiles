#!/usr/bin/env bash
# T3 Code, started on every workspace start and reached through Coder's port
# forwarding instead of Tailscale or T3 Connect.
#
# Installed into ~/.local with npm, the same way 10-packages.sh installs
# tree-sitter-cli, rather than run as `npx t3 serve` each start: ~/.local is
# the PVC, so the package itself is only downloaded when it changes.
# This tracks the nightly channel (npm dist-tag `nightly`), not `latest`.
# Every start asks npm which build `nightly` points at and reinstalls when it
# differs from the one on the PVC, so a restart always serves the newest
# nightly. Nightlies land about daily, so a lookup on every start is the only
# way to stay current. If npm can't be reached, the installed build keeps
# running. A stable build left on the PVC by an earlier version of this script
# is replaced on the next start.
#
# Upstream's `t3 service install` is not used because it supports only systemd
# and launchd, and a Coder workspace container has neither.

# Version of the t3 in ~/.local, or nothing. Read from the package's own
# manifest rather than `t3 --version`, which would start the CLI on every boot.
# Always returns 0, for the same reason as latest_release_tag in lib.sh.
_t3code_installed_version() {
  sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' \
    "$HOME/.local/lib/node_modules/t3/package.json" 2>/dev/null | head -1
  return 0
}

# Version the `nightly` dist-tag points at, or nothing when npm is unreachable.
_t3code_latest_nightly() {
  timeout 20 npm view t3@nightly version 2>/dev/null | tail -1
  return 0
}

start_t3code() {
  local port=${T3CODE_PORT:-3773} state="$HOME/.local/state/t3code" log installed=0
  local have want reason=""

  if command -v npm >/dev/null 2>&1; then
    have="$(_t3code_installed_version)"
    want="$(_t3code_latest_nightly)"
    if needs_install t3 || [ -z "$have" ]; then
      reason="installing t3@nightly"
    elif [ -n "$want" ] && [ "$want" != "$have" ]; then
      reason="updating t3 $have -> $want"
    elif [ -z "$want" ] && [[ "$have" != *-nightly.* ]]; then
      reason="replacing t3 $have with t3@nightly"
    elif [ -z "$want" ]; then
      warn "t3: could not look up the newest nightly; keeping $have"
    fi
    if [ -n "$reason" ]; then
      info "npm: $reason into ~/.local"
      if npm install -g --prefix "$HOME/.local" "t3@${want:-nightly}" >/dev/null 2>&1; then
        installed=1
      else
        warn "t3 install failed"
      fi
    fi
  elif needs_install t3; then
    warn "npm not found; skipping T3 Code"
  fi
  command -v t3 >/dev/null 2>&1 || return 0

  _t3code_listening() { (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; }

  # Also covers `dotup` in a running workspace. It does not restart the server
  # onto the upgraded build, because that would kill whatever agent sessions
  # are in flight.
  if _t3code_listening; then
    info "t3: port $port is already in use; not starting another server"
    [ "$installed" = 1 ] && info "t3: restart the workspace to run the newly installed build"
    return 0
  fi

  mkdir -p "$state" || { warn "t3: could not create $state"; return 0; }
  log="$state/serve.log"

  # An explicit 0.0.0.0, not t3's default, puts the server under its
  # remote-reachable auth policy and binds every interface Coder can forward.
  # The pinned port matters too: without --port, t3 scans upward from 3773,
  # and the forwarded URL would change whenever that port was taken.
  #
  # setsid and full stdio redirection detach it from the startup script. A
  # background child that keeps the script's stdout or stderr open stops the
  # Coder agent from ever seeing the startup script finish.
  (cd "$HOME" && setsid t3 serve --host 0.0.0.0 --port "$port" "$HOME" \
      >"$log" 2>&1 </dev/null &)

  for _ in $(seq 1 30); do
    if _t3code_listening; then
      info "t3: serving on 0.0.0.0:$port (log: $log)"
      return 0
    fi
    sleep 0.5
  done
  warn "t3: server did not start listening on :$port within 15s; see $log"
}

start_t3code
