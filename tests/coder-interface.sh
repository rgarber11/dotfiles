#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
# shellcheck source=tests/lib.sh
source "$HERE/lib.sh"

TMP="$(mktemp -d)"
cleanup() {
  if [ -n "${LEGACY_PID:-}" ]; then kill "$LEGACY_PID" 2>/dev/null || true; fi
  if [ -n "${T3UP_LISTENER_PID:-}" ]; then kill "$T3UP_LISTENER_PID" 2>/dev/null || true; fi
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


# T3 provider seeding. ai-auth is stubbed with the exact table layout the
# template prints, including a "not logged in" row whose status also ends in
# "logged in".
run_t3_seed_step() {
  local home=$1 command_path=${2:-$t3_bin:/usr/bin:/bin}
  HOME="$home" REPO_UNDER_TEST="$REPO" PATH="$command_path" bash -c '
      set -euo pipefail
      source "$REPO_UNDER_TEST/headless/setup/lib.sh"
      source "$REPO_UNDER_TEST/headless/setup/55-t3code-providers.sh"
    '
}
t3_instances() {   # $1 = home; prints "id homePath displayName enabled" per instance
  jq -r '.providerInstances // {} | to_entries[]
    | "\(.key) \(.value.config.homePath) \(.value.displayName) \(.value.enabled)"' \
    "$1/.t3/userdata/settings.json" | sort
}

t3_bin="$TMP/t3-bin"
mkdir -p "$t3_bin"
cat > "$t3_bin/ai-auth" <<'SH'
#!/usr/bin/env sh
[ "$*" = "claude list" ] || exit 2
[ -e "${T3_AI_AUTH_FAIL:-/nonexistent}" ] && exit 1
cat <<'TABLE'
profile      command                account                      plan     status
default      claude                 richard@voiceerp.ai          team     logged in
monet        claude-monet           richard@voiceerp.ai          max      logged in
other        claude-other           -                            -        not logged in
shannon      claude-shannon         richard@laborbeam.com        max      logged in
renamed      claude-renamed         richard@voiceerp.ai          max      logged in
nohome       claude-nohome          richard@voiceerp.ai          max      logged in
TABLE
SH
chmod +x "$t3_bin/ai-auth"

t3_home="$TMP/t3-home"
mkdir -p "$t3_home/.t3/userdata"
for profile in monet other shannon renamed; do mkdir -p "$t3_home/.claude-$profile"; done
cat > "$t3_home/.t3/userdata/settings.json" <<'JSON'
{
  "providers": { "cursor": { "enabled": false } },
  "providerInstances": {
    "claudeAgent_monet": {
      "driver": "claudeAgent", "displayName": "My Monet", "enabled": false,
      "config": { "homePath": "~/.claude-monet" }
    },
    "claude_custom": {
      "driver": "claudeAgent", "displayName": "Custom", "enabled": true,
      "config": { "homePath": "~/.claude-renamed" }
    }
  }
}
JSON
run_t3_seed_step "$t3_home"
assert_equal "T3 seeding adds only missing logged-in ai-auth profiles" \
  "claudeAgent_monet ~/.claude-monet My Monet false
claudeAgent_shannon ~/.claude-shannon Shannon true
claude_custom ~/.claude-renamed Custom true" "$(t3_instances "$t3_home")"
assert_equal "T3 seeding keeps unrelated settings" \
  false "$(jq -r '.providers.cursor.enabled' "$t3_home/.t3/userdata/settings.json")"
assert_equal "T3 seeded instances use the claudeAgent driver" \
  claudeAgent "$(jq -r '.providerInstances.claudeAgent_shannon.driver' "$t3_home/.t3/userdata/settings.json")"

t3_before="$(cat "$t3_home/.t3/userdata/settings.json")"
t3_second="$(run_t3_seed_step "$t3_home" 2>&1)"
assert_equal "T3 seeding is idempotent" \
  "$t3_before" "$(cat "$t3_home/.t3/userdata/settings.json")"
assert_not_contains "T3 seeding reports nothing when nothing changed" "t3:" "$t3_second"

t3_fresh="$TMP/t3-fresh"
mkdir -p "$t3_fresh/.claude-shannon"
run_t3_seed_step "$t3_fresh"
assert_equal "T3 seeding creates settings on a fresh home" \
  "claudeAgent_shannon ~/.claude-shannon Shannon true" "$(t3_instances "$t3_fresh")"

t3_noauth="$TMP/t3-noauth"
mkdir -p "$t3_noauth/.claude-shannon"
run_t3_seed_step "$t3_noauth" /usr/bin:/bin
assert_path_absent "T3 seeding without ai-auth writes nothing" \
  "$t3_noauth/.t3/userdata/settings.json"

touch "$TMP/t3-ai-auth-fail"
t3_failhome="$TMP/t3-failhome"
mkdir -p "$t3_failhome/.claude-shannon"
if T3_AI_AUTH_FAIL="$TMP/t3-ai-auth-fail" run_t3_seed_step "$t3_failhome" 2>/dev/null; then
  pass "a failing ai-auth does not abort install.sh"
else
  fail "a failing ai-auth does not abort install.sh"
fi
assert_path_absent "a failing ai-auth writes nothing" \
  "$t3_failhome/.t3/userdata/settings.json"

t3_badjson="$TMP/t3-badjson"
mkdir -p "$t3_badjson/.t3/userdata" "$t3_badjson/.claude-shannon"
printf '{ not json' > "$t3_badjson/.t3/userdata/settings.json"
if run_t3_seed_step "$t3_badjson" 2>/dev/null; then
  pass "unreadable T3 settings do not abort install.sh"
else
  fail "unreadable T3 settings do not abort install.sh"
fi
assert_equal "unreadable T3 settings are left untouched" \
  '{ not json' "$(cat "$t3_badjson/.t3/userdata/settings.json")"


# T3 project registration. The t3 stub mimics `t3 project add`: it refuses a
# path that already has a project with ProjectAlreadyExistsError, exactly as
# t3 0.0.44 does. The checkouts are real git repos, since the step picks them
# by their origin URL.
t3proj_bin="$TMP/t3proj-bin"
t3proj_db="$TMP/t3proj.db"
t3proj_fail="$TMP/t3proj-fail"
mkdir -p "$t3proj_bin"
cat > "$t3proj_bin/t3" <<'SH'
#!/usr/bin/env sh
[ "$1 $2" = "project add" ] || exit 2
if [ -e "$T3_STUB_FAIL" ]; then
  echo "[00:00:00.000] ERROR (#4): SqlError: disk I/O error"
  echo "    at file:///t3:1:1"
  exit 1
fi
if grep -qxF "$3" "$T3_STUB_DB" 2>/dev/null; then
  echo "[00:00:00.000] ERROR (#4): ProjectAlreadyExistsError: An active project already exists for '$3'."
  echo "    at file:///t3:1:1"
  exit 1
fi
printf '%s\n' "$3" >> "$T3_STUB_DB"
echo "Added project 0000 (${3##*/}) at $3."
SH
chmod +x "$t3proj_bin/t3"

run_t3_projects_step() {
  local home=$1 command_path=${2:-$t3proj_bin:/usr/bin:/bin}
  HOME="$home" REPO_UNDER_TEST="$REPO" PATH="$command_path" \
    T3_STUB_DB="$t3proj_db" T3_STUB_FAIL="$t3proj_fail" \
    T3CODE_PROJECT_POLL_SECONDS="${T3CODE_PROJECT_POLL_SECONDS:-0.05}" \
    bash -c '
      set -euo pipefail
      source "$REPO_UNDER_TEST/headless/setup/lib.sh"
      source "$REPO_UNDER_TEST/headless/setup/65-t3code-projects.sh"
    '
}
t3proj_clone() {   # $1 = checkout dir, $2 = origin URL
  git init -q "$1"
  git -C "$1" remote add origin "$2"
}
t3proj_org_home() {   # $1 = home; dsp-base, one sibling, and three decoys
  t3proj_clone "$1/workspace/dsp-base" https://github.com/PhoeniciaLabsOrg/dsp-base.git
  t3proj_clone "$1/workspace/spec-base" git@github.com:PhoeniciaLabsOrg/spec-base.git
  t3proj_clone "$1/workspace/elsewhere" https://github.com/someone-else/elsewhere.git
  t3proj_clone "$1/workspace/.video-studio.staging" https://github.com/PhoeniciaLabsOrg/video-studio.git
  mkdir -p "$1/workspace/not-a-repo"
}
wait_for_file_line() {   # $1 = file, $2 = exact line
  for _ in $(seq 1 100); do
    grep -qxF "$2" "$1" 2>/dev/null && return 0
    sleep 0.05
  done
  return 1
}
wait_for_waiters() {   # the step's detached waiter has no pid we can wait on
  for _ in $(seq 1 100); do
    pgrep -f 'wait_and_add_t3code_projects$' >/dev/null || return 0
    sleep 0.05
  done
  return 1
}

t3proj_home="$TMP/t3proj-home"
t3proj_org_home "$t3proj_home"
t3proj_log="$t3proj_home/.local/state/t3code/projects.log"
# Captured with $(...), which only returns once every holder of the pipe has
# closed it. A waiter that kept install.sh's stdout would hang this line, the
# same way it would stop the Coder agent from seeing startup finish.
t3proj_first="$(run_t3_projects_step "$t3proj_home" 2>&1)"
assert_contains "T3 projects are added in the background" \
  "t3: adding PhoeniciaLabsOrg checkouts as T3 projects in the background" "$t3proj_first"
wait_for_waiters
assert_equal "only PhoeniciaLabsOrg checkouts are added as T3 projects" \
  "$t3proj_home/workspace/dsp-base
$t3proj_home/workspace/spec-base" "$(sort "$t3proj_db")"
assert_contains "the waiter logs each added project" \
  "t3: added project $t3proj_home/workspace/spec-base" "$(cat "$t3proj_log")"

: > "$t3proj_log"
run_t3_projects_step "$t3proj_home" >/dev/null 2>&1
wait_for_waiters
assert_equal "already-registered T3 projects are left quiet" "" "$(cat "$t3proj_log")"
assert_equal "each T3 project is registered once" 2 "$(wc -l < "$t3proj_db")"

t3proj_nobin="$TMP/t3proj-nobin"
t3proj_org_home "$t3proj_nobin"
run_t3_projects_step "$t3proj_nobin" /usr/bin:/bin
assert_path_absent "T3 project step without t3 does nothing" "$t3proj_nobin/.local/state/t3code"

rm -f "$t3proj_db"
touch "$t3proj_fail"
if run_t3_projects_step "$t3proj_home" >/dev/null 2>&1; then
  pass "the T3 project step never aborts install.sh"
else
  fail "the T3 project step never aborts install.sh"
fi
wait_for_waiters
assert_contains "a failing t3 project add warns with the error" \
  "warning: t3: could not add project $t3proj_home/workspace/dsp-base: [00:00:00.000] ERROR (#4): SqlError: disk I/O error" \
  "$(cat "$t3proj_log")"
rm -f "$t3proj_fail"

# First start: the template has created its setup marker and the empty
# ~/workspace/dsp-base, and cloned a sibling, but dsp-base is still staging.
t3proj_late="$TMP/t3proj-late"
mkdir -p "$t3proj_late/.config/dsp" "$t3proj_late/workspace/dsp-base"
date > "$t3proj_late/.config/dsp/setup-running"
t3proj_clone "$t3proj_late/workspace/spec-base" https://github.com/PhoeniciaLabsOrg/spec-base.git
run_t3_projects_step "$t3proj_late" >/dev/null 2>&1
sleep 0.3
if grep -q "$t3proj_late" "$t3proj_db" 2>/dev/null; then
  fail "nothing is added while the template's setup is running"
else
  pass "nothing is added while the template's setup is running"
fi
t3proj_clone "$t3proj_late/workspace/dsp-base" https://github.com/PhoeniciaLabsOrg/dsp-base.git
sleep 0.3
if grep -q "$t3proj_late" "$t3proj_db" 2>/dev/null; then
  fail "a dsp-base checkout alone does not end the wait while setup runs"
else
  pass "a dsp-base checkout alone does not end the wait while setup runs"
fi
rm -f "$t3proj_late/.config/dsp/setup-running"
if wait_for_file_line "$t3proj_db" "$t3proj_late/workspace/dsp-base" &&
   wait_for_file_line "$t3proj_db" "$t3proj_late/workspace/spec-base"; then
  pass "every checkout is added once the template's setup finishes"
else
  fail "every checkout is added once the template's setup finishes"
fi
wait_for_waiters

t3proj_stuck="$TMP/t3proj-stuck"
mkdir -p "$t3proj_stuck/.config/dsp"
date > "$t3proj_stuck/.config/dsp/setup-running"
t3proj_clone "$t3proj_stuck/workspace/spec-base" https://github.com/PhoeniciaLabsOrg/spec-base.git
T3CODE_PROJECT_WAIT_SECONDS=0 run_t3_projects_step "$t3proj_stuck" >/dev/null 2>&1
if wait_for_file_line "$t3proj_db" "$t3proj_stuck/workspace/spec-base"; then
  pass "a setup that never finishes still gets its checkouts added"
else
  fail "a setup that never finishes still gets its checkouts added"
fi
wait_for_waiters
assert_contains "giving up on the template's setup is logged" \
  "warning: t3: workspace setup is still not done; adding what is checked out" \
  "$(cat "$t3proj_stuck/.local/state/t3code/projects.log")"

# T3 nightly updates. The npm stub answers `npm view t3@nightly version` from
# $T3_STUB_NIGHTLY (failing when it is empty, like an unreachable registry) and
# "installs" by writing the manifest the step reads. A listener the test holds
# on the step's port stands in for a running server, so the step stops there
# instead of starting t3.
t3up_bin="$TMP/t3up-bin"
t3up_npm_log="$TMP/t3up-npm.log"
mkdir -p "$t3up_bin"
cat > "$t3up_bin/npm" <<'SH'
#!/usr/bin/env sh
case "$*" in
  "view t3@nightly version")
    [ -n "$T3_STUB_NIGHTLY" ] || exit 1
    echo "$T3_STUB_NIGHTLY" ;;
  "install -g --prefix $HOME/.local t3@"*)
    echo "$*" >> "$T3_STUB_NPM_LOG"
    version=${5#t3@}
    [ "$version" = nightly ] && version=0.1.1-nightly.20261020.1
    mkdir -p "$HOME/.local/lib/node_modules/t3" "$HOME/.local/bin"
    printf '{\n  "name": "t3",\n  "version": "%s"\n}\n' "$version" \
      > "$HOME/.local/lib/node_modules/t3/package.json"
    printf '#!/bin/sh\nexit 0\n' > "$HOME/.local/bin/t3"
    chmod +x "$HOME/.local/bin/t3" ;;
  *) exit 2 ;;
