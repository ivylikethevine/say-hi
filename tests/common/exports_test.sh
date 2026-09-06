#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Unit tests for what a process started from an interactive hi shell inherits:
# core.sh's _HI_CHILD_ENV roster and _hi_unexport, the fish mirror of both in
# common/config.fish, and the session rc lines load.sh writes so that a nested
# shell on a target reads the client's verdicts from a file rather than from
# its environment. The contract under test is that `env | grep ^_HI_` in a
# child of a hi shell shows the roster and nothing else - the ~60 names
# paths.sh has to `export` (its four-shell dialect has no other assignment)
# stay shell variables and stop at the shell.
#
# GLOSSARY: HI.47 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# _hi_child_env <shell> <rc> - `env | grep ^_HI_` in a child of <shell> after
# it sourced <rc>, names only, sorted. $HOME and the overlay point at the
# workdir so nothing of the user's is read.
function _hi_child_env() {
  HOME="$_HI_WORKDIR/home" env -u _HI_CLEANUP "$1" -c "source $2; env" 2>/dev/null |
    grep -o '^_HI_[A-Za-z0-9_]*' | sort
}

# Every name a child sees is in the roster; the roster is the ceiling, not a
# target, since an unset knob (_HI_TARGETS_TTL etc.) is rightly absent.
function _hi_env_within_roster() {
  local shell="$1" rc="$2" n stray=""
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    case " ${_HI_CHILD_ENV[*]} " in
    *" $n "*) ;;
    *) stray="$stray $n" ;;
    esac
  done < <(_hi_child_env "$shell" "$rc")
  [ -z "$stray" ] || {
    _hi_cecho " | $shell child inherits:$stray" "$RED"
    return 1
  }
}

function test_bash_child_sees_only_the_roster() {
  _hi_env_within_roster bash "$_HI_BASHRC"
}

function test_zsh_child_sees_only_the_roster() {
  _hi_env_within_roster zsh "$_HI_ZSHRC"
}

function test_fish_child_sees_only_the_roster() {
  _hi_env_within_roster fish "$_HI_FISH_CONFIG"
}

# The value has to survive the flip: `now` expands $_HI_HUMAN_SHORT_DATE when
# it is typed, and the prompt reads the colour memos every render. One body
# for all three shells - the shell and its rc are the only difference - run
# through _hi_check_eq so a failure prints want and got alike.
function _hi_shell_keeps_values() { # <shell> <rc>
  HOME="$_HI_WORKDIR/home" "$1" -c "source $2; printf '%s|%s' \"\$_HI_ROOT\" \"\$_HI_HUMAN_SHORT_DATE\"" 2>/dev/null
}

# The roster is what the child gets, so a name in it must still be exported
# after the flip - the loop's exception list, tested from the other side.
function test_bash_child_still_sees_the_roster() {
  local out
  out="$(_hi_child_env bash "$_HI_BASHRC")"
  if ! printf '%s\n' "$out" | grep -qx _HI_HOME || ! printf '%s\n' "$out" | grep -qx _HI_CONFIG_DIR; then
    _hi_cecho " | roster names missing from: $(printf '%s' "$out" | tr '\n' ' ')" "$RED"
    return 1
  fi
}

# A session value fish holds as a plain global reaches the bash it shells
# out to for the header and the colours, and only that bash: __hi_bash's
# function-scoped export must not leak the name into the environment after.
function test_fish_bridge_passes_session_values_without_exporting_them() {
  local out
  out="$(HOME="$_HI_WORKDIR/home" fish -c "set -g _HI_LOCAL_USER bridged; source $_HI_FISH_CONFIG; __hi_bash 'printf %s \"\$_HI_LOCAL_USER\"'; printf '|'; env | grep -c '^_HI_LOCAL_USER=' || true" 2>/dev/null)"
  [ "$out" = "bridged|0" ] || {
    _hi_cecho " | got: $out (want bridged|0)" "$RED"
    return 1
  }
}

# config.fish carries hand-written mirrors of both rosters; this is their
# whole-list drift guard, on paths_test.sh's toggle-mirror precedent.
function _hi_fish_list() {
  awk -v name="$1" '$0 ~ "^set -g " name " " {p=1} p{print; if ($0 !~ /\\$/) exit}' \
    "$_HI_ROOT/common/config.fish" | grep -oE '_HI_[A-Z0-9_]+' | grep -vx "$1"
}

