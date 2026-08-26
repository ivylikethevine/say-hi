#!/usr/bin/env bash
# The counted case: _hi_case tallies, _hi_assert reports, _hi_check does both.
#
# Part of the tests/test_lib.sh harness; sourced by it, never on its own.
# GLOSSARY: HI.30
# shellcheck disable=SC2329

# Runs "$@" as one sub-case of a multi-case test file (one shell, one
# container shape, one scenario, ...), bumping the caller's _HI_TOTAL/
# _HI_FAILED counters accordingly. Set both to 0 via _hi_suite_begin before
# the first case runs, so _hi_suite_end can report "$_HI_FAILED/$_HI_TOTAL
# cases failed" instead of a bare pass/fail.
function _hi_case() {
  _HI_TOTAL=$((_HI_TOTAL + 1))
  "$@" || _HI_FAILED=$((_HI_FAILED + 1))
}

# Runs "$@" (a predicate function or command) and reports it under $1 as a
# human-readable label. The unit suites always want this wrapped in _hi_case,
# which is what _hi_check below is; the e2e suites bring their own case
# runners, which report their own timings, and so use _hi_case directly.
function _hi_assert() {
  local label="$1"
  shift
  if "$@"; then
    _hi_align " | $label" "OK" "$GREEN"
  else
    _hi_align " | $label" "FAILED" "$RED"
    _hi_note_failure "$label"
    return 1
  fi
}

# _hi_check <label> <predicate...> - one counted, labelled assertion.
function _hi_check() {
  _hi_case _hi_assert "$@"
}
