#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# The repo's shellcheck run: every *.sh file, through shellcheck itself, with
# one precondition ahead of it that is fatal rather than counted.
#
# This is one of four suites the `lint` group runs; the others cover what
# this suite's own reading can't. dialects_test.sh runs the same files a
# non-bash shell parses for itself through that shell's own syntax checker
# (native, plus a pinned floor and ceiling build). tools_test.sh wraps shfmt,
# checkbashisms, mandoc and typos. drift_test.sh is the repo-consistency
# sweeps: the bash-3.2 grep, the $HOME default grep, GLOSSARY tags, the
# settings roster, Liquid syntax, and the tests/dockerfiles/ caller and
# image-tag checks. See each file's own header; all four are registered under
# `lint` in test_runner.sh's _HI_TESTS table.
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# A source of the user's config directory with no `# shellcheck source=`
# directive above it is a machine-killer, not a style nit, and this is what
# keeps one from landing again. It runs as a *precondition* of run_shellcheck
# rather than as one of the checks in the other three suites: the damage
# happens in the fan-out below, so a check that runs after it never gets the
# chance to speak.
#
# .shellcheckrc sets source-path=SCRIPTDIR, so under `shellcheck -x` the
# basename in a config-dir source resolves against the *sourcing file's own*
# directory. Where that basename is the file's own name - which is exactly what
# the per-shell overrides and settings/aliases.sh's own overlay are - the linter
# follows the file into itself and re-parses its source tree until the kernel
# stops it. Measured on this tree: ~33GB resident before a global OOM, twice,
# taking the editor down with the run. Neither the `[ -f ]` test nor the path
# comparison guarding those lines is visible to it; only the directive is.
#
# (No line of this comment may begin with the linter's own name followed by a
# space - that is the directive syntax, and prose there is a parse error.)
#
# Six lines of look-back because the guarded form spans an `&&` chain and the
# directive sits above the whole statement, not above the `source` token.
#
# The needle is split so this file does not match its own detector - the two
# halves are concatenated at run time and never appear adjacent in the source.
function lint_config_dir_sources() {
  local file needle rel stripped i n total ok bad=0
  local -a lines
  # shellcheck disable=SC2016 # a literal to match for, not an expansion
  needle='"$_HI_CONFIG'"_DIR/"
  _hi_h2 "Checking config-dir sources carry a shellcheck directive"
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  for file in "${_HI_SH_FILES[@]}"; do
    case "$(<"$file")" in *"$needle"*) ;; *) continue ;; esac
    _hi_read_lines lines <"$file"
    total="${#lines[@]}"
    for ((i = 0; i < total; i++)); do
      # leading whitespace off, comments skipped, and the dot form only where
      # `.` is a command: `grep -c . "$_HI_CONFIG_DIR/$f"` (scripts/doctor.sh)
      # is a regex dot and an argument, not a source, and matching it was this
      # check's first false positive.
      stripped="${lines[i]#"${lines[i]%%[![:space:]]*}"}"
      case "$stripped" in '#'*) continue ;; esac
      case "$stripped" in
      "source $needle"* | ". $needle"* | \
        *"&& source $needle"* | *"&& . $needle"* | \
        *"; source $needle"* | *"; . $needle"*) ;;
      *) continue ;;
      esac
      ok=""
      for ((n = 1; n <= 6 && i - n >= 0; n++)); do
        case "${lines[i - n]}" in
        *'# shellcheck source='*)
          ok=1
          break
          ;;
        esac
      done
      [ -n "$ok" ] && continue
      rel="${file#"$_HI_ROOT"/}"
      _hi_align " | $rel:$((i + 1)) sources the config dir with no 'shellcheck source=' above it" "FAILED" "$RED"
      _hi_note_failure "config-dir source: $rel:$((i + 1))"
      bad=$((bad + 1))
    done
  done
  [ "$bad" -eq 0 ] && _hi_align " | every config-dir source is directive-guarded" "OK" "$GREEN"
  return "$bad"
}

