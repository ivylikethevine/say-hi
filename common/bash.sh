#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# set -euo pipefail # cannot be enabled: an interactive shell would exit on the first error

# === start required configuration ===
# $_HI_HOME first, this file's own path as the fallback for a hand-written
# `source` (hi.sh and install.sh's rc line set it). GLOSSARY: HI.33
: "${_HI_HOME:=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck source=./core.sh
source "$_HI_HOME/say-hi/common/core.sh"
# shellcheck source=./git_prompt.sh
source "$_HI_GIT_PROMPT"
# shellcheck source=../settings/aliases.sh
source "$_HI_ALIASES"

_hi_interactive_extras
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# Primed unconditionally, so a custom PS1 in the user's own bash.sh
# (sourced at the end of this file) can use hi's per-host/per-user color
# hashing with _HI_DISABLE_PROMPT=1. $_HI_HOST_ESC/$_HI_USER_ESC are the
# ready-to-embed escapes; core.sh's _hi_prime_identity stops at the color
# names (zsh's %F{} wants those), so bash primes its own on top.
_hi_prime_identity
_hi_host_escape >/dev/null
_hi_user_escape >/dev/null

if [[ "${_HI_DISABLE_PROMPT:-0}" != 1 ]] && ! _hi_wants_starship; then
  # `\$` renders as $ for a user and # for root - see core.sh's _hi_prompt_end
  HI_PS1_END=""
  _hi_prompt_end BASH HI_PS1_END
  _hi_ps1_lead=" "
  [[ "${_HI_NO_LEAD_SPACE:-0}" == 1 ]] && _hi_ps1_lead=""
  if _hi_has_color; then
    # the *_var forms: a cache read, not a $( ) fork. Spelled empty first, so
    # the linter sees the `printf -v` assignment (SC2154); file scope, no `local`.
    _hi_ps1_u="" _hi_ps1_h="" _hi_ps1_at="$NC"
    _hi_user_escape _hi_ps1_u
    _hi_host_escape _hi_ps1_h
    [ -n "${SSH_TTY:-}" ] && _hi_ps1_at="$YELLOW"
    HI_PS1="$_hi_ps1_lead${debian_chroot:-}\[$_hi_ps1_u\]\u\[$_hi_ps1_at\]@\[$_hi_ps1_h\]\h\[$NC\] \[$BRBLUE\]\w\[$NC\]"
    unset _hi_ps1_u _hi_ps1_h _hi_ps1_at
  else
    HI_PS1="$_hi_ps1_lead${debian_chroot:-}\u@\h:\w"
  fi
  unset _hi_ps1_lead
fi

if ! shopt -oq posix; then
  # $BASH_COMPLETION_VERSINFO is the loader's own sentinel: the host's stock
  # rc often sourced it already, and re-parsing costs 20-50ms a shell
  # shellcheck disable=SC1091
  [ -n "${BASH_COMPLETION_VERSINFO-}" ] ||
    source /usr/share/bash-completion/bash_completion 2>/dev/null ||
    source /etc/bash_completion 2>/dev/null
fi

# complete `hi` from the same target list zsh/fish use, and make `exa`
# complete the way `eza` does.
#
# targets.sh file-caches for $_HI_TARGETS_TTL seconds, but finding that out is
# still a fork; holding the names in the shell for the same window makes it
# free. The two windows are offset (this one starts at the last read, the
# file's at its write), so the worst case is close to twice the TTL; only
# _HI_TARGETS_TTL=0 turns both off. $SECONDS because it is a builtin; -1 is
# "never filled". GLOSSARY: HI.26
_HI_TARGET_NAMES=""
_HI_TARGET_NAMES_AT=-1

function _hi_target_names() {
  local -a rows=()
  if [ "$_HI_TARGET_NAMES_AT" -ge 0 ] &&
    [ "$((SECONDS - _HI_TARGET_NAMES_AT))" -lt "${_HI_TARGETS_TTL:-5}" ]; then
    return 0
  fi
  _hi_read_lines rows < <(sh "$_HI_TARGETS")
  # names are field 1; the tab strip is a builtin, sparing a `cut` per TAB
  _HI_TARGET_NAMES="${rows[*]%%$'\t'*}"
  _HI_TARGET_NAMES_AT="$SECONDS"
}

# Matched in-shell: `compgen` through a process substitution cost a fork plus
# an `eval` per candidate on every TAB. targets.sh already drops names with
# `*` or `?`; `set -f` is belt to that.
function _hi_complete() {
  local cur="${COMP_WORDS[COMP_CWORD]}" prev="" n
  COMPREPLY=()
  ((COMP_CWORD > 1)) && prev="${COMP_WORDS[COMP_CWORD - 1]}"
  # the word a flag takes - `hi --preview <TAB>`, `hi --use <TAB>` - is
  # neither a flag nor a target: targets.sh's words roster, no probe
  case "$prev" in
  --preview | --use)
    while IFS=$'\t' read -r n _; do
      case "$n" in "$cur"*) COMPREPLY+=("$n") ;; esac
    done < <(sh "$_HI_TARGETS" words "$prev")
    return 0
    ;;
  esac
  # A `-` word asks for hi's own options, never a target, so this answers
  # without touching the target cache or its probes. Uncached on purpose: the
  # roster is a dozen printfs in targets.sh.
  if [[ "$cur" == -* ]]; then
    # "<flag>\t<help>" lines; bash's menu has no room for the second column
    while IFS=$'\t' read -r n _; do
      case "$n" in "$cur"*) COMPREPLY+=("$n") ;; esac
    done < <(sh "$_HI_TARGETS" flags)
    return 0
  fi
  _hi_target_names
  set -f
  for n in $_HI_TARGET_NAMES; do
    case "$n" in "$cur"*) COMPREPLY+=("$n") ;; esac
  done
  set +f
}
complete -F _hi_complete hi

