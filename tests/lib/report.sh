#!/usr/bin/env bash
# The counted case and everything a suite prints: _hi_case tallies, _hi_assert
# reports, _hi_check does both; the aligned status line they print through,
# the begin/end banners, the skip and failure ledgers the runner reads, and
# the host report.
#
# Part of the tests/test_lib.sh harness; sourced by it, never on its own.
# GLOSSARY: HI.30
# shellcheck disable=SC2329

# _hi_align <left> <right> [color] - a status line with <right> at
# _HI_MAX_WIDTH, so every verdict lines up. <left> includes its prefix; a long
# one overflows, keeping at least two spaces before <right>.
function _hi_align() {
  local left="$1" right="$2" pad line floor=$((${#2} + 2))
  pad=$((${_HI_MAX_WIDTH:-80} - ${#left}))
  ((pad < floor)) && pad=$floor
  # printf -v, not $( ): this runs once per verdict line, hundreds a run
  printf -v line '%s%*s' "$left" "$pad" "$right"
  _hi_cecho "$line" "${3:-}"
}

# Runs "$@" as one sub-case of a multi-case test file (one shell, one
# container shape, one scenario, ...), bumping the caller's _HI_TOTAL/
# _HI_FAILED counters accordingly. Set both to 0 via _hi_suite_begin before
# the first case runs, so _hi_suite_end can report "$_HI_FAILED/$_HI_TOTAL
# cases failed" instead of a bare pass/fail.
function _hi_case() {
  local _hi_cs_t0=$SECONDS _hi_cs_l
  # its label where _hi_assert or _hi_expect_eq ran it, else its command
  case "$1" in _hi_assert | _hi_expect_eq) _hi_cs_l="${2:-}" ;; *) _hi_cs_l="$*" ;; esac
  _hi_note_case "$_hi_cs_l"
  _HI_TOTAL=$((_HI_TOTAL + 1))
  "$@" || _HI_FAILED=$((_HI_FAILED + 1))
  _hi_note_time $((SECONDS - _hi_cs_t0)) "$_hi_cs_l"
  _hi_report_progress
}

# _hi_note_case <label> - the case about to run, beside the progress file:
# what the runner's progress line names a running suite by, and what it names
# a suite that hangs by. One write and no fork, and never a failure.
function _hi_note_case() {
  [ -n "${_HI_PROGRESS_FILE:-}" ] || return 0
  printf '%s\n' "${1:0:100}" 2>/dev/null >"$_HI_PROGRESS_FILE.case" || :
}

# _hi_note_time <seconds> <label> - a case that took a second or more, beside
# the failures file, for the runner's "Slowest cases": a suite's time says
# nothing of which case spent it. $SECONDS, so whole seconds and no fork; the
# cases under one are the many and are not written.
function _hi_note_time() {
  [ -n "${_HI_FAILS_FILE:-}" ] && [ "$1" -ge 1 ] || return 0
  printf '%s\t%s\n' "$1" "${2:0:100}" >>"$_HI_FAILS_FILE.times"
}

# The fixed predicates every harness suite's own cases feed _hi_check/
# _hi_assert/_hi_par_case to prove the assertion machinery itself - a
# HI.34 case for the helper more than one suite needs living here instead
# of being copied.
function _hi_true() { return 0; }
function _hi_false() { return 1; }

# _hi_because <text> - says on stderr why a case fails, beside its FAILED
# line, and fails it; one line where `|| { echo ...; return 1; }` would be
# four after shfmt.
function _hi_because() {
  printf '%s\n' "$1" >&2
  return 1
}

# _hi_prints <want> <cmd...> - a case whose whole claim is one command's output.
# Its status is no part of the claim, but this one and its twins below refuse
# 127: a subject that does not exist prints nothing, which an empty <want> and
# a negative claim would otherwise read as a pass.
function _hi_prints() {
  local want="$1" got rc=0
  shift
  got="$("$@")" || rc=$?
  [ "$rc" != 127 ] && [ "$got" = "$want" ] || _hi_because "from: $* - exit $rc, wanted [$want], got [$got]"
}

# _hi_says <phrase> <cmd...> - ...that its output holds <phrase>
function _hi_says() {
  local phrase="$1" out rc=0
  shift
  out="$("$@" 2>&1)" || rc=$?
  [ "$rc" != 127 ] && [[ "$out" == *"$phrase"* ]] || _hi_because "from: $* - exit $rc, wanted [$phrase] in [$out]"
}

# _hi_var_is <want> <fn> [arg...] - ...that <fn>, as `<fn> <outvar> [arg...]`,
# leaves <want> in its out-var, with no fork
function _hi_var_is() {
  local _hi_vi="" rc=0
  "$2" _hi_vi "${@:3}" || rc=$?
  [ "$rc" != 127 ] && [ "$_hi_vi" = "$1" ] || _hi_because "from: ${*:2} - exit $rc, wanted [$1], got [$_hi_vi]"
}

# _hi_case_failed <label> <why> [transcript] - a target case's red heading, its
# transcript, and the reason named for the runner's recap
function _hi_case_failed() {
  _hi_h3 " | [$1] -- FAILED: $2" "$RED"
  [ -z "${3:-}" ] || _hi_show_transcript "the session's transcript" "$3"
  _hi_note_failure "[$1] $2"
}

# _hi_refused <phrase> <cmd...> - a case whose claim is a refusal: exit 1, with
# <phrase> in what it said
function _hi_refused() {
  local phrase="$1" out rc=0
  shift
  out="$("$@" 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"$phrase"* ]] || _hi_because "from: $* - exit $rc, wanted [$phrase], got [$out]"
}

# _hi_why [-N] [name...] - _hi_because with no words of its own: the failed
# statement from the suite's file (and N lines above, for a bare `return 1`)
# and each named variable, cut at 300 characters. Only on failure.
function _hi_why() {
  local _hi_w_file="${BASH_SOURCE[1]:-}" _hi_w_line="${BASH_LINENO[0]:-0}" _hi_w_text="" _hi_w_n _hi_w_v _hi_w_cut _hi_w_up=0
  case "${1:-}" in -[0-9]*)
    _hi_w_up="${1#-}"
    shift
    ;;
  esac
  if [ -r "$_hi_w_file" ]; then
    _hi_w_text="$(awk -v n="$_hi_w_line" -v up="$_hi_w_up" '
      NR > n - 8 - up && NR <= n { buf[NR] = $0 }
      END {
        s = n
        while (((s - 1) in buf) && buf[s - 1] ~ /(\|\||&&|\\|\|)[ \t]*$/) s--
        for (i = s - up; i < s; i++) if (i in buf) printf "%s\n       ", buf[i]
        for (i = s; i <= n; i++) {
          sub(/^[ \t]+/, "", buf[i])
          printf "%s%s", (i > s ? " " : ""), buf[i]
        }
      }' "$_hi_w_file" 2>/dev/null)" || _hi_w_text=""
  fi
  printf '      not so, at %s:%s: %s\n' "${_hi_w_file##*/}" "$_hi_w_line" "${_hi_w_text:0:700}" >&2
  for _hi_w_n in "$@"; do
    case "$_hi_w_n" in '' | [0-9]* | *[!A-Za-z0-9_]*) continue ;; esac
    _hi_w_v="${!_hi_w_n-<unset>}"
    _hi_w_cut=""
    [ "${#_hi_w_v}" -le 300 ] || _hi_w_cut=" (${#_hi_w_v} characters, cut)"
    printf '        %s=[%s]%s\n' "$_hi_w_n" "${_hi_w_v:0:300}" "$_hi_w_cut" >&2
  done
  return 1
}

function _hi_assert() {
  local label="$1" t0=$SECONDS _HI_WORKDIR="$_HI_WORKDIR"
  shift
  if ! _hi_case_workdir; then
    _hi_align " | $label" "FAILED" "$RED"
    printf '      no directory of its own could be made under %s\n' "$_HI_SUITE_WORKDIR" >&2
    _hi_note_failure "$label"
    return 1
  fi
  if "$@"; then
    _hi_rerun_holds "$label" "$@" || return 1
    _hi_align " | $label" "OK" "$GREEN"
    return 0
  fi
  # a failed case is run once more, traced (_hi_trace_rerun): a pass the
  # second time is a flake - FLAKY in yellow, noted for the runner's recap,
  # and not a failure - and a second failure is FAILED with the trace's tail
  [ "${_HI_TRACE_RERUN:-1}" != 1 ] || ! _hi_flaky_allowed || _hi_pipe_probe
  _hi_case_workdir || :
  if _hi_trace_rerun $((SECONDS - t0)) "$@"; then
    if _hi_flaky_allowed; then
      _hi_align " | $label" "FLAKY" "$YELLOW"
      printf '      failed once, passed on a traced rerun - not counted as a failure\n' >&2
      _hi_note_flaky "$label"
      return 0
    fi
    _hi_align " | $label" "FLAKY" "$RED"
    printf '      failed once, passed on a traced rerun - a failure on native Linux x64, which allows no flakes\n' >&2
    _hi_note_failure "$label (flaky, and Linux x64 allows none)"
    return 1
  fi
  _hi_align " | $label" "FAILED" "$RED"
  _hi_note_failure "$label"
  [ -z "$_HI_RERUN_OUT" ] || printf '%s\n' "$_HI_RERUN_OUT" >&2
  return 1
}

# _hi_case_workdir - a fresh, empty $_HI_WORKDIR for one try of one case
# (a rerun gets its own, so a flake can pass); shared setup goes in
# $_HI_SUITE_WORKDIR. `mkdir` of a counted name, not `$(mktemp -d)`, whose
# empty capture on Windows arm64 would aim the case at /; a taken name is
# retried.
_HI_CASE_SEQ=0
function _hi_case_workdir() {
  local try
  [ -n "${_HI_SUITE_WORKDIR:-}" ] || return 0
  for try in 1 2 3 4 5; do
    _HI_CASE_SEQ=$((_HI_CASE_SEQ + 1))
    _HI_WORKDIR="$_HI_SUITE_WORKDIR/case.$_HI_CASE_SEQ.$RANDOM"
    mkdir "$_HI_WORKDIR" 2>/dev/null && return 0
  done
  return 1
}

# _hi_rerun_holds <label> <case...> - under $_HI_RERUN_CHECK=1, reruns a passed
# case as its traced rerun would; a failure means its first try changed state
# outside its directory, so a flake could never pass. Doubles a run's time.
function _hi_rerun_holds() {
  local label="$1"
  shift
  [ "${_HI_RERUN_CHECK:-0}" = 1 ] || return 0
  _hi_case_workdir || :
  ("$@") >/dev/null 2>&1 && return 0
  _hi_align " | $label" "FAILED" "$RED"
  printf '      passed, then failed a second run: its first try changed something outside its directory, so its traced rerun could never pass\n' >&2
  _hi_note_failure "$label (fails a second run)"
  return 1
}

# _hi_trace_rerun <seconds-it-took> <case...> - reruns a failed case under
# `set -x`, in a subshell and fresh directory, leaving the trace's tail in
# $_HI_RERUN_OUT. 0 when it passed (a flake), else 1. A failure over 30s is
# rerun in the background and cut off after that time plus 30s, for the trace
# alone: a slow failure is never a flake. Off under $_HI_TRACE_RERUN=0 (the
# coverage sweeps own xtrace). A passing case pays nothing.
_HI_RERUN_OUT=""
function _hi_trace_rerun() {
  local took="$1" out rc=0
  shift
  _HI_RERUN_OUT=""
  if [ "${_HI_TRACE_RERUN:-1}" != 1 ]; then
    _HI_RERUN_OUT="      (no trace here: a coverage tracer owns xtrace; the fast suites job of this commit runs the case with one)"
    return 1
  fi
  if [ "$took" -gt 30 ]; then
    _hi_trace_rerun_slow "$took" "$@"
    return
  fi
  out="$(_hi_traced "$@")" || rc=$?
  [ "$rc" = 0 ] && return 0
  _HI_RERUN_OUT="      traced rerun (exit $rc), its last lines:"$'\n'"$(printf '%s\n' "$out" | tail -n 40 | sed 's/^/      /')"
  return 1
}

# _hi_traced <case...> - the case under set -x, its trace beside its output;
# only ever in a subshell. xtrace on fd 9, a copy of the capture: on stderr it
# would land in every `$(... 2>&1)` the case makes, and a case that reads its
# own stderr would fail the rerun on the trace alone and never count as a
# flake (bash 3.2 has no BASH_XTRACEFD and keeps tracing to stderr)
function _hi_traced() {
  PS4='+ ${BASH_SOURCE[0]##*/}:${LINENO}: '
  exec 9>&1
  BASH_XTRACEFD=9
  {
    set -x
    "$@"
  } 2>&1
}

# ...the slow failure's: the same rerun as a job of its own, on this shell's
# stdin, its trace in a file under the suite's work directory. Always false.
function _hi_trace_rerun_slow() {
  local took="$1" limit t0=$SECONDS file="${_HI_WORKDIR:-${TMPDIR:-/tmp}}/hi.rerun.$$"
  shift
  limit=$((took + 30))
  _hi_traced "$@" <&0 >"$file" 2>&1 &
  _hi_wait_pid "$!" "$limit"
  if [ "$_HI_WAIT_EXIT" = 124 ]; then
    _HI_RERUN_OUT="      traced rerun, ended at ${limit}s (the failure took ${took}s) - where it stood, its last lines:"
  elif [ "$_HI_WAIT_EXIT" = 0 ]; then
    _HI_RERUN_OUT="      traced rerun passed in $((SECONDS - t0))s where the failure took ${took}s - a slow failure is a failure, never a flake; the pass's last lines:"
  else
    _HI_RERUN_OUT="      traced rerun (exit $_HI_WAIT_EXIT, the failure took ${took}s), its last lines:"
  fi
  _HI_RERUN_OUT="$_HI_RERUN_OUT"$'\n'"$(tail -n 40 "$file" 2>/dev/null | sed 's/^/      /')"
  rm -f "$file"
  return 1
}

# _hi_pipe_probe - one stderr line on whether this host is losing output now
# (20 rounds each of subshell, child bash, process substitution, and file
# writes), with the runtime and load, before a failed case's rerun. Windows
# arm64's flakes are captures that come back empty.
function _hi_pipe_probe() {
  local i got want=0123456789abcdef sub=0 child=0 psub=0 file=0 died=0 f="${_HI_WORKDIR:-${TMPDIR:-/tmp}}/pipe-probe" load=""
  for ((i = 0; i < 20; i++)); do
    got="$(printf '%s' "$want")" || died=$((died + 1))
    [ "$got" = "$want" ] || sub=$((sub + 1))
    got="$("$BASH" -c 'printf 0123456789abcdef')" || died=$((died + 1))
    [ "$got" = "$want" ] || child=$((child + 1))
    got=""
    IFS= read -r got < <(printf '%s\n' "$want") || :
    [ "$got" = "$want" ] || psub=$((psub + 1))
    got=""
    "$BASH" -c 'printf "0123456789abcdef\n"' >"$f" 2>/dev/null || died=$((died + 1))
    IFS= read -r got <"$f" 2>/dev/null || :
    [ "$got" = "$want" ] || file=$((file + 1))
  done
  [ ! -r /proc/loadavg ] || IFS= read -r load </proc/loadavg || :
  printf '      output probe, short of 20: subshell %s, child bash %s, process substitution %s, child bash to a file %s; %s exited non-zero (%s%s)\n' \
    "$sub" "$child" "$psub" "$file" "$died" "$(uname -srm 2>/dev/null || true)" "${load:+, load $load}" >&2
}

# _hi_flaky_allowed - whether a flake may pass: everywhere but native Linux
# x64, where a second try means shaky code. $_HI_FLAKY_OK (1/0) overrides.
_HI_FLAKY_OK_MEMO=""
function _hi_flaky_allowed() {
  if [ -z "$_HI_FLAKY_OK_MEMO" ]; then
    _HI_FLAKY_OK_MEMO=1
    case "$(uname -s 2>/dev/null)/$(uname -m 2>/dev/null)/$(uname -r 2>/dev/null)" in
    *[Mm]icrosoft* | *WSL*) ;;
    Linux/x86_64/*) _HI_FLAKY_OK_MEMO=0 ;;
    esac
  fi
  [ "${_HI_FLAKY_OK:-$_HI_FLAKY_OK_MEMO}" = 1 ]
}

# _hi_note_flaky <label> - a case that failed and then passed on its rerun,
# beside the failures file, for the runner's "Flaky cases" recap
function _hi_note_flaky() {
  [ -n "${_HI_FAILS_FILE:-}" ] || return 0
  printf '%s\n' "$1" >>"$_HI_FAILS_FILE.flaky"
}

# _hi_run_said [--both] <what> <cmd...> - runs a program that always prints,
# through a file, keeping its status. A silent run (Windows arm64 ends some
# early with 0) is retried once where flakes may pass and listed as <what>
# under "Flaky cases"; one silent twice is named on stderr.
function _hi_run_said() {
  local both=0 what said rc try
  [ "$1" != --both ] || {
    both=1
    shift
  }
  what="$1"
  shift
  said="$(mktemp "${_HI_WORKDIR:-${TMPDIR:-/tmp}}/said.XXXXXX")" || said=""
  if [ -z "$said" ]; then
    "$@"
    return
  fi
  for try in 1 2; do
    rc=0
    if [ "$both" = 1 ]; then
      "$@" >"$said" 2>&1 || rc=$?
    else
      "$@" >"$said" || rc=$?
    fi
    [ ! -s "$said" ] || break
    [ "$try" = 1 ] || break
    _hi_flaky_allowed || break
    _hi_note_flaky "$what wrote nothing (exit $rc), and was run again"
  done
  [ -s "$said" ] || printf ' | %s wrote nothing and exited %s\n' "$what" "$rc" >&2
  cat "$said"
  rm -f "$said"
  return "$rc"
}

# _hi_check <label> <predicate...> - one counted, labelled assertion.
function _hi_check() {
  _hi_case _hi_assert "$@"
}

# the third rule weight, below scripts/lib.sh's _hi_h1/_hi_h2 - suites only
function _hi_h3() {
  _hi_hrule "$1" '~' 3 "${2:-$BRPURPLE}"
}

function _hi_suite_begin() {
  _HI_FAILED=0
  _HI_TOTAL=0
  _HI_SKIPPED=0
}

# One case the suite could not run (no python3 for a pty, say), counted so
# the banner says how much ran; _hi_report_skip is the whole suite. Under
# --require-run it is also reported as a failure here, where the label and
# reason are at hand, while still tallied as a skip; _hi_suite_end turns the
# count into the verdict (a parallel case's _HI_SKIPPED returns through its
# verdict file).
function _hi_skip() {
  _HI_SKIPPED=$((${_HI_SKIPPED:-0} + 1))
  if [ "${_HI_REQUIRE_RUN:-0}" = 1 ]; then
    _hi_align " | $1" "SKIPPED${2:+ ($2)}" "$RED"
    _hi_note_failure "$1 stood down${2:+ ($2)}, and --require-run was given"
    return 0
  fi
  _hi_align " | $1" "SKIPPED${2:+ ($2)}" "$YELLOW"
}

# _hi_report_counts <total> <failed> [skipped] - the suite's tally for the
# runner's summary, through $_HI_COUNTS_FILE (a no-op outside the runner; a
# suite that never reports shows "-"). Lint suites use _hi_lint_suite_end.
function _hi_report_counts() {
  [ -n "${_HI_COUNTS_FILE:-}" ] || return 0
  printf '%s %s %s\n' "$1" "$2" "${3:-0}" >"$_HI_COUNTS_FILE"
}

# _hi_report_progress - the tally so far, in _hi_report_counts' format, to
# $_HI_PROGRESS_FILE after every case: what the runner's progress line counts
# a still-running suite by. A no-op outside the runner, like its twin, and
# never a failure: a lost update only costs the progress line a tick.
function _hi_report_progress() {
  [ -n "${_HI_PROGRESS_FILE:-}" ] || return 0
  printf '%s %s %s\n' "$_HI_TOTAL" "${_HI_FAILED:-0}" "${_HI_SKIPPED:-0}" 2>/dev/null >"$_HI_PROGRESS_FILE" || :
}

# _hi_note_failure <label> - the failing case's name, up to the runner, which
# repeats every suite's under its summary table so finding what broke never
# means scrolling back through the whole transcript. Same no-op-when-standalone
# rule as _hi_report_counts.
function _hi_note_failure() {
  [ -n "${_HI_FAILS_FILE:-}" ] || return 0
  printf '%s\n' "$1" >>"$_HI_FAILS_FILE"
}

# _hi_note_failure_unless_named <label> <text> - the parallel path's backstop
# for a case that died before naming itself; one already named (as "[label]"
# by _hi_case_result or bare by _hi_assert) is not listed twice.
function _hi_note_failure_unless_named() {
  [ -n "${_HI_FAILS_FILE:-}" ] || return 0
  grep -qxF "$1" "$_HI_FAILS_FILE" 2>/dev/null && return 0
  grep -qF "[$1]" "$_HI_FAILS_FILE" 2>/dev/null && return 0
  _hi_note_failure "$2"
}

# _hi_expect_eq <label> <want> <cmd...> - _hi_assert's twin for a value rather
# than a predicate: runs <cmd> and compares its stdout to <want>, printing
# both quoted on failure so empties and trailing newlines show.
# _hi_check_eq and _hi_par_check_eq wrap it.
function _hi_expect_eq() {
  local label="$1" want="$2" got rc=0
  shift 2
  # the status kept aside, because the assertion is about what <cmd> *printed*
  # (a plain assignment would hand it to `set -e` and lose the diagnostic in
  # the one case it exists for); 127 alone counts, as in _hi_prints
  got="$("$@")" || rc=$?
  if [ "$rc" != 127 ] && [ "$got" = "$want" ]; then
    _hi_align " | $label" "OK" "$GREEN"
    return 0
  fi
  _hi_align " | $label" "FAILED" "$RED"
  _hi_cecho "      want: \"$want\"" "$RED"
  _hi_cecho "      got:  \"$got\" (exit $rc)" "$RED"
  _hi_note_failure "$label"
  return 1
}

# _hi_dump_log <message> <file> [color] - a failure line and the output that
# explains it: the text, never the path, which the exit trap removes. Raw, at
# a six-space indent, into the case's stdout.
function _hi_dump_log() {
  local msg="$1" file="$2" color="${3:-$RED}"
  _hi_cecho " | $msg" "$color"
  if [ -s "$file" ]; then
    sed 's/^/      /' "$file" 2>/dev/null
  else
    _hi_cecho "      (the command wrote nothing)" "$color"
  fi
}

# _hi_show_transcript <title> <file> [lines] - the end of a session's
# transcript under a failure line, at _hi_dump_log's indent, with the cursor
# moves, clears, and titles a prompt or a multiplexer wrote taken out so the
# dump reads as text and does not redraw the terminal it lands on. Says so
# where there is none: an empty transcript is a finding too.
function _hi_show_transcript() {
  local n="${3:-60}" tail
  if [ ! -s "$2" ]; then
    printf '      %s: nothing was written (%s)\n' "$1" "$2"
    return 0
  fi
  printf '      %s, its last %s lines:\n' "$1" "$n"
  tail="$(tail -n "$n" "$2" | tr -d '\r')"
  _hi_strip_ansi "$tail" | sed 's/^/        /' || true
}

# _hi_show_target <container> - what a target holds when a case about its
# sessions or its trees fails: hi's trees and the claims in them, the
# multiplexers' sessions, and the account's processes. Read off the
# container, so it is the state the assertion saw and not a guess at it.
function _hi_show_target() {
  [ -n "${1:-}" ] || return 0
  printf '      the target (%s) at the failure:\n' "$1"
  # shellcheck disable=SC2016 # the container's sh expands it
  "${_HI_BACKEND:-docker}" exec "$1" sh -c '
    echo "trees:"
    ls -ld /tmp/*.hi.* /tmp/hi.boot.* 2>/dev/null || echo "  (none)"
    for f in /tmp/*.hi.*/say-hi/hi.kept /tmp/*.hi.*/say-hi/hi.pid /tmp/*.hi.*/say-hi/hi.held /tmp/*.hi.*/say-hi/hi.hold /tmp/*.hi.*/say-hi/hi.cwd; do
      [ -e "$f" ] && echo "  $f: $(cat "$f" 2>&1)"
    done
    echo "sessions:"
    { command -v tmux >/dev/null 2>&1 && su hitest -c "tmux list-sessions" 2>&1; } | sed "s/^/  tmux: /"
    { command -v zellij >/dev/null 2>&1 && su hitest -c "zellij ls -n" 2>&1; } | sed "s/^/  zellij: /"
    { command -v screen >/dev/null 2>&1 && su hitest -c "screen -ls" 2>&1; } | sed "s/^/  screen: /"
    echo "processes:"
    ps -eo pid,ppid,user,args 2>/dev/null || ps
  ' 2>&1 | head -n 80 | sed 's/^/        /' || true
}

# _hi_report_skip <reason> - the same channel, saying "this suite ran nothing"
# rather than a tally. A skipped suite exits 0, so without this the runner
# would render it a green PASS and a run could report every suite passing
# while several of them never executed a case. Same no-op-when-standalone
# rule as _hi_report_counts.
function _hi_report_skip() {
  [ -n "${_HI_COUNTS_FILE:-}" ] || return 0
  printf 'SKIP %s\n' "$1" >"$_HI_COUNTS_FILE"
}

# The tally, closing banner, and exit status (the runner's PASS or FAILED).
# Under --require-run a skip fails the status, though the counts still say
# skip. The banner and status share $_hi_bad.
function _hi_suite_end() {
  local subject="$1" skipped="" bad="$_HI_FAILED" stood_down=""
  [ "${_HI_SKIPPED:-0}" -gt 0 ] && skipped=", ${_HI_SKIPPED} skipped"
  _hi_report_counts "$_HI_TOTAL" "$_HI_FAILED" "${_HI_SKIPPED:-0}"
  if [ "${_HI_REQUIRE_RUN:-0}" = 1 ] && [ "${_HI_SKIPPED:-0}" -gt 0 ]; then
    bad=$((bad + _HI_SKIPPED))
    stood_down=" (${_HI_SKIPPED} more stood down, and --require-run was given)"
  fi
  if [ "$bad" -eq 0 ]; then
    _hi_h1 "${2:-All $subject checks passed ($_HI_TOTAL cases$skipped)}" "$BRGREEN"
  elif [ "$_HI_FAILED" -eq 0 ]; then
    # nothing failed an assertion - the verdict is entirely --require-run's,
    # so it says so rather than borrowing the caller's failure banner, which
    # would report cases that never ran as cases that broke
    _hi_h1 "${_HI_SKIPPED} of $subject's cases stood down, and --require-run was given" "$RED"
  else
    _hi_h1 "${3:-$_HI_FAILED/$_HI_TOTAL $subject checks FAILED}$stood_down" "$RED"
  fi
  exit "$bad"
}

# _hi_stand_down <reason> [message] - the whole suite stops here, honestly:
# yellow note, SKIP reported to the runner, exit 0. _hi_require_bin covers
# requirements known at startup; this is also for *runtime* failures (an image
# that didn't build, a cluster that never came up), which must report a skip
# rather than exiting 0 unreported and painting the suite green.
function _hi_stand_down() {
  _hi_cecho "${2:-$1, skipping}" "$YELLOW"
  _hi_report_skip "$1"
  exit 0
}

function _hi_require_bin() {
  command -v "$1" >/dev/null 2>&1 && return 0
  _hi_stand_down "no $1" "$1 ${2:-not installed}, skipping"
}

function _hi_require_backend() {
  _hi_require_bin "$@"
  "$1" info >/dev/null 2>&1 && return 0
  _hi_stand_down "$1 unreachable" "$1 not reachable, skipping"
}

# The host report (--host-report, or _HI_HOST_REPORT=1): which bash, which
# userland, and which tree, for comparing a local run with CI. Every probe is
# guarded, so it never fails a run; with nothing on PATH every row reads
# "absent" (lib_test.sh checks).

# _hi_host_row <label> <text> [color]
function _hi_host_row() {
  _hi_cecho " | $(printf '%-9s' "$1") $2" "${3:-}"
}

# _hi_host_resolve <dir> - <dir> with symlinks resolved, empty if it is not a
# directory. `cd -P`, not `readlink -f`: that is a GNU extension, and this
# file has to give the same answer on the macOS job.
function _hi_host_resolve() {
  [ -n "${1:-}" ] || return 0
  (cd -P "$1" 2>/dev/null && pwd) || true
}

# _hi_tool_version <cmd> - "<cmd> X.Y.Z", or "<cmd> (absent)". One extractor
# for every tool below: the first version-shaped token anywhere in --version's
# output, which is all shellcheck (version on line 2), checkbashisms (a
# sentence), shfmt (a bare vX.Y.Z) and the four shells agree on. </dev/null so
# a tool that answers --version by starting a REPL exits instead of hanging.
function _hi_tool_version() {
  local out
  command -v "$1" >/dev/null 2>&1 || {
    printf '%s (absent)' "$1"
    return 0
  }
  out="$("$1" --version 2>&1 </dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)"
  printf '%s %s' "$1" "${out:-?}"
}

# _hi_host_versions <cmd...> - the row body for a group of tools.
function _hi_host_versions() {
  local cmd out=""
  for cmd in "$@"; do out="$out${out:+, }$(_hi_tool_version "$cmd")"; done
  printf '%s' "$out"
}

# The machine's size, for reading a borderline bench timing. Paths are
# overridable for fixtures; read with `read`, so it works with no PATH.

# _hi_host_cores - online CPU count, or empty
function _hi_host_cores() {
  local n=""
  n="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
  [ -n "$n" ] || n="$(nproc 2>/dev/null || true)"
  [ -n "$n" ] || n="$(sysctl -n hw.ncpu 2>/dev/null || true)"
  case "$n" in '' | *[!0-9]*) return 0 ;; esac
  printf '%s' "$n"
}

