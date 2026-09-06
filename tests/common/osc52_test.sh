#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Unit tests for the OSC 52 clipboard feature: common/osc52.sh (the emitter),
# the `hi_copy` alias in settings/aliases.sh, and settings/vim.rc's yank autocmd.
#
# The emitter's whole job is producing exactly the right bytes, so every case
# reads the bytes - captured through a pipe, which is the script's fallback
# when it has no controlling terminal - and matches the literal sequence.
# The emitter *prefers* /dev/tty over stdout (that preference is the point of
# it), so an interactive run must detach it from the terminal or the bytes
# land on the tester's screen - and in their clipboard - instead of the pipe.
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# $_HI_ESC/$_HI_BEL, the $_HI_EMIT_GATE tty gate and _hi_detached are the
# harness's (tests/lib/fixtures.sh), shared with the notify sibling suite.

# the emitter, run with a clean-ish env, no controlling terminal, and its
# output captured. $1 is the text to copy; anything after is NAME=VALUE for
# the run (TMUX, TERM, ...).
function _hi_emit() {
  local text="$1"
  shift
  printf '%s' "$text" | _hi_detached env -u TMUX -u TERM -u ZELLIJ "$@" sh "$_HI_OSC52"
}

function _hi_emits_plain() {
  local out want
  out="$(_hi_emit hello)"
  # base64 of "hello", spelled out rather than computed - a test that encodes
  # the text the same way the script does would pass on a broken encoder
  want="${_HI_ESC}]52;c;aGVsbG8=${_HI_BEL}"
  [ "$out" = "$want" ]
}

function _hi_unwrapped_payload() {
  # base64 wraps at 76 columns; a newline left in the payload lands mid-escape
  # and the terminal drops the whole sequence. 400 bytes is comfortably past
  # the wrap point.
  local text out
  text="$(printf '%*s' 400 '' | tr ' ' x)"
  out="$(_hi_emit "$text")"
  case "$out" in
  *$'\n'* | *' '*) return 1 ;;
  "${_HI_ESC}]52;c;"*"${_HI_BEL}") return 0 ;;
  esac
  return 1
}

function _hi_wraps_for_tmux() {
  local out
  out="$(_hi_emit hi TMUX=/tmp/fake,1,0)"
  [ "$out" = "${_HI_ESC}Ptmux;${_HI_ESC}${_HI_ESC}]52;c;aGk=${_HI_BEL}${_HI_ESC}\\" ]
}

# $TMUX wins over a screen-shaped $TERM: tmux commonly leaves TERM as
# screen-256color, and wrapping that in screen's DCS instead of tmux's would
# send the passthrough to the wrong multiplexer.
function _hi_tmux_beats_screen_term() {
  local out
  out="$(_hi_emit hi TMUX=/tmp/fake,1,0 TERM=screen-256color)"
  case "$out" in
  "${_HI_ESC}Ptmux;"*) return 0 ;;
  esac
  return 1
}

function _hi_wraps_for_screen() {
  local out
  out="$(_hi_emit hi TERM=screen-256color)"
  [ "$out" = "${_HI_ESC}P${_HI_ESC}]52;c;aGk=${_HI_BEL}${_HI_ESC}\\" ]
}

# zellij handles OSC 52 itself and has no DCS passthrough, so wrapping is the
# one thing that would break it - raw even when TERM looks like screen's
function _hi_raw_for_zellij() {
  local out
  out="$(_hi_emit hi ZELLIJ=0 TERM=screen-256color)"
  [ "$out" = "${_HI_ESC}]52;c;aGk=${_HI_BEL}" ]
}

# tmux inside zellij: the inner multiplexer is the one that must see its
# passthrough first; it unwraps and forwards, and zellij handles the rest
function _hi_tmux_beats_zellij() {
  local out
  out="$(_hi_emit hi TMUX=/tmp/fake,1,0 ZELLIJ=0)"
  case "$out" in
  "${_HI_ESC}Ptmux;"*) return 0 ;;
  esac
  return 1
}

