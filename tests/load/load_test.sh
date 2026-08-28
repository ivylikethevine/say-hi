#!/usr/bin/env bash
# Unit tests for load.sh, the target-side half of hi: the marker-delimited block
# it grafts onto the host's rc files, and the cleanup that takes it - and, only
# for a disposable tree, say-hi itself - back out. Sourced with
# _HI_LOAD_NO_INIT=1 for the functions alone, with _HI_CONFIGS and _HI_ROOT
# reassigned into the scratch dir.
#
# SAFETY: clean_all ends in `rm -rf "${_HI_CLEANUP:-$_HI_ROOT}"`, so no case
# calls it directly - every call goes through _hi_clean_all, which shadows
# both. The real thing with the real paths would delete this checkout; the
# canary case at the end proves none did.
#
# GLOSSARY: HI.30 + HI.34
# The single-quoted probe scripts expand in the child shell, which is the
# point (SC2016).
# shellcheck disable=SC2329,SC2016
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

_HI_LOAD_NO_INIT=1
# shellcheck source=../../load.sh
source "$_HI_ROOT/load.sh"

_HI_USER_LINE='# a line the user put here themselves'
_HI_FAKE_HOME=""

function _hi_fake_rcs() {
  local name
  _HI_FAKE_HOME="$_HI_WORKDIR/$1"
  rm -rf "$_HI_FAKE_HOME"
  mkdir -p "$_HI_FAKE_HOME"
  for name in bashrc zshrc fishconf; do
    printf 'source-for-%s\n' "$name" >"$_HI_FAKE_HOME/src.$name"
  done
  printf '%s\n' "$_HI_USER_LINE" >"$_HI_FAKE_HOME/.bashrc"
  printf '%s\n' "$_HI_USER_LINE" >"$_HI_FAKE_HOME/.zshrc"
  # rows are "<dialect>|<hi's rc>|<the user's rc>": bash and zsh share `sh`
  _HI_CONFIGS=(
    "sh|$_HI_FAKE_HOME/src.bashrc|$_HI_FAKE_HOME/.bashrc"
    "sh|$_HI_FAKE_HOME/src.zshrc|$_HI_FAKE_HOME/.zshrc"
    "fish|$_HI_FAKE_HOME/src.fishconf|$_HI_FAKE_HOME/.config/fish/config.fish"
  )
}

function _hi_clean_all() {
  local _HI_ROOT="${1:-$_HI_WORKDIR/unused-root}" _HI_CLEANUP="${2:-}"
  clean_all
}

function _hi_clean_only_root() {
  local -a _HI_CONFIGS=("sh|$_HI_WORKDIR/no.src|$_HI_WORKDIR/no.such.rc")
  _hi_clean_all "$@"
}

function _hi_block_count() {
  grep -c "^$_HI_CONFIG_START\$" "$1" 2>/dev/null || true
}

function test_configure_files_appends_block() {
  _hi_fake_rcs append
  configure_files
  [ "$(_hi_block_count "$_HI_FAKE_HOME/.bashrc")" -eq 1 ] || return 1
  grep -q '^source-for-bashrc$' "$_HI_FAKE_HOME/.bashrc" || return 1
  grep -q "^$_HI_CONFIG_END\$" "$_HI_FAKE_HOME/.bashrc" || return 1
  grep -q '^source-for-zshrc$' "$_HI_FAKE_HOME/.zshrc"
}

function test_configure_files_is_idempotent() {
  _hi_fake_rcs idempotent
  configure_files
  configure_files
  [ "$(_hi_block_count "$_HI_FAKE_HOME/.bashrc")" -eq 1 ]
}

function test_configure_files_skips_absent_fish_dir() {
  _hi_fake_rcs nofish
  configure_files
  [ ! -e "$_HI_FAKE_HOME/.config/fish/config.fish" ]
}

