#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# bash-it's prompt hand-over, sourced by common/bash.sh once _hi_prompt_tool
# picks it; its own file so a target not handed bash-it is not sent it
# (GLOSSARY: HI.32).
# shellcheck disable=SC2154 # _hi_bashit_theme is common/bash.sh's
if ! declare -F _bash-it-log-prefix-by-path >/dev/null; then
  # not loaded by the rc: bash_it.sh's own loader takes a literal path in
  # BASH_IT_THEME (sourced directly, no name lookup), so unlike oh-my-bash
  # this needs no separate theme step - _hi_prompt_fw already required a
  # home theme to exist before selecting bash-it here in the first place
  BASH_IT="${BASH_IT:-$HOME/.bash_it}"
  # shellcheck source=/dev/null
  BASH_IT_THEME="$_hi_bashit_theme" DISABLE_AUTO_UPDATE=true source "$BASH_IT/bash_it.sh"
else
  # already loaded with its own theme, whose precmd_functions entry
  # (prompt_command, the fixed name most bundled themes use) survives
  # sourcing a different theme file over it - bash-preexec's
  # safe_append_prompt_command only ever adds, so the rc's own theme
  # would keep redrawing every prompt after this one otherwise. Clear
  # it first, as bash.sh's hi-named unhook does.
  _hi_drop_prompt_command precmd_functions
  # shellcheck source=/dev/null
  [ -f "$_hi_bashit_theme" ] && source "$_hi_bashit_theme"
fi
