#!/usr/bin/env bash
# Unit tests for the tests/lib/ harness - the scratch dir, its teardown, and
# the parallel batch.
# tests/lib/workdir.sh and tests/lib/parallel.sh. The cases that overwrite
# $_HI_WORKDIR/$_HI_LEDGER shadow them with locals or a subshell - this suite
# uses the globals it is testing.
#
# The harness is the one code whose bugs would be invisible: a broken _hi_case
# under-counts failures and every suite still looks green.
#
# Anything that exits or installs a trap runs in a subshell so it can't take
# this suite down.
#
# GLOSSARY: HI.30 + HI.34. The subshell containment above is the mechanism
# SC2030/2031 would warn about.
# shellcheck disable=SC2329,SC2030,SC2031
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# The hook a case hands _HI_EXTRA_CLEANUP to prove the teardown carries on past
# a failing one. Its own copy, the way lib_test.sh and lib_report_test.sh each
# carry theirs: without it the hook is merely *missing*, which the teardown
# swallows just the same - but as a "command not found" on the suite's stderr,
# and the case then tests something it does not say it tests.
function _hi_false() { return 1; }

function test_workdir_creates_a_scratch_dir() {
  local dir
  dir="$(
    _hi_workdir probe
    printf '%s' "$_HI_WORKDIR"
  )"
  # the subshell's exit trap already removed it, which is the other half of
  # the contract - so assert on the shape and on its being gone
  [[ "$dir" == */hi.probe.* ]] && [ ! -d "$dir" ]
}

function test_test_cleanup_runs_the_extra_hook_first() {
  local marker="$_HI_WORKDIR/hook-ran"
  (
    _HI_WORKDIR="$(mktemp -d "$_HI_WORKDIR/inner.XXXXXX")"
    _HI_LEDGER=""
    # shellcheck disable=SC2317 # invoked by _hi_test_cleanup through $_HI_EXTRA_CLEANUP
    function _hi_probe_hook() { : >"$marker"; }
    _HI_EXTRA_CLEANUP=_hi_probe_hook
    _hi_test_cleanup
  )
  [ -f "$marker" ]
}

function test_test_cleanup_removes_the_workdir_even_if_the_hook_fails() {
  local inner
  inner="$(mktemp -d "$_HI_WORKDIR/inner.XXXXXX")"
  (
    _HI_WORKDIR="$inner"
    _HI_LEDGER=""
    _HI_EXTRA_CLEANUP=_hi_false
    _hi_test_cleanup
  )
  [ ! -d "$inner" ]
}

# The ledger's whole reason for being a file: the background subshell's entry
# has to be there for the *parent's* exit trap to find. An array cannot do it:
# the append dies with the subshell, and the container leaks.
function test_track_container_records_from_a_subshell_too() {
  local _HI_LEDGER="$_HI_WORKDIR/ledger-track" rows
  : >"$_HI_LEDGER"
  _hi_track_container one
  (_hi_track_container two) &
  wait
  _hi_track_network relaynet
  rows="$(_hi_ledger_rows container | tr '\n' ' ')"
  [ "$rows" = "one two " ] || return 1
  [ "$(_hi_ledger_rows network)" = relaynet ]
}

# ...and the sweep that consumes it, through a fake backend that records what it
# was asked to remove. Networks after containers, since docker refuses to remove
# one that still has a container on it.
function test_cleanup_sweeps_containers_then_networks() {
  local dir="$_HI_WORKDIR/sweep" log
  mkdir -p "$dir/bin"
  log="$dir/calls"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s"\n' "$log" >"$dir/bin/hi-fake-backend"
  chmod +x "$dir/bin/hi-fake-backend"
  (
    _HI_WORKDIR="$(mktemp -d "$dir/inner.XXXXXX")"
    _HI_LEDGER="$_HI_WORKDIR/.ledger"
    : >"$_HI_LEDGER"
    _HI_EXTRA_CLEANUP=""
    _HI_BACKEND=hi-fake-backend
    PATH="$dir/bin:$PATH"
    _hi_track_container gone
    _hi_track_network alsogone
    _hi_test_cleanup
  )
  [ -f "$log" ] || return 1
  _hi_before "$(cat "$log")" '^rm -f gone$' '^network rm alsogone$'
}

# The counted-case contract, run in a background subshell. Everything here is
# assertable without docker, which is the point: the suites that use it need a
# container backend, and a harness bug there looks like a product bug.

function _hi_par_ok() { return 0; }
function _hi_par_bad() { return 1; }
function _hi_par_skipper() { _hi_skip "[a skipped case]" "on purpose"; }
function _hi_par_exits() { exit 0; }
function _hi_par_says() { printf '%s\n' "$1"; }

