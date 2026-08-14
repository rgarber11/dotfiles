#!/usr/bin/env bash
# Runs install.sh in a container that mimics a dsp-base workspace.
#
#   ./tests/run.sh          fresh volume, install, assert, simulate restart, assert again
#   ./tests/run.sh --keep   reuse the existing volume (faster iteration)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
IMAGE=dotfiles-test
VOLUME=dotfiles-test-home
# shellcheck source=tests/lib.sh
source "$HERE/lib.sh"

case "${1:-}" in
  ""|--keep) ;;
  *) echo "run.sh: unknown argument: $1" >&2; exit 2 ;;
esac
[ "${1:-}" = "--keep" ] || podman volume rm -f "$VOLUME" >/dev/null 2>&1 || true
podman volume create "$VOLUME" >/dev/null 2>&1 || true
podman build -q -t "$IMAGE" -f "$HERE/Containerfile" "$HERE" >/dev/null

# Each invocation is a NEW container on the SAME volume: /usr resets, $HOME persists.
# $1, if "restart", is the only way in to the two spec-base-only knobs below --
# not env vars a caller could leave exported. STUB_CONFLICTS and SEED_HUB_MARKER
# are 100% correlated (both only ever apply to the restart call), and an env-var
# form has a real hazard: a developer exporting SEED_HUB_MARKER while debugging
# would make the *first* install_run call of every future invocation seed the
# marker too -- corrupting that run's own "hub is pinned to hosted" assertion
# with no hint why. A positional argument can't leak like that, and it also
# stops passing a spec-base-only knob into the three container roles that
# ignore it (the CHECKS and AFTER probes, and nocreds_run).
in_workspace() {
  local stub_conflicts=0 seed_hub_marker=0
  if [ "${1:-}" = restart ]; then
    stub_conflicts=1
    seed_hub_marker=1
  fi
  # The GIT_* values mimic what the Coder agent exports. They are deliberately
  # WRONG so the identity assertions actually prove .zshenv/.bashrc beat them;
  # without these the test would pass even if the unset were missing entirely.
  podman run --rm -i \
    -v "$VOLUME:/home/coder" \
    -v "$REPO:/repo:ro" \
    -e CODER_AGENT_URL=http://fake.invalid \
    -e GIT_AUTHOR_NAME="Wrong Person" \
    -e GIT_AUTHOR_EMAIL=wrong@example.com \
    -e GIT_COMMITTER_NAME="Wrong Person" \
    -e GIT_COMMITTER_EMAIL=wrong@example.com \
    -e STUB_CONFLICTS="$stub_conflicts" \
    -e SEED_HUB_MARKER="$seed_hub_marker" \
    "$IMAGE" bash -s
}

