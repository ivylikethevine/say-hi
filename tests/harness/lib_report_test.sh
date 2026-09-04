#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Unit tests for the tests/lib/ harness - what a suite counts and what it prints.
# tests/lib/case.sh and tests/lib/report.sh: the counters, the begin/end banners,
# the skip and failure ledgers test_runner.sh reads back, and the two things
# every line goes through - _hi_align and _hi_dump_log.
#
# The harness is the one code whose bugs would be invisible: a broken _hi_case
# under-counts failures and every suite still looks green.
#
# Anything that exits or installs a trap runs in a subshell so it can't take
# this suite down.
#
# GLOSSARY: HI.30 + HI.34.
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# runs "$@" with the counters sandboxed, so a case can call _hi_case/
# _hi_suite_begin freely without corrupting this suite's own tally
function _hi_sandboxed() {
  local saved_total="$_HI_TOTAL" saved_failed="$_HI_FAILED" rc=0
  "$@" || rc=$?
  _HI_TOTAL="$saved_total"
  _HI_FAILED="$saved_failed"
  return "$rc"
}

function _hi_true() { return 0; }
function _hi_false() { return 1; }

function test_case_counts_a_pass() {
  _hi_suite_begin
  _hi_case _hi_true
  [ "$_HI_TOTAL" -eq 1 ] && [ "$_HI_FAILED" -eq 0 ]
}

function test_case_counts_a_failure() {
  _hi_suite_begin
  _hi_case _hi_false
  [ "$_HI_TOTAL" -eq 1 ] && [ "$_HI_FAILED" -eq 1 ]
}

function test_case_keeps_running_after_a_failure() {
  _hi_suite_begin
  _hi_case _hi_false
  _hi_case _hi_true
  _hi_case _hi_false
  [ "$_HI_TOTAL" -eq 3 ] && [ "$_HI_FAILED" -eq 2 ]
}

function test_assert_passes_through_arguments() {
  local out
  out="$(_hi_strip_ansi "$(_hi_assert "with args" test 1 -eq 1)")"
  printf '%s\n' "$out" | grep -qE 'with args +OK$'
}

function test_assert_reports_ok_and_returns_zero() {
  local out
  out="$(_hi_strip_ansi "$(_hi_assert "some label" _hi_true)")"
  printf '%s\n' "$out" | grep -qE 'some label +OK$'
}

function test_assert_reports_failed_and_returns_nonzero() {
  local out rc=0
  # the capture stays on _hi_assert itself: wrapping it in _hi_strip_ansi would
  # report the stripper's exit status, which is 0 whatever _hi_assert returned
  out="$(_hi_assert "some label" _hi_false)" || rc=$?
  [ "$rc" -ne 0 ] && printf '%s\n' "$(_hi_strip_ansi "$out")" | grep -qE 'some label +FAILED$'
}

function test_check_counts_and_labels_in_one_call() {
  _hi_suite_begin
  _hi_check "a failing check" _hi_false >/dev/null
  [ "$_HI_TOTAL" -eq 1 ] && [ "$_HI_FAILED" -eq 1 ]
}

function test_suite_begin_zeroes_both_counters() {
  _HI_TOTAL=7
  _HI_FAILED=3
  _hi_suite_begin
  [ "$_HI_TOTAL" -eq 0 ] && [ "$_HI_FAILED" -eq 0 ]
}

function test_suite_end_exits_zero_when_nothing_failed() {
  (
    _HI_TOTAL=4
    _HI_FAILED=0
    _hi_suite_end thing >/dev/null
  )
}

function test_suite_end_exits_with_the_failure_count() {
  local rc=0
  (
    _HI_TOTAL=5
    _HI_FAILED=3
    _hi_suite_end thing >/dev/null
  ) || rc=$?
  [ "$rc" -eq 3 ]
}

function test_suite_end_default_wording_uses_the_subject() {
  local out
  out="$(
    _HI_TOTAL=2
    _HI_FAILED=0
    _hi_suite_end "check.sh"
  )"
  [[ "$out" == *"All check.sh checks passed (2 cases)"* ]]
}

