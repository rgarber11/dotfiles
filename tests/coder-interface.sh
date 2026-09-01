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
  if [ -n "${LOGIN_PID:-}" ]; then kill "$LOGIN_PID" 2>/dev/null || true; fi
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
[ ! -e "$FAKE_PROXY_UNHEALTHY_FILE" ] || exit 1
[ -f "$FAKE_PROXY_MARKER" ] &&
  [ "$(cat "$FAKE_PROXY_MARKER")" = "$FAKE_PROXY_EXPECTED_VERSION" ] ||
  exit 1
if [ -e "$FAKE_PROXY_KILL_DURING_PROBE_FILE" ]; then
  probe_pid="$(cat "$FAKE_PROXY_CHILD_PID_FILE")"
  kill -TERM "$probe_pid"
  for attempt in $(seq 1 100); do
    kill -0 "$probe_pid" 2>/dev/null || break
    sleep 0.02
  done
fi
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
printf '%s\n' "\$\$" > "\$FAKE_PROXY_CHILD_PID_FILE"
lock_status=clean
for fd in /proc/"\$\$"/fd/*; do
  case "\$(readlink "\$fd" 2>/dev/null || true)" in
    */setup.lock) lock_status=inherited ;;
  esac
done
printf '%s\n' "\$lock_status" > "\$FAKE_PROXY_LOCK_STATUS_FILE"
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
  FAKE_PROXY_CHILD_PID_FILE="$TMP/proxy-child.pid" \
  FAKE_PROXY_UNHEALTHY_FILE="$TMP/proxy-unhealthy" \
  FAKE_PROXY_LOCK_STATUS_FILE="$TMP/proxy-lock-status" \
  FAKE_PROXY_KILL_DURING_PROBE_FILE="$TMP/proxy-kill-during-probe" \
  bash -c '
    set -euo pipefail
    source "$DOTFILES_DIR/headless/setup/lib.sh"
    latest_release_tag() { return 0; }
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

kill "$pid5"
wait_dead "$pid5"
FAKE_PROXY_MARKER="$TMP/proxy-version" \
  FAKE_PROXY_CHILD_PID_FILE="$TMP/login-child.pid" \
  FAKE_PROXY_LOCK_STATUS_FILE="$TMP/login-lock-status" \
  "$proxy_home/.local/bin/cli-proxy-api" \
  --config "$proxy_config" --codex-device-login >/dev/null 2>&1 &
LOGIN_PID=$!
printf '%s\n' "$LOGIN_PID" > "$proxy_home/.local/state/cli-proxy-api/server.pid"
run_proxy_step 0
login_replacement_pid="$(cat "$proxy_home/.local/state/cli-proxy-api/server.pid")"
if kill -0 "$LOGIN_PID" 2>/dev/null; then
  pass "login-mode process is not signaled"
else
  fail "login-mode process is not signaled"
fi
case "$login_replacement_pid" in
  "$LOGIN_PID") fail "login-mode process is not reused as the daemon" ;;
  *) pass "login-mode process is not reused as the daemon" ;;
esac

printf '%s\n' unhealthy > "$TMP/proxy-version"
run_proxy_step 0
unhealthy_replacement_pid="$(cat "$proxy_home/.local/state/cli-proxy-api/server.pid")"
case "$unhealthy_replacement_pid" in
  "$login_replacement_pid") fail "unhealthy matching daemon is restarted" ;;
  *) pass "unhealthy matching daemon is restarted" ;;
esac
if wait_dead "$login_replacement_pid"; then
  pass "unhealthy matching daemon is stopped"
else
  fail "unhealthy matching daemon is stopped"
  kill "$login_replacement_pid" 2>/dev/null || true
  wait_dead "$login_replacement_pid" || true
  rm -f "$proxy_home/.local/state/cli-proxy-api/server.pid"
  run_proxy_step 0
fi