install_run() {
  in_workspace "${1:-}" <<'SH'
set -e
# Reproduce what `coder dotfiles` does: clone into Coder's global config dir.
mkdir -p ~/.config/coderv2
rm -rf ~/.config/coderv2/dotfiles
cp -r /repo ~/.config/coderv2/dotfiles
# The real spec-base repo is private and this container has no credentials, so
# the setup step is pointed at a local git repo instead. Cloning a path needs no
# credentials. It holds only a stub launcher that logs its argv and prints the
# real launcher's JSON shape, which is exactly the seam worth testing here: which
# subcommand the step chooses. The launcher itself has its own test suite.
# Rebuilt every run, not just when missing: --keep persists this fixture on the
# volume across separate ./tests/run.sh invocations, so a stale build would
# silently keep testing an old stub after editing it.
#
# Note for whoever automates the UPGRADE=1 path later: rebuilding gives the
# fixture a fresh, unrelated root commit each run, so a `git fetch && merge`
# against it (what `update` does) would fail with "refusing to merge unrelated
# histories". Nothing here exercises that today -- the existing checkout's
# objects from an earlier run stay resolvable -- but it will bite the first
# `--upgrade` test against this fixture.
FIXTURE=~/.cache/spec-base-fixture
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/packages/spec-base-local/bin"
cat > "$FIXTURE/packages/spec-base-local/bin/spec-base-local.mjs" <<'STUB'
#!/usr/bin/env node
import { appendFileSync } from 'node:fs';
appendFileSync(`${process.env.HOME}/spec-base-stub.log`, `${process.argv.slice(2).join(' ')}\n`);
const cmd = process.argv[2];
// Enforce the subcommand contract, not just log it: a typo in the flags this
// step passes should fail loudly here, rather than silently produce a report
// shaped like nothing the real launcher would ever emit.
if (cmd !== 'install' && cmd !== 'update') {
  process.exit(2);
}
// Exercises both arms of the step's conflict-path mapper: a bare string (the
// shape a hand-rolled report or a future launcher revision might use) and the
// {link, reason} object the real launcher actually emits.
const conflicts = process.env.STUB_CONFLICTS === '1'
  ? ['commands/spec-base.md', { link: 'skills/spec-base-local', reason: 'not a symlink' }]
  : [];
const install = {
  linked: conflicts.length ? [] : ['skills/spec-base-local'],
  relinked: [],
  alreadyCorrect: [],
  conflicts,
};
// cmdInstall spreads install()'s fields at the top level; cmdUpdate nests them
// under "install". No assertion in this suite drives the update path yet --
// Task 6's manual upgrade check does -- but the stub needs to be capable of
// both shapes so the step's `r.install ?? r` parsing has something real to be
// tested against later.
const report = cmd === 'update' ? { checkout: 'stub', install } : { checkout: 'stub', ...install };
console.log(JSON.stringify(report));
STUB
git -C "$FIXTURE" init -q -b main
git -C "$FIXTURE" add -A
git -C "$FIXTURE" -c user.email=t@example.com -c user.name=T commit -qm fixture
export SPEC_BASE_REPO="$FIXTURE"
export SPEC_BASE_BRANCH=main
# A leftover temp dir from a clone killed partway through must be cleared, not
# tripped over: git refuses to clone into a non-empty directory, so without the
# pre-clone rm -rf the step would fail on every start from here on.
# Only on the pre-clone start: install_run is called twice and install #2 never
# clones, so seeding it there would just litter the post-restart state.
if [ ! -e ~/.claude/spec-base-local/checkout ]; then
  mkdir -p ~/.claude/spec-base-local/.checkout.tmp
  echo junk > ~/.claude/spec-base-local/.checkout.tmp/junk
fi
# Measured right after the clone, before install.sh runs: catches install.sh
# (or anything it runs, like `:Lazy update`) writing INTO the clone. A flat
# zero would false-fail on a host with an in-progress edit to install.sh, so
# we compare this against the same measurement taken after install.sh below.
# -uno: only tracked modifications count as "install.sh modified the clone".
# cp -r (unlike the real `coder dotfiles` clone) carries over ignored files
# from the host working tree, e.g. an editor's untracked scratch directory;
# those aren't something install.sh writing into the clone would produce.
REPO_STATUS_BEFORE="$(git -C ~/.config/coderv2/dotfiles status --porcelain -uno | wc -l)"
chmod +x ~/.config/coderv2/dotfiles/install.sh
# Seed a real pre-existing file so the backup-before-overwrite path is
# actually exercised; on a fresh volume ~/.zshrc doesn't exist yet, so
# without this the backup logic would go untested. Idempotent: on the
# second run ~/.zshrc is already install.sh's symlink, so this leaves it
# alone.
[ -e ~/.zshrc ] || echo '# pre-existing user file' > ~/.zshrc
# The stub log lives on the persisted volume, so without this a leftover log
# from a previous run (or --keep) would inflate spec_clones' invocation count.
# Truncating here, not deleting: this keeps the fixture's own "append" contract
# intact and only resets what each install_run measures.
: > ~/spec-base-stub.log
# Gated on SEED_HUB_MARKER, not on "does config.json already exist": under
# --keep this same install_run also runs as the FIRST call of a later
# ./tests/run.sh invocation, when config.json already survives from the
# previous invocation's restart -- a plain existence check would reseed it
# there too and corrupt that run's own "hub is pinned to hosted" assertion.
# Only the restart call passes SEED_HUB_MARKER=1.
#
# The point of seeding at all: overwrite config.json with a value the setup
# step's own write path never produces, so the AFTER probe below can tell "the
# write-if-absent guard held" apart from "the guard is gone and it rewrote
# hosted -> hosted anyway" -- the fixture's install.sh only ever writes
# "hosted", so asserting spec_hub=hosted after a restart alone would pass
# either way.
if [ "$SEED_HUB_MARKER" = 1 ]; then
  if [ -e ~/.claude/spec-base-local/config.json ]; then
    printf '{\n  "hub": "custom-marker"\n}\n' > ~/.claude/spec-base-local/config.json
  fi
# Self-heals a stale marker on any non-restart call (the normal fresh-volume
# path, and a --keep invocation's first install alike). The AFTER probe below
# restores "hosted" on the happy path, but a genuine second-install failure,
# Ctrl-C, or a read-only/full volume failing that restore would otherwise
# leave the marker on the volume with nothing pointing at it -- the next
# --keep run would just fail "hub is pinned to hosted" with no clue why.
# Precise on purpose: only ever removes a config.json that literally holds our
# marker, so it can never touch a config.json a real run wrote.
elif [ -e ~/.claude/spec-base-local/config.json ] && \
     grep -qF '"custom-marker"' ~/.claude/spec-base-local/config.json; then
  rm -f ~/.claude/spec-base-local/config.json
fi
~/.config/coderv2/dotfiles/install.sh
REPO_STATUS_AFTER="$(git -C ~/.config/coderv2/dotfiles status --porcelain -uno | wc -l)"
echo "repo_status_delta=$((REPO_STATUS_AFTER - REPO_STATUS_BEFORE))"
# fortune and cowsay come from 10-packages.sh's apt install, which -- like
# everything else outside ~/.local -- lives in the container filesystem, not
# the persisted /home/coder volume. The later CHECKS block runs in a fresh
# container that never invoked install.sh, so /usr/games and these binaries
# would simply not exist there regardless of the PATH fix; this must be
# asserted inside THIS container, right after install.sh ran (same reasoning
# as the /etc/passwd shell= check right below).
echo "greeting=$(zsh -ic 'give_fortune' 2>/dev/null | head -1 | tr -d '\n' | cut -c1-20)"
# /etc/passwd lives in the container filesystem, not the persisted /home/coder
# volume, so it must be asserted inside THIS container, right after install.sh
# ran -- a separate podman run would see the image's default shell instead.
# id -un, not $USER: $USER is unset here (the same pitfall that broke
# 50-shell.sh).
echo "shell=$(getent passwd "$(id -un)" | cut -d: -f7)"
SH
}