function test_suite_end_default_failure_wording_shows_the_ratio() {
  local out
  out="$(
    _HI_TOTAL=5
    _HI_FAILED=2
    _hi_suite_end "check.sh"
  )" || true
  [[ "$out" == *"2/5 check.sh checks FAILED"* ]]
}

function test_suite_end_honours_custom_banners() {
  local pass fail
  pass="$(
    _HI_TOTAL=1
    _HI_FAILED=0
    _hi_suite_end "" "custom pass line" "custom fail line"
  )"
  fail="$(
    _HI_TOTAL=1
    _HI_FAILED=1
    _hi_suite_end "" "custom pass line" "custom fail line"
  )" || true
  [[ "$pass" == *"custom pass line"* && "$fail" == *"custom fail line"* ]]
}

function test_report_counts_writes_total_and_failed() {
  local file
  file="$_HI_WORKDIR/counts.reported"
  (
    _HI_COUNTS_FILE="$file"
    _hi_report_counts 9 2
  )
  [ "$(cat "$file")" = "9 2 0" ]
}

function test_report_counts_writes_the_skip_tally() {
  local file
  file="$_HI_WORKDIR/counts.skiptally"
  (
    _HI_COUNTS_FILE="$file"
    _hi_report_counts 9 2 3
  )
  [ "$(cat "$file")" = "9 2 3" ]
}

function test_note_failure_appends_the_label() {
  local file
  file="$_HI_WORKDIR/fails.noted"
  (
    _HI_FAILS_FILE="$file"
    _hi_note_failure "first case"
    _hi_note_failure "second case"
  )
  [ "$(cat "$file")" = "first case
second case" ]
}

function test_note_failure_is_a_noop_without_a_fails_file() {
  (
    unset _HI_FAILS_FILE
    _hi_note_failure "nobody listening"
  )
}

# run standalone (no runner above it) the helper must do nothing at all,
# rather than erroring on an unset path
function test_report_counts_is_a_noop_without_a_counts_file() {
  (
    unset _HI_COUNTS_FILE
    _hi_report_counts 1 0
  )
}

function test_report_skip_marks_the_suite_as_skipped() {
  local file
  file="$_HI_WORKDIR/counts.skipped"
  (
    _HI_COUNTS_FILE="$file"
    _hi_report_skip "no docker"
  )
  [ "$(cat "$file")" = "SKIP no docker" ]
}

function test_report_skip_is_a_noop_without_a_counts_file() {
  (
    unset _HI_COUNTS_FILE
    _hi_report_skip "no docker"
  )
}

# _hi_require's skip path has to reach the runner, or a suite that never ran
# a case still renders as a green PASS - the whole point of the status
function test_require_reports_a_skip_for_a_missing_binary() {
  local file
  file="$_HI_WORKDIR/counts.require"
  (
    _HI_COUNTS_FILE="$file"
    _hi_require definitely-not-a-real-binary >/dev/null 2>&1
  ) || true
  [[ "$(cat "$file")" == SKIP* ]]
}

# the counter has to be bumped in the *caller's* shell, so the output goes to
# a file rather than through $(...) - a command substitution would run
# _hi_skip in a subshell and lose the increment it is meant to prove
function test_skip_counts_the_case_without_passing_it() {
  local out file="$_HI_WORKDIR/skip.out"
  local _HI_SKIPPED=0 _HI_REQUIRE_RUN=0
  _hi_skip "[case]" "no python3" >"$file"
  out="$(cat "$file")"
  [ "$_HI_SKIPPED" -eq 1 ] && [[ "$out" == *SKIPPED* ]] && [[ "$out" == *"no python3"* ]]
}

# $_HI_REQUIRE_RUN is pinned off in every case below that skips something: the
# runner hands it down to each suite, so a `--require-run` run of this suite
# would otherwise put its own cases under the rule they are describing.
function test_suite_end_names_the_skipped_cases() {
  local out
  out="$(
    _HI_REQUIRE_RUN=0
    _HI_TOTAL=3
    _HI_FAILED=0
    _HI_SKIPPED=2
    _hi_suite_end demo
  )" || true
  [[ "$out" == *"3 cases, 2 skipped"* ]]
}

