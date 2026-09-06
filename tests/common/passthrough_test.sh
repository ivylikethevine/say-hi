#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Unit tests for common/passthrough.sh, the one emitter behind hi_copy (stdin
# -> the client's clipboard over OSC 52), hi_notify (a command, then a desktop
# notification over OSC 9/777) and settings/vim.rc's yank autocmd, plus the
# two aliases in settings/aliases.sh and the _HI_DISABLE_PASSTHROUGH toggle
# that covers all of it.
#
# The emitter's whole job is producing exactly the right bytes, so every case
# reads the bytes - captured through a pipe, which is the script's fallback
# when it has no controlling terminal - and matches the literal sequence.
# The emitter *prefers* /dev/tty over stdout (that preference is the point of
# it), so an interactive run must detach it from the terminal or the bytes
# land on the tester's screen - and in their clipboard - instead of the pipe.
#
# What notify has that copy does not is a *command* in the middle: the escape
# carries the command line and its exit status, and `hi_notify` has to hand
# that status back to the caller.
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# $_HI_ESC/$_HI_BEL, the $_HI_EMIT_GATE tty gate and _hi_detached are the
# harness's (tests/lib/fixtures.sh).

# the copy subject, run with a clean-ish env, no controlling terminal, and
# its output captured. $1 is the text to copy; anything after is NAME=VALUE
# for the run (TMUX, TERM, ...).
function _hi_copy() {
  local text="$1"
  shift
  printf '%s' "$text" | _hi_detached env -u TMUX -u TERM -u ZELLIJ "$@" sh "$_HI_PASSTHROUGH" copy
}

# the notify subject, likewise. Everything before the `--` is NAME=VALUE for
# the run; everything after is the command it should run.
function _hi_notify() {
  local -a envv=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
    envv+=("$1")
    shift
  done
  shift
  _hi_detached env -u TMUX -u TERM -u ZELLIJ ${envv[@]+"${envv[@]}"} \
    sh "$_HI_PASSTHROUGH" notify "$@" 2>/dev/null
}

#
# copy

function _hi_copy_emits_plain() {
  local out want
  out="$(_hi_copy hello)"
  # base64 of "hello", spelled out rather than computed - a test that encodes
  # the text the same way the script does would pass on a broken encoder
  want="${_HI_ESC}]52;c;aGVsbG8=${_HI_BEL}"
  [ "$out" = "$want" ]
}

function _hi_copy_unwrapped_payload() {
  # base64 wraps at 76 columns; a newline left in the payload lands mid-escape
  # and the terminal drops the whole sequence. 400 bytes is comfortably past
  # the wrap point.
  local text out
  text="$(printf '%*s' 400 '' | tr ' ' x)"
  out="$(_hi_copy "$text")"
  case "$out" in
  *$'\n'* | *' '*) return 1 ;;
  "${_HI_ESC}]52;c;"*"${_HI_BEL}") return 0 ;;
  esac
  return 1
}

function _hi_copy_wraps_for_tmux() {
  local out
  out="$(_hi_copy hi TMUX=/tmp/fake,1,0)"
  [ "$out" = "${_HI_ESC}Ptmux;${_HI_ESC}${_HI_ESC}]52;c;aGk=${_HI_BEL}${_HI_ESC}\\" ]
}

# $TMUX wins over a screen-shaped $TERM: tmux commonly leaves TERM as
# screen-256color, and wrapping that in screen's DCS instead of tmux's would
# send the passthrough to the wrong multiplexer.
function _hi_copy_tmux_beats_screen_term() {
  local out
  out="$(_hi_copy hi TMUX=/tmp/fake,1,0 TERM=screen-256color)"
  case "$out" in
  "${_HI_ESC}Ptmux;"*) return 0 ;;
  esac
  return 1
}

function _hi_copy_wraps_for_screen() {
  local out
  out="$(_hi_copy hi TERM=screen-256color)"
  [ "$out" = "${_HI_ESC}P${_HI_ESC}]52;c;aGk=${_HI_BEL}${_HI_ESC}\\" ]
}

# zellij handles OSC 52 itself and has no DCS passthrough, so wrapping is the
# one thing that would break it - raw even when TERM looks like screen's
function _hi_copy_raw_for_zellij() {
  local out
  out="$(_hi_copy hi ZELLIJ=0 TERM=screen-256color)"
  [ "$out" = "${_HI_ESC}]52;c;aGk=${_HI_BEL}" ]
}

