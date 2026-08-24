#!/bin/bash
# hi's own bash preferences: history sizing, shell options, readline bindings.
# Taste, not product - which is why they live here rather than in common/bash.sh
# beside the prompt and the aliases that are.
#
# Sourced by common/bash.sh behind $_HI_DISABLE_PERSONAL, and NOT shipped at all
# when that toggle is on (hi.sh's _hi_payload_tar trims it). Your own copy at
# $_HI_CONFIG_DIR/bash.sh is sourced after this one and wins, on
# settings/personal.sh's precedent - additive, never a replacement.
HISTSIZE=2000
HISTFILESIZE=2000
HISTCONTROL="erasedups:ignoreboth"
export HISTIGNORE="&:[ ]*:exit:ls:bg:fg:history:clear"
PROMPT_DIRTRIM=2

shopt -s histappend checkwinsize cmdhist
# globstar is bash 4; on bash 3.2 `shopt -s` on an unknown option is an error,
# which under an rc file that keeps going is noise on every prompt
shopt -s globstar 2>/dev/null || true

bind "set completion-ignore-case on"
bind "set completion-map-case on"
bind "set show-all-if-ambiguous on"
bind "set mark-symlinked-directories on"

bind Space:magic-space
bind '"\e[A": history-search-backward'
bind '"\e[B": history-search-forward'
bind '"\e[C": forward-char'
bind '"\e[D": backward-char'
