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
  if [ -n "${PUBLISH_PID:-}" ]; then kill "$PUBLISH_PID" 2>/dev/null || true; fi
  if [ -n "${EARLY_START_PID:-}" ]; then kill "$EARLY_START_PID" 2>/dev/null || true; fi
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
cat > "$fake_bin/mv" <<'SH'
#!/usr/bin/env sh
destination=
for argument in "$@"; do destination=$argument; done
if [ -e "$FAKE_PROXY_INTERRUPT_PUBLISH_FILE" ]; then
  case "$destination" in
    */server.pid)
      kill -TERM "$PPID"
      sleep 0.1
      exit 143
      ;;
  esac
fi
exec /usr/bin/mv "$@"
SH
chmod +x "$fake_bin/mv"
cat > "$fake_bin/nohup" <<'SH'
#!/usr/bin/env sh
if [ -e "$FAKE_PROXY_INTERRUPT_BEFORE_IDENTITY_FILE" ]; then
  printf '%s\n' "$$" > "$FAKE_PROXY_EARLY_CHILD_PID_FILE"
  kill -TERM "$PPID"
  exec sleep 300
fi
exec /usr/bin/nohup "$@"
SH
chmod +x "$fake_bin/nohup"
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
  FAKE_PROXY_INTERRUPT_PUBLISH_FILE="$TMP/proxy-interrupt-publish" \
  FAKE_PROXY_INTERRUPT_BEFORE_IDENTITY_FILE="$TMP/proxy-interrupt-before-identity" \
  FAKE_PROXY_EARLY_CHILD_PID_FILE="$TMP/proxy-early-child.pid" \
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


touch "$TMP/proxy-interrupt-before-identity"
early_interrupt_output="$(run_proxy_step 0 2>&1 || true)"
EARLY_START_PID="$(cat "$TMP/proxy-early-child.pid")"
if wait_dead "$EARLY_START_PID"; then
  pass "pre-identity startup interruption stops the owned child"
else
  fail "pre-identity startup interruption stops the owned child"
  kill "$EARLY_START_PID" 2>/dev/null || true
  wait_dead "$EARLY_START_PID" || true
fi
if [ -e "$proxy_home/.local/state/cli-proxy-api/server.pid" ]; then
  fail "pre-identity startup interruption leaves no PID metadata"
else
  pass "pre-identity startup interruption leaves no PID metadata"
fi
rm -f "$TMP/proxy-interrupt-before-identity"

touch "$TMP/proxy-interrupt-publish"
publish_interrupt_output="$(run_proxy_step 0 2>&1 || true)"
PUBLISH_PID="$(cat "$TMP/proxy-child.pid")"
if wait_dead "$PUBLISH_PID"; then
  pass "interrupted PID publication stops the spawned child"
else
  fail "interrupted PID publication stops the spawned child"
  kill "$PUBLISH_PID" 2>/dev/null || true
  wait_dead "$PUBLISH_PID" || true
fi
if [ -e "$proxy_home/.local/state/cli-proxy-api/server.pid" ]; then
  fail "interrupted PID publication leaves no installed PID metadata"
else
  pass "interrupted PID publication leaves no installed PID metadata"
fi
if compgen -G "$proxy_home/.local/state/cli-proxy-api/server.pid.tmp.*" >/dev/null; then
  fail "interrupted PID publication removes temporary PID metadata"
else
  pass "interrupted PID publication removes temporary PID metadata"
fi
rm -f "$TMP/proxy-interrupt-publish"
run_proxy_step 0
publish_recovery_pid="$(cat "$proxy_home/.local/state/cli-proxy-api/server.pid")"
assert_equal "setup after interrupted publication tracks the replacement child" \
  "$publish_recovery_pid" "$(cat "$TMP/proxy-child.pid")"
if kill -0 "$publish_recovery_pid" 2>/dev/null; then
  pass "setup after interrupted publication starts one live tracked daemon"
else
  fail "setup after interrupted publication starts one live tracked daemon"
fi

for profile in arch headless; do
  for launcher in claude gpt_code monet; do
    if [ -x "$REPO/$profile/bin/$launcher" ]; then
      pass "$profile $launcher is a standalone executable"
    else
      fail "$profile $launcher is a standalone executable"
    fi
    assert_contains "$profile profile installs standalone $launcher" \
      ".local/bin/$launcher" "$(cat "$REPO/profiles/$profile.links")"
  done
done
if grep -Eq '^(claude|gpt_code|monet)\(\)' "$REPO/arch/zshrc"; then
  fail "Arch zshrc does not define Claude launchers"
else
  pass "Arch zshrc does not define Claude launchers"
