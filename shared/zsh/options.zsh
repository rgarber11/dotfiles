# Shell options shared by every profile. Sourced from each profile's .zshrc.

setopt autocd extendedglob
unsetopt beep nomatch notify

bindkey -e
# Standard xterm Alt+arrow sequences -> Emacs word motion.
bindkey -M emacs '\e[1;3C' forward-word
bindkey -M emacs '\e[1;3D' backward-word

# History. oh-my-zsh used to supply all of this; without it zsh saves nothing
# at all. extended_history is load-bearing beyond taste: command_stats() parses
# the `: <epoch>:<elapsed>;<command>` form out of ~/.zsh_history and returns
# nothing without it.
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt extended_history inc_append_history share_history
setopt hist_ignore_dups hist_ignore_space hist_verify

# Spelling correction, minus the parts that fight tooling directories.
ENABLE_CORRECTION="true"
setopt nocorrectall
setopt correct
CORRECT_IGNORE=".sst|.expo"
CORRECT_IGNORE_FILE=".ssh|.expo"
