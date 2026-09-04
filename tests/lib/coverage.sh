#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# The scaffold tests/coverage.sh and tests/coverage_v2.sh share: tree
# resolution, suite selection off the runner's table, the tally files the
# suites report through, the per-suite trace loop, and cleanup. Sourced by
# those two drivers directly - deliberately NOT part of the tests/test_lib.sh
# harness. HI.34 is about suites; these drivers avoid test_lib.sh so the
# instrumented process stays the suite script itself (see each driver's
# header for what its instrumentation does and does not record).

if [ -z "${_HI_HOME:-}" ]; then
  _HI_HOME="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fi
export _HI_HOME
# shellcheck source=../../common/core.sh
source "$_HI_HOME/say-hi/common/core.sh"

_HI_RUNNER="$_HI_HOME/say-hi/tests/test_runner.sh"

# Everything a driver wants removed on the way out lands in this array; the
# one trap covers files appended at any later point (the trap body expands at
# fire time, not here).
declare -a _HI_COV_TRASH=()
function _hi_cov_cleanup() {
  rm -f ${_HI_COV_TRASH[@]+"${_HI_COV_TRASH[@]}"}
}
trap '_hi_cov_cleanup' EXIT

# _hi_cov_select_suites [runner args...] - fill $_HI_NAMES/$_HI_PATHS with the
# suites the given runner arguments select. The runner owns the suite table,
# so ask it rather than keeping a second copy here - the same reason
# .github/workflows/ci.yml stopped spelling the suites out. `--list-paths`
# exists for this caller: the instrumenting tool has to launch the suite
# script itself, so the name alone is not enough.
#
# `shellcheck` is dropped from whatever the selection resolves to. It is a
# linter sweep, not a code path: it shells out to shellcheck, shfmt and
# checkbashisms over every file in the tree and runs almost none of hi's own
# bash, so it traces nothing this report is asking about - while being the
# slowest suite in its group by an order of magnitude, and slower again under
# instrumentation. Dropped by name, so a groupless run (the default, every
# suite including the lint group) does not sweep it back in.
function _hi_cov_select_suites() {
  _HI_NAMES=()
  _HI_PATHS=()
  local _hi_group _hi_name _hi_path
  while read -r _hi_group _hi_name _hi_path; do
    [ -n "${_hi_path:-}" ] || continue
    [ "$_hi_name" = shellcheck ] && continue
    _HI_NAMES+=("$_hi_name")
    _HI_PATHS+=("$_hi_path")
  done < <("$_HI_RUNNER" "$@" --list-paths)

  if [ "${#_HI_PATHS[@]}" -eq 0 ]; then
    _hi_cecho " | coverage: no suites selected by: $*" "$RED" >&2
    exit 1
  fi
}

# _hi_cov_counts_files <tag> - the two files the runner would otherwise
# export, made here so _hi_suite_end has somewhere to write its tally;
# everything else a suite needs it derives from $_HI_HOME through
# common/paths.sh.
function _hi_cov_counts_files() {
  _HI_COUNTS_FILE="$(mktemp -t "hi.$1.counts.XXXXXX")"
  _HI_FAILS_FILE="$(mktemp -t "hi.$1.fails.XXXXXX")"
  export _HI_COUNTS_FILE _HI_FAILS_FILE
  _HI_COV_TRASH+=("$_HI_COUNTS_FILE" "$_HI_FAILS_FILE")
}

# _hi_cov_trace_all <trace-fn> - run <trace-fn> <name> <path> for every
# selected suite, its output discarded (the report is the artifact, the
# transcript is noise). A suite that fails does not stop the sweep: a red
# suite still traced everything it reached on the way down, and losing the
# whole report to one environment-specific failure (no fish, no docker) is
# the opposite of useful. The names land in $_HI_FAILED for
# _hi_cov_report_failed to print at the end instead.
function _hi_cov_trace_all() {
  local _hi_i _hi_suite _hi_path
  _HI_FAILED=""
  for _hi_i in $(seq 0 $((${#_HI_PATHS[@]} - 1))); do
    _hi_suite="${_HI_NAMES[$_hi_i]}"
    _hi_path="${_HI_PATHS[$_hi_i]}"
    _hi_cecho " | coverage: tracing $_hi_suite" "$BRCYAN"
    "$1" "$_hi_suite" "$_hi_path" >/dev/null 2>&1 ||
      _HI_FAILED="$_HI_FAILED $_hi_suite"
  done
}

function _hi_cov_report_failed() {
  [ -z "$_HI_FAILED" ] ||
    _hi_cecho " | coverage: these suites failed while being traced (their coverage still counts):$_HI_FAILED" "$YELLOW"
}
