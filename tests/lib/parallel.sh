#!/usr/bin/env bash
# The parallel batch runner - the counters, teardown, and transcript a case needs
# when it runs in a background subshell instead of this shell.
#
# Part of the tests/test_lib.sh harness; sourced by it, never on its own.
# GLOSSARY: HI.30
# shellcheck disable=SC2329

# The container suites are nearly the whole cost of a full run, and nearly all
# of that is spent waiting on one container at a time while the machine idles.
# Every case already builds its own container under its own name, so the
# containers never collided - the harness around them did, in three places:
#
#   - **the counters.** _hi_case increments $_HI_TOTAL/$_HI_FAILED in the
#     current shell, and a background subshell's increments die with it. A case
#     writes its verdict to a file instead and _hi_par_wait tallies them in the
#     parent, which is the shape common/header.sh's _hi_probe_start /
#     _hi_probe_wait already uses for the header's backend probes.
#   - **teardown registration.** See the ledger (tests/lib/workdir.sh).
#   - **the transcript.** Concurrent _hi_cecho lines are unreadable, so each
#     case's output is buffered to its own file and replayed *in submission
#     order* once the batch is done. That is test_runner.sh's
#     collapse-and-replay idea one level down rather than a second mechanism:
#     a parallel run reads exactly like a serial one, only the timings overlap.
#
# Cases that share state stay serial through _hi_case - ssh_test.sh's two
# _hi_transcript_is_clean checks read files the bash32 cases write, so they run
# after the batch, not in it.
_HI_PAR_DIR=""
_HI_PAR_N=0
_HI_PAR_SLOTS=1
declare -a _HI_PAR_LABELS=()
# every pid not yet reaped - _hi_par_slot prunes it as cases finish, so what
# is left is exactly what _hi_par_wait must wait on and _hi_par_kill may kill
# (a reaped pid could already belong to somebody else's new process)
declare -a _HI_PAR_RUNNING=()
# case <n>'s subshell and the $SECONDS it started at, while it runs
declare -a _HI_PAR_PID=() _HI_PAR_T0=()

# How wide to fan out. Unbounded is the wrong answer on a laptop: twenty sshd
# containers, twenty ssh clients, and twenty pty feeders thrash the docker daemon
# and swap the box, which is both slower and flakier than four. So the default
# is four, or the CPU count when that is smaller. $_HI_PAR_WIDTH overrides it,
# and _HI_PAR_WIDTH=1 is a genuine serial run down this same code path - what
# bisecting a flake wants.
#
# That cap is about the daemon, not the box. A suite whose cases are plain
# local processes (a pty-driven configure run, an `env -i` shell, a nested
# runner) sets _HI_PAR_LOCAL=1 at its top and gets the whole CPU count
# instead; $_HI_PAR_WIDTH still overrides both.
function _hi_par_width() {
  local cpus
  if [ -n "${_HI_PAR_WIDTH:-}" ]; then
    printf '%s' "$_HI_PAR_WIDTH"
    return 0
  fi
  cpus="$(_hi_host_cores)"
  [ -n "$cpus" ] || cpus=2
  [ "$cpus" -lt 1 ] && cpus=1
  [ "${_HI_PAR_LOCAL:-0}" = 1 ] || [ "$cpus" -le 4 ] || cpus=4
  printf '%s' "$cpus"
}

# _hi_par_begin [what] - open a batch, and say out loud how wide it will run.
# A capped run must never read as "everything at once": same honesty rule the
# bench suite states about hyperfine, one directory over.
function _hi_par_begin() {
  _HI_PAR_DIR="$_HI_WORKDIR/par"
  rm -rf "$_HI_PAR_DIR"
  mkdir -p "$_HI_PAR_DIR"
  _HI_PAR_N=0
  _HI_PAR_LABELS=()
  _HI_PAR_RUNNING=()
  _HI_PAR_PID=()
  _HI_PAR_T0=()
  _HI_PAR_SLOTS="$(_hi_par_width)"
  if [ "$_HI_PAR_SLOTS" -le 1 ]; then
    _hi_cecho " | ${1:-cases}: one at a time (_HI_PAR_WIDTH=$_HI_PAR_SLOTS)" "$YELLOW"
  else
    _hi_cecho " | ${1:-cases}: $_HI_PAR_SLOTS at a time, transcripts replayed in submission order below" "$BLUE"
  fi
  return 0
}

