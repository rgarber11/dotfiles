# Herdr Remote Neovim Clipboard Bridge Implementation Plan

## Implementation outcome

> **Completed and verified at `baf9081`.** This file preserves the original implementation checklist as historical context; it is not a current runbook. Original Tasks 3 and 4 were superseded by the evidence-driven responder and tunnel designs summarized below. The canonical final contract and observed verification results are in [the implemented design spec](../specs/2026-08-19-herdr-remote-clipboard-design.md).

The final implementation uses a function-owned loopback socat responder that runs a fresh `wl-paste` after every accept, plus a second private, nonpersistent OpenSSH control master that owns the exact reverse forward. Herdr's `ControlPersist=yes` master made an SSH-config forward survive detach and collide with later sessions, so `~/.ssh/config` remains unchanged. The provider runs `nc 127.0.0.1 52052` without the half-close option because Neovim already closes provider stdin; using that option made socat terminate before returning clipboard output.

**Goal:** Make `"+p` in Neovim inside `herdr --remote richard-worktree-2.coder` read the Arch desktop's current Wayland text clipboard while preserving OSC 52 for remote yanks.

**Architecture:** `herdr_remote()` owns a loopback socat `reuseaddr,fork` responder and a private `ControlPersist=no` OpenSSH master/reverse forward, each in an owned `setsid` process group. Headless Neovim uses OSC 52 callbacks for copy and `nc 127.0.0.1 52052` for uncached paste.

**Tech Stack:** Zsh, socat, `setsid`, OpenSSH control sockets and reverse forwarding, OpenBSD netcat, `wl-clipboard`, Neovim 0.12 Lua clipboard provider, Bash/Podman dotfiles tests.

---

## File map

- `tests/run.sh` — container-level assertions that the Coder install supplies netcat and configures the expected headless Neovim provider.
- `headless/setup/10-packages.sh` — installs Ubuntu's `netcat-openbsd` package on each ephemeral Coder container.
- `shared/nvim/init.lua` — selects the asymmetric clipboard provider only for the existing headless/Coder profile.
- `arch/zshrc` — canonical tracked desktop `herdr_remote()` implementation, including responder, tunnel, and whole-process-group cleanup.
- `/home/rgarber11/.zshrc` — active desktop copy of the same `herdr_remote()` function; only that function was updated because the file has unrelated machine-local drift.
- `/home/rgarber11/.ssh/config` — unchanged; it has no clipboard stanza.
- `docs/superpowers/specs/2026-08-19-herdr-remote-clipboard-design.md` — canonical implemented and verified behavioral, lifecycle, and security contract.

Do not replace the active desktop Zsh file with the tracked copy. Make surgical edits only.

## Historical implementation record

> The unchecked boxes and commands below record the original proposal, not remaining work or current instructions. In particular, Tasks 3 and 4 contain superseded approaches and are labeled accordingly.

### Task 1: Capture the broken OSC 52 paste baseline

**Files:** None.

- [ ] **Step 1: Put a unique value on the desktop clipboard**

Run on the Arch desktop:

```bash
printf 'herdr-clipboard-baseline-2026-08-19' | wl-copy
```

Expected: `wl-paste --no-newline` prints `herdr-clipboard-baseline-2026-08-19`.

- [ ] **Step 2: Reproduce the current failure in the actual surface**

Run `herdr_remote()`, open Neovim in a remote Herdr pane, create an empty buffer, and execute:

```vim
"+p
```

Expected before implementation: Neovim does not paste the unique value. It displays the OSC 52 waiting message after one second and eventually reports `Timed out waiting for a clipboard response from the terminal`, unless interrupted.

- [ ] **Step 3: Detach cleanly**

Detach from Herdr with its configured detach binding and return to the desktop shell.

Expected: the original `herdr_remote()` restores the prior Kitty colors.

### Task 2: Add the tested Coder-side provider

**Files:**
- Modify: `tests/run.sh:88-188`
- Modify: `headless/setup/10-packages.sh:6-13`
- Modify: `shared/nvim/init.lua:56-62`

