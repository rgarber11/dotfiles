# Claude Launcher Argument Forwarding Design

## Goal

Make `monet` and `gpt_code` forward all caller-supplied arguments to Claude Code without changing their existing environment, terminal colors, Herdr labels, cleanup behavior, or fixed model selection.

The intended call must work as written:

```zsh
monet "/spec-base-attach sessionId=sb-ahjt3h"
```

The quoted text remains one argument. Multiple positional arguments and flags must also retain their original boundaries.

## Existing behavior

Both functions build a `launch_command` zsh array. The Herdr branch wraps Claude in `sh -c` to set terminal colors before `exec "$@"`; the ordinary Kitty branch invokes Claude directly. Neither branch currently appends the wrapper function's positional arguments, so Claude starts without them.

`gpt_code` also supplies the fixed option `--model gpt-5.6-sol`. Caller arguments must follow that option. `monet` has no fixed Claude arguments.

The active definitions are in `~/.zshrc`; the tracked source of truth is `~/dotfiles/arch/zshrc`.

## Design

Append the wrapper's `"$@"` expansion while constructing `launch_command` in every branch:

- Herdr `gpt_code`: wrapper command, `claude`, fixed model option, then caller arguments.
- Kitty `gpt_code`: `claude`, fixed model option, then caller arguments.
- Herdr `monet`: wrapper command, `claude`, then caller arguments.
- Kitty `monet`: `claude`, then caller arguments.

Because zsh expands `"$@"` as one array element per original argument, quoted prompts, spaces, empty arguments, and multiple flags are preserved. The existing `sh -c` wrapper already forwards its post-sentinel arguments through `exec "$@"`, so no shell-string interpolation or `eval` is needed.

Apply the same launcher changes to both files. Do not refactor the surrounding functions or modify unrelated uncommitted work.

## Error handling

Argument validation remains Claude Code's responsibility. The wrappers must not reinterpret, join, discard, or validate caller arguments. Claude's exit status continues to flow through the existing function body, and the `always` block continues restoring Kitty state.

## Verification

1. Parse both files with `zsh -n`.
2. Source each file in an isolated zsh process with stubbed `claude`, `kitty`, and Herdr conditions.
3. Invoke both launchers outside Herdr with a quoted slash command and multiple arguments; assert exact argument order and boundaries.
4. Invoke both launchers under a Herdr pane; assert the `sh -c` path reaches the stubbed Claude command with the same argument order and boundaries.
5. Confirm `gpt_code` keeps `--model gpt-5.6-sol` before caller arguments and `monet` adds no fixed argument.
