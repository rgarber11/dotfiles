# Shell functions shared by every profile. Sourced from each profile's .zshrc.

# cd to the root of the current git worktree.
cgt() {
  cd "$(git rev-parse --show-toplevel)" || return
}

# Every stream and container field ffprobe knows about, as JSON.
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

# Frequency of subcommands used with $1, e.g. `command_stats git`.
# Depends on extended_history being set in options.zsh.
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
  grep -E "$grep_command" ~/.zsh_history | awk "$awk_column" | sort | uniq -c | sort -nr
}

# Unzip into a directory named after the archive rather than the cwd.
unzip_into() {
  unzip "$1" -d "${1:t:r}"
}

to_qr() {
  if [[ -n "$1" ]]; then
    qrencode -o - "$1" | chafa -f kitty -
  elif [[ ! -t 0 ]]; then
    cat | qrencode -o - | chafa -f kitty -
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

# 30% Russian fortunes where that database exists. Ubuntu ships no fortunes-ru,
# so fall back rather than printing an error into every new shell.
#
# Don't probe with `fortune -f`: it does not enumerate subdirectory-style
# databases, so on Arch -- where fortune-mod-ru installs to /usr/share/fortune/ru/
# -- a probe never matches and the Russian branch would never fire. Just try it
# and fall back when it yields nothing.
give_fortune() {
  (( $+commands[fortune] )) || return 0
  (( $+commands[cowsay] )) || return 0
  local text=""
  (( RANDOM % 10 < 3 )) && text="$(fortune ru 2>/dev/null)"
  [[ -n "$text" ]] || text="$(fortune -a 2>/dev/null)"
  [[ -n "$text" ]] && print -r -- "$text" | cowsay
  return 0
}

# Print the greeting after the first prompt is drawn, not during .zshrc.
#
# p10k's instant prompt treats any console output produced while .zshrc is still
# being sourced as suspect -- even output on the very last line, since the
# boundary it cares about is "the real first prompt has been drawn", not "end of
# file". A one-shot precmd hook that removes itself lands the greeting just past
# that boundary. Same pattern p10k uses internally for _p9k_precmd_first.
greet_on_first_prompt() {
  autoload -Uz add-zsh-hook
  _dotfiles_greeting() {
    add-zsh-hook -d precmd _dotfiles_greeting
    give_fortune
  }
  add-zsh-hook precmd _dotfiles_greeting
}
