#!/usr/bin/env bash
# Unit tests for load.sh, the target-side half of hi: the session rc directory
# it writes, the shell handoff, and the cleanup that removes it - and, only for
# a disposable tree, say-hi itself. Sourced with _HI_LOAD_NO_INIT=1 for the
# functions alone, with _HI_ROOT reassigned into the scratch dir.
#
# SAFETY: clean_all ends in `rm -rf "$_HI_CLEANUP"`, so no case calls it
# directly - every call goes through _hi_clean_all, which shadows $_HI_ROOT
# and $_HI_CLEANUP both. The real thing with the real paths would delete this
# checkout; the canary case at the end proves none did.
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

function _hi_clean_all() {
  local _HI_ROOT="${1:-$_HI_WORKDIR/unused-root}" _HI_CLEANUP="${2:-}"
  clean_all
}

function test_clean_all_keeps_permanent_install() {
  local root="$_HI_WORKDIR/permanent"
  mkdir -p "$root"
  printf 'colors\n' >"$root/keepme"
  _hi_clean_all "$root"
  [ -f "$root/keepme" ]
}

function test_clean_all_removes_disposable_copy() {
  local root="$_HI_WORKDIR/disposable"
  mkdir -p "$root"
  printf 'copied\n' >"$root/keepme"
  _hi_clean_all "$root" "$root"
  [ ! -e "$root" ]
}

# clean_all removes the whole $_HI_CLEANUP tree, not just $_HI_ROOT under
# it - a sibling file that landed directly under $_HI_HOME (the ssh arm's
# $_HI_SESSION_RC_DIR before it was nested under $_HI_CLEANUP, or anything
# else that might one day) goes with it, not just say-hi/ itself.
function test_clean_all_removes_the_whole_cleanup_tree_not_just_root() {
  local cleanup="$_HI_WORKDIR/wholetree" root="$_HI_WORKDIR/wholetree/say-hi"
  mkdir -p "$root"
  printf 'sibling\n' >"$cleanup/sibling-file"
  _hi_clean_all "$root" "$cleanup"
  [ ! -e "$cleanup" ]
}

function test_clean_all_succeeds_with_nothing_to_do() {
  _hi_clean_all "$_HI_WORKDIR/never-created"
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
# reason hi never writes to a target's rc files, so it is pinned rather than
# left to the e2e suites.
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
    # the target's own rc first, hi's on top
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

# With $_HI_CLEANUP set (the ephemeral shape), the rc directory nests
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
# unaffected, and the case this suite already had before the whole-tree
# cleanup above was added.
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

# _hi_fishquote's contract is "one fish word, byte-identical after fish
# unquotes it" - proven through a real fish, the same way hi_helpers proves
# _hi_shquote through a real sh. Backslash and single quote are fish's only
# two escapes, so they are the round trip that matters.
function _hi_fishquote_roundtrip() {
  local q out
  _hi_fishquote q "$1"
  out="$(fish -c "printf %s $q" </dev/null)"
  [ "$out" = "$1" ]
}

function test_fishquote_roundtrips_the_hard_cases() {
  _hi_fishquote_roundtrip "plain" &&
    _hi_fishquote_roundtrip "with space" &&
    _hi_fishquote_roundtrip "don't" &&
    _hi_fishquote_roundtrip 'back\slash' &&
    _hi_fishquote_roundtrip "a\\'mix\\\\of'both"
}

# the sh-dialect session rc shape bash and zsh share: the target's own rc
# first, this run's verdicts, then hi's rc - in that order
function test_session_sh_rc_writes_the_three_layers() {
  local out="$_HI_WORKDIR/session.rc" sh_vars=$'_HI_TARGET=probe\n'
  _hi_session_sh_rc .proberc "/some tree/rc file.sh" "$out" || return 1
  diff "$out" - <<'EOF' || return 1
[ -r "$HOME/.proberc" ] && . "$HOME/.proberc"
_HI_TARGET=probe
. /some\ tree/rc\ file.sh
EOF
  return 0
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

  _hi_h2 "Testing: clean_all"
  _hi_check "Keeps \$_HI_ROOT when _HI_CLEANUP is unset" test_clean_all_keeps_permanent_install
  _hi_check "Removes \$_HI_ROOT when _HI_CLEANUP is set" test_clean_all_removes_disposable_copy
  _hi_check "Removes the whole \$_HI_CLEANUP tree, not just \$_HI_ROOT" test_clean_all_removes_the_whole_cleanup_tree_not_just_root
  _hi_check "Succeeds with nothing to clean" test_clean_all_succeeds_with_nothing_to_do

  _hi_h2 "Testing: profile restoration"
  _hi_check "Sourcing restores the profile chain" test_source_restores_profile
  _hi_check "_HI_LOAD_NO_INIT=1 skips it" test_no_init_guard_skips_profile
  _hi_check "the tree is never put on PATH" test_tree_is_never_put_on_path
  _hi_check "the session rc dir carries every shell (HI.46)" test_session_rc_setup_writes_every_shell_and_exports_the_pointers
  _hi_check "the session shell reads hi's rc, not \$HOME's" test_session_shell_cmd_points_each_shell_at_his_rc
  _hi_check "the rc dir nests under \$_HI_CLEANUP when set" test_session_rc_setup_nests_under_cleanup_when_set
  _hi_check "...and stands alone without one" test_session_rc_setup_stands_alone_without_cleanup
  _hi_check_requires fish "_hi_fishquote round-trips through a real fish" test_fishquote_roundtrips_the_hard_cases
  _hi_check "_hi_session_sh_rc writes the three layers in order" test_session_sh_rc_writes_the_three_layers

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
