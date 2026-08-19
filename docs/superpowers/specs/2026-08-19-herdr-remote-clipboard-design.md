# Herdr remote Neovim clipboard bridge design

Date: 2026-08-19
Status: approved design, awaiting written-spec review

## Goal

Make `"+p` in Neovim running inside `herdr --remote richard-worktree-2.coder` paste the Arch desktop's current Wayland clipboard without relying on OSC 52 clipboard queries.

Preserve the working path in the opposite direction: remote Neovim yanks continue to update the desktop clipboard through Neovim's bundled OSC 52 copy provider and Herdr's existing OSC 52 write forwarding.

## Current behavior

The Coder workspace has no X11 or Wayland display. Neovim 0.12.4 therefore falls back to its bundled OSC 52 clipboard provider. OSC 52 writes traverse Herdr, so `"+y` works. OSC 52 reads do not traverse Herdr correctly, so `"+p` emits a query, waits for a response, and eventually times out.

Herdr pull request 1414 did not provide a usable query path. It wrote responses to the outer terminal rather than the originating child PTY, emitted an invalid response form, discarded the originating pane in remote mode, lacked a client-to-server response route, and changed the wire protocol without a version bump. Its proposed unconditional clipboard reads also gave every process in every pane access to the host clipboard without an explicit policy.

## Scope

Included:

- Text clipboard reads from the Arch desktop into headless Neovim's `+` and `*` registers.
- Session-scoped activation tied to `herdr_remote()`.
- Loopback-only transport through the authenticated SSH connection used by Herdr.
- Existing OSC 52 clipboard writes from remote Neovim to the desktop.
- Fast failure when the local bridge is unavailable.
- Installation of the remote `nc` command required by Neovim's custom provider.

Excluded:

- Images or arbitrary binary clipboard formats.
- General Herdr OSC 52 query support.
- Clipboard access for other remote hosts.
- A persistent desktop clipboard daemon.
- Clipboard history, synchronization, retries, or caching.
- Changes to Herdr itself.

## Architecture

The bridge has three small parts.

### Local clipboard responder

The desktop `herdr_remote()` function starts a background responder before launching Herdr. The responder binds OpenBSD netcat to TCP port `52052` on `127.0.0.1` only. For each accepted connection, it runs `wl-paste --no-newline`, sends the resulting bytes, closes the connection, and returns to listening for the next request.

The responder exists only for the lifetime of that `herdr_remote()` invocation. The function's `always` cleanup terminates the responder even when Herdr exits with an error or the user interrupts it. The existing Kitty color restoration remains in the same cleanup path.

The responder must close the socket after clipboard input reaches EOF. OpenBSD netcat's `-N` option supplies that behavior so Neovim does not wait indefinitely for the provider process.

### SSH reverse forward

An exact-host stanza for `richard-worktree-2.coder` is added outside the Coder-managed section of `~/.ssh/config`. It forwards workspace endpoint `127.0.0.1:52052` to desktop endpoint `127.0.0.1:52052` and enables `ExitOnForwardFailure`.

Herdr 0.8.0 remote attach includes the user's SSH config before adding its own keepalive and control-socket defaults. The `RemoteForward` therefore belongs to Herdr's authenticated, per-attach SSH connection without a second tunnel process.

Both endpoints use explicit `127.0.0.1` bind addresses. No listener is exposed to the desktop LAN, the Coder pod network, or the public internet.

### Headless Neovim provider

The shared Neovim configuration installs a custom `vim.g.clipboard` provider before any clipboard-provider initialization, but only when the existing `headless` detection is true.

The provider is intentionally asymmetric:

- `copy["+"]` and `copy["*"]` use `require('vim.ui.clipboard.osc52').copy(...)`.
- `paste["+"]` and `paste["*"]` run remote `nc -N 127.0.0.1 52052`.
- Caching is disabled because the source of truth is the current desktop clipboard, not the last remote yank.

Desktop Neovim keeps normal automatic clipboard-tool detection and remains unchanged.

There is no OSC 52 read fallback. When no local responder or SSH forward exists, the TCP connection fails promptly and Neovim receives no clipboard text instead of entering OSC 52's ten-second wait path.