# Two cases that each wait on a file the other creates: run together both
# return at once, run in turn the first spends its whole budget and fails.
# A rendezvous rather than a stopwatch, so "did they overlap" has a yes/no
# answer that a loaded runner cannot smear.
function _hi_par_rendezvous() {
  : >"$_HI_PAR_RV_DIR/$1"
  _hi_poll_bool "$3" 0.25 test -f "$_HI_PAR_RV_DIR/$2"
}

# Three cases in, but $_HI_TOTAL is 2: a skipped case is counted in
# $_HI_SKIPPED alone, exactly as the serial twin does it (_hi_check_requires
# reaches _hi_skip without going through _hi_case). The next case pins why that
# matters.
function test_par_case_tallies_pass_fail_and_skip() {
  (
    _hi_suite_begin
    _hi_par_begin "harness probe"
    _hi_par_case ok _hi_par_ok
    _hi_par_case bad _hi_par_bad
    _hi_par_case skipped _hi_par_skipper
    _hi_par_wait
    [ "$_HI_TOTAL" -eq 2 ] && [ "$_HI_FAILED" -eq 1 ] && [ "$_HI_SKIPPED" -eq 1 ]
  ) >/dev/null
}

# test_runner.sh reports `pass = cases - failed` (its _hi_pass), so a skipped
# case left in $_HI_TOTAL is reported as a green pass *and* a yellow skip - the
# arithmetic that quietly inflated the count feeding --totals-file and the
# README badge. A stand-down is never green: this is that rule, in numbers.
function test_par_skip_is_not_reported_as_a_pass() {
  local tally="$_HI_WORKDIR/par-skip-tally" total failed skipped
  # the tally through a file, not a process substitution: _hi_par_begin and
  # _hi_par_case narrate to stdout, and their lines would be what `read` got
  (
    _hi_suite_begin
    _hi_par_begin "harness probe"
    _hi_par_case ok _hi_par_ok
    _hi_par_case skipped _hi_par_skipper
    _hi_par_wait
    printf '%s %s %s\n' "$_HI_TOTAL" "$_HI_FAILED" "${_HI_SKIPPED:-0}" >"$tally"
  ) >/dev/null 2>&1
  read -r total failed skipped <"$tally"
  [ "$((total - failed))" -eq 1 ] && [ "$skipped" -eq 1 ]
}

# _hi_par_check reports through _hi_assert, which names the case by its bare
# label; _hi_par_wait's backstop then must not list it a second time as
# "exited 1 before reporting a verdict", which reads as a crash rather than a
# false assertion. A backstop that looks only for the bracketed "[label]"
# _hi_case_result writes recaps every failed parallel case twice.
function test_par_failed_assertion_is_recapped_once() {
  local fails="$_HI_WORKDIR/par-fails-once"
  : >"$fails"
  (
    _HI_FAILS_FILE="$fails"
    _hi_suite_begin
    _hi_par_begin "recap probe"
    _hi_par_check "a failing case" _hi_par_bad
    _hi_par_wait
  ) >/dev/null 2>&1 || true
  [ "$(grep -c . "$fails")" -eq 1 ] && grep -qxF "a failing case" "$fails"
}

# a case that never reaches its verdict is a failure, not a case that vanishes
# from the totals - the counting bug that would make a red run look green
function test_par_case_without_a_verdict_counts_as_a_failure() {
  local fails="$_HI_WORKDIR/par-fails"
  : >"$fails"
  (
    _HI_FAILS_FILE="$fails"
    _hi_suite_begin
    _hi_par_begin "verdict probe"
    _hi_par_case vanished _hi_par_exits
    _hi_par_wait
    [ "$_HI_TOTAL" -eq 1 ] && [ "$_HI_FAILED" -eq 1 ]
  ) >/dev/null || return 1
  grep -q 'vanished' "$fails"
}

# _hi_expect_eq's whole reason to exist is the failure transcript: a bare
# `[ "$a" = "$b" ]` reports FAILED and withholds the values, which is what made
# an install_location failure on a runner nobody can reach undiagnosable.
function _hi_expect_probe() { printf '%s' "${1:-}"; }

function test_expect_eq_passes_on_a_match() {
  _hi_expect_eq "match" wanted _hi_expect_probe wanted >/dev/null
}

function test_expect_eq_prints_want_and_got_on_a_mismatch() {
  local out
  out="$(_hi_expect_eq "mismatch" wanted _hi_expect_probe "" 2>&1)" && return 1
  out="$(_hi_strip_ansi "$out")"
  [[ "$out" == *FAILED* ]] && [[ "$out" == *'want: "wanted"'* ]] && [[ "$out" == *'got:  ""'* ]]
}

# and it has to name the failing case for the recap, exactly as _hi_assert does
function test_expect_eq_names_the_case_for_the_recap() {
  local fails="$_HI_WORKDIR/expect-fails"
  : >"$fails"
  (
    _HI_FAILS_FILE="$fails"
    _hi_expect_eq "a mismatched case" wanted _hi_expect_probe other
  ) >/dev/null 2>&1 || true
  grep -qxF "a mismatched case" "$fails"
}

