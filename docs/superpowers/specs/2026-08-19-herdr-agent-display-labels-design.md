# Herdr agent display labels design

Date: 2026-08-19
Status: approved design

## Goal

Make every Herdr pane launched by `gpt_code()` display `gpt_code` and every pane launched by `monet()` display `monet`, with no numeric suffixes, while preserving Claude session detection and Herdr lifecycle reporting.

## Existing behavior

The zsh helper `_name_herdr_agent` assigns custom Herdr agent names. Herdr 0.8.0 requires custom names to be globally unique and returns `agent_name_taken` on a duplicate. The helper therefore tries the base label first, then suffixes `_2` through `_32`.

The repeated `omp` labels in Herdr are not custom names. Those panes have `name: null` and share the detected/displayed agent label `omp`, which is allowed to repeat. Herdr's `pane.report_metadata` API supports the same display-only override for user integrations without taking over lifecycle or session authority.

## Change

Replace `_name_herdr_agent` with `_label_herdr_agent` in both launcher sources:

- `/home/rgarber11/.zshrc`
- `/home/rgarber11/dotfiles/arch/zshrc`

The helper accepts a pane ID and display label, retries until `herdr agent get` confirms the pane hosts an agent, then reports display-only metadata with:

- A stable user-owned metadata source.
- Agent scope `claude`.
- No `applies-to-source` guard. The canonical hook reports Claude session identity but does not own lifecycle hook authority, so guarding against `herdr:claude` is accepted by the API but hides the metadata. Agent scope `claude` ties metadata cleanup to the detected Claude process.
- `display-agent` set to `gpt_code` or `monet`.

Update `gpt_code()` and `monet()` to call the display-label helper in the same asynchronous launch position as the current rename helper. Delete the suffix loop and all custom-name assignment behavior.

Do not modify either Claude settings file, the canonical Herdr hook, the Oh My Posh theme, terminal colors, Claude environment variables, or launch commands.

## Existing pane migration

After source verification, migrate currently active custom-named GPT/Monet panes:

1. Enumerate agents whose custom name is exactly `gpt_code`, `monet`, or one of their numeric suffixes.
2. Clear each matching custom name with `herdr agent rename <pane-id> --clear`.
3. Apply the corresponding display-only metadata label through `herdr pane report-metadata`.
4. Do not alter unrelated agents or panes.

This migration is runtime state only. Future launches use the updated helper.

## Behavior and tradeoff

Concurrent panes may share the visible label `gpt_code` or `monet`, matching OMP's repeated `omp` display. Their pane IDs remain unique. A label alone is no longer a unique CLI target when multiple matching panes exist; callers must use a pane ID or another unique target.

Metadata is presentation-only and agent-scoped to `claude`, so it follows the detected Claude process without replacing the canonical hook's session association, lifecycle state, or agent identity. The `herdr:claude` session source remains unchanged.

## Verification

1. Parse both zsh files with `zsh -n`.
2. Assert both files contain `_label_herdr_agent`, no `_name_herdr_agent`, no suffix loop, and the intended `gpt_code`/`monet` calls.
3. Use an isolated temporary Herdr server or controlled active pane to prove the metadata command sets `display_agent` while leaving the custom `name` null and the underlying agent identity Claude.
4. Launch or migrate at least two concurrent GPT panes and confirm both visibly display `gpt_code` with distinct pane IDs and no numeric suffix.
5. Confirm Herdr session reporting remains associated with the canonical `herdr:claude` source.
6. Run the dotfiles test suite after focused runtime verification.

## Risks

The display label is intentionally non-unique. Commands that previously targeted `gpt_code_2` by custom name must instead target its pane ID. If metadata reporting fails, the pane remains a normally detected `claude` agent rather than losing lifecycle detection; the helper runs asynchronously and does not block Claude startup.
