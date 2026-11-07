#!/usr/bin/env bash
# scripts/configure.sh's one question, and hi --configure handing the file to
# the editor, each driven through a pty.
# A part of configure_test.sh, a suite of its own so the Windows and coverage
# shards split them.
# The preamble's source line is configure_test.sh's - it sources the harness, and
# holds the helpers the parts share (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# SC2015: `A && B || _hi_why` is one assertion, its reporter run when either
# half is false.
# shellcheck disable=SC2329,SC2015
set -euo pipefail

_HI_CONFIGURE_PART=pty
# shellcheck source=./configure_test.sh
source "${BASH_SOURCE[0]%/*}/configure_test.sh"

# Enter under --configure keeps the current settings: nothing seeded, and the
# run carries on rather than failing
function test_preset_question_enter_keeps_current() {
  local got
  _hi_cfg_pty pre_enter '\n' '' config_pick_preset "" || _hi_why || return 1
  got="$(_hi_cfg_rc pre_enter)"
  { [ "$got" = 0 ] && _hi_cfg_has pre_enter "Enter keeps your settings" && ! _hi_cfg_has pre_enter "starting from the"; } || _hi_why got
}

# ...and on a first install it takes the default it names
function test_preset_question_enter_takes_the_default() {
  local got
  _hi_cfg_pty pre_default '\n' '' config_pick_preset balanced || _hi_why || return 1
  got="$(_hi_cfg_lines pre_default)"
  _hi_cfg_has pre_default "starting from the 'balanced' preset" &&
    [[ "$got" == *"export _HI_DISABLE_LOCAL=1"* ]] || _hi_why got
}

# a typo gets the full name list back and the run carries on unseeded - the
# question is an offer, not a gate
function test_preset_question_refuses_a_stranger_and_carries_on() {
  local got
  _hi_cfg_pty pre_unknown 'zzz\n' '' config_pick_preset "" || _hi_why || return 1
  got="$(_hi_cfg_rc pre_unknown)"
  { [ "$got" = 0 ] && _hi_cfg_has pre_unknown "no such preset: zzz"; } || _hi_why got
}

# a shorthand letter resolves and seeds the run
function test_preset_shorthand_seeds_the_run() {
  local got
  _hi_cfg_pty pre_walk 'b\n' '' config_pick_preset "" || _hi_why || return 1
  _hi_cfg_has pre_walk "starting from the 'balanced' preset" || _hi_why || return 1
  got="$(_hi_cfg_lines pre_walk)"
  [[ "$got" == *"export _HI_PACKAGES_GROUPS='core,deprecated'"* ]] || _hi_why got
}

# The whole run: m picks minimal, and the one write is exactly the preset's
# lines, every other setting commented
function test_full_run_writes_the_preset() {
  _hi_cfg_pty full_walk 'm\n' '' run_configure "" || _hi_why || return 1
  local block
  block="$(grep -F "$_HI_MARKER" "$_HI_WORKDIR/full_walk/overlay/settings.sh")"
  _hi_cfg_has full_walk "starting from the 'minimal' preset" &&
    [[ "$block" == *"export _HI_DISABLE_HEADER=1"* && "$block" == *"export _HI_DISABLE_LOCAL=1"* &&
      "$block" == *"export _HI_PLUGINS_OFF='vim,nvim,nano,emacs,hx,kak,micro'"* &&
      "$block" == *"# export _HI_MAX_WIDTH=80"* ]] || _hi_why block
}

# EOF at the question keeps what there is and still writes the block
function test_eof_keeps_the_file() {
  _hi_cfg_pty pre_eof '\004' 'export _HI_DISABLE_GIT_STATUS=1' run_configure "" || _hi_why || return 1
  local block
  block="$(grep -F "$_HI_MARKER" "$_HI_WORKDIR/pre_eof/overlay/settings.sh")"
  [[ "$block" == *"export _HI_DISABLE_GIT_STATUS=1"* ]] || _hi_why block
}

# hi --configure at a terminal ends in the editor, on settings.sh: $VISUAL
# here is a stub that writes down what it was handed
function test_configure_opens_the_editor() {
  local dir="$_HI_WORKDIR/editor" out="$_HI_WORKDIR/editor.cfg.out" got
  mkdir -p "$dir/xdg/say-hi"
  # shellcheck disable=SC2016 # the stub's own $1, for it to expand
  printf '#!/bin/sh\nprintf "%%s\\n" "$1" >"%s/opened"\n' "$dir" >"$dir/ed"
  chmod +x "$dir/ed"
  : >"$out"
  printf 'm\n' |
    VISUAL="$dir/ed" _HI_CONFIG_DIR="$dir/xdg/say-hi" "${_HI_PTY_FORCED[@]}" bash "$_HI_INSTALL" --configure >"$out" 2>&1 &
  _hi_wait_quiet "$!" "${_HI_CASE_TIMEOUT:-60}" "$out" editor
  [ "$_HI_WAIT_EXIT" != 124 ] || _hi_because "hi --configure never finished" || return 1
  got="$(cat "$dir/opened" 2>/dev/null)"
  [ "$got" = "$dir/xdg/say-hi/settings.sh" ] && grep -qF "export _HI_DISABLE_LOCAL=1" "$got" ||
    _hi_why got "$(_hi_strip_ansi "$(<"$out")")"
}

function run_configure_pty_tests() {
  _hi_configure_begin

  _hi_h1 "Testing scripts/configure.sh's reusable logic (pty)"

  # Every pty case fans out together: each drives its own child under its own
  # $_HI_WORKDIR/<label>, so nothing in this shell is shared.
  _hi_h2 "Testing: the preset question and the editor (pty)"
  _hi_par_begin "pty cases"
  _hi_par_check_capable pty "Preset question: Enter keeps current" test_preset_question_enter_keeps_current
  _hi_par_check_capable pty "Preset question: Enter takes a first install's default" test_preset_question_enter_takes_the_default
  _hi_par_check_capable pty "Preset question: a stranger is refused, run continues" test_preset_question_refuses_a_stranger_and_carries_on
  _hi_par_check_capable pty "Preset shorthand seeds the run" test_preset_shorthand_seeds_the_run
  _hi_par_check_capable pty "Full run: the preset, every other setting commented" test_full_run_writes_the_preset
  _hi_par_check_capable pty "EOF keeps the file" test_eof_keeps_the_file
  _hi_par_check_capable pty "hi --configure opens settings.sh in the editor" test_configure_opens_the_editor
  _hi_par_wait

  _hi_suite_end "configure.sh logic (pty)"
}

run_configure_pty_tests