esac
SH
chmod +x "$t3up_bin/npm"

t3up_port_file="$TMP/t3up-port"
python3 -c '
import socket, sys
s = socket.socket()
s.bind(("127.0.0.1", 0))
s.listen()
open(sys.argv[1], "w").write(str(s.getsockname()[1]))
while True:
    s.accept()[0].close()
' "$t3up_port_file" &
T3UP_LISTENER_PID=$!
for _ in $(seq 1 100); do [ -s "$t3up_port_file" ] && break; sleep 0.05; done
t3up_port="$(cat "$t3up_port_file")"

run_t3_install_step() {   # $1 = home, $2 = nightly the registry reports
  HOME="$1" REPO_UNDER_TEST="$REPO" PATH="$t3up_bin:/usr/bin:/bin" \
    T3_STUB_NIGHTLY="$2" T3_STUB_NPM_LOG="$t3up_npm_log" T3CODE_PORT="$t3up_port" \
    bash -c '
      set -euo pipefail
      source "$REPO_UNDER_TEST/headless/setup/lib.sh"
      source "$REPO_UNDER_TEST/headless/setup/60-t3code.sh"
    '
}
t3up_version() {   # $1 = home
  sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$1/.local/lib/node_modules/t3/package.json"
}

t3up_home="$TMP/t3up-home"
mkdir -p "$t3up_home"
run_t3_install_step "$t3up_home" 0.1.1-nightly.20261019.3360 >/dev/null 2>&1
assert_equal "a fresh workspace installs the current nightly" \
  0.1.1-nightly.20261019.3360 "$(t3up_version "$t3up_home")"