# Blocks until a slot frees up. `wait <pid>` on each in turn and never `wait -n`
# (macOS ships bash 3.2, as header.sh's probes note), so a finished case is
# spotted by polling kill -0 and then reaped - the reap is what keeps the
# process table clean, and it returns immediately for a pid that has already
# exited.
function _hi_par_slot() {
  local pid
  local -a keep
  while [ "${#_HI_PAR_RUNNING[@]}" -ge "$_HI_PAR_SLOTS" ]; do
    [ "${_HI_PAR_CASE_LIMIT:-300}" = 0 ] || _hi_par_overdue
    keep=()
    for pid in ${_HI_PAR_RUNNING[@]+"${_HI_PAR_RUNNING[@]}"}; do
      if kill -0 "$pid" 2>/dev/null; then
        keep+=("$pid")
      else
        wait "$pid" 2>/dev/null || true
      fi
    done
    _HI_PAR_RUNNING=(${keep[@]+"${keep[@]}"})
    [ "${#_HI_PAR_RUNNING[@]}" -ge "$_HI_PAR_SLOTS" ] && sleep 0.05
  done
  return 0
}

# _hi_par_case <label> <fn> [args...] - _hi_case's parallel twin: same contract
# (one counted case, non-zero means failed), run in a background subshell once a
# slot is free. The verdict file carries the exit status *and* the case's own
# skip tally, since _hi_skip increments a variable that would otherwise die with
# the subshell too. A case that leaves no verdict at all - killed, or `exit`ed
# out from under us - is counted as a failure by _hi_par_wait rather than
# quietly vanishing from the totals.
function _hi_par_case() {
  local label="$1"
  shift
  _hi_par_slot
  _HI_PAR_N=$((_HI_PAR_N + 1))
  _HI_PAR_LABELS+=("$label")
  _hi_note_case "$label"
  local out="$_HI_PAR_DIR/$_HI_PAR_N.out" res="$_HI_PAR_DIR/$_HI_PAR_N.res"
  _hi_cecho " | [$label] started" "$BLUE"
  (
    # the subshell-local counters SC2030/SC2031 warn about are the mechanism,
    # not the bug: they are reset here, written to the verdict file below, and
    # summed back into the caller's by _hi_par_wait
    # shellcheck disable=SC2030
    _HI_SKIPPED=0
    _HI_PROGRESS_FILE="" # this copy's tally is partial; _hi_par_wait reports
    _hi_par_rc=0 _hi_par_t0=$SECONDS
    "$@" || _hi_par_rc=$?
    _hi_note_time $((SECONDS - _hi_par_t0)) "$label"
    printf '%s %s\n' "$_hi_par_rc" "${_HI_SKIPPED:-0}" >"$res"
  ) >"$out" 2>&1 &
  _HI_PAR_RUNNING+=("$!")
  _HI_PAR_PID[_HI_PAR_N]=$!
  _HI_PAR_T0[_HI_PAR_N]=$SECONDS
  return 0
}

# A case still running $_HI_PAR_CASE_LIMIT seconds after it started (300, or
# 0 for no limit; the slowest healthy case takes under 40) is stopped, its
# processes listed into its transcript first. Waiting on a hung one ran the
# job out with no transcript replayed and no case named. At 0 neither poll
# calls this: under a tracer each line it runs is a line through the trace
# pipe, 20 times a second.
function _hi_par_overdue() {
  local n pid limit="${_HI_PAR_CASE_LIMIT:-300}"
  [ "${#_HI_PAR_PID[@]}" -gt 0 ] || return 0
  for n in "${!_HI_PAR_PID[@]}"; do
    pid="${_HI_PAR_PID[n]}"
    if ! kill -0 "$pid" 2>/dev/null; then
      unset "_HI_PAR_PID[n]"
    elif [ "$limit" -gt 0 ] && ((SECONDS - _HI_PAR_T0[n] >= limit)); then
      _hi_par_stop "$n" "$pid" "$limit"
      unset "_HI_PAR_PID[n]"
    fi
  done
  return 0
}