# _hi_host_cpu_model - the brand string, or empty
function _hi_host_cpu_model() {
  local line
  if [ -r "${_HI_PROC_CPUINFO:-/proc/cpuinfo}" ]; then
    while IFS= read -r line; do
      # x86 and most arm kernels say "model name"; some arm ones say
      # "Processor". The first of either is enough - the rows below it are the
      # same chip.
      case "$line" in
      "model name"*:* | "Model name"*:* | "Processor"*:*) ;;
      *) continue ;;
      esac
      line="${line#*:}"
      while [ "${line# }" != "$line" ]; do line="${line# }"; done
      [ -n "$line" ] || continue
      printf '%s' "$line"
      return 0
    done <"${_HI_PROC_CPUINFO:-/proc/cpuinfo}"
  fi
  # macOS answers the brand string; the BSDs put the same thing in hw.model,
  # which on macOS is the *machine* model ("MacBookPro18,3") - so it comes second
  line="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)"
  [ -n "$line" ] || line="$(sysctl -n hw.model 2>/dev/null || true)"
  printf '%s' "$line"
}

# _hi_host_mem_kb <field> - a /proc/meminfo value in kB, or empty
function _hi_host_mem_kb() {
  local line v
  [ -r "${_HI_PROC_MEMINFO:-/proc/meminfo}" ] || return 0
  while IFS= read -r line; do
    case "$line" in
    "$1":*)
      v="${line#*:}"
      v="${v%% kB*}"
      # shellcheck disable=SC2086 # unquoted to strip the leading run of spaces
      set -- $v
      printf '%s' "${1:-}"
      return 0
      ;;
    esac
  done <"${_HI_PROC_MEMINFO:-/proc/meminfo}"
}