# A third install run, isolated by CLAUDE_CONFIG_DIR, with a repo that cannot
# exist. This is the harness's only way to reproduce a fresh workspace whose git
# credentials are not written yet: the clone must fail, warn, and leave nothing
# behind -- and install.sh must still finish, or a boot with no credentials would
# leave the workspace with no shell.
#
# Depends on install_run having already copied the repo onto the volume as
# ~/.config/coderv2/dotfiles -- this only invokes install.sh from there, so it
# cannot run standalone against a fresh volume.
nocreds_run() {
  in_workspace <<'SH'
set -e
export CLAUDE_CONFIG_DIR=/tmp/claude-nocreds
export SPEC_BASE_REPO=/nonexistent/spec-base.git
export SPEC_BASE_BRANCH=main
# Simulate a clone killed partway through on an earlier start: the leftover temp
# directory must be cleared, not adopted. Without the rm -rf around the clone
# this junk would survive.
mkdir -p /tmp/claude-nocreds/spec-base-local/.checkout.tmp/.git
echo junk > /tmp/claude-nocreds/spec-base-local/.checkout.tmp/junk
~/.config/coderv2/dotfiles/install.sh
echo "nocreds_checkout=$([ -d /tmp/claude-nocreds/spec-base-local/checkout ] && echo present || echo absent)"
echo "nocreds_tmp=$([ -e /tmp/claude-nocreds/spec-base-local/.checkout.tmp ] && echo present || echo absent)"
SH
}

echo "=== first install (fresh home) ==="
FIRST="$(install_run 2>&1)" || { echo "$FIRST"; echo "install failed"; exit 1; }
echo "$FIRST" | tail -20

