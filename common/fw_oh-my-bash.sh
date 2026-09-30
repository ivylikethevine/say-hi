#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# oh-my-bash's prompt hand-over, sourced by common/bash.sh once
# _hi_prompt_tool picks it; its own file so a target not handed oh-my-bash is
# not sent it (GLOSSARY: HI.32). Not loaded by the rc: all of it but plugins,
# aliases, and completions (none listed), and hi's aliases put back over its
# libraries'.
# shellcheck disable=SC2154 # _hi_omb_theme is common/bash.sh's
if ! declare -F _omb_module_require >/dev/null; then
  _hi_a="$(alias -p)"
  OSH="${OSH:-$HOME/.oh-my-bash}"
  # shellcheck source=/dev/null
  DISABLE_AUTO_UPDATE=true OSH_THEME="" source "$OSH/oh-my-bash.sh"
  unalias -a
  # alias -p's lines, `alias <name>='<value>'`, read back as text: a ' in a
  # value is '\''
  _hi_q="'" _hi_nl=$'\n'
  while [ -n "$_hi_a" ]; do
    _hi_a="${_hi_a#alias }" _hi_a="${_hi_a#-- }"
    _hi_n="${_hi_a%%=*}" _hi_a="${_hi_a#*="$_hi_q"}" _hi_v=""
    while :; do
      [[ $_hi_a == *$_hi_q* ]] || {
        _hi_a=""
        break
      }
      _hi_v+="${_hi_a%%"$_hi_q"*}" _hi_a="${_hi_a#*"$_hi_q"}"
      [[ $_hi_a == "\\$_hi_q$_hi_q"* ]] || break
      _hi_v+=$_hi_q _hi_a="${_hi_a#"\\$_hi_q$_hi_q"}"
    done
    # shellcheck disable=SC2139 # the value is meant to be fixed now
    alias "$_hi_n=$_hi_v"
    _hi_a="${_hi_a#"$_hi_nl"}"
  done
  unset _hi_a _hi_q _hi_nl _hi_n _hi_v
fi
# shellcheck source=/dev/null
[ -f "$_hi_omb_theme" ] && source "$_hi_omb_theme"
