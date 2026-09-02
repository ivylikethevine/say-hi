#!/usr/bin/env bash
# The lint infra more than one tests/lint/*_test.sh needs: the file-listing
# sweep, and the counted-file suite protocol (begin/halves/end below) that
# every lint suite reports through. run_shellcheck (shellcheck_test.sh) uses
# the sweep to build the *.sh list shellcheck itself reads, and
# lint_bash32/lint_home_default/lint_liquid_docs (drift_test.sh) use it
# through _hi_lint_mirror and _hi_jekyll_md_files. Different suites, different
# processes - GLOSSARY: HI.34 says a suite sources test_lib.sh and nothing
# else, so a helper more than one of them needs lives here instead of being
# copied.
#
# Part of the tests/test_lib.sh harness; sourced by it, never on its own.
# shellcheck disable=SC2329

# _hi_lint_find <find-name-expr...> - the files a lint sweeps. The exclusions
# live here, not at each caller: packaging/mkpkg.sh stages a *copy* of the tree
# under dist/, so a run after a local package build would lint everything twice
# and report against paths that are not the source. .claude/ is agent scratch.
function _hi_lint_find() {
  find "$_HI_ROOT" \( "$@" \) -not -path '*/.git/*' \
    -not -path "$_HI_ROOT/dist/*" -not -path "$_HI_ROOT/.claude/*" | sort
}

# The counted-file suite protocol - the lint twin of report.sh's
# _hi_suite_begin/_hi_suite_end, reporting files where those report cases.
# A lint suite opens with _hi_lint_suite_begin (or, like shellcheck_test.sh,
# derives $_HI_LINT_TOTAL its own way), runs its halves, and closes with
# _hi_lint_suite_end. The counts line the end helper prints is parsed by
# test_runner.sh's collector, so its format moves only in lockstep with
# _hi_report_counts' readers.

# _hi_lint_suite_begin <banner> - zero the file counters, start the clock,
# print the suite heading.
function _hi_lint_suite_begin() {
  _HI_LINT_TOTAL=0
  _HI_LINT_FAILED=0
  _HI_SKIPPED=0
  _HI_T0="$(_hi_now)"
  _hi_h1 "$1"
}

# _hi_lint_halves <fn...> - run each lint half, folding its return value into
# $_HI_LINT_FAILED.
function _hi_lint_halves() {
  local _hi_lint_half
  for _hi_lint_half in "$@"; do
    "$_hi_lint_half" || _HI_LINT_FAILED=$((_HI_LINT_FAILED + $?))
  done
}

# _hi_lint_suite_end - the counts line plus the closing banner; exits with the
# failed-file count when there is anything to report.
function _hi_lint_suite_end() {
  _hi_report_counts "$_HI_LINT_TOTAL" "$_HI_LINT_FAILED" "$_HI_SKIPPED"

  local skipped=""
  [ "$_HI_SKIPPED" -gt 0 ] && skipped=", $_HI_SKIPPED skipped"
  if [ "$_HI_LINT_FAILED" -eq 0 ]; then
    _hi_h1 "Found no issues ($_HI_LINT_TOTAL files$skipped, $(_hi_elapsed "$_HI_T0" "$(_hi_now)")s)" "$BRGREEN"
  else
    _hi_h1 "Found issues: $_HI_LINT_FAILED/$_HI_LINT_TOTAL files$skipped ($(_hi_elapsed "$_HI_T0" "$(_hi_now)")s)" "$RED"
    exit "$_HI_LINT_FAILED"
  fi
}
