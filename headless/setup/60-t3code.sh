#!/usr/bin/env bash
# T3 Code, started on every workspace start and reached through Coder's port
# forwarding instead of Tailscale or T3 Connect.
#
# Installed into ~/.local with npm, the same way 10-packages.sh installs
# tree-sitter-cli, rather than run as `npx t3 serve` each start: ~/.local is
# the PVC, so this installs once and the startup path stays off the network.
# --upgrade (dotup) re-resolves the latest release.
#
# Upstream's `t3 service install` is not used because it supports only systemd
# and launchd, and a Coder workspace container has neither.

start_t3code() {
  local port=3773 state="$HOME/.local/state/t3code" log

  if needs_install t3; then
    if command -v npm >/dev/null 2>&1; then
      info "npm: installing t3 into ~/.local"
      npm install -g --prefix "$HOME/.local" t3@latest >/dev/null 2>&1 ||
        warn "t3 install failed"
    else
      warn "npm not found; skipping T3 Code"
    fi
  fi
  command -v t3 >/dev/null 2>&1 || return 0

  _t3code_listening() { (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; }

  # Also covers `dotup` in a running workspace. It does not restart the server
  # onto the upgraded build, because that would kill whatever agent sessions
  # are in flight.
  if _t3code_listening; then
    info "t3: port $port is already in use; not starting another server"
    [ "${UPGRADE:-0}" = 1 ] && info "t3: restart the workspace to run the upgraded build"
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
