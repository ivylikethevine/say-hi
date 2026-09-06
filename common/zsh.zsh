#!/bin/zsh
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT

# === start required configuration ===
# The tree from this file's own path: %x is this file, :A absolute, :h up one.
# GLOSSARY: HI.33
: "${_HI_HOME:=${${(%):-%x}:A:h:h:h}}"
source "$_HI_HOME/say-hi/common/core.sh"
source "$_HI_GIT_PROMPT"
source "$_HI_ALIASES"

# NOT setopt KSH_ARRAYS: it is global, hi's block runs after oh-my-zsh's, and
# their code assumes zsh's 1-based arrays - core.sh counts instead.
setopt prompt_subst

_hi_interactive_extras

# Primed unconditionally, so a custom PROMPT in the user's own zsh.zsh
# (sourced at the end of this file) can use hi's color hashing with
# _HI_DISABLE_PROMPT=1 - $_HI_HOST_COLOR/$_HI_USER_COLOR are the names %F{} wants.
_hi_prime_identity

if [[ "${_HI_DISABLE_PROMPT:-0}" != 1 ]]; then
  if _hi_wants_starship; then
    # GLOSSARY: HI.32
    eval "$(starship init zsh)"
  else
    # git info through a precmd out-var, never a $( ) in PS1 - the fork-free,
    # pw3nage-safe form bash.sh's ps1() uses
    __hi_git_precmd() { _hi_git_prompt __hi_git_info; }
    precmd_functions+=(__hi_git_precmd)
    # OSC 133 prompt marks and OSC 7 cwd reporting, as common/bash.sh's ps1()
    # emits them; _HI_DISABLE_MARKS=1 turns them off
    _hi_marks_a="" _hi_marks_b=""
    if [[ "${_HI_DISABLE_MARKS:-0}" != 1 ]]; then
      _hi_marks_a=$'%{\e]133;A\a%}'
      _hi_marks_b=$'%{\e]133;B\a%}'
      __hi_marks_precmd() {
        local ec=$?
        printf '\e]133;D;%s\a\e]7;file://%s%s\a' "$ec" "${HOST:-}" "$PWD"
      }
      __hi_marks_preexec() { printf '\e]133;C\a'; }
      precmd_functions=(__hi_marks_precmd "${precmd_functions[@]}")
      preexec_functions+=(__hi_marks_preexec)
    fi
    # concatenated onto the $'...' strings, not interpolated, so zsh's prompt
    # expansion happens at render time rather than at assignment. $_hi_lead is
    # a plain double-quoted segment instead - $_HI_NO_LEAD_SPACE is a static
    # setting, not something that needs re-deciding on every prompt draw.
    _hi_prompt_end ZSH HI_PS1_END
    _hi_lead=" "
    [[ "${_HI_NO_LEAD_SPACE:-0}" == 1 ]] && _hi_lead=""
    if _hi_has_color; then
      export CLICOLOR=1
      export LSCOLORS=gafacadabaegedabagacad
      # %F{} has no bright variants, so brred/brblue/... fall back to their
      # base color. The memos, not $( ): _hi_prime_identity filled both.
      USER_COLOR="${_HI_USER_COLOR//br/}"
      HOST_COLOR="${_HI_HOST_COLOR//br/}"
      # under a color scheme the hex form instead, which %F{} takes from
      # 5.7 on; an older zsh keeps the name (GLOSSARY: HI.50)
      autoload -Uz is-at-least
      if is-at-least 5.7; then
        _hi_hex=""
        _hi_color_hex _hi_hex "$_HI_USER_COLOR"
        [ -n "$_hi_hex" ] && USER_COLOR="#$_hi_hex"
        _hi_color_hex _hi_hex "$_HI_HOST_COLOR"
        [ -n "$_hi_hex" ] && HOST_COLOR="#$_hi_hex"
        unset _hi_hex
      fi
      _hi_at_color=plain
      [ -n "${SSH_TTY:-}" ] && _hi_at_color=yellow
      PS1="$_hi_marks_a$_hi_lead"$'${debian_chroot:-}%F{$USER_COLOR}%n%f%F{$_hi_at_color}@%f%F{$HOST_COLOR}%m%f%F{cyan} %~%f%F{plain}%{${__hi_git_info}%} '"$HI_PS1_END $_hi_marks_b"
    else
      PS1="$_hi_marks_a$_hi_lead"$'${debian_chroot:-}%n@%m %~%{${__hi_git_info}%} '"$HI_PS1_END $_hi_marks_b"
    fi
    unset _hi_lead
  fi