# Deferred to the first TAB after `exa`: startup shouldn't parse a multi-KB
# spec most sessions never use. 124 is bash-completion's "retry".
function _hi_load_exa_completion() {
  local spec
  command -v _completion_loader &>/dev/null && _completion_loader eza &>/dev/null
  spec=$(complete -p eza 2>/dev/null) || return 1
  eval "${spec% eza} exa"
  return 124
}
complete -F _hi_load_exa_completion exa

# modified from: https://github.com/riobard/bash-powerline/blob/master/bash-powerline.sh
if [[ "${_HI_DISABLE_PROMPT:-0}" != 1 ]]; then
  if _hi_wants_starship; then
    # GLOSSARY: HI.32
    eval "$(starship init bash)"
  else
    # Readline counts every $PS1 character it was not told to ignore, so an
    # unmarked color escape makes the typed line wrap back over the prompt.
    # \[ \] marks the static half; the git segment reaches PS1 through a
    # variable, expanded *after* bash decodes those, so it carries the bytes
    # they decode to instead: \001 ... \002.
    function _hi_ps_mark() { # <var>
      local s="${!1}" out="" esc
      while [[ "$s" == *$'\e['* ]]; do
        out+="${s%%$'\e['*}"
        s="${s#*$'\e['}"
        esc="${s%%m*}"
        s="${s#*m}"
        out+=$'\001\e['"$esc"m$'\002'
      done
      printf -v "$1" '%s' "$out$s"
    }
    # Semantic prompt marks (OSC 133) and cwd reporting (OSC 7) for terminals
    # that read them (kitty, WezTerm, ghostty, foot, iTerm2). D (last status)
    # and A from PROMPT_COMMAND, B at the end of PS1, C from PS0 (bash 4.4+;
    # 3.2 simply lacks it). Raw, never multiplexer-wrapped: an unknown OSC is
    # dropped, and tmux passes 133 through. _HI_DISABLE_MARKS=1 turns it off.
    _hi_marks_a="" _hi_marks_b=""
    if [[ "${_HI_DISABLE_MARKS:-0}" != 1 ]]; then
      _hi_marks_a=$'\[\e]133;A\a\]'
      _hi_marks_b=$'\[\e]133;B\a\]'
      if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4))); then
        PS0=$'\e]133;C\a'"${PS0:-}"
      fi
    fi
    function ps1() {
      local _hi_ec=$?
      [ -n "$_hi_marks_a" ] && printf '\e]133;D;%s\a\e]7;file://%s%s\a' "$_hi_ec" "${HOSTNAME:-}" "$PWD"
      # git info through a reference, never expanded into PS1: expanding user
      # strings is the pw3nage class of bug (github.com/njhartwell/pw3nage)
      _hi_git_prompt __powerline_git_info # out-var form: no $( ) fork per prompt
      _hi_ps_mark __powerline_git_info
      # shellcheck disable=SC2154 # assigned by the printf -v two lines up
      if shopt -q promptvars; then
        PS1="$_hi_marks_a$HI_PS1\${__powerline_git_info}\[$NC\] $HI_PS1_END $_hi_marks_b"
      else
        # no expansion happens without promptvars, so the value goes in as text
        PS1="$_hi_marks_a$HI_PS1$__powerline_git_info\[$NC\] $HI_PS1_END $_hi_marks_b"
      fi
    }
    PROMPT_COMMAND="ps1${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
  fi
fi

# Last in the required block, once every alias has expanded its paths:
# children inherit core.sh's _HI_CHILD_ENV and nothing else with the prefix.
# The overlay's bash.sh below can still `export` anything. GLOSSARY: HI.47
_hi_unexport
# === end required configuration ===

# The path test stops $_HI_CONFIG_DIR pointed at common/ from sourcing this
# file forever (a hang, not an error). The directive is the same hazard seen
# statically, and it is NOT optional: .shellcheckrc's source-path=SCRIPTDIR
# makes `shellcheck -x` resolve the basename to this file and follow it into
# itself until OOM-killed. core.sh and aliases.sh guard their overlay sources
# the same way.
# shellcheck source=/dev/null # user config, may not exist
[[ "$_HI_CONFIG_DIR/bash.sh" != "$_HI_ROOT/common/bash.sh" ]] &&
  [[ -f "$_HI_CONFIG_DIR/bash.sh" ]] && source "$_HI_CONFIG_DIR/bash.sh"
