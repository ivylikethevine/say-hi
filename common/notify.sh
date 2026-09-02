#!/bin/sh
# <cmd> [args...] -> run it here, then a desktop notification on the *client's*
# terminal emulator: the escape rides the pty back, so nothing is installed on
# the target (the same trick common/osc52.sh plays for the clipboard). Run,
# not sourced, by the `hi_notify` alias in settings/aliases.sh.
#
# `set -u` and not `set -e`: the point is to survive the command failing and
# report its status.
set -u

if [ "$#" -eq 0 ]; then
  echo "hi_notify: usage: hi_notify <command> [args...]" >&2
  exit 2
fi

# The escape bytes as themselves, not `\033` for `printf %b`: a command line
# can carry a literal `\033`, which %b would turn into a real ESC that breaks
# out of the escape. Real bytes plus `printf %s` keeps the body inert.
_HI_ESC="$(printf '\033')"
_HI_BEL="$(printf '\a')"

# One escape, wrapped for whatever multiplexer is in the way, written to the
# tty. Same wrap as common/osc52.sh. A function because two escapes go out
# below and the tmux arm doubles the *inner* ESC - wrapping both at once
# would leave the second's ESC to terminate the DCS early.
_hi_emit() {
  _hi_esc="$1"
  if [ -n "${TMUX:-}" ]; then
    # tmux wants the inner ESC doubled
    _hi_esc="$_HI_ESC""P""tmux;""$_HI_ESC""$_hi_esc""$_HI_ESC""\\"
  elif [ -z "${ZELLIJ:-}" ]; then
    # raw under zellij (it passes these through itself, no DCS passthrough);
    # `case`, not `${TERM#screen}`: dash enforces `set -u` inside ${var#word},
    # and TERM is genuinely unset on CI runners
    case "${TERM:-}" in
    screen*) _hi_esc="$_HI_ESC""P""$_hi_esc""$_HI_ESC""\\" ;;
    esac
  fi
  # the open is the test (`[ -w /dev/tty ]` passes with no controlling
  # terminal); 2>/dev/null so the shell's complaint stays off the screen
  printf '%s' "$_hi_esc" 2>/dev/null >/dev/tty || printf '%s' "$_hi_esc"
}

# The command line, captured *before* running it so nothing it does can
# rewrite what gets reported. ESC and BEL would end the escape early; CR and
# LF break it like an unstripped newline breaks OSC 52. 120 characters: a
# notification is a glance, not a log.
_hi_what="$(printf '%s' "$*" | tr -d '\033\a\r\n' | cut -c1-120)"

"$@"
_hi_rc=$?

_hi_body="ok: $_hi_what"
[ "$_hi_rc" -eq 0 ] || _hi_body="failed ($_hi_rc): $_hi_what"

# Both escapes: OSC 9 is what most emulators implement, OSC 777 is iTerm2's
# spelling (and the only one with a title field), and which one the *client*
# understands is not knowable from the target ($TERM_PROGRAM does not cross
# ssh). Understanding both shows the notification twice - the price of not
# being able to ask.
_hi_emit "$_HI_ESC]9;$_hi_body$_HI_BEL"
_hi_emit "$_HI_ESC]777;notify;hi;$_hi_body$_HI_BEL"

exit "$_hi_rc"
