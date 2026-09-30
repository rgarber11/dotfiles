#!/usr/bin/env bash
# T3 Code provider instances for every Claude profile ai-auth has logged in.
#
# The logins already live on the shared /mnt/user-state volume, and each
# ~/.claude-<name> the template links points there. What T3 does not get from
# them is the instance list in ~/.t3/userdata/settings.json, which is on this
# workspace's PVC, so a new workspace starts with only the built-in Claude.
# This adds a claudeAgent instance per profile before 60-t3code.sh starts the
# server.
#
# It only adds. An instance already pointing at a profile's home, under any id,
# is left exactly as it is, so a rename or disable in the T3 UI sticks. A
# deleted one comes back on the next start; disable it instead.
#
# "default" is skipped because it is ~/.claude, which T3's built-in Claude
# provider already uses.

seed_t3code_providers() {
  local settings="$HOME/.t3/userdata/settings.json" listing current updated
  local -a profiles=()

  command -v ai-auth >/dev/null 2>&1 || return 0
  if ! command -v jq >/dev/null 2>&1; then
    warn "t3: jq not found; not seeding T3 providers from ai-auth"
    return 0
  fi

  listing="$(ai-auth claude list 2>/dev/null)" || {
    warn "t3: 'ai-auth claude list' failed; not seeding T3 providers"
    return 0
  }
  # The status column is two or three words ("logged in", "not logged in"),
  # so match it from the end of the line.
  while read -r name; do
    [[ "$name" =~ ^[A-Za-z0-9_-]+$ ]] || continue
    [ -d "$HOME/.claude-$name" ] || continue
    profiles+=("$name")
  done < <(awk 'NR > 1 && $1 != "default" && $NF == "in" && $(NF-1) == "logged" &&
                $(NF-2) != "not" { print $1 }' <<<"$listing")
  [ "${#profiles[@]}" -gt 0 ] || return 0

  if [ -e "$settings" ]; then
    current="$(cat "$settings")" || { warn "t3: could not read $settings"; return 0; }
  else
    current='{}'
  fi

  updated="$(
    printf '%s\n' "${profiles[@]}" |
      jq -R '{id: ("claudeAgent_" + .), home: ("~/.claude-" + .),
              display: ((.[:1] | ascii_upcase) + .[1:])}' |
      jq -s --argjson settings "$current" '
        reduce .[] as $p ($settings;
          if [(.providerInstances // {})[] | .config.homePath?] | index($p.home)
          then .
          else .providerInstances[$p.id] = {
            driver: "claudeAgent", displayName: $p.display, enabled: true,
            config: {homePath: $p.home}}
          end)' 2>/dev/null
  )" || { warn "t3: $settings is not valid JSON; not seeding T3 providers"; return 0; }

  [ "$(jq -S . <<<"$current")" = "$(jq -S . <<<"$updated")" ] && return 0

  mkdir -p "${settings%/*}" || { warn "t3: could not create ${settings%/*}"; return 0; }
  if printf '%s\n' "$updated" >"$settings.tmp" && mv "$settings.tmp" "$settings"; then
    info "t3: seeded provider instances from ai-auth"
  else
    rm -f "$settings.tmp"
    warn "t3: could not write $settings"
  fi
}

seed_t3code_providers