# _hi_host_gib <kb> - "15.6 GiB", or empty. Integer arithmetic in bash rather
# than an awk fork; one decimal is all a debug row wants.
function _hi_host_gib() {
  local kb="${1:-}" whole tenth
  case "$kb" in '' | *[!0-9]*) return 0 ;; esac
  whole=$((kb / 1048576))
  tenth=$(((kb % 1048576) * 10 / 1048576))
  printf '%s.%s GiB' "$whole" "$tenth"
}

# _hi_host_memory - "15.6 GiB total, 13.9 GiB available", or empty. Only Linux
# has a cheap MemAvailable equivalent, so everywhere else reports the total
# alone: macOS keeps it in hw.memsize and the BSDs in hw.physmem - hw.physmem64
# first for NetBSD, where the 32-bit name saturates on a big machine.
function _hi_host_memory() {
  local total avail bytes name
  total="$(_hi_host_gib "$(_hi_host_mem_kb MemTotal)")"
  if [ -z "$total" ]; then
    for name in hw.memsize hw.physmem64 hw.physmem; do
      bytes="$(sysctl -n "$name" 2>/dev/null || true)"
      case "$bytes" in '' | *[!0-9]*) continue ;; esac
      printf '%s total' "$(_hi_host_gib $((bytes / 1024)))"
      return 0
    done
    return 0
  fi
  avail="$(_hi_host_gib "$(_hi_host_mem_kb MemAvailable)")"
  printf '%s total%s' "$total" "${avail:+, $avail available}"
}

