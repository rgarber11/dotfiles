# Coder Claude proxy implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add privacy-preserving GPT and Monet Claude launchers to the Coder zsh profile, backed by an automatically started loopback CLIProxyAPI service with shared user credentials.

**Architecture:** Two focused headless setup steps own persistent state: one atomically enforces the GPT profile's privacy settings, and one installs and starts CLIProxyAPI without systemd. A separate headless zsh module owns launcher, theme, metadata, and resume dispatch behavior. A fast shell test covers the setup and zsh contracts; the existing container harness covers links, the real release binary, persistence, and restart behavior.

**Tech stack:** Bash, zsh, jq, CLIProxyAPI, OSC terminal sequences, Podman, the existing shell assertion helpers.

---

## File map

- Create `headless/setup/41-claude-other-settings.sh`: merge the privacy-only settings into the shared GPT Claude profile without losing user keys.
- Create `headless/cli-proxy-api.yaml`: loopback-only CLIProxyAPI configuration with the shared auth directory and fixed local client key.
- Create `headless/setup/42-cli-proxy-api.sh`: install, validate, start, stop, restart, and readiness-check the proxy process.
- Create `headless/claude.zsh`: Herdr metadata helper, `gpt_code`, `monet`, and `claude` resume dispatch.
- Create `tests/coder-interface.sh`: fast behavioral tests for the two setup steps and zsh module.
- Modify `profiles/headless.links`: link the proxy configuration into `~/.config/cli-proxy-api/config.yaml`.
- Modify `headless/zshrc`: source the headless Claude module.
- Modify `tests/run.sh`: mount shared user state and exercise the real CLIProxyAPI binary through the existing Coder container test.
- Modify `README.md`: document the installed proxy, the one-time device login, and the three zsh commands.

### Task 1: Enforce GPT profile privacy settings

**Files:**
- Create: `tests/coder-interface.sh`
- Create: `headless/setup/41-claude-other-settings.sh`

- [ ] **Step 1: Write the failing privacy-setting tests**

Create `tests/coder-interface.sh` with the privacy cases below. The test covers a missing file, preservation and forced privacy values in a populated file, idempotence, mode `0600`, and byte-for-byte preservation of invalid JSON.

```bash
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

run_privacy_step() {
  HOME="$1" DOTFILES_DIR="$REPO" UPGRADE=0 bash -c '
    set -euo pipefail
    source "$DOTFILES_DIR/headless/setup/lib.sh"
    source "$DOTFILES_DIR/headless/setup/41-claude-other-settings.sh"
  '
}

missing_home="$TMP/privacy-missing"
run_privacy_step "$missing_home"
missing_json="$(jq -c '{env,disableClaudeAiConnectors}' "$missing_home/.claude-other/settings.json")"
assert_contains "missing GPT settings are created with privacy controls" \
  '"CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC":"1"' "$missing_json"
assert_contains "Claude.ai connectors are disabled" \
  '"disableClaudeAiConnectors":true' "$missing_json"
assert_contains "privacy settings use mode 0600" \
  '600' "$(stat -c %a "$missing_home/.claude-other/settings.json")"

populated_home="$TMP/privacy-populated"
mkdir -p "$populated_home/.claude-other"
cat > "$populated_home/.claude-other/settings.json" <<'JSON'
{
  "permissions": {"defaultMode": "auto"},
  "custom": {"keep": true},
  "env": {
    "KEEP_ME": "yes",
    "DISABLE_TELEMETRY": "0"
  },
  "disableClaudeAiConnectors": false
}
JSON
run_privacy_step "$populated_home"
populated_json="$(jq -c . "$populated_home/.claude-other/settings.json")"
assert_contains "existing permissions survive the privacy merge" \
  '"permissions":{"defaultMode":"auto"}' "$populated_json"
assert_contains "unrelated environment survives the privacy merge" \
  '"KEEP_ME":"yes"' "$populated_json"
assert_contains "telemetry is forced off" \
  '"DISABLE_TELEMETRY":"1"' "$populated_json"
assert_contains "error reporting is forced off" \
  '"DISABLE_ERROR_REPORTING":"1"' "$populated_json"
assert_contains "feedback is forced off" \
  '"DISABLE_FEEDBACK_COMMAND":"1"' "$populated_json"
assert_contains "marketplace autoinstall is forced off" \
  '"CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL":"1"' "$populated_json"
first_hash="$(sha256sum "$populated_home/.claude-other/settings.json" | cut -d' ' -f1)"
run_privacy_step "$populated_home"
second_hash="$(sha256sum "$populated_home/.claude-other/settings.json" | cut -d' ' -f1)"
assert_contains "privacy merge is idempotent" "$first_hash" "$second_hash"

invalid_home="$TMP/privacy-invalid"
mkdir -p "$invalid_home/.claude-other"
printf '{invalid json\n' > "$invalid_home/.claude-other/settings.json"
invalid_before="$(sha256sum "$invalid_home/.claude-other/settings.json" | cut -d' ' -f1)"
run_privacy_step "$invalid_home"
invalid_after="$(sha256sum "$invalid_home/.claude-other/settings.json" | cut -d' ' -f1)"
assert_contains "invalid settings remain byte-for-byte unchanged" "$invalid_before" "$invalid_after"

summary
```

