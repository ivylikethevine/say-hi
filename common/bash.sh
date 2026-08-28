#!/usr/bin/env bash
# set -euo pipefail # cannot be enabled: an interactive shell would exit on the first error

# === start required configuration ===
# Through $_HI_HOME, not this file's own path: load.sh grafts this file's *text*
# into someone else's rc (GLOSSARY: HI.24), where $BASH_SOURCE is that rc. The
# derivation is for a hand-written `source`; a graft and install.sh's rc line
# both set $_HI_HOME first. GLOSSARY: HI.33
: "${_HI_HOME:=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck source=./core.sh
source "$_HI_HOME/say-hi/common/core.sh"
# shellcheck source=./git_prompt.sh
source "$_HI_GIT_PROMPT"
# shellcheck source=../settings/aliases.sh
source "$_HI_ALIASES"

_hi_interactive_extras
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# C2: primed unconditionally, not only when hi's own prompt is on, so a
# custom PS1 in the user's own bash.sh (sourced at the end of hi's,
# docs/CONFIGURATION.md) can still use hi's per-host/per-user color hashing
# with _HI_DISABLE_PROMPT=1 - $_HI_HOST_ESC/$_HI_USER_ESC are the ANSI
# escapes ready to embed, the way this file's own PS1 below does; core.sh's
# _hi_prime_identity stops at the color names ($_HI_HOST_COLOR/$_HI_USER_COLOR
# - what zsh's own prompt wants) since zsh never uses the escape form, so bash
# primes its own on top.
_hi_prime_identity
_hi_host_escape >/dev/null
_hi_user_escape >/dev/null

if [[ "${_HI_SCRATCH_HISTORY:-0}" = 1 ]]; then
  # shellcheck source=./history.sh
  source "$_HI_HOME/say-hi/common/history.sh"
  export HISTFILE="$_HI_TMPDIR/bash_history"
  PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
fi

if [[ "${_HI_DISABLE_PROMPT:-0}" != 1 ]] && ! _hi_wants_starship; then
  # `\$` renders as $ for a user and # for root - see core.sh's _hi_prompt_end
  HI_PS1_END=""
  _hi_prompt_end BASH HI_PS1_END
  if _hi_has_color; then
    # the *_var forms, not $( ): both escapes were primed unconditionally
    # above, so this is a cache read, not a fresh $( ) fork. Spelled empty
    # first so shellcheck sees the `printf -v` assignment (SC2154); file
    # scope, so no `local`.
    _hi_ps1_u="" _hi_ps1_h="" _hi_ps1_at="$NC"
    _hi_user_escape_var _hi_ps1_u
    _hi_host_escape_var _hi_ps1_h
    [ -n "${SSH_TTY:-}" ] && _hi_ps1_at="$YELLOW"
    HI_PS1=" ${debian_chroot:-}\[$_hi_ps1_u\]\u\[$_hi_ps1_at\]@\[$_hi_ps1_h\]\h\[$NC\] \[$BRBLUE\]\w\[$NC\]"
    unset _hi_ps1_u _hi_ps1_h _hi_ps1_at
  else
    HI_PS1=" ${debian_chroot:-}\u@\h:\w"
  fi
fi

if ! shopt -oq posix; then
  # $BASH_COMPLETION_VERSINFO is the loader's own sentinel: the host's stock rc
  # often sourced it before hi's grafted block runs, and re-parsing the
  # ~2000-line script costs 20-50ms a shell for nothing
  # shellcheck disable=SC1091
  [ -n "${BASH_COMPLETION_VERSINFO-}" ] ||
    source /usr/share/bash-completion/bash_completion 2>/dev/null ||
    source /etc/bash_completion 2>/dev/null
fi

