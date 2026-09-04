#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Unit tests for scripts/rc.sh - the code that owns the lines hi writes into a
# user's real shell rc files. Nothing here touches the tester's own rc files:
# rc.sh builds $_HI_RC_TABLE at source time from paths derived off $HOME, so
# every case runs in a child bash whose $HOME is a throwaway directory and
# re-sources core.sh + rc.sh there. The single-quoted child scripts are the
# *child's* to expand (SC2016).
# GLOSSARY: HI.34
# shellcheck disable=SC2329,SC2016
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# _hi_rc_in <home> <env NAME=VALUE...> -- <fn> [args...] - run one rc.sh
# function in a child bash rooted at <home>. The child re-derives every rc
# path from that $HOME; stdout is squelched (the functions narrate), stderr
# kept for a real failure.
function _hi_rc_in() {
  local home="$1"
  shift
  local -a envs=()
  while [ "${1:-}" != -- ]; do
    envs+=("$1")
    shift
  done
  shift
  mkdir -p "$home"
  env HOME="$home" ${envs[@]+"${envs[@]}"} bash -c '
    source "$_HI_HOME/say-hi/common/core.sh"
    source "$_HI_HOME/say-hi/scripts/lib.sh"
    source "$_HI_HOME/say-hi/scripts/rc.sh"
    "$@"' rc_probe "$@" >/dev/null
}

function test_config_shell_fresh_write() {
  local home="$_HI_WORKDIR/fresh"
  _hi_rc_in "$home" -- config_shell bashrc "$home/.bashrc" 'export A=1' '' 'source b' || return 1
  grep -qF 'export A=1' "$home/.bashrc" || return 1
  grep -qF 'source b' "$home/.bashrc" || return 1
  # two lines tagged; the empty argument contributed nothing
  [ "$(grep -cF "$_HI_MARKER" "$home/.bashrc")" = 2 ]
}

function test_config_shell_is_idempotent() {
  local home="$_HI_WORKDIR/idem" before
  _hi_rc_in "$home" -- config_shell bashrc "$home/.bashrc" 'export A=1' || return 1
  before="$(cat "$home/.bashrc")"
  _hi_rc_in "$home" -- config_shell bashrc "$home/.bashrc" 'export A=1' || return 1
  [ "$(cat "$home/.bashrc")" = "$before" ]
}

function test_config_shell_repairs_stale_lines() {
  local home="$_HI_WORKDIR/repair"
  _hi_rc_in "$home" -- config_shell bashrc "$home/.bashrc" 'export OLD=1' || return 1
  _hi_rc_in "$home" -- config_shell bashrc "$home/.bashrc" 'export NEW=1' || return 1
  grep -qF 'export NEW=1' "$home/.bashrc" || return 1
  ! grep -qF 'export OLD=1' "$home/.bashrc"
}

function test_config_shell_preserves_foreign_lines() {
  local home="$_HI_WORKDIR/foreign"
  mkdir -p "$home"
  printf 'echo mine\n' >"$home/.bashrc"
  _hi_rc_in "$home" -- config_shell bashrc "$home/.bashrc" 'export A=1' || return 1
  grep -qF 'echo mine' "$home/.bashrc" || return 1
  grep -qF 'export A=1' "$home/.bashrc"
}

# the backup is one-time and pre-hi: taken on the first write to a non-empty
# file, never overwritten by later rewrites
function test_config_shell_one_time_backup() {
  local home="$_HI_WORKDIR/backup"
  mkdir -p "$home"
  printf 'echo original\n' >"$home/.bashrc"
  _hi_rc_in "$home" -- config_shell bashrc "$home/.bashrc" 'export A=1' || return 1
  [ "$(cat "$home/.bashrc.hi-orig")" = "echo original" ] || return 1
  _hi_rc_in "$home" -- config_shell bashrc "$home/.bashrc" 'export B=2' || return 1
  [ "$(cat "$home/.bashrc.hi-orig")" = "echo original" ]
}

function test_config_shell_no_backup_of_an_empty_file() {
  local home="$_HI_WORKDIR/nobackup"
  mkdir -p "$home"
  : >"$home/.bashrc"
  _hi_rc_in "$home" -- config_shell bashrc "$home/.bashrc" 'export A=1' || return 1
  [ ! -e "$home/.bashrc.hi-orig" ]
}

function test_strip_marker_removes_only_hi_lines() {
  local home="$_HI_WORKDIR/strip"
  mkdir -p "$home"
  printf 'echo mine\n' >"$home/.bashrc"
  _hi_rc_in "$home" -- config_shell bashrc "$home/.bashrc" 'export A=1' || return 1
  _hi_rc_in "$home" -- strip_marker bashrc "$home/.bashrc" || return 1
  ! grep -qF "$_HI_MARKER" "$home/.bashrc" || return 1
  grep -qF 'echo mine' "$home/.bashrc"
}

function test_strip_marker_missing_file_is_fine() {
  local home="$_HI_WORKDIR/stripnone"
  _hi_rc_in "$home" -- strip_marker bashrc "$home/.bashrc" || return 1
  [ ! -e "$home/.bashrc" ]
}

function test_tmpdir_line_dialects() {
  # stdout is the answer here, so ask without _hi_rc_in's squelch
  local home="$_HI_WORKDIR/tmpdirline" fish sh
  mkdir -p "$home"
  fish="$(env HOME="$home" bash -c '
    source "$_HI_HOME/say-hi/common/core.sh"
    source "$_HI_HOME/say-hi/scripts/lib.sh"
    source "$_HI_HOME/say-hi/scripts/rc.sh"
    tmpdir_line fish /custom')"
  sh="$(env HOME="$home" bash -c '
    source "$_HI_HOME/say-hi/common/core.sh"
    source "$_HI_HOME/say-hi/scripts/lib.sh"
    source "$_HI_HOME/say-hi/scripts/rc.sh"
    tmpdir_line sh /custom')"
  [ "$fish" = 'set -gx _HI_HOME "/custom"' ] && [ "$sh" = 'export _HI_HOME="/custom"' ]
}