echo
echo "=== assertions after first install ==="
CHECKS="$(in_workspace <<'SH'
export PATH="$HOME/.local/bin:$PATH"
echo "nvim=$(command -v nvim || echo none)"
echo "difft=$(command -v difft || echo none)"
# Not just "is chafa present" -- noble's apt chafa is 1.14, which predates
# --probe and is the whole reason to_qr rendered too narrow over ssh. Assert
# the ~/.local build wins on PATH and that it actually has the feature.
echo "chafa=$(command -v chafa || echo none)"
echo "chafa_probe=$(chafa --help 2>/dev/null | grep -c -- --probe || echo 0)"
# Not just "is node present" -- noble's apt nodejs is 18.19, the whole reason
# the Containerfile installs from nodesource instead. Assert the version, not
# just presence, so a nodesource install that silently fell back to noble's
# package (see the Containerfile's build-time guard) would still be caught here.
echo "node=$(node --version)"
# --help is handled in the arg loop before fasterfetch checks for fastfetch and
# chafa, so this exercises the symlink, the exec bit and that the script parses,
# without needing a tty for its terminal probe.
echo "fasterfetch=$(command -v fasterfetch || echo none)"
echo "fasterfetch_help=$(fasterfetch --help >/dev/null 2>&1 && echo ok || echo fail)"
echo "fastfetch=$(command -v fastfetch || echo none)"
echo "herdr=$(command -v herdr || echo none)"
echo "zshrc=$(readlink -f ~/.zshrc || echo none)"
echo "nvimcfg=$(readlink -f ~/.config/nvim || echo none)"
# The dsp-base image sources its own /etc/zsh/dsp-base.zsh -- powerlevel10k and
# the same five plugins -- from the stock /etc/zsh/zshrc, i.e. before ~/.zshrc.
# This marker is what makes it stand down; without it every plugin loads twice.
# This container mimics the image as it was BEFORE that config was baked in and
# has no such file, so all that can be asserted here is that the marker gets
# created. That it actually suppresses the system config is verified against
# the real image.
echo "no_system_rc=$([ -e ~/.config/zsh/no-system-rc ] && echo yes || echo no)"
echo "gitconfig_first_line=$(head -1 ~/.gitconfig 2>/dev/null)"
echo "git_email=$(git config --get user.email)"
echo "zsh_ident=$(zsh -ic 'git var GIT_AUTHOR_IDENT' 2>/dev/null | tail -1)"
echo "bash_ident=$(bash -lc 'git var GIT_AUTHOR_IDENT' 2>/dev/null | tail -1)"
echo "backups=$(find ~ -maxdepth 1 -name '*.pre-dotfiles*' | wc -l)"
# The greeting assertion elsewhere calls give_fortune directly, which proves
# fortune/cowsay resolve on PATH but never exercises how .zshrc actually
# wires it up. This catches the likely regressions -- someone dropping the
# call from .zshrc, or someone moving it back below the instant-prompt
# block -- without needing a pty to drive a real prompt cycle. Ordering is
# the whole fix here: p10k's instant prompt treats any console output
# produced from its sourcing point onward as suspect, so give_fortune has to
# run strictly before it, not merely somewhere in the file.
echo "greet_before_instant=$(awk '
  /p10k-instant-prompt/ && !p10k_line { p10k_line = NR }
  /^give_fortune$/ && !fortune_line { fortune_line = NR }
  END { print (fortune_line && p10k_line && fortune_line < p10k_line) ? "yes" : "no" }
' ~/.zshrc)"
# nvim's binary and config symlink both persist under ~/.local and the repo
# clone, so (unlike fortune/cowsay above) this is fine to check from a fresh
# container.
# Write the value to a file rather than capturing stdout or stderr. A first
# nvim launch emits lazy.nvim build chatter (hererocks clone, treesitter parser
# downloads) on BOTH streams, which otherwise gets concatenated into the
# captured value and fails the assertion for reasons unrelated to the theme.
nvim --headless \
  -c 'lua local f=io.open("/tmp/nvim-colors","w") f:write(vim.g.colors_name or "none") f:close()' \
  -c qa >/dev/null 2>&1 || true