# _hi_proc_table [pid] - every process, or <pid> with everything under it and
# everything in its group, ps's header first: pid, ppid, pgid, then where ps
# -o has them the controlling terminal, the state (T is stopped) and the
# kernel wait channel, then age and command. For a hung case: whether the
# shell had a terminal, whether a signal stopped it, and what it waits on.
# Both the tree and the group, because a `timeout` may have moved what it ran
# into a group of its own (OpenBSD's does) and a daemon reparents to init.
# -A on Linux, macOS and the BSDs (-e there is the environment), -e on a
# busybox without -A, MSYS's plain ps elsewhere; pid, ppid and pgid lead all,
# after the one-letter status MSYS puts ahead of a waiting or stopped process.
function _hi_proc_table() {
  local list
  list="$(ps -A -o pid,ppid,pgid,tty,stat,wchan,etime,args 2>/dev/null)" ||
    list="$(ps -A -o pid,ppid,pgid,etime,args 2>/dev/null)" ||
    list="$(ps -e -o pid,ppid,pgid,etime,args 2>/dev/null)" ||
    list="$(ps 2>/dev/null)"
  if [ -z "${1:-}" ]; then
    printf '%s\n' "$list"
    return 0
  fi
  printf '%s\n' "$list" | awk -v root="$1" '
    NR == 1 { print; next }
    $1 !~ /^[0-9]+$/ { sub(/^[ \t]*[^ \t]+/, "") }
    { n++; pid[n] = $1; ppid[n] = $2; pgid[n] = $3; row[n] = $0 }
    END {
      keep[root] = 1
      do {
        grew = 0
        for (i = 1; i <= n; i++)
          if (!(pid[i] in keep) && (ppid[i] in keep || pgid[i] == root)) { keep[pid[i]] = 1; grew = 1 }
      } while (grew)
      for (i = 1; i <= n; i++) if (pid[i] in keep) print row[i]
    }'
}

# _hi_par_stop <n> <pid> <limit> - ends case <n>'s subshell and everything
# under it, TERM first so its traps run, and leaves the verdict a timeout
function _hi_par_stop() {
  local n="$1" pid="$2" tree p
  local -a pids=("$pid")
  tree="$(_hi_proc_table "$pid")"
  while read -r p _; do
    case "$p" in '' | *[!0-9]* | "$pid") continue ;; esac
    pids+=("$p")
  done <<<"$tree"
  kill -TERM "${pids[@]}" 2>/dev/null || true
  sleep 1
  kill -KILL "${pids[@]}" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  # the subshell's own writes are done, so the note lands after them
  {
    _hi_align " | [${_HI_PAR_LABELS[n - 1]}] -- still running after ${3}s (_HI_PAR_CASE_LIMIT), stopped" "FAILED" "$RED"
    printf '      its processes then:\n'
    printf '%s\n' "$tree" | sed 's/^/      /'
  } >>"$_HI_PAR_DIR/$n.out"
  [ -s "$_HI_PAR_DIR/$n.res" ] || printf '124 0\n' >"$_HI_PAR_DIR/$n.res"
  printf '%s\n' "$3" >"$_HI_PAR_DIR/$n.late"
}

# _hi_par_check / _hi_par_check_requires - _hi_check's parallel twins. The
# reporting runs in the subshell; _hi_par_wait does the counting.
function _hi_par_check() {
  _hi_par_case "$1" _hi_assert "$@"
}

# _hi_check_eq / _hi_par_check_eq <label> <want> <cmd...> - the _hi_expect_eq
# twins of _hi_check / _hi_par_check.
function _hi_check_eq() {
  _hi_case _hi_expect_eq "$@"
}

function _hi_par_check_eq() {
  _hi_par_case "$1" _hi_expect_eq "$@"
}

function _hi_par_check_requires() { _hi_par_case "$2" _hi_par_requires_body "$1" _hi_assert "${@:2}"; }

# _hi_par_check_capable <capability> <label> <cmd...> - _hi_check_capable's
# parallel twin, for the container-shaped suites. The probe runs inside the
# case's subshell like the _requires guard's does, so the skip is reported and
# tallied through the same .res file every other verdict here goes through -
# a parent-side skip would print out of submission order.
function _hi_par_check_capable() { _hi_par_case "$2" _hi_par_capable_body "$1" _hi_assert "${@:2}"; }

function _hi_par_capable_body() {
  local cap="$1" assert="$2" rc=0
  shift 2
  _hi_capable "$cap" || rc=$?
  case "$rc" in
  0) "$assert" "$@" ;;
  1) _hi_skip "$1" "no $cap" ;;
  *) return 1 ;;
  esac
}

# _hi_par_check_requires_eq <bin> <label> <want> <cmd...> - the _hi_expect_eq
# arm of the same guard.
function _hi_par_check_requires_eq() { _hi_par_case "$2" _hi_par_requires_body "$1" _hi_expect_eq "${@:2}"; }

# The assertion is a parameter so both wrappers above share one guard: which of
# _hi_assert / _hi_expect_eq runs is the only thing that differs between them.
function _hi_par_requires_body() {
  local bin="$1" assert="$2"
  shift 2
  if command -v "$bin" >/dev/null 2>&1; then
    "$assert" "$@"
  else
    _hi_skip "$1" "no $bin"
  fi
}