: > "$t3up_npm_log"
run_t3_install_step "$t3up_home" 0.1.1-nightly.20261019.3360 >/dev/null 2>&1
assert_equal "a restart on the current nightly does not reinstall" "" "$(cat "$t3up_npm_log")"

t3up_out="$(run_t3_install_step "$t3up_home" 0.1.1-nightly.20261020.3371 2>&1)"
assert_equal "a restart after a new nightly installs it" \
  0.1.1-nightly.20261020.3371 "$(t3up_version "$t3up_home")"
assert_contains "the nightly update is logged" \
  "npm: updating t3 0.1.1-nightly.20261019.3360 -> 0.1.1-nightly.20261020.3371" "$t3up_out"

: > "$t3up_npm_log"
if t3up_out="$(run_t3_install_step "$t3up_home" "" 2>&1)"; then
  pass "an unreachable registry does not abort install.sh"
else
  fail "an unreachable registry does not abort install.sh"
fi
assert_equal "an unreachable registry keeps the installed nightly" "" "$(cat "$t3up_npm_log")"
assert_contains "an unreachable registry is logged" \
  "t3: could not look up the newest nightly; keeping 0.1.1-nightly.20261020.3371" "$t3up_out"

t3up_stable="$TMP/t3up-stable"
mkdir -p "$t3up_stable/.local/lib/node_modules/t3" "$t3up_stable/.local/bin"
printf '{\n  "version": "0.1.0"\n}\n' > "$t3up_stable/.local/lib/node_modules/t3/package.json"
printf '#!/bin/sh\nexit 0\n' > "$t3up_stable/.local/bin/t3"
chmod +x "$t3up_stable/.local/bin/t3"
run_t3_install_step "$t3up_stable" "" >/dev/null 2>&1
assert_equal "a stable build is replaced even when the registry lookup fails" \
  0.1.1-nightly.20261020.1 "$(t3up_version "$t3up_stable")"

