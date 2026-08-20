# Herdr Claude Instance Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Herdr restore GPT Code and Monet sessions through their original launcher contexts while preserving primary Claude behavior.

**Architecture:** Define a narrow Zsh `claude()` dispatcher after the existing launchers. It intercepts only Herdr's bare `claude --resume <id>` form, identifies the owning alternate user configuration root from the transcript filename, and delegates to `gpt_code` or `monet`; those launchers remain the single source of truth for environment, model, colors, labels, and argument forwarding. Unknown and primary sessions execute the real Claude binary unchanged.

**Tech Stack:** Zsh functions and glob qualifiers, POSIX executable stubs, existing `gpt_code`/`monet` launchers, Claude Code transcript storage, Herdr 0.8.0 native restore behavior.

---

## File map

- `/home/rgarber11/dotfiles/arch/zshrc` — tracked source of truth; add only the restore dispatcher after `monet()`.
- `/home/rgarber11/.zshrc` — active machine-local configuration; add the same dispatcher without changing its local GPT environment values.
- `/tmp/test-herdr-claude-restore.zsh` — temporary TDD and smoke harness; extract the real functions, stub external commands, and exercise fake plus real transcript stores. Remove after verification.
- `docs/superpowers/specs/2026-08-19-herdr-claude-instance-restore-design.md` — approved behavior and boundaries; reference only.

The tracked `arch/zshrc` already contains the user's broader uncommitted launcher changes. Do not stage or commit it, and do not stage the existing untracked OMP session HTML. The active `~/.zshrc` is outside the repository. This implementation therefore ends with verified, unstaged Zsh changes rather than a source commit.

### Task 1: Capture the failing native-restore contract

**Files:**
- Create temporarily: `/tmp/test-herdr-claude-restore.zsh`
- Reference: `/home/rgarber11/dotfiles/arch/zshrc:62-151`
- Reference: `/home/rgarber11/.zshrc:177-268`

- [ ] **Step 1: Write the behavioral harness**

Create `/tmp/test-herdr-claude-restore.zsh` with this complete content:

