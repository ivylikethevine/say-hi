#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Line coverage for the bash suites via kcov - run by hand, and by
# coverage.yml after every green push to main. The point is finding which
# arms of scripts/install.sh and packaging/bump.sh the ~1,400 cases never
# touch, not gating on a number.
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
# HOW FAR TO TRUST A NUMBER THIS PRINTS
#
# With the current kcov pin and the full-sweep default, this lands within a
# few points of bashcov's figure (coverage_v2.sh), so the numbers are usable:
# for finding untested arms and watching the trend - still never as a gate.
# That sentence has to be re-earned whenever the two badges diverge, because
# an earlier kcov lost the plot entirely, and the measured record of how is
# kept here so the next person can rerun it instead of rediscovering it:
#
# That kcov stopped recording the moment tests/test_lib.sh finished being
# sourced - everything a suite did after that was invisible, and the
# percentages described "what ran while the harness loaded", not coverage.
# The probe: one script that sources core.sh, sources git_prompt.sh, makes a
# git repo and calls _hi_git_prompt once, traced under kcov:
#
#   no test_lib.sh sourced at all ................ git_prompt.sh  59.15%
#   test_lib.sh sourced BEFORE the call .......... git_prompt.sh   2.82%
#   test_lib.sh sourced BEFORE git_prompt.sh ..... git_prompt.sh  ABSENT
#
# 2.82% was 2 lines of 71: the `set -euo pipefail`/`set +euo pipefail` pair
# that runs at *source* time, with the whole asserted function body recorded
# as never executed. The cause was inside kcov's bash instrumentation (it
# drives a DEBUG trap; something in test_lib.sh's source-time work lost it),
# not in test_lib.sh or the suites. If kcov's badge ever sags far under
# bashcov's again, rerun that probe before believing either figure.
#
# The topology below is what makes the trace work at all: one kcov per suite
# with the suite script as the *top-level* process, merged at the end.
# Wrapping test_runner.sh instead would put every suite in a child process
# and lose even the load-time lines.
#
# FILES THAT READ LOW HERE ON PURPOSE - NOT A GAP, DON'T ADD TESTS
#
# The DEBUG trap above is lost specifically at test_lib.sh's *source* time; it
# is equally lost inside any `$( )`, `( )`, `&` or child process launched
# anywhere after, for the rest of that suite's run. bashcov's xtrace has no
# such hole (SHELLOPTS carries `xtrace` into every child bash), so the two
# tools' figures are read together per docs/TESTING.md, and where they
# disagree this wide it is this file's instrumentation, confirmed against
# coverage_v2.sh's numbers on the same suites, both measured 2026-09-03:
#
#   common/git_prompt.sh   57.69% here, 100.00%  under coverage_v2.sh - every
#     case in git_prompt_test.sh calls _hi_git_prompt inside $( ), the
#     original instance of this bug (the probe above is this file).
#   common/targets.sh      ABSENT here, 95.29%   under coverage_v2.sh
#   common/notify.sh       ABSENT here, 100.00%  under coverage_v2.sh
#   common/osc52.sh        ABSENT here, 100.00%  under coverage_v2.sh
#     all three are `#!/bin/sh` scripts their suites *execute* as children
#     (targets_test.sh, notify_test.sh, osc52_test.sh) rather than source -
#     common/paths.sh is also `#!/bin/sh` and reads 100% here only because
#     core.sh sources it into the traced process instead.
#   hi.sh                  64.77% here under --group fast, 84.56% under the
#     full sweep, 97.80% under coverage_v2.sh's full sweep - the e2e/backends
#     suites reach _say_hi/_say_hi_container/_hi themselves only inside a
#     backgrounded child (tests/lib/process.sh) or a parallel-case subshell
#     (tests/lib/backend.sh), both invisible here for the same reason.
#
# Confirmed real rather than an artifact: every one of these reads >=70%
# under coverage_v2.sh's full sweep too, which is what settled it - don't
# re-add tests here on the strength of this file's number alone; rerun both
# sweeps and compare.
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
