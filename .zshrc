#!/bin/zsh
if (( RANDOM % 10 < 3 )); then fortune ru | cowsay; else fortune -a | cowsay; fi
# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git archlinux colorize common-aliases zsh-interactive-cd)

export ZSH="$HOME/.oh-my-zsh"
source $ZSH/oh-my-zsh.sh

source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme
setopt autocd extendedglob

unsetopt beep nomatch notify

bindkey -e
# Match standard xterm Alt+arrow sequences to Emacs word motion.
bindkey -M emacs '\e[1;3C' forward-word
bindkey -M emacs '\e[1;3D' backward-word
#
# Path to your Oh My Zsh installation.
fpath=(~/.local/share/zsh/site-functions $fpath)
zstyle :compinstall filename '/home/rgarber11/.zshrc'
# completions
autoload -Uz compinit
compinit
autoload -Uz add-zsh-hook
rehash_precmd() {
  if [[ -a /var/cache/zsh/pacman ]]; then
    local paccache_time="$(date -r /var/cache/zsh/pacman +%s%N)"
    if (( zshcache_time < paccache_time )); then
      rehash
      zshcache_time="$paccache_time"
    fi
  fi
}
add-zsh-hook -Uz precmd rehash_precmd
# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='nvim'
# fi

ZSH_COLORIZE_STYLE="colorful"
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=23'
[[ "$(cat /proc/$PPID/comm)" =~ "kitty" ]] && alias ssh="kitten ssh"
export EDITOR=nvim
export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH:$HOME/Android/Sdk/platform-tools:$HOME/Android/Sdk/emulator
export ANDROID_HOME="$HOME/Android/Sdk"

[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
give_fortune() {
  if (( RANDOM % 10 < 3 )); then
    fortune ru | cowsay
  else
    fortune -a | cowsay
  fi
}
alias new_mirrorlist="reflector -n 50 -c US --delay 0.25 -f 20 --sort rate > mirrorlist.new"
cgt() {
  cd "$(git rev-parse --show-toplevel)" || return
}
monitor_app() {
adb logcat --pid=$(adb shell pidof com.voiceerp.voiceerp)
}

ffmpeg_all_info() {
  ffprobe -v quiet -of json -show_entries stream:format -show_chapters file:"$1"
}
delete_node_modules() {
  echo -n "Are you sure you want to delete all node_modules directories (CHECK THE DIRECTORY YOU'RE IN!!!)? (y/n): "
  read REPLY
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    return 1
  fi
  find . -name "node_modules" -type d -prune -exec rm -rf '{}' \;
}
gpt_code() {
  local original_kitty_colors
  original_kitty_colors=$(kitty @ get-colors) || return
  {
    kitty @ set-colors  "~/.config/kitty/kitty-themes/Catppuccin-Mocha.conf"
    kitty @ set-tab-title "GPT Code"
     env \
      CLAUDE_CONFIG_DIR="$HOME/.config/claude-other/" \
      ANTHROPIC_BASE_URL="http://127.0.0.1:8317" \
      ENABLE_CLAUDEAI_MCP_SERVERS=false \
      DISABLE_TELEMETRY=1 \
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
      ANTHROPIC_AUTH_TOKEN="rKPV+ZYXtt893+JCEHrFGIhd1UO9/zJyvPR4LOxQCcOS9xQ3jGjqP/M5S50j1MGDMdqmGAnAammJfy+3EwqxIg==" \
      ANTHROPIC_DEFAULT_OPUS_MODEL="gpt-5.6-sol" \
      ANTHROPIC_DEFAULT_SONNET_MODEL="gpt-5.6-terra" \
      ANTHROPIC_DEFAULT_HAIKU_MODEL="gpt-5.6-luna" \
      claude --model gpt-5.6-sol
  } always {
    kitty @ set-colors <(print -r -- "$original_kitty_colors")
    kitty @ set-tab-title ""
  }
}
herdr_remote() {
  local original_kitty_colors
  original_kitty_colors=$(kitty @ get-colors) || return 
  {
    kitty @ set-colors "~/.config/kitty/kitty-themes/Catppuccin-Mocha.conf"
    herdr --remote richard-worktree-2.coder
  } always {
    kitty @ set-colors <(print -r -- "$original_kitty_colors")
  }
}
command_stats() {
local uname_output=$(uname -s)
local awk_column=""
local grep_command=""
case "${uname_output}" in
Linux*)
  awk_column="{ print \"$1 \"\$3 }"
  grep_command="[[:digit:]];$1[ \n]"
  ;;
Darwin*)
  awk_column="{ print \"$1 \"\$2 }"
  grep_command="^$1[ \n]"
  ;;
*)
  echo "Unsupported OS: ${uname_output}"
  return 1
  ;;
esac
  grep -E "$grep_command" ~/.zsh_history | awk "$awk_column"  | sort | uniq -c | sort -nr 
}
unzip_into() {
  unzip "$1" -d "${1:t:r}"
}
to_qr() {
  if [[ -n "$1" ]]; then
    qrencode -o - "$1" | chafa -f kitty -
  elif [[ ! -t 0 ]]; then
    cat | qrencode -o -  | chafa -f kitty -
  else
    echo "Usage: to_qr <string> (or pipe input to it)"
    return 1
  fi
}
refresh_git_branch() {
  declare -a commits
  commits=$(git rev-list HEAD)
  local branches_that_head_has=$(git branch --contains HEAD)
  for commit in $commits; do
    branches=$(git branch --contains $commit)
    echo "$branches"
    for branch in $branches; do
      if [[ $branches_that_head_has == *"$branch"* ]]; then
        continue
      fi
      echo "$branch"
      break 2
    done
done
    
}
export NODE_OPTIONS="--max_old_space_size=8196 --stack-trace-limit=1000"
. /usr/share/nvm/init-nvm.sh
 ENABLE_CORRECTION="true"
 setopt nocorrectall; setopt correct;
 CORRECT_IGNORE=".sst|.expo"
 CORRECT_IGNORE_FILE=".ssh|.expo"
