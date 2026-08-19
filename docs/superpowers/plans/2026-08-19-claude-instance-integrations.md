# Claude Instance Integrations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Herdr session reporting to `gpt_code()` and `monet()`, remove the misleading GPT Oh My Posh status line, and add the real-limit Oh My Posh status line to Monet without changing either Herdr agent name.

**Architecture:** Keep integration configuration inside each instance's existing `CLAUDE_CONFIG_DIR`. Both instances reference Herdr's canonical managed hook; only Monet invokes the shared Oh My Posh Claude theme. The zsh launchers and naming helper remain unchanged.

**Tech Stack:** Claude Code JSON settings, POSIX shell Herdr hook, zsh launchers, Oh My Posh Claude status-line adapter, jq, PTY smoke tests.

---

### Task 1: Configure the GPT Claude instance

**Files:**
- Modify: `/home/rgarber11/.config/claude-other/settings.json`
- Reference only: `/home/rgarber11/.claude/settings.json`
- Reference only: `/home/rgarber11/.claude/hooks/herdr-agent-state.sh`

- [ ] **Step 1: Verify the current GPT settings fail the target contract**

Run:

```bash
jq -e '
  (.hooks.SessionStart[0].matcher == "*") and
  (.hooks.SessionStart[0].hooks[0].type == "command") and
  (.hooks.SessionStart[0].hooks[0].command == "bash '/home/rgarber11/.claude/hooks/herdr-agent-state.sh' session") and
  (.hooks.SessionStart[0].hooks[0].timeout == 10) and
  (has("statusLine") | not)
' /home/rgarber11/.config/claude-other/settings.json
```

Expected: nonzero exit because `hooks` is absent and `statusLine` is present.

- [ ] **Step 2: Add the canonical Herdr hook and remove the status line**

Preserve every unrelated setting. The resulting file must be:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "env": {
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL": "1",
    "DISABLE_TELEMETRY": "1",
    "DISABLE_ERROR_REPORTING": "1",
    "DISABLE_FEEDBACK_COMMAND": "1"
  },
  "permissions": {
    "deny": [
      "Read(~/.cli-proxy-api/**)",
      "Read(~/.claude/**)",
      "Read(~/.ssh/**)",
      "Read(~/.gnupg/**)",
      "Read(~/.aws/**)",
      "Read(~/.zshrc)"
    ]
  },
  "hooks": {
    "SessionStart": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash '/home/rgarber11/.claude/hooks/herdr-agent-state.sh' session",
            "timeout": 10
          }
        ]
      }
    ]
  },
  "disableClaudeAiConnectors": true,
  "skipWebFetchPreflight": true,
  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "allowUnsandboxedCommands": false
  },
  "theme": "dark",
  "autoMode": {
    "classifyAllShell": true
  },
  "tui": "fullscreen"
}
```

- [ ] **Step 3: Verify the GPT settings contract passes**

Run the `jq -e` expression from Step 1 again.

Expected: exit 0 and output `true`.

- [ ] **Step 4: Smoke-test a real cli-proxy-api-backed Claude request**

Run:

```bash
env \
  CLAUDE_CONFIG_DIR="$HOME/.config/claude-other/" \
  ANTHROPIC_BASE_URL="http://127.0.0.1:8317" \
  ENABLE_CLAUDEAI_MCP_SERVERS=false \
  DISABLE_TELEMETRY=1 \
  CLAUDE_CODE_MAX_CONTEXT_TOKENS=372000 \
  CLAUDE_CODE_AUTO_COMPACT_WINDOW=372000 \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
  ANTHROPIC_AUTH_TOKEN="$(yq -r '.api-keys[0]' "$HOME/.cli-proxy-api/config.yaml")" \
  ANTHROPIC_DEFAULT_OPUS_MODEL="gpt-5.6-sol" \
  ANTHROPIC_DEFAULT_SONNET_MODEL="gpt-5.6-terra" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL="gpt-5.6-luna" \
  claude --model gpt-5.6-sol --print 'Reply with exactly GPT_CONFIG_OK'