```zsh
#!/bin/zsh
set -eu

repo_zshrc=/home/rgarber11/dotfiles/arch/zshrc
active_zshrc=/home/rgarber11/.zshrc
real_home=$HOME
fake_home=''
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
fake_home="$workdir/home"
mkdir -p "$workdir/bin" \
  "$fake_home/.claude/projects/project" \
  "$fake_home/.config/claude-other/projects/project" \
  "$fake_home/.config/claude-monet/projects/project"

cat > "$workdir/bin/claude" <<'STUB'
#!/bin/sh
{
  printf 'config=%s\n' "${CLAUDE_CONFIG_DIR-}"
  printf 'base=%s\n' "${ANTHROPIC_BASE_URL-}"
  printf 'mcp=%s\n' "${ENABLE_CLAUDEAI_MCP_SERVERS-}"
  printf 'telemetry=%s\n' "${DISABLE_TELEMETRY-}"
  printf 'traffic=%s\n' "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC-}"
  printf 'opus=%s\n' "${ANTHROPIC_DEFAULT_OPUS_MODEL-}"
  printf 'sonnet=%s\n' "${ANTHROPIC_DEFAULT_SONNET_MODEL-}"
  printf 'haiku=%s\n' "${ANTHROPIC_DEFAULT_HAIKU_MODEL-}"
  if [ -n "${ANTHROPIC_AUTH_TOKEN-}" ]; then
    printf 'auth=set\n'
  else
    printf 'auth=unset\n'
  fi
  printf 'argc=%s\n' "$#"
  index=1
  for argument do
    printf 'arg%s=%s:%s\n' "$index" "${#argument}" "$argument"
    index=$((index + 1))
  done
} > "$CLAUDE_CAPTURE"
STUB

cat > "$workdir/bin/herdr" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$HERDR_CAPTURE"
exit 0
STUB

chmod +x "$workdir/bin/claude" "$workdir/bin/herdr"
export PATH="$workdir/bin:$PATH"
export CLAUDE_CAPTURE="$workdir/claude-capture"
export HERDR_CAPTURE="$workdir/herdr-capture"

fail() {
  print -u2 -- "FAIL: $1"
  return 1
}

assert_contains() {
  local description=$1
  local needle=$2
  local haystack=$3
  [[ "$haystack" == *"$needle"* ]] || fail "$description (missing: $needle)"
}

assert_not_contains() {
  local description=$1
  local needle=$2
  local haystack=$3
  [[ "$haystack" != *"$needle"* ]] || fail "$description (unexpected: $needle)"
}

assert_empty_file() {
  local description=$1
  local path=$2
  [[ ! -s "$path" ]] || fail "$description"
}

reset_captures() {
  : > "$CLAUDE_CAPTURE"
  : > "$HERDR_CAPTURE"
  : > "$workdir/stdout"
  : > "$workdir/stderr"
}

wait_for_label() {
  local description=$1
  local expected=$2
  local attempt actual
  for attempt in {1..50}; do
    actual=$(<"$HERDR_CAPTURE")
    [[ "$actual" == *"--display-agent $expected"* ]] && return 0
    sleep 0.02
  done
  fail "$description"
}

load_functions() {
  local source_file=$1
  local function_name
  unfunction _label_herdr_agent gpt_code monet claude 2>/dev/null || true
  for function_name in _label_herdr_agent gpt_code monet claude; do
    sed -n "/^${function_name}() {$/,/^}$/p" "$source_file"
  done > "$workdir/functions.zsh"
  source "$workdir/functions.zsh"
}

exercise_fake_store() {
  local source_file=$1
  local source_name=$2
  local output capture

  export HOME="$fake_home"
  export HERDR_PANE_ID=test-pane
  export ANTHROPIC_AUTH_TOKEN=test-token
  unset CLAUDE_CONFIG_DIR
  load_functions "$source_file"

  : > "$HOME/.config/claude-other/projects/project/gpt-session.jsonl"
  reset_captures
  output=$(claude --resume gpt-session 'argument with spaces')
  capture=$(<"$CLAUDE_CAPTURE")
  assert_contains "$source_name GPT config" \
    "config=$HOME/.config/claude-other/" "$capture"
  assert_contains "$source_name GPT proxy" \
    'base=http://127.0.0.1:8317' "$capture"
  assert_contains "$source_name GPT model environment" \
    'opus=gpt-5.6-sol' "$capture"
  assert_contains "$source_name GPT MCP policy" 'mcp=false' "$capture"
  assert_contains "$source_name GPT telemetry policy" 'telemetry=1' "$capture"
  assert_contains "$source_name GPT traffic policy" 'traffic=1' "$capture"
  assert_contains "$source_name GPT Sonnet mapping" 'sonnet=gpt-5.6-terra' "$capture"
  assert_contains "$source_name GPT Haiku mapping" 'haiku=gpt-5.6-luna' "$capture"
  assert_contains "$source_name GPT authentication" 'auth=set' "$capture"
  assert_contains "$source_name GPT fixed model option" \
    'arg1=7:--model' "$capture"
  assert_contains "$source_name GPT fixed model value" \
    'arg2=11:gpt-5.6-sol' "$capture"
  assert_contains "$source_name GPT resume flag" \
    'arg3=8:--resume' "$capture"
  assert_contains "$source_name GPT session ID" \
    'arg4=11:gpt-session' "$capture"
  assert_contains "$source_name GPT argument boundary" \
    'arg5=20:argument with spaces' "$capture"
  assert_contains "$source_name GPT foreground color" '#c0caf5' "$output"
  assert_contains "$source_name GPT background color" '#24283b' "$output"
  wait_for_label "$source_name GPT display label" gpt_code

  : > "$HOME/.config/claude-monet/projects/project/monet-session.jsonl"
  reset_captures
  output=$(claude --resume monet-session 'argument with spaces')
  capture=$(<"$CLAUDE_CAPTURE")
  assert_contains "$source_name Monet config" \
    "config=$HOME/.config/claude-monet/" "$capture"
  assert_contains "$source_name Monet keeps its own backend" $'base=\n' "$capture"
  assert_not_contains "$source_name Monet has no GPT model option" '--model' "$capture"
  assert_contains "$source_name Monet resume flag" 'arg1=8:--resume' "$capture"
  assert_contains "$source_name Monet session ID" 'arg2=13:monet-session' "$capture"
  assert_contains "$source_name Monet argument boundary" \
    'arg3=20:argument with spaces' "$capture"
  assert_contains "$source_name Monet foreground color" '#839395' "$output"
  assert_contains "$source_name Monet background color" '#001419' "$output"
  wait_for_label "$source_name Monet display label" monet

  : > "$HOME/.claude/projects/project/primary-session.jsonl"
  reset_captures
  output=$(claude --resume primary-session)
  capture=$(<"$CLAUDE_CAPTURE")
  assert_contains "$source_name primary config remains default" $'config=\n' "$capture"
  assert_contains "$source_name primary resume flag" 'arg1=8:--resume' "$capture"
  assert_contains "$source_name primary session ID" 'arg2=15:primary-session' "$capture"
  assert_not_contains "$source_name primary has no GPT model option" '--model' "$capture"
  [[ -z "$output" ]] || fail "$source_name primary emitted launcher colors"
  assert_empty_file "$source_name primary reported a custom label" "$HERDR_CAPTURE"

  reset_captures
  export CLAUDE_CONFIG_DIR="$HOME/custom-config"
  output=$(claude --resume gpt-session)
  unset CLAUDE_CONFIG_DIR
  capture=$(<"$CLAUDE_CAPTURE")
  assert_contains "$source_name explicit config is preserved" \
    "config=$HOME/custom-config" "$capture"
  assert_contains "$source_name explicit config preserves arguments" \
    'arg1=8:--resume' "$capture"
  assert_not_contains "$source_name explicit config has no GPT model option" '--model' "$capture"
  [[ -z "$output" ]] || fail "$source_name explicit config emitted launcher colors"
  assert_empty_file "$source_name explicit config reported a custom label" "$HERDR_CAPTURE"

  reset_captures
  unset HERDR_PANE_ID
  output=$(claude --resume gpt-session)
  capture=$(<"$CLAUDE_CAPTURE")
  assert_contains "$source_name non-Herdr call remains default" $'config=\n' "$capture"
  assert_contains "$source_name non-Herdr call preserves arguments" \
    'arg1=8:--resume' "$capture"
  assert_not_contains "$source_name non-Herdr call has no GPT model option" '--model' "$capture"
  [[ -z "$output" ]] || fail "$source_name non-Herdr call emitted launcher colors"
  export HERDR_PANE_ID=test-pane

  : > "$HOME/.config/claude-other/projects/project/ambiguous-session.jsonl"
  : > "$HOME/.config/claude-monet/projects/project/ambiguous-session.jsonl"
  reset_captures
  if claude --resume ambiguous-session > "$workdir/stdout" 2> "$workdir/stderr"; then
    fail "$source_name ambiguous session executed Claude"
  fi
  assert_empty_file "$source_name ambiguous session reached Claude" "$CLAUDE_CAPTURE"
  assert_contains "$source_name ambiguity error" \
    'session ambiguous-session exists in both gpt_code and monet stores' \
    "$(<"$workdir/stderr")"

  reset_captures
  output=$(claude --resume '../gpt-session')
  capture=$(<"$CLAUDE_CAPTURE")
  assert_contains "$source_name slash-containing ID is passed through" \
    'arg2=14:../gpt-session' "$capture"
  assert_not_contains "$source_name slash-containing ID has no GPT model option" \
    '--model' "$capture"
  [[ -z "$output" ]] || fail "$source_name slash-containing ID emitted launcher colors"
}

exercise_real_store() {
  local gpt_session=45ed31b7-0b03-4bde-9265-2d827a859cc5
  local monet_session=02436271-0f40-47f5-a4d1-dfd0885d537b
  local capture

  [[ -f "$real_home/.config/claude-other/projects/-home-rgarber11-PhoeniciaLabs-secondaryDSP/$gpt_session.jsonl" ]] ||
    fail 'real GPT transcript fixture is missing'
  [[ -f "$real_home/.config/claude-monet/projects/-home-rgarber11-PhoeniciaLabs-dsp-base/$monet_session.jsonl" ]] ||
    fail 'real Monet transcript fixture is missing'

  export HOME="$real_home"
  export HERDR_PANE_ID=test-pane
  unset CLAUDE_CONFIG_DIR
  load_functions "$active_zshrc"

  reset_captures
  claude --resume "$gpt_session" >/dev/null
  capture=$(<"$CLAUDE_CAPTURE")
  assert_contains 'real GPT transcript selects GPT config' \
    "config=$real_home/.config/claude-other/" "$capture"
  assert_contains 'real GPT transcript restores fixed model' \
    'arg1=7:--model' "$capture"
  wait_for_label 'real GPT transcript restores display label' gpt_code

  reset_captures
  claude --resume "$monet_session" >/dev/null
  capture=$(<"$CLAUDE_CAPTURE")
  assert_contains 'real Monet transcript selects Monet config' \
    "config=$real_home/.config/claude-monet/" "$capture"
  assert_contains 'real Monet transcript preserves resume flag' \
    'arg1=8:--resume' "$capture"
  wait_for_label 'real Monet transcript restores display label' monet
}

exercise_fake_store "$repo_zshrc" tracked
exercise_fake_store "$active_zshrc" active
exercise_real_store
print 'Herdr Claude instance restore: PASS'
```

