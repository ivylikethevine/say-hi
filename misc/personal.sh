#!/bin/sh
# Shared by bash, zsh AND fish, so this file must stay in the subset all three
# parse: `alias`, `export`, `&&` chains - no if/then/fi, no $(...) conditionals.
# shellcheck disable=SC2139 # aliases are meant to expand $_HI_* now, not later
# shellcheck disable=SC2155
# shellcheck disable=SC2089 # the *_OPTS quotes are literal alias text; the overlay source below makes the linter guess otherwise
# GLOSSARY: HI.13 - first-installed wins; reorder to taste.

alias sudo="command sudo " # works in bash/zsh, fish has a sudo wrapper in config.fish

export EDITOR="$_HI_EDITOR_BIN"
alias micro="micro -autoindent=true -colorscheme=darcula -colorcolumn=80 -diffgutter=true -softwrap=true -tabsize=2"
export IDE="$(command -v zeditor || command -v zed || command -v code || command -v vi)"

# cat is bat with our options when bat exists, plain cat otherwise. Everything
# in here is bat syntax, -P (--no-pager) included, which is why it is only ever
# attached behind $_HI_BAT_REAL - see the chain's comment in aliases.sh.
export _HI_BAT_OPTS='-P --tabs 2 --theme Monokai\ Extended\ Bright --style changes,grid'
# batcat is batcat on some Linux distros (fallback to ccat)
# ccat is cat with syntax highlighting (fallback to cat)
alias batcat="$_HI_BATCAT_BIN"
alias bat="batcat"
alias batn="batcat"
[ -n "$_HI_BAT_REAL" ] && alias bat="batcat $_HI_BAT_OPTS" || true
[ -n "$_HI_BAT_REAL" ] && alias batn="batcat $_HI_BAT_OPTS,numbers" || true
alias cat="bat"
alias catn="batn"

alias now='echo "LOCAL: $(date $_HI_HUMAN_SHORT_DATE) => UTC: $(date -u $_HI_HUMAN_SHORT_DATE)"'

alias zed="$(command -v zeditor || command -v zed || command -v echo)"

# eza/exa (its predecessor) improved ls; time format per
# https://docs.rs/chrono/latest/chrono/format/strftime/index.html
export _HI_EXA_SHARED_OPTS='-F -1 -l -m --group-directories-first'
export _HI_EXA_OPTS="$_HI_EXA_SHARED_OPTS --group --no-filesize"
export _HI_EZA_OPTS="$_HI_EXA_SHARED_OPTS"' --smart-group --time-style="+%b %d %Y %H:%M"'
export _HI_EZA_OPTS_SIZE="$_HI_EZA_OPTS --total-size"
alias exa="$_HI_EXA_BIN $_HI_EXA_OPTS"
alias lr="exa"
alias lsx="lr"
alias lra="lr -a"
alias lrt="lr -T -L2"
alias eza="$_HI_EZA_BIN $_HI_EZA_OPTS"
alias lsz="eza"
alias les="eza $_HI_EZA_OPTS_SIZE"
alias lest="eza $_HI_EZA_OPTS_SIZE -T -L2"
alias lesg="eza $_HI_EZA_OPTS_SIZE --git --git-repos-no-status"
alias le="eza --no-filesize"
alias lea="le -a"
alias let="le -T -L2"
alias leg="le --git --git-repos-no-status"
alias l="$_HI_EZA_BIN -l"
