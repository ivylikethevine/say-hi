#!/bin/zsh

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

if [[ "${_HI_DISABLE_PROMPT:-0}" != 1 ]]; then
  if _hi_wants_starship; then
    # GLOSSARY: HI.32
    eval "$(starship init zsh)"
  else
    _hi_prime_identity
    # git info through a precmd out-var reference, never a $( ) in PS1 - the
    # fork-free, pw3nage-safe form bash.sh's ps1() uses
    __hi_git_precmd() { _hi_git_prompt __hi_git_info; }
    precmd_functions+=(__hi_git_precmd)
    # concatenated onto the $'...' strings, not interpolated, so zsh's prompt
    # expansion happens at render time rather than at assignment
    HI_PS1_END="$(_hi_prompt_end ZSH)"
    if _hi_has_color; then
      export CLICOLOR=1
      export LSCOLORS=gafacadabaegedabagacad
      # %F{} has no bright variants, so brred/brblue/... fall back to their base color
      USER_COLOR="${$(_hi_user_color)//br/}"
      HOST_COLOR="${$(_hi_host_color)//br/}"
      _hi_at_color=plain
      [ -n "${SSH_TTY:-}" ] && _hi_at_color=yellow
      PS1=$' ${debian_chroot:-}%F{$USER_COLOR}%n%f%F{$_hi_at_color}@%f%F{$HOST_COLOR}%m%f%F{cyan} %~%f%F{plain}%{${__hi_git_info}%} '"$HI_PS1_END"' '
    else
      PS1=$' ${debian_chroot:-}%n@%m %~%{${__hi_git_info}%} '"$HI_PS1_END"' '
    fi
  fi
fi

# completion: `hi` from the shared target list, `exa` the same way as `eza`
zmodload zsh/complist
autoload -Uz compinit promptinit
# bare `compinit` costs 50-150ms a start; full check once a day, -C between.
# (#qN.mh+24): N tolerates a missing dump, .mh+24 = older than 24h.
if [[ -n ${ZDOTDIR:-$HOME}/.zcompdump(#qN.mh+24) ]]; then
  compinit
  # compinit leaves an unchanged dump's mtime alone, making this branch
  # permanent once the dump turns a day old - touch restarts the clock
  touch "${ZDOTDIR:-$HOME}/.zcompdump" 2>/dev/null || true
else
  compinit -C
fi
promptinit
# The in-shell TTL cache bash.sh's _hi_complete explains, in zsh's dialect -
# including the part where this window and the file cache's are offset, so the
# two stack to nearly twice the TTL.
# (( )) rather than [ ]: zsh's SECONDS is a float once anything typeset -F's it.
# GLOSSARY: HI.26
_HI_TARGET_ROWS=()
_HI_TARGET_DESCS=()
_HI_TARGET_ROWS_AT=-1

_hi() {
  local name kind
  # hi's own options when the word is one, targets otherwise - the same split
  # bash.sh's _hi_complete makes, and for the same reason: a flag list must not
  # wait on a backend probe. Unlike targets it is not cached; it is a dozen
  # printfs.
  if [[ "${words[CURRENT]}" == -* ]]; then
    local -a flags
    flags=("${(@f)$(sh "$_HI_TARGETS" flags)}")
    compadd -a flags
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
  compadd -d _HI_TARGET_DESCS -a _HI_TARGET_ROWS
}
compdef _hi hi
# only when something actually completes `eza`: compdef's service form errors
# out when the right-hand side has no binding, which is every shell without
# eza. _comps is compinit's own command -> completion map, so no fork.
(( ${+_comps[eza]} )) && compdef exa=eza
# === end required configuration ===

# see common/bash.sh for why the paths are compared before sourcing
[[ "$_HI_CONFIG_DIR/zsh.zsh" != "$_HI_ROOT/common/zsh.zsh" ]] &&
  [[ -f "$_HI_CONFIG_DIR/zsh.zsh" ]] && source "$_HI_CONFIG_DIR/zsh.zsh"
