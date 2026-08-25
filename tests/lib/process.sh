#!/bin/bash
# Driving something that takes time: the target-side probe strings, pty wrapping,
# the polling helpers, and the timed interactive case.
#
# Part of the tests/test_lib.sh harness; sourced by it, never on its own.
# GLOSSARY: HI.30
# shellcheck disable=SC2329

# The command each e2e suite runs *on the target* to prove hi landed there: it
# echoes $1 (the marker) only if the assertion holds, and the suite greps the
# transcript for it. $2 picks the shape, which differs by what each branch has
# in scope:
#
#   bash              the main branch: asserts the copy landed and sources
#                     aliases.sh itself, which that branch does not
#   fallback          the container fallback copies only aliases.sh - no
#                     paths.sh, so hi_info isn't in scope; check a plain alias
#   fallback_fish     the same, in fish's dialect (its aliases are functions)
#   ssh_fallback      the ssh fallback rc *does* source paths.sh, so hi_info is
#   ssh_fallback_fish ssh_fallback in fish's dialect
#   installed         a permanent say-hi: asserts $_HI_ROOT is ~/say-hi, i.e.
#                     _say_hi loaded it in place rather than shipping a tree
#   installed_nested  the same, for a permanent say-hi that is *not* at ~/say-hi:
#                     only _hi_remote_root reading install.sh's rc line can
#                     have found it, so the path itself is the assertion
#   installed_at      the general form: $3 is the tree the session must have
#                     landed in. What install_methods_test.sh asserts, where the
#                     path differs per packaging channel rather than per shell
#
# Every string stays single-quoted: the variables expand on the target.
# shellcheck disable=SC2016 # these expand later, on the target
function _hi_probe_cmd() {
  local marker="$1"
  case "$2" in
  bash) printf '%s%s' 'test -f "$_HI_ROOT/hi.sh" && source "$_HI_ALIASES" && alias hi_info >/dev/null 2>&1 && echo ' "$marker" ;;
  fallback) printf '%s%s' 'alias sudo >/dev/null 2>&1 && echo ' "$marker" ;;
  fallback_fish) printf '%s%s' 'functions -q sudo; and echo ' "$marker" ;;
  ssh_fallback) printf '%s%s' 'test -f "$_HI_ROOT/hi.sh" && alias hi_info >/dev/null 2>&1 && echo ' "$marker" ;;
  ssh_fallback_fish) printf '%s%s' 'test -f "$_HI_ROOT/hi.sh"; and functions -q hi_info; and echo ' "$marker" ;;
  installed) printf '%s%s' 'test "$_HI_ROOT" = "$HOME/say-hi" && source "$_HI_ALIASES" && alias hi_info >/dev/null 2>&1 && echo ' "$marker" ;;
  installed_nested) printf '%s%s' 'test "$_HI_ROOT" = "$HOME/opt/nested/say-hi" && source "$_HI_ALIASES" && alias hi_info >/dev/null 2>&1 && echo ' "$marker" ;;
  installed_at) printf 'test "$_HI_ROOT" = "%s" && source "$_HI_ALIASES" && alias hi_info >/dev/null 2>&1 && echo %s' "$3" "$marker" ;;
  *)
    _hi_cecho "unknown probe shape: $2" "$RED"
    return 1
    ;;
  esac
}

_HI_PTY_SPAWN='import pty, sys; sys.exit(pty.spawn(sys.argv[1:]))'

# Whether python3 can actually build one, which is a different question from
# whether python3 exists: `pty` and `tty` are Unix-only modules, so on Windows
# `command -v python3` succeeds and the import does not - and a case gated on
# the binary runs and fails where it should have stood down. Probed once at
# source time, one interpreter start per suite and only where there is an
# interpreter to start, so every consumer below asks the capability instead.
_HI_PTY_OK=0
command -v python3 >/dev/null 2>&1 &&
  python3 -c 'import pty, tty' >/dev/null 2>&1 && _HI_PTY_OK=1

# Sets the global array _HI_PTY_WRAP to a python3-based pty-spawn prefix
# whenever it's needed, empty otherwise. $1 is the fd to check for tty-ness,
# $2 is "auto" (only wrap if fd $1 isn't a real tty) or "force" (always
# wrap - for callers where the fd being checked is never the right proxy for
# whether the *launcher* ends up with a real tty), $3 is the warning printed
# when there is no usable pty to build the fake with.
function _hi_pty_wrap() {
  local fd="$1" mode="$2" warning="$3"
  _HI_PTY_WRAP=()
  if [ "$mode" = force ] || [ ! -t "$fd" ]; then
    if [ "$_HI_PTY_OK" -eq 1 ]; then
      _HI_PTY_WRAP=(python3 -c "$_HI_PTY_SPAWN")
    else
      _hi_cecho " | $warning" "$YELLOW"
    fi
  fi
}

