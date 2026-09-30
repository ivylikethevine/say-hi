#!/bin/zsh
# SPDX-License-Identifier: MIT
# oh-my-zsh's prompt hand-over, sourced by common/zsh.zsh once
# _hi_prompt_tool picks it; its own file so a target not handed oh-my-zsh is
# not sent it (GLOSSARY: HI.32). Not loaded by the rc: only the libraries
# themes call into - no plugins, completion, or key bindings - and hi's
# aliases put back over theirs.
if (( ! $+functions[git_prompt_info] )); then
  typeset -gA _hi_a
  _hi_a=("${(@kv)aliases}")
  : "${ZSH:=$HOME/.oh-my-zsh}"
  autoload -Uz colors && colors
  for _hi_l in async_prompt bzr git nvm prompt_info_functions spectrum theme-and-appearance vcs_info; do
    [[ -f $ZSH/lib/$_hi_l.zsh ]] && source "$ZSH/lib/$_hi_l.zsh"
  done
  aliases=("${(@kv)_hi_a}")
  unset _hi_a _hi_l
fi
[[ -f $_hi_omz_theme ]] && source "$_hi_omz_theme"