- [ ] **Step 1: Add failing install and provider assertions**

In the `CHECKS` heredoc in `tests/run.sh`, add netcat discovery after the Herdr discovery:

```bash
echo "nc=$(command -v nc || echo none)"
```

Add a second output file to the existing headless Neovim invocation, before `-c qa`:

```bash
  -c 'lua local cb=vim.g.clipboard; local f=assert(io.open("/tmp/nvim-clipboard-provider","w")); f:write(table.concat({ cb.name or "none", type(cb.copy["+"]), table.concat(cb.paste["+"], " "), tostring(cb.cache_enabled) }, "|")); f:close()' \
```

After the existing `colorscheme=...` output line, add:

```bash
echo "clipboard_provider=$(cat /tmp/nvim-clipboard-provider 2>/dev/null || echo unknown)"
```

Add these assertions with the other first-install assertions:

```bash
assert_not_contains "netcat installed" "nc=none" "$CHECKS"
assert_contains "headless Neovim uses the Herdr clipboard bridge" \
  "clipboard_provider=herdr-remote|function|nc 127.0.0.1 52052|0" "$CHECKS"
```

- [ ] **Step 2: Run the changed test and verify the new contract fails**

Run:

```bash
./tests/run.sh --keep
```

Expected before implementation: the summary reports failures for `netcat installed` and `headless Neovim uses the Herdr clipboard bridge`. Existing unrelated assertions retain their prior result.

- [ ] **Step 3: Install OpenBSD netcat in the Coder profile**

Change the final package row in `headless/setup/10-packages.sh` to:

```bash
  qrencode btop file netcat-openbsd
```

Do not add netcat to the container base image; the test must exercise `install.sh`'s package list.

- [ ] **Step 4: Configure the asymmetric headless provider**

Immediately after the existing `headless` assignment in `shared/nvim/init.lua`, add:

```lua
if headless then
  local osc52 = require 'vim.ui.clipboard.osc52'
  vim.g.clipboard = {
    name = 'herdr-remote',
    copy = {
      ['+'] = osc52.copy '+',
      ['*'] = osc52.copy '*',
    },
    paste = {
      ['+'] = { 'nc', '127.0.0.1', '52052' },
      ['*'] = { 'nc', '127.0.0.1', '52052' },
    },
    cache_enabled = 0,
  }
end
```

This must stay before `require('lazy').setup(...)` and before any call that can initialize the clipboard provider. Do not set `'clipboard'`; explicit register use remains the contract.

- [ ] **Step 5: Run the focused container contract again**

Run:

```bash
./tests/run.sh --keep
```

Expected: `netcat installed` and `headless Neovim uses the Herdr clipboard bridge` pass. The emitted provider line is exactly:

```text
clipboard_provider=herdr-remote|function|nc 127.0.0.1 52052|0
```

- [ ] **Step 6: Check Neovim diagnostics for the changed config**

Run the workspace diagnostics operation for `shared/nvim/init.lua` through the available Lua language server.

Expected: no new diagnostic on the clipboard provider block.

- [ ] **Step 7: Commit the Coder-side contract**

```bash
git add tests/run.sh headless/setup/10-packages.sh shared/nvim/init.lua
git commit -m "feat: bridge remote Neovim clipboard paste"
```

### Task 3: Historical / superseded desktop responder

> **Superseded — do not implement:** The netcat listener and sleep-based readiness below were replaced by one function-owned `setsid` socat master using `reuseaddr,fork`, an exact PID-bearing post-bind diagnostic in a private log, and whole-process-group cleanup. This section remains only as the original plan record.

**Files:**
- Modify: `arch/zshrc:85-94`
- Modify: `/home/rgarber11/.zshrc:194-203`

- [ ] **Step 1: Replace the tracked function**

Replace only `herdr_remote()` in `arch/zshrc` with:

```zsh
herdr_remote() {
  local original_kitty_colors clipboard_server_pid
  original_kitty_colors=$(kitty @ get-colors) || return
  {
    (
      local nc_pid=""
      trap '[[ -n "$nc_pid" ]] && kill "$nc_pid" 2>/dev/null; exit 0' TERM INT
      while true; do
        wl-paste --no-newline 2>/dev/null | nc -N -l 127.0.0.1 52052 >/dev/null &
        nc_pid=$!
        wait "$nc_pid" || exit
      done
    ) &
    clipboard_server_pid=$!

    # A bind failure terminates the responder immediately; do not open a Herdr
    # session that appears clipboard-capable when no listener exists.
    sleep 0.1
    if ! kill -0 "$clipboard_server_pid" 2>/dev/null; then
      wait "$clipboard_server_pid" 2>/dev/null
      print -u2 'herdr_remote: could not bind clipboard responder to 127.0.0.1:52052'
      return 1
    fi

    kitty @ set-colors '~/.config/kitty/kitty-themes/Catppuccin-Mocha.conf'
    herdr --remote richard-worktree-2.coder
  } always {
    if [[ -n "${clipboard_server_pid:-}" ]]; then
      kill "$clipboard_server_pid" 2>/dev/null
      wait "$clipboard_server_pid" 2>/dev/null
    fi
    kitty @ set-colors <(print -r -- "$original_kitty_colors")
  }
}
```

The netcat stdout redirect is required: Neovim's provider sends an empty stdin line, which must not be printed into the desktop terminal.

- [ ] **Step 2: Apply the same function to the active desktop config**

Replace only lines belonging to `herdr_remote()` in `/home/rgarber11/.zshrc` with the exact function above. Do not copy all of `arch/zshrc`; the active file contains unrelated machine-local configuration.

- [ ] **Step 3: Validate both Zsh files parse**

Run:

```bash
zsh -n arch/zshrc
zsh -n /home/rgarber11/.zshrc
```

Expected: both commands exit 0 with no output.

- [ ] **Step 4: Verify occupied-port failure without launching Herdr**

Start a temporary loopback listener on port 52052, then invoke `herdr_remote()` from an interactive Kitty Zsh.

Expected: the function prints:

```text
herdr_remote: could not bind clipboard responder to 127.0.0.1:52052
```

It returns nonzero, does not launch Herdr, does not leave a responder process, and restores the original Kitty colors. Stop the temporary listener afterward.

- [ ] **Step 5: Commit the canonical desktop function**

```bash
git add arch/zshrc
git commit -m "feat: serve clipboard during remote Herdr attach"
```

The active `/home/rgarber11/.zshrc` is outside this repository and is intentionally not part of the commit.

### Task 4: Historical / superseded SSH-config forwarding

> **Superseded — do not implement:** The SSH-config stanza below was replaced by a second function-owned `ControlPersist=no` master with a private control socket. The function waits with `ssh -O check`, installs the exact reverse forward synchronously with `ssh -O forward`, and cleans up with `ssh -O exit`, process-group/direct-PID fallback, wait, and private artifact removal. Herdr's `ControlPersist=yes` connection made the config-based forward outlive detach and collide with later sessions.

**Files:**
- Modify: `/home/rgarber11/.ssh/config:22` (append after the Coder-managed block)

- [ ] **Step 1: Confirm the forward is absent**

Run:

```bash
ssh -G richard-worktree-2.coder | sed -n '/^remoteforward /p;/^exitonforwardfailure /p'
```

Expected before the edit: no `remoteforward` line for port 52052 and `exitonforwardfailure no` or no explicit enabled value.

- [ ] **Step 2: Add the exact-host stanza outside the managed region**

Append after `# ------------END-CODER------------`:

```sshconfig

# Text clipboard reads for the session-scoped responder in herdr_remote().
Host richard-worktree-2.coder
  RemoteForward 127.0.0.1:52052 127.0.0.1:52052
  ExitOnForwardFailure yes
```