fi
if grep -q 'headless/claude\.zsh' "$REPO/headless/zshrc"; then
  fail "headless zshrc does not source a Claude launcher module"
else
  pass "headless zshrc does not source a Claude launcher module"
fi

zhome="$TMP/zsh-home"
zbin="$TMP/zsh-bin"
zlog="$TMP/zsh-launch.log"
herdr_log="$TMP/herdr.log"
kitty_log="$TMP/kitty.log"
mkdir -p "$zhome/.claude-other/projects/p" "$zhome/.claude-monet/projects/p" "$zbin"
for launcher in claude claude-other claude-monet; do
  cat > "$zbin/$launcher" <<'SH'
#!/usr/bin/env sh
{
  printf 'launcher=%s\n' "${0##*/}"
  printf 'argc=%s\n' "$#"
  argument_index=1
  for argument do
    printf 'arg%s=%s\n' "$argument_index" "$argument"
    argument_index=$((argument_index + 1))
  done
  printf 'ANTHROPIC_BASE_URL=%s\n' "${ANTHROPIC_BASE_URL-}"
  printf 'ANTHROPIC_AUTH_TOKEN=%s\n' "${ANTHROPIC_AUTH_TOKEN-}"
  printf 'ENABLE_CLAUDEAI_MCP_SERVERS=%s\n' "${ENABLE_CLAUDEAI_MCP_SERVERS-}"
  printf 'DISABLE_TELEMETRY=%s\n' "${DISABLE_TELEMETRY-}"
  printf 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=%s\n' \
    "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC-}"
  printf 'ANTHROPIC_DEFAULT_OPUS_MODEL=%s\n' "${ANTHROPIC_DEFAULT_OPUS_MODEL-}"
  printf 'ANTHROPIC_DEFAULT_SONNET_MODEL=%s\n' "${ANTHROPIC_DEFAULT_SONNET_MODEL-}"
  printf 'ANTHROPIC_DEFAULT_HAIKU_MODEL=%s\n' "${ANTHROPIC_DEFAULT_HAIKU_MODEL-}"
  printf 'CLAUDE_CONFIG_DIR=%s:%s\n' \
    "${CLAUDE_CONFIG_DIR+x}" "${CLAUDE_CONFIG_DIR-}"
} >> "$CLAUDE_TEST_LOG"
exit "${CLAUDE_TEST_STATUS:-0}"
SH
  chmod +x "$zbin/$launcher"
done
cat > "$zbin/herdr" <<'SH'
#!/usr/bin/env sh

if [ "${1:-} ${2:-}" = "agent get" ] && [ -n "${HERDR_GET_STATE:-}" ]; then
  get_attempts=0
  if [ -f "$HERDR_GET_STATE" ]; then
    get_attempts="$(cat "$HERDR_GET_STATE")"
  fi
  get_attempts=$((get_attempts + 1))
  printf '%s\n' "$get_attempts" > "$HERDR_GET_STATE"
  if [ "$get_attempts" -le "${HERDR_GET_FAILURES:-0}" ]; then
    exit 1
  fi
fi

if [ "${1:-} ${2:-}" = "pane report-metadata" ] &&
  [ -n "${HERDR_REPORT_STATE:-}" ]; then
  report_attempts=0
  if [ -f "$HERDR_REPORT_STATE" ]; then
    report_attempts="$(cat "$HERDR_REPORT_STATE")"
  fi
  report_attempts=$((report_attempts + 1))
  printf '%s\n' "$report_attempts" > "$HERDR_REPORT_STATE"
  if [ "$report_attempts" -le "${HERDR_REPORT_FAILURES:-0}" ]; then
    exit 1
  fi
fi
printf '%s\n' "$*" >> "$HERDR_TEST_LOG"

exit 0
SH
cat > "$zbin/kitty" <<'SH'
#!/usr/bin/env sh
printf '%s\n' "$*" >> "$KITTY_TEST_LOG"
exit 99
SH
chmod +x "$zbin/herdr" "$zbin/kitty"

unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ENABLE_CLAUDEAI_MCP_SERVERS
unset DISABLE_TELEMETRY CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
unset ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL
unset ANTHROPIC_DEFAULT_HAIKU_MODEL CLAUDE_CONFIG_DIR

run_claude_zsh() {
  local launcher=$1
  shift
  HOME="$zhome" \
  PATH="$REPO/headless/bin:$zbin:/usr/bin:/bin" \
  CLAUDE_TEST_LOG="$zlog" \
  HERDR_TEST_LOG="$herdr_log" \
  KITTY_TEST_LOG="$kitty_log" \
  "$REPO/headless/bin/$launcher" "$@"
}
wait_for_herdr_metadata() {
  local expected=$1 attempt contents
  for attempt in $(seq 1 50); do
    contents="$(cat "$herdr_log" 2>/dev/null || true)"
    case "$contents" in
      *"$expected"*) return 0 ;;
    esac
    sleep 0.02
  done
  return 1
}