function test_fish_child_env_mirror_matches_core() {
  local fish_list core_list
  fish_list="$(_hi_fish_list _HI_CHILD_ENV)"
  core_list="$(printf '%s\n' "${_HI_CHILD_ENV[@]}")"
  [ "$fish_list" = "$core_list" ] || {
    _hi_cecho " | config.fish: $(printf '%s' "$fish_list" | tr '\n' ' ')" "$RED"
    _hi_cecho " | core.sh:     ${_HI_CHILD_ENV[*]}" "$RED"
    return 1
  }
}

function test_fish_session_vars_mirror_matches_core() {
  local fish_list core_list
  fish_list="$(_hi_fish_list _HI_SESSION_VARS)"
  core_list="$(printf '%s\n' "${_HI_SESSION_VARS[@]}")"
  [ "$fish_list" = "$core_list" ] || {
    _hi_cecho " | config.fish: $(printf '%s' "$fish_list" | tr '\n' ' ')" "$RED"
    _hi_cecho " | core.sh:     ${_HI_SESSION_VARS[*]}" "$RED"
    return 1
  }
}

# hi.sh's _hi_session_env is the list of what the client exports into a
# session; core.sh's _HI_SESSION_VARS is what load.sh re-homes into the
# session rc. A name added to one and not the other is a value a nested shell
# silently loses, so the two are pinned. NO_COLOR is not hi's name and is
# left where it is.
function test_session_env_names_match_the_roster() {
  local hi_list core_list
  hi_list="$(awk '/^function _hi_session_env\(\)/{p=1} p{print} p && /^}/{exit}' "$_HI_ROOT/hi.sh" |
    grep -oE "printf '_HI_[A-Z0-9_]+" | sed "s/printf '//")"
  core_list="$(printf '%s\n' "${_HI_SESSION_VARS[@]}")"
  [ "$hi_list" = "$core_list" ] || {
    _hi_cecho " | hi.sh:   $(printf '%s' "$hi_list" | tr '\n' ' ')" "$RED"
    _hi_cecho " | core.sh: ${_HI_SESSION_VARS[*]}" "$RED"
    return 1
  }
}

# The two workstation names are exactly the ones the roster must never grow.
function test_roster_never_names_the_workstation() {
  case " ${_HI_CHILD_ENV[*]} " in
  *" _HI_LOCAL_USER "* | *" _HI_LOCAL_HOSTNAME "*)
    _hi_cecho " | _HI_CHILD_ENV carries a workstation name" "$RED"
    return 1
    ;;
  esac
}

# Every _HI_* name targets.sh reads off its environment is in the roster, or
# is one it re-derives to the same answer paths.sh gives (_HI_SSH_CONFIG:
# $HOME/.ssh/config both ways). A knob added to targets.sh and not here would
# work from a script and silently take its default from a completion.
function test_targets_env_reads_are_in_the_roster() {
  local n stray=""
  while IFS= read -r n; do
    case " ${_HI_CHILD_ENV[*]} _HI_SSH_CONFIG " in
    *" $n "*) ;;
    *) stray="$stray $n" ;;
    esac
  done < <(grep -oE '\$\{_HI_[A-Z0-9_]+:-' "$_HI_ROOT/common/targets.sh" | grep -oE '_HI_[A-Z0-9_]+' | sort -u)
  [ -z "$stray" ] || {
    _hi_cecho " | targets.sh reads from the environment:$stray" "$RED"
    return 1
  }
}

# load.sh's session rc carries every set session value, in each dialect, and
# the quoting round-trips through the shell that will read it. The tag has
# a quote and a space and the hostname a backslash on purpose.
_HI_RC_TAG="it's a tag"
_HI_RC_HOST='box\1'

function _hi_session_rc_dir() {
  _HI_TARGET_COLOR=red _HI_TARGET_TAG="$_HI_RC_TAG" \
    _HI_LOCAL_USER=ivy _HI_LOCAL_HOSTNAME="$_HI_RC_HOST" _HI_RELEASE=1.2.3 _HI_ASCII=0 \
    _HI_LOAD_NO_INIT=1 bash -c '
    source "$_HI_HOME/say-hi/load.sh"
    _HI_SESSION_RC_DIR=""
    _hi_session_rc_setup || exit 1
    printf "%s\n" "$_HI_SESSION_RC_DIR"
  '
}

function _hi_rc_round_trips() { # <shell> <file> <assignment grep>
  local dir out
  dir="$(_hi_session_rc_dir)" || return 1
  grep "$3" "$dir/$2" >"$_HI_WORKDIR/vars.$1"
  out="$("$1" -c "source $_HI_WORKDIR/vars.$1; printf '%s|%s|%s|%s' \"\$_HI_TARGET_COLOR\" \"\$_HI_TARGET_TAG\" \"\$_HI_LOCAL_HOSTNAME\" \"\$_HI_ASCII\"" 2>&1)"
  rm -rf "$dir"
  [ "$out" = "red|$_HI_RC_TAG|$_HI_RC_HOST|0" ] || {
    _hi_cecho " | $1 read back: $out" "$RED"
    return 1
  }
}

