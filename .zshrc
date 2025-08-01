#!/bin/zsh
if (( RANDOM % 10 < 3 )); then fortune ru | cowsay; else fortune -a | cowsay; fi
# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="/home/rgarber11/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="powerlevel10k/powerlevel10k"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git archlinux colorize common-aliases zsh-interactive-cd)

source $ZSH/oh-my-zsh.sh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8
export LM_LICENSE_FILE=/home/rgarber11/.config/questa/LR-067885_License.dat

# Preferred editor for local and remote sessions
 if [[ -n $SSH_CONNECTION ]]; then
   export EDITOR='vim'
 else
   export EDITOR='nvim'
 fi
ZSH_COLORIZE_STYLE="colorful"
# Compilation flags
export ARCHFLAGS="-arch x86_64"
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=23'
# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
[[ "$(cat /proc/$PPID/comm)" =~ "kitty" ]] && alias ssh="kitten ssh"
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

export QSYS_ROOTDIR="/home/rgarber11/.cache/yay/quartus-free/pkg/quartus-free-quartus/opt/intelFPGA/24.1/quartus/sopc_builder/bin"
zshcache_time="$(date +%s%N)"

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
function format_python_comment() {
echo "$1" | fmt -78 | sed "s/.*/# \0/"
}
sdiff() {
  diff --color=always -- "$1" "$2" | less -R
}
add-zsh-hook -Uz precmd rehash_precmd
set -o extendedglob
export VCPKG_ROOT=/home/rgarber11/.local/bin/vcpkg
PATH="${VCPKG_ROOT}:/home/rgarber11/.config/emacs/bin:/home/rgarber11/perl5/bin${PATH:+:${PATH}}:$HOME/go/bin"; export PATH;
PERL5LIB="/home/rgarber11/perl5/lib/perl5${PERL5LIB:+:${PERL5LIB}}"; export PERL5LIB;
PERL_LOCAL_LIB_ROOT="/home/rgarber11/perl5${PERL_LOCAL_LIB_ROOT:+:${PERL_LOCAL_LIB_ROOT}}"; export PERL_LOCAL_LIB_ROOT;
PERL_MB_OPT="--install_base \"/home/rgarber11/perl5\""; export PERL_MB_OPT;
PERL_MM_OPT="INSTALL_BASE=/home/rgarber11/perl5"; export PERL_MM_OPT;
alias give_fortune="if (( RANDOM % 10 < 3 )); then fortune ru | cowsay; else fortune -a | cowsay; fi"
alias new_mirrorlist="reflector -n 50 -c US --delay 0.25 -f 20 --sort rate > mirrorlist.new"

ffmpeg_all_info() {
  ffprobe -v quiet -of json -show_entries stream:format -show_chapters file:"$1"
}
VCPKG_DOWNLOADS=/home/rgarber11/.cache/vcpkg
export GHCUP_USE_XDG_DIRS=1
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
# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/home/rgarber11/miniforge3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/home/rgarber11/miniforge3/etc/profile.d/conda.sh" ]; then
        . "/home/rgarber11/miniforge3/etc/profile.d/conda.sh"
    else
        export PATH="/home/rgarber11/miniforge3/bin:$PATH"
    fi
fi
unset __conda_setup

if [ -f "/home/rgarber11/miniforge3/etc/profile.d/mamba.sh" ]; then
    . "/home/rgarber11/miniforge3/etc/profile.d/mamba.sh"
fi
export ANDROID_HOME="/home/rgarber11/Android/Sdk"
# <<< conda initialize <<<
