# Claude Code profile launchers for the Coder headless profile.

_label_herdr_agent() {
  local pane_id=$1
  local display_label=$2
  local attempt

  for attempt in {1..50}; do
    if herdr agent get "$pane_id" >/dev/null 2>&1 &&
      herdr pane report-metadata "$pane_id" \
        --source user:zsh-claude-display \
        --agent claude \
        --display-agent "$display_label" >/dev/null 2>&1; then
      return
    fi
    sleep 0.1
  done
}

gpt_code() {
  local -a launch_command

  if [[ -n ${HERDR_PANE_ID:-} ]]; then
    _label_herdr_agent "$HERDR_PANE_ID" gpt_code &!
    launch_command=(
      sh -c
      'printf "\033]10;#ebdbb2\033\\"; printf "\033]11;#282828\033\\"; exec "$@"'
      sh
      claude-other --model gpt-5.6-sol "$@"
    )
  else
    launch_command=(claude-other --model gpt-5.6-sol "$@")
  fi

  env \
    ANTHROPIC_BASE_URL=http://127.0.0.1:8317 \
    ENABLE_CLAUDEAI_MCP_SERVERS=false \
    DISABLE_TELEMETRY=1 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    ANTHROPIC_AUTH_TOKEN=coder-local \
    ANTHROPIC_DEFAULT_OPUS_MODEL=gpt-5.6-sol \
    ANTHROPIC_DEFAULT_SONNET_MODEL=gpt-5.6-terra \
    ANTHROPIC_DEFAULT_HAIKU_MODEL=gpt-5.6-luna \
    "${launch_command[@]}"
}

monet() {
  local -a launch_command

  if [[ -n ${HERDR_PANE_ID:-} ]]; then
    _label_herdr_agent "$HERDR_PANE_ID" monet &!
    launch_command=(
      sh -c
      'printf "\033]10;#adadad\033\\"; printf "\033]11;#202020\033\\"; exec "$@"'
      sh
      claude-monet "$@"
    )
  else
    launch_command=(claude-monet "$@")
  fi

  "${launch_command[@]}"
}

claude() {
  if [[ -z ${CLAUDE_CONFIG_DIR:-} &&
        ${1:-} == --resume &&
        -n ${2:-} &&
        ${2:-} != */* ]]; then
    local session_id=$2
    local -a gpt_sessions monet_sessions

    gpt_sessions=(
      "$HOME"/.claude-other/projects/*/"$session_id".jsonl(N)
    )
    monet_sessions=(
      "$HOME"/.claude-monet/projects/*/"$session_id".jsonl(N)
    )

    if (( ${#gpt_sessions} && ${#monet_sessions} )); then
      print -u2 -- "claude: session $session_id exists in both gpt_code and monet stores"
      return 1
    fi
    if (( ${#gpt_sessions} )); then
      gpt_code "$@"
      return
    fi
    if (( ${#monet_sessions} )); then
      monet "$@"
      return
    fi
  fi

  command claude "$@"
}