kill "$unhealthy_replacement_pid"
wait_dead "$unhealthy_replacement_pid"
touch "$TMP/proxy-unhealthy"
failed_start_output="$(run_proxy_step 0 2>&1)"
failed_start_pid="$(cat "$TMP/proxy-child.pid")"
assert_contains "live unready child reports a readiness warning" \
  'did not become ready' "$failed_start_output"
if [ -e "$proxy_home/.local/state/cli-proxy-api/server.pid" ]; then
  fail "live unready child PID metadata is removed"
else
  pass "live unready child PID metadata is removed"
fi
if wait_dead "$failed_start_pid"; then
  pass "live unready child is stopped"
else
  fail "live unready child is stopped"
  kill "$failed_start_pid" 2>/dev/null || true
  wait_dead "$failed_start_pid" || true
fi
rm -f "$TMP/proxy-unhealthy"
run_proxy_step 0
lock_test_pid="$(cat "$proxy_home/.local/state/cli-proxy-api/server.pid")"
assert_equal "daemon child does not inherit the setup lock" \
  clean "$(cat "$TMP/proxy-lock-status")"

kill "$lock_test_pid"
wait_dead "$lock_test_pid"
touch "$TMP/proxy-kill-during-probe"
probe_race_output="$(run_proxy_step 0 2>&1)"
probe_race_pid="$(cat "$TMP/proxy-child.pid")"
assert_contains "dead new child cannot pass readiness via another listener" \
  'did not become ready' "$probe_race_output"
if [ -e "$proxy_home/.local/state/cli-proxy-api/server.pid" ]; then
  fail "dead probe-race child PID metadata is removed"
else
  pass "dead probe-race child PID metadata is removed"
fi
wait_dead "$probe_race_pid"
pass "probe-race child is dead"
rm -f "$TMP/proxy-kill-during-probe"

cat > "$fake_bin/cli-proxy-api" <<'SH'
#!/usr/bin/env sh
exit 0
SH
chmod +x "$fake_bin/cli-proxy-api"
run_install_probe() {
  local home=$1 upgrade=$2 call_file=$3
  HOME="$home" \
  DOTFILES_DIR="$REPO" \
  UPGRADE="$upgrade" \
  PATH="$fake_bin:/usr/bin:/bin" \
  INSTALL_CALL_FILE="$call_file" \
  bash -c '
    set -euo pipefail
    source "$DOTFILES_DIR/headless/setup/lib.sh"
    latest_release_tag() {
      [ "$1" = router-for-me/CLIProxyAPI ]
      printf "%s\n" v9
    }
    install_tarball() {
      printf "%s|%s|%s|%s|%s\n" "$1" "$2" "$3" "$4" "$5" > "$INSTALL_CALL_FILE"
    }
    source "$DOTFILES_DIR/headless/setup/42-cli-proxy-api.sh"
  ' >/dev/null 2>&1
}

missing_managed_home="$TMP/install-missing-managed"
missing_managed_call="$TMP/install-missing-managed.call"
run_install_probe "$missing_managed_home" 0 "$missing_managed_call"
if [ -f "$missing_managed_call" ]; then
  assert_equal "managed-path absence triggers the exact release install" \
    'cli-proxy-api|v9|https://github.com/router-for-me/CLIProxyAPI/releases/download/v9/CLIProxyAPI_9_linux_amd64.tar.gz|cli-proxy-api|0' \
    "$(cat "$missing_managed_call")"
else
  fail "managed-path absence triggers the exact release install"
fi

upgrade_install_home="$TMP/install-upgrade"
mkdir -p "$upgrade_install_home/.local/bin"
cp "$fake_bin/cli-proxy-api" "$upgrade_install_home/.local/bin/cli-proxy-api"
upgrade_install_call="$TMP/install-upgrade.call"
run_install_probe "$upgrade_install_home" 1 "$upgrade_install_call"
if [ -f "$upgrade_install_call" ]; then
  pass "upgrade still triggers the managed release install"
else
  fail "upgrade still triggers the managed release install"
fi

summary
