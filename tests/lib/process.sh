#!/usr/bin/env bash
# Driving something that takes time: the target-side probe strings, pty wrapping,
# the polling helpers, and the timed interactive case.
#
# Part of the tests/test_lib.sh harness; sourced by it, never on its own.
# GLOSSARY: HI.30
# shellcheck disable=SC2329

# The command an e2e suite runs on the target: it echoes $1 (the marker) only
# if hi landed, by the shape $2 names:
#
#   bash               the copy landed (sourcing aliases.sh itself)
#   fallback           the container fallback: $_HI_BAT_OPTS, which only
#                      aliases.sh exports (no paths.sh there)
#   fallback_fish      the same, in fish
#   ssh_fallback       the ssh fallback rc, which has paths.sh's hi_info
#   ssh_fallback_fish  the same, in fish
#   rooted_under       the session's tree is under $3
#   rooted_elsewhere   the session runs its own tree, not the target's
#                      install at $3
#
# Single-quoted: the variables expand on the target.
# shellcheck disable=SC2016 # these expand later, on the target
function _hi_probe_cmd() {
  local marker="$1"
  # the tail every rooted shape shares: prove the aliases really loaded, then
  # say the marker
  local probe='source "$_HI_ALIASES" && alias hi_info >/dev/null 2>&1 && echo '
  case "$2" in
  bash) printf 'test -f "$_HI_ROOT/hi.sh" && %s%s' "$probe" "$marker" ;;
  fallback) printf '%s%s' '[ -n "${_HI_BAT_OPTS:-}" ] && echo ' "$marker" ;;
  fallback_fish) printf '%s%s' 'set -q _HI_BAT_OPTS; and echo ' "$marker" ;;
  ssh_fallback) printf '%s%s' 'test -f "$_HI_ROOT/hi.sh" && alias hi_info >/dev/null 2>&1 && echo ' "$marker" ;;
  ssh_fallback_fish) printf '%s%s' 'test -f "$_HI_ROOT/hi.sh"; and functions -q hi_info; and echo ' "$marker" ;;
  rooted_under) printf 'case "$_HI_ROOT" in %s/*) %s%s ;; esac' "$3" "$probe" "$marker" ;;
  # the inverse, for a target that *has* a say-hi installed at <path>: the
  # session ships its own tree and must not be running out of that one
  rooted_elsewhere) printf 'test "$_HI_ROOT" != "%s" && %s%s' "$3" "$probe" "$marker" ;;
  *)
    _hi_cecho "unknown probe shape: $2" "$RED" >&2
    return 1
    ;;
  esac
}

_HI_PTY_SPAWN='import pty, sys; sys.exit(pty.spawn(sys.argv[1:]))'

# Whether python3 can build a pty, not just exist (`pty` is Unix-only, so
# Windows has python3 and no pty). Probed once by the runner and inherited.
: "${_HI_PTY_OK:=$(python3 -c 'import pty, tty' >/dev/null 2>&1 && echo 1 || echo 0)}"
export _HI_PTY_OK

# Sets _HI_PTY_WRAP to a python3 pty-spawn prefix when needed, else empty.
# $1 the fd to check, $2 "auto" (wrap unless $1 is a tty) or "force", $3 an
# optional warning for when no pty can be made.
function _hi_pty_wrap() {
  local fd="$1" mode="$2" warning="${3:-}"
  _HI_PTY_WRAP=()
  if [ "$mode" = force ] || [ ! -t "$fd" ]; then
    if [ "$_HI_PTY_OK" -eq 1 ]; then
      _HI_PTY_WRAP=(python3 -c "$_HI_PTY_SPAWN")
    else
      if [ -z "$warning" ]; then
        if [ "$mode" = force ]; then
          warning="no python3 to give the launcher its own pty - it will raw-mode this terminal and the test kills it before it can restore, expect garbled output afterwards"
        else
          warning="no tty and no python3 to fake one - results may be unreliable"
        fi
      fi
      _hi_cecho " | $warning" "$YELLOW"
    fi
  fi
}