- [ ] **Step 2: Run the focused test and verify the missing setup step fails**

Run:

```bash
chmod +x tests/coder-interface.sh
./tests/coder-interface.sh
```

Expected: the shell exits non-zero because `headless/setup/41-claude-other-settings.sh` does not exist.

- [ ] **Step 3: Implement the atomic privacy merge**

Create `headless/setup/41-claude-other-settings.sh`:

```bash
#!/usr/bin/env bash
# Keep the GPT-backed Claude profile from contacting Anthropic services that
# are irrelevant or misleading when requests go through CLIProxyAPI.

apply_claude_other_privacy() {
  local dir="$HOME/.claude-other"
  local settings="$dir/settings.json"
  local tmp

  if ! command -v jq >/dev/null 2>&1; then
    warn "claude-other: jq is unavailable; privacy settings were not updated"
    return 0
  fi
  if ! mkdir -p "$dir"; then
    warn "claude-other: could not create $dir; privacy settings were not updated"
    return 0
  fi
  if [ -e "$settings" ] && [ ! -f "$settings" ]; then
    warn "claude-other: $settings is not a regular file; leaving it unchanged"
    return 0
  fi

  tmp="$(mktemp "$dir/.settings.json.tmp.XXXXXX")" || {
    warn "claude-other: could not create a temporary settings file"
    return 0
  }

  if [ -f "$settings" ]; then
    jq '
      .env = ((.env // {}) + {
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
        "CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL": "1",
        "DISABLE_TELEMETRY": "1",
        "DISABLE_ERROR_REPORTING": "1",
        "DISABLE_FEEDBACK_COMMAND": "1"
      }) |
      .disableClaudeAiConnectors = true
    ' "$settings" > "$tmp" || {
      rm -f "$tmp"
      warn "claude-other: $settings is not valid mergeable JSON; leaving it unchanged"
      return 0
    }
  else
    jq -n '
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
    ' > "$tmp" || {
      rm -f "$tmp"
      warn "claude-other: could not build privacy settings"
      return 0
    }
  fi

  if ! chmod 600 "$tmp" || ! mv "$tmp" "$settings"; then
    rm -f "$tmp"
    warn "claude-other: could not replace $settings"
    return 0
  fi
  info "claude-other: privacy settings enforced"
}

apply_claude_other_privacy
```

- [ ] **Step 4: Run the focused test and verify the privacy cases pass**

Run:

```bash
./tests/coder-interface.sh
```

Expected: every privacy assertion prints `ok`, followed by `all checks passed`.

- [ ] **Step 5: Commit the privacy step**

```bash
git add headless/setup/41-claude-other-settings.sh tests/coder-interface.sh
git commit -m "feat: preserve GPT Claude privacy settings"
```

### Task 2: Install and auto-start CLIProxyAPI

**Files:**
- Create: `headless/cli-proxy-api.yaml`
- Create: `headless/setup/42-cli-proxy-api.sh`
- Modify: `profiles/headless.links:5-8`
- Modify: `tests/coder-interface.sh`

- [ ] **Step 1: Add failing proxy lifecycle tests**

