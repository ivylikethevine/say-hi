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
  eval "$_hi_a"
  unset _hi_a
fi
# shellcheck source=/dev/null
[ -f "$_hi_omb_theme" ] && source "$_hi_omb_theme"