# tmux inside zellij: the inner multiplexer is the one that must see its
# passthrough first; it unwraps and forwards, and zellij handles the rest
function _hi_copy_tmux_beats_zellij() {
  local out
  out="$(_hi_copy hi TMUX=/tmp/fake,1,0 ZELLIJ=0)"
  case "$out" in
  "${_HI_ESC}Ptmux;"*) return 0 ;;
  esac
  return 1
}

function _hi_copy_no_wrap_for_xterm() {
  local out
  out="$(_hi_copy hi TERM=xterm-256color)"
  [ "$out" = "${_HI_ESC}]52;c;aGk=${_HI_BEL}" ]
}

# Past the cap the escape would be dropped by the terminal anyway; refusing
# loudly beats leaving the user pasting their previous clipboard.
function _hi_copy_refuses_oversize() {
  local out rc=0
  out="$(printf '%*s' 90000 '' | env -u TMUX -u TERM sh "$_HI_PASSTHROUGH" copy 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || return 1
  case "$out" in
  *"OSC 52"*) return 0 ;;
  esac
  return 1
}

#
# notify

# Both escapes, spelled out rather than built the way the script builds them:
# a case that assembles the sequence with the same expression would pass
# against a broken one.
function _hi_notify_emits_both_escapes() {
  local out want
  out="$(_hi_notify -- true)"
  want="${_HI_ESC}]9;ok: true${_HI_BEL}${_HI_ESC}]777;notify;hi;ok: true${_HI_BEL}"
  [ "$out" = "$want" ]
}

# the body carries the failing status, which is the whole reason to fire on
# exit rather than before the command runs
function _hi_notify_reports_failure_status() {
  local out want
  out="$(_hi_notify -- sh -c 'exit 7')"
  want="${_HI_ESC}]9;failed (7): sh -c exit 7${_HI_BEL}"
  case "$out" in "$want"*) return 0 ;; esac
  return 1
}

# Same wrap as copy, and the reason each escape is wrapped on its own rather
# than the pair being wrapped once: tmux's passthrough doubles the inner ESC,
# so one wrap around both would leave the second escape's ESC to terminate
# the DCS early. These cases are what pins that.
function _hi_notify_wraps_each_for_tmux() {
  local out one two
  out="$(_hi_notify TMUX=/tmp/fake,1,0 -- true)"
  one="${_HI_ESC}Ptmux;${_HI_ESC}${_HI_ESC}]9;ok: true${_HI_BEL}${_HI_ESC}\\"
  two="${_HI_ESC}Ptmux;${_HI_ESC}${_HI_ESC}]777;notify;hi;ok: true${_HI_BEL}${_HI_ESC}\\"
  [ "$out" = "$one$two" ]
}

function _hi_notify_wraps_each_for_screen() {
  local out one two
  out="$(_hi_notify TERM=screen-256color -- true)"
  one="${_HI_ESC}P${_HI_ESC}]9;ok: true${_HI_BEL}${_HI_ESC}\\"
  two="${_HI_ESC}P${_HI_ESC}]777;notify;hi;ok: true${_HI_BEL}${_HI_ESC}\\"
  [ "$out" = "$one$two" ]
}

function _hi_notify_raw_for_zellij() {
  local out
  out="$(_hi_notify ZELLIJ=0 TERM=screen-256color -- true)"
  case "$out" in
  "${_HI_ESC}]9;"*) return 0 ;;
  esac
  return 1
}

function _hi_notify_no_wrap_for_xterm() {
  local out
  out="$(_hi_notify TERM=xterm-256color -- true)"
  case "$out" in
  *"${_HI_ESC}P"*) return 1 ;;
  "${_HI_ESC}]9;"*) return 0 ;;
  esac
  return 1
}

# A command line is not base64 the way OSC 52's payload is, so the emitter has
# to defend the escape from what is in it. Two shapes, and the second is the
# one that bit during development: `printf %b` expands a literal backslash-033
# typed as an *argument* into a real ESC, which breaks straight out of the
# escape. The emitter uses real bytes and `printf %s` for exactly this.
#
# The wrapped command is `true` and must not go back to being `echo`. What is
# under test is the *body* the emitter builds out of argv, and `echo`'s
# treatment of a backslash is unspecified by POSIX: bash-as-sh leaves `\033`
# as text, while dash and macOS's /bin/sh expand it. With `echo` the wrapped
# command's own stdout therefore injects a real ESC of its own, and the count
# below reads 3 - on ubuntu and macOS, which is to say on both platforms CI
# runs and neither of the ones a bash-as-sh developer box has. `true` writes
# nothing and still puts the argument on the command line, which is all this
# case ever needed.
function _hi_notify_body_survives_a_literal_escape_sequence() {
  local out
  out="$(_hi_notify -- true 'x\033]9;pwned\a')"
  # one ESC per escape, and no more: the argument's backslashes stay text
  [ "$(printf '%s' "$out" | tr -cd "$_HI_ESC" | wc -c)" -eq 2 ] || return 1
  case "$out" in *'\033]9;pwned\a'*) return 0 ;; esac
  return 1
}

