#!/usr/bin/env bash
# Retire the Coder GPT launcher and CLIProxyAPI installation that this repo used
# to own. The Coder template now provides both; stale links or a surviving
# daemon from the old setup can shadow or block the template-managed versions.

retire_coder_gpt() {
  local proxy_link="$HOME/.local/bin/cli-proxy-api"
  local gpt_link="$HOME/.local/bin/gpt_code"
  local config_link="$HOME/.config/cli-proxy-api/config.yaml"
  local state="$HOME/.local/state/cli-proxy-api"
  local handoff_pending="$HOME/.local/state/dotfiles/coder-gpt-handoff-pending"
  local proxy_target="" candidate recorded_pid lock_fd
  local legacy_config=0 legacy_gpt=0 legacy_proxy_link=0
  local retired_proxy=0 stop_failed=0

  _retire_owned_symlink() {
    local target
    [ -L "$1" ] || return 1
    target=$(readlink "$1" 2>/dev/null || true)
    case "$target" in
      "$DOTFILES_DIR/$2"|"$HOME/.config/coderv2/dotfiles/$2"|"$HOME/dotfiles/$2") return 0 ;;
      *) return 1 ;;
    esac
  }

  _retire_pid_is_alive() {
    local pid=$1 line rest
    case "$pid" in ''|*[!0-9]*) return 1 ;; esac
    kill -0 "$pid" 2>/dev/null || return 1
    IFS= read -r line < "/proc/$pid/stat" 2>/dev/null || return 1
    rest=${line##*) }
    [ "${rest%% *}" != Z ]
  }

  _retire_legacy_proxy_pid_is_ours() {
    local pid=$1 n first_line interpreter candidate_exe interpreter_exe
    local -a argv=() shebang_argv=()

    _retire_pid_is_alive "$pid" || return 1
    [ -r "/proc/$pid/cmdline" ] || return 1
    mapfile -d '' -t argv < "/proc/$pid/cmdline" 2>/dev/null || return 1
    n=${#argv[@]}
    if [ "$n" -eq 3 ] &&
        { [ "${argv[0]}" = "$proxy_link" ] || [ "${argv[0]}" = "$proxy_target" ]; }; then
      :
    elif [ "$n" -eq 4 ] &&
        { [ "${argv[1]}" = "$proxy_link" ] || [ "${argv[1]}" = "$proxy_target" ]; }; then
      [ -r "$proxy_link" ] || return 1
      IFS= read -r first_line < "$proxy_link" || return 1
      case "$first_line" in '#!'*) ;; *) return 1 ;; esac
      read -r -a shebang_argv <<< "${first_line#\#!}"
      [ "${#shebang_argv[@]}" -ge 1 ] || return 1
      if [ "${shebang_argv[0]##*/}" = env ]; then
        [ "${#shebang_argv[@]}" -eq 2 ] || return 1
        interpreter=$(command -v "${shebang_argv[1]}") || return 1
      else
        [ "${#shebang_argv[@]}" -eq 1 ] || return 1
        interpreter=${shebang_argv[0]}
      fi
      candidate_exe=$(readlink -f "/proc/$pid/exe") || return 1
      interpreter_exe=$(readlink -f "$interpreter") || return 1
      [ "$candidate_exe" = "$interpreter_exe" ] || return 1
    else
      return 1
    fi
    [ "${argv[n - 2]}" = --config ] && [ "${argv[n - 1]}" = "$config_link" ]
  }

  _retire_stop_legacy_proxy() {
    local pid=$1
    _retire_legacy_proxy_pid_is_ours "$pid" || return 1
    kill -TERM "$pid" 2>/dev/null || true
    for _ in $(seq 1 50); do
      _retire_pid_is_alive "$pid" || return 0
      sleep 0.1
    done
    if _retire_legacy_proxy_pid_is_ours "$pid"; then
      kill -KILL "$pid" 2>/dev/null || true
    fi
    for _ in $(seq 1 20); do
      _retire_pid_is_alive "$pid" || return 0
      sleep 0.1
    done
    return 1
  }

  _retire_owned_symlink "$config_link" headless/cli-proxy-api.yaml &&
    legacy_config=1
  _retire_owned_symlink "$gpt_link" headless/bin/gpt_code &&
    legacy_gpt=1

  if [ "$legacy_config" = 1 ] || [ "$legacy_gpt" = 1 ]; then
    mkdir -p "$state" || {
      warn "Coder GPT retirement: could not create $state; leaving legacy artifacts in place"
      return 0
    }
    exec {lock_fd}>>"$state/setup.lock" || {
      warn "Coder GPT retirement: could not open the proxy setup lock"
      return 0
    }
    if ! flock -w 60 "$lock_fd"; then
      warn "Coder GPT retirement: proxy setup lock timed out; leaving legacy artifacts in place"
      exec {lock_fd}>&-
      return 0
    fi

    if [ -L "$proxy_link" ]; then
      proxy_target=$(readlink "$proxy_link" 2>/dev/null || true)
      case "$proxy_target" in
        "$HOME"/.local/opt/cli-proxy-api-*/cli-proxy-api) legacy_proxy_link=1 ;;
      esac
    fi

    for process in /proc/[0-9]*; do
      candidate=${process##*/}
      if _retire_legacy_proxy_pid_is_ours "$candidate"; then
        if _retire_stop_legacy_proxy "$candidate"; then
          recorded_pid=$(cat "$state/server.pid" 2>/dev/null || true)
          if [ "$recorded_pid" = "$candidate" ]; then
            rm -f "$state/server.pid"
          fi
        else
          warn "Coder GPT retirement: legacy proxy pid $candidate did not stop"
          stop_failed=1
        fi
      fi
    done

    if [ "$stop_failed" = 0 ]; then
      if [ "$legacy_proxy_link" = 1 ]; then
        rm -f "$proxy_link"
        retired_proxy=1
      fi
      if [ "$legacy_config" = 1 ]; then
        rm -f "$config_link"
        retired_proxy=1
      fi
      if [ "$legacy_gpt" = 1 ]; then
        rm -f "$gpt_link"
      fi
      info "retired the dotfiles-managed Coder GPT/CLIProxyAPI artifacts"
      if [ "$retired_proxy" = 1 ]; then
        if ! mkdir -p "$(dirname "$handoff_pending")" ||
            ! : > "$handoff_pending"; then
          warn "Coder GPT retirement: could not record the pending template handoff"
        fi
      fi
    fi

    flock -u "$lock_fd" 2>/dev/null || true
    exec {lock_fd}>&-
  fi

  if [ -e "$handoff_pending" ] && command -v ai-auth >/dev/null 2>&1; then
    if ai-auth cli-proxy start; then
      rm -f "$handoff_pending"
    else
      warn "cli-proxy: template-managed proxy did not start; run 'ai-auth cli-proxy status'"
    fi
  fi
}

retire_coder_gpt