Do not edit inside Coder's managed markers. Do not apply this forward to wildcard `*.coder` hosts.

- [ ] **Step 3: Validate OpenSSH's resolved configuration**

Run:

```bash
ssh -G richard-worktree-2.coder | sed -n '/^remoteforward /p;/^exitonforwardfailure /p'
```

Expected: output contains a reverse-forward mapping from workspace loopback port 52052 to desktop loopback port 52052 and `exitonforwardfailure yes`.

- [ ] **Step 4: Validate ordinary SSH still connects**

Run:

```bash
ssh richard-worktree-2.coder 'printf connected'
```

Expected: `connected` and exit status 0. Because `herdr_remote()` is not running, the reverse-forward destination has no responder; establishing the SSH forward itself must still succeed.

No repository commit is associated with this task because `/home/rgarber11/.ssh/config` is machine-local.

### Task 5: Activate and verify the complete workflow

**Files:** No new source files. This task deploys the committed Coder-side changes and exercises the real UI.

- [ ] **Step 1: Make the Coder-side commit reachable by the workspace**

The local `coder-dotfiles` branch already contains user commits ahead of `origin/coder-dotfiles`. Before pushing, show the exact outgoing commit list and verify every commit belongs to this dotfiles effort. Then run:

```bash
git push origin coder-dotfiles
```

Expected: `origin/coder-dotfiles` advances without force. Never use `--force` or rewrite the existing branch.

- [ ] **Step 2: Refresh the Coder workspace dotfiles**

Run:

```bash
ssh richard-worktree-2.coder 'cd ~/dotfiles && git pull --ff-only && ~/dotfiles/install.sh'
```

Expected: fast-forward succeeds, `netcat-openbsd` is installed, and the installer completes without modifying the remote dotfiles clone.

- [ ] **Step 3: Verify remote prerequisites**

Run:

```bash
ssh richard-worktree-2.coder 'command -v nc && nvim --headless "+lua local c=vim.g.clipboard; print(c.name, table.concat(c.paste[\"+\"], \" \"))" +qa'
```

Expected output includes an `nc` path and:

```text
herdr-remote nc 127.0.0.1 52052
```

- [ ] **Step 4: Launch the real session and prove desktop-to-remote paste**

Put a fresh multi-line value on the desktop clipboard:

```bash
printf 'herdr clipboard line one\nherdr clipboard line two' | wl-copy
```

Launch `herdr_remote()`. In a remote Herdr pane, open Neovim in an empty buffer and execute `"+p`.

Expected buffer text:

```text
herdr clipboard line one
herdr clipboard line two
```

No OSC 52 waiting message appears.

- [ ] **Step 5: Prove repeated requests are live, not cached**

Without restarting Herdr or Neovim, replace the desktop clipboard:

```bash
printf 'herdr clipboard second value' | wl-copy
```

Execute `"+p` again in remote Neovim.

Expected: `herdr clipboard second value`, not the earlier two-line value.

- [ ] **Step 6: Prove OSC 52 copy still works**

In remote Neovim, select or set the text `remote-yank-through-osc52` and execute `"+y`. On the desktop run:

```bash
wl-paste --no-newline
```

Expected: `remote-yank-through-osc52`.

- [ ] **Step 7: Prove responder cleanup**

Detach or exit the `herdr_remote()` invocation, then run on the desktop:

```bash
nc -z 127.0.0.1 52052
```

Expected: nonzero exit status. No clipboard responder remains, and Kitty colors match their pre-attach values.

- [ ] **Step 8: Prove bridge absence fails promptly**

With `herdr_remote()` stopped, start ordinary SSH and remote Neovim, then execute `"+p`.

Expected: the provider reports a failed `nc` command promptly. It does not display `Waiting for OSC 52 response from the terminal` and does not wait ten seconds.

- [ ] **Step 9: Run final repository verification**

Run:

```bash
./tests/run.sh --keep
```

Expected: all assertions pass, including the two clipboard bridge assertions. Record the summary counts in the completion report.