# a real ESC or BEL in the argument is stripped rather than passed through
function _hi_notify_body_strips_real_control_bytes() {
  local out body
  out="$(_hi_notify -- echo "$_HI_ESC$_HI_BEL")"
  body="${out#*]9;}"
  body="${body%%"$_HI_BEL"*}"
  [ "$body" = "ok: echo " ]
}

# the reported command line is cut at 120 characters - a regression losing
# the `cut` would leak an arbitrarily long argument into the notification
function _hi_notify_body_truncates_at_120_chars() {
  local long body out
  long="$(printf 'x%.0s' $(seq 1 200))"
  out="$(_hi_notify -- echo "$long")"
  body="${out#*]9;ok: }"
  body="${body%%"$_HI_BEL"*}"
  [ "${#body}" -eq 120 ]
}

# hi_notify wraps a command, so it has to be transparent: dropping the status
# would break every `hi_notify make && ...` written with it.
function _hi_notify_exits_with_the_command_status() {
  local rc=0
  _hi_detached env -u TMUX -u TERM sh "$_HI_PASSTHROUGH" notify sh -c 'exit 7' \
    >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 7 ]
}

function _hi_notify_exits_zero_on_success() {
  local rc=0
  _hi_detached env -u TMUX -u TERM sh "$_HI_PASSTHROUGH" notify true >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ]
}

# no command is a usage error, not a silent notification about nothing
function _hi_notify_refuses_with_no_command() {
  local out rc=0
  out="$(env -u TMUX -u TERM sh "$_HI_PASSTHROUGH" notify 2>&1)" || rc=$?
  [ "$rc" -eq 2 ] || return 1
  case "$out" in *usage*) return 0 ;; esac
  return 1
}

#
# the script itself

# no subject, or one it does not know, is a usage error - never a silent
# read of stdin that would hang an interactive caller
function _hi_refuses_a_subject() {
  local out rc=0
  out="$(env -u TMUX -u TERM sh "$_HI_PASSTHROUGH" "$@" </dev/null 2>&1)" || rc=$?
  [ "$rc" -eq 2 ] || return 1
  case "$out" in *usage*) return 0 ;; esac
  return 1
}

# _HI_DISABLE_PASSTHROUGH=1 has to keep the emitter off the wire as well as
# unalias it. hi/payload_test.sh owns the trimming cases; this one is the
# claim that hi.sh knows the file at all, which is what a rename would break.
function _hi_payload_trims_the_emitter() {
  # the _HI_TRIM_TABLE row: toggle, then the tree file it takes off the wire
  grep -q '"_HI_DISABLE_PASSTHROUGH|say-hi/common/passthrough.sh|' "$_HI_LAUNCHER"
}

# vim.rc's autocmd, asked of a real vim rather than grepped: the four
# conditions it is guarded by are the whole point of the block.
function _hi_vim_autocmd() {
  local want="$1" out
  shift
  out="$_HI_WORKDIR/vim.$want"
  env "$@" vim -es -u "$_HI_VIMRC" \
    -c "call writefile([string(exists('#hi_osc52'))], '$out')" -c 'qa!' \
    >/dev/null 2>&1 || true
  [ -f "$out" ] && [ "$(cat "$out")" = "$want" ]
}

