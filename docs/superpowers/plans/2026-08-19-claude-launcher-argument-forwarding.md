# Claude Launcher Argument Forwarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `monet` and `gpt_code` preserve and forward every caller argument to Claude Code in both ordinary Kitty and Herdr panes.

**Architecture:** Keep the existing zsh `launch_command` arrays and append `"$@"` at array construction time. This preserves zsh argument boundaries through the direct `env` invocation and through the existing Herdr `sh -c`/`exec "$@"` wrapper without introducing string interpolation or refactoring unrelated launcher behavior.

**Tech Stack:** zsh arrays, POSIX executable stubs, existing dotfiles repository.

---

## File map

- Modify: `/home/rgarber11/dotfiles/arch/zshrc:79-151` — tracked Arch definitions for `gpt_code()` and `monet()`.
- Modify: `/home/rgarber11/.zshrc:194-268` — active shell definitions; must match the tracked launch-command changes while preserving its existing local-only environment values.
- Temporary test only: `/tmp/test-claude-launcher-arguments.zsh` — focused behavioral harness; do not commit it.

### Task 1: Forward Claude arguments in both launchers

**Files:**
- Modify: `/home/rgarber11/dotfiles/arch/zshrc:79-151`
- Modify: `/home/rgarber11/.zshrc:194-268`
- Test: `/tmp/test-claude-launcher-arguments.zsh`

- [ ] **Step 1: Write the focused failing behavioral harness**

Create `/tmp/test-claude-launcher-arguments.zsh` with this complete content:

```zsh
#!/bin/zsh
set -eu

repo_zshrc=/home/rgarber11/dotfiles/arch/zshrc
active_zshrc=/home/rgarber11/.zshrc
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

cat > "$workdir/claude" <<'STUB'
#!/bin/sh
{
  printf '%s\n' "$#"
  for argument do
    printf '%s:%s\n' "${#argument}" "$argument"
  done
} > "$CLAUDE_CAPTURE"
STUB

cat > "$workdir/kitty" <<'STUB'
#!/bin/sh
if [ "$1" = "@" ] && [ "$2" = "get-colors" ]; then
  printf 'foreground #ffffff\nbackground #000000\n'
fi
STUB

cat > "$workdir/herdr" <<'STUB'
#!/bin/sh
exit 0
STUB

chmod +x "$workdir/claude" "$workdir/kitty" "$workdir/herdr"
export PATH="$workdir:$PATH"
export CLAUDE_CAPTURE="$workdir/captured"

load_launchers() {
  local source_file=$1
  source <(sed -n '/^_label_herdr_agent() {$/,/^}$/p' "$source_file")
  source <(sed -n '/^gpt_code() {$/,/^}$/p' "$source_file")
  source <(sed -n '/^monet() {$/,/^}$/p' "$source_file")
}

assert_capture() {
  local expected=$1
  local actual=$(<"$CLAUDE_CAPTURE")
  [[ "$actual" == "$expected" ]] || {
    print -u2 -- "expected:\n$expected\nactual:\n$actual"
    return 1
  }
}

exercise_launchers() {
  local source_file=$1
  unfunction _label_herdr_agent gpt_code monet 2>/dev/null || true
  load_launchers "$source_file"

  unset HERDR_PANE_ID
  gpt_code "/spec-base-attach sessionId=sb-ahjt3h" --resume "session with spaces"
  assert_capture $'5\n7:--model\n11:gpt-5.6-sol\n37:/spec-base-attach sessionId=sb-ahjt3h\n8:--resume\n19:session with spaces'

  monet "/spec-base-attach sessionId=sb-ahjt3h" --resume "session with spaces"
  assert_capture $'3\n37:/spec-base-attach sessionId=sb-ahjt3h\n8:--resume\n19:session with spaces'

  export HERDR_PANE_ID=test-pane
  gpt_code "/spec-base-attach sessionId=sb-ahjt3h" --resume "session with spaces"
  assert_capture $'5\n7:--model\n11:gpt-5.6-sol\n37:/spec-base-attach sessionId=sb-ahjt3h\n8:--resume\n19:session with spaces'

  monet "/spec-base-attach sessionId=sb-ahjt3h" --resume "session with spaces"
  assert_capture $'3\n37:/spec-base-attach sessionId=sb-ahjt3h\n8:--resume\n19:session with spaces'
  unset HERDR_PANE_ID
}

exercise_launchers "$repo_zshrc"
exercise_launchers "$active_zshrc"
print 'claude launcher argument forwarding: PASS'
```

This harness extracts and executes the actual launcher definitions, stubs only external processes, and covers both branch paths plus quoted argument boundaries.

- [ ] **Step 2: Run the harness and verify the current behavior fails**

Run:

```bash
zsh /tmp/test-claude-launcher-arguments.zsh
```

Expected: nonzero exit on the first `gpt_code` assertion. The capture contains only the two fixed model arguments because caller arguments are not yet appended.

- [ ] **Step 3: Append caller arguments in the tracked launchers**

In `/home/rgarber11/dotfiles/arch/zshrc`, make only these four array changes:

```zsh
# gpt_code, Herdr branch
      claude --model gpt-5.6-sol "$@"

# gpt_code, ordinary Kitty branch
    launch_command=(claude --model gpt-5.6-sol "$@")

# monet, Herdr branch
      claude "$@"

# monet, ordinary Kitty branch
    launch_command=(claude "$@")
```

Do not change the `sh -c` command, environment variables, terminal state handling, or Herdr metadata helper.

- [ ] **Step 4: Apply the same array changes to the active launchers**

In `/home/rgarber11/.zshrc`, apply the same four replacements shown in Step 3. Preserve every active-only environment value, including its current context-token settings and authentication configuration.

- [ ] **Step 5: Parse both zsh files**

Run:

```bash
zsh -n /home/rgarber11/dotfiles/arch/zshrc && zsh -n /home/rgarber11/.zshrc
```

Expected: exit status 0 with no output.

- [ ] **Step 6: Run the behavioral harness and verify both execution paths**

Run:

```bash
zsh /tmp/test-claude-launcher-arguments.zsh
```

Expected output ends with:

```text
claude launcher argument forwarding: PASS
```

The Herdr wrapper may also emit terminal color escape sequences before the final PASS line. All four calls for each file must satisfy their exact argument assertions.

- [ ] **Step 7: Check the focused tracked diff without staging user work**

Run:

```bash
git -C /home/rgarber11/dotfiles diff --check -- arch/zshrc
```

Expected: exit status 0 with no whitespace errors.

Do not commit `arch/zshrc`: it already contains the user's broader uncommitted launcher work, and staging the overlapping function hunks would capture changes outside this task. Leave the verified source change unstaged for the user.
