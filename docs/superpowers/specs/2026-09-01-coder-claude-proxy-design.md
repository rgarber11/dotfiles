# Coder Claude proxy design

Date: 2026-09-01
Status: approved design

## Goal

Bring the desktop Claude launch behavior into the Coder headless profile:

- `claude --resume <id>` selects the default, Monet, or GPT-backed session store.
- `monet` launches the template-managed `claude-monet` profile.
- `gpt_code` launches the template-managed `claude-other` profile through a local CLIProxyAPI process.
- Herdr shows different colors for Monet and GPT Code.
- CLIProxyAPI starts on each workspace boot and keeps its own Codex OAuth login in shared user storage.

This first change stays in the dotfiles repository. A later talos-home change will add CLIProxyAPI login and status operations to `coder/templates/*/ai-auth.sh` after the live path is proven.

## Existing behavior

The desktop `arch/zshrc` already defines `gpt_code`, `monet`, and a `claude` resume dispatcher. It assumes profile directories under `~/.config`, and it has a separate branch that controls a local Kitty instance.

Coder now supplies profile launchers in `/usr/local/bin`:

- `claude-monet` sets `CLAUDE_CONFIG_DIR="$HOME/.claude-monet"` and runs `claude`.
- `claude-other` sets `CLAUDE_CONFIG_DIR="$HOME/.claude-other"` and runs `claude`.

The template's `ai-auth sync` links `~/.claude`, `~/.claude-monet`, `~/.claude-other`, and `~/.codex` into the per-user `/mnt/user-state` mount. The headless zsh profile does not yet define the three launcher functions.

The Coder container has no systemd. PID 1 is `coder`, and `systemctl` is absent. A user service cannot own CLIProxyAPI.

## Repository changes

Add a headless-only CLIProxyAPI config and link it through `profiles/headless.links`. The config binds `127.0.0.1:8317`, accepts the fixed local client key `coder-local`, disables debug and usage statistics, and uses `/mnt/user-state/cli-proxy-api` as `auth-dir`. The local key is not an upstream credential. Loopback binding prevents another pod or LAN client from reaching it.

Add `headless/setup/42-cli-proxy-api.sh`. It will:

1. Resolve the latest `router-for-me/CLIProxyAPI` release when the binary is missing or `--upgrade` is active.
2. Download the Linux amd64 archive into a versioned directory under `~/.local/opt` and link `~/.local/bin/cli-proxy-api`.
3. Create the shared auth directory with mode `0700` when `/mnt/user-state` is writable, and enforce mode `0600` on the linked config.
4. Validate the recorded process before trusting or terminating its PID. Validation checks both liveness and the process command line. A reused PID must never be treated as CLIProxyAPI.
5. On `--upgrade`, stop a validated old process before starting the new binary. A normal workspace start reuses a healthy process.
6. Start CLIProxyAPI with `nohup`, write its PID and log under `~/.local/state/cli-proxy-api`, and poll the authenticated `/v1/models` endpoint for a bounded readiness window.

Download, startup, or readiness failure prints a warning and does not abort later dotfiles setup steps. An absent or unwritable `/mnt/user-state` also warns and skips proxy startup. It must not create a per-workspace OAuth copy because that would defeat the requested shared login.

The first login is explicit:

```sh
cli-proxy-api --config "$HOME/.config/cli-proxy-api/config.yaml" --codex-device-login --no-browser
```

CLIProxyAPI writes its provider credential into `/mnt/user-state/cli-proxy-api`. It watches that directory while running, so the service does not need a restart after login. Setup never reads, copies, or rewrites native `~/.codex/auth.json`. The two programs use different credential schemas and independent refresh-token state.

## Zsh behavior

Add the Herdr metadata helper and the three functions to `headless/zshrc`. Do not add the desktop Kitty remote-control branch.

### `gpt_code`

Under Herdr, report `gpt_code` as the display agent and launch through a small shell command that writes these OSC colors before `exec`:

- foreground `#ebdbb2`
- background `#282828`

Those values come from the Gruvbox Dark kitty theme.

The command is `/usr/local/bin/claude-other --model gpt-5.6-sol`. Preserve the desktop proxy environment:

- `ANTHROPIC_BASE_URL=http://127.0.0.1:8317`
- `ANTHROPIC_AUTH_TOKEN=coder-local`
- `ENABLE_CLAUDEAI_MCP_SERVERS=false`
- `DISABLE_TELEMETRY=1`
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`
- Opus, Sonnet, and Haiku model mappings for `gpt-5.6-sol`, `gpt-5.6-terra`, and `gpt-5.6-luna`

Outside Herdr, use the same launcher and environment without emitting theme OSC sequences or invoking Kitty.

### `monet`

`monet` remains a thin wrapper around `/usr/local/bin/claude-monet`. It does not set `CLAUDE_CONFIG_DIR` itself. This keeps the Coder template's generated profile wrapper as the source of truth.

Under Herdr, report `monet` as the display agent and apply the JetBrains Darcula kitty theme foreground `#adadad` and background `#202020`. Outside Herdr, run `claude-monet` directly with no terminal-specific handling.

Both wrappers forward every user argument unchanged and return the launched command's status.

### Resume dispatch

The `claude` function handles only `--resume <session-id>` calls that do not already set `CLAUDE_CONFIG_DIR` and whose session argument is an ID rather than a path. It searches:

- `~/.claude-other/projects/*/<session-id>.jsonl`
- `~/.claude-monet/projects/*/<session-id>.jsonl`

A GPT-only match calls `gpt_code`. A Monet-only match calls `monet`. A match in both stores fails with a clear collision message. No match falls through to `command claude`, which owns the default `~/.claude` store. Calls other than the supported resume form also fall through unchanged.

The dispatcher works in Herdr and ordinary Coder terminals. Only metadata and colors depend on `HERDR_PANE_ID`.

## Failure behavior

The zsh wrappers do not start a second proxy. Workspace setup owns process startup. If the proxy is unavailable, `gpt_code` receives the real connection failure from Claude Code rather than hiding it with a fallback provider.

A stale PID file is recoverable. A PID that belongs to another executable is left untouched and replaced only after its stale metadata is removed. Upgrade waits a bounded time after `TERM` and uses `KILL` only for a process that still passes CLIProxyAPI identity validation.

The daemon log must not contain shell tracing or credential file contents. The tracked config contains no vendor token. Shared auth files retain the permissions written by CLIProxyAPI inside a mode `0700` directory.

## Verification

Extend the existing container test to cover the permanent behavior:

1. Install CLIProxyAPI into `~/.local`, confirm the config link, and confirm the daemon answers the loopback models endpoint.
2. Run setup again and prove it reuses one process.
3. Seed stale and foreign PID cases. Prove stale metadata recovers and a foreign process is never signaled.
4. Exercise the upgrade path with a controlled replacement binary and prove the validated daemon restarts.
5. Source `headless/zshrc` with fake `claude`, `claude-monet`, and `claude-other` commands. Assert exact argument forwarding and GPT proxy environment.
6. Create isolated session stores and cover GPT dispatch, Monet dispatch, default fallthrough, path fallthrough, explicit `CLAUDE_CONFIG_DIR`, and duplicate-store failure.
7. Set `HERDR_PANE_ID` with a fake `herdr` command and assert the display labels plus exact Gruvbox Dark and JetBrains Darcula foreground/background OSC sequences.
8. Confirm a non-Herdr shell never invokes Kitty and still launches both profiles.

After the automated checks pass, run the real headless installer in the Coder workspace, complete one CLIProxyAPI device login, call the authenticated models endpoint, and launch one real `gpt_code` prompt. Launch `monet` and resume one session from each alternate store to verify the actual Herdr path.

## Known risk

`~/PhoeniciaLabs/talos-home/docs/ai-credentials.md` currently rejects proxy projects because they expose subscription OAuth through an API and may violate provider terms. Binding this instance to loopback and using only the owner's account limits who can call it, but it does not remove that policy risk. This design proceeds with that risk explicitly accepted.

Each running workspace has its own proxy process but shares the same per-user CLIProxyAPI credential directory. Concurrent token refresh can collide, just as the existing shared native Codex login can. A fresh device login repairs the credential. Solving cross-workspace single-writer refresh requires template-level coordination and is outside this dotfiles-first change.