function _hi_no_wrap_for_xterm() {
  local out
  out="$(_hi_emit hi TERM=xterm-256color)"
  [ "$out" = "${_HI_ESC}]52;c;aGk=${_HI_BEL}" ]
}

# Past the cap the escape would be dropped by the terminal anyway; refusing
# loudly beats leaving the user pasting their previous clipboard.
function _hi_refuses_oversize() {
  local out rc=0
  out="$(printf '%*s' 90000 '' | env -u TMUX -u TERM sh "$_HI_OSC52" 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || return 1
  case "$out" in
  *"OSC 52"*) return 0 ;;
  esac
  return 1
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

function run_osc52_test() {
  _hi_h1 "Testing OSC 52 clipboard (common/osc52.sh, hi_copy, vim yank)"
  _hi_workdir osc52
  _hi_suite_begin

  _hi_h2 "the emitter"
  _hi_check_requires "$_HI_EMIT_GATE" "plain escape for a plain terminal" _hi_emits_plain
  _hi_check_requires "$_HI_EMIT_GATE" "payload carries no wrap or newline" _hi_unwrapped_payload
  _hi_check_requires "$_HI_EMIT_GATE" "tmux passthrough under \$TMUX" _hi_wraps_for_tmux
  _hi_check_requires "$_HI_EMIT_GATE" "\$TMUX wins over a screen \$TERM" _hi_tmux_beats_screen_term
  _hi_check_requires "$_HI_EMIT_GATE" "screen passthrough under TERM=screen*" _hi_wraps_for_screen
  _hi_check_requires "$_HI_EMIT_GATE" "no passthrough under TERM=xterm*" _hi_no_wrap_for_xterm
  _hi_check_requires "$_HI_EMIT_GATE" "raw under \$ZELLIJ, whatever \$TERM says" _hi_raw_for_zellij
  _hi_check_requires "$_HI_EMIT_GATE" "\$TMUX wins over \$ZELLIJ (inner mux first)" _hi_tmux_beats_zellij
  _hi_check "refuses a payload past the OSC 52 cap" _hi_refuses_oversize

  _hi_h2 "the hi_copy alias"
  local shell
  for shell in sh bash zsh fish; do
    _hi_check_requires "$shell" "[$shell] defined by default" \
      _hi_alias_defined_in "$shell" hi_copy _HI_DISABLE_PASSTHROUGH=0 yes
    _hi_check_requires "$shell" "[$shell] gone on _HI_DISABLE_PASSTHROUGH=1" \
      _hi_alias_defined_in "$shell" hi_copy _HI_DISABLE_PASSTHROUGH=1 no
  done
  _hi_check "absent without paths.sh (container fallback)" \
    _hi_no_alias_without_paths hi_copy _HI_OSC52

  _hi_h2 "the toggle"
  _hi_check "_HI_DISABLE_PASSTHROUGH in core.sh's _HI_TOGGLES" _hi_toggle_in_core_list _HI_DISABLE_PASSTHROUGH
  _hi_check "_HI_DISABLE_PASSTHROUGH in config.fish's copy" _hi_toggle_in_fish_list _HI_DISABLE_PASSTHROUGH

  _hi_h2 "the vim autocmd"
  _hi_check_requires vim "registered in a hi session" \
    _hi_vim_autocmd 1 "_HI_OSC52=$_HI_OSC52" "_HI_DISABLE_PASSTHROUGH=0"
  _hi_check_requires vim "gone on _HI_DISABLE_PASSTHROUGH=1" \
    _hi_vim_autocmd 0 "_HI_OSC52=$_HI_OSC52" "_HI_DISABLE_PASSTHROUGH=1"
  _hi_check_requires vim "gone outside a hi session (no \$_HI_OSC52)" \
    _hi_vim_autocmd 0 "_HI_OSC52=" "_HI_DISABLE_PASSTHROUGH=0"

  _hi_suite_end "OSC 52"
}

run_osc52_test
