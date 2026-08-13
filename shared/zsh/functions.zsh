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

# Does this terminal implement the kitty graphics protocol? Asks it directly,
# the way kitty documents, rather than guessing from $TERM -- multiplexers and
# ssh make $TERM an unreliable proxy for what the far end can actually draw.
#
# The graphics query is paired with a Primary DA request: terminals that don't
# implement graphics simply never answer the first, but every terminal answers
# DA, so the read terminates on the DA reply instead of hanging for a timeout.
# Cached per shell -- the answer cannot change mid-session.
typeset -g _to_qr_kitty_graphics_support=""
_supports_kitty_graphics() {
  if [[ -n "$_to_qr_kitty_graphics_support" ]]; then
    [[ "$_to_qr_kitty_graphics_support" == 1 ]]
    return
  fi

  # Querying is meaningless if we're not actually attached to a terminal
  # (piped/redirected output) -- default to "unsupported" without touching
  # the tty at all.
  if [[ ! -t 1 ]]; then
    return 1
  fi

  local old_stty
  old_stty=$(stty -g 2>/dev/null) || return 1

  # Open the tty once and read from that fd rather than re-opening /dev/tty
  # on every read -- re-opening it per-read is what makes a signal landing
  # mid-read wedge the shell (confirmed by hand: a SIGINT trap that fires
  # while a `read ... </dev/tty` is blocked never regains control and hangs
  # forever; the exact same loop reading from a single already-open fd
  # returns cleanly the instant the trap runs).
  local ttyfd
  { exec {ttyfd}<>/dev/tty } 2>/dev/null || return 1

  # No matter how this function exits -- including a ^C landing mid-query --
  # the tty must come back out of raw mode.
  trap 'stty "$old_stty" 2>/dev/null; exec {ttyfd}<&-; trap - INT; return 130' INT

  # raw/-echo so the reply is never drawn on screen and arrives byte-at-a-
  # time without line buffering; min 0 time 3 bounds each single-byte read
  # to ~0.3s so a silent terminal can't stall us for long.
  stty raw -echo min 0 time 3 2>/dev/null

  # A 1x1 pixel transmission "query" action (a=q -- validates without
  # displaying anything), immediately followed by a Primary Device
  # Attributes request.
  print -nu $ttyfd $'\x1b_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\x1b\\\x1b[c'

  local reply="" chunk
  local -i tries=0 deadline=$(( SECONDS + 2 ))
  while (( tries < 100 && SECONDS < deadline )); do
    IFS= read -u $ttyfd -r -k 1 -t 0.3 chunk || break
    reply+="$chunk"
    (( tries++ ))
    # A Primary DA reply is a CSI sequence that always ends in a bare 'c';
    # once we've seen it, neither query has anything left to send.
    [[ "$reply" == *$'\x1b['*c ]] && break
  done

  exec {ttyfd}<&-
  stty "$old_stty" 2>/dev/null
  trap - INT

  # A supporting terminal answers the graphics query with \e_Gi=31;...\e\\
  # (OK, or an error -- either proves it parsed and answered in-protocol).
  if [[ "$reply" == *$'\x1b_G'*';'* ]]; then
    _to_qr_kitty_graphics_support=1
  else
    _to_qr_kitty_graphics_support=0
  fi

  [[ "$_to_qr_kitty_graphics_support" == 1 ]]
}

to_qr() {
  if [[ -z "$1" && -t 0 ]]; then
    echo "Usage: to_qr <string> (or pipe input to it)"
    return 1
  fi

  local size="${TO_QR_SIZE:-40x40}"
  local fmt="symbols"
  _supports_kitty_graphics && fmt="kitty"

  local -a qr_args
  [[ -n "$1" ]] && qr_args=("$1")

  qrencode -o - "${qr_args[@]}" | chafa -f "$fmt" --size "$size" -
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