function run_passthrough_test() {
  _hi_h1 "Testing passthrough (common/passthrough.sh, hi_copy, hi_notify, vim yank)"
  _hi_workdir passthrough
  _hi_suite_begin

  _hi_h2 "copy: the escape"
  _hi_check_requires "$_HI_EMIT_GATE" "plain escape for a plain terminal" _hi_copy_emits_plain
  _hi_check_requires "$_HI_EMIT_GATE" "payload carries no wrap or newline" _hi_copy_unwrapped_payload
  _hi_check_requires "$_HI_EMIT_GATE" "tmux passthrough under \$TMUX" _hi_copy_wraps_for_tmux
  _hi_check_requires "$_HI_EMIT_GATE" "\$TMUX wins over a screen \$TERM" _hi_copy_tmux_beats_screen_term
  _hi_check_requires "$_HI_EMIT_GATE" "screen passthrough under TERM=screen*" _hi_copy_wraps_for_screen
  _hi_check_requires "$_HI_EMIT_GATE" "no passthrough under TERM=xterm*" _hi_copy_no_wrap_for_xterm
  _hi_check_requires "$_HI_EMIT_GATE" "raw under \$ZELLIJ, whatever \$TERM says" _hi_copy_raw_for_zellij
  _hi_check_requires "$_HI_EMIT_GATE" "\$TMUX wins over \$ZELLIJ (inner mux first)" _hi_copy_tmux_beats_zellij
  _hi_check "refuses a payload past the OSC 52 cap" _hi_copy_refuses_oversize

  _hi_h2 "notify: the escape shape"
  _hi_check_requires "$_HI_EMIT_GATE" "OSC 9 and OSC 777, in that order" _hi_notify_emits_both_escapes
  _hi_check_requires "$_HI_EMIT_GATE" "the body carries a failing status" _hi_notify_reports_failure_status

  _hi_h2 "notify: the multiplexer wrapping"
  _hi_check_requires "$_HI_EMIT_GATE" "each escape wrapped on its own under \$TMUX" _hi_notify_wraps_each_for_tmux
  _hi_check_requires "$_HI_EMIT_GATE" "screen passthrough under TERM=screen*" _hi_notify_wraps_each_for_screen
  _hi_check_requires "$_HI_EMIT_GATE" "raw under \$ZELLIJ, whatever \$TERM says" _hi_notify_raw_for_zellij
  _hi_check_requires "$_HI_EMIT_GATE" "no passthrough under TERM=xterm*" _hi_notify_no_wrap_for_xterm

  _hi_h2 "notify: the body"
  _hi_check_requires "$_HI_EMIT_GATE" "a literal \\033 in an argument stays text" \
    _hi_notify_body_survives_a_literal_escape_sequence
  _hi_check_requires "$_HI_EMIT_GATE" "a real ESC/BEL in an argument is stripped" \
    _hi_notify_body_strips_real_control_bytes
  _hi_check_requires "$_HI_EMIT_GATE" "truncated at 120 characters" \
    _hi_notify_body_truncates_at_120_chars

  _hi_h2 "notify: the exit status"
  _hi_check "exits with the command's status" _hi_notify_exits_with_the_command_status
  _hi_check "exits 0 when the command succeeds" _hi_notify_exits_zero_on_success
  _hi_check "refuses with no command" _hi_notify_refuses_with_no_command

  _hi_h2 "the subject"
  _hi_check "no subject is a usage error" _hi_refuses_a_subject
  _hi_check "an unknown subject is refused" _hi_refuses_a_subject bogus

  _hi_h2 "the aliases"
  local shell name
  for name in hi_copy hi_notify; do
    for shell in sh bash zsh fish; do
      _hi_check_requires "$shell" "[$shell] $name defined by default" \
        _hi_alias_defined_in "$shell" "$name" _HI_DISABLE_PASSTHROUGH=0 yes
      _hi_check_requires "$shell" "[$shell] $name gone on _HI_DISABLE_PASSTHROUGH=1" \
        _hi_alias_defined_in "$shell" "$name" _HI_DISABLE_PASSTHROUGH=1 no
    done
    _hi_check "$name absent without paths.sh (container fallback)" \
      _hi_no_alias_without_paths "$name" _HI_PASSTHROUGH
  done

  _hi_h2 "the toggle"
  _hi_check "_HI_DISABLE_PASSTHROUGH in core.sh's _HI_TOGGLES" _hi_toggle_in_core_list _HI_DISABLE_PASSTHROUGH
  _hi_check "_HI_DISABLE_PASSTHROUGH in config.fish's copy" _hi_toggle_in_fish_list _HI_DISABLE_PASSTHROUGH
  _hi_check "hi.sh trims common/passthrough.sh when it is off" _hi_payload_trims_the_emitter

  _hi_h2 "the vim autocmd"
  _hi_check_requires vim "registered in a hi session" \
    _hi_vim_autocmd 1 "_HI_PASSTHROUGH=$_HI_PASSTHROUGH" "_HI_DISABLE_PASSTHROUGH=0"
  _hi_check_requires vim "gone on _HI_DISABLE_PASSTHROUGH=1" \
    _hi_vim_autocmd 0 "_HI_PASSTHROUGH=$_HI_PASSTHROUGH" "_HI_DISABLE_PASSTHROUGH=1"
  _hi_check_requires vim "gone outside a hi session (no \$_HI_PASSTHROUGH)" \
    _hi_vim_autocmd 0 "_HI_PASSTHROUGH=" "_HI_DISABLE_PASSTHROUGH=0"

  _hi_suite_end "passthrough"
}

run_passthrough_test