# The prefix always built, for _hi_interactive_case, whose launcher's stdin
# is our pipe yet must look like a tty. Empty with no pty, which makes those
# cases skip (`_hi_check_capable pty`). Filled at source time.
_HI_PTY_FORCED=()
[ "$_HI_PTY_OK" -eq 1 ] && _HI_PTY_FORCED=(python3 -c "$_HI_PTY_SPAWN")

# Saves our stdin on fd 3 and decides the pty wrap from it ($1 mode, $2
# warning), since `exec -it` wants a tty CI lacks. fd 3 (with `<&3` in
# _hi_exec_case), because a backgrounded job's fd 0 becomes /dev/null.
function _hi_pty_stdin() {
  exec 3<&0
  _hi_pty_wrap 3 "$1" "${2:-}"
}

function _hi_poll_budget() {
  awk -v t="$1" -v i="$2" \
    'BEGIN { b = t * i; b = (b == int(b) ? b : int(b) + 1); printf "%d", (b < 1 ? 1 : b) }'
}

# Both pollers take (tries, interval), but only as a wall-clock budget: a
# counted loop stretches when the machine is busy. +1 because $SECONDS is
# already truncated when read, so the budget is a floor, not a ceiling.
function _hi_poll_bool() {
  local abort=""
  if [ "$1" = -a ]; then
    abort="$2"
    shift 2
  fi
  local tries="$1" interval="$2" deadline
  shift 2
  deadline=$((SECONDS + $(_hi_poll_budget "$tries" "$interval") + 1))
  while :; do
    "$@" >/dev/null 2>&1 && return 0
    if [ -n "$abort" ] && ! "$abort"; then
      return 1
    fi
    [ "$SECONDS" -lt "$deadline" ] || return 1
    sleep "$interval"
  done
}

function _hi_poll_value() {
  local tries="$1" interval="$2" out deadline
  shift 2
  deadline=$((SECONDS + $(_hi_poll_budget "$tries" "$interval") + 1))
  while :; do
    out="$("$@" 2>/dev/null)"
    if [ -n "$out" ]; then
      printf '%s' "$out"
      return 0
    fi
    [ "$SECONDS" -lt "$deadline" ] || return 1
    sleep "$interval"
  done
}

# A wall-clock deadline, as the pollers use (+1 included), polled every 50ms
# so a fast pty case is noticed quickly.
function _hi_wait_pid() {
  local pid="$1" timeout_s="$2" deadline
  shift 2
  _HI_WAIT_EXIT=0
  deadline=$((SECONDS + timeout_s + 1))
  while [ "$SECONDS" -lt "$deadline" ]; do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.05
  done
  if kill -0 "$pid" 2>/dev/null; then
    [ $# -gt 0 ] && "$@"
    kill -9 "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    _HI_WAIT_EXIT=124
  else
    wait "$pid" 2>/dev/null || _HI_WAIT_EXIT=$?
  fi
}

# _hi_wait_quiet <pid> <quiet_s> <transcript> <label> - _hi_wait_pid for a pty
# case: the deadline is <quiet_s> without new output (capped at five times
# that), so a slow host still drawing is not a wedge. A killed child is named
# with its run time and _hi_wedge_report's view.
function _hi_wait_quiet() {
  local pid="$1" quiet_s="$2" file="$3" label="$4" t0=$SECONDS last=$SECONDS tick="" size="" now
  _HI_WAIT_EXIT=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ $((SECONDS - last)) -gt "$quiet_s" ] || [ $((SECONDS - t0)) -gt $((quiet_s * 5)) ]; then
      _hi_h3 " | [$label] -- TIMED OUT: $((SECONDS - last))s with nothing new, $((SECONDS - t0))s in all, killing" "$RED"
      _hi_wedge_report "$file"
      kill -9 "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      _HI_WAIT_EXIT=124
      return 0
    fi
    sleep 0.05
    # the size once a second, not once a poll: reading it is a fork
    if [ "$tick" != "$SECONDS" ]; then
      tick=$SECONDS
      now="$(wc -c <"$file" 2>/dev/null || true)"
      if [ "$now" != "$size" ]; then
        size="$now" last=$SECONDS
      fi
    fi
  done
  wait "$pid" 2>/dev/null || _HI_WAIT_EXIT=$?
}

