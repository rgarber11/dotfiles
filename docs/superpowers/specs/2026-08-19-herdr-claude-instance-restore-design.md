# Herdr Claude instance restore design

Date: 2026-08-19
Status: approved design

## Goal

Make Herdr session restore resume `gpt_code` and `monet` Claude sessions through the same configuration, account, backend, model environment, terminal colors, and display label as their original launch. Preserve ordinary primary-Claude behavior and the existing launchers.

## Existing behavior and root cause

`gpt_code()` launches Claude with `CLAUDE_CONFIG_DIR="$HOME/.config/claude-other/"` and a proxy-specific environment. `monet()` launches Claude with `CLAUDE_CONFIG_DIR="$HOME/.config/claude-monet/"`. Their session transcripts therefore live under each selected user configuration root's `projects` directory.

Herdr 0.8.0 persists the official Claude session ID but constructs every native Claude restore as:

```text
claude --resume <session-id>
```

The restore plan does not persist or reapply `CLAUDE_CONFIG_DIR`, launcher environment variables, or display-only pane metadata. The command runs in a newly restored interactive shell, so Claude defaults to `~/.claude` and cannot find sessions stored in either alternate root. A GPT restore would also use the wrong backend and model environment even if transcript lookup alone were repaired.

Herdr's documented support for `CLAUDE_CONFIG_DIR` applies when installing its Claude integration. It does not alter the hard-coded native restore command.

## Claude configuration and session locations

Claude uses two distinct configuration scopes:

- The active user configuration root (`~/.claude` by default, or `CLAUDE_CONFIG_DIR`) owns session transcripts under `projects/<encoded-cwd>/<session-id>.jsonl`, credentials, and user-level settings.
- A repository's `.claude` directory owns project settings, local settings, agents, commands, and skills loaded from the process working directory.

The current `dsp-base/.claude` directory contains project configuration and no session transcripts. Sessions for that repository are present under all three user roots according to the instance that created them:

- Primary Claude: `~/.claude/projects/...`
- GPT Code: `~/.config/claude-other/projects/...`
- Monet: `~/.config/claude-monet/projects/...`

Herdr already restores the pane working directory. Once the correct user configuration root is selected, Claude continues to load the repository-local `.claude` directory normally.

A project-local `.claude` directory would become a session root only if a launcher explicitly set `CLAUDE_CONFIG_DIR` to that directory. None of the current launchers do so. Any future instance with another user root must add that root and its complete launch context to the dispatcher explicitly.

## Selected approach

Add a narrow Zsh `claude()` restore dispatcher to both launcher sources:

- `/home/rgarber11/dotfiles/arch/zshrc`
- `/home/rgarber11/.zshrc`

The function intercepts only a command satisfying all of these conditions:

1. `HERDR_PANE_ID` is set.
2. `CLAUDE_CONFIG_DIR` is not already set.
3. The arguments contain Herdr's native two-argument restore form, `--resume <session-id>`.

Every other invocation executes the real Claude binary unchanged. The existing launcher behavior remains unchanged because each launcher's `env` command resolves the executable directly and already supplies `CLAUDE_CONFIG_DIR`; `gpt_code()` is updated only to consume the shared GPT environment definition.

## Restore dispatch

For an intercepted restore, inspect the known alternate user roots for an exact transcript filename:

```text
<root>/projects/*/<session-id>.jsonl
```

Treat the session ID as pathname data, not a glob or shell command.

- A match under `~/.config/claude-other` selects GPT Code.
- A match under `~/.config/claude-monet` selects Monet.
- No alternate match delegates unchanged to the real Claude binary, preserving primary Claude restore through `~/.claude` and Claude's normal error handling for unknown IDs.
- Matches under more than one alternate root fail with a clear ambiguity error rather than selecting the wrong account or backend.

The lookup is limited to intercepted Herdr restores. Normal Claude startup pays no directory-scan cost.

## Recovered launch contexts

### GPT Code

Before executing the real Claude binary, the dispatcher:

1. Reapplies the `gpt_code` display metadata through the existing asynchronous `_label_herdr_agent` helper.
2. Emits the same foreground and background terminal escape sequences as the existing Herdr launcher path.
3. Executes Claude with the same environment used by `gpt_code()`:
   - `CLAUDE_CONFIG_DIR="$HOME/.config/claude-other/"`
   - `ANTHROPIC_BASE_URL="http://127.0.0.1:8317"`
   - `ENABLE_CLAUDEAI_MCP_SERVERS=false`
   - `DISABLE_TELEMETRY=1`
   - `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`
   - the caller's current `ANTHROPIC_AUTH_TOKEN`
   - the existing GPT Opus, Sonnet, and Haiku model mappings
4. Prepends the launcher's fixed `--model gpt-5.6-sol` option, then forwards Herdr's original `--resume` argument and session ID exactly.

The GPT environment definition is shared between the ordinary launcher and restore dispatcher so the two paths cannot drift.

### Monet

Before executing the real Claude binary, the dispatcher:

1. Reapplies the `monet` display metadata through `_label_herdr_agent`.
2. Emits the same Monet terminal colors as the existing Herdr launcher path.
3. Sets `CLAUDE_CONFIG_DIR="$HOME/.config/claude-monet/"`.
4. Preserves Herdr's original arguments exactly.

Monet's model, status line, plugins, theme, and account data continue to come from that configuration root.

## Error handling and boundaries

- Do not search arbitrary repository `.claude` directories. They are project configuration, not registered user session roots.
- Do not infer an instance from the current directory; all three instances can have sessions for the same repository.
- Do not select an alternate instance from the display label. Herdr does not persist display-only metadata in its session snapshot.
- Do not mutate or copy transcript files.
- Do not modify Herdr, its canonical hook, Claude settings files, or the Oh My Posh configuration.
- If the alternate-root lookup is ambiguous, return nonzero and leave the restored pane at its shell with an actionable error.
- If the ID is absent from alternate roots, delegate to primary Claude unchanged.

## Verification

Use an isolated Zsh behavioral harness with stubbed `claude`, `herdr`, and controlled transcript trees.

1. Capture Herdr's current failing contract: bare `claude --resume <id>` does not select either alternate configuration.
2. Verify a GPT transcript selects the GPT user root, proxy/auth/model environment, fixed model option, GPT colors, and `gpt_code` metadata label while preserving Herdr's argument boundaries.
3. Verify a Monet transcript selects the Monet user root, Monet colors, and `monet` metadata label while preserving arguments.
4. Verify a primary or unknown session delegates without adding alternate-instance environment.
5. Verify an ambiguous ID returns nonzero and does not execute Claude.
6. Verify ordinary non-Herdr calls, non-resume calls, and calls with an existing `CLAUDE_CONFIG_DIR` remain unchanged.
7. Run `zsh -n` against both Zsh files.
8. Exercise the dispatcher with a real existing alternate-root session ID and a stub executable so filesystem discovery is verified without issuing a model request or disrupting the active Herdr server.
9. Run the repository's focused shell tests, then its full existing test suite if the focused checks pass.

## Risks

A future launcher can drift if it adds environment outside the shared GPT context or introduces another Claude root without registering it. Keeping instance roots and their complete execution context together makes such additions explicit. The dispatcher intentionally depends on Claude's current `projects/<encoded-cwd>/<id>.jsonl` storage contract; the behavioral tests will detect a storage-layout change.