# Waits out the batch, then replays and tallies it in submission order.
function _hi_par_wait() {
  local pid i=0 label rc skipped
  while [ "${_HI_PAR_CASE_LIMIT:-300}" != 0 ] && [ "${#_HI_PAR_PID[@]}" -gt 0 ]; do
    _hi_par_overdue
    [ "${#_HI_PAR_PID[@]}" -eq 0 ] || sleep 0.2
  done
  for pid in ${_HI_PAR_RUNNING[@]+"${_HI_PAR_RUNNING[@]}"}; do wait "$pid" 2>/dev/null || true; done
  for label in ${_HI_PAR_LABELS[@]+"${_HI_PAR_LABELS[@]}"}; do
    i=$((i + 1))
    [ -f "$_HI_PAR_DIR/$i.out" ] && cat "$_HI_PAR_DIR/$i.out"
    rc=1
    skipped=0
    if [ -s "$_HI_PAR_DIR/$i.res" ]; then
      read -r rc skipped <"$_HI_PAR_DIR/$i.res"
    else
      _hi_align " | [$label] -- the case left no verdict (killed, or it exited the subshell)" "FAILED" "$RED"
      [ -s "$_HI_PAR_DIR/$i.out" ] || printf '      it printed nothing before it went: look for a kill or an exit ahead of its first line\n'
      _hi_note_failure "[$label] left no verdict"
    fi
    # $_HI_TOTAL counts cases that reached a verdict, pass or fail - a skipped
    # one is tracked in $_HI_SKIPPED alone. That is the serial twin's rule
    # (_hi_check_requires reaches _hi_skip *without* going through _hi_case, so
    # nothing is added there), and counting it in both columns here made
    # test_runner.sh's `pass = cases - failed` report every stand-down as a
    # green pass - inflating the number that feeds --totals-file and the README
    # badge. A case that skipped and then failed is still a failure.
    if [ -s "$_HI_PAR_DIR/$i.late" ]; then
      _HI_TOTAL=$((_HI_TOTAL + 1))
      _HI_FAILED=$((_HI_FAILED + 1))
      _hi_note_failure "[$label] still running after $(cat "$_HI_PAR_DIR/$i.late")s, stopped"
    elif [ "$rc" -ne 0 ]; then
      _HI_TOTAL=$((_HI_TOTAL + 1))
      _HI_FAILED=$((_HI_FAILED + 1))
      _hi_note_failure_unless_named "$label" "[$label] exited $rc before reporting a verdict"
    elif [ "$skipped" -eq 0 ]; then
      _HI_TOTAL=$((_HI_TOTAL + 1))
    fi
    # shellcheck disable=SC2031 # this is the parent's copy, which is the point
    _HI_SKIPPED=$((${_HI_SKIPPED:-0} + skipped))
  done
  _HI_PAR_LABELS=()
  _HI_PAR_RUNNING=()
  _HI_PAR_PID=()
  _HI_PAR_T0=()
  _HI_PAR_N=0
  _hi_report_progress
}

# The teardown half, reached from _hi_test_cleanup: stop anything still running
# before the ledger is swept, or a case mid-`docker run` puts a container back
# behind it. TERM first so a case's own traps get their chance, KILL after.
function _hi_par_kill() {
  local pid
  for pid in ${_HI_PAR_RUNNING[@]+"${_HI_PAR_RUNNING[@]}"}; do
    kill -TERM "$pid" 2>/dev/null || true
  done
  for pid in ${_HI_PAR_RUNNING[@]+"${_HI_PAR_RUNNING[@]}"}; do
    kill -9 "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
  _HI_PAR_RUNNING=()
  _HI_PAR_PID=()
  return 0
}

# _hi_before <text> <first-pattern> <second-pattern> - both patterns present
# in <text>, and the first's earliest match on an earlier line. The ordering
# assertion several suites make about generated rc/bootloader content.
# `grep -m1` and a here-string, not `printf | grep | head | cut`: two processes
# per pattern instead of four, across ten call sites in the fast suites. The
# patterns stay grep's BREs on purpose - bash's own `=~` is an ERE, where the
# unescaped `+` in a caller's 'set +euo pipefail' silently stops being literal.
function _hi_before() {
  local a b
  a="$(grep -n -m1 "$2" <<<"$1")"
  b="$(grep -n -m1 "$3" <<<"$1")"
  [ -n "$a" ] && [ -n "$b" ] && [ "${a%%:*}" -lt "${b%%:*}" ]
}