# the roster loop: every local shell's rc gets its marker block, in its own
# dialect, and bash gets its extra non-interactive return
function test_install_rc_lines_covers_the_roster() {
  local home="$_HI_WORKDIR/roster"
  mkdir -p "$home/.config/fish"
  _hi_rc_in "$home" -- install_rc_lines || return 1
  local f
  for f in .bashrc .zshrc .config/fish/config.fish; do
    grep -qF "$_HI_MARKER" "$home/$f" || return 1
    # sh spells it `export _HI_HOME="..."`, fish `set -gx _HI_HOME "..."`
    grep -qF '_HI_HOME' "$home/$f" || return 1
  done
  grep -qF '[[ $- != *i* ]] && return' "$home/.bashrc" || return 1
  ! grep -qF '[[ $- != *i* ]] && return' "$home/.zshrc" || return 1
  grep -qF 'if status is-interactive' "$home/.config/fish/config.fish" || return 1
  grep -qF 'set -gx _HI_HOME' "$home/.config/fish/config.fish"
}

function test_strip_rc_lines_restores_the_originals() {
  local home="$_HI_WORKDIR/inverse"
  mkdir -p "$home/.config/fish"
  printf 'echo bash-mine\n' >"$home/.bashrc"
  printf 'echo zsh-mine\n' >"$home/.zshrc"
  printf 'echo fish-mine\n' >"$home/.config/fish/config.fish"
  _hi_rc_in "$home" -- install_rc_lines || return 1
  _hi_rc_in "$home" -- strip_rc_lines || return 1
  [ "$(cat "$home/.bashrc")" = "echo bash-mine" ] &&
    [ "$(cat "$home/.zshrc")" = "echo zsh-mine" ] &&
    [ "$(cat "$home/.config/fish/config.fish")" = "echo fish-mine" ]
}

function test_check_one_config_verdicts() {
  local home="$_HI_WORKDIR/checkone"
  mkdir -p "$home"
  printf 'echo fine\n' >"$home/good.sh"
  printf 'if true; then\n' >"$home/bad.sh"
  _hi_rc_in "$home" -- check_one_config bash "$home/good.sh" bash -n || return 1
  ! _hi_rc_in "$home" -- check_one_config bash "$home/bad.sh" bash -n || return 1
  # a missing file and a missing checker are both silent skips, not failures
  _hi_rc_in "$home" -- check_one_config bash "$home/absent.sh" bash -n || return 1
  _hi_rc_in "$home" -- check_one_config x "$home/good.sh" no-such-tool-9x -n
}

function test_check_shell_configs_flags_a_broken_rc() {
  local home="$_HI_WORKDIR/checkall"
  mkdir -p "$home"
  printf 'echo fine\n' >"$home/.bashrc"
  _hi_rc_in "$home" -- check_shell_configs || return 1
  printf 'if true; then\n' >"$home/.bashrc"
  ! _hi_rc_in "$home" -- check_shell_configs
}

# --yes waves a broken config through; a non-interactive run without it aborts
# (install.sh rewrites the very files that failed to parse)
function test_config_validate_shells_gate() {
  local home="$_HI_WORKDIR/gate"
  mkdir -p "$home"
  printf 'if true; then\n' >"$home/.bashrc"
  _hi_rc_in "$home" _HI_ASSUME_YES=1 -- config_validate_shells || return 1
  ! _hi_rc_in "$home" _HI_ASSUME_YES=0 -- config_validate_shells </dev/null 2>/dev/null
}

function run_rc_lines_test() {
  _hi_h1 "Testing scripts/rc.sh (the lines hi owns in a user's rc files)"
  _hi_workdir rc_lines
  _hi_suite_begin

  _hi_h2 "Testing: config_shell"
  _hi_check "Fresh write tags every line" test_config_shell_fresh_write
  _hi_check "Second run changes nothing" test_config_shell_is_idempotent
  _hi_check "Stale lines are repaired, not appended" test_config_shell_repairs_stale_lines
  _hi_check "Foreign lines survive" test_config_shell_preserves_foreign_lines
  _hi_check "One-time backup stays the pre-hi original" test_config_shell_one_time_backup
  _hi_check "No backup of an empty file" test_config_shell_no_backup_of_an_empty_file

  _hi_h2 "Testing: strip_marker"
  _hi_check "Removes only hi's lines" test_strip_marker_removes_only_hi_lines
  _hi_check "A missing file is fine" test_strip_marker_missing_file_is_fine

  _hi_h2 "Testing: tmpdir_line"
  _hi_check "Each dialect's _HI_HOME line" test_tmpdir_line_dialects

  _hi_h2 "Testing: install_rc_lines / strip_rc_lines"
  _hi_check "Install covers the local roster, per dialect" test_install_rc_lines_covers_the_roster
  _hi_check "Strip restores the originals byte for byte" test_strip_rc_lines_restores_the_originals

  _hi_h2 "Testing: the syntax gate"
  _hi_check "check_one_config's four verdicts" test_check_one_config_verdicts
  _hi_check "check_shell_configs flags a broken rc" test_check_shell_configs_flags_a_broken_rc
  _hi_check "config_validate_shells: --yes vs non-interactive" test_config_validate_shells_gate

  _hi_suite_end "rc.sh"
}

run_rc_lines_test