## Data flow

### Paste: desktop to remote Neovim

1. The user invokes `"+p` in Neovim inside a remote Herdr pane.
2. Neovim starts `nc` against the configured workspace loopback port.
3. OpenSSH carries that TCP connection through the reverse forward to the desktop loopback listener.
4. The local responder reads the current Wayland clipboard with `wl-paste --no-newline`.
5. Netcat streams the text back through SSH and closes the socket.
6. Neovim receives stdout from the provider command and applies normal `+`-register paste semantics.

### Yank: remote Neovim to desktop

1. The user invokes `"+y` in remote Neovim.
2. Neovim's OSC 52 copy callback sends the encoded selection to the TUI.
3. Herdr forwards the OSC 52 write to the local terminal.
4. Kitty writes the decoded text to the Wayland clipboard.

The netcat bridge is not involved in this direction.

## Error handling and lifecycle

- After starting the responder, `herdr_remote()` verifies that it remained alive long enough to bind. If desktop port `52052` is already occupied or netcat exits, the function reports the failure and does not launch Herdr.
- If OpenSSH cannot establish the reverse forward, `ExitOnForwardFailure` prevents a misleading successful attach.
- If `wl-paste` fails or the clipboard has no text representation, that request returns no text; the responder remains available for later requests.
- If the SSH connection drops, its reverse forward disappears automatically. Herdr's normal reconnect or next attach recreates it.
- If Herdr exits or is interrupted, the Zsh `always` block terminates and reaps the responder before returning to the prompt.
- Clipboard text is transferred verbatim. No shell interpolation, command construction from clipboard contents, or temporary file is used.

## Security boundary

This is an explicit clipboard-read opt-in, not a claim that clipboard reads are harmless.

While `herdr_remote()` is attached, any process running as the Coder user can connect to the forwarded workspace loopback port and read the desktop's current text clipboard. Trusting the machine means accepting that its processes and dependencies receive this capability during the attach. The design narrows exposure by:

- enabling it only for the exact `richard-worktree-2.coder` SSH host;
- binding both sides to loopback;
- carrying traffic only through authenticated SSH;
- starting the desktop responder only for an interactive `herdr_remote()` invocation; and
- removing the capability when that invocation ends.

This is narrower than unconditional OSC 52 query handling inside Herdr, which would silently expose the clipboard to every pane whenever Herdr ran.

## Repository changes

- Desktop `~/.zshrc`: update the existing machine-local `herdr_remote()` function to own the responder lifecycle alongside Kitty color changes.
- Desktop `~/.ssh/config`: add the exact-host reverse-forward stanza after the Coder-managed block.
- `shared/nvim/init.lua`: set the asymmetric custom clipboard provider under the existing `headless` condition and before clipboard-provider initialization.
- `headless/setup/10-packages.sh`: add Ubuntu's `netcat-openbsd` package.

The active desktop `~/.zshrc` and `~/.ssh/config` are not currently managed by the repository, so their changes are applied directly and documented by the implementation plan. The Coder-side Neovim and package changes remain canonical in `~/dotfiles`.

## Verification

Verification uses the actual Herdr remote surface, not only headless configuration checks.

1. Run the updated `herdr_remote()` and confirm the local responder and SSH reverse forward start.
2. Copy a unique multi-line text value on the Arch desktop.
3. In remote Neovim, execute `"+p` and confirm the buffer receives the exact value.
4. Copy a different value with `"+y` in remote Neovim and confirm `wl-paste --no-newline` on the desktop returns it.
5. Detach or exit Herdr and confirm the local listener no longer accepts connections.
6. Start remote Neovim without the bridge and confirm `"+p` fails promptly without the OSC 52 waiting message or ten-second timeout.
7. Reattach through `herdr_remote()` and confirm repeated paste requests return the clipboard value current at each request, not a cached earlier value.

## Sources

- Herdr remote attach documentation: <https://herdr.dev/docs/persistence-remote/>
- Herdr pull request 1414: <https://github.com/herdrdev/herdr/pull/1414>
- Neovim `:help g:clipboard` and `:help clipboard-osc52` from the installed Neovim 0.12.4 runtime.