function test_configure_files_creates_missing_rc_file() {
  _hi_fake_rcs missingrc
  rm -f "$_HI_FAKE_HOME/.zshrc"
  configure_files
  [ -f "$_HI_FAKE_HOME/.zshrc" ] && grep -q '^source-for-zshrc$' "$_HI_FAKE_HOME/.zshrc"
}

function test_configure_files_grafts_fish_when_dir_exists() {
  _hi_fake_rcs withfish
  mkdir -p "$_HI_FAKE_HOME/.config/fish"
  configure_files
  grep -q '^source-for-fishconf$' "$_HI_FAKE_HOME/.config/fish/config.fish"
}

# clean_all cannot run after a hard kill, so configure_files wraps each graft
# in a tree-exists guard (fish syntax for fish, sh's for the rest). The fixture
# content is not a command, so a guard failing
# open shows up as "command not found" on the next shell's stderr - which is
# exactly the user-visible symptom the guard exists to prevent.

# _hi_graft_probe <command> [NAME=VALUE...] - the shell the bash cases below
# put the graft in front of: a bash reading the grafted rc, on a pty of its
# own, with the run's environment cleared down to $HOME, $TERM and $PATH plus
# whatever the case names - $_HI_HOME above all, since the guard reads it.
#
# The pty is not decoration. `-i` is the only thing that makes bash read an
# --rcfile, and a forced-interactive bash claims a terminal for job control:
# it takes the one it inherits, and when its process group is not that
# terminal's foreground group it SIGTTINs its *whole* process group - this
# suite and the runner driving it included. That stops the run rather than
# failing it, with no output and nothing to wait for: the FreeBSD e2e job hung
# here for its full 30 minutes and was cancelled with the transcript ending on
# the "crash guard" heading. $_HI_PTY_FORCED gives the probe a session and a
# terminal of its own, so the only process group its job control can reach is
# its own; </dev/null keeps the wrapper's tcsetattr off our terminal, which is
# the same hazard one signal over (SIGTTOU). The cases are registered with
# _hi_check_capable pty, so a host that cannot build one skips them yellow
# rather than running the shape that hangs.
function _hi_graft_probe() {
  local cmd="$1"
  shift
  env -i HOME="$_HI_FAKE_HOME" TERM=dumb PATH="$PATH" "$@" \
    "${_HI_PTY_FORCED[@]}" bash --rcfile "$_HI_FAKE_HOME/.bashrc" -ic "$cmd" \
    </dev/null 2>&1
}

function test_dead_graft_is_silent_in_bash() {
  local out
  _hi_fake_rcs deadgraft
  configure_files
  out="$(_hi_graft_probe 'echo probe-ok')"
  # the shared error vocabulary, not just "command not found": a guard that
  # fails open with any symptom has to fail this test
  [[ "$out" == *probe-ok* ]] && ! grep -qE "$_HI_SHELL_ERROR_RE" <<<"$out"
}

# $_HI_HOME is what the guard asks for - it never falls back to $HOME, since a
# guessed tree is how a session ends up reading someone else's
# (GLOSSARY: HI.33). In a real session hi.sh's preamble has exported it, which
# is what this passes.
function test_live_graft_still_runs_in_bash() {
  local out
  _hi_fake_rcs livegraft
  mkdir -p "$_HI_FAKE_HOME/say-hi/common"
  : >"$_HI_FAKE_HOME/say-hi/common/core.sh"
  printf 'echo graft-ran\n' >"$_HI_FAKE_HOME/src.bashrc"
  configure_files
  out="$(_hi_graft_probe true _HI_HOME="$_HI_FAKE_HOME")"
  [[ "$out" == *graft-ran* ]]
}

