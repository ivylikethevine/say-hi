#!/bin/zsh
# hi's own zsh preferences: history sizing, keybindings, completion styling.
# Taste, not product - which is why they live here rather than in shells/zsh.zsh
# beside the prompt and the aliases that are.
#
# Sourced by shells/zsh.zsh behind $_HI_DISABLE_PERSONAL, and NOT shipped at all
# when that toggle is on (hi.sh's _hi_payload_tar trims it). Your own copy at
# $_HI_CONFIG_DIR/zsh.zsh is sourced after this one and wins, on
# misc/personal.sh's precedent - additive, never a replacement.
HISTFILE=~/.zsh_history
HISTSIZE=2000
SAVEHIST=2000

# home/end/delete, plain and ctrl-modified
bindkey "^[OH" beginning-of-line
bindkey "^[[H" beginning-of-line
bindkey "^[[1;5H" backward-word
bindkey "^[[1;5D" backward-word
bindkey "^[OF" end-of-line
bindkey "^[[F" end-of-line
bindkey "^[[1;5F" forward-word
bindkey "^[[1;5C" forward-word
bindkey "^[[3;5~" delete-word

setopt LIST_PACKED
setopt histignorealldups sharehistory
unsetopt beep
bindkey -e

zstyle ':completion:*' menu yes select
zstyle ':completion:*' completer _extensions _expand _complete _correct _approximate
zstyle ':completion:*' file-list all
zstyle ':completion:*' verbose yes
zstyle ':completion:*' use-cache on
zstyle ':completion:*' rehash true
# XDG_CACHE_HOME is unset on most targets, leaving this at an unwritable
# /zsh/.zcompcache - fall back to the spec's own default
zstyle ':completion:*' cache-path "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/.zcompcache"
zstyle ':completion:*' squeeze-slashes true
zstyle ':completion:*' complete-options true
zstyle ':completion:*' group-name ''

zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*:*:-command-:*:*' group-order alias builtins functions commands

zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