echo "colorscheme=$(cat /tmp/nvim-colors 2>/dev/null || echo unknown)"
echo "spec_checkout=$([ -d ~/.claude/spec-base-local/checkout/.git ] && echo present || echo absent)"
echo "spec_hub=$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.env.HOME + "/.claude/spec-base-local/config.json", "utf8")).hub)' 2>/dev/null || echo none)"
# The last line, not the whole file: install_run truncates this log at the top
# of each run, so today it only ever holds this run's own invocation(s) -- tail
# -1 just keeps this robust if that ever changes to hold more than one line.
echo "spec_argv=$(tail -1 ~/spec-base-stub.log 2>/dev/null)"
# wc -l, not `grep -c '^' ... || echo 0`: grep -c on an empty-but-present log
# prints "0" AND exits 1, so the `|| echo 0` fallback fires too and doubles the
# line -- garbling this exact spot in exactly the failure case worth debugging.
# The redirection into wc simply fails (nothing printed) if the log is missing,
# so the fallback only ever contributes one line.
echo "spec_clones=$(wc -l < ~/spec-base-stub.log 2>/dev/null || echo 0)"
# Present here would mean the successful clone left its staging dir behind --
# e.g. a `cp -r` standing in for the `mv` into place -- which a checkout=present
# check alone would not catch, since the copy still populates the checkout fine.
echo "spec_tmp=$([ -e ~/.claude/spec-base-local/.checkout.tmp ] && echo present || echo absent)"
SH
)"
echo "$CHECKS"

assert_not_contains "nvim installed"      "nvim=none"      "$CHECKS"
assert_not_contains "difftastic installed" "difft=none"    "$CHECKS"
assert_not_contains "fastfetch installed" "fastfetch=none" "$CHECKS"
assert_not_contains "herdr installed"     "herdr=none"     "$CHECKS"
assert_contains "nvim is under ~/.local"  "nvim=/home/coder/.local/bin/nvim" "$CHECKS"
assert_contains "chafa is the ~/.local build, not noble's 1.14" \
  "chafa=/home/coder/.local/bin/chafa" "$CHECKS"
assert_not_contains "chafa supports --probe" "chafa_probe=0" "$CHECKS"
assert_contains "node is nodesource 24, not noble's 18.19" "node=v24." "$CHECKS"
assert_contains "fasterfetch is linked into ~/.local/bin" \
  "fasterfetch=/home/coder/.local/bin/fasterfetch" "$CHECKS"
assert_contains "fasterfetch runs" "fasterfetch_help=ok" "$CHECKS"
assert_contains "gitconfig is generated"  "gitconfig_first_line=# generated by dotfiles install.sh" "$CHECKS"
assert_contains "zsh identity beats the agent env" \
  "zsh_ident=Richard Garber <9834847+rgarber11@users.noreply.github.com>" "$CHECKS"
assert_contains "bash identity beats the agent env" \
  "bash_ident=Richard Garber <9834847+rgarber11@users.noreply.github.com>" "$CHECKS"
assert_not_contains "the wrong address never wins" "wrong@example.com" "$CHECKS"
assert_contains "nvim uses catppuccin mocha in the workspace" "colorscheme=catppuccin-mocha" "$CHECKS"
assert_contains "login shell is zsh"      "shell=/usr/bin/zsh" "$FIRST"
# assert_not_contains does a plain substring match, and "greeting=" is a
# substring of "greeting=Some fortune text" just as much as of "greeting="
# alone -- checking for the bare key would fail unconditionally. Instead
# check for the key immediately followed by the newline the next echo
# produces: that sequence only occurs when the value is empty. (greeting=
# is asserted against $FIRST, not $CHECKS -- see the comment in install_run.)
assert_not_contains "fortune greeting produces output" $'greeting=\n' "$FIRST"
assert_contains "greeting runs before p10k instant prompt starts monitoring" \
  "greet_before_instant=yes" "$CHECKS"
assert_contains "zshrc symlinks into the repo" \
  "zshrc=/home/coder/.config/coderv2/dotfiles/headless/zshrc" "$CHECKS"
assert_contains "nvim config symlinks into the repo" \
  "nvimcfg=/home/coder/.config/coderv2/dotfiles/shared/nvim" "$CHECKS"