Insert the following block in `tests/coder-interface.sh` immediately before `summary`. It supplies a fake long-running proxy and a fake readiness client, so the test exercises PID ownership, idempotence, stale recovery, foreign PID safety, and upgrade restart without network access.

```bash
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
printf '{"data":[],"object":"list"}\n'
SH
chmod +x "$fake_bin/curl"
make_fake_proxy() {
  local version=$1
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
run_proxy_step 0
pid1="$(cat "$proxy_home/.local/state/cli-proxy-api/server.pid")"
run_proxy_step 0
pid2="$(cat "$proxy_home/.local/state/cli-proxy-api/server.pid")"
assert_contains "normal setup reuses the running proxy" "$pid1" "$pid2"

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

make_fake_proxy v2
run_proxy_step 1
pid5="$(cat "$proxy_home/.local/state/cli-proxy-api/server.pid")"
case "$pid5" in "$pid4") fail "upgrade restarts the proxy" ;; *) pass "upgrade restarts the proxy" ;; esac
assert_contains "upgrade starts the replacement binary" "v2" "$(cat "$TMP/proxy-version")"
```

- [ ] **Step 2: Run the focused test and verify proxy setup is missing**

Run:

```bash
./tests/coder-interface.sh
```

Expected: privacy checks pass, then the script exits non-zero because `headless/setup/42-cli-proxy-api.sh` does not exist.

- [ ] **Step 3: Add the tracked loopback configuration and link**

Create `headless/cli-proxy-api.yaml`:

```yaml
host: 127.0.0.1
port: 8317

auth-dir: /mnt/user-state/cli-proxy-api

api-keys:
  - coder-local

debug: false
logging-to-file: false
usage-statistics-enabled: false

remote-management:
  allow-remote: false
```

Add this row to `profiles/headless.links` after the Herdr config row:

```text
.config/cli-proxy-api/config.yaml headless/cli-proxy-api.yaml
```

- [ ] **Step 4: Implement installation and daemon lifecycle**

Create `headless/setup/42-cli-proxy-api.sh`:

```bash
#!/usr/bin/env bash
# Install CLIProxyAPI under persistent ~/.local storage and keep one process
# running for this workspace. Coder has no systemd; install.sh runs each start.

setup_cli_proxy_api_locked() {
  local config="${CLI_PROXY_CONFIG:-$HOME/.config/cli-proxy-api/config.yaml}"
  local auth_dir="${CLI_PROXY_AUTH_DIR:-/mnt/user-state/cli-proxy-api}"
  local state="$HOME/.local/state/cli-proxy-api"
  local pid_file="$state/server.pid"
  local log_file="$state/server.log"
  local tag version url pid current_pid cmdline attempt ready=0

  if needs_install cli-proxy-api; then
    tag="$(latest_release_tag router-for-me/CLIProxyAPI)"
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
  if [ ! -d "$(dirname "$auth_dir")" ] || [ ! -w "$(dirname "$auth_dir")" ]; then
    warn "cli-proxy-api: shared user storage is unavailable at $(dirname "$auth_dir"); proxy not started"
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

  proxy_pid_is_ours() {
    local candidate=$1 candidate_cmdline
    case "$candidate" in ''|*[!0-9]*) return 1 ;; esac
    kill -0 "$candidate" 2>/dev/null || return 1
    [ -r "/proc/$candidate/cmdline" ] || return 1
    candidate_cmdline="$(tr '\0' '\n' < "/proc/$candidate/cmdline")"
    case "$candidate_cmdline" in
      *"$HOME/.local/bin/cli-proxy-api"*"$config"*) return 0 ;;
      *) return 1 ;;
    esac
  }

  stop_proxy() {
    local stop_pid=$1
    proxy_pid_is_ours "$stop_pid" || return 1
    kill -TERM "$stop_pid" 2>/dev/null || true
    for attempt in $(seq 1 50); do
      kill -0 "$stop_pid" 2>/dev/null || return 0
      sleep 0.1
    done
    if proxy_pid_is_ours "$stop_pid"; then
      kill -KILL "$stop_pid" 2>/dev/null || true
    fi
    return 0
  }

  current_pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [ -n "$current_pid" ] && proxy_pid_is_ours "$current_pid"; then
    if [ "${UPGRADE:-0}" = 0 ]; then
      info "cli-proxy-api: already running (pid $current_pid)"
      return 0
    fi
    stop_proxy "$current_pid"
  elif [ -n "$current_pid" ]; then
    if kill -0 "$current_pid" 2>/dev/null; then
      warn "cli-proxy-api: pid $current_pid belongs to another process; leaving it untouched"
    fi
    rm -f "$pid_file"
  fi

  umask 077
  nohup "$HOME/.local/bin/cli-proxy-api" --config "$config" > "$log_file" 2>&1 &
  pid=$!
  printf '%s\n' "$pid" > "$pid_file.tmp"
  mv "$pid_file.tmp" "$pid_file"

  for attempt in $(seq 1 50); do
    if curl -fsS --max-time 2 \
        -H 'Authorization: Bearer coder-local' \
        http://127.0.0.1:8317/v1/models >/dev/null 2>&1; then
      ready=1
      break
    fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
  done
  if [ "$ready" = 1 ]; then
    info "cli-proxy-api: ready on 127.0.0.1:8317 (pid $pid)"
  else
    kill -0 "$pid" 2>/dev/null || rm -f "$pid_file"
    warn "cli-proxy-api: did not become ready; see $log_file"
  fi
  return 0
}

setup_cli_proxy_api() {
  local state="$HOME/.local/state/cli-proxy-api"
  local lock_fd rc
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
  setup_cli_proxy_api_locked
  rc=$?
  flock -u "$lock_fd" 2>/dev/null || true
  exec {lock_fd}>&-
  return "$rc"
}

setup_cli_proxy_api
```

