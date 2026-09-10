#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
# shellcheck source=tests/lib.sh
source "$HERE/lib.sh"

TMP="$(mktemp -d)"
cleanup() {
  if [ -n "${LEGACY_PID:-}" ]; then kill "$LEGACY_PID" 2>/dev/null || true; fi
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

assert_path_absent() { # description, path
  if [ -e "$2" ] || [ -L "$2" ]; then
    fail "$1"
  else
    pass "$1"
  fi
}

run_retirement_step() {
  local home=$1 dotfiles_dir=${2:-$REPO} command_path=${3:-/usr/bin:/bin}
  HOME="$home" DOTFILES_DIR="$dotfiles_dir" REPO_UNDER_TEST="$REPO" \
    PATH="$command_path" bash -c '
      set -euo pipefail
      source "$REPO_UNDER_TEST/headless/setup/lib.sh"
      source "$REPO_UNDER_TEST/headless/setup/41-retire-coder-gpt.sh"
    '
}

pid_is_alive() {
  local pid=$1 line rest
  kill -0 "$pid" 2>/dev/null || return 1
  IFS= read -r line < "/proc/$pid/stat" 2>/dev/null || return 1
  rest=${line##*) }
  [ "${rest%% *}" != Z ]
}

wait_dead() {
  local pid=$1
  for _ in $(seq 1 100); do
    pid_is_alive "$pid" || return 0
    sleep 0.02
  done
  return 1
}

wait_for_argument() {
  local pid=$1 expected=$2 argument
  local -a argv=()
  for _ in $(seq 1 100); do
    argv=()
    mapfile -d '' -t argv < "/proc/$pid/cmdline" 2>/dev/null || true
    for argument in "${argv[@]}"; do
      [ "$argument" = "$expected" ] && return 0
    done
    sleep 0.02
  done
  return 1
}

for retired_path in \
  headless/setup/41-claude-other-settings.sh \
  headless/setup/42-cli-proxy-api.sh \
  headless/cli-proxy-api.yaml \
  headless/bin/gpt_code; do
  if [ -e "$REPO/$retired_path" ]; then
    fail "$retired_path is retired"
  else
    pass "$retired_path is retired"
  fi
done
assert_not_contains "headless profile no longer links a proxy config" \
  '.config/cli-proxy-api/config.yaml' "$(cat "$REPO/profiles/headless.links")"
assert_not_contains "headless profile no longer shadows the template gpt_code" \
  '.local/bin/gpt_code' "$(cat "$REPO/profiles/headless.links")"

retire_home="$TMP/retire-home"
legacy_target="$retire_home/.local/opt/cli-proxy-api-v1/cli-proxy-api"
legacy_config="$retire_home/.config/cli-proxy-api/config.yaml"
legacy_clone="$retire_home/.config/coderv2/dotfiles"
mkdir -p "$(dirname "$legacy_target")" "$(dirname "$legacy_config")" \
  "$retire_home/.local/bin" "$retire_home/.local/state/cli-proxy-api" "$legacy_clone"
ln -s .config/coderv2/dotfiles "$retire_home/dotfiles"
cat > "$legacy_target" <<'SH'
#!/usr/bin/env bash
trap 'exit 0' TERM INT
while :; do sleep 1; done
SH
chmod +x "$legacy_target"
ln -s "$legacy_target" "$retire_home/.local/bin/cli-proxy-api"
ln -s "$legacy_clone/headless/cli-proxy-api.yaml" "$legacy_config"
ln -s "$legacy_clone/headless/bin/gpt_code" "$retire_home/.local/bin/gpt_code"
"$retire_home/.local/bin/cli-proxy-api" --config "$legacy_config" &
LEGACY_PID=$!
printf '%s\n' "$LEGACY_PID" > "$retire_home/.local/state/cli-proxy-api/server.pid"
if ! wait_for_argument "$LEGACY_PID" "$legacy_config"; then
  fail "fake legacy proxy reaches its daemon command line"
  kill -KILL "$LEGACY_PID" 2>/dev/null || true
fi
run_retirement_step "$retire_home" "$retire_home/dotfiles"
if wait_dead "$LEGACY_PID"; then
  pass "retirement stops the old proxy daemon"
else
  fail "retirement stops the old proxy daemon"
  kill -KILL "$LEGACY_PID" 2>/dev/null || true
fi
wait "$LEGACY_PID" 2>/dev/null || true
LEGACY_PID=
assert_path_absent "retirement removes the old proxy executable link" \
  "$retire_home/.local/bin/cli-proxy-api"
assert_path_absent "retirement removes the old proxy config link" "$legacy_config"
assert_path_absent "retirement removes the old headless gpt_code link" \
  "$retire_home/.local/bin/gpt_code"
assert_path_absent "retirement removes the stopped daemon PID" \
  "$retire_home/.local/state/cli-proxy-api/server.pid"
handoff_pending="$retire_home/.local/state/dotfiles/coder-gpt-handoff-pending"
if [ -e "$handoff_pending" ]; then
  pass "retirement records a handoff when ai-auth is unavailable"
else
  fail "retirement records a handoff when ai-auth is unavailable"
fi

handoff_bin="$TMP/handoff-bin"
handoff_log="$TMP/handoff.log"
handoff_fail="$TMP/handoff-fail"
mkdir -p "$handoff_bin"
cat > "$handoff_bin/ai-auth" <<'SH'
#!/usr/bin/env sh
printf '%s\n' "$*" >> "$HANDOFF_LOG"
[ ! -e "$HANDOFF_FAIL" ]
SH
chmod +x "$handoff_bin/ai-auth"
touch "$handoff_fail"
HANDOFF_LOG="$handoff_log" HANDOFF_FAIL="$handoff_fail" \
  run_retirement_step "$retire_home" "$retire_home/dotfiles" "$handoff_bin:/usr/bin:/bin"
if [ -e "$handoff_pending" ]; then
  pass "a failed template handoff remains pending"
else
  fail "a failed template handoff remains pending"
fi
rm -f "$handoff_fail"
HANDOFF_LOG="$handoff_log" HANDOFF_FAIL="$handoff_fail" \
  run_retirement_step "$retire_home" "$retire_home/dotfiles" "$handoff_bin:/usr/bin:/bin"
assert_path_absent "a successful template handoff clears the pending marker" \
  "$handoff_pending"
assert_equal "pending handoff retries the template proxy start" \
  "cli-proxy start
cli-proxy start" "$(cat "$handoff_log")"

user_home="$TMP/user-home"
user_proxy="$user_home/.local/opt/cli-proxy-api-custom/cli-proxy-api"
mkdir -p "$user_home/.local/bin" "$user_home/.config/cli-proxy-api" \
  "$(dirname "$user_proxy")"
ln -s "$user_proxy" "$user_home/.local/bin/cli-proxy-api"
ln -s "$TMP/user-config" "$user_home/.config/cli-proxy-api/config.yaml"
ln -s "$TMP/user-gpt" "$user_home/.local/bin/gpt_code"
run_retirement_step "$user_home"
assert_equal "retirement leaves a user-owned proxy link alone" \
  "$user_proxy" "$(readlink "$user_home/.local/bin/cli-proxy-api")"
assert_equal "retirement leaves a user-owned config link alone" \
  "$TMP/user-config" "$(readlink "$user_home/.config/cli-proxy-api/config.yaml")"
assert_equal "retirement leaves a user-owned gpt_code link alone" \
  "$TMP/user-gpt" "$(readlink "$user_home/.local/bin/gpt_code")"

for launcher in claude gpt_code monet; do
  if [ -x "$REPO/arch/bin/$launcher" ]; then
    pass "arch $launcher is a standalone executable"
  else
    fail "arch $launcher is a standalone executable"
  fi
  assert_contains "arch profile installs standalone $launcher" \
    ".local/bin/$launcher" "$(cat "$REPO/profiles/arch.links")"
done
for launcher in claude monet; do
  if [ -x "$REPO/headless/bin/$launcher" ]; then
    pass "headless $launcher is a standalone executable"
  else
    fail "headless $launcher is a standalone executable"
  fi
  assert_contains "headless profile installs standalone $launcher" \
    ".local/bin/$launcher" "$(cat "$REPO/profiles/headless.links")"
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
mkdir -p "$zhome/.claude-gpt/projects/p" "$zhome/.claude-monet/projects/p" "$zbin"
for launcher in claude claude-monet gpt_code; do
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

unset CLAUDE_CONFIG_DIR

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
  local expected=$1 contents
  for _ in $(seq 1 50); do
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
monet_output="$(HERDR_PANE_ID=pane-monet run_claude_zsh monet --resume "monet session")"
assert_equal "monet emits only the exact Darcula OSC colors in Herdr" \
  $'\033]10;#adadad\033\\\033]11;#202020\033\\' "$monet_output"
assert_equal "monet is a thin generated-profile launcher" \
  "launcher=claude-monet
argc=2
arg1=--resume
arg2=monet session
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
assert_equal "Herdr metadata helper retries failed agent detection" \
  4 "$(cat "$herdr_get_state" 2>/dev/null || printf 0)"
assert_equal "Herdr metadata helper retries failed metadata reports" \
  2 "$(cat "$herdr_report_state" 2>/dev/null || printf 0)"

: > "$zlog"
touch "$zhome/.claude-gpt/projects/p/gpt-session.jsonl"
run_claude_zsh claude --resume gpt-session --verbose
assert_contains "GPT-only resume dispatch uses the template launcher with all arguments" \
  "launcher=gpt_code
argc=3
arg1=--resume
arg2=gpt-session
arg3=--verbose" "$(cat "$zlog")"

: > "$zlog"
touch "$zhome/.claude-monet/projects/p/monet-session.jsonl"
run_claude_zsh claude --resume monet-session --verbose
assert_contains "Monet-only resume dispatch uses monet with all arguments" \
  "launcher=claude-monet
argc=3
arg1=--resume
arg2=monet-session
arg3=--verbose" "$(cat "$zlog")"

if CLAUDE_TEST_STATUS=22 HERDR_PANE_ID='' \
  run_claude_zsh monet status-direct >/dev/null; then
  direct_monet_status=0
else
  direct_monet_status=$?
fi
assert_equal "direct monet returns the generated launcher status" \
  22 "$direct_monet_status"

if CLAUDE_TEST_STATUS=23 HERDR_PANE_ID='' \
  run_claude_zsh claude --resume gpt-session >/dev/null; then
  resumed_gpt_status=0
else
  resumed_gpt_status=$?
fi
assert_equal "GPT resume dispatch returns the template launcher status" \
  23 "$resumed_gpt_status"

if CLAUDE_TEST_STATUS=24 HERDR_PANE_ID='' \
  run_claude_zsh claude --resume monet-session >/dev/null; then
  resumed_monet_status=0
else
  resumed_monet_status=$?
fi
assert_equal "Monet resume dispatch returns the generated launcher status" \
  24 "$resumed_monet_status"

touch "$zhome/.claude-gpt/projects/p/collision.jsonl"
touch "$zhome/.claude-monet/projects/p/collision.jsonl"
: > "$zlog"
if run_claude_zsh claude --resume collision > "$TMP/collision.out" 2> "$TMP/collision.err"; then
  fail "duplicate GPT and Monet session stores fail"
else
  pass "duplicate GPT and Monet session stores fail"
fi
assert_equal "duplicate session error clearly names both stores" \
  'claude: session collision exists in both gpt_code and monet stores' \
  "$(cat "$TMP/collision.err")"
assert_equal "duplicate session stores do not launch Claude" "" "$(cat "$zlog")"

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
CLAUDE_CONFIG_DIR="$zhome/custom" run_claude_zsh claude --resume monet-session
assert_contains "explicit config dir bypasses resume dispatch" \
  "launcher=claude
argc=2
arg1=--resume
arg2=monet-session" "$(cat "$zlog")"
assert_contains "external Claude receives the explicit config dir unchanged" \
  "CLAUDE_CONFIG_DIR=x:$zhome/custom" "$(cat "$zlog")"

: > "$zlog"
run_claude_zsh claude --verbose --resume monet-session
assert_contains "unsupported resume position falls through to external Claude" \
  "launcher=claude
argc=3
arg1=--verbose
arg2=--resume
arg3=monet-session" "$(cat "$zlog")"

: > "$zlog"
run_claude_zsh claude --resume
assert_contains "empty resume ID falls through to external Claude" \
  "launcher=claude
argc=1
arg1=--resume" "$(cat "$zlog")"

: > "$zlog"
plain_monet_output="$(HERDR_PANE_ID='' run_claude_zsh monet plain)"
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
