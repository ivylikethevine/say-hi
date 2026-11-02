#!/usr/bin/env bash
# Where this user's zsh reads its .zshrc. Sourced by scripts/rc.sh (the file
# install wires and doctor checks) and scripts/pack.sh (the rc a prompt
# framework is found in), after common/core.sh, whose _hi_out it uses; not an
# entry point of its own.
#
# The values matched are ~/.zshenv's to expand (SC2016).
# shellcheck disable=SC2016

# _hi_rc_last_match <regex> <outvar> <file...> - the second group of the last
# line of <file...> the regex matches, into <outvar>; 1 when none does. What
# an rc *sets* - a theme name, a flag on an init line - lives in a shell
# variable or a command line no child of the rc sees, so the file is read,
# never sourced. An absent file is skipped.
function _hi_rc_last_match() {
  local _hi_rl_re="$1" _hi_rl_out="$2" _hi_rl_f _hi_rl_l _hi_rl_v=""
  shift 2
  for _hi_rl_f; do
    [ -f "$_hi_rl_f" ] || continue
    while IFS= read -r _hi_rl_l || [ -n "$_hi_rl_l" ]; do
      [[ "$_hi_rl_l" =~ $_hi_rl_re ]] && _hi_rl_v="${BASH_REMATCH[2]}"
    done <"$_hi_rl_f"
  done
  [ -n "$_hi_rl_v" ] && printf -v "$_hi_rl_out" '%s' "$_hi_rl_v"
}

# _hi_rc_value <NAME> <outvar> <file...> - what the last NAME= line of
# <file...> sets, its quotes dropped; 1 when none does, or it sets nothing
function _hi_rc_value() {
  local _hi_rv=""
  _hi_rc_last_match "^[[:space:]]*(export[[:space:]]+)?$1=(\"[^\"]*\"|'[^']*'|[^[:space:]#;]*)" _hi_rv "${@:3}" || return 1
  _hi_rv="${_hi_rv#[\"\']}"
  _hi_rv="${_hi_rv%[\"\']}"
  [ -n "$_hi_rv" ] && printf -v "$2" '%s' "$_hi_rv"
}

# _hi_zshrc_here [outvar] - the .zshrc zsh reads on this machine: under
# $ZDOTDIR, else under what the last ZDOTDIR= line of ~/.zshenv sets, else
# ~/.zshrc. Only a zsh has a ~/.zshenv's ZDOTDIR in its environment, and
# install, doctor, and a connect run from any shell, so the file is read,
# never sourced: a value is a path that starts at /, ~, $HOME, or
# $XDG_CONFIG_HOME (bare, or with its ~/.config default) and expands nothing
# else. Any other value reads as unset.
function _hi_zshrc_here() {
  local _hi_zh_v="" _hi_zh_x="${XDG_CONFIG_HOME:-$HOME/.config}"
  if [ -n "${ZDOTDIR:-}" ]; then
    _hi_out "${1:-}" "$ZDOTDIR/.zshrc"
    return 0
  fi
  _hi_rc_value ZDOTDIR _hi_zh_v "$HOME/.zshenv" || :
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