# What the e2e suites need, reported rather than enforced: docker and podman
# have to *answer*, not merely exist (_hi_require_backend runs the same `info`,
# and a downed daemon is why an e2e suite skips); the rest only have to be on
# PATH. Probed through _hi_probe, so a wedged daemon costs the same ceiling
# here as it does in the header.
# shellcheck disable=SC2206 # the family roster is core.sh's space-separated list
_HI_HOST_BACKENDS=($_HI_CONTAINER_CLIS nomad kubectl kind ssh)

function _hi_host_backend_state() {
  local bin out="" t0
  for bin in "${_HI_HOST_BACKENDS[@]}"; do
    if ! command -v "$bin" >/dev/null 2>&1; then
      out="$out${out:+, }$bin: absent"
      continue
    fi
    case "$bin" in
    docker | podman)
      t0="$(_hi_now)"
      if _hi_probe "$bin" info >/dev/null 2>&1; then
        out="$out${out:+, }$bin: answering ($(_hi_elapsed "$t0" "$(_hi_now)")s)"
      else
        out="$out${out:+, }$bin: NOT answering"
      fi
      ;;
    *) out="$out${out:+, }$bin: present" ;;
    esac
  done
  printf '%s' "$out"
}

# _hi_host_tree_check <reference-tree> - is $_HI_ROOT the tree this run was
# invoked from? Silent if so, else one yellow line and non-zero. The caller
# supplies the reference, since everything derived from $_HI_HOME moves with
# the mistake. A warning only: another tree is allowed, but an inherited
# _HI_HOME otherwise shows only as fewer cases.
function _hi_host_tree_check() {
  local here="${1:-}" there="${_HI_ROOT:-}"
  [ "$there" = "$here" ] || there="$(_hi_host_resolve "$there")"
  [ -n "$here" ] && [ "$here" = "$there" ] && return 0
  _hi_cecho " | _HI_ROOT is ${there:-${_HI_ROOT:-unset} (missing)}, not the tree this run came from${here:+ ($here)} - the suites are testing another checkout" "$YELLOW"
  return 1
}