The harness calls the exact bare restore command Herdr 0.8.0 injects into the restored shell. External `claude` and `herdr` processes are stubbed, but both real Zsh launcher sources, argument handling, filesystem lookup, environment selection, colors, and metadata command construction execute. The final two cases use existing real transcript paths without making a model request or changing the running Herdr server.

- [ ] **Step 2: Run the harness and verify it fails for the right reason**

Run:

```bash
zsh /tmp/test-herdr-claude-restore.zsh
```

Expected: nonzero exit at `tracked GPT config`, reporting that the GPT configuration root is missing. Before implementation, no `claude()` function is extracted, so the stub receives Herdr's bare command with an empty `CLAUDE_CONFIG_DIR`.

### Task 2: Add the restore dispatcher to both Zsh sources

**Files:**
- Modify: `/home/rgarber11/dotfiles/arch/zshrc` immediately after `monet()` and before `herdr_remote()`
- Modify: `/home/rgarber11/.zshrc` immediately after `monet()` and before `herdr_remote()`
- Test: `/tmp/test-herdr-claude-restore.zsh`

- [ ] **Step 1: Add the dispatcher to the tracked source**

Insert this complete function after `monet()` in `/home/rgarber11/dotfiles/arch/zshrc`:

```zsh
claude() {
  if [[ -n ${HERDR_PANE_ID:-} &&
        -z ${CLAUDE_CONFIG_DIR:-} &&
        ${1:-} == --resume &&
        -n ${2:-} &&
        ${2:-} != */* ]]; then
    local session_id=$2
    local -a gpt_sessions monet_sessions

    gpt_sessions=(
      "$HOME"/.config/claude-other/projects/*/"$session_id".jsonl(N)
    )
    monet_sessions=(
      "$HOME"/.config/claude-monet/projects/*/"$session_id".jsonl(N)
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

The quoted session ID is pathname data; only the single project-directory wildcard is active. Rejecting slash-containing IDs prevents traversal outside the expected `projects/<encoded-cwd>/<id>.jsonl` shape. The `(N)` qualifier converts no-match globs to empty arrays without changing the caller's shell options.

- [ ] **Step 2: Add the same dispatcher to the active source**

Insert the identical `claude()` function shown in Step 1 after `monet()` in `/home/rgarber11/.zshrc`.

Do not alter `_label_herdr_agent()`, `gpt_code()`, `monet()`, the active file's context-token variables, its authentication value, or any unrelated function. `gpt_code "$@"` and `monet "$@"` deliberately reuse those existing machine-local execution contexts.

- [ ] **Step 3: Parse both files**

Run:

```bash
zsh -n /home/rgarber11/dotfiles/arch/zshrc && \
  zsh -n /home/rgarber11/.zshrc