kill "$T3UP_LISTENER_PID" 2>/dev/null || true

# acli login. A stub already in ~/.local/bin keeps the step off the network;
# it records its argv and stdin so the test can check where the token went.
acli_home="$TMP/acli-home"
mkdir -p "$acli_home/.local/bin"
cat > "$acli_home/.local/bin/acli" <<'SH'
#!/usr/bin/env sh
printf '%s\n' "$*" > "$HOME/acli-argv"
cat > "$HOME/acli-stdin"
[ "$5" = good.atlassian.net ]
SH
chmod +x "$acli_home/.local/bin/acli"

run_acli_step() {   # $1 = site; email and token are fixed
  HOME="$acli_home" REPO_UNDER_TEST="$REPO" PATH=/usr/bin:/bin \
    ATLASSIAN_CLI_SITE="$1" ATLASSIAN_CLI_EMAIL=me@example.com \
    ATLASSIAN_CLI_API_TOKEN=s3cret \
    bash -c '
      set -euo pipefail
      source "$REPO_UNDER_TEST/headless/setup/lib.sh"
      source "$REPO_UNDER_TEST/headless/setup/47-acli.sh"
    '
}

acli_out="$(run_acli_step good.atlassian.net 2>&1)"
assert_equal "acli logs in to jira with the workspace site and email" \
  "jira auth login --site good.atlassian.net --email me@example.com --token" \
  "$(cat "$acli_home/acli-argv")"
assert_equal "the acli token arrives on stdin" s3cret "$(cat "$acli_home/acli-stdin")"
assert_contains "the acli login is logged" "acli: logged in to jira at good.atlassian.net" "$acli_out"

if acli_out="$(run_acli_step bad.atlassian.net 2>&1)"; then
  pass "a failed acli login does not abort install.sh"
else
  fail "a failed acli login does not abort install.sh"
fi
assert_contains "a failed acli login is logged" "acli: jira login to bad.atlassian.net failed" "$acli_out"

rm -f "$acli_home/acli-argv"
acli_out="$(run_acli_step "" 2>&1)"
assert_path_absent "acli does not log in without ATLASSIAN_CLI_SITE" "$acli_home/acli-argv"
assert_contains "the skipped acli login is logged" "skipping jira login" "$acli_out"

summary