function test_par_wait_replays_in_submission_order() {
  local out
  out="$(
    _HI_PAR_WIDTH=4
    _hi_suite_begin
    _hi_par_begin "order probe"
    _hi_par_case slow bash -c 'sleep 0.75; printf "FIRST-CASE\n"'
    _hi_par_case quick _hi_par_says SECOND-CASE
    _hi_par_wait
  )"
  _hi_before "$out" 'FIRST-CASE' 'SECOND-CASE'
}

function test_par_cases_really_run_at_once() {
  (
    _HI_PAR_WIDTH=2
    _HI_PAR_RV_DIR="$_HI_WORKDIR/rv-parallel"
    mkdir -p "$_HI_PAR_RV_DIR"
    _hi_suite_begin
    _hi_par_begin "overlap probe"
    _hi_par_case a _hi_par_rendezvous a b 20
    _hi_par_case b _hi_par_rendezvous b a 20
    _hi_par_wait
    [ "$_HI_FAILED" -eq 0 ]
  ) >/dev/null
}

# the other half of the same proof, and the escape hatch's test: at width 1 the
# cases cannot see each other, so the first one spends its (short) budget and
# fails. _HI_PAR_WIDTH=1 is a real serial run down the parallel code path.
function test_par_width_one_really_serializes() {
  (
    _HI_PAR_WIDTH=1
    _HI_PAR_RV_DIR="$_HI_WORKDIR/rv-serial"
    mkdir -p "$_HI_PAR_RV_DIR"
    _hi_suite_begin
    _hi_par_begin "serial probe"
    _hi_par_case a _hi_par_rendezvous a b 4
    _hi_par_case b _hi_par_rendezvous b a 4
    _hi_par_wait
    [ "$_HI_FAILED" -eq 1 ]
  ) >/dev/null
}

# a capped run must say it is capped rather than read as "everything at once"
function test_par_begin_announces_the_width() {
  local wide narrow
  wide="$( (_HI_PAR_WIDTH=3 _hi_par_begin "probe cases") )"
  narrow="$( (_HI_PAR_WIDTH=1 _hi_par_begin "probe cases") )"
  [[ "$wide" == *"3 at a time"* ]] || return 1
  [[ "$narrow" == *"one at a time"* ]]
}

function test_par_width_defaults_within_bounds() {
  local w
  w="$( (
    unset _HI_PAR_WIDTH
    _hi_par_width
  ))"
  [ "$w" -ge 1 ] && [ "$w" -le 4 ]
}

function run_lib_parallel_tests() {
  _hi_workdir libpartest

  _hi_suite_begin

  _hi_h1 "Testing tests/lib/: the workdir and the parallel batch"

  _hi_h2 "Testing: _hi_workdir / _hi_track_container / _hi_test_cleanup"
  _hi_check "Workdir creates a scratch dir" test_workdir_creates_a_scratch_dir
  _hi_check "Cleanup runs the suite-specific hook" test_test_cleanup_runs_the_extra_hook_first
  _hi_check "Cleanup removes the workdir even if the hook fails" test_test_cleanup_removes_the_workdir_even_if_the_hook_fails
  _hi_check "Track_container records from a subshell too" test_track_container_records_from_a_subshell_too
  _hi_check "Cleanup sweeps containers, then networks" test_cleanup_sweeps_containers_then_networks

  _hi_h2 "Testing: _hi_par_case / _hi_par_wait"
  _hi_check "Tallies pass, fail and skip" test_par_case_tallies_pass_fail_and_skip
  _hi_check "A skipped case is not a pass" test_par_skip_is_not_reported_as_a_pass
  _hi_check "A failed assertion is recapped once" test_par_failed_assertion_is_recapped_once
  _hi_check "A case with no verdict is a failure" test_par_case_without_a_verdict_counts_as_a_failure
  _hi_check "Transcripts replay in submission order" test_par_wait_replays_in_submission_order
  _hi_check "The cases really do overlap" test_par_cases_really_run_at_once
  _hi_check "_HI_PAR_WIDTH=1 really serializes" test_par_width_one_really_serializes
  _hi_check "The width is announced, capped or not" test_par_begin_announces_the_width
  _hi_check "The default width stays within bounds" test_par_width_defaults_within_bounds

  _hi_h2 "Testing: _hi_expect_eq"
  _hi_check "Passes on a match" test_expect_eq_passes_on_a_match
  _hi_check "Prints want and got on a mismatch" test_expect_eq_prints_want_and_got_on_a_mismatch
  _hi_check "Names the case for the recap" test_expect_eq_names_the_case_for_the_recap
  _hi_suite_end "tests/lib/ (workdir and parallel batch)"
}

run_lib_parallel_tests