# --require-run: a case that never ran is a failure, and the suite has to exit
# non-zero saying so - a green suite with a yellow line in it is the hole the
# flag exists to close
function test_suite_end_fails_on_a_skip_under_require_run() {
  local out rc=0
  out="$(
    _HI_REQUIRE_RUN=1
    _HI_TOTAL=3
    _HI_FAILED=0
    _HI_SKIPPED=2
    _hi_suite_end demo
  )" || rc=$?
  [ "$rc" -eq 2 ] && [[ "$out" == *"stood down"* ]] && [[ "$out" == *"--require-run"* ]]
}

# a suite that both failed and skipped keeps its own failure wording, with the
# stand-downs added to the count rather than replacing what broke
function test_suite_end_adds_skips_to_real_failures() {
  local out rc=0
  out="$(
    _HI_REQUIRE_RUN=1
    _HI_TOTAL=5
    _HI_FAILED=2
    _HI_SKIPPED=1
    _hi_suite_end demo
  )" || rc=$?
  [ "$rc" -eq 3 ] && [[ "$out" == *"2/5 demo checks FAILED"* ]] && [[ "$out" == *"1 more stood down"* ]]
}

# ...but the tally it hands the runner is unchanged: the cases skipped, they
# did not fail an assertion, and the summary's two columns have to keep saying
# which is which
function test_require_run_leaves_the_counts_alone() {
  local file
  file="$_HI_WORKDIR/counts.require_run"
  (
    _HI_REQUIRE_RUN=1
    _HI_COUNTS_FILE="$file"
    _HI_TOTAL=4
    _HI_FAILED=1
    _HI_SKIPPED=2
    _hi_suite_end thing >/dev/null
  ) || true
  [ "$(cat "$file")" = "4 1 2" ]
}

# the label and the reason are only in hand inside _hi_skip, so that is where
# the runner's recap has to be told which case went missing
function test_skip_names_the_case_under_require_run() {
  local file fails
  file="$_HI_WORKDIR/skip.requirerun.out"
  fails="$_HI_WORKDIR/skip.requirerun.fails"
  : >"$fails"
  (
    _HI_REQUIRE_RUN=1
    _HI_FAILS_FILE="$fails"
    _HI_SKIPPED=0
    _hi_skip "[mise]" "image did not build" >"$file"
  )
  [[ "$(cat "$fails")" == *"[mise]"* ]] &&
    [[ "$(cat "$fails")" == *"image did not build"* ]] &&
    [[ "$(cat "$file")" == *SKIPPED* ]]
}

function test_suite_end_stays_quiet_with_nothing_skipped() {
  local out
  out="$(
    _HI_TOTAL=3
    _HI_FAILED=0
    _HI_SKIPPED=0
    _hi_suite_end demo
  )" || true
  [[ "$out" == *"3 cases)"* ]] && [[ "$out" != *skipped* ]]
}

function test_suite_end_reports_its_counts() {
  local file
  file="$_HI_WORKDIR/counts.suite_end"
  (
    _HI_COUNTS_FILE="$file"
    _HI_TOTAL=5
    _HI_FAILED=2
    _HI_SKIPPED=1
    _hi_suite_end thing >/dev/null
  ) || true
  [ "$(cat "$file")" = "5 2 1" ]
}

# _hi_dump_log replaced six messages that printed a log's *path*, every one of
# them under $_HI_WORKDIR and so already deleted by _hi_test_cleanup's rm -rf
# by the time anyone could follow it. What matters now is that the text itself
# reaches the transcript, since that is the only surviving copy.
function _hi_dump_log_out() {
  _hi_strip_ansi "$(_hi_dump_log "$@")"
}

function test_dump_log_prints_the_logs_text() {
  local log="$_HI_WORKDIR/dump.log" out
  printf 'first line\nsecond line\n' >"$log"
  out="$(_hi_dump_log_out "it broke:" "$log")"
  [[ "$out" == *"first line"* ]] && [[ "$out" == *"second line"* ]]
}