# The linter is the whole cost of `--group fast`, and it runs as one serial
# process: under -x it re-parses each file's entire sourced tree from scratch, so
# tests/test_lib.sh and the eight parts under tests/lib/ are analysed once per
# suite that sources them - most of the tree. The work is per-file and
# independent, so it fans out here the way tests/lib/parallel.sh fans out
# container cases: one shellcheck per file, $(_hi_sc_width) at a time, each
# writing its own output file so concurrent findings cannot interleave, replayed
# in the original order once the batch is done. Same tool, same flags, same
# bytes on the terminal - only the wall clock changes.
#
# The width is the whole CPU count rather than _hi_par_width's cap of four: that
# cap is there because a container case is a docker daemon and an sshd, where
# this is pure CPU and a few MB resident. $_HI_SC_WIDTH overrides it, and
# _HI_SC_WIDTH=1 is the serial run down this same code path.
#
# Raising it past the CPU count is not the lever it looks like. Measured on an
# 8-core box: 1 -> 60s, 2 -> 47s, 4 -> 41s, 8 -> 40s, and 12/16/24/32 all sit at
# 38-39s, which is run-to-run noise. What flattens the curve is -x re-parsing,
# not scheduling - see _hi_sc_chunks below, which is where the time actually
# went.
function _hi_sc_width() {
  local cpus
  if [ -n "${_HI_SC_WIDTH:-}" ]; then
    printf '%s' "$_HI_SC_WIDTH"
    return 0
  fi
  cpus="$(_hi_host_cores)"
  [ -n "$cpus" ] || cpus=2
  [ "$cpus" -lt 1 ] && cpus=1
  printf '%s' "$cpus"
}

# _hi_sc_chunks <outdir> <width> <file...> - the file list dealt into <width>
# chunks, printed as "<outdir>/<n>\0<file>\0<file>...\0\n" - one line per chunk,
# which is the argv one shellcheck invocation gets.
#
# Chunks rather than one process per file, and the difference is not small: under
# -x a single invocation parses each sourced file once and reuses it for every
# file in that invocation, so 130 one-file runs re-parse test_lib.sh and its
# parts 130 times and spend triple the CPU to save half the wall clock.
#
# The same argument decides how the files are *dealt*, and it points the
# opposite way to load balancing. Dealing file by file with round-robin would
# spread tests/ evenly but make all eight invocations parse test_lib.sh and
# its parts - eight times the work one invocation would do. Dealing whole
# top-level directories instead keeps every file that shares a sourced tree in
# the same invocation, so that tree is parsed once. Measured at width 8: 42-45s
# by file, 32s by directory, repeatably.
#
# Chunks are *deliberately* unbalanced as a result - tests/ is 47 of 75 files
# and lands whole in one of them, which is also the run's critical path. That is
# the trade: an even split costs more total CPU than the idle cores save, and
# splitting tests/ by subdirectory (each of which sources test_lib.sh too) times
# at 36-37s, between the two. It also means width past the number of top-level
# directories buys nothing at all - there is no tenth group to hand a ninth
# core.
function _hi_sc_chunks() {
  local out="$1" width="$2" i=0 f rel top idx seen="" s
  shift 2
  for f in "$@"; do
    # $_HI_ROOT-relative, so the group is the top-level directory - and a
    # root-level file (hi.sh, load.sh) is its own group, which is right: it
    # shares a sourced tree with nothing.
    rel="${f#"$_HI_ROOT"/}"
    top="${rel%%/*}"
    case " $seen " in
    *" $top "*) ;;
    *) seen="$seen $top" ;;
    esac
    # the group's position in $seen is its chunk - first seen, first chunk,
    # which keeps the deal stable for a given (sorted) file list
    idx=0
    # shellcheck disable=SC2086 # deliberate split: $seen is a space-joined list
    for s in $seen; do
      [ "$s" = "$top" ] && break
      idx=$((idx + 1))
    done
    printf '%s\0' "$f" >>"$out/chunk.$((idx % width))"
  done
  i=0
  while [ "$i" -lt "$width" ]; do
    [ -s "$out/chunk.$i" ] && printf '%s\n' "$i"
    i=$((i + 1))
  done
}

