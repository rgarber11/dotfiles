# Herdr remote Neovim clipboard bridge design

Date: 2026-08-19
Status: implemented and verified at `baf9081`

## Goal

Make `"+p` in Neovim running inside `herdr --remote richard-worktree-2.coder` paste the Arch desktop's current Wayland clipboard without relying on OSC 52 clipboard queries.

Preserve the working path in the opposite direction: remote Neovim yanks continue to update the desktop clipboard through Neovim's bundled OSC 52 copy provider and Herdr's existing OSC 52 write forwarding.

## Background

The Coder workspace has no X11 or Wayland display. Neovim 0.12.4 therefore falls back to its bundled OSC 52 clipboard provider. OSC 52 writes traverse Herdr, so `"+y` works. OSC 52 reads do not traverse Herdr correctly, so the old `"+p` path emitted a query, waited for a response, and eventually timed out.

Herdr pull request 1414 did not provide a usable query path. It wrote responses to the outer terminal rather than the originating child PTY, emitted an invalid response form, discarded the originating pane in remote mode, lacked a client-to-server response route, and changed the wire protocol without a version bump. Its proposed unconditional clipboard reads also gave every process in every pane access to the host clipboard without an explicit policy.

## Scope

Included:

- Text clipboard reads from the Arch desktop into headless Neovim's `+` and `*` registers.
- Session-scoped activation tied to `herdr_remote()`.
- Loopback-only transport through an authenticated private SSH connection.
- Existing OSC 52 clipboard writes from remote Neovim to the desktop.
- Fast failure when the local bridge is unavailable.
- Installation and verification of the remote `nc` command required by Neovim's custom provider.

Excluded:

- Images or arbitrary binary clipboard formats.
- General Herdr OSC 52 query support.
- Clipboard access for other remote hosts.
- A persistent desktop clipboard daemon.
- Clipboard history, synchronization, retries, or caching.
- Changes to Herdr itself.

## Architecture

The bridge has three parts. `herdr_remote()` owns the session-scoped socat responder and private SSH master. The persistent headless Neovim configuration defines the provider, and Neovim owns each per-paste `nc` process.

### Local clipboard responder

The desktop function creates a private `mktemp` diagnostic log, disables Zsh job-control monitoring while launching the process, and starts one loopback socat master in its own session and process group:

```text
setsid socat -d -d -lf <private-log> \
  TCP4-LISTEN:52052,bind=127.0.0.1,reuseaddr,fork \
  SYSTEM:'wl-paste --no-newline 2>/dev/null'
```

`reuseaddr,fork` leaves the master listening while a child handles each accepted connection. The `SYSTEM` command is started only after that accept, so every paste request runs a new `wl-paste --no-newline` and reads the current clipboard rather than a value captured when the listener started.

The function does not infer readiness from a delay. It verifies that the launched PID is also the observed process-group ID and waits for socat's exact post-bind diagnostic, `socat[<pid>] N listening on AF=2 127.0.0.1:52052`, in the private log. Failure to reach that state aborts before Herdr starts.

The original `MONITOR` state is restored after each background launch. Cleanup signals the owned socat process group so forked descendants cannot survive, falls back to the direct PID if needed, waits for the master, and removes the diagnostic log.

### Private SSH reverse forward

`~/.ssh/config` has no clipboard stanza. Instead, `herdr_remote()` creates a private `mktemp -d` directory and control socket, then starts a second, nonpersistent OpenSSH master under its own `setsid` process group. It uses `-M -S <socket> -N -T -n`, `ControlPersist=no`, `ExitOnForwardFailure=yes`, and `ClearAllForwardings=yes`.

The function waits until the control socket exists and `ssh -O check` succeeds, while also requiring the observed process-group ID to equal the launched PID. It then synchronously installs exactly this reverse forward through the private master:

```text
ssh -S <socket> -O forward \
  -R 127.0.0.1:52052:127.0.0.1:52052 \
  richard-worktree-2.coder
```

This separation is required because Herdr's own connection uses `ControlPersist=yes`. A forwarding rule inherited from SSH configuration therefore outlived Herdr detach in the persistent master and collided with the next attach. The function-owned master makes the tunnel lifetime explicit and independent of Herdr's persistent connection.

On every return, error, or interrupt, cleanup first requests `ssh -O exit`, then signals the owned process group with a direct-PID fallback, waits for the master, removes the private control socket and related mux files, and removes its temporary directory.

Both forward endpoints use explicit `127.0.0.1` bind addresses. No listener is exposed to the desktop LAN, the Coder pod network, or the public internet.

### Headless Neovim provider

The shared Neovim configuration installs a custom `vim.g.clipboard` provider before clipboard-provider initialization, but only when the existing `headless` detection is true.

The provider is intentionally asymmetric:

- `copy["+"]` and `copy["*"]` use `require('vim.ui.clipboard.osc52').copy(...)`.
- `paste["+"]` and `paste["*"]` run `nc 127.0.0.1 52052`.
- Caching is disabled with `cache_enabled = 0`; the source of truth is the current desktop clipboard.

The provider deliberately omits netcat's half-close option. Neovim closes provider stdin itself; adding that option made netcat close its write side and caused socat to terminate the per-connection command before returning clipboard output.

Desktop Neovim keeps normal automatic clipboard-tool detection and remains unchanged. There is no OSC 52 read fallback. When the responder or reverse forward is absent, the TCP connection fails promptly and Neovim receives no clipboard text instead of entering OSC 52's ten-second wait path.

