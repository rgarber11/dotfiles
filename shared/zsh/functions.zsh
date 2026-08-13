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
give_fortune() {
  (( $+commands[fortune] )) || return 0
  (( $+commands[cowsay] )) || return 0
  if (( RANDOM % 10 < 3 )) && fortune -f 2>&1 | grep -qw ru; then
    fortune ru | cowsay
  else
    fortune -a | cowsay
  fi
}