# The same prefix in its own array, always built, alongside whatever
# _hi_pty_wrap decided. _hi_interactive_case needs one even when the suite is
# running on a real terminal: it drives the session by *writing* to the
# launcher's stdin, so that stdin is a pipe from us rather than the terminal,
# and both `ssh -t` and `<backend> exec -it` want a tty there. Left empty when
# there is no usable pty, which is what makes those cases skip rather than
# fail, and what `_hi_check_capable pty` reads. Filled here rather than by a
# function four suites had to remember to call first: it takes no arguments
# and reads nothing that varies between cases.
_HI_PTY_FORCED=()
[ "$_HI_PTY_OK" -eq 1 ] && _HI_PTY_FORCED=(python3 -c "$_HI_PTY_SPAWN")

# The _hi_pty_wrap preamble every suite that backgrounds the launcher needs:
# stash our real stdin on fd 3 and decide the pty wrap from *that*. $1 is the
# mode, $2 the warning. `exec -it` refuses a remote tty unless our stdin is one,
# which it isn't in CI, so the local fake is what makes these suites reliable
# off an interactive terminal.
#
# The check must use the duplicated fd: bash rewires a backgrounded job's stdin
# to /dev/null with job control off, so testing `-t 0` here and handing the job
# fd 0 later would report a terminal and still fail. fd 3 plus `<&3` in
# _hi_exec_case keeps the original tty-ness - which is why they go together.
function _hi_pty_stdin() {
  exec 3<&0
  _hi_pty_wrap 3 "$1" "$2"
}

function _hi_poll_budget() {
  awk -v t="$1" -v i="$2" \
    'BEGIN { b = t * i; b = (b == int(b) ? b : int(b) + 1); printf "%d", (b < 1 ? 1 : b) }'
}