# The bystander HI.24 names: a shell opened mid-session with none of the
# session's env. The tree is right there at $HOME/say-hi and the graft still has
# to stay out of it - that shell was never given a tree, and picking one for it
# is the guess this guard exists to refuse.
function test_live_graft_is_silent_without_a_tree_in_the_env() {
  local out
  _hi_fake_rcs bystander
  mkdir -p "$_HI_FAKE_HOME/say-hi/common"
  : >"$_HI_FAKE_HOME/say-hi/common/core.sh"
  printf 'echo graft-ran\n' >"$_HI_FAKE_HOME/src.bashrc"
  configure_files
  out="$(_hi_graft_probe 'echo probe-ok')"
  [[ "$out" == *probe-ok* ]] && [[ "$out" != *graft-ran* ]] &&
    ! grep -qE "$_HI_SHELL_ERROR_RE" <<<"$out"
}

function test_dead_graft_is_silent_in_fish() {
  local out
  _hi_fake_rcs deadfish
  mkdir -p "$_HI_FAKE_HOME/.config/fish"
  # the row's shell column is what selects fish's guard syntax
  printf 'not-a-command\n' >"$_HI_FAKE_HOME/src.rc.fish"
  local -a _HI_CONFIGS=("fish|$_HI_FAKE_HOME/src.rc.fish|$_HI_FAKE_HOME/.config/fish/config.fish")
  configure_files
  out="$(env -i HOME="$_HI_FAKE_HOME" TERM=dumb PATH="$PATH" \
    fish -c 'echo probe-ok' 2>&1)"
  # fish phrases its errors its own way, so the fixture token rides alongside
  # the shared vocabulary
  [[ "$out" == *probe-ok* && "$out" != *not-a-command* ]] &&
    ! grep -qE "$_HI_SHELL_ERROR_RE" <<<"$out"
}

function test_clean_all_strips_block_and_keeps_user_lines() {
  _hi_fake_rcs strip
  configure_files
  _hi_clean_all
  [ "$(cat "$_HI_FAKE_HOME/.bashrc")" = "$_HI_USER_LINE" ] || return 1
  [ "$(cat "$_HI_FAKE_HOME/.zshrc")" = "$_HI_USER_LINE" ]
}

# Two overlapping sessions to one host, a shape the docs otherwise leave
# unstated. configure_files skips the graft when the marker is already there,
# so the second session adds nothing; clean_all strips on the way out
# unconditionally, so the *first* session to leave takes the block away from
# the one still running. Not "the owner cleans up after itself" - whoever exits
# first does.
#
# This is a known limit, not a bug, and docs/CONFIGURATION.md says so: nothing
# the survivor is using breaks (a running shell read its rc once, and the
# session trees are per-mktemp so neither can delete the other's), but a shell
# opened inside it afterwards - su, a nested login - comes up
# bare. Refcounting the graft is the alternative, and it needs shared state on
# the target that would outlive a crashed session, which is the thing hi's
# footprint promise (docs/SECURITY.md) exists to avoid.
#
# If this case ever fails because the block survived, the graft has been
# refcounted: CONFIGURATION.md's note has to change in the same commit.
function test_second_session_adds_no_block_and_first_exit_strips_it() {
  _hi_fake_rcs concurrent
  configure_files # session A connects and grafts
  configure_files # session B connects, sees the marker, adds nothing
  [ "$(_hi_block_count "$_HI_FAKE_HOME/.bashrc")" -eq 1 ] || return 1
  _hi_clean_all # ...and whichever of the two exits first strips it
  [ "$(cat "$_HI_FAKE_HOME/.bashrc")" = "$_HI_USER_LINE" ]
}

function test_clean_all_removes_lone_start_marker() {
  _hi_fake_rcs lonemarker
  printf '%s\n%s\n' "$_HI_CONFIG_START" 'orphaned line' >>"$_HI_FAKE_HOME/.bashrc"
  _hi_clean_all
  ! grep -q "$_HI_CONFIG_START" "$_HI_FAKE_HOME/.bashrc" || return 1
  grep -q '^orphaned line$' "$_HI_FAKE_HOME/.bashrc"
}

function test_clean_all_keeps_permanent_install() {
  local root="$_HI_WORKDIR/permanent"
  mkdir -p "$root"
  printf 'colors\n' >"$root/keepme"
  _hi_clean_only_root "$root"
  [ -f "$root/keepme" ]
}

