#!/bin/sh
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# The one file behind hi_copy, hi_notify and vim.rc's yank autocmd: an escape
# that rides the pty back to the *client's* terminal, so nothing is installed
# or running on the target. Run, not sourced, as `sh passthrough.sh <subject>`:
#
#   copy                stdin -> the client's clipboard over OSC 52
#   notify <cmd...>     run it here, then a desktop notification (OSC 9/777)
#
# One toggle (_HI_DISABLE_PASSTHROUGH) and one _HI_TRIM_TABLE row cover both
# subjects, so this is one file (GLOSSARY: HI.39).
#
# `set -u` and not `set -e`: notify's point is to survive the command failing
# and report its status; copy's failure paths exit explicitly.
set -u

# The escape bytes as themselves, not `\033` for `printf %b`: a notify command
# line can carry a literal `\033`, which %b would turn into a real ESC that
# breaks out of the escape. Real bytes plus `printf %s` keeps the body inert.
_HI_ESC="$(printf '\033')"
_HI_BEL="$(printf '\a')"

# One escape, wrapped for whatever multiplexer is in the way, written to the
# tty. tmux/screen swallow unknown OSCs unless passthrough-wrapped ($TMUX
# first: tmux leaves TERM as screen-*); zellij handles these itself and needs
# the escape raw. A function because notify sends two and the tmux arm doubles
# the *inner* ESC - wrapping both at once would leave the second's ESC to
# terminate the DCS early.
_hi_emit() {
  _hi_esc="$1"
  if [ -n "${TMUX:-}" ]; then
    # tmux wants the inner ESC doubled
    _hi_esc="$_HI_ESC""P""tmux;""$_HI_ESC""$_hi_esc""$_HI_ESC""\\"
  elif [ -z "${ZELLIJ:-}" ]; then
    # `case`, not `${TERM#screen}`: dash enforces `set -u` inside ${var#word},
    # and TERM is genuinely unset on CI runners. Unchunked: real screen
    # truncates a long DCS, so a big yank there can arrive clipped - visibly,
    # and rarely enough not to earn a rejoin loop.
    case "${TERM:-}" in
    screen*) _hi_esc="$_HI_ESC""P""$_hi_esc""$_HI_ESC""\\" ;;
    esac
  fi
  # the open is the test (`[ -w /dev/tty ]` passes with no controlling
  # terminal); 2>/dev/null so the shell's complaint stays off the screen
  printf '%s' "$_hi_esc" 2>/dev/null >/dev/tty || printf '%s' "$_hi_esc"
}

case "${1:-}" in
copy)
  _hi_b64="$(base64 | tr -d '\r\n')"
  # terminals cap the payload (~75KB in xterm, less elsewhere) and drop longer
  # ones silently, which reads as "paste gave me my previous clipboard"
  if [ "${#_hi_b64}" -gt 100000 ]; then
    echo "hi_copy: too much text for OSC 52 (terminals cap the payload); clipboard unchanged" >&2
    exit 1
  fi
  _hi_emit "$_HI_ESC]52;c;$_hi_b64$_HI_BEL"
  ;;
notify)
  shift
  if [ "$#" -eq 0 ]; then
    echo "hi_notify: usage: hi_notify <command> [args...]" >&2
    exit 2
  fi
  # The command line, captured *before* running it so nothing it does can
  # rewrite what gets reported. ESC and BEL would end the escape early; CR
  # and LF break it like an unstripped newline breaks OSC 52. 120 characters:
  # a notification is a glance, not a log.
  _hi_what="$(printf '%s' "$*" | tr -d '\033\a\r\n' | cut -c1-120)"

  "$@"
  _hi_rc=$?

  _hi_body="ok: $_hi_what"
  [ "$_hi_rc" -eq 0 ] || _hi_body="failed ($_hi_rc): $_hi_what"

  # Both escapes: OSC 9 is what most emulators implement, OSC 777 is iTerm2's
  # spelling (and the only one with a title field), and which one the
  # *client* understands is not knowable from the target ($TERM_PROGRAM does
  # not cross ssh). Understanding both shows the notification twice - the
  # price of not being able to ask.
  _hi_emit "$_HI_ESC]9;$_hi_body$_HI_BEL"
  _hi_emit "$_HI_ESC]777;notify;hi;$_hi_body$_HI_BEL"
  exit "$_hi_rc"
  ;;
*)
  echo "passthrough.sh: usage: sh passthrough.sh copy | notify <command> [args...]" >&2
  exit 2
  ;;
esac
