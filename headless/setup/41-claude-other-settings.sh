#!/usr/bin/env bash
# Keep the GPT-backed Claude profile from contacting Anthropic services that
# are irrelevant or misleading when requests go through CLIProxyAPI.

apply_claude_other_privacy() {
  local dir="$HOME/.claude-other"
  local settings="$dir/settings.json"
  local tmp=""

  if ! command -v jq >/dev/null 2>&1; then
    warn "claude-other: jq is unavailable; privacy settings were not updated"
    return 0
  fi
  if ! mkdir -p "$dir"; then
    warn "claude-other: could not create $dir; privacy settings were not updated"
    return 0
  fi
  if [ -L "$settings" ] || { [ -e "$settings" ] && [ ! -f "$settings" ]; }; then
    warn "claude-other: $settings is not a regular file; leaving it unchanged"
    return 0
  fi

  if ! tmp="$(mktemp "$dir/.settings.json.tmp.XXXXXX")"; then
    warn "claude-other: could not create a temporary settings file"
    return 0
  fi

  if [ -f "$settings" ]; then
    if ! jq -s '
      if length != 1 then
        error("settings must contain exactly one JSON value")
      elif (.[0] | type) != "object" then
        error("settings must be a JSON object")
      elif (.[0].env != null and (.[0].env | type) != "object") then
        error("env must be a JSON object")
      else
        .[0] |
        .env = ((.env // {}) + {
          "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
          "CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL": "1",
          "DISABLE_TELEMETRY": "1",
          "DISABLE_ERROR_REPORTING": "1",
          "DISABLE_FEEDBACK_COMMAND": "1"
        }) |
        .disableClaudeAiConnectors = true
      end
    ' "$settings" > "$tmp"; then
      rm -f "$tmp" 2>/dev/null || true
      warn "claude-other: $settings is not valid mergeable JSON; leaving it unchanged"
      return 0
    fi
  else
    if ! jq -n '
      {
        env: {
          "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
          "CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL": "1",
          "DISABLE_TELEMETRY": "1",
          "DISABLE_ERROR_REPORTING": "1",
          "DISABLE_FEEDBACK_COMMAND": "1"
        },
        disableClaudeAiConnectors: true
      }
    ' > "$tmp"; then
      rm -f "$tmp" 2>/dev/null || true
      warn "claude-other: could not build privacy settings"
      return 0
    fi
  fi

  if ! chmod 600 "$tmp"; then
    rm -f "$tmp" 2>/dev/null || true
    warn "claude-other: could not set private permissions on $settings"
    return 0
  fi
  if ! mv "$tmp" "$settings"; then
    rm -f "$tmp" 2>/dev/null || true
    warn "claude-other: could not replace $settings"
    return 0
  fi

  info "claude-other: privacy settings enforced"
}

apply_claude_other_privacy
