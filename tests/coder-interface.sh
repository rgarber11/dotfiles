#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
# shellcheck source=tests/lib.sh
source "$HERE/lib.sh"

TMP="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

assert_equal() { # description, expected, actual
  if [ "$2" = "$3" ]; then
    pass "$1"
  else
    fail "$1 (expected: $2; actual: $3)"
  fi
}

run_privacy_step() {
  HOME="$1" DOTFILES_DIR="$REPO" UPGRADE=0 bash -c '
    set -euo pipefail
    source "$DOTFILES_DIR/headless/setup/lib.sh"
    source "$DOTFILES_DIR/headless/setup/41-claude-other-settings.sh"
  '
}

privacy_filter='{
  env: {
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL": "1",
    "DISABLE_TELEMETRY": "1",
    "DISABLE_ERROR_REPORTING": "1",
    "DISABLE_FEEDBACK_COMMAND": "1"
  },
  disableClaudeAiConnectors: true
}'

missing_home="$TMP/privacy-missing"
run_privacy_step "$missing_home"
missing_settings="$missing_home/.claude-other/settings.json"
assert_equal "missing GPT settings are created with exactly the privacy controls" \
  "$(jq -cS -n "$privacy_filter")" \
  "$(jq -cS . "$missing_settings")"
assert_equal "privacy settings use mode 0600" \
  '600' "$(stat -c %a "$missing_settings")"

populated_home="$TMP/privacy-populated"
mkdir -p "$populated_home/.claude-other"
cat > "$populated_home/.claude-other/settings.json" <<'JSON'
{
  "permissions": {"defaultMode": "auto"},
  "custom": {"keep": true},
  "env": {
    "KEEP_ME": "yes",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "0",
    "CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL": "0",
    "DISABLE_TELEMETRY": "0",
    "DISABLE_ERROR_REPORTING": "0",
    "DISABLE_FEEDBACK_COMMAND": "0"
  },
  "disableClaudeAiConnectors": false
}
JSON
run_privacy_step "$populated_home"
populated_settings="$populated_home/.claude-other/settings.json"
expected_populated="$(jq -cS -n "($privacy_filter) as \$privacy |
  \$privacy + {
    permissions: {defaultMode: \"auto\"},
    custom: {keep: true},
    env: (\$privacy.env + {KEEP_ME: \"yes\"})
  }")"
assert_equal "unrelated settings survive and conflicting privacy values are overwritten" \
  "$expected_populated" "$(jq -cS . "$populated_settings")"
assert_equal "updated privacy settings use mode 0600" \
  '600' "$(stat -c %a "$populated_settings")"
cp "$populated_settings" "$TMP/populated-first.json"
run_privacy_step "$populated_home"
if cmp -s "$TMP/populated-first.json" "$populated_settings"; then
  pass "a second privacy merge is byte-identical"
else
  fail "a second privacy merge is byte-identical"
fi

invalid_home="$TMP/privacy-invalid"
mkdir -p "$invalid_home/.claude-other"
printf '{invalid json\n' > "$invalid_home/.claude-other/settings.json"
invalid_settings="$invalid_home/.claude-other/settings.json"
cp "$invalid_settings" "$TMP/invalid-before.json"
invalid_output="$(run_privacy_step "$invalid_home" 2>&1)"
assert_contains "invalid settings produce a warning" \
  'not valid mergeable JSON; leaving it unchanged' "$invalid_output"
if cmp -s "$TMP/invalid-before.json" "$invalid_settings"; then
  pass "invalid settings remain byte-for-byte unchanged"
else
  fail "invalid settings remain byte-for-byte unchanged"
fi

summary
