#!/bin/zsh
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT

# === start required configuration ===
# see common/bash.sh: re-entered while loading, return. GLOSSARY: HI.55
[[ -z "${_hi_rc_loading-}" ]] || return 0
_hi_rc_loading=1
# The tree from this file's own path: %x is this file, :A absolute, :h up one.
# GLOSSARY: HI.33
: "${_HI_HOME:=${${(%):-%x}:A:h:h:h}}"
source "$_HI_HOME/say-hi/common/core.sh"
source "$_HI_GIT_PROMPT"
source "$_HI_ENV_PROMPT"
source "$_HI_ALIASES"

# NOT setopt KSH_ARRAYS: it is global, hi's block runs after oh-my-zsh's, and
# their code assumes zsh's 1-based arrays - core.sh counts instead.
setopt prompt_subst

_hi_interactive_extras

# Primed unconditionally, so a custom PROMPT in the user's own zsh.zsh
# (sourced at the end of this file) can use hi's color hashing with
# _HI_DISABLE_PROMPT=1 - $_HI_HOST_COLOR/$_HI_USER_COLOR are the names; %F{} wants
# _hi_color_base's answer for one of the extras.
_hi_prime_identity

if [[ "${_HI_DISABLE_PROMPT:-0}" != 1 ]]; then
  if _hi_wants_prompt_tool; then
    # GLOSSARY: HI.32
    eval "$("$_HI_PROMPT_TOOL" init zsh)"
  else
    # git info through a precmd out-var, never a $( ) in PS1 - the fork-free,
    # pw3nage-safe form bash.sh's ps1() uses
    __hi_git_precmd() { _hi_git_prompt __hi_git_info; }
    precmd_functions+=(__hi_git_precmd)
    # zsh keeps the $PS1 it was given, so another tool's prefix is still on
    # screen and hi stands down for it. GLOSSARY: HI.54
    _HI_ENV_DEFER=1
    __hi_env_precmd() { _hi_env_prompt __hi_env_info; }
    precmd_functions+=(__hi_env_precmd)
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
    # a plain double-quoted segment instead - $_HI_DISABLE_LEAD_SPACE is a static
    # setting, not something that needs re-deciding on every prompt draw.
    _hi_prompt_end ZSH HI_PS1_END
    _hi_lead=" "
    [[ "${_HI_DISABLE_LEAD_SPACE:-0}" == 1 ]] && _hi_lead=""
    if _hi_has_color; then
      export CLICOLOR=1
      export LSCOLORS=gafacadabaegedabagacad
      # %F{} knows the sixteen and no bright variants: an extra name (orange)
      # is its 16-color base first, then brred/brblue/... lose the br. The
      # memos, not $( ): _hi_prime_identity filled both.
      _hi_color_base USER_COLOR "$_HI_USER_COLOR"
      _hi_color_base HOST_COLOR "$_HI_HOST_COLOR"
      USER_COLOR="${USER_COLOR//br/}"
      HOST_COLOR="${HOST_COLOR//br/}"
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
      PS1="$_hi_marks_a$_hi_lead"$'%F{cyan}${__hi_env_info}%f${debian_chroot:-}%F{$USER_COLOR}%n%f%F{$_hi_at_color}@%f%F{$HOST_COLOR}%m%f%F{cyan} %~%f%F{plain}%{${__hi_git_info}%} '"$HI_PS1_END $_hi_marks_b"
    else
      PS1="$_hi_marks_a$_hi_lead"$'${__hi_env_info}${debian_chroot:-}%n@%m %~%{${__hi_git_info}%} '"$HI_PS1_END $_hi_marks_b"
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
  local name kind sym
  # the word a flag takes (`hi --preview <TAB>`, `hi --use <TAB>`), then
  # hi's own options when the word is one, targets otherwise - the split
  # bash.sh's _hi_complete makes: a flag list must not wait on a backend probe
  if [[ " $_HI_WORD_FLAGS " == *" ${words[CURRENT-1]} "* ]]; then
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
    # "<flag>\t<help>" lines: the flag is the match, the help its description;
    # behind a local command (`hi --install --<TAB>`) its own switches instead
    local -a flags descs
    local row
    for row in "${(@f)$(sh "$_HI_TARGETS" flags "${words[2]}")}"; do
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
      _hi_target_symbol sym "$kind"
      _HI_TARGET_DESCS+=("$sym $kind - $name")
    done < <(sh "$_HI_TARGETS")
    _HI_TARGET_ROWS_AT=$SECONDS
  fi
  # -V: an unsorted group, so targets.sh's order is the menu's; through
  # _description, so the hi-targets tag's list-colors (below) applies
  local -a expl
  _description -V hi-targets expl target
  compadd "${expl[@]}" -d _HI_TARGET_DESCS -a _HI_TARGET_ROWS
}
# hi.sh too: zsh expands paths.sh's `hi` alias before completing, so the
# command it looks up is the launcher's name, not `hi`
compdef _hi hi "${_HI_LAUNCHER:t}"
# The target list colored by backend, matched on the kind after each line's
# symbol ("▣ docker - web"): ssh yellow, the container family blue, nomad
# green, kube light purple, in hi's palette so a color scheme repaints them. None under
# $NO_COLOR, and never over a list-colors of your own for the same context.
() {
  local kind color esc
  local -a spec
  zstyle -g esc ':completion:*:hi-targets' list-colors && return
  for kind color in ssh yellow "(${(j:|:)${=_HI_CONTAINER_CLIS}})" blue nomad green kube brmagenta; do
    _hi_color_escape_var esc "$color"
    [[ -n $esc ]] || return 0
    esc=${esc#\\e\[}
    spec+=("=* $kind - *=${esc%m}")
  done
  zstyle ':completion:*:hi-targets' list-colors "${spec[@]}"
}
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
# see common/bash.sh: a local interactive shell greets with hi's header,
# drawn by bash since header.sh is bash's, handed the session values
# _hi_unexport kept back (as config.fish's __hi_bash does)
[[ -o interactive && -z "${ZSH_EXECUTION_STRING-}" && "$_HI_REMOTE_SESSION" != 1 &&
  "${_HI_DISABLE_HEADER:-0}" != 1 ]] && () {
  local n
  local -a kv
  for n in $_HI_SESSION_VARS; do (( ${+parameters[$n]} )) && kv+=("$n=${(P)n}"); done
  env "${kv[@]}" COLUMNS=$COLUMNS bash -c 'source "$1" && hi_header Online' hi "$_HI_HEADER"
}
unset _hi_rc_loading
