#!/usr/bin/env bash
# Unit tests for the per-shell scratch history feature: common/history.sh (the
# bash/zsh mktemp'd, exit-cleaned directory), common/config.fish's own copy for
# fish, and the _HI_DISABLE_HISTORY toggle.
#
# Built on tests/common/rc_test.sh's _hi_rc_shell pattern: a fresh shell under
# `env -i`, HOME and _HI_CONFIG_DIR pointed into the workdir so nothing local
# leaks in. rc_test.sh used to carry a zsh HISTFILE row of its own, proving hi
# shipped no history preference at all; now that it does (on by default), that
# coverage lives here instead.
#
# GLOSSARY: HI.30 + HI.34. The single-quoted scripts are expanded by the
# *child* shell, which is the whole point (SC2016).
# shellcheck disable=SC2329,SC2016
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# run <shell> -c <script> in the controlled environment; mirrors rc_test.sh's
# _hi_rc_shell, kept local rather than shared per this suite's own precedent
# (notify_test.sh's _hi_notify, osc52_test.sh's equivalent).
function _hi_history_shell() {
  local term="$1" shell="$2" script="$3"
  shift 3
  env -i HOME="$_HI_WORKDIR" TERM="$term" PATH="$PATH" \
    _HI_HOME="$_HI_HOME" _HI_CONFIG_DIR="$_HI_WORKDIR/cfg" "$@" \
    "$shell" -c "$script" </dev/null
}

# --- bash/zsh: HISTFILE and its directory --------------------------------

# the directory check has to happen *inside* the child, before its own exit
# trap removes it - by the time a $(...) capture returns, that shell has
# already exited and cleaned up after itself.
function test_bash_default_histfile_under_a_fresh_dir() {
  local out
  out="$(_hi_history_shell xterm-256color bash \
    'source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null
     [ -n "$HISTFILE" ] && [ -d "${HISTFILE%/*}" ] && echo yes || echo no')"
  [ "$out" = yes ]
}

function test_zsh_default_histfile_under_a_fresh_dir() {
  local out
  out="$(_hi_history_shell xterm-256color zsh \
    'source "$_HI_HOME/say-hi/common/zsh.zsh" 2>/dev/null
     [ -n "$HISTFILE" ] && [ -d "${HISTFILE%/*}" ] && echo yes || echo no')"
  [ "$out" = yes ]
}

function test_bash_history_disabled_leaves_histfile_unset() {
  local out
  out="$(_HI_DISABLE_HISTORY=1 _hi_history_shell xterm-256color bash \
    'export _HI_DISABLE_HISTORY=1; source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; printf %s "${HISTFILE:-}"')"
  [ -z "$out" ]
}

function test_zsh_history_disabled_leaves_histfile_unset() {
  local out
  out="$(_HI_DISABLE_HISTORY=1 _hi_history_shell xterm-256color zsh \
    'export _HI_DISABLE_HISTORY=1; source "$_HI_HOME/say-hi/common/zsh.zsh" 2>/dev/null; printf %s "${HISTFILE:-}"')"
  [ -z "$out" ]
}

# the directory a session printed has to be gone once that session's shell
# process exits - the whole point of "scratch"
function test_bash_tmpdir_removed_after_shell_exits() {
  local dir
  dir="$(_hi_history_shell xterm-256color bash \
    'source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; printf %s "$_HI_TMPDIR"')"
  [ -n "$dir" ] && [ ! -d "$dir" ]
}

function test_zsh_tmpdir_removed_after_shell_exits() {
  local dir
  dir="$(_hi_history_shell xterm-256color zsh \
    'source "$_HI_HOME/say-hi/common/zsh.zsh" 2>/dev/null; printf %s "$_HI_TMPDIR"')"
  [ -n "$dir" ] && [ ! -d "$dir" ]
}

# your own file (sourced at the end of hi's, per CONFIGURATION.md) still wins,
# the same guarantee every other per-shell override file makes
function test_zsh_user_histfile_overrides_the_default() {
  local out
  printf 'HISTFILE=/tmp/hi.sentinel\n' >"$_HI_WORKDIR/cfg/zsh.zsh"
  out="$(_hi_history_shell xterm-256color zsh \
    'source "$_HI_HOME/say-hi/common/zsh.zsh" 2>/dev/null; printf %s "$HISTFILE"')"
  rm -f "$_HI_WORKDIR/cfg/zsh.zsh"
  [ "$out" = /tmp/hi.sentinel ]
}

# --- fish: the postexec log, since it has no arbitrary history path -------
#
# fish_postexec is emitted by the interactive reader loop, which `fish -c`
# never runs (confirmed: a --on-event fish_postexec handler never fires under
# `fish -c`, `-i -c` included) - there is no scriptable way to exercise it
# firing, so this suite tests the structural half instead: the handler exists
# exactly when the toggle says it should, on the same precedent as the marks
# feature's own fish coverage (registration, not the escape actually landing).
function test_fish_history_postexec_defined_by_default() {
  local out
  out="$(_hi_history_shell xterm-256color fish \
    'source $_HI_HOME/say-hi/common/config.fish 2>/dev/null
     functions -q __hi_history_postexec; and echo yes; or echo no')"
  [ "$out" = yes ]
}