: > "$zlog"
: > "$herdr_log"
: > "$kitty_log"
gpt_output="$(HERDR_PANE_ID=pane-gpt run_claude_zsh gpt_code --verbose "two words")"
assert_equal "gpt_code emits only the exact Gruvbox Dark OSC colors in Herdr" \
  $'\033]10;#ebdbb2\033\\\033]11;#282828\033\\' "$gpt_output"
assert_equal "gpt_code uses the generated profile launcher, arguments, and exact proxy environment" \
  "launcher=claude-other
argc=4
arg1=--model
arg2=gpt-5.6-sol
arg3=--verbose
arg4=two words
ANTHROPIC_BASE_URL=http://127.0.0.1:8317
ANTHROPIC_AUTH_TOKEN=coder-local
ENABLE_CLAUDEAI_MCP_SERVERS=false
DISABLE_TELEMETRY=1
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
ANTHROPIC_DEFAULT_OPUS_MODEL=gpt-5.6-sol
ANTHROPIC_DEFAULT_SONNET_MODEL=gpt-5.6-terra
ANTHROPIC_DEFAULT_HAIKU_MODEL=gpt-5.6-luna
CLAUDE_CONFIG_DIR=:" \
  "$(cat "$zlog")"
if wait_for_herdr_metadata \
  'pane report-metadata pane-gpt --source user:zsh-claude-display --agent claude --display-agent gpt_code'; then
  pass "gpt_code reports exact Herdr display metadata"
else
  fail "gpt_code reports exact Herdr display metadata"
fi

: > "$zlog"
: > "$herdr_log"
monet_output="$(HERDR_PANE_ID=pane-monet run_claude_zsh monet --resume "monet session")"
assert_equal "monet emits only the exact Darcula OSC colors in Herdr" \
  $'\033]10;#adadad\033\\\033]11;#202020\033\\' "$monet_output"
assert_equal "monet is a thin generated-profile launcher without reconstructed profile environment" \
  "launcher=claude-monet
argc=2
arg1=--resume
arg2=monet session
ANTHROPIC_BASE_URL=
ANTHROPIC_AUTH_TOKEN=
ENABLE_CLAUDEAI_MCP_SERVERS=
DISABLE_TELEMETRY=
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=
ANTHROPIC_DEFAULT_OPUS_MODEL=
ANTHROPIC_DEFAULT_SONNET_MODEL=
ANTHROPIC_DEFAULT_HAIKU_MODEL=
CLAUDE_CONFIG_DIR=:" \
  "$(cat "$zlog")"
if wait_for_herdr_metadata \
  'pane report-metadata pane-monet --source user:zsh-claude-display --agent claude --display-agent monet'; then
  pass "monet reports exact Herdr display metadata"
else
  fail "monet reports exact Herdr display metadata"
fi

herdr_get_state="$TMP/herdr-get-attempts"
herdr_report_state="$TMP/herdr-report-attempts"
rm -f "$herdr_get_state" "$herdr_report_state"
: > "$herdr_log"
HERDR_GET_FAILURES=2 \
HERDR_REPORT_FAILURES=1 \
HERDR_GET_STATE="$herdr_get_state" \
HERDR_REPORT_STATE="$herdr_report_state" \
HERDR_PANE_ID=pane-retry \
  run_claude_zsh monet retry >/dev/null
if wait_for_herdr_metadata \
  'pane report-metadata pane-retry --source user:zsh-claude-display --agent claude --display-agent monet'; then
  pass "Herdr metadata helper eventually reports after controlled failures"
else
  fail "Herdr metadata helper eventually reports after controlled failures"
fi
herdr_get_attempts="$(cat "$herdr_get_state" 2>/dev/null || printf 0)"
herdr_report_attempts="$(cat "$herdr_report_state" 2>/dev/null || printf 0)"
assert_equal "Herdr metadata helper retries failed agent detection" \
  4 "$herdr_get_attempts"
assert_equal "Herdr metadata helper retries failed metadata reports" \
  2 "$herdr_report_attempts"

: > "$zlog"
touch "$zhome/.claude-other/projects/p/gpt-session.jsonl"
run_claude_zsh claude --resume gpt-session --verbose
assert_contains "GPT-only resume dispatch uses gpt_code with all arguments" \
  "launcher=claude-other
argc=5
arg1=--model
arg2=gpt-5.6-sol
arg3=--resume
arg4=gpt-session
arg5=--verbose" "$(cat "$zlog")"

