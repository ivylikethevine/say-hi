#!/bin/sh
# SPDX-License-Identifier: MIT
# What `tmux`, `zellij`, and `screen` are aliased to in a session
# (common/aliases.sh): mux.sh <tool> [words...]. The tree is this file's
# own, and the config hi carried is $_HI_CONFIG_DIR, which a session's
# children inherit, or the tree's config/.
#
# Typed bare, the multiplexer becomes the session's kept one: `hi --keep` as
# typed there (hi.sh's _hi_keep_here), in the tool that was named, so its
# panes are hi's shell, it owns the tree, and the next `hi <target>` attaches
# it. Only where that can hold: a terminal, no multiplexer around this shell
# already, and a session load.sh left hi.keep for.
#
# With words of its own (`tmux attach`, `tmux new -s work`) it is the user's,
# and starts on the config hi carried, as the alias this one replaces did.
# POSIX sh: it runs where the tool does, bash or not. GLOSSARY: HI.65
_hi_t="$1"
shift
_hi_r="${0%/common/mux.sh}"
_hi_c="${_HI_CONFIG_DIR:-$_hi_r/config}"
if [ "$#" -eq 0 ] && [ -t 0 ] && [ -z "${TMUX:-}${ZELLIJ:-}${STY:-}" ] && [ -r "$_hi_r/hi.keep" ]; then
  _HI_KEEP_WITH="$_hi_t"
  export _HI_KEEP_WITH
  exec "$_hi_r/hi.sh" --keep
fi
case "$_hi_t" in
tmux) [ ! -f "$_hi_c/tmux/tmux.conf" ] || exec tmux -f "$_hi_c/tmux/tmux.conf" "$@" ;;
screen) [ ! -f "$_hi_c/screenrc" ] || exec screen -c "$_hi_c/screenrc" "$@" ;;
zellij) [ ! -d "$_hi_c/zellij" ] || exec zellij --config-dir "$_hi_c/zellij" "$@" ;;
esac
exec "$_hi_t" "$@"
