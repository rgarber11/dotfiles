# Claude instance integrations design

Date: 2026-08-19
Status: approved design

## Goal

Give the `gpt_code()` and `monet()` Claude Code instances the primary Claude installation's Herdr session integration while preserving their existing Herdr agent names. Give only `monet()` the primary installation's Oh My Posh status line and real Claude Max rate-limit display.

## Existing behavior

`gpt_code()` launches Claude with `CLAUDE_CONFIG_DIR="$HOME/.config/claude-other/"` and routes Anthropic requests through cli-proxy-api. Its settings already contain the primary Oh My Posh status-line command, but cli-proxy-api does not supply Claude Code's Pro/Max `rate_limits` status data. Oh My Posh consequently renders empty 5-hour and 7-day gauges that do not represent the Codex account's quota. Its settings do not contain the Herdr `SessionStart` hook.

`monet()` launches Claude with `CLAUDE_CONFIG_DIR="$HOME/.config/claude-monet/"` and authenticates a separate Claude Max account. Its settings currently contain only the theme and TUI mode. This account can supply the rate-limit data consumed by the existing Oh My Posh Claude segment.

Both zsh functions already start `_name_herdr_agent` when `HERDR_PANE_ID` is set. That helper retains the requested names (`gpt_code` or `monet`) and adds numeric suffixes on collisions. The Herdr Claude hook reports a session ID and transcript path; it does not rename the pane agent.

## Configuration changes

Update `~/.config/claude-other/settings.json`:

- Add the same wildcard `SessionStart` command hook used by `~/.claude/settings.json`.
- Reference the canonical Herdr-managed script at `/home/rgarber11/.claude/hooks/herdr-agent-state.sh`; do not copy or modify the managed script.
- Remove the existing `statusLine` block so `gpt_code()` does not display misleading quota gauges.
- Preserve all existing environment, permission, sandbox, theme, auto-mode, and TUI settings.

Update `~/.config/claude-monet/settings.json`:

- Add the same wildcard `SessionStart` command hook and canonical script reference.
- Add the existing Oh My Posh command status line: `oh-my-posh claude --config ~/.config/oh-my-posh/claude.omp.json`, with zero padding.
- Preserve the existing theme and TUI settings.

Do not modify `.zshrc`, `arch/zshrc`, the Oh My Posh theme, or the managed Herdr script. The launchers already select the intended configuration directory, inherit Herdr's environment, set terminal colors, and assign agent names.

## Runtime behavior

Under Herdr, each Claude instance executes the shared hook at `SessionStart`. The hook reports the new top-level Claude session to the current Herdr pane. `_name_herdr_agent` remains responsible for the visible `gpt_code[_N]` or `monet[_N]` name, so session reporting cannot replace the configured name.

Outside Herdr, the hook sees no Herdr environment or pane/socket identifiers and exits successfully without side effects. Both launchers continue to work in ordinary Kitty tabs.

`monet()` sends Claude Code's status JSON to Oh My Posh. The existing theme renders path, edit counts, Max five-hour and seven-day usage, reset times, model, and context capacity. `gpt_code()` uses Claude Code's normal status display and has no Oh My Posh command.

## Verification

1. Parse both settings files as JSON.
2. Invoke each configured Herdr hook with an isolated Unix socket and a synthetic top-level `SessionStart` payload. Confirm it emits `pane.report_agent_session` with the supplied pane ID, session ID, and transcript path.
3. Launch Claude through the `gpt_code()` configuration and confirm a real proxy-backed prompt succeeds without an Oh My Posh status line.
4. Launch Claude through the `monet()` configuration and confirm a real Claude prompt succeeds with the Oh My Posh status line.
5. Confirm the zsh definitions still contain `_name_herdr_agent "$HERDR_PANE_ID" gpt_code` and `_name_herdr_agent "$HERDR_PANE_ID" monet`; no launcher edit is required.

## Risks

The non-default settings reference a script under `~/.claude`. This is intentional: Herdr owns and updates that canonical file. The hook runs as a Claude hook command rather than as a Claude tool read, so `gpt_code()`'s tool permission denial for `Read(~/.claude/**)` does not prevent execution.

Monet's five-hour and seven-day fields depend on Claude Code continuing to provide rate-limit data for its OAuth account. If the service omits those fields, the existing theme may show empty gauges; no synthetic or proxy-derived quota is introduced.