function test_clean_all_removes_disposable_copy() {
  local root="$_HI_WORKDIR/disposable"
  mkdir -p "$root"
  printf 'copied\n' >"$root/keepme"
  _hi_clean_only_root "$root" "$root"
  [ ! -e "$root" ]
}

# D4: clean_all removes the whole $_HI_CLEANUP tree, not just $_HI_ROOT under
# it - a sibling file that landed directly under $_HI_HOME (the ssh arm's
# $_HI_SESSION_RC_DIR before it was nested under $_HI_CLEANUP, or anything
# else that might one day) goes with it, not just say-hi/ itself.
function test_clean_all_removes_the_whole_cleanup_tree_not_just_root() {
  local cleanup="$_HI_WORKDIR/wholetree" root="$_HI_WORKDIR/wholetree/say-hi"
  mkdir -p "$root"
  printf 'sibling\n' >"$cleanup/sibling-file"
  _hi_clean_only_root "$root" "$cleanup"
  [ ! -e "$cleanup" ]
}

function test_clean_all_succeeds_with_nothing_to_do() {
  _hi_clean_only_root "$_HI_WORKDIR/never-created"
}

function _hi_source_load() {
  local home="$1" guard="$2"
  _HI_LOAD_NO_INIT="$guard" HOME="$home" bash -c \
    'source "$1/load.sh"; printf "%s|%s" "${HI_LOAD_TEST_PROFILE:-}" "$PATH"' _ "$_HI_ROOT"
}

function test_source_restores_profile() {
  local home="$_HI_WORKDIR/profilehome" out
  mkdir -p "$home"
  printf 'export HI_LOAD_TEST_PROFILE=1\n' >"$home/.profile"
  out="$(_hi_source_load "$home" 0)"
  [[ "${out%%|*}" == 1 ]]
}

function test_no_init_guard_skips_profile() {
  local home="$_HI_WORKDIR/profilehome" out
  mkdir -p "$home"
  printf 'export HI_LOAD_TEST_PROFILE=1\n' >"$home/.profile"
  out="$(_hi_source_load "$home" 1)"
  [[ -z "${out%%|*}" ]]
}

# The tree must NOT land on $PATH: on a disposable session $_HI_ROOT is a
# directory under /tmp, and "no /tmp on PATH" is a line item in every
# hardening baseline an admin has to answer to. paths.sh's `alias hi=` is
# what a session actually reaches the launcher through, in all four shells,
# so a PATH entry would add nothing `hi` typed inside a session to relay
# onward doesn't already have. Asserted on the restore path *and* under the
# no-init guard, since the append lives in the function the guard skips and
# could come back in either.
function test_tree_is_never_put_on_path() {
  local home="$_HI_WORKDIR/profilehome" out guard
  mkdir -p "$home"
  printf 'export HI_LOAD_TEST_PROFILE=1\n' >"$home/.profile"
  for guard in 0 1; do
    out="$(_hi_source_load "$home" "$guard")"
    [[ "${out#*|}" != *"$_HI_ROOT"* ]] || {
      _hi_cecho " | _HI_LOAD_NO_INIT=$guard put $_HI_ROOT on PATH" "$RED"
      return 1
    }
  done
}

# HI.46: the rc directory load() points the session shell at, and the three
# variables that carry it to anything started inside the session. The whole
# reason _HI_GRAFT_RC could become opt-in, so it is pinned rather than left to
# the e2e suites.
function _hi_rc_setup_in_a_subshell() {
  # in a subshell: this exports ZDOTDIR and ENV, which the rest of the run
  # must not inherit, and makes a directory only clean_all removes
  (
    _HI_SESSION_RC_DIR=""
    _hi_session_rc_setup || exit 1
    printf '%s\n' "$_HI_SESSION_RC_DIR" "$_HI_SESSION_RC" "$ZDOTDIR" "$ENV"
    for f in bashrc .zshrc .zshenv fish.config shrc; do
      [ -f "$_HI_SESSION_RC_DIR/$f" ] || {
        printf 'MISSING %s\n' "$f"
        exit 1
      }
    done
    # the target's own rc first, hi's on top - the order the graft produced
    head -n1 "$_HI_SESSION_RC_DIR/bashrc"
    rm -rf "$_HI_SESSION_RC_DIR"
  )
}

