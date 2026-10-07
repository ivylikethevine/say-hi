#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# scripts/doctor.sh's plain report, run whole.
# A part of doctor_test.sh, a suite of its own so the Windows shards split them.
# The preamble's source line is doctor_test.sh's - it sources the harness, and
# holds the helpers the parts share (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329,SC2317
set -euo pipefail

_HI_DOCTOR_PART=report
# shellcheck source=./doctor_test.sh
source "${BASH_SOURCE[0]%/*}/doctor_test.sh"

function test_help_exits_zero() {
  "$_HI_DOCTOR" --help >/dev/null
}

# reached as `hi --doctor`, the usage line says so; run by hand it names the
# file
function test_help_names_what_was_typed() {
  [ "$(_HI_ARGV0="hi --doctor" "$_HI_DOCTOR" --help | head -1)" = "Usage: hi --doctor [--json] [--problems] [--use <backend>] [ssh-options] [target]" ] &&
    [ "$("$_HI_DOCTOR" --help | head -1)" = "Usage: doctor.sh [--json] [--problems] [--use <backend>] [ssh-options] [target]" ]
}

# a target never starts with a dash, so a dash word the parser does not know
# is an error rather than the target; --mux and --no-mux
# are the connect-time flags with nothing to report here, like --plain
function test_unknown_flag_is_refused_not_taken_as_the_target() {
  local out rc=0 home
  out="$("$_HI_DOCTOR" --bogus 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"unknown option --bogus"* ]] || return 1
  rc=0
  home="$(_hi_doctor_home)"
  out="$(PATH="$(_hi_doctor_shims):$(_hi_doctor_path)" HOME="$home" _HI_SSH_CONFIG=/nonexistent \
  _HI_CONFIG_DIR="$_HI_WORKDIR/nocfg" "$_HI_DOCTOR" --mux --no-mux)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" != *"Target: --"* ]]
}

function test_a_second_target_is_refused() {
  local out rc=0
  out="$("$_HI_DOCTOR" one two 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"one target at a time"* ]]
}

# an ssh option that takes a value takes the next word with it, so that word is
# never the target; a bare ssh flag takes nothing
function test_an_ssh_value_option_takes_its_word() {
  local out rc=0
  out="$("$_HI_DOCTOR" -p 2222 -J bastion one two 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"one target at a time (one and two)"* ]] || return 1
  rc=0
  out="$("$_HI_DOCTOR" -4 one -A two 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"one target at a time (one and two)"* ]]
}

# ...and one that ends the line with no value is refused, not read as a flag
function test_a_trailing_ssh_value_option_is_refused() {
  local out rc=0
  out="$("$_HI_DOCTOR" host -p 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"-p needs a value"* ]]
}

function test_use_equals_spelling_names_the_arm() {
  local out rc=0
  out="$("$_HI_DOCTOR" --use=frobnicate host 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--use"* ]] || return 1
  rc=0
  out="$("$_HI_DOCTOR" --use= host 2>&1)" || rc=$?
  [ "$rc" -eq 1 ]
}

# --use last on the line, with nothing after it, is the one arm the loop
# cannot answer from inside: it falls out still waiting for the name
function test_use_needs_a_backend_name() {
  local out rc=0
  out="$("$_HI_DOCTOR" --use 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--use needs a backend name"* ]]
}

# two --use naming different arms are refused, not resolved last-wins
function test_use_twice_naming_two_backends_is_refused() {
  local out rc=0
  out="$("$_HI_DOCTOR" --use docker --use podman host 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--use podman and --use docker both name a backend; pick one"* ]]
}

# --help anywhere on the line, not only first: after a flag, after a target
function test_help_is_read_anywhere_on_the_line() {
  local out want="Usage: doctor.sh [--json] [--problems] [--use <backend>] [ssh-options] [target]"
  out="$("$_HI_DOCTOR" --json --help)" && [ "${out%%$'\n'*}" = "$want" ] || return 1
  out="$("$_HI_DOCTOR" somehost --help)" && [ "${out%%$'\n'*}" = "$want" ]
}