function test_fish_history_disabled_defines_no_postexec() {
  local out
  out="$(_HI_DISABLE_HISTORY=1 _hi_history_shell xterm-256color fish \
    'set -gx _HI_DISABLE_HISTORY 1; source $_HI_HOME/say-hi/common/config.fish 2>/dev/null
     functions -q __hi_history_postexec; and echo yes; or echo no')"
  [ "$out" = no ]
}

function test_fish_history_disabled_never_makes_a_tmpdir() {
  local out
  out="$(_HI_DISABLE_HISTORY=1 _hi_history_shell xterm-256color fish \
    'set -gx _HI_DISABLE_HISTORY 1; source $_HI_HOME/say-hi/common/config.fish 2>/dev/null
     set -q _HI_TMPDIR; and echo yes; or echo no')"
  [ "$out" = no ]
}

function test_fish_tmpdir_removed_after_shell_exits() {
  local dir
  dir="$(_hi_history_shell xterm-256color fish \
    'source $_HI_HOME/say-hi/common/config.fish 2>/dev/null; printf %s $_HI_TMPDIR')"
  [ -n "$dir" ] && [ ! -d "$dir" ]
}

# --- the toggle -------------------------------------------------------------

function _hi_toggle_in_core_list() {
  case " ${_HI_TOGGLES[*]} " in
  *" _HI_DISABLE_HISTORY "*) return 0 ;;
  esac
  return 1
}

# config.fish keeps its own copy of the toggle list (fish can't read core.sh's
# array); a toggle added to one and not the other is the exact drift this
# catches.
function _hi_toggle_in_fish_list() {
  grep -q '_HI_DISABLE_HISTORY' "$_HI_FISH_CONFIG"
}

# the _HI_TRIM_TABLE row: toggle, then the tree file it takes off the wire.
# tests/hi/payload_test.sh owns the trimming behavior itself; this is the
# claim that hi.sh knows the file at all, which is what a rename would break.
function _hi_payload_trims_the_history_file() {
  grep -q '"_HI_DISABLE_HISTORY|say-hi/common/history.sh|' "$_HI_LAUNCHER"
}

function run_history_test() {
  _hi_h1 "Testing per-shell history capture (common/history.sh, _HI_DISABLE_HISTORY)"
  _hi_workdir history
  mkdir -p "$_HI_WORKDIR/cfg"
  _hi_suite_begin

  _hi_h2 "bash and zsh: HISTFILE and its scratch directory"
  _hi_check "[bash] HISTFILE defaults under a fresh dir" test_bash_default_histfile_under_a_fresh_dir
  _hi_check_requires zsh "[zsh] HISTFILE defaults under a fresh dir" test_zsh_default_histfile_under_a_fresh_dir
  _hi_check "[bash] _HI_DISABLE_HISTORY=1 leaves HISTFILE unset" test_bash_history_disabled_leaves_histfile_unset
  _hi_check_requires zsh "[zsh] _HI_DISABLE_HISTORY=1 leaves HISTFILE unset" test_zsh_history_disabled_leaves_histfile_unset
  _hi_check "[bash] the scratch dir is gone after the shell exits" test_bash_tmpdir_removed_after_shell_exits
  _hi_check_requires zsh "[zsh] the scratch dir is gone after the shell exits" test_zsh_tmpdir_removed_after_shell_exits
  _hi_check_requires zsh "[zsh] your own HISTFILE overrides the default" test_zsh_user_histfile_overrides_the_default

  _hi_h2 "fish: the postexec log"
  _hi_check_requires fish "the postexec handler is defined by default" test_fish_history_postexec_defined_by_default
  _hi_check_requires fish "_HI_DISABLE_HISTORY=1 defines no postexec handler" test_fish_history_disabled_defines_no_postexec
  _hi_check_requires fish "_HI_DISABLE_HISTORY=1 makes no scratch dir" test_fish_history_disabled_never_makes_a_tmpdir
  _hi_check_requires fish "the scratch dir is gone after the shell exits" test_fish_tmpdir_removed_after_shell_exits

  _hi_h2 "the toggle"
  _hi_check "_HI_DISABLE_HISTORY in core.sh's _HI_TOGGLES" _hi_toggle_in_core_list
  _hi_check "_HI_DISABLE_HISTORY in config.fish's copy" _hi_toggle_in_fish_list
  _hi_check "hi.sh trims common/history.sh when it is off" _hi_payload_trims_the_history_file

  _hi_suite_end "history"
}

run_history_test