# complete `hi` from the same target list zsh/fish use, and make `exa` complete
# the way `eza` does, whatever bash-completion bound to it.
#
# targets.sh file-caches for $_HI_TARGETS_TTL seconds, but finding that out is
# still a fork and an exec. Holding the names in the shell for the same window
# makes it free. Not for the *same* window, though: this one starts when this
# shell last read the file, and the file's started when it was written, so a
# memo filled from an already-stale file holds it for a full TTL on top of
# what it had already spent - worst case is close to twice the TTL, and only
# _HI_TARGETS_TTL=0 turns both layers off. Nothing invalidates either; a
# container started inside the window waits for the clock. $SECONDS is the
# stamp because it is a builtin; -1 is "never filled", and a TTL of 0 refreshes
# every time, as targets.sh reads it. GLOSSARY: HI.26
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

# On a warm cache _hi_target_names does nothing, and `compgen` through a
# process substitution then cost a fork plus an `eval` per candidate on every
# TAB; matching in-shell costs neither. targets.sh already drops names carrying
# `*` or `?`, and `set -f` is belt to that: names are matched, never globbed.
function _hi_complete() {
  local cur="${COMP_WORDS[COMP_CWORD]}" n
  COMPREPLY=()
  # A word starting with `-` is asking for hi's own options, never a target, so
  # this answers without touching the target cache or its probes. Uncached on
  # purpose: the roster is a dozen printfs in targets.sh, cheaper than the
  # bookkeeping a cache would need.
  if [[ "$cur" == -* ]]; then
    for n in $(sh "$_HI_TARGETS" flags); do
      case "$n" in "$cur"*) COMPREPLY+=("$n") ;; esac
    done
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
    # Readline counts every character of $PS1 it was not told to ignore, so an
    # unmarked color escape makes bash believe the line is wider than it prints
    # - and past the real edge the typed line wraps back over the prompt. \[ \]
    # says "no width" for the static half; the git segment reaches PS1 through
    # a variable, expanded *after* bash decodes those escapes, so it carries
    # the bytes they decode to instead: \001 ... \002.
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
    # Semantic prompt marks (OSC 133) and cwd reporting (OSC 7), for
    # terminals that read them - kitty, WezTerm, ghostty, foot, iTerm2: jump
    # between prompts, select one command's output, open a new tab in this
    # directory. D carries the last status and A opens the prompt, both from
    # PROMPT_COMMAND; B closes it at the end of PS1; C, "command starts", is
    # PS0's job and PS0 is bash 4.4 - on 3.2 the marks simply lack it. Raw,
    # never multiplexer-wrapped: a terminal that does not know an OSC drops
    # it, and tmux passes 133 through on its own. \[ \] keeps readline from
    # counting them. _HI_DISABLE_MARKS=1 turns the lot off.
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

# Last in the required block, once every alias above has expanded its paths:
# nothing started from this shell inherits hi's namespace beyond core.sh's
# _HI_CHILD_ENV. The overlay's bash.sh below runs after this and can `export`
# any name it wants a child to see. GLOSSARY: HI.47
_hi_unexport
# === end required configuration ===

# The guard is settings/aliases.sh's: $_HI_CONFIG_DIR pointed at common/ would make
# this file source itself forever, and a hang is worse than an error.
#
# The directive is the same hazard seen statically, and it is NOT optional.
# .shellcheckrc sets source-path=SCRIPTDIR, so under `shellcheck -x` the
# basename below resolves against this file's own directory - to this file -
# and shellcheck follows it into itself regardless of the runtime guard above,
# re-parsing until it is OOM-killed (measured: ~33GB before the kernel stepped
# in). /dev/null is what stops the follow; common/core.sh:45 does the same for
# $_HI_CONFIG_DIR/settings.sh.
# shellcheck source=/dev/null # user config, may not exist
[[ "$_HI_CONFIG_DIR/bash.sh" != "$_HI_ROOT/common/bash.sh" ]] &&
  [[ -f "$_HI_CONFIG_DIR/bash.sh" ]] && source "$_HI_CONFIG_DIR/bash.sh"