```

Expected: `GPT_CONFIG_OK`. The settings contract from Step 3 proves this instance has no custom status-line command; print mode proves the configured proxy/model path still works.

No commit is created for this task because the modified file is live Claude runtime state outside the dotfiles repository.

### Task 2: Configure the Monet Claude instance

**Files:**
- Modify: `/home/rgarber11/.config/claude-monet/settings.json`
- Reference only: `/home/rgarber11/.config/oh-my-posh/claude.omp.json`
- Reference only: `/home/rgarber11/.claude/hooks/herdr-agent-state.sh`

- [ ] **Step 1: Verify the current Monet settings fail the target contract**

Run:

```bash
jq -e '
  (.hooks.SessionStart[0].matcher == "*") and
  (.hooks.SessionStart[0].hooks[0].type == "command") and
  (.hooks.SessionStart[0].hooks[0].command == "bash '/home/rgarber11/.claude/hooks/herdr-agent-state.sh' session") and
  (.hooks.SessionStart[0].hooks[0].timeout == 10) and
  (.statusLine.type == "command") and
  (.statusLine.command == "oh-my-posh claude --config ~/.config/oh-my-posh/claude.omp.json") and
  (.statusLine.padding == 0)
' /home/rgarber11/.config/claude-monet/settings.json
```

Expected: nonzero exit because `hooks` and `statusLine` are absent.

- [ ] **Step 2: Add the canonical Herdr hook and Oh My Posh status line**

The resulting file must be:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash '/home/rgarber11/.claude/hooks/herdr-agent-state.sh' session",
            "timeout": 10
          }
        ]
      }
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "oh-my-posh claude --config ~/.config/oh-my-posh/claude.omp.json",
    "padding": 0
  },
  "theme": "dark",
  "tui": "fullscreen"
}
```

- [ ] **Step 3: Verify the Monet settings contract passes**

Run the `jq -e` expression from Step 1 again.

Expected: exit 0 and output `true`.

- [ ] **Step 4: Verify Oh My Posh renders Monet's rate-limit payload**

Send a representative Claude Code status payload through the configured command:

```bash
printf '%s\n' '{"cwd":"/tmp/project","session_id":"monet-test","transcript_path":"/tmp/monet-test.jsonl","model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"workspace":{"current_dir":"/tmp/project","project_dir":"/tmp/project"},"version":"2.1.235","cost":{"total_cost_usd":0,"total_duration_ms":1000,"total_api_duration_ms":500,"total_lines_added":3,"total_lines_removed":1},"context_window":{"total_input_tokens":1000,"total_output_tokens":100,"context_window_size":200000,"current_usage":{"input_tokens":1000,"output_tokens":100}},"rate_limits":{"five_hour":{"used_percentage":40,"resets_at":1787169600},"seven_day":{"used_percentage":20,"resets_at":1787596800}}}' \
  | oh-my-posh claude --plain --config "$HOME/.config/oh-my-posh/claude.omp.json"
```

Expected: output includes `5h`, `7d`, `Opus 4.6`, `+3/-1`, and non-empty gauges.

- [ ] **Step 5: Smoke-test a real Monet Claude request**

Run:

```bash
env CLAUDE_CONFIG_DIR="$HOME/.config/claude-monet/" \
  claude --print 'Reply with exactly MONET_CONFIG_OK'
```

Expected: `MONET_CONFIG_OK` using Monet's existing OAuth credentials.

No commit is created for this task because the modified file is live Claude runtime state outside the dotfiles repository.

### Task 3: Verify Herdr reporting and preserved launcher names