# _hi_shellcheck_all <log> <file...> - every file checked, concatenated into
# <log> in the order given. Non-zero when any file had findings, exactly as a
# single shellcheck over the whole list would be.
function _hi_shellcheck_all() {
  local log="$1" out width rc=0 i
  shift
  width="$(_hi_sc_width)"
  out="$_HI_WORKDIR/sc.out"
  rm -rf "$out"
  mkdir -p "$out"

  _hi_read_lines _HI_SC_CHUNKS < <(_hi_sc_chunks "$out" "$width" "$@")

  # one invocation per chunk, each writing its own file so concurrent findings
  # cannot interleave; replayed in chunk order once the batch is done
  # ($1 below expands in the child sh, which is the point - SC2016.)
  # shellcheck disable=SC2016
  printf '%s\0' ${_HI_SC_CHUNKS[@]+"${_HI_SC_CHUNKS[@]}"} |
    (cd "$out" && xargs -0 -n 1 -P "$width" \
      sh -c 'xargs -0 shellcheck -x -Calways -S style <"chunk.$1" >"out.$1" 2>&1' sh) || rc=$?

  : >"$log"
  for i in ${_HI_SC_CHUNKS[@]+"${_HI_SC_CHUNKS[@]}"}; do
    [ -s "$out/out.$i" ] && cat "$out/out.$i" >>"$log"
  done
  return "$rc"
}

function run_shellcheck() {
  # deliberately *not* _hi_require: every other suite skips cleanly when its
  # backend is missing, but this one is the lint gate - a missing shellcheck
  # means the check didn't run, which must not read as a pass.
  if ! command -v shellcheck >/dev/null 2>&1; then
    _hi_cecho "shellcheck is not installed" "$RED"
    exit 1
  fi

  # the .git/dist exclusions and why they are there live on _hi_lint_find
  # (tests/lib/lint.sh), which drift_test.sh's lint_home_default reads through
  # too
  _hi_read_lines _HI_SH_FILES < <(_hi_lint_find -name '*.sh')
  _HI_LINT_TOTAL="${#_HI_SH_FILES[@]}"
  _HI_SKIPPED=0

  _hi_h1 "Running shellcheck on ${#_HI_SH_FILES[@]} files"
  _hi_h2 "Version: $(shellcheck --version | awk '/^version:/ {print $2}')"

  _hi_cecho "$(printf ' | %s\n' "${_HI_SH_FILES[@]}")" "$BLUE"

  # Before the fan-out, and fatal - not one of the checks the sibling suites
  # run. A config-dir source with no directive makes the very next step
  # recurse into itself until the kernel OOM-kills it, so a check that reports
  # afterwards reports only when there is nothing to report. Ordering is the
  # whole value of this check.
  if ! lint_config_dir_sources; then
    _hi_cecho " | refusing to run shellcheck: the files above would make it" "$RED"
    _hi_cecho " | re-parse itself until the machine runs out of memory" "$RED"
    exit 1
  fi

  _hi_workdir shellchecktest
  _HI_SC_LOG="$_HI_WORKDIR/shellcheck.log"

  _HI_T0="$(_hi_now)"

  _HI_SC_FAILED=0
  _HI_SC_RC=0
  _hi_shellcheck_all "$_HI_SC_LOG" "${_HI_SH_FILES[@]}" || _HI_SC_RC=$?
  cat "$_HI_SC_LOG"
  if [ "$_HI_SC_RC" -ne 0 ]; then
    # -Calways leaves ANSI codes in $_HI_SC_LOG (needed for the colorized
    # output above), so they have to be stripped before "^In " can match
    _HI_SC_FAILED=$(_hi_strip_ansi "$(<"$_HI_SC_LOG")" | grep -oE '^In .* line [0-9]+:' | sed -E 's/^In (.*) line [0-9]+:/\1/' | sort -u | wc -l)
    _hi_note_failure "shellcheck: $_HI_SC_FAILED file(s) with findings"
  fi

  _HI_LINT_FAILED=$_HI_SC_FAILED
  _hi_lint_suite_end
}

run_shellcheck
