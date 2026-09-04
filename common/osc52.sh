#!/bin/sh
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# stdin -> the *client's* clipboard over OSC 52; the escape rides the pty back,
# nothing needed on the target. Run, not sourced, by `hi_copy` and vim.rc's
# yank autocmd, so the wrapping isn't written twice.
set -eu

_hi_b64="$(base64 | tr -d '\r\n')"

# terminals cap the payload (~75KB in xterm, less elsewhere) and drop longer
# ones silently, which reads as "paste gave me my previous clipboard"
if [ "${#_hi_b64}" -gt 100000 ]; then
  echo "hi_copy: too much text for OSC 52 (terminals cap the payload); clipboard unchanged" >&2
  exit 1
fi

# Real bytes, not `\033` for printf %b. Base64 has no backslash, so %b would
# be safe here (unlike notify.sh's command line) - raw bytes anyway, so the
# wrap block below stays byte-for-byte the same as notify.sh's _hi_emit.
_HI_ESC="$(printf '\033')"
_HI_BEL="$(printf '\a')"

_hi_esc="$_HI_ESC]52;c;$_hi_b64$_HI_BEL"

# tmux/screen swallow unknown OSCs unless passthrough-wrapped ($TMUX first:
# tmux leaves TERM as screen-*); zellij handles OSC 52 itself and needs the
# escape raw. Kept as a copy of notify.sh's _hi_emit rather than one sourced
# file: each has its own _HI_DISABLE_* trim-table row (GLOSSARY: HI.39), and a
# shared file would have to ship whenever either toggle is on.
if [ -n "${TMUX:-}" ]; then
  _hi_esc="$_HI_ESC""P""tmux;""$_HI_ESC""$_hi_esc""$_HI_ESC""\\" # tmux wants the inner ESC doubled
elif [ -z "${ZELLIJ:-}" ]; then
  # raw under zellij (it handles OSC 52 itself); `case`, not `${TERM#screen}`:
  # dash enforces `set -u` inside ${var#word}, and TERM is genuinely unset on
  # CI runners
  case "${TERM:-}" in
  # unchunked: real screen truncates a long DCS, so a big yank there can arrive
  # clipped - visibly, and rarely enough not to earn a rejoin loop
  screen*) _hi_esc="$_HI_ESC""P""$_hi_esc""$_HI_ESC""\\" ;;
  esac
fi

# the open is the test (`[ -w /dev/tty ]` passes with no controlling terminal);
# 2>/dev/null so the shell's complaint stays off the screen
printf '%s' "$_hi_esc" 2>/dev/null >/dev/tty || printf '%s' "$_hi_esc"