**Files:**
- Verify only: `/home/rgarber11/.zshrc:172-264`
- Verify only: `/home/rgarber11/dotfiles/arch/zshrc:62-152`
- Verify only: `/home/rgarber11/.claude/hooks/herdr-agent-state.sh`
- Verify only: `/home/rgarber11/.config/claude-other/settings.json`
- Verify only: `/home/rgarber11/.config/claude-monet/settings.json`

- [ ] **Step 1: Start an isolated Unix socket receiver**

Create a temporary directory, listen on `$tmpdir/herdr.sock`, and capture one newline-delimited request. The receiver must reply with `{}` so the hook completes without waiting for its read timeout:

```python
import json
import os
import socket
import tempfile
import threading

root = tempfile.TemporaryDirectory(prefix="herdr-config-test-")
socket_path = os.path.join(root.name, "herdr.sock")
received = []

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(socket_path)
server.listen(2)

def receive_requests():
    for _ in range(2):
        connection, _ = server.accept()
        with connection:
            payload = b""
            while not payload.endswith(b"\n"):
                payload += connection.recv(4096)
            received.append(json.loads(payload))
            connection.sendall(b"{}\n")

thread = threading.Thread(target=receive_requests)
thread.start()
```

Run this in a persistent Python kernel so `socket_path`, `received`, `thread`, and `root` remain available for Steps 2-4.

- [ ] **Step 2: Invoke the configured GPT hook through an isolated Herdr environment**

Read the hook command from `/home/rgarber11/.config/claude-other/settings.json`, then execute it with `HERDR_ENV=1`, `HERDR_SOCKET_PATH=$socket_path`, and `HERDR_PANE_ID=gpt-pane`. Send this JSON on stdin:

```json
{
  "hook_event_name": "SessionStart",
  "session_id": "gpt-session",
  "transcript_path": "/tmp/gpt-session.jsonl",
  "source": "startup"
}
```

Expected: command exits 0.

- [ ] **Step 3: Invoke the configured Monet hook through the same isolated Herdr environment**

Read the hook command from `/home/rgarber11/.config/claude-monet/settings.json`, execute it with pane ID `monet-pane`, and send:

```json
{
  "hook_event_name": "SessionStart",
  "session_id": "monet-session",
  "transcript_path": "/tmp/monet-session.jsonl",
  "source": "startup"
}
```

Expected: command exits 0.

- [ ] **Step 4: Assert both Herdr reports contain the intended session data**

Join the receiver thread, then assert:

```python
thread.join(timeout=5)
assert not thread.is_alive()

reports = {item["params"]["pane_id"]: item for item in received}
assert reports["gpt-pane"]["method"] == "pane.report_agent_session"
assert reports["gpt-pane"]["params"]["agent_session_id"] == "gpt-session"
assert reports["gpt-pane"]["params"]["agent_session_path"] == "/tmp/gpt-session.jsonl"
assert reports["monet-pane"]["method"] == "pane.report_agent_session"
assert reports["monet-pane"]["params"]["agent_session_id"] == "monet-session"
assert reports["monet-pane"]["params"]["agent_session_path"] == "/tmp/monet-session.jsonl"

server.close()
root.cleanup()
```

Expected: all assertions pass. The isolated pane IDs ensure this check cannot alter the current Herdr pane's session association.

- [ ] **Step 5: Verify both launcher sources preserve their naming calls**

Run:

```bash
for file in "$HOME/.zshrc" "$HOME/dotfiles/arch/zshrc"; do
  grep -F '_name_herdr_agent "$HERDR_PANE_ID" gpt_code &!' "$file"
  grep -F '_name_herdr_agent "$HERDR_PANE_ID" monet &!' "$file"
done
```

Expected: four matching lines, one GPT and one Monet call in each file.

- [ ] **Step 6: Parse both launcher sources without modifying them**

Run:

```bash
zsh -n "$HOME/.zshrc"
zsh -n "$HOME/dotfiles/arch/zshrc"
```

Expected: both commands exit 0 with no output.

No source commit is required: launcher sources remain byte-for-byte unchanged, and the only runtime changes are outside git.
