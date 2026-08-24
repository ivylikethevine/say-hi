#!/bin/bash
# Unit tests for the desktop-notification feature: shells/notify.sh (the
# emitter), the `hi_notify` alias in misc/aliases.sh, and the
# _HI_DISABLE_NOTIFY toggle.
#
# Built on tests/shells/osc52_test.sh, which is the sibling feature and the
# file to read first. The emitter's job is the same shape - produce exactly the
# right bytes and put them on the tty - so every case here reads the bytes
# through a pipe, which is what the script falls back to with no controlling
# terminal, and matches the literal sequence.
#
# What this one has that OSC 52 does not is a *command* in the middle: the
# escape carries the command line and its exit status, and `hi_notify` has to
# hand that status back to the caller. Those are the cases nothing in the
# sibling suite covers.
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

_HI_ESC=$'\033'
_HI_BEL=$'\a'

# Same gate as the sibling suite: with a tty present the emitter prefers
# /dev/tty, so an interactive run has to be detached or the escapes land on the
# tester's screen instead of the pipe. Skips yellow on a box with no setsid.
if { : </dev/tty; } 2>/dev/null; then
  _HI_EMIT_GATE="setsid"
else
  _HI_EMIT_GATE="sh"
fi

function _hi_detached() {
  if [ "$_HI_EMIT_GATE" = setsid ]; then
    setsid -w "$@"
  else
    "$@"
  fi
}

# the emitter, run with a clean-ish env and its output captured. Everything
# before the `--` is NAME=VALUE for the run (TMUX, TERM, ...); everything after
# is the command it should run.
function _hi_notify() {
  local -a envv=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
    envv+=("$1")
    shift
  done
  shift
  _hi_detached env -u TMUX -u TERM -u ZELLIJ ${envv[@]+"${envv[@]}"} \
    sh "$_HI_NOTIFY" "$@" 2>/dev/null
}

# --- the escape shape -------------------------------------------------------

# Both escapes, spelled out rather than built the way the script builds them: a
# case that assembles the sequence with the same expression would pass against
# a broken one.
function _hi_emits_both_escapes() {
  local out want
  out="$(_hi_notify -- true)"
  want="${_HI_ESC}]9;ok: true${_HI_BEL}${_HI_ESC}]777;notify;hi;ok: true${_HI_BEL}"
  [ "$out" = "$want" ]
}

# the body carries the failing status, which is the whole reason to fire on
# exit rather than before the command runs
function _hi_reports_failure_status() {
  local out want
  out="$(_hi_notify -- sh -c 'exit 7')"
  want="${_HI_ESC}]9;failed (7): sh -c exit 7${_HI_BEL}"
  case "$out" in "$want"*) return 0 ;; esac
  return 1
}

# --- the multiplexer wrapping -----------------------------------------------
#
# Same rule as shells/osc52.sh, and the reason each escape is wrapped on its own
# rather than the pair being wrapped once: tmux's passthrough doubles the inner
# ESC, so one wrap around both would leave the second escape's ESC to terminate
# the DCS early. These cases are what pins that.

function _hi_wraps_each_for_tmux() {
  local out one two
  out="$(_hi_notify TMUX=/tmp/fake,1,0 -- true)"
  one="${_HI_ESC}Ptmux;${_HI_ESC}${_HI_ESC}]9;ok: true${_HI_BEL}${_HI_ESC}\\"
  two="${_HI_ESC}Ptmux;${_HI_ESC}${_HI_ESC}]777;notify;hi;ok: true${_HI_BEL}${_HI_ESC}\\"
  [ "$out" = "$one$two" ]
}

function _hi_wraps_each_for_screen() {
  local out one two
  out="$(_hi_notify TERM=screen-256color -- true)"
  one="${_HI_ESC}P${_HI_ESC}]9;ok: true${_HI_BEL}${_HI_ESC}\\"
  two="${_HI_ESC}P${_HI_ESC}]777;notify;hi;ok: true${_HI_BEL}${_HI_ESC}\\"
  [ "$out" = "$one$two" ]
}

function _hi_raw_for_zellij() {
  local out
  out="$(_hi_notify ZELLIJ=0 TERM=screen-256color -- true)"
  case "$out" in
  "${_HI_ESC}]9;"*) return 0 ;;
  esac
  return 1
}

function _hi_no_wrap_for_xterm() {
  local out
  out="$(_hi_notify TERM=xterm-256color -- true)"
  case "$out" in
  *"${_HI_ESC}P"*) return 1 ;;
  "${_HI_ESC}]9;"*) return 0 ;;
  esac
  return 1
}

# --- the body ---------------------------------------------------------------

# A command line is not base64 the way OSC 52's payload is, so the emitter has
# to defend the escape from what is in it. Two shapes, and the second is the one
# that bit during development: `printf %b` expands a literal backslash-033 typed
# as an *argument* into a real ESC, which breaks straight out of the escape.
# The emitter uses real bytes and `printf %s` for exactly this.
function _hi_body_survives_a_literal_escape_sequence() {
  local out
  out="$(_hi_notify -- echo 'x\033]9;pwned\a')"
  # one ESC per escape, and no more: the argument's backslashes stay text
  [ "$(printf '%s' "$out" | tr -cd "$_HI_ESC" | wc -c)" -eq 2 ] || return 1
  case "$out" in *'\033]9;pwned\a'*) return 0 ;; esac
  return 1
}