fi

# completion: `hi` from the shared target list, `exa` the same way as `eza`
zmodload zsh/complist
autoload -Uz compinit promptinit
# bare `compinit` costs 50-150ms a start; full check once a day, -C between.
# (#qN.mh+24): N tolerates a missing dump, .mh+24 = older than 24h. -u on the
# full check: compaudit's interactive [y/n] on a group-writable $fpath hangs
# `hi` when piped through something non-interactive (vhs included).
if [[ -n ${ZDOTDIR:-$HOME}/.zcompdump(#qN.mh+24) ]]; then
  compinit -u
  # compinit leaves an unchanged dump's mtime alone, making this branch
  # permanent once the dump turns a day old - touch restarts the clock
  touch "${ZDOTDIR:-$HOME}/.zcompdump" 2>/dev/null || true
else
  compinit -C
fi
promptinit
# The in-shell TTL cache bash.sh's _hi_complete explains, in zsh's dialect.
# (( )) rather than [ ]: zsh's SECONDS is a float once anything typeset -F's it.
# GLOSSARY: HI.26
_HI_TARGET_ROWS=()
_HI_TARGET_DESCS=()
_HI_TARGET_ROWS_AT=-1

_hi() {
  local name kind
  # the word a flag takes (`hi --preview <TAB>`, `hi --use <TAB>`), then
  # hi's own options when the word is one, targets otherwise - the split
  # bash.sh's _hi_complete makes: a flag list must not wait on a backend probe
  if [[ "${words[CURRENT-1]}" == --preview || "${words[CURRENT-1]}" == --use ]]; then
    local -a subjects sdescs
    local srow
    for srow in "${(@f)$(sh "$_HI_TARGETS" words "${words[CURRENT-1]}")}"; do
      subjects+=("${srow%%$'\t'*}")
      sdescs+=("${srow%%$'\t'*} - ${srow#*$'\t'}")
    done
    compadd -d sdescs -a subjects
    return 0
  fi
  if [[ "${words[CURRENT]}" == -* ]]; then
    # "<flag>\t<help>" lines: the flag is the match, the help its description
    local -a flags descs
    local row
    for row in "${(@f)$(sh "$_HI_TARGETS" flags)}"; do
      flags+=("${row%%$'\t'*}")
      descs+=("${row%%$'\t'*} - ${row#*$'\t'}")
    done
    compadd -d descs -a flags
    return 0
  fi
  if (( _HI_TARGET_ROWS_AT < 0 || SECONDS - _HI_TARGET_ROWS_AT >= ${_HI_TARGETS_TTL:-5} )); then
    _HI_TARGET_ROWS=()
    _HI_TARGET_DESCS=()
    while IFS=$'\t' read -r name kind; do
      _HI_TARGET_ROWS+=("$name")
      _HI_TARGET_DESCS+=("$kind - $name")
    done < <(sh "$_HI_TARGETS")
    _HI_TARGET_ROWS_AT=$SECONDS
  fi
  # -V: an unsorted group, so targets.sh's order (recent first) is the menu's
  compadd -V hi-targets -d _HI_TARGET_DESCS -a _HI_TARGET_ROWS
}
compdef _hi hi
# only when something completes `eza`: compdef's service form errors out
# otherwise. _comps is compinit's own command -> completion map, so no fork.
(( ${+_comps[eza]} )) && compdef exa=eza

# see common/bash.sh: children inherit core.sh's _HI_CHILD_ENV and nothing
# else with the prefix. GLOSSARY: HI.47
_hi_unexport
# === end required configuration ===

# see common/bash.sh for why the paths are compared before sourcing
[[ "$_HI_CONFIG_DIR/zsh.zsh" != "$_HI_ROOT/common/zsh.zsh" ]] &&
  [[ -f "$_HI_CONFIG_DIR/zsh.zsh" ]] && source "$_HI_CONFIG_DIR/zsh.zsh"