assert_contains "the image's system zsh config is opted out of" "no_system_rc=yes" "$CHECKS"
assert_contains "pre-existing zshrc was backed up, not clobbered" "backups=1" "$CHECKS"
assert_contains "install.sh does not modify the dotfiles clone" "repo_status_delta=0" "$FIRST"
assert_contains "the hub is pinned to hosted" "spec_hub=hosted" "$CHECKS"
# A normal start must never run the networked update: it fetches and merges
# origin/main, which is upgrade-only work in this repo. Anchored on the
# trailing newline the next echo produces, not a bare substring match: without
# it "install --anything" would also read as a pass.
assert_contains "a normal start links only" $'spec_argv=install\n' "$CHECKS"
# Anchored the same way as the restart's equivalent check below: a plain
# substring match on "spec_clones=1" also matches 10-19 and 100-199, which is
# exactly the window a step that looped the launcher once per link (instead of
# once per start) would land in.
assert_contains "the launcher ran once on a fresh install" $'spec_clones=1\n' "$CHECKS"
assert_contains "the spec-base checkout is cloned, and a leftover temp dir does not block it" \
  "spec_checkout=present" "$CHECKS"
assert_contains "the clone's staging dir does not survive a successful install" \
  "spec_tmp=absent" "$CHECKS"

echo
echo "=== second install (new container, same home: simulates restart) ==="
# STUB_CONFLICTS=1 only on this run: it drives the stub to report two
# conflicting links (one bare string, one {link, reason} object) so the warn
# path that names them gets exercised somewhere -- the first install's
# assertions above are all keyed off the default (no-conflicts) report, so
# this doesn't disturb them. A fourth container run just for this would cost
# another minute-plus; nothing this run already asserts (spec_argv, the
# invocation count, the hub) is sensitive to what the report's counts are.
SECOND="$(install_run restart 2>&1)" || { echo "$SECOND"; echo "second install failed"; exit 1; }
echo "$SECOND" | tail -20

echo
echo "=== assertions after restart ==="
assert_not_contains "neovim not re-downloaded"    "downloading nvim"      "$SECOND"
assert_not_contains "difftastic not re-downloaded" "downloading difft"     "$SECOND"
assert_not_contains "fastfetch not re-downloaded" "downloading fastfetch" "$SECOND"
assert_not_contains "herdr not reinstalled"       "installing herdr"      "$SECOND"
assert_contains "install.sh does not modify the dotfiles clone (restart)" "repo_status_delta=0" "$SECOND"
assert_contains "conflicting links are named, not just counted" \
  "commands/spec-base.md skills/spec-base-local" "$SECOND"
assert_not_contains "the spec-base checkout is not re-cloned" "spec-base: cloning" "$SECOND"

AFTER="$(in_workspace <<'SH'
export PATH="$HOME/.local/bin:$PATH"
echo "nvim=$(command -v nvim || echo none)"
echo "zshrc=$(readlink -f ~/.zshrc || echo none)"
echo "nvimcfg=$(readlink -f ~/.config/nvim || echo none)"
echo "backups=$(find ~ -maxdepth 1 -name '*.pre-dotfiles*' | wc -l)"
echo "bashrc_blocks=$(grep -cF '# >>> dotfiles: coder git identity >>>' ~/.bashrc)"
echo "profile_blocks=$(grep -cF '# >>> dotfiles: coder git identity >>>' ~/.profile)"
echo "spec_argv=$(tail -1 ~/spec-base-stub.log 2>/dev/null)"
echo "spec_clones=$(wc -l < ~/spec-base-stub.log 2>/dev/null || echo 0)"
echo "spec_hub=$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.env.HOME + "/.claude/spec-base-local/config.json", "utf8")).hub)' 2>/dev/null || echo none)"
# Restore the pin the seeding step above overwrote. Without this, the
# custom-marker value would persist on the volume and, under --keep, corrupt
# the *next* invocation's fresh-install assertion that the hub is pinned to
# hosted (that install_run would see config.json already present and, quite
# correctly, leave the leftover marker alone). install_run's own self-heal is
# the backstop if this fails outright; this line still has to say so rather
# than swallow it, or a read-only/full volume leaves no signal at all.
if ! printf '{\n  "hub": "hosted"\n}\n' > ~/.claude/spec-base-local/config.json 2>/dev/null; then
  echo "spec_hub_restore_failed=1"
