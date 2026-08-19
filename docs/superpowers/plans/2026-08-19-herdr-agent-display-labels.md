# Herdr Agent Display Labels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace unique numbered Herdr custom names with repeatable display-only `gpt_code` and `monet` labels, matching how concurrent OMP panes all display `omp`.

**Architecture:** The zsh launcher helper will wait until Herdr detects the Claude pane, then report presentation metadata scoped to agent `claude`. Runtime migration will clear only matching GPT/Monet custom names and apply the same metadata, leaving agent identity, session authority, and unrelated panes untouched. Do not use `applies-to-source`: the canonical hook supplies session identity but does not own lifecycle hook authority, so that guard is accepted but hides presentation metadata.

**Tech Stack:** zsh, Herdr 0.8.0 CLI/API, JSON inspection, dotfiles shell test suite.

---

### Task 1: Replace custom naming with display metadata

**Files:**
- Modify: `/home/rgarber11/dotfiles/arch/zshrc:62-152`
- Modify: `/home/rgarber11/.zshrc:177-269`
- Reference: `/home/rgarber11/.cache/yay/herdr/herdr-0.8.0.tar.gz:herdr-0.8.0/src/app/agents.rs`
- Reference: `/home/rgarber11/.cache/yay/herdr/herdr-0.8.0.tar.gz:herdr-0.8.0/src/app/api/panes.rs`

- [ ] **Step 1: Capture the failing source contract**

Run this focused check against both launcher files:

```bash
python3 - <<'PY'
from pathlib import Path

for path in (Path.home() / ".zshrc", Path.home() / "dotfiles/arch/zshrc"):
    source = path.read_text()
    assert "_label_herdr_agent()" in source
    assert "_name_herdr_agent" not in source
    assert "for suffix in" not in source
    assert 'herdr pane report-metadata \\' in source
    assert '--source user:zsh-claude-display \\' in source
    assert '--agent claude \\' in source
    assert "--applies-to-source" not in source
    assert '--display-agent "$display_label"' in source
    assert '_label_herdr_agent "$HERDR_PANE_ID" gpt_code &!' in source
    assert '_label_herdr_agent "$HERDR_PANE_ID" monet &!' in source
PY
```

Expected: assertion failure because the files still define and call `_name_herdr_agent` and contain the suffix loop.

- [ ] **Step 2: Replace the helper in the tracked launcher**

Replace `_name_herdr_agent` in `/home/rgarber11/dotfiles/arch/zshrc` with:

```zsh
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
```

Change only these callers:

```zsh
_label_herdr_agent "$HERDR_PANE_ID" gpt_code &!
```

```zsh
_label_herdr_agent "$HERDR_PANE_ID" monet &!
```

Do not alter launcher commands, colors, environment variables, cleanup blocks, or unrelated shell configuration.

- [ ] **Step 3: Apply the identical helper and caller changes to the live launcher**

Make the same replacement in `/home/rgarber11/.zshrc`. The helper and both call lines must be byte-identical to their tracked counterparts even though the surrounding files differ.

- [ ] **Step 4: Run the source contract and zsh parser checks**

Run the Step 1 Python contract again, then:

```bash
zsh -n /home/rgarber11/.zshrc
zsh -n /home/rgarber11/dotfiles/arch/zshrc
```

Expected: the Python contract exits 0; both zsh parses exit 0 with no output.

- [ ] **Step 5: Review the launcher edits without staging user work**

Run:

```bash
git diff --check -- arch/zshrc
git diff -- arch/zshrc
```

Expected: no whitespace errors. Compare the resulting helper and two call lines with the pre-edit snapshot. The full git diff also contains the user's pre-existing uncommitted `gpt_code()`/`monet()` launcher work; do not treat that existing diff as part of this change.

- [ ] **Step 6: Leave the tracked launcher unstaged**

Do not stage or commit `arch/zshrc`: the intended display-label edits share a file and hunks with the user's pre-existing uncommitted launcher work, so staging the file would capture work that this task does not own. Do not add the pre-existing untracked HTML artifact. The live `.zshrc` is outside git and remains active runtime configuration.

