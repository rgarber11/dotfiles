#!/usr/bin/env bash
# Install CLIProxyAPI under persistent ~/.local storage and keep one process
# running for this workspace. Coder has no systemd; install.sh runs each start.

setup_cli_proxy_api_locked() {
  local config="${CLI_PROXY_CONFIG:-$HOME/.config/cli-proxy-api/config.yaml}"
  local auth_dir="${CLI_PROXY_AUTH_DIR:-/mnt/user-state/cli-proxy-api}"
  local auth_parent
  local state="$HOME/.local/state/cli-proxy-api"
  local pid_file="$state/server.pid"
  local log_file="$state/server.log"
  local tag version url pid pid_tmp current_pid attempt ready=0

  if [ "${UPGRADE:-0}" = 1 ] ||
      [ ! -x "$HOME/.local/bin/cli-proxy-api" ]; then
    tag="$(latest_release_tag router-for-me/CLIProxyAPI)" || tag=""
    if [ -n "$tag" ]; then
      version="${tag#v}"
      url="https://github.com/router-for-me/CLIProxyAPI/releases/download/$tag/CLIProxyAPI_${version}_linux_amd64.tar.gz"
      install_tarball cli-proxy-api "$tag" "$url" cli-proxy-api 0 ||
        warn "cli-proxy-api: install failed; keeping any existing binary"
    else
      warn "cli-proxy-api: could not resolve the latest release"
    fi
  fi

  if [ ! -x "$HOME/.local/bin/cli-proxy-api" ]; then
    warn "cli-proxy-api: no executable is installed; proxy not started"
    return 0
  fi
  if [ ! -f "$config" ]; then
    warn "cli-proxy-api: missing config $config; proxy not started"
    return 0
  fi

  auth_parent="$(dirname "$auth_dir")"
  if [ ! -d "$auth_parent" ] || [ ! -w "$auth_parent" ]; then
    warn "cli-proxy-api: shared user storage is unavailable at $auth_parent; proxy not started"
    return 0
  fi
  if ! mkdir -p "$auth_dir" "$state"; then
    warn "cli-proxy-api: could not create auth or state directories"
    return 0
  fi
  chmod 700 "$auth_dir" || {
    warn "cli-proxy-api: could not protect $auth_dir"
    return 0
  }
  chmod 600 "$config" || {
    warn "cli-proxy-api: could not protect $config"
    return 0
  }

  pid_is_alive() {
    local candidate=$1 stat_pid stat_comm stat_state stat_rest
    case "$candidate" in ''|*[!0-9]*) return 1 ;; esac
    kill -0 "$candidate" 2>/dev/null || return 1
    read -r stat_pid stat_comm stat_state stat_rest < "/proc/$candidate/stat" ||
      return 1
    [ "$stat_state" != Z ]
  }

  proxy_pid_is_ours() {
    local candidate=$1 executable="$HOME/.local/bin/cli-proxy-api"
    local first_line interpreter candidate_exe interpreter_exe
    local -a candidate_argv=() shebang_argv=()

    pid_is_alive "$candidate" || return 1
    [ -r "/proc/$candidate/cmdline" ] || return 1
    mapfile -d '' -t candidate_argv < "/proc/$candidate/cmdline" || return 1

    if [ "${#candidate_argv[@]}" -eq 3 ] &&
        [ "${candidate_argv[0]}" = "$executable" ]; then
      :
    elif [ "${#candidate_argv[@]}" -eq 4 ] &&
        [ "${candidate_argv[1]}" = "$executable" ]; then
      IFS= read -r first_line < "$executable" || return 1
      case "$first_line" in '#!'*) ;; *) return 1 ;; esac
      read -r -a shebang_argv <<< "${first_line#\#!}"
      [ "${#shebang_argv[@]}" -ge 1 ] || return 1
      if [ "${shebang_argv[0]##*/}" = env ]; then
        [ "${#shebang_argv[@]}" -eq 2 ] || return 1
        interpreter="$(command -v "${shebang_argv[1]}")" || return 1
      else
        [ "${#shebang_argv[@]}" -eq 1 ] || return 1
        interpreter="${shebang_argv[0]}"
      fi
      candidate_exe="$(readlink -f "/proc/$candidate/exe")" || return 1
      interpreter_exe="$(readlink -f "$interpreter")" || return 1
      [ "$candidate_exe" = "$interpreter_exe" ] || return 1
    else
      return 1
    fi

    [ "${candidate_argv[${#candidate_argv[@]} - 2]}" = --config ] &&
      [ "${candidate_argv[${#candidate_argv[@]} - 1]}" = "$config" ]
  }

  proxy_endpoint_is_healthy() {
    curl -fsS --max-time 2 \
      -H 'Authorization: Bearer coder-local' \
      http://127.0.0.1:8317/v1/models >/dev/null 2>&1
  }

  stop_proxy() {
    local stop_pid=$1
    proxy_pid_is_ours "$stop_pid" || return 1
    kill -TERM "$stop_pid" 2>/dev/null || true
    for attempt in $(seq 1 50); do
      pid_is_alive "$stop_pid" || return 0
      sleep 0.1
    done
    if proxy_pid_is_ours "$stop_pid"; then
      kill -KILL "$stop_pid" 2>/dev/null || true
    fi
    return 0
  }

  current_pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [ -n "$current_pid" ] && proxy_pid_is_ours "$current_pid"; then
    if [ "${UPGRADE:-0}" = 0 ] &&
        proxy_endpoint_is_healthy &&
        proxy_pid_is_ours "$current_pid"; then
      info "cli-proxy-api: already running (pid $current_pid)"
      return 0
    fi
    if [ "${UPGRADE:-0}" = 0 ]; then
      warn "cli-proxy-api: existing process is unhealthy; restarting it"
    fi
    stop_proxy "$current_pid" || true
  elif [ -n "$current_pid" ]; then
    if kill -0 "$current_pid" 2>/dev/null; then
      warn "cli-proxy-api: pid $current_pid belongs to another process; leaving it untouched"
    fi
    if ! rm -f "$pid_file"; then
      warn "cli-proxy-api: could not remove stale PID metadata"
      return 0
    fi
  fi

  umask 077
  (
    exec {lock_fd}>&-
    exec nohup "$HOME/.local/bin/cli-proxy-api" --config "$config"
  ) > "$log_file" 2>&1 &
  pid=$!
  pid_tmp="$pid_file.tmp.$$"
  if ! printf '%s\n' "$pid" > "$pid_tmp" || ! mv "$pid_tmp" "$pid_file"; then
    rm -f "$pid_tmp" 2>/dev/null || true
    stop_proxy "$pid" || true
    warn "cli-proxy-api: could not record the proxy PID"
    return 0
  fi

  for attempt in $(seq 1 50); do
    if pid_is_alive "$pid" &&
        proxy_endpoint_is_healthy &&
        pid_is_alive "$pid"; then
      ready=1
      break
    fi
    pid_is_alive "$pid" || break
    sleep 0.1
  done
  if [ "$ready" = 1 ]; then
    info "cli-proxy-api: ready on 127.0.0.1:8317 (pid $pid)"
  else
    if pid_is_alive "$pid"; then
      stop_proxy "$pid" || true
    fi
    rm -f "$pid_file" ||
      warn "cli-proxy-api: could not remove failed child PID metadata"
    warn "cli-proxy-api: did not become ready; see $log_file"
  fi
  return 0
}

setup_cli_proxy_api() {
  local state="$HOME/.local/state/cli-proxy-api"
  local lock_fd rc=0
  mkdir -p "$state" || {
    warn "cli-proxy-api: could not create $state"
    return 0
  }
  exec {lock_fd}>"$state/setup.lock" || {
    warn "cli-proxy-api: could not open the setup lock"
    return 0
  }
  if ! flock -w 30 "$lock_fd"; then
    warn "cli-proxy-api: setup lock timed out"
    exec {lock_fd}>&-
    return 0
  fi
  setup_cli_proxy_api_locked || rc=$?
  flock -u "$lock_fd" 2>/dev/null || true
  exec {lock_fd}>&-
  if [ "$rc" -ne 0 ]; then
    warn "cli-proxy-api: setup failed; proxy may be unavailable"
  fi
  return 0
}

setup_cli_proxy_api