## Data flow

### Paste: desktop to remote Neovim

1. The user invokes `"+p` in Neovim inside a remote Herdr pane.
2. Neovim starts `nc` against workspace loopback port `52052`.
3. The private OpenSSH master carries that connection through its exact reverse forward to desktop loopback port `52052`.
4. Socat accepts the connection and forks a handler.
5. That handler starts a fresh `wl-paste --no-newline` and returns its bytes through SSH.
6. Neovim closes provider stdin, receives stdout, and applies normal `+`-register paste semantics.

### Yank: remote Neovim to desktop

1. The user invokes `"+y` in remote Neovim.
2. Neovim's OSC 52 copy callback sends the encoded selection to the TUI.
3. Herdr forwards the OSC 52 write to the local terminal.
4. Kitty writes the decoded text to the Wayland clipboard.

The socat responder and private SSH master are not involved in this direction.

## Error handling and lifecycle

- Responder startup requires the exact post-bind socat diagnostic and the expected owned process group. An occupied port, early exit, or unreadable readiness state reports `herdr_remote: could not bind clipboard responder to 127.0.0.1:52052` and prevents Herdr launch.
- Tunnel startup requires the private master to remain alive, own its process group, expose its control socket, pass `ssh -O check`, and accept the synchronous exact reverse forward. Failure reports `herdr_remote: could not establish clipboard SSH tunnel` and prevents Herdr launch.
- If `wl-paste` fails or the clipboard has no text representation, that connection returns no text; the socat master remains available for later requests.
- A Zsh `always` block performs complete cleanup on normal return, setup failure, Herdr failure, or interrupt. It shuts down the private SSH master and socat process groups, waits for both direct children, removes private artifacts, and restores the original Kitty colors.
- `localoptions` restores the caller's option state, including `MONITOR`, and `localtraps` restores the caller's INT trap after the function-local trap has mapped an interrupt to status 130.
- Clipboard text is transferred verbatim. No shell interpolation or command construction from clipboard contents is used.

## Security boundary

This is an explicit clipboard-read opt-in, not a claim that clipboard reads are harmless.

While a function-owned responder and tunnel are live, any process running as the Coder user can connect to workspace loopback port `52052` and read the desktop's current text clipboard. Trusting the machine means accepting that its processes and dependencies receive this capability for that interval. The design narrows exposure by:

- binding both sides to loopback;
- carrying traffic only through the authenticated, function-owned SSH master;
- starting the responder and tunnel only for an explicit `herdr_remote()` invocation; and
- removing both capabilities when that invocation ends.

This is narrower than unconditional OSC 52 query handling inside Herdr, which would silently expose the clipboard to every pane whenever Herdr ran.

## Repository and deployed changes

- `arch/zshrc` is the canonical tracked `herdr_remote()` implementation. The same function was surgically applied to the active `/home/rgarber11/.zshrc`, whose unrelated machine-local drift remains untouched.
- `/home/rgarber11/.ssh/config` was not changed and contains no clipboard stanza.
- `shared/nvim/init.lua` sets the asymmetric headless provider with `nc 127.0.0.1 52052`, OSC 52 copy callbacks, and caching disabled.
- `headless/setup/10-packages.sh` installs Ubuntu's `netcat-openbsd` package in Coder workspaces.
- `tests/run.sh` verifies netcat installation and the exact provider contract.

The final implementation commit is `baf9081` (`fix: keep clipboard connection open for paste`), with the preceding responder and private-tunnel commits included in its history.

## Verification

Verification exercised the actual Kitty → `herdr --remote richard-worktree-2.coder` → configured remote Neovim surface:

1. **A, multiline paste:** desktop clipboard `local-A-one\nlocal-A-two` produced remote buffer `E2E_A=["local-A-one","local-A-two"]`, with no OSC 52 wait or `E353`.
2. **B, fresh repeated paste:** without restarting Neovim, changing the desktop clipboard to `local-B-fresh` produced `E2E_B=["local-B-fresh"]`; A was not cached.
3. **C, OSC 52 yank:** an exact visual `+`-register yank of `remote-exact-C` produced the same 14 bytes from desktop `wl-paste --no-newline`.
4. **Detach cleanup:** desktop and workspace loopback port `52052` both refused connections. The owned socat PGID and private SSH-master PGID no longer existed, the session process listing was empty, and no responder log, control socket, mux file, or temporary directory remained.
5. **Terminal state:** Kitty's palette and `cursor_text_color` were restored. After normalizing Kitty's additional equivalent `cursor_text #111111` alias, the restored color output had the exact baseline SHA-256.
6. **Bridge absent:** configured remote Neovim through ordinary SSH failed paste in `0.813592098` seconds with `clipboard: error: 1` and `E353: Nothing in register +`; no OSC 52 waiting message appeared.
7. **Regression suite:** the final container suite reported `all checks passed` in 54.69 seconds, including netcat installation and exact provider output `herdr-remote|function|nc 127.0.0.1 52052|0`.

After verification, the local worktree, remote clone, and `origin/coder-dotfiles` all pointed to clean commit `baf9081`.

## Sources

- Herdr remote attach documentation: <https://herdr.dev/docs/persistence-remote/>
- Herdr pull request 1414: <https://github.com/herdrdev/herdr/pull/1414>
- Neovim `:help g:clipboard` and `:help clipboard-osc52` from the installed Neovim 0.12.4 runtime.