# Both pollers take (tries, interval) - the shape every call site speaks -
# but tries*interval only sizes the wall-clock budget: the deadline is the
# one bound, for _hi_wait_pid's reason (an iteration counter stretches
# without bound exactly when the machine is busiest).
function _hi_poll_bool() {
  local abort=""
  if [ "$1" = -a ]; then
    abort="$2"
    shift 2
  fi
  local tries="$1" interval="$2" deadline
  shift 2
  deadline=$((SECONDS + $(_hi_poll_budget "$tries" "$interval")))
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
  deadline=$((SECONDS + $(_hi_poll_budget "$tries" "$interval")))
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

# Wall-clock, not iteration count: `for ((i = 0; i < timeout_s * 4))` at
# sleep 0.25 only equals timeout_s when nothing else is competing for the
# machine, and stretches without bound when something is - which is exactly
# when an e2e suite is most likely to need the timeout. _hi_poll_bool and
# _hi_poll_value already use this deadline; this now matches them.
function _hi_wait_pid() {
  local pid="$1" timeout_s="$2" deadline
  shift 2
  _HI_WAIT_EXIT=0
  deadline=$((SECONDS + timeout_s))
  while [ "$SECONDS" -lt "$deadline" ]; do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.25
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

# _hi_timed_out <label> <timeout_s> [hook] - _hi_wait_pid's timeout callback,
# reached through its "$@". One top-level function: a per-runner
# `_hi_on_timeout` would be global anyway, and the second definition would
# silently redefine the first.
# shellcheck disable=SC2329
function _hi_timed_out() {
  _hi_h3 " | [$1] -- TIMED OUT after ${2}s, killing" "$RED"
  [ -n "${3:-}" ] && "$3"
  return 0
}

# _hi_case_result <label> <what> <exit> <t0> <t1> <out_file> <marker...> - the
# verdict both case runners reach: OK with a timing, or FAILED with the
# transcript indented under it. Every marker given must be present.
function _hi_case_result() {
  local label="$1" what="$2" exit_code="$3" t0="$4" t1="$5" out_file="$6" marker ok=1
  shift 6
  for marker in "$@"; do
    grep -qF "$marker" "$out_file" 2>/dev/null || ok=0
  done
  if [ "$ok" -eq 1 ]; then
    _hi_align " | [$label] -- $what" "OK ($(_hi_elapsed "$t0" "$t1")s)" "$GREEN"
    return 0
  fi
  _hi_h3 " | [$label] -- FAILED (exit $exit_code, $(_hi_elapsed "$t0" "$t1")s)" "$RED"
  sed 's/^/      /' "$out_file" 2>/dev/null
  _hi_note_failure "[$label] $what (exit $exit_code)"
  return 1
}

function _hi_exec_case() {
  local label="$1" what="$2" marker="$3" timeout_s="$4" target="$5" cmd="$6" hook="${7:-}"
  local out_file="$_HI_WORKDIR/$label.out" exit_code t0 t1

  _hi_cecho " | Running: $_HI_LAUNCHER $target $cmd"
  t0="$(_hi_now)"
  # ${a[@]+"${a[@]}"}: _HI_PTY_WRAP is empty whenever we already have a real
  # tty, and on bash 3.2 (macOS) expanding an empty array under `set -u` is fatal
  ${_HI_PTY_WRAP[@]+"${_HI_PTY_WRAP[@]}"} "$_HI_LAUNCHER" "$target" "$cmd" <&3 >"$out_file" 2>&1 &
  _hi_wait_pid "$!" "$timeout_s" _hi_timed_out "$label" "$timeout_s" "$hook"
  exit_code="$_HI_WAIT_EXIT"
  t1="$(_hi_now)"

  _hi_case_result "$label" "$what" "$exit_code" "$t0" "$t1" "$out_file" "$marker"
}

# True once the target's session has actually reached a shell, so
# _hi_interactive_case knows when its input will be read rather than guessing.
# Both shapes count: load()'s full path announces the shell it picked, and the
# no-bash fallback says so instead - a readiness check that only knew about
# the first would hang out the full timeout on any target without bash.
function _hi_session_ready() {
  grep -qE 'hi loaded with|aliases only' "$1" 2>/dev/null
}

# Like _hi_exec_case, but drives a real *interactive* session instead of a
# one-off command - the only shape that reaches load.sh's load(). hi.sh's
# $CMDARG replaces `load` outright in the bootloader (see _hi_bootloader), so a
# command-shaped case never exercises the header, the rc grafting, the shell
# handoff or clean_all; this one does. The session is driven by piping a
# printf and an `exit` into it after a settle, and it asserts both the marker
# (an interactive shell really came up and ran our line) and load()'s closing
# line (its exit path ran, rather than the session dying early).
#
# _hi_interactive_case [-c <closing>] [-m <marker>]... [-f <fn>] \
#   <label> <what> <marker> <timeout_s> <launcher...> -
# where <launcher...> is the *bare* command, with no pty prefix of its own:
# _HI_PTY_FORCED is prepended here; it is filled at source time, so no suite
# has to remember to ask for it. The options are what let every pty-driven
# suite share this one driver instead of forking it:
#   -c <closing>  the line whose appearance means the session is over - the
#                 feeder holds the pipe open until it lands, and it is
#                 asserted as a marker. Default: load()'s "hi closing"; a tier
#                 that never reaches load.sh names its own.
#   -m <marker>   a further must-appear transcript marker (repeatable)
#   -f <fn>       runs inside the feeder between the marker line and the
#                 `exit`: its stdout is typed into the live session, and it
#                 may also do host-side work mid-session
function _hi_interactive_case() {
  local closing="hi closing" feeder=""
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
  # The left side of the pipe runs alongside the session, so it can watch the
  # transcript the session is writing rather than guessing how long it needs.
  # A fixed sleep here was the suite's worst flake: on a loaded runner the
  # input landed before the shell was ready and the marker never appeared.
  # $_HI_INTERACTIVE_SETTLE is the ceiling now, not the wait itself.
  #
  # Reading $out_file on the left while the right writes it is the whole
  # mechanism, not the accident SC2094 warns about: the two sides are separate
  # processes and the reader only ever polls, so there is no truncate-then-read
  # race to hit.
  # shellcheck disable=SC2094
  {
    _hi_poll_bool "$((${_HI_INTERACTIVE_SETTLE:-4} * 4))" 0.25 _hi_session_ready "$out_file" || true
    printf "printf '%%s-%%s\\\\n' %s INTERACTIVE\n" "$marker"
    [ -z "$feeder" ] || "$feeder"
    printf 'exit\n'
    # ...and the same on the way out: hold the pipe open until the closing
    # line lands rather than for a flat two seconds
    _hi_poll_bool 20 0.25 grep -q "$closing" "$out_file" || true
  } | "${_HI_PTY_FORCED[@]}" "$@" >"$out_file" 2>&1 &
  _hi_wait_pid "$!" "$timeout_s" _hi_timed_out "$label" "$timeout_s"
  exit_code="$_HI_WAIT_EXIT"
  t1="$(_hi_now)"

  # both markers: the interactive shell really came up and ran our line, and
  # the session reached its closing line rather than dying early
  # (${a[@]+...}: bash 3.2 + set -u, as above)
  _hi_case_result "$label" "$what" "$exit_code" "$t0" "$t1" "$out_file" \
    "$expected" "$closing" ${extra[@]+"${extra[@]}"}
}
