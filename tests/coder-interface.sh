#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
# shellcheck source=tests/lib.sh
source "$HERE/lib.sh"

TMP="$(mktemp -d)"
cleanup() {
  if [ -f "$TMP/proxy-home/.local/state/cli-proxy-api/server.pid" ]; then
    pid="$(cat "$TMP/proxy-home/.local/state/cli-proxy-api/server.pid" 2>/dev/null || true)"
    case "$pid" in ''|*[!0-9]*) ;; *) kill "$pid" 2>/dev/null || true ;; esac
  fi
  if [ -n "${FOREIGN_PID:-}" ]; then kill "$FOREIGN_PID" 2>/dev/null || true; fi
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

proxy_home="$TMP/proxy-home"
proxy_auth="$TMP/proxy-auth"
proxy_config="$TMP/proxy-config.yaml"
fake_bin="$TMP/fake-bin"
mkdir -p "$proxy_home/.local/opt/cli-proxy-api-v1" "$proxy_home/.local/bin" "$proxy_auth" "$fake_bin"
cat > "$proxy_config" <<EOF
host: 127.0.0.1
port: 8317
auth-dir: "$proxy_auth"
api-keys:
  - coder-local
EOF
cat > "$fake_bin/curl" <<'SH'
#!/usr/bin/env sh
authenticated=0
endpoint=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    -H)
      shift
      [ "${1:-}" = 'Authorization: Bearer coder-local' ] && authenticated=1
      ;;
    http://127.0.0.1:8317/v1/models) endpoint=1 ;;
  esac
  shift
done
[ "$authenticated" = 1 ] && [ "$endpoint" = 1 ] || exit 1
[ -f "$FAKE_PROXY_MARKER" ] &&
  [ "$(cat "$FAKE_PROXY_MARKER")" = "$FAKE_PROXY_EXPECTED_VERSION" ] ||
  exit 1
printf '{"data":[],"object":"list"}\n'
SH
chmod +x "$fake_bin/curl"
make_fake_proxy() {
  local version=$1
  FAKE_PROXY_EXPECTED_VERSION=$version
  local target="$proxy_home/.local/opt/cli-proxy-api-$version/cli-proxy-api"
  mkdir -p "$(dirname "$target")"
  cat > "$target" <<EOF
#!/usr/bin/env sh
trap 'exit 0' TERM INT
printf '%s\n' '$version' > "\$FAKE_PROXY_MARKER"
while :; do sleep 1; done
EOF
  chmod +x "$target"
  ln -sfn "$target" "$proxy_home/.local/bin/cli-proxy-api"
}
run_proxy_step() {
  local upgrade=$1
  HOME="$proxy_home" \
  DOTFILES_DIR="$REPO" \
  UPGRADE="$upgrade" \
  CLI_PROXY_CONFIG="$proxy_config" \
  CLI_PROXY_AUTH_DIR="$proxy_auth" \
  PATH="$fake_bin:$proxy_home/.local/bin:/usr/bin:/bin" \
  FAKE_PROXY_MARKER="$TMP/proxy-version" \
  FAKE_PROXY_EXPECTED_VERSION="$FAKE_PROXY_EXPECTED_VERSION" \
  bash -c '
    set -euo pipefail
    source "$DOTFILES_DIR/headless/setup/lib.sh"
    needs_install() { return 1; }
    source "$DOTFILES_DIR/headless/setup/42-cli-proxy-api.sh"
  '
}
wait_dead() {
  local pid=$1 attempt
  for attempt in $(seq 1 50); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.02
  done
  return 1
}

make_fake_proxy v1
proxy_start_output="$(run_proxy_step 0 2>&1)"
assert_contains "proxy readiness uses the authenticated loopback endpoint" \
  'ready on 127.0.0.1:8317' "$proxy_start_output"
pid1="$(cat "$proxy_home/.local/state/cli-proxy-api/server.pid")"
assert_equal "proxy auth directory uses mode 0700" \
  '700' "$(stat -c %a "$proxy_auth")"
assert_equal "proxy config uses mode 0600" \
  '600' "$(stat -c %a "$proxy_config")"
run_proxy_step 0
pid2="$(cat "$proxy_home/.local/state/cli-proxy-api/server.pid")"
assert_equal "normal setup reuses the running proxy" "$pid1" "$pid2"

kill "$pid2"
wait_dead "$pid2"
run_proxy_step 0
pid3="$(cat "$proxy_home/.local/state/cli-proxy-api/server.pid")"
case "$pid3" in "$pid2") fail "stale proxy PID is replaced" ;; *) pass "stale proxy PID is replaced" ;; esac

kill "$pid3"
wait_dead "$pid3"
sleep 300 &
FOREIGN_PID=$!
printf '%s\n' "$FOREIGN_PID" > "$proxy_home/.local/state/cli-proxy-api/server.pid"
run_proxy_step 0
kill -0 "$FOREIGN_PID"
pass "foreign PID recorded in the state file is not signaled"
pid4="$(cat "$proxy_home/.local/state/cli-proxy-api/server.pid")"
case "$pid4" in "$FOREIGN_PID") fail "foreign PID metadata is replaced" ;; *) pass "foreign PID metadata is replaced" ;; esac

make_fake_proxy v2
run_proxy_step 1
pid5="$(cat "$proxy_home/.local/state/cli-proxy-api/server.pid")"
case "$pid5" in "$pid4") fail "upgrade restarts the proxy" ;; *) pass "upgrade restarts the proxy" ;; esac
wait_dead "$pid4"
pass "upgrade stops the validated old proxy"
assert_contains "upgrade starts the replacement binary" "v2" "$(cat "$TMP/proxy-version")"

summary