- [ ] **Step 5: Run the focused lifecycle test**

Run:

```bash
./tests/coder-interface.sh
```

Expected: privacy and process assertions pass. The last lifecycle assertions are `upgrade restarts the proxy` and `upgrade starts the replacement binary`, followed by `all checks passed`.

- [ ] **Step 6: Commit the proxy setup**

```bash
git add headless/cli-proxy-api.yaml headless/setup/42-cli-proxy-api.sh profiles/headless.links tests/coder-interface.sh
git commit -m "feat: install and start CLIProxyAPI in Coder"
```

### Task 3: Add Coder Claude launcher functions

**Files:**
- Create: `headless/claude.zsh`
- Modify: `headless/zshrc:51-60`
- Modify: `tests/coder-interface.sh`

- [ ] **Step 1: Add failing zsh behavior tests**

Insert the block below in `tests/coder-interface.sh` before `summary`. The fake commands make launcher choice, arguments, environment, Herdr metadata, colors, and Kitty absence observable.

```bash
zhome="$TMP/zsh-home"
zbin="$TMP/zsh-bin"
zlog="$TMP/zsh-launch.log"
herdr_log="$TMP/herdr.log"
kitty_log="$TMP/kitty.log"
mkdir -p "$zhome/.claude-other/projects/p" "$zhome/.claude-monet/projects/p" "$zbin"
for launcher in claude claude-other claude-monet; do
  cat > "$zbin/$launcher" <<'SH'
#!/usr/bin/env sh
printf '%s|%s|%s|%s|%s|%s\n' \
  "$(basename "$0")" "$*" \
  "${ANTHROPIC_BASE_URL:-}" "${ANTHROPIC_AUTH_TOKEN:-}" \
  "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-}" \
  "${ENABLE_CLAUDEAI_MCP_SERVERS:-}" >> "$CLAUDE_TEST_LOG"
SH
  chmod +x "$zbin/$launcher"
done
cat > "$zbin/herdr" <<'SH'
#!/usr/bin/env sh
printf '%s\n' "$*" >> "$HERDR_TEST_LOG"
exit 0
SH
cat > "$zbin/kitty" <<'SH'
#!/usr/bin/env sh
printf '%s\n' "$*" >> "$KITTY_TEST_LOG"
exit 99
SH
chmod +x "$zbin/herdr" "$zbin/kitty"

run_claude_zsh() {
  HOME="$zhome" \
  PATH="$zbin:/usr/bin:/bin" \
  CLAUDE_TEST_LOG="$zlog" \
  HERDR_TEST_LOG="$herdr_log" \
  KITTY_TEST_LOG="$kitty_log" \
  zsh -fc 'source "$1"; shift; "$@"' zsh "$REPO/headless/claude.zsh" "$@"
}

: > "$zlog"
gpt_output="$(HERDR_PANE_ID=pane-gpt run_claude_zsh gpt_code --verbose "two words")"
sleep 0.2
gpt_line="$(cat "$zlog")"
assert_contains "gpt_code uses the other profile launcher" 'claude-other|' "$gpt_line"
assert_contains "gpt_code selects GPT 5.6 Sol" '--model gpt-5.6-sol --verbose two words' "$gpt_line"
assert_contains "gpt_code uses the loopback proxy" 'http://127.0.0.1:8317|coder-local|1|false' "$gpt_line"
assert_contains "gpt_code applies Gruvbox foreground" $'\033]10;#ebdbb2\033\\' "$gpt_output"
assert_contains "gpt_code applies Gruvbox background" $'\033]11;#282828\033\\' "$gpt_output"
assert_contains "gpt_code reports Herdr metadata" 'pane report-metadata pane-gpt' "$(cat "$herdr_log")"
assert_contains "gpt_code uses its Herdr display name" '--display-agent gpt_code' "$(cat "$herdr_log")"

: > "$zlog"
monet_output="$(HERDR_PANE_ID=pane-monet run_claude_zsh monet --resume monet-session)"
sleep 0.2
assert_contains "monet uses the generated profile launcher" 'claude-monet|--resume monet-session' "$(cat "$zlog")"
assert_contains "monet applies Darcula foreground" $'\033]10;#adadad\033\\' "$monet_output"
assert_contains "monet applies Darcula background" $'\033]11;#202020\033\\' "$monet_output"
assert_contains "monet uses its Herdr display name" '--display-agent monet' "$(cat "$herdr_log")"

: > "$zlog"
touch "$zhome/.claude-other/projects/p/gpt-session.jsonl"
run_claude_zsh claude --resume gpt-session
assert_contains "resume dispatch finds the GPT store" 'claude-other|--model gpt-5.6-sol --resume gpt-session' "$(cat "$zlog")"

: > "$zlog"
touch "$zhome/.claude-monet/projects/p/monet-session.jsonl"
run_claude_zsh claude --resume monet-session
assert_contains "resume dispatch finds the Monet store" 'claude-monet|--resume monet-session' "$(cat "$zlog")"

: > "$zlog"
run_claude_zsh claude --resume default-session
assert_contains "unknown resume ID falls through to default Claude" 'claude|--resume default-session' "$(cat "$zlog")"

: > "$zlog"
run_claude_zsh claude --resume project/session.jsonl
assert_contains "resume path falls through to default Claude" 'claude|--resume project/session.jsonl' "$(cat "$zlog")"

: > "$zlog"
CLAUDE_CONFIG_DIR="$zhome/custom" run_claude_zsh claude --resume gpt-session
assert_contains "explicit config dir bypasses resume dispatch" 'claude|--resume gpt-session' "$(cat "$zlog")"

touch "$zhome/.claude-monet/projects/p/collision.jsonl" "$zhome/.claude-other/projects/p/collision.jsonl"
if run_claude_zsh claude --resume collision > "$TMP/collision.out" 2> "$TMP/collision.err"; then
  fail "duplicate session stores fail"
else
  pass "duplicate session stores fail"
fi
assert_contains "duplicate session error names both stores" \
  'exists in both gpt_code and monet stores' "$(cat "$TMP/collision.err")"

: > "$zlog"
plain_output="$(run_claude_zsh gpt_code plain)"
case "$plain_output" in *$'\033]10;'*) fail "non-Herdr gpt_code emits no theme OSC" ;; *) pass "non-Herdr gpt_code emits no theme OSC" ;; esac
if [ -s "$kitty_log" ]; then fail "headless launchers never invoke Kitty"; else pass "headless launchers never invoke Kitty"; fi
```