function test_session_rc_round_trips_in_bash() {
  _hi_rc_round_trips bash bashrc '^_HI_'
}

function test_session_rc_round_trips_in_zsh() {
  _hi_rc_round_trips zsh .zshrc '^_HI_'
}

function test_session_rc_round_trips_in_fish() {
  _hi_rc_round_trips fish fish.config '^set -g _HI_'
}

# The lines sit between the target's own rc and hi's, so the host's config is
# underneath and hi's rc reads them - and an unset one is not written at all.
function test_session_rc_places_and_skips() {
  local dir
  dir="$(_hi_session_rc_dir)" || return 1
  local first last
  first="$(head -n1 "$dir/bashrc")"
  last="$(tail -n1 "$dir/bashrc")"
  case "$first" in *'.bashrc'*) ;; *)
    _hi_cecho " | first line is not the target's rc: $first" "$RED"
    rm -rf "$dir"
    return 1
    ;;
  esac
  case "$last" in *"$_HI_BASHRC"*) ;; *)
    _hi_cecho " | last line is not hi's rc: $last" "$RED"
    rm -rf "$dir"
    return 1
    ;;
  esac
  if grep -q '^_HI_TARGET_TAG=' "$dir/bashrc" && ! grep -q '^_HI_NOT_A_VAR=' "$dir/bashrc"; then
    rm -rf "$dir"
    return 0
  fi
  rm -rf "$dir"
  return 1
}

function run_exports_tests() {
  _hi_workdir exportstest
  mkdir -p "$_HI_WORKDIR/home"

  _hi_h1 "Testing what a child of a hi shell inherits (HI.47)"

  _hi_suite_begin

  _hi_h2 "Testing: the child environment is the roster"
  _hi_check "bash: a child sees only \$_HI_CHILD_ENV" test_bash_child_sees_only_the_roster
  _hi_check_requires zsh "zsh: a child sees only \$_HI_CHILD_ENV" test_zsh_child_sees_only_the_roster
  _hi_check_requires fish "fish: a child sees only \$_HI_CHILD_ENV" test_fish_child_sees_only_the_roster
  _hi_check "bash: the roster itself is still exported" test_bash_child_still_sees_the_roster
  _hi_check_eq "bash: the values stay as shell variables" "$_HI_ROOT|$_HI_HUMAN_SHORT_DATE" _hi_shell_keeps_values bash "$_HI_BASHRC"
  _hi_check_requires_eq zsh "zsh: the values stay as shell variables" "$_HI_ROOT|$_HI_HUMAN_SHORT_DATE" _hi_shell_keeps_values zsh "$_HI_ZSHRC"
  _hi_check_requires_eq fish "fish: the values stay as shell variables" "$_HI_ROOT|$_HI_HUMAN_SHORT_DATE" _hi_shell_keeps_values fish "$_HI_FISH_CONFIG"
  _hi_check_requires fish "fish: __hi_bash passes session values without exporting them" test_fish_bridge_passes_session_values_without_exporting_them

  _hi_h2 "Testing: the rosters cannot drift"
  _hi_check "config.fish's _HI_CHILD_ENV mirror matches core.sh" test_fish_child_env_mirror_matches_core
  _hi_check "config.fish's _HI_SESSION_VARS mirror matches core.sh" test_fish_session_vars_mirror_matches_core
  _hi_check "hi.sh's _hi_session_env names match _HI_SESSION_VARS" test_session_env_names_match_the_roster
  _hi_check "the roster never names the workstation" test_roster_never_names_the_workstation
  _hi_check "every env read in targets.sh is in the roster" test_targets_env_reads_are_in_the_roster

  _hi_h2 "Testing: load.sh re-homes the session values into the session rc"
  _hi_check "bash rc round-trips the values" test_session_rc_round_trips_in_bash
  _hi_check_requires zsh "zsh rc round-trips the values" test_session_rc_round_trips_in_zsh
  _hi_check_requires fish "fish rc round-trips the values" test_session_rc_round_trips_in_fish
  _hi_check "the lines sit between the target's rc and hi's; unset ones are skipped" test_session_rc_places_and_skips

  _hi_suite_end "exports"
}

run_exports_tests
