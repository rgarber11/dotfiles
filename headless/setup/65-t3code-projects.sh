#!/usr/bin/env bash
# T3 Code projects for the PhoeniciaLabsOrg repos the Coder template checks out
# into ~/workspace: dsp-base, plus the sibling repos when the workspace's
# clone_org_repos parameter is on. Picked by origin URL rather than listed here,
# so a repo the template starts cloning is picked up without a change here.
#
# The template's startup script runs in parallel with this install. On a first
# start it clones dsp-base and only moves it into place after its npm install,
# minutes later. So a detached waiter holds off until the template would call
# the workspace ready, by the same test as its Setup status row (dsp-base
# checked out and ~/.config/dsp/setup-running gone), then adds every checkout.
# Running detached also keeps the second or so each `t3 project add` takes off
# the startup path.
#
# `t3 project add` works with or without the server running, and refuses a
# path that already has an active project, so running this on every start is a
# no-op after the first. A project removed in the T3 UI comes back on the next
# start.

add_t3code_project() {   # $1 = workspace root
  local out
  if out="$(t3 project add "$1" 2>&1 </dev/null)"; then
    info "t3: added project $1"
  elif [[ "$out" != *ProjectAlreadyExistsError* ]]; then
    # t3 logs a migration banner and a stack trace around the one line that
    # says what went wrong.
    warn "t3: could not add project $1: $(grep -m1 ERROR <<<"$out" || tail -n1 <<<"$out")"
  fi
}

t3code_org_checkouts() {   # prints each PhoeniciaLabsOrg checkout in ~/workspace
  local dir url
  # The glob skips the template's .<repo>.staging trees.
  for dir in "$HOME"/workspace/*/; do
    dir=${dir%/}
    [ -e "$dir/.git" ] || continue
    url="$(git -C "$dir" remote get-url origin 2>/dev/null)" || continue
    if [[ "$url" =~ github\.com[:/]PhoeniciaLabsOrg/ ]]; then
      printf '%s\n' "$dir"
    fi
  done
}

# Runs detached. The default wait comfortably covers a first start, which took
# about 9 minutes. Past it the setup marker is more likely stale than the setup
# still running, so add what is there rather than nothing.
wait_and_add_t3code_projects() {
  local poll=${T3CODE_PROJECT_POLL_SECONDS:-10} root
  local deadline=$((SECONDS + ${T3CODE_PROJECT_WAIT_SECONDS:-3600}))
  until [ -e "$HOME/workspace/dsp-base/.git" ] &&
        [ ! -e "$HOME/.config/dsp/setup-running" ]; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      warn "t3: workspace setup is still not done; adding what is checked out"
      break
    fi
    sleep "$poll"
  done
  while read -r root; do
    add_t3code_project "$root"
  done < <(t3code_org_checkouts)
}

start_t3code_projects() {
  local state="$HOME/.local/state/t3code"
  command -v t3 >/dev/null 2>&1 || return 0
  mkdir -p "$state" || { warn "t3: could not create $state"; return 0; }
  # setsid and full stdio redirection for the same reason as t3 serve in
  # 60-t3code.sh: the Coder agent waits for every holder of the startup
  # script's stdout and stderr.
  (setsid bash -c "$(declare -f info warn add_t3code_project t3code_org_checkouts \
      wait_and_add_t3code_projects)
    wait_and_add_t3code_projects" >>"$state/projects.log" 2>&1 </dev/null &)
  info "t3: adding PhoeniciaLabsOrg checkouts as T3 projects in the background (log: $state/projects.log)"
}

start_t3code_projects
