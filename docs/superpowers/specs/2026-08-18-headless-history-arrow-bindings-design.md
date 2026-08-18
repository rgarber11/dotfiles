# Headless history arrow bindings design

Date: 2026-08-18
Status: approved design

## Goal

Make Up and Down reliably invoke `zsh-history-substring-search` in both headless shell configurations when the terminal uses either normal or application cursor-key mode.

## Existing behavior

Both configurations already load `zsh-history-substring-search` and bind the normal CSI sequences (`Esc [ A` and `Esc [ B`). The active `richard-worktree-2` workspace was inspected: both widgets are loaded and those CSI bindings are active. A physical arrow press still does not search, which isolates the failure to the alternative SS3/application sequences (`Esc O A` and `Esc O B`).

Oh My Zsh makes the desktop behavior appear implicit because its internal key-binding library performs terminal key bindings while `.zshrc` is loaded. The headless profiles do not load Oh My Zsh and therefore own these bindings directly.

## Change

Update both configuration sources:

- `headless/zshrc` in the dotfiles repository.
- `coder/templates/dsp-base/build/zsh/dsp-base.zsh` in the talos-home repository.

Keep the existing plugin and CSI bindings. Add explicit SS3/application bindings:

- `Esc O A` to `history-substring-search-up`.
- `Esc O B` to `history-substring-search-down`.

Keep the existing `Ctrl-P` and `Ctrl-N` mappings. Do not alter Alt-Left or Alt-Right behavior, plugin ordering, prompt setup, history options, or either repository's deployment process.

## Verification

1. Parse both modified zsh files with `zsh -n`.
2. Start a PTY-backed zsh using each configuration, seed history with distinguishable commands, type a substring from the middle of one command, and inject both Up encodings independently.
3. Confirm each encoding selects the matching command, and the corresponding Down encoding traverses forward through matching history.
4. Inspect the active widget map in the Coder workspace after deployment when a rebuilt Talos image is available; source-level and local PTY checks cover this change before deployment.

## Risks

Binding both encodings is safe because they are distinct byte sequences that represent the same logical keys in different terminal modes. The mappings are installed after syntax highlighting and the history widget load, preserving the existing load-order invariant.