# a real ESC or BEL in the argument is stripped rather than passed through
function _hi_body_strips_real_control_bytes() {
  local out body
  out="$(_hi_notify -- echo "$_HI_ESC$_HI_BEL")"
  body="${out#*]9;}"
  body="${body%%"$_HI_BEL"*}"
  [ "$body" = "ok: echo " ]
}

# --- the exit status --------------------------------------------------------
#
# hi_notify wraps a command, so it has to be transparent: dropping the status
# would break every `hi_notify make && ...` written with it.

function _hi_exits_with_the_command_status() {
  local rc=0
  _hi_detached env -u TMUX -u TERM sh "$_HI_NOTIFY" sh -c 'exit 7' \
    >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 7 ]
}

function _hi_exits_zero_on_success() {
  local rc=0
  _hi_detached env -u TMUX -u TERM sh "$_HI_NOTIFY" true >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ]
}

# no command is a usage error, not a silent notification about nothing
function _hi_refuses_with_no_command() {
  local out rc=0
  out="$(env -u TMUX -u TERM sh "$_HI_NOTIFY" 2>&1)" || rc=$?
  [ "$rc" -eq 2 ] || return 1
  case "$out" in *usage*) return 0 ;; esac
  return 1
}

# --- the alias --------------------------------------------------------------

# Every shell aliases.sh has to parse, since the alias line sits in that file's
# POSIX+fish subset - test_lib.sh's _hi_alias_probe holds the two dialects.
function _hi_alias_defined_in() {
  [ "$(_hi_alias_probe "$1" hi_notify _HI_DISABLE_NOTIFY="$2")" = "$3" ]
}

# The container fallback path copies aliases.sh alone, with no paths.sh to
# define $_HI_NOTIFY. A bare `alias hi_notify="sh "` there would drop the user
# into an interactive shell on their own terminal, so the alias must not exist.
function _hi_no_alias_without_paths() {
  [ "$(_hi_alias_probe_bare hi_notify _HI_NOTIFY)" = no ]
}

# --- the toggle -------------------------------------------------------------

function _hi_toggle_in_core_list() {
  case " ${_HI_TOGGLES[*]} " in
  *" _HI_DISABLE_NOTIFY "*) return 0 ;;
  esac
  return 1
}

# config.fish keeps its own copy of the toggle list (fish can't read core.sh's
# array); a toggle added to one and not the other is the exact drift this
# catches.
function _hi_toggle_in_fish_list() {
  grep -q '_HI_DISABLE_NOTIFY' "$_HI_FISH_CONFIG"
}

# _HI_DISABLE_NOTIFY=1 has to keep the emitter off the wire as well as unalias
# it - the same guarantee _HI_DISABLE_OSC52 already makes for the clipboard
# half. hi/payload_test.sh owns the trimming cases; this one is the claim that
# hi.sh knows the file at all, which is what a rename would break.
function _hi_payload_trims_the_emitter() {
  grep -q 'exclude=say-hi/shells/notify.sh' "$_HI_LAUNCHER"
}

function run_notify_test() {
  _hi_h1 "Testing desktop notifications (shells/notify.sh, hi_notify)"
  _hi_workdir notify
  _hi_suite_begin

  _hi_h2 "the escape shape"
  _hi_check_requires "$_HI_EMIT_GATE" "OSC 9 and OSC 777, in that order" _hi_emits_both_escapes
  _hi_check_requires "$_HI_EMIT_GATE" "the body carries a failing status" _hi_reports_failure_status

  _hi_h2 "the multiplexer wrapping"
  _hi_check_requires "$_HI_EMIT_GATE" "each escape wrapped on its own under \$TMUX" _hi_wraps_each_for_tmux
  _hi_check_requires "$_HI_EMIT_GATE" "screen passthrough under TERM=screen*" _hi_wraps_each_for_screen
  _hi_check_requires "$_HI_EMIT_GATE" "raw under \$ZELLIJ, whatever \$TERM says" _hi_raw_for_zellij
  _hi_check_requires "$_HI_EMIT_GATE" "no passthrough under TERM=xterm*" _hi_no_wrap_for_xterm

  _hi_h2 "the body"
  _hi_check_requires "$_HI_EMIT_GATE" "a literal \\033 in an argument stays text" \
    _hi_body_survives_a_literal_escape_sequence
  _hi_check_requires "$_HI_EMIT_GATE" "a real ESC/BEL in an argument is stripped" \
    _hi_body_strips_real_control_bytes

  _hi_h2 "the exit status"
  _hi_check "exits with the command's status" _hi_exits_with_the_command_status
  _hi_check "exits 0 when the command succeeds" _hi_exits_zero_on_success
  _hi_check "refuses with no command" _hi_refuses_with_no_command

  _hi_h2 "the hi_notify alias"
  local shell
  for shell in sh bash zsh fish; do
    _hi_check_requires "$shell" "[$shell] defined by default" _hi_alias_defined_in "$shell" 0 yes
    _hi_check_requires "$shell" "[$shell] gone on _HI_DISABLE_NOTIFY=1" _hi_alias_defined_in "$shell" 1 no
  done
  _hi_check "absent without paths.sh (container fallback)" _hi_no_alias_without_paths

  _hi_h2 "the toggle"
  _hi_check "_HI_DISABLE_NOTIFY in core.sh's _HI_TOGGLES" _hi_toggle_in_core_list
  _hi_check "_HI_DISABLE_NOTIFY in config.fish's copy" _hi_toggle_in_fish_list
  _hi_check "hi.sh trims shells/notify.sh when it is off" _hi_payload_trims_the_emitter

  _hi_suite_end "notify"
}

run_notify_test