: > "$zlog"
touch "$zhome/.claude-monet/projects/p/monet-session.jsonl"
run_claude_zsh claude --resume monet-session --verbose
assert_contains "Monet-only resume dispatch uses monet with all arguments" \
  "launcher=claude-monet
argc=3
arg1=--resume
arg2=monet-session
arg3=--verbose" "$(cat "$zlog")"

if CLAUDE_TEST_STATUS=21 HERDR_PANE_ID= \
  run_claude_zsh gpt_code status-direct >/dev/null; then
  direct_gpt_status=0
else
  direct_gpt_status=$?
fi
assert_equal "direct gpt_code returns the generated launcher status" \
  21 "$direct_gpt_status"

if CLAUDE_TEST_STATUS=22 HERDR_PANE_ID= \
  run_claude_zsh monet status-direct >/dev/null; then
  direct_monet_status=0
else
  direct_monet_status=$?
fi
assert_equal "direct monet returns the generated launcher status" \
  22 "$direct_monet_status"

if CLAUDE_TEST_STATUS=23 HERDR_PANE_ID= \
  run_claude_zsh claude --resume gpt-session >/dev/null; then
  resumed_gpt_status=0
else
  resumed_gpt_status=$?
fi
assert_equal "GPT resume dispatch returns the generated launcher status" \
  23 "$resumed_gpt_status"

if CLAUDE_TEST_STATUS=24 HERDR_PANE_ID= \
  run_claude_zsh claude --resume monet-session >/dev/null; then
  resumed_monet_status=0
else
  resumed_monet_status=$?
fi
assert_equal "Monet resume dispatch returns the generated launcher status" \
  24 "$resumed_monet_status"

: > "$zlog"
run_claude_zsh claude --resume default-session
assert_contains "unknown resume ID falls through to external Claude" \
  "launcher=claude
argc=2
arg1=--resume
arg2=default-session" "$(cat "$zlog")"

: > "$zlog"
run_claude_zsh claude --resume project/session.jsonl
assert_contains "resume path falls through to external Claude" \
  "launcher=claude
argc=2
arg1=--resume
arg2=project/session.jsonl" "$(cat "$zlog")"

: > "$zlog"
CLAUDE_CONFIG_DIR="$zhome/custom" run_claude_zsh claude --resume gpt-session
assert_contains "explicit config dir bypasses resume dispatch" \
  "launcher=claude
argc=2
arg1=--resume
arg2=gpt-session" "$(cat "$zlog")"
assert_contains "external Claude receives the explicit config dir unchanged" \
  "CLAUDE_CONFIG_DIR=x:$zhome/custom" "$(cat "$zlog")"

: > "$zlog"
run_claude_zsh claude --verbose --resume gpt-session
assert_contains "unsupported resume position falls through to external Claude" \
  "launcher=claude
argc=3
arg1=--verbose
arg2=--resume
arg3=gpt-session" "$(cat "$zlog")"

: > "$zlog"
run_claude_zsh claude --resume
assert_contains "empty resume ID falls through to external Claude" \
  "launcher=claude
argc=1
arg1=--resume" "$(cat "$zlog")"

touch "$zhome/.claude-monet/projects/p/collision.jsonl"
touch "$zhome/.claude-other/projects/p/collision.jsonl"
: > "$zlog"
if run_claude_zsh claude --resume collision > "$TMP/collision.out" 2> "$TMP/collision.err"; then
  fail "duplicate session stores fail"
else
  pass "duplicate session stores fail"
fi
assert_equal "duplicate session error clearly names both stores" \
  'claude: session collision exists in both gpt_code and monet stores' \
  "$(cat "$TMP/collision.err")"
assert_equal "duplicate session stores do not launch Claude" "" "$(cat "$zlog")"

: > "$zlog"
plain_gpt_output="$(HERDR_PANE_ID= run_claude_zsh gpt_code plain)"
assert_equal "non-Herdr gpt_code emits no OSC output" "" "$plain_gpt_output"
assert_contains "non-Herdr gpt_code still uses the generated launcher" \
  "launcher=claude-other
argc=3
arg1=--model
arg2=gpt-5.6-sol
arg3=plain" "$(cat "$zlog")"

: > "$zlog"
plain_monet_output="$(HERDR_PANE_ID= run_claude_zsh monet plain)"
assert_equal "non-Herdr monet emits no OSC output" "" "$plain_monet_output"
assert_contains "non-Herdr monet still uses the generated launcher" \
  "launcher=claude-monet
argc=1
arg1=plain" "$(cat "$zlog")"
if [ -s "$kitty_log" ]; then
  fail "headless launchers never invoke Kitty"
else
  pass "headless launchers never invoke Kitty"
fi

summary