# _hi_wedge_report [transcript] - what a killed case leaves to read: the
# host's load, and the last lines the child drew, which is the question or
# the page it stopped at
function _hi_wedge_report() {
  local load=""
  if command -v uptime >/dev/null 2>&1; then
    load="$(uptime 2>/dev/null || true)"
  fi
  [ -z "$load" ] || printf '      host: %s\n' "${load#"${load%%[![:space:]]*}"}"
  [ -s "${1:-}" ] || return 0
  printf '      the last of its %s bytes:\n' "$(_hi_file_bytes "$1")"
  _hi_strip_ansi "$(tail -c 1500 "$1" | tr '\r' '\n')" | grep -v '^[[:space:]]*$' | tail -n 12 | sed 's/^/      | /' || true
}

# _hi_timed_out <label> <timeout_s> [hook] - _hi_wait_pid's timeout callback,
# reached through its "$@". One top-level function: a per-runner
# `_hi_on_timeout` would be global anyway, and the second definition would
# silently redefine the first.
# shellcheck disable=SC2329
function _hi_timed_out() {
  _hi_h3 " | [$1] -- TIMED OUT after ${2}s, killing" "$RED"
  _hi_wedge_report
  [ -n "${3:-}" ] && "$3"
  return 0
}

# _hi_case_result <label> <what> <exit> <t0> <t1> <out_file> <marker...> - the
# verdict: OK with a timing when every marker is present, else FAILED with
# the transcript. 124 (_hi_wait_pid's timeout) always fails, since a session
# can print its marker and then hang. Other non-zero statuses (the execs
# return their own) pass but are shown on the OK line.
function _hi_case_result() {
  local label="$1" what="$2" exit_code="$3" t0="$4" t1="$5" out_file="$6" marker ok=1
  shift 6
  for marker in "$@"; do
    grep -qF "$marker" "$out_file" 2>/dev/null || ok=0
  done
  if [ "$exit_code" = 124 ]; then
    local markers=present
    [ "$ok" -eq 1 ] || markers=missing
    _hi_h3 " | [$label] -- FAILED: TIMED OUT ($(_hi_elapsed "$t0" "$t1")s, markers $markers)" "$RED"
    sed 's/^/      /' "$out_file" 2>/dev/null
    _hi_note_failure "[$label] $what (timed out)"
    return 1
  fi
  if [ "$ok" -eq 1 ]; then
    if [ "$exit_code" = 0 ]; then
      _hi_align " | [$label] -- $what" "OK ($(_hi_elapsed "$t0" "$t1")s)" "$GREEN"
    else
      _hi_align " | [$label] -- $what" "OK ($(_hi_elapsed "$t0" "$t1")s, exit $exit_code)" "$YELLOW"
    fi
    return 0
  fi
  _hi_h3 " | [$label] -- FAILED (exit $exit_code, $(_hi_elapsed "$t0" "$t1")s)" "$RED"
  sed 's/^/      /' "$out_file" 2>/dev/null
  _hi_note_failure "[$label] $what (exit $exit_code)"
  return 1
}

# <attempts> (last, default 1) - tries before _hi_case_result, for
# kube_test.sh's transient markerless kubectl failure. A timeout (124) is
# never retried. Each try truncates $out_file, so one transcript and one
# result print.
function _hi_exec_case() {
  local label="$1" what="$2" marker="$3" timeout_s="$4" target="$5" cmd="$6" hook="${7:-}"
  local out_file="$_HI_WORKDIR/$label.out" exit_code t0 t1
  local attempt attempts="${8:-1}"

  t0="$(_hi_now)"
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    _hi_cecho " | Running: $_HI_LAUNCHER $target $cmd"
    # ${a[@]+"${a[@]}"}: _HI_PTY_WRAP is empty whenever we already have a real
    # tty, and on bash 3.2 (macOS) expanding an empty array under `set -u` is fatal
    ${_HI_PTY_WRAP[@]+"${_HI_PTY_WRAP[@]}"} "$_HI_LAUNCHER" "$target" "$cmd" <&3 >"$out_file" 2>&1 &
    _hi_wait_pid "$!" "$timeout_s" _hi_timed_out "$label" "$timeout_s" "$hook"
    exit_code="$_HI_WAIT_EXIT"
    t1="$(_hi_now)"
    [ "$exit_code" = 124 ] && break
    grep -qF "$marker" "$out_file" 2>/dev/null && break
    # `x || notice`, never `x && notice`: as the loop body's last statement the
    # && form would leave a non-zero status on the final pass and errexit
    # would kill this function before _hi_case_result runs
    [ "$attempt" -eq "$attempts" ] || _hi_cecho " | [$label] no marker on attempt $attempt, retrying" "$YELLOW"
  done

  _hi_case_result "$label" "$what" "$exit_code" "$t0" "$t1" "$out_file" "$marker"
}