```

Expected: exit status 0 with no output.

- [ ] **Step 4: Run the focused harness and verify every contract passes**

Run:

```bash
zsh /tmp/test-herdr-claude-restore.zsh
```

Expected final output:

```text
Herdr Claude instance restore: PASS
```

This proves both tracked and active files dispatch fake GPT and Monet sessions, preserve primary/explicit/non-Herdr calls, reject ambiguity, treat unsafe IDs as ordinary Claude input, and resolve one real transcript from each alternate root. The Claude executable remains stubbed, so this check cannot issue model requests.

### Task 3: Verify the integrated dotfiles and clean temporary artifacts

**Files:**
- Verify: `/home/rgarber11/dotfiles/arch/zshrc`
- Verify: `/home/rgarber11/.zshrc`
- Verify: `/home/rgarber11/dotfiles/tests/run.sh`
- Remove: `/tmp/test-herdr-claude-restore.zsh`

- [ ] **Step 1: Run the existing full dotfiles test suite**

Run:

```bash
cd /home/rgarber11/dotfiles && ./tests/run.sh
```

Expected: exit status 0 and output ending in:

```text
all checks passed
```

The container suite does not exercise desktop-only launcher dispatch directly; the focused harness supplies that proof. This run checks that the tracked Zsh change did not disturb the shared installation and headless profile.

- [ ] **Step 2: Confirm the active shell loads the dispatcher**

Run:

```bash
zsh -ic 'whence -w claude; whence -w gpt_code; whence -w monet'
```

Expected output contains:

```text
claude: function
gpt_code: function
monet: function
```

Any unrelated interactive-shell startup output may surround these three lines.

- [ ] **Step 3: Remove the temporary harness**

Run:

```bash
rm /tmp/test-herdr-claude-restore.zsh
```

Expected: exit status 0. The harness's private work directory is already removed by its `EXIT` trap.

- [ ] **Step 4: Leave existing user work unstaged**

Do not stage or commit `/home/rgarber11/dotfiles/arch/zshrc`; it contains the user's pre-existing display-label and argument-forwarding changes in the same launcher area. Do not add `omp-session-2026-08-19T14-11-01-424Z_01a01a5c-72b0-7000-a69e-15823f6a1922.html`. The deliverable is the verified tracked-source edit plus the active `~/.zshrc` deployment.