# sections present and the exit code is the red-finding count (0 here -
# nothing is broken, only absent, and absent is not an error)
function test_full_report_runs_clean() {
  _hi_doctor_plain_report
  [ "$_HI_DOC_PLAIN_RC" -eq 0 ] &&
    [[ "$_HI_DOC_PLAIN_OUT" == *"The local tree"* && "$_HI_DOC_PLAIN_OUT" == *"Backends"* &&
      "$_HI_DOC_PLAIN_OUT" == *"Nothing looks broken"* ]]
}

# every section of the whole report is a boxed table, square on the page, and
# the warn rows it carries on the shims stay in their sections: no closing
# box repeats them (that box is --problems' alone)
function test_full_report_draws_tables_and_no_findings_box() {
  local out
  _hi_doctor_plain_report
  out="$(_hi_strip_ansi "$_HI_DOC_PLAIN_OUT")"
  _hi_table_is_rectangular "$out" || return 1
  # boxed, with no header row: the section heading says what the table is
  [[ "$out" == *"$_HI_BOX_V"* && "$out" != *"$_HI_BOX_V CHECK"* ]] || return 1
  [[ "$out" != *"Findings:"* && "$out" != *"$_HI_BOX_V FINDING"* ]]
}

# ...and it is the text report: --json's document is asked for, never what a
# bare run prints
function test_json_is_off_by_default() {
  _hi_doctor_plain_report
  [ "$_HI_DOC_PLAIN_RC" -eq 0 ] || return 1
  [[ "$_HI_DOC_PLAIN_OUT" != *'"rows"'* && "$_HI_DOC_PLAIN_OUT" == *"hi doctor"* ]]
}

# _hi_doctor_problems [args...] - `--problems` on the shims, output then exit
# status on the last line
function _hi_doctor_problems() {
  local rc=0
  _hi_doctor_run --problems "$@" || rc=$?
  printf 'rc=%s\n' "$rc"
}

# --problems is the findings box alone: no banner, no section, the same exit
# status - 1 with a bad row (the unanswered target's), 0 with only warnings
function test_problems_prints_only_the_findings() {
  local out
  out="$(_hi_strip_ansi "$(_hi_doctor_problems somehost)")"
  [[ "$out" == *"rc=1" && "$out" == *"Findings: 1 bad, "*"$_HI_BOX_V"* ]] || return 1
  [[ "$out" != *"hi doctor"* && "$out" != *"The local tree"* && "$out" != *RESULT* ]] || return 1
  out="$(_hi_strip_ansi "$(_hi_doctor_problems)")"
  [[ "$out" == *"rc=0" && "$out" == *"Findings: 0 bad, "* ]] || return 1
  [[ "$out" != *"The local tree"* && "$out" != *RESULT* && "$out" != *"Nothing looks broken"* ]]
}

function run_doctor_report_tests() {
  _hi_doctor_begin

  _hi_h1 "Testing scripts/doctor.sh (report)"

  _hi_h2 "Testing: the report"
  _hi_check "--help exits zero" test_help_exits_zero
  _hi_check "--help names what was typed" test_help_names_what_was_typed
  _hi_check "--help is read anywhere on the line" test_help_is_read_anywhere_on_the_line
  _hi_check "An unknown flag is refused, not the target" test_unknown_flag_is_refused_not_taken_as_the_target
  _hi_check "A second target is refused" test_a_second_target_is_refused
  _hi_check "An ssh option's value is not the target" test_an_ssh_value_option_takes_its_word
  _hi_check "A trailing ssh value option is refused" test_a_trailing_ssh_value_option_is_refused
  _hi_check "--use=<backend> is checked like --use" test_use_equals_spelling_names_the_arm
  _hi_check "A trailing --use is refused" test_use_needs_a_backend_name
  _hi_check "Two --use naming two backends are refused" test_use_twice_naming_two_backends_is_refused
  _hi_check "Full report runs clean on shims" test_full_report_runs_clean
  _hi_check "Sections are tables, and no findings box repeats them" test_full_report_draws_tables_and_no_findings_box
  _hi_check "--json is off by default" test_json_is_off_by_default
  _hi_check "--problems prints only the findings" test_problems_prints_only_the_findings

  _hi_suite_end "doctor.sh (report)"
}

run_doctor_report_tests