- [ ] **Step 2: Run the focused test and verify the zsh module is missing**

Run:

```bash
./tests/coder-interface.sh
```

Expected: setup checks pass, then zsh reports that `headless/claude.zsh` cannot be sourced.

- [ ] **Step 3: Implement launchers, themes, metadata, and resume dispatch**

Create `headless/claude.zsh`:

```zsh
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
```

Source it in `headless/zshrc` immediately after the `dotup` alias and before `rcopy`:

```zsh
source "$HOME/dotfiles/headless/claude.zsh"
```

- [ ] **Step 4: Run the focused launcher tests**

Run:

```bash
./tests/coder-interface.sh
```

Expected: all privacy, lifecycle, launcher, dispatch, metadata, theme, and no-Kitty checks pass.

- [ ] **Step 5: Commit the zsh interface**

```bash
git add headless/claude.zsh headless/zshrc tests/coder-interface.sh
git commit -m "feat: add Coder Claude profile launchers"
```

### Task 4: Integrate the real proxy into the Coder container test

**Files:**
- Modify: `tests/run.sh:10-36,39-80,89-220,221-253`

- [ ] **Step 1: Add failing real-install assertions**

Add these assertions against `FIRST`:

```bash
assert_contains "CLIProxyAPI installs under ~/.local" \
  "cli_proxy=/home/coder/.local/bin/cli-proxy-api" "$FIRST"
assert_contains "CLIProxyAPI config links into the repo" \
  "cli_proxy_config=/home/coder/.config/coderv2/dotfiles/headless/cli-proxy-api.yaml" "$FIRST"
assert_contains "CLIProxyAPI answers its authenticated loopback endpoint" \
  "cli_proxy_ready=yes" "$FIRST"
assert_not_contains "CLIProxyAPI records a process ID" "cli_proxy_pid=none" "$FIRST"
assert_contains "GPT profile keeps every privacy control" \
  $'claude_other_private=1\t1\t1\t1\t1\ttrue' "$FIRST"
```