# _hi_host_report <reference-tree> - the block itself.
function _hi_host_report() {
  local ref="${1:-}" kernel os userland sed_ver loc glyphs cores cpu mem

  _hi_h2 "The host"
  _hi_host_row bash "${BASH_VERSION:-?} (${BASH:-?})"

  kernel="$(uname -srm 2>/dev/null || true)"
  os=""
  if [ -f "${_HI_LINUX_RELEASE:-/etc/os-release}" ]; then
    os="$(awk -F= '$1 == "PRETTY_NAME" { gsub(/"/, "", $2); print $2 }' \
      "${_HI_LINUX_RELEASE:-/etc/os-release}" 2>/dev/null || true)"
  elif command -v sw_vers >/dev/null 2>&1; then
    os="macOS $(sw_vers -productVersion 2>/dev/null || true)"
  fi
  _hi_host_row os "${kernel:-?}${os:+ - $os}"

  cores="$(_hi_host_cores)"
  cpu="$(_hi_host_cpu_model)"
  mem="$(_hi_host_memory)"
  _hi_host_row cpu "${cores:-?} cores${cpu:+ - $cpu}"
  _hi_host_row memory "${mem:-?}"

  # GNU or not decides `sed -i`, `mktemp -t`, `base64 -D`, and half the reasons
  # a suite passes here and fails on the macOS job
  sed_ver="$(sed --version 2>&1 </dev/null || true)"
  case "$sed_ver" in
  *GNU*) userland="GNU" ;;
  *[Bb]usy[Bb]ox*) userland="busybox" ;;
  *) userland="BSD/other (sed has no --version)" ;;
  esac
  if command -v timeout >/dev/null 2>&1; then
    userland="$userland, timeout present"
  else
    # core.sh's _hi_probe degrades to a bare call without it, so nothing on
    # this host is actually bounded by $_HI_PROBE_TIMEOUT
    userland="$userland, NO timeout - probes are unbounded here"
  fi
  _hi_host_row userland "$userland"

  loc="${LC_ALL:-${LC_CTYPE:-${LANG:-unset}}}"
  if _hi_use_ascii; then glyphs="ASCII marks"; else glyphs="UTF-8 glyphs"; fi
  _hi_host_row locale "$loc ($glyphs)"

  _hi_host_row _HI_HOME "${_HI_HOME:-unset}"
  # on disagreement the check prints its own line, which says more than a row
  if _hi_host_tree_check "$ref"; then
    _hi_host_row tree "${_HI_ROOT:-unset} - the tree this run came from" "$GREEN"
  fi

  _hi_host_row backends "$(_hi_host_backend_state)"
  _hi_host_row harness "$(_hi_host_versions python3 pgrep git tar)"
  _hi_host_row shells "$(_hi_host_versions bash zsh fish dash)"
  _hi_host_row lint "$(_hi_host_versions shellcheck shfmt checkbashisms)"
  return 0
}
