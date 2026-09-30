#!/bin/zsh
# SPDX-License-Identifier: MIT
# powerlevel10k's prompt hand-over, sourced by common/zsh.zsh once
# _hi_prompt_tool picks it; its own file so a target not handed p10k is not
# sent it (GLOSSARY: HI.32). Not loaded by the rc (a target, then): the
# theme, then home's config; loaded, home's config still goes over the
# target's own.
if (( ! $+functions[p10k] )); then
  typeset -g POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
  _hi_p10k_theme && source "$REPLY"
fi
[[ -f $_hi_p10k_cfg ]] && source "$_hi_p10k_cfg"