function test_dump_log_indents_the_text_it_dumps() {
  local log="$_HI_WORKDIR/dump.log" out
  printf 'a failure\n' >"$log"
  out="$(_hi_dump_log_out "it broke:" "$log")"
  # six spaces, the indent _hi_case_result already dumps transcripts at
  printf '%s\n' "$out" | grep -qx '      a failure'
}

function test_dump_log_prints_its_message() {
  local log="$_HI_WORKDIR/dump.log" out
  printf 'noise\n' >"$log"
  out="$(_hi_dump_log_out "the pod never started:" "$log")"
  [[ "$out" == *"the pod never started:"* ]]
}

function test_dump_log_says_so_when_the_log_is_empty() {
  local log="$_HI_WORKDIR/empty.log" out
  : >"$log"
  out="$(_hi_dump_log_out "it broke:" "$log")"
  [[ "$out" == *"it broke:"* ]] && [[ "$out" == *"wrote nothing"* ]]
}

# a command can fail before its redirection ever creates the file
function test_dump_log_survives_a_missing_log() {
  local out
  out="$(_hi_dump_log_out "it broke:" "$_HI_WORKDIR/never-written.log")"
  [[ "$out" == *"it broke:"* ]] && [[ "$out" == *"wrote nothing"* ]]
}

# the path is what this replaced: it is unlinked before it can be read, so
# printing it would be pointing at nothing
function test_dump_log_does_not_print_the_path() {
  local log="$_HI_WORKDIR/dump.log" out
  printf 'boom\n' >"$log"
  out="$(_hi_dump_log_out "it broke:" "$log")"
  [[ "$out" != *"$log"* ]]
}
# _hi_align is the one rule behind every verdict a run prints - the per-case
# lines here and, through _hi_status_line, the per-suite ones the runner leaves
# behind. runner_test.sh covers it from that end; these cover it directly.
function _hi_align_out() {
  _hi_strip_ansi "$(_hi_align "$@")"
}

function test_align_spans_hi_max_width() {
  local out
  export _HI_MAX_WIDTH=60
  out="$(_hi_align_out " | a label" "OK")"
  unset _HI_MAX_WIDTH
  [ "${#out}" -eq 60 ]
}

# the point of it: two labels of different lengths put their verdict in the
# same column rather than each ragging along behind its own label
function test_align_puts_verdicts_in_one_column() {
  local short long
  export _HI_MAX_WIDTH=60
  short="$(_hi_align_out " | a" "OK")"
  long="$(_hi_align_out " | a much longer label" "OK")"
  unset _HI_MAX_WIDTH
  # the column each verdict starts in, as the width of everything before it
  short="${short%%OK*}"
  long="${long%%OK*}"
  [ "${#short}" -eq "${#long}" ]
}

function test_align_defaults_to_eighty_columns() {
  local out
  out="$(_hi_align_out " | a label" "OK")"
  [ "${#out}" -eq 80 ]
}

# a label with no room left for its verdict overflows rather than truncating,
# and keeps the two-space gutter so the two never run together
function test_align_overflows_rather_than_truncating() {
  local out
  export _HI_MAX_WIDTH=12
  out="$(_hi_align_out " | a label far wider than the width" "OK")"
  unset _HI_MAX_WIDTH
  [[ "$out" == *"a label far wider than the width"* ]] &&
    [[ "$out" == *"  OK" ]]
}

function test_align_keeps_the_whole_verdict_together() {
  local out
  export _HI_MAX_WIDTH=60
  out="$(_hi_align_out " | a case" "SKIPPED (no python3)")"
  unset _HI_MAX_WIDTH
  [[ "$out" == *"SKIPPED (no python3)" ]]
}

