# Headless History Arrow Bindings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `zsh-history-substring-search` respond to Up and Down in both normal and application cursor-key modes in the dotfiles headless profile and the Talos Coder base image.

**Architecture:** Keep the existing plugin and load order. Extend each profile's adjacent key map with the SS3 sequences `Esc O A/B`, while retaining the existing CSI and Ctrl-P/Ctrl-N mappings. Protect the dotfiles-installed profile with an integration assertion and verify the Talos source with syntax and interactive image checks.

**Tech Stack:** zsh ZLE, zsh-history-substring-search, Bash integration harness, Podman, Coder CLI.

---

### Task 1: Add a failing dotfiles binding assertion

**Files:**
- Modify: `tests/run.sh:88-180`

- [ ] **Step 1: Record the installed SS3 bindings in the integration output**

Add these lines after the existing `no_system_rc` output:

```bash
echo "history_up_ss3=$(zsh -ic '[[ "$(bindkey "\\eOA")" == *history-substring-search-up ]] && print yes || print no' 2>/dev/null | tail -1)"
echo "history_down_ss3=$(zsh -ic '[[ "$(bindkey "\\eOB")" == *history-substring-search-down ]] && print yes || print no' 2>/dev/null | tail -1)"
```

Add these assertions after the `no_system_rc=yes` assertion:

```bash
assert_contains "application Up searches history substrings" "history_up_ss3=yes" "$CHECKS"
assert_contains "application Down searches history substrings" "history_down_ss3=yes" "$CHECKS"
```

- [ ] **Step 2: Run the focused integration harness and verify the regression is exposed**

Run:

```bash
./tests/run.sh --keep
```

Expected: the new application Up assertion fails with `history_up_ss3=no`; the application Down assertion is not reached or also reports `history_down_ss3=no`.

### Task 2: Bind application arrows in the dotfiles profile

**Files:**
- Modify: `headless/zshrc:36-45`
- Test: `tests/run.sh`

- [ ] **Step 1: Add SS3 mappings beside the existing CSI mappings**

Make the binding block read:

```zsh
source "$ZSH_PLUGIN_DIR/zsh-history-substring-search/zsh-history-substring-search.zsh"
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
bindkey '\eOA' history-substring-search-up
bindkey '\eOB' history-substring-search-down
bindkey -M emacs '^P' history-substring-search-up
bindkey -M emacs '^N' history-substring-search-down
```

- [ ] **Step 2: Parse the modified shell configuration**

Run:

```bash
zsh -n headless/zshrc
```

Expected: exit status 0 and no output.

- [ ] **Step 3: Re-run the integration harness**

Run:

```bash
./tests/run.sh --keep
```

Expected: both new assertions print `ok`, and the harness ends with `ALL TESTS PASSED`.

- [ ] **Step 4: Commit the dotfiles behavior change**

```bash
git add headless/zshrc tests/run.sh docs/superpowers/plans/2026-08-18-headless-history-arrow-bindings.md
git commit -m "fix: bind application arrows to history search"
```

### Task 3: Bind application arrows in the Talos base image

**Files:**
- Modify: `/home/rgarber11/PhoeniciaLabs/talos-home/coder/templates/dsp-base/build/zsh/dsp-base.zsh:66-76`

- [ ] **Step 1: Add the same SS3 mappings to the baked profile**

Make the binding block read:

```zsh
source "$ZSH_PLUGIN_DIR/zsh-history-substring-search/zsh-history-substring-search.zsh"
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
bindkey '\eOA' history-substring-search-up
bindkey '\eOB' history-substring-search-down
bindkey -M emacs '^P' history-substring-search-up
bindkey -M emacs '^N' history-substring-search-down
```

- [ ] **Step 2: Parse the baked shell configuration**

Run:

```bash
zsh -n coder/templates/dsp-base/build/zsh/dsp-base.zsh
```

from `/home/rgarber11/PhoeniciaLabs/talos-home`.

Expected: exit status 0 and no output.

- [ ] **Step 3: Commit the Talos behavior change**

```bash
git add coder/templates/dsp-base/build/zsh/dsp-base.zsh
git commit -m "fix: bind application arrows to Coder history search"
```

### Task 4: Exercise both terminal encodings

**Files:**
- Verify: `headless/zshrc`
- Verify: `/home/rgarber11/PhoeniciaLabs/talos-home/coder/templates/dsp-base/build/zsh/dsp-base.zsh`

- [ ] **Step 1: Start an interactive PTY-backed Coder shell**

Run `coder ssh richard-worktree-2` in a managed PTY. In that shell, install the new SS3 mappings for the smoke test if the committed dotfiles change has not yet been deployed:

```zsh
bindkey '\eOA' history-substring-search-up
bindkey '\eOB' history-substring-search-down
```

- [ ] **Step 2: Verify normal cursor mode**

Run a distinctive command, then start a new command containing only a middle substring and inject `Esc [ A`. Expected: the buffer becomes the distinctive full command. Inject `Esc [ B`; expected: traversal moves forward through matching history.

- [ ] **Step 3: Verify application cursor mode**

Repeat with another distinctive command and inject `Esc O A`. Expected: the buffer becomes the distinctive full command. Inject `Esc O B`; expected: traversal moves forward through matching history.

- [ ] **Step 4: Inspect all active mappings**

Run:

```zsh
bindkey '^[[A'
bindkey '^[[B'
bindkey '\eOA'
bindkey '\eOB'
```

Expected: Up encodings map to `history-substring-search-up`; Down encodings map to `history-substring-search-down`.
