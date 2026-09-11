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
#                selects, wherever it appears - see tests/lib/coverage.sh.
#
# ---------------------------------------------------------------------------
# HOW FAR TO TRUST A NUMBER THIS PRINTS
#
# With the current kcov pin and the full-sweep default, this lands within a
# few points of bashcov's figure (coverage_v2.sh), and has for many commits:
# both are reliable, the average of the two badges is the coverage figure,
# and the per-file report is for finding untested arms - still never a gate.
# Only a massive divergence between the two badges (tens of points, not the
# usual few) puts that in question, because an earlier kcov lost the plot
# entirely, and the measured record of how is
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
# THE MERGE RE-READS THE SOURCES
#
# `kcov --merge` opens every file its inputs recorded, at the absolute path
# they recorded it under, to count that file's lines again. Merge somewhere
# the tree is not and the result is not an error but a well-formed empty
# report - `"files": []`, `"total_lines": 0`, `"percent_covered": "0.00"`.
# A gather job with no `actions/checkout` would publish exactly that as the
# README's kcov badge. Measured on kcov 43, three suites' parts merged twice:
#
#   sources present ...... 41.06%, five files listed
#   one source moved away . 0.00%, "files": []
#
# The gather job checks the tree out, and tests/harness/runner_test.sh
# asserts that every coverage.yml job running `kcov --merge` does.
#
# The topology below is what makes the trace work at all: one kcov per suite
# with the suite script as the *top-level* process, merged at the end.
# Wrapping test_runner.sh instead would put every suite in a child process
# and lose even the load-time lines.
#
# FILES THAT READ LOW HERE ON PURPOSE - NOT A GAP, DON'T ADD TESTS
#
# The DEBUG trap above is lost specifically at test_lib.sh's *source* time; it
# is equally lost inside any `$( )`, `( )`, `&`, or child process launched
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
#     a `#!/bin/sh` script its suite *executes* as a child
#     (targets_test.sh) rather than sources -
#     common/paths.sh is also `#!/bin/sh` and reads 100% here only because
#     core.sh sources it into the traced process instead. The same
#     file reads 0% under coverage_v2.sh too wherever /bin/sh is dash
#     rather than bash (0/220, measured): neither tracer can
#     follow a non-bash child, so this driver shims `sh` to bash on PATH
#     (_hi_cov_shim_sh_to_bash, tests/lib/coverage.sh) before it starts.
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

# tree resolution, suite selection, the tally files, and the trace loop are
# shared with tests/coverage_v2.sh
# shellcheck source=lib/coverage.sh
source "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/coverage.sh"

# --merge <dest> <parts-dir> - coverage.yml's gather-kcov mode: merge every
# shard's uploaded parts (one subdirectory per suite, flattened into
# <parts-dir> by download-artifact's merge-multiple - disjoint by
# construction, since --shard partitions the suite table), print the same
# worst-first ranking a local sweep does, and write <dest>/coverage-pct/pct.
# Exits 0 either way, warning instead of failing: a badge is visibility,
# never a gate, and gather-kcov's own continue-on-error is one job-wide
# reason already, this is the other. `kcov --merge` re-reads every source
# file at the absolute path its shard recorded, so a caller with no working
# tree merges to `"files": []` and a well-formed 0.00 rather than an error -
# runner_test.sh checks the calling job still checks the tree out.
if [ "${1:-}" = --merge ]; then
  shift
  _hi_cov_merge_dest="$1" _hi_cov_merge_parts="$2"
  if ! command -v kcov >/dev/null 2>&1; then
    echo "::warning::kcov not installed - nothing to merge"
    exit 0
  fi
  shopt -s nullglob
  _hi_cov_merge_dirs=("$_hi_cov_merge_parts"/*)
  if [ "${#_hi_cov_merge_dirs[@]}" -eq 0 ]; then
    echo "::warning::no kcov shard parts were downloaded - nothing to merge"
    exit 0
  fi
  kcov --merge "$_hi_cov_merge_dest/merged" "${_hi_cov_merge_dirs[@]}"
  # Every file kcov traced, worst first - the same ranking a local sweep
  # prints below, reproduced here since this merge happens in CI's gather
  # job instead. Straight from kcov's merged JSON, where one object is one
  # line, and every value is a quoted string - see the ranking below for why
  # the percent is found by walking to the `percent_covered` key.
  _hi_cov_merge_json="$(find "$_hi_cov_merge_dest/merged" -name coverage.json | head -1)"
  if [ -n "$_hi_cov_merge_json" ]; then
    awk -F'"' '
      /"file"/ {
        for (i = 1; i < NF; i++)
          if ($i == "percent_covered") {
            printf " |   %6s%%  %5s/%-5s  %s\n", $(i + 2), $(i + 6), $(i + 10), $4
            break
          }
      }' "$_hi_cov_merge_json" | sort -n
  fi
  # A merge that resolved no sources still writes a well-formed report -
  # "files": [], run-wide 0.00 - and publishing that is worse than nothing:
  # a grey "not measured" badge reads as broken while 0.00% reads as true.
  if [ -z "$_hi_cov_merge_json" ] || ! grep -q '"file"' "$_hi_cov_merge_json"; then
    echo "::warning::the merge resolved no sources - no figure to publish"
    exit 0
  fi
  _hi_cov_merge_pct="$(sed -n 's/^[[:space:]]*"percent_covered"[[:space:]]*:[[:space:]]*"\{0,1\}\([0-9.]*\).*/\1/p' "$_hi_cov_merge_json" | tail -1)"
  case "$_hi_cov_merge_pct" in '' | *[!0-9.]*)
    echo "::warning::could not read percent_covered out of $_hi_cov_merge_json"
    exit 0
    ;;
  esac
  mkdir -p "$_hi_cov_merge_dest/coverage-pct"
  printf '%s\n' "$_hi_cov_merge_pct" >"$_hi_cov_merge_dest/coverage-pct/pct"
  echo "kcov reports ${_hi_cov_merge_pct}% of lines executed"
  exit 0
fi

if ! command -v kcov >/dev/null 2>&1; then
  _hi_cecho " | coverage: kcov not installed - skipping (a dev-only tool, and outside a PPA Debian/Ubuntu do not carry it: build it from github.com/SimonKagstrom/kcov, as CI does)" "$YELLOW"
  exit 0
fi

_hi_cov_shim_sh_to_bash

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