### Task 2: Migrate and verify active Herdr panes

**Files:**
- Runtime state only: active Herdr panes whose custom names match `gpt_code`, `gpt_code_<number>`, `monet`, or `monet_<number>`
- Verify: `/home/rgarber11/.zshrc`
- Verify: `/home/rgarber11/dotfiles/arch/zshrc`

- [ ] **Step 1: Capture the failing runtime contract**

Run:

```bash
python3 - <<'PY'
import json
import subprocess

agents = json.loads(subprocess.run(
    ["herdr", "agent", "list"], check=True, capture_output=True, text=True
).stdout)["result"]["agents"]
gpt = [item for item in agents if item.get("name") in {"gpt_code", "gpt_code_2"}]
assert len(gpt) >= 2
assert all(item.get("name") is None for item in gpt)
assert all(item.get("display_agent") == "gpt_code" for item in gpt)
PY
```

Expected: assertion failure because the active GPT panes still have unique custom names and no display metadata.

- [ ] **Step 2: Migrate only matching custom-named panes**

Run this controlled migration once:

```python
import json
import re
import subprocess

response = subprocess.run(
    ["herdr", "agent", "list"], check=True, capture_output=True, text=True
)
agents = json.loads(response.stdout)["result"]["agents"]
pattern = re.compile(r"^(gpt_code|monet)(?:_[0-9]+)?$")
targets = []

for agent in agents:
    name = agent.get("name")
    match = pattern.fullmatch(name or "")
    if match:
        targets.append((agent["pane_id"], match.group(1)))

for pane_id, display_agent in targets:
    subprocess.run(
        ["herdr", "agent", "rename", pane_id, "--clear"], check=True
    )
    subprocess.run(
        [
            "herdr", "pane", "report-metadata", pane_id,
            "--source", "user:zsh-claude-display",
            "--agent", "claude",
            "--display-agent", display_agent,
        ],
        check=True,
    )

print(json.dumps(targets))
```

Expected: output lists only the currently named GPT/Monet pane IDs and intended plain display labels. No unrelated pane is changed.

- [ ] **Step 3: Verify duplicate display labels and preserved Claude authority**

Run:

```python
import json
import subprocess

agents = json.loads(subprocess.run(
    ["herdr", "agent", "list"], check=True, capture_output=True, text=True
).stdout)["result"]["agents"]
gpt = [item for item in agents if item.get("display_agent") == "gpt_code"]
assert len(gpt) >= 2
assert len({item["pane_id"] for item in gpt}) == len(gpt)
assert all(item.get("name") is None for item in gpt)
assert all(item.get("agent") == "claude" for item in gpt)
assert all(item.get("agent_session", {}).get("source") == "herdr:claude" for item in gpt)
assert all(not str(item.get("display_agent", "")).rsplit("_", 1)[-1].isdigit() for item in gpt)
print(json.dumps([
    {
        "pane_id": item["pane_id"],
        "name": item.get("name"),
        "agent": item.get("agent"),
        "display_agent": item.get("display_agent"),
        "session_source": item.get("agent_session", {}).get("source"),
    }
    for item in gpt
], indent=2))
```

Expected: at least two distinct pane IDs; every custom name is null; every displayed agent is exactly `gpt_code`; underlying identity is `claude`; session source remains `herdr:claude`.

If active Monet panes existed in Step 2, run the same assertions for `display_agent == "monet"`.

- [ ] **Step 4: Exercise the updated helper against one controlled active Claude pane**

In zsh, source only the helper definition from the updated launcher or invoke its exact metadata command for a known active Claude pane. Confirm repeated invocation is idempotent: `display_agent` remains the intended plain label, custom `name` remains null, and the command exits 0 twice.

- [ ] **Step 5: Run the complete dotfiles verification suite**

```bash
cd /home/rgarber11/dotfiles
./tests/run.sh
```

Expected: `all checks passed` with no failed assertions.

- [ ] **Step 6: Confirm runtime migration created no repository changes**

Run:

```bash
git status --short
```

Expected: only the user's pre-existing unrelated worktree entries remain; runtime Herdr metadata does not modify repository files.