Add these assertions to the restart section:

```bash
assert_not_contains "CLIProxyAPI is not re-downloaded" "downloading cli-proxy-api" "$SECOND"
assert_contains "CLIProxyAPI survived the restart" \
  "cli_proxy=/home/coder/.local/bin/cli-proxy-api" "$AFTER"
assert_contains "CLIProxyAPI recovered the stale container PID" "cli_proxy_ready=yes" "$SECOND"
```

- [ ] **Step 2: Run the container test and verify the assertions fail**

Run:

```bash
./tests/run.sh
```

Expected: the new assertions fail because `FIRST`, `SECOND`, and `AFTER` do not emit the `cli_proxy`, readiness, or privacy observation lines yet.

- [ ] **Step 3: Add the shared volume and observable integration checks**

Update `tests/run.sh` to create a second named volume that represents `/mnt/user-state`:

```bash
USER_STATE_VOLUME=dotfiles-test-user-state

[ "${1:-}" = "--keep" ] || podman volume rm -f "$VOLUME" "$USER_STATE_VOLUME" >/dev/null 2>&1 || true
podman volume create "$VOLUME" >/dev/null 2>&1 || true
podman volume create "$USER_STATE_VOLUME" >/dev/null 2>&1 || true
```

Add this mount to `in_workspace`:

```bash
-v "$USER_STATE_VOLUME:/mnt/user-state" \
```

At the start of `install_run`, before `install.sh`, mimic `ai-auth sync`, seed the generated GPT profile, and run the focused suite:

```bash
sudo chown "$(id -u):$(id -g)" /mnt/user-state
mkdir -p /mnt/user-state/claude/other
[ -L ~/.claude-other ] || ln -s /mnt/user-state/claude/other ~/.claude-other
[ -f ~/.claude-other/settings.json ] || printf '{"permissions":{"defaultMode":"auto"}}\n' > ~/.claude-other/settings.json
~/.config/coderv2/dotfiles/tests/coder-interface.sh
```

After `install.sh`, emit observable real-proxy state:

```bash
export PATH="$HOME/.local/bin:$PATH"
echo "cli_proxy=$(command -v cli-proxy-api || echo none)"
echo "cli_proxy_config=$(readlink -f ~/.config/cli-proxy-api/config.yaml || echo none)"
echo "cli_proxy_ready=$(curl -fsS --max-time 5 -H 'Authorization: Bearer coder-local' http://127.0.0.1:8317/v1/models >/dev/null && echo yes || echo no)"
echo "cli_proxy_pid=$(cat ~/.local/state/cli-proxy-api/server.pid 2>/dev/null || echo none)"
echo "claude_other_private=$(jq -r '[.env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC,.env.CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL,.env.DISABLE_TELEMETRY,.env.DISABLE_ERROR_REPORTING,.env.DISABLE_FEEDBACK_COMMAND,.disableClaudeAiConnectors] | @tsv' ~/.claude-other/settings.json)"
```

Add the persistent binary observation to `AFTER`:

```bash
echo "cli_proxy=$(command -v cli-proxy-api || echo none)"
```

Run from a clean volume:

```bash
./tests/run.sh
```

Expected: both fresh-install and restart phases finish, every assertion prints `ok`, and the script ends with `all checks passed`.

- [ ] **Step 4: Commit the container coverage**

```bash
git add tests/run.sh
git commit -m "test: cover Coder Claude proxy integration"
```

### Task 5: Document and verify the complete interface

**Files:**
- Modify: `README.md:12-30`

- [ ] **Step 1: Update Coder usage documentation**

Add this paragraph after the `dotup` paragraph in `README.md`:

````markdown
The headless profile installs CLIProxyAPI at `~/.local/bin/cli-proxy-api` and starts it on `127.0.0.1:8317` each workspace boot. Its OAuth files live in `/mnt/user-state/cli-proxy-api`, beside the state managed by the Coder template's `ai-auth` helper. Authenticate it once per Coder user:

```sh
cli-proxy-api --config ~/.config/cli-proxy-api/config.yaml --codex-device-login --no-browser
```

`gpt_code` runs `claude-other` through that proxy with the Gruvbox Dark pane colors. `monet` is a thin `claude-monet` wrapper with JetBrains Darcula colors. `claude --resume <id>` searches both alternate profile stores before falling back to the default Claude profile.
````

Also extend the `dotup` sentence so it lists CLIProxyAPI among the tools whose latest release is resolved.

- [ ] **Step 2: Run syntax checks**

Run:

```bash
bash -n install.sh headless/setup/*.sh tests/*.sh
zsh -n headless/zshrc headless/claude.zsh
```

Expected: both commands exit `0` with no output.

- [ ] **Step 3: Run focused behavioral verification**

Run:

```bash
./tests/coder-interface.sh
```

Expected: every privacy, daemon lifecycle, launcher, dispatch, metadata, theme, and no-Kitty assertion prints `ok`; final line is `all checks passed`.

- [ ] **Step 4: Run the full Coder simulation from a clean state**

Run:

```bash
./tests/run.sh
```

Expected: the real latest CLIProxyAPI release starts on loopback during both simulated workspace starts; all checks pass.

- [ ] **Step 5: Commit the documentation**

```bash
git add README.md
git commit -m "docs: describe Coder Claude proxy commands"
```

- [ ] **Step 6: Verify in the real Coder workspace after the branch reaches its dotfiles clone**

Run from the desktop:

```bash
ssh richard-worktree-2.coder '~/.config/coderv2/dotfiles/install.sh'
ssh richard-worktree-2.coder 'curl -fsS --max-time 5 -H "Authorization: Bearer coder-local" http://127.0.0.1:8317/v1/models'
```

Expected before login: the first command reports `cli-proxy-api: ready on 127.0.0.1:8317`; the second returns a JSON model list, which may be empty.

Start the one-time login in an interactive SSH terminal:

```bash
ssh -t richard-worktree-2.coder 'cli-proxy-api --config ~/.config/cli-proxy-api/config.yaml --codex-device-login --no-browser'
```

Open the printed device URL, enter the printed code, and wait for `Codex authentication successful`. Then run:

```bash
ssh richard-worktree-2.coder 'curl -fsS --max-time 5 -H "Authorization: Bearer coder-local" http://127.0.0.1:8317/v1/models'
```

Expected after login: JSON `data` contains the configured GPT models. In Herdr, run `gpt_code`, submit one harmless prompt, exit, run `monet`, and resume one known session from each alternate store. Confirm Gruvbox Dark on GPT Code, JetBrains Darcula on Monet, correct display-agent labels, and successful resume routing.
