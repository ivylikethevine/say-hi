#!/bin/sh
# <cmd> [args...] -> run it here, then a desktop notification on the *client's*
# terminal emulator. The same trick common/osc52.sh plays for the clipboard: the
# escape rides the pty back, so nothing is installed or running on the target -
# no notify-send, no terminal-notifier, no daemon. Run, not sourced, by the
# `hi_notify` alias in settings/aliases.sh.
#
# `set -u` and not `set -e`: the whole point is to survive the command failing
# and report its status, which -e would turn into an early exit with no
# notification at all.
set -u

if [ "$#" -eq 0 ]; then
  echo "hi_notify: usage: hi_notify <command> [args...]" >&2
  exit 2
fi

# The escape bytes as themselves, not as `\033` for `printf %b` to expand.
# common/osc52.sh can use the %b form safely because its payload is base64,
# which has no backslash in it; a *command line* very much can, and %b would
# turn a literal `\033` typed as an argument into a real ESC that breaks out of
# the escape. Real bytes plus `printf %s` is what makes the body inert.
_HI_ESC="$(printf '\033')"
_HI_BEL="$(printf '\a')"

# One escape, wrapped for whatever multiplexer is in the way, written to the
# tty. Same rule as common/osc52.sh - read that file for why each arm is there.
# A function rather than the straight-line form osc52.sh uses because two
# escapes go out below, and the tmux arm doubles the *inner* ESC: concatenating
# both escapes first and wrapping once would double the first one's ESC and
# leave the second's to terminate the DCS early.
_hi_emit() {
  _hi_esc="$1"
  if [ -n "${TMUX:-}" ]; then
    # tmux wants the inner ESC doubled
    _hi_esc="$_HI_ESC""P""tmux;""$_HI_ESC""$_hi_esc""$_HI_ESC""\\"
  elif [ -n "${ZELLIJ:-}" ]; then
    : # raw - zellij passes these through itself and has no DCS passthrough
  else
    # `case`, not `${TERM#screen}`: dash enforces `set -u` inside ${var#word}
    # (bash does not), and TERM is genuinely unset on CI runners
    case "${TERM:-}" in
    screen*) _hi_esc="$_HI_ESC""P""$_hi_esc""$_HI_ESC""\\" ;;
    esac
  fi
  # the open is the test (`[ -w /dev/tty ]` passes with no controlling
  # terminal); 2>/dev/null so the shell's complaint stays off the screen
  printf '%s' "$_hi_esc" 2>/dev/null >/dev/tty || printf '%s' "$_hi_esc"
}

# The command line, captured *before* running it so nothing it does to the
# positional parameters can rewrite what gets reported. ESC and BEL are the two
# bytes that would end the escape early and leave the rest of the body printed
# on the screen as text; CR and LF break it the way an unstripped newline breaks
# OSC 52. 120 characters because a notification is a glance, not a log, and a
# long pipeline would otherwise fill the popup.
_hi_what="$(printf '%s' "$*" | tr -d '\033\a\r\n' | cut -c1-120)"

"$@"
_hi_rc=$?

if [ "$_hi_rc" -eq 0 ]; then
  _hi_body="ok: $_hi_what"
else
  _hi_body="failed ($_hi_rc): $_hi_what"
fi

# Both escapes, deliberately: OSC 9 is what most emulators
# implement, OSC 777 is iTerm2's spelling, and which one a *client* understands
# is not knowable from the target - $TERM_PROGRAM does not cross an ssh
# connection the way $TERM does. An emulator that understands neither prints
# nothing; one that understands both shows the notification twice, which is the
# price of not being able to ask. Only OSC 777 carries a title field.
_hi_emit "$_HI_ESC]9;$_hi_body$_HI_BEL"
_hi_emit "$_HI_ESC]777;notify;hi;$_hi_body$_HI_BEL"

exit "$_hi_rc"
