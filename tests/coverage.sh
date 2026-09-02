#!/usr/bin/env bash
# Line coverage for the bash suites via kcov - a dev tool to run occasionally,
# deliberately not wired into CI. The point is finding which arms of
# scripts/install.sh and packaging/bump.sh the ~670 fast cases never touch,
# not gating on a number.
#
# Usage: tests/coverage.sh [outdir] [runner args...]
#   outdir       where kcov writes its report (default: $TMPDIR/say-hi-coverage)
#   runner args  passed straight to test_runner.sh (default: none - the same
#                "every suite" test_runner.sh itself defaults to, e2e and
#                backends groups included; pass e.g. --group fast to narrow
#                it). The `shellcheck` suite is dropped from whatever this
#                selects, wherever it appears - see the loop below.
#
# ---------------------------------------------------------------------------
# READ THIS BEFORE BELIEVING A NUMBER THIS PRINTS
#
# kcov stops recording the moment tests/test_lib.sh finishes being sourced.
# Everything a suite does after that - which is every case it runs - is
# invisible to the report. So these percentages are NOT "the arms the suites
# never reach". They are much closer to "the lines that ran before the harness
# finished loading", and they understate real coverage by a wide, uneven margin.
#
# How that was established, so the next person doesn't have to redo it. Take one
# script that sources core.sh, sources git_prompt.sh, makes a git repo and calls
# _hi_git_prompt once, and trace it under kcov:
#
#   no test_lib.sh sourced at all ................ git_prompt.sh  59.15%
#   test_lib.sh sourced BEFORE the call .......... git_prompt.sh   2.82%
#   test_lib.sh sourced BEFORE git_prompt.sh ..... git_prompt.sh  ABSENT
#
# 2.82% is 2 lines of 71: `set -euo pipefail` on line 5 and `set +euo pipefail`
# on line 116, the two statements that run at *source* time. The whole function
# body - called immediately after, successfully, with its output asserted - is
# recorded as never executed. That 2.82% is also exactly what a full
# `--group fast` run reports for the file, while its 17 cases pass. The cause is
# inside kcov's bash instrumentation (it drives a DEBUG trap; something in
# test_lib.sh's source-time work loses it), not in test_lib.sh or in the suites,
# and it is not say-hi's to fix. Nothing here is a code smell to go chasing.
#
# What that means in practice: a low number here is not evidence that tests are
# missing, and a high one is not evidence that they are not. Do not write tests
# to move these figures. Until kcov is fixed or replaced, treat the output as a
# rough map of what executes at load time and nothing more.
#
# The topology below is still the correct one, and is kept for when the tool
# works again: one kcov per suite with the suite script as the *top-level*
# process, merged at the end. Wrapping test_runner.sh instead would put every
# suite in a child process and lose even the load-time lines.
# ---------------------------------------------------------------------------
#
# Lives in tests/ on purpose: tests/ ships in neither the ssh payload
# ($_HI_PAYLOAD) nor the OS packages ($_HI_PACKAGE_CONTENTS), and a coverage
# harness has no business on a target.
set -euo pipefail

# tree resolution, suite selection, the tally files and the trace loop are
# shared with tests/coverage_v2.sh
# shellcheck source=lib/coverage.sh
source "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/coverage.sh"

if ! command -v kcov >/dev/null 2>&1; then
  _hi_cecho " | coverage: kcov not installed - skipping (a dev-only tool, and outside a PPA Debian/Ubuntu do not carry it: build it from github.com/SimonKagstrom/kcov, as CI does)" "$YELLOW"
  exit 0
fi

_HI_COV_DIR="${1:-${TMPDIR:-/tmp}/say-hi-coverage}"
shift 2>/dev/null || true

rm -rf "$_HI_COV_DIR"
mkdir -p "$_HI_COV_DIR/parts"

_hi_cov_select_suites "$@"
_hi_cov_counts_files cov

# The suite script is what kcov launches - not test_runner.sh with the suite
# named, which puts the suite back in a child process and traces nothing (see
# the header). tests/ itself is excluded from the report - the product is the
# subject, not the harness.
function _hi_cov_trace_one() {
  kcov --include-path="$_HI_HOME/say-hi" \
    --exclude-path="$_HI_HOME/say-hi/tests" \
    "$_HI_COV_DIR/parts/$1" \
    "$2"
}
_hi_cov_trace_all _hi_cov_trace_one

kcov --merge "$_HI_COV_DIR/merged" "$_HI_COV_DIR"/parts/* >/dev/null 2>&1

_hi_cecho " | coverage: report in $_HI_COV_DIR/merged/index.html" "$GREEN"
_hi_cov_report_failed

# Every file kcov traced, worst first - the ranking is the point, since the
# question this answers is "which arms does nothing reach", and the answer moves
# as suites are added. Straight from kcov's merged JSON, where one object is one
# line and every value is a quoted string:
#   {"file": "...", "percent_covered": "48.84", "covered_lines": "168", ...}
# So the percent is found by walking to the `percent_covered` key rather than by
# field number - which is what the first version of this got wrong, printing the
# path a second time where the number belonged, because it read `file` and
# `percent_covered` as two separate lines.
_HI_COV_JSON="$(find "$_HI_COV_DIR/merged" -name coverage.json 2>/dev/null | head -1)"
if [ -n "$_HI_COV_JSON" ] && [ -f "$_HI_COV_JSON" ]; then
  awk -F'"' -v root="$_HI_HOME/say-hi/" '
    /"file"/ {
      for (i = 1; i < NF; i++)
        if ($i == "percent_covered") {
          path = $4
          sub(root, "", path)
          printf " |   %6s%%  %5s/%-5s  %s\n", $(i + 2), $(i + 6), $(i + 10), path
          break
        }
    }' "$_HI_COV_JSON" | sort -n
fi