# True once the session reached a shell: load()'s banner (a constant, which
# ssh_relay_test.sh also counts) or the no-bash fallback's notice.
_HI_SESSION_LOADED_RE='hi loaded:'
function _hi_session_ready() {
  grep -qE "$_HI_SESSION_LOADED_RE|aliases only" "$1" 2>/dev/null
}

# _hi_interactive_case [-c <closing>] [-m <marker>]... [-f <fn>] \
#   <label> <what> <marker> <timeout_s> <launcher...> - an interactive session,
# the only shape that reaches load(): types a line and `exit` once the shell
# is ready, and asserts the marker and the closing line. <launcher...> is
# bare; _HI_PTY_FORCED is prepended.
#   -c <closing>  the line that ends the session, held for and asserted
#                 (default load()'s "| session: <duration>")
#   -m <marker>   another required marker (repeatable)
#   -f <fn>       runs before the `exit`; its stdout is typed into the
#                 session
# the interactive case is still waiting on its session ($out_file is the
# case's, through dynamic scoping)
function _hi_interactive_live() { [ ! -e "$out_file.over" ]; }

function _hi_interactive_case() {
  local closing="| session: " feeder=""
  local -a extra=()
  while :; do
    case "${1:-}" in
    -c)
      closing="$2"
      shift 2
      ;;
    -m)
      extra+=("$2")
      shift 2
      ;;
    -f)
      feeder="$2"
      shift 2
      ;;
    *) break ;;
    esac
  done
  local label="$1" what="$2" marker="$3" timeout_s="$4"
  shift 4
  local out_file="$_HI_WORKDIR/$label.interactive.out" exit_code t0 t1
  # a pty echoes back everything we type, so the line we send must not itself
  # contain what we grep for - the shell has to assemble it. printf's two
  # arguments arrive space-separated on the echoed line and hyphen-joined only
  # in the real output, in every shell load() might hand us.
  local expected="$marker-INTERACTIVE"

  if [ "${#_HI_PTY_FORCED[@]}" -eq 0 ]; then
    _hi_skip "[$label]" "no usable pty to drive an interactive case"
    return 0
  fi

  _hi_cecho " | Running (interactive): $*"
  t0="$(_hi_now)"
  : >"$out_file"
  rm -f "$out_file.over"
  # The pipe's left side watches the transcript, types nothing before the
  # shell is ready (earlier input is lost on a loaded runner), and holds the
  # pipe until the closing line. It only polls $out_file, so SC2094's race
  # does not apply.
  # shellcheck disable=SC2094
  {
    if _hi_poll_bool -a _hi_interactive_live "$((timeout_s * 4))" 0.25 _hi_session_ready "$out_file"; then
      printf "printf '%%s-%%s\\\\n' %s INTERACTIVE\n" "$marker"
      [ -z "$feeder" ] || "$feeder"
      printf 'exit\n'
      _hi_poll_bool -a _hi_interactive_live "$((timeout_s * 4))" 0.25 grep -q "$closing" "$out_file" || true
    fi
  } | "${_HI_PTY_FORCED[@]}" "$@" >"$out_file" 2>&1 &
  _hi_wait_pid "$!" "$timeout_s" _hi_timed_out "$label" "$timeout_s"
  : >"$out_file.over"
  exit_code="$_HI_WAIT_EXIT"
  t1="$(_hi_now)"

  # both markers: the interactive shell really came up and ran our line, and
  # the session reached its closing line rather than dying early
  # (${a[@]+...}: bash 3.2 + set -u, as above)
  _hi_case_result "$label" "$what" "$exit_code" "$t0" "$t1" "$out_file" \
    "$expected" "$closing" ${extra[@]+"${extra[@]}"}
}
