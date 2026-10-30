#!/bin/sh
# What `tmux`, `zellij`, and `screen` are aliased to in a session
# (common/aliases.sh): mux.sh <tool> [words...]. The tree is this file's
# own, and the config hi carried is $_HI_CONFIG_DIR, which a session's
# children inherit, or the tree's config/.
#
# Typed bare, the multiplexer becomes the session's kept one: `hi --keep` as
# typed there (common/keep.sh's _hi_keep_here), in the tool that was named, so its
# panes are hi's shell, it owns the tree, and the next `hi <target>` attaches
# it. Only where that can hold: a terminal, no multiplexer around this shell
# already, and a session load.sh left hi.keep for. It asks first, the way
# the owner pane's exit does (keep.sh's _hi_keep_stays), since a session
# that stays on the target is the user's to leave: `y` keeps, anything else
# starts nothing and names the plain tool. A session with no
# hi.keep asks too, saying its panes are the machine's own, and `y` goes on
# to the tool.
#
# With words of its own (`tmux attach`, `tmux new -s work`) it is the user's,
# and starts on the config hi carried, as the alias this one replaces did; a
# kept session starts through here too (keep.sh's _hi_keep_start), so each
# tool's config flag is spelled once.
# POSIX sh: it runs where the tool does, bash or not. GLOSSARY: HI.65
_hi_t="$1"
shift
_hi_r="${0%/common/mux.sh}"
_hi_c="${_HI_CONFIG_DIR:-$_hi_r/config}"

# _hi_ask <question> - the question and [y/N] at the terminal, in the yellow
# the exit's ask uses unless $NO_COLOR; true on a y
_hi_ask() {
  if [ -n "${NO_COLOR:-}" ]; then
    printf ' hi: %s [y/N] ' "$1" >&2
  else
    printf '\033[33m hi: %s [y/N] \033[0m' "$1" >&2
  fi
  read -r _hi_a || return 1
  case "$_hi_a" in [yY]*) return 0 ;; esac
  return 1
}

if [ "$#" -eq 0 ] && [ -t 0 ] && [ -z "${TMUX:-}${ZELLIJ:-}${STY:-}" ]; then
  if [ -r "$_hi_r/hi.keep" ]; then
    _hi_as=""
    while IFS= read -r _hi_l; do
      case "$_hi_l" in _HI_KEEP_AS=*) _hi_as="${_hi_l#*=}" ;; esac
    done <"$_hi_r/hi.keep"
    if _hi_ask "$_hi_t here keeps this session on [$_hi_as]: it stays after you disconnect, until nobody has been attached for _HI_KEEP_TIMEOUT (24h unless set); hi $_hi_as comes back to it, hi --end $_hi_as closes it, and its new panes open hi's shell, not the machine's own. Keep it?"; then
      _HI_KEEP_WITH="$_hi_t"
      export _HI_KEEP_WITH
      exec "$_hi_r/hi.sh" --keep
    fi
    case "$_hi_t" in tmux) _hi_e="tmux new -s work" ;; screen) _hi_e="screen -S work" ;; *) _hi_e="zellij -s work" ;; esac
    printf " hi: not kept - %s with words after it (%s) is the plain tool, whose panes open this machine's own shell\n" "$_hi_t" "$_hi_e" >&2
    exit 0
  fi
  # no hi.keep, a container's session or a --no-keep one: the panes are not
  # hi's, and nothing else would say so
  _hi_ask "$_hi_t here opens this machine's own shell in its panes, not hi's, and its session stays on this machine after you disconnect; a kept session takes one hi connected, into bash, started without --no-keep. Start it?" || exit 0
fi
case "$_hi_t" in
tmux) [ ! -f "$_hi_c/tmux/tmux.conf" ] || exec tmux -f "$_hi_c/tmux/tmux.conf" "$@" ;;
screen) [ ! -f "$_hi_c/screenrc" ] || exec screen -c "$_hi_c/screenrc" "$@" ;;
zellij) [ ! -d "$_hi_c/zellij" ] || exec zellij --config-dir "$_hi_c/zellij" "$@" ;;
esac
exec "$_hi_t" "$@"
