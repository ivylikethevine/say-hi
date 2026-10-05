#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Where this user's zsh reads its .zshrc. Sourced by scripts/rc.sh (the file
# install wires and doctor checks) and scripts/pack.sh (the rc a prompt
# framework is found in), after common/core.sh, whose _hi_out it uses; not an
# entry point of its own.
#
# The values matched are ~/.zshenv's to expand (SC2016).
# shellcheck disable=SC2016

# _hi_zshrc_here [outvar] - the .zshrc zsh reads on this machine: under
# $ZDOTDIR, else under what the last ZDOTDIR= line of ~/.zshenv sets, else
# ~/.zshrc. Only a zsh has a ~/.zshenv's ZDOTDIR in its environment, and
# install, doctor, and a connect run from any shell, so the file is read,
# never sourced: a value is a path that starts at /, ~, $HOME, or
# $XDG_CONFIG_HOME (bare, or with its ~/.config default) and expands nothing
# else. Any other value reads as unset.
function _hi_zshrc_here() {
  local _hi_zh_l _hi_zh_v="" _hi_zh_x="${XDG_CONFIG_HOME:-$HOME/.config}"
  local _hi_zh_re="^[[:space:]]*(export[[:space:]]+)?ZDOTDIR=(\"[^\"]*\"|'[^']*'|[^[:space:]#;]*)"
  if [ -n "${ZDOTDIR:-}" ]; then
    _hi_out "${1:-}" "$ZDOTDIR/.zshrc"
    return 0
  fi
  if [ -f "$HOME/.zshenv" ]; then
    while IFS= read -r _hi_zh_l || [ -n "$_hi_zh_l" ]; do
      [[ "$_hi_zh_l" =~ $_hi_zh_re ]] && _hi_zh_v="${BASH_REMATCH[2]}"
    done <"$HOME/.zshenv"
  fi
  _hi_zh_v="${_hi_zh_v#[\"\']}"
  _hi_zh_v="${_hi_zh_v%[\"\']}"
  case "$_hi_zh_v" in
  \~ | \~/*) _hi_zh_v="$HOME${_hi_zh_v#?}" ;;
  '$HOME' | '$HOME/'*) _hi_zh_v="$HOME${_hi_zh_v#?????}" ;;
  '${HOME}' | '${HOME}/'*) _hi_zh_v="$HOME${_hi_zh_v#*\}}" ;;
  '$XDG_CONFIG_HOME' | '$XDG_CONFIG_HOME/'*) _hi_zh_v="$_hi_zh_x${_hi_zh_v#????????????????}" ;;
  '${XDG_CONFIG_HOME}'* | '${XDG_CONFIG_HOME:-$HOME/.config}'* | '${XDG_CONFIG_HOME:-~/.config}'*)
    _hi_zh_v="$_hi_zh_x${_hi_zh_v#*\}}"
    ;;
  esac
  case "$_hi_zh_v" in
  /*) case "$_hi_zh_v" in *['$`']*) _hi_zh_v="$HOME" ;; esac ;;
  *) _hi_zh_v="$HOME" ;;
  esac
  _hi_out "${1:-}" "${_hi_zh_v%/}/.zshrc"
}