function test_session_rc_setup_writes_every_shell_and_exports_the_pointers() {
  local out dir rc zdot env_ first
  out="$(_hi_rc_setup_in_a_subshell)" || return 1
  case "$out" in *MISSING*)
    _hi_cecho " | $out" "$RED"
    return 1
    ;;
  esac
  dir="$(printf '%s' "$out" | sed -n 1p)"
  rc="$(printf '%s' "$out" | sed -n 2p)"
  zdot="$(printf '%s' "$out" | sed -n 3p)"
  env_="$(printf '%s' "$out" | sed -n 4p)"
  first="$(printf '%s' "$out" | sed -n 5p)"
  [ -n "$dir" ] || return 1
  # $_HI_SESSION_RC and $ZDOTDIR are the directory; $ENV is the POSIX rc in it
  [ "$rc" = "$dir" ] && [ "$zdot" = "$dir" ] && [ "$env_" = "$dir/shrc" ] || {
    _hi_cecho " | rc=$rc zdotdir=$zdot env=$env_ dir=$dir" "$RED"
    return 1
  }
  case "$first" in *'$HOME/.bashrc'*) return 0 ;; esac
  _hi_cecho " | the generated bashrc does not source the target's own first: $first" "$RED"
  return 1
}

# D4: with $_HI_CLEANUP set (the ephemeral shape), the rc directory nests
# under it - so the bootstrap's own `rm -rf $_HI_CLEANUP` backstop sweeps it
# too, not just clean_all - rather than a wholly separate mktemp invisible to
# that trap.
function test_session_rc_setup_nests_under_cleanup_when_set() {
  local dir
  (
    local _HI_SESSION_RC_DIR="" _HI_CLEANUP="$_HI_WORKDIR/nesttest"
    mkdir -p "$_HI_CLEANUP"
    _hi_session_rc_setup || exit 1
    printf '%s\n' "$_HI_SESSION_RC_DIR"
  ) >"$_HI_WORKDIR/nest_out"
  dir="$(cat "$_HI_WORKDIR/nest_out")"
  case "$dir" in
  "$_HI_WORKDIR/nesttest"/*) rm -rf "$_HI_WORKDIR/nesttest" ;;
  *)
    _hi_cecho " | $dir is not nested under \$_HI_CLEANUP" "$RED"
    rm -rf "$_HI_WORKDIR/nesttest"
    return 1
    ;;
  esac
}

# ...and without one (the permanent-install shape), a standalone mktemp -
# unaffected, and the case this suite already had before D4.
function test_session_rc_setup_stands_alone_without_cleanup() {
  local dir
  (
    local _HI_SESSION_RC_DIR=""
    unset _HI_CLEANUP
    _hi_session_rc_setup || exit 1
    printf '%s\n' "$_HI_SESSION_RC_DIR"
  ) >"$_HI_WORKDIR/nofollow_out"
  dir="$(cat "$_HI_WORKDIR/nofollow_out")"
  case "$dir" in
  "$_HI_WORKDIR"/*)
    _hi_cecho " | $dir landed under \$_HI_WORKDIR unexpectedly" "$RED"
    rm -rf "$dir"
    return 1
    ;;
  esac
  rm -rf "$dir"
}

# The session shell must be started against hi's rc, not a bare `$shell -i`
# that would read the target's $HOME. zsh is the one arm with no flag, because
# _hi_session_rc_setup exported $ZDOTDIR for it.
function test_session_shell_cmd_points_each_shell_at_his_rc() {
  local -a cmd=()
  local _HI_SESSION_RC_DIR="$_HI_WORKDIR/rcdir"
  _hi_session_shell_cmd bash cmd
  [ "${cmd[*]}" = "bash --rcfile $_HI_SESSION_RC_DIR/bashrc -i" ] || {
    _hi_cecho " | bash: ${cmd[*]}" "$RED"
    return 1
  }
  _hi_session_shell_cmd zsh cmd
  [ "${cmd[*]}" = "zsh -i" ] || {
    _hi_cecho " | zsh: ${cmd[*]}" "$RED"
    return 1
  }
  _hi_session_shell_cmd fish cmd
  [ "${cmd[*]}" = "fish -C source $_HI_SESSION_RC_DIR/fish.config -i" ] || {
    _hi_cecho " | fish: ${cmd[*]}" "$RED"
    return 1
  }
}

function test_this_checkout_was_never_touched() {
  [ -f "$_HI_ROOT/load.sh" ] && [ -f "$_HI_ROOT/hi.sh" ] && [ -d "$_HI_ROOT/common" ]
}

# Which shell the session runs in - $_HI_SHELL_PREFERENCE is the whole rule, and
# load.sh's own comment says why `login` leads its default.

# _hi_shell_answer <"bins..."> [NAME=VALUE ...] - the shell chosen when those
# binaries, and only those, are on $PATH.
#
# $PATH is *replaced*, not prefixed: the question is which shells exist, and
# this machine's real fish would answer for itself otherwise. The few real
# tools _hi_login_shell needs ride a second _hi_real_path entry, and the
# interpreter is named by absolute path since one of the fakes is called
# `bash`.
function _hi_shell_answer() {
  local bins="$1" dir
  shift
  # shellcheck disable=SC2086 # a deliberate word split into the fake list
  dir="$(_hi_fake_path "shells-${bins// /-}" $bins)"
  env -i "$@" PATH="$dir:$(_hi_real_path shell-tools id awk getent sh)" \
    HOME="$_HI_WORKDIR" _HI_HOME="$_HI_HOME" "$BASH" -c '
    _HI_LOAD_NO_INIT=1
    source "$_HI_HOME/say-hi/common/core.sh"
    source "$_HI_HOME/say-hi/load.sh"
    _hi_session_shell' 2>/dev/null
}

# _hi_shell_case <installed> <env-string> - _hi_shell_answer with the env
# pairs taken from one table field. eval'd so a value with spaces in it
# (_HI_SHELL_PREFERENCE="fish zsh bash") stays one argument; the field is
# literal text in this file, not input.
function _hi_shell_case() {
  local installed="$1" envs="$2"
  eval "set -- $envs"
  _hi_shell_answer "$installed" "$@"
}

function run_load_tests() {
  _hi_workdir loadtest

  _hi_h1 "Testing load.sh"

  _hi_suite_begin

  _hi_h2 "Testing: configure_files"
  _hi_check "Appends the marked block" test_configure_files_appends_block
  _hi_check "Second call doesn't duplicate it" test_configure_files_is_idempotent
  _hi_check "Skips fish when its config dir is absent" test_configure_files_skips_absent_fish_dir
  _hi_check "Grafts fish when its config dir exists" test_configure_files_grafts_fish_when_dir_exists
  _hi_check "Creates an rc file that doesn't exist yet" test_configure_files_creates_missing_rc_file

  _hi_h2 "Testing: the crash guard"
  _hi_check_capable pty "A dead graft is silent in bash" test_dead_graft_is_silent_in_bash
  _hi_check_capable pty "A live tree still runs the graft" test_live_graft_still_runs_in_bash
  _hi_check_capable pty "A bystander shell with no tree in its env is left alone" test_live_graft_is_silent_without_a_tree_in_the_env
  _hi_check_requires fish "A dead graft is silent in fish" test_dead_graft_is_silent_in_fish

  _hi_h2 "Testing: clean_all"
  _hi_check "Strips the block, keeps user lines" test_clean_all_strips_block_and_keeps_user_lines
  _hi_check "A second session adds no block; the first exit strips it" test_second_session_adds_no_block_and_first_exit_strips_it
  _hi_check "Removes a start marker with no end marker" test_clean_all_removes_lone_start_marker
  _hi_check "Keeps \$_HI_ROOT when _HI_CLEANUP is unset" test_clean_all_keeps_permanent_install
  _hi_check "Removes \$_HI_ROOT when _HI_CLEANUP is set" test_clean_all_removes_disposable_copy
  _hi_check "Removes the whole \$_HI_CLEANUP tree, not just \$_HI_ROOT (D4)" test_clean_all_removes_the_whole_cleanup_tree_not_just_root
  _hi_check "Succeeds with nothing to clean" test_clean_all_succeeds_with_nothing_to_do

  _hi_h2 "Testing: profile restoration"
  _hi_check "Sourcing restores the profile chain" test_source_restores_profile
  _hi_check "_HI_LOAD_NO_INIT=1 skips it" test_no_init_guard_skips_profile
  _hi_check "the tree is never put on PATH" test_tree_is_never_put_on_path
  _hi_check "the session rc dir carries every shell (HI.46)" test_session_rc_setup_writes_every_shell_and_exports_the_pointers
  _hi_check "the session shell reads hi's rc, not \$HOME's" test_session_shell_cmd_points_each_shell_at_his_rc
  _hi_check "the rc dir nests under \$_HI_CLEANUP when set (D4)" test_session_rc_setup_nests_under_cleanup_when_set
  _hi_check "...and stands alone without one" test_session_rc_setup_stands_alone_without_cleanup

  _hi_h2 "Testing: _hi_session_shell"
  # <label>|<installed shells>|<env pairs>|<want>. Six cases, three of which
  # asserted twice in one body - split into a row each, so a failure names the
  # half that broke and _hi_check_eq prints the shell it actually chose.
  while IFS='|' read -r _label _installed _env _want; do
    case "$_label" in '' | '#'*) continue ;; esac
    _hi_check_eq "$_label" "$_want" _hi_shell_case "$_installed" "$_env"
  done <<'EOF'
Prefers the login shell (zsh)|bash zsh fish|SHELL=/bin/zsh|zsh
Prefers the login shell (bash)|bash zsh fish|SHELL=/usr/bin/bash|bash
# a login shell hi doesn't style is not a reason to refuse the session
Falls back for a shell hi doesn't style|bash zsh fish|SHELL=/bin/mksh|fish
# ...nor is one that isn't installed here
Falls back when it isn't installed|bash zsh|SHELL=/usr/bin/fish|zsh
_HI_SHELL_PREFERENCE decides|bash zsh fish|SHELL=/bin/zsh _HI_SHELL_PREFERENCE=bash|bash
# the pre-login-shell behaviour, for anyone who liked it
_HI_SHELL_PREFERENCE decides (full list)|bash zsh fish|SHELL=/bin/bash _HI_SHELL_PREFERENCE="fish zsh bash"|fish
# load.sh only runs where bash exists, so bash is the floor no matter what
Floors at bash|bash|SHELL=/usr/bin/fish _HI_SHELL_PREFERENCE="fish zsh"|bash
# The default tail is $_HI_SHELL_TREE, which carries the bash-less tiers
# (dash, ash, sh) after bash - they are hi.sh's ladder's business, not this
# file's, and _hi_session_shell's allow-list `case` is what keeps them out. A
# tree walked without that filter would answer "dash" here.
A bash-less tier is never the session shell (dash)|bash dash zsh|SHELL=/bin/dash|zsh
EOF

  _hi_h2 "Testing: this checkout"
  _hi_check "Still intact after every clean_all above" test_this_checkout_was_never_touched

  _hi_suite_end "load.sh"
}

run_load_tests