fi
SH
)"
echo "$AFTER"
assert_contains "nvim survived the restart" "nvim=/home/coder/.local/bin/nvim" "$AFTER"
assert_contains "chsh re-applied after restart" "shell=/usr/bin/zsh" "$SECOND"
assert_contains "zshrc symlink survived the restart" \
  "zshrc=/home/coder/.config/coderv2/dotfiles/headless/zshrc" "$AFTER"
assert_contains "nvim config symlink survived the restart" \
  "nvimcfg=/home/coder/.config/coderv2/dotfiles/shared/nvim" "$AFTER"
assert_contains "no duplicate backup on restart" "backups=1" "$AFTER"
assert_contains "no duplicate bashrc block" "bashrc_blocks=1" "$AFTER"
assert_contains "no duplicate profile block" "profile_blocks=1" "$AFTER"
assert_contains "the restart re-links" $'spec_argv=install\n' "$AFTER"
# Truncated at the top of each install_run, so this counts invocations within the
# restart alone: exactly one. Catches a step that calls the launcher twice per
# start, and unlike a cumulative count it holds under --keep too. Anchored on
# the trailing newline: a bare substring match on "spec_clones=1" also matches
# 10-19 and 100-199, which is exactly the window a step that looped the
# launcher once per link (instead of once per start) would land in.
assert_contains "the launcher ran once per start" $'spec_clones=1\n' "$AFTER"
# The seeded value from install_run's heredoc, not "hosted": proves config.json
# is left alone on a restart, rather than merely happening to still say hosted
# (see the comment at the seeding site for why the latter would not distinguish
# "not rewritten" from "rewritten identically").
assert_contains "an existing config.json is not overwritten by the restart" \
  "spec_hub=custom-marker" "$AFTER"
# Closes the loop on the restore two lines up in the heredoc: without this,
# a restore that fails (read-only or full volume) still prints "all checks
# passed", with the failure visible only to a human reading the dump on an
# otherwise-green run -- which nobody does.
assert_not_contains "the hub pin is restored for the next --keep run" \
  "spec_hub_restore_failed=1" "$AFTER"

echo
echo "=== third install (unreachable spec-base repo, isolated claude dir) ==="
NOCREDS="$(nocreds_run 2>&1)" || { echo "$NOCREDS"; echo "install failed without spec-base credentials"; exit 1; }
echo "$NOCREDS" | tail -20

assert_contains "install.sh finishes when the spec-base repo is unreachable" \
  "==> dotfiles: done" "$NOCREDS"
assert_contains "an unreachable spec-base repo warns instead of aborting" \
  "spec-base: clone failed" "$NOCREDS"
# Positive control for "the spec-base checkout is not re-cloned" above: that
# assertion greps $SECOND for the same "spec-base: cloning" text, and the only
# other place that string exists in the whole suite is the `info` line at
# 99-spec-base-setup.sh's clone site. Reword that line with nothing else
# checking for it, and the not-re-cloned assertion would pass forever with
# nothing flagging that it had gone vacuous. Asserting it here instead of
# against $FIRST: $FIRST is not a mode-independent place to always find a
# clone attempt (under --keep, a persisted checkout means the first install
# legitimately does not clone either), but nocreds_run's isolated
# CLAUDE_CONFIG_DIR lives in the container filesystem, not the volume, so it
# starts empty every time and always reaches the clone path.
assert_contains "the clone path announces itself (positive control for the not-re-cloned check above)" \
  "spec-base: cloning" "$NOCREDS"
# git cleans up its own failed clone of a path that never existed, so this only
# proves the isolated config dir was left with no checkout at all -- not that a
# partially-written one gets cleaned up. The next assertion covers that case.
assert_contains "a failed clone leaves no checkout behind" \
  "nocreds_checkout=absent" "$NOCREDS"
assert_contains "a leftover partial clone is cleared, not adopted" \
  "nocreds_tmp=absent" "$NOCREDS"

summary