function run_lib_report_tests() {
  _hi_workdir libreporttest

  _hi_suite_begin

  _hi_h1 "Testing tests/lib/: counting and reporting"

  _hi_h2 "Testing: _hi_case / _hi_assert / _hi_check"
  _hi_check "Counts a passing case" _hi_sandboxed test_case_counts_a_pass
  _hi_check "Counts a failing case" _hi_sandboxed test_case_counts_a_failure
  _hi_check "Keeps running after a failure" _hi_sandboxed test_case_keeps_running_after_a_failure
  _hi_check "Assert reports OK" test_assert_reports_ok_and_returns_zero
  _hi_check "Assert reports FAILED and returns non-zero" test_assert_reports_failed_and_returns_nonzero
  _hi_check "Assert forwards extra arguments" test_assert_passes_through_arguments
  _hi_check "Check counts and labels in one call" _hi_sandboxed test_check_counts_and_labels_in_one_call

  _hi_h2 "Testing: _hi_suite_begin / _hi_suite_end"
  _hi_check "Begin zeroes both counters" _hi_sandboxed test_suite_begin_zeroes_both_counters
  _hi_check "End exits 0 when nothing failed" test_suite_end_exits_zero_when_nothing_failed
  _hi_check "End exits with the failure count" test_suite_end_exits_with_the_failure_count
  _hi_check "End's default pass wording uses the subject" test_suite_end_default_wording_uses_the_subject
  _hi_check "End's default failure wording shows the ratio" test_suite_end_default_failure_wording_shows_the_ratio
  _hi_check "End honours custom banners" test_suite_end_honours_custom_banners

  _hi_h2 "Testing: _hi_report_counts / _hi_note_failure"
  _hi_check "Writes total and failed" test_report_counts_writes_total_and_failed
  _hi_check "Writes the skip tally" test_report_counts_writes_the_skip_tally
  _hi_check "No-op without a counts file" test_report_counts_is_a_noop_without_a_counts_file
  _hi_check "End reports its counts" test_suite_end_reports_its_counts
  _hi_check "Note_failure appends the label" test_note_failure_appends_the_label
  _hi_check "Note_failure is a no-op standalone" test_note_failure_is_a_noop_without_a_fails_file

  _hi_h2 "Testing: _hi_report_skip / _hi_skip"
  _hi_check "Report_skip marks the suite skipped" test_report_skip_marks_the_suite_as_skipped
  _hi_check "Report_skip is a no-op without a counts file" test_report_skip_is_a_noop_without_a_counts_file
  _hi_check "Require reports a skip for a missing binary" test_require_reports_a_skip_for_a_missing_binary
  _hi_check "Skip counts a case without passing it" test_skip_counts_the_case_without_passing_it
  _hi_check "End names the skipped cases" test_suite_end_names_the_skipped_cases
  _hi_check "End stays quiet with nothing skipped" test_suite_end_stays_quiet_with_nothing_skipped
  _hi_check "End fails on a skip under --require-run" test_suite_end_fails_on_a_skip_under_require_run
  _hi_check "End adds skips to real failures" test_suite_end_adds_skips_to_real_failures
  _hi_check "--require-run leaves the counts alone" test_require_run_leaves_the_counts_alone
  _hi_check "Skip names the case under --require-run" test_skip_names_the_case_under_require_run

  _hi_h2 "Testing: _hi_align"
  _hi_check "Spans _HI_MAX_WIDTH" test_align_spans_hi_max_width
  _hi_check "Verdicts land in one column" test_align_puts_verdicts_in_one_column
  _hi_check "Defaults to 80 columns" test_align_defaults_to_eighty_columns
  _hi_check "A too-wide label overflows, keeping its gutter" test_align_overflows_rather_than_truncating
  _hi_check "A multi-word verdict stays whole" test_align_keeps_the_whole_verdict_together

  _hi_h2 "Testing: _hi_dump_log"
  _hi_check "Dumps the failing log's text" test_dump_log_prints_the_logs_text
  _hi_check "Indents the dump six spaces" test_dump_log_indents_the_text_it_dumps
  _hi_check "Prints the failure message too" test_dump_log_prints_its_message
  _hi_check "Says so when the log is empty" test_dump_log_says_so_when_the_log_is_empty
  _hi_check "Survives a log that was never written" test_dump_log_survives_a_missing_log
  _hi_check "Never prints the (deleted) log path" test_dump_log_does_not_print_the_path
  _hi_suite_end "tests/lib/ (counting and reporting)"
}

run_lib_report_tests
