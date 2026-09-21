#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# set -euo pipefail # cannot be enabled: an interactive shell would exit on the first error

# === start required configuration ===
# re-entered while loading (an overlay bash.sh sourcing ~/.bashrc, say):
# return at once rather than recurse. GLOSSARY: HI.55
[[ -z "${_hi_rc_loading-}" ]] || return 0
_hi_rc_loading=1
# $_HI_HOME first, this file's own path as the fallback for a hand-written
# `source` (hi.sh and install.sh's rc line set it). GLOSSARY: HI.33
# `${BASH_SOURCE%/*}` and not `$(dirname ...)`: header.sh:14 and core.sh:21
# already spell it this way, and a fork here is one every hand-written
# `source` pays.
_hi_d="${BASH_SOURCE[0]}"
case "$_hi_d" in */*) _hi_d="${_hi_d%/*}" ;; *) _hi_d="." ;; esac
: "${_HI_HOME:=$(cd -P "$_hi_d/../.." && pwd)}"
unset _hi_d
# core.sh's load guard is a no-op *within* one process, and this file is the
# one place that is wrong: a shell outlives the tree under it, and re-sourcing
# an rc after an in-place upgrade has to re-derive every path rather than keep
# the version the shell loaded first. load.sh clears it for the same reason on
# a target. GLOSSARY: HI.60
unset _hi_core_loaded
# shellcheck source=./core.sh
source "$_HI_HOME/say-hi/common/core.sh"
# shellcheck source=./git_prompt.sh
source "$_HI_GIT_PROMPT"
# shellcheck source=./env_prompt.sh
source "$_HI_ENV_PROMPT"
# shellcheck source=../config/aliases.sh
source "$_HI_ALIASES"
_hi_load_plugins

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

# the prompt program the prompt goes to, if any (GLOSSARY: HI.32). oh-my-bash
# and bash-it count once the rc loaded either, or where either installs with
# a theme from home to draw - the overlay's copy, so only on a target
_hi_omb_theme=""
_hi_bashit_theme=""
[ "$_HI_REMOTE_SESSION" = 1 ] && _hi_omb_theme="$_HI_CONFIG_DIR/oh-my-bash.theme.sh"
[ "$_HI_REMOTE_SESSION" = 1 ] && _hi_bashit_theme="$_HI_CONFIG_DIR/bash-it.theme.bash"
function _hi_prompt_fw() {
  case "$1" in
  oh-my-bash)
    declare -F _omb_module_require >/dev/null ||
      { [ -f "$_hi_omb_theme" ] && [ -f "${OSH:-$HOME/.oh-my-bash}/oh-my-bash.sh" ]; }
    ;;
  bash-it)
    declare -F _bash-it-log-prefix-by-path >/dev/null ||
      { [ -f "$_hi_bashit_theme" ] && [ -f "${BASH_IT:-$HOME/.bash_it}/bash_it.sh" ]; }
    ;;
  esac
}
_hi_pt=""
[[ "${_HI_DISABLE_PROMPT:-0}" == 1 ]] || _hi_prompt_tool bash _hi_pt || true

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
_HI_TARGET_ROWS=()
_HI_TARGET_ROWS_AT=-1

function _hi_target_rows() {
  if [ "$_HI_TARGET_ROWS_AT" -ge 0 ] &&
    [ "$((SECONDS - _HI_TARGET_ROWS_AT))" -lt "${_HI_TARGETS_TTL:-5}" ]; then
    return 0
  fi
  # the rows whole, as common/zsh.zsh caches them: name is field 1 and kind
  # field 2, and the tab strips that split them are builtins, sparing a `cut`
  # per TAB. Flattening the two fields into a pair of space-joined strings
  # would need a `set -f` re-split on the way out and would silently desync
  # the halves the first time a target name carried a space.
  _hi_read_lines _HI_TARGET_ROWS < <(sh "$_HI_TARGETS")
  _HI_TARGET_ROWS_AT="$SECONDS"
}

# Matched in-shell: `compgen` through a process substitution cost a fork plus
# an `eval` per candidate on every TAB. targets.sh already drops names with
# `*` or `?`; `set -f` is belt to that.
function _hi_complete() {
  local cur="${COMP_WORDS[COMP_CWORD]}" prev="" n
  COMPREPLY=()
  local -a ask=()
  ((COMP_CWORD > 1)) && prev="${COMP_WORDS[COMP_CWORD - 1]}"
  # the word a flag takes (`hi --preview <TAB>`) is targets.sh's words roster;
  # a `-` word is hi's own options - or, behind a local command (`hi --install
  # --<TAB>`), that command's switches. Neither touches the target cache or
  # its probes; uncached on purpose, the rosters are a dozen printfs.
  case " $_HI_WORD_FLAGS " in *" $prev "*) ask=(words "$prev") ;; esac
  ((${#ask[@]})) || [[ "$cur" != -* ]] || ask=(flags "${COMP_WORDS[1]}")
  if ((${#ask[@]})); then
    # "<word>\t<help>" lines; bash's menu has no room for the second column
    while IFS=$'\t' read -r n _; do
      case "$n" in "$cur"*) COMPREPLY+=("$n") ;; esac
    done < <(sh "$_HI_TARGETS" "${ask[@]}")
    return 0
  fi
  _hi_target_rows
  local -a hit_kinds=() shown=() syms=()
  local i j sym row
  for row in "${_HI_TARGET_ROWS[@]}"; do
    n="${row%%$'\t'*}"
    case "$n" in "$cur"*) COMPREPLY+=("$n") hit_kinds+=("${row#*$'\t'}") ;; esac
  done
  # each name's backend symbol, only while readline lists - never when an
  # entry lands on the command line. GLOSSARY: HI.56
  case "${COMP_TYPE:-}" in 63 | 33 | 64) ;; *) return 0 ;; esac
  ((${#COMPREPLY[@]} > 1)) || return 0
  for i in "${!COMPREPLY[@]}"; do
    n="${COMPREPLY[i]}"
    _hi_target_symbol sym "${hit_kinds[i]}"
    for j in "${!shown[@]}"; do
      [ "${shown[j]}" = "$n" ] && {
        syms[j]+="$sym"
        continue 2
      }
    done
    shown+=("$n") syms+=("$sym")
  done
  COMPREPLY=()
  if ((${#shown[@]} > 1)); then
    for i in "${!shown[@]}"; do COMPREPLY+=("${shown[i]} ${syms[i]}"); done
  else
    COMPREPLY=("${shown[@]}")
  fi
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

# _hi_drop_prompt_command <array> - <array> minus prompt_command, a no-op when
# unset; bash has no zsh-style :# array filter, so a rebuild loop
function _hi_drop_prompt_command() {
  declare -p "$1" &>/dev/null || return 0
  local _hi_f _hi_ref="$1[@]"
  local -a _hi_pf=()
  for _hi_f in "${!_hi_ref}"; do
    [[ "$_hi_f" == prompt_command ]] || _hi_pf+=("$_hi_f")
  done
  eval "$1=(\${_hi_pf[@]+\"\${_hi_pf[@]}\"})"
}

# modified from: https://github.com/riobard/bash-powerline/blob/master/bash-powerline.sh
if [[ "${_HI_DISABLE_PROMPT:-0}" != 1 ]]; then
  if [ -n "$_hi_pt" ]; then
    # each the way its own README wires it into an rc. GLOSSARY: HI.32
    case "$_hi_pt" in
    powerline-go)
      function __hi_plgo_ps1() {
        local ec=$?
        # shellcheck disable=SC2086 # the options are words
        PS1="$(powerline-go -shell bash -error "$ec" -jobs "$(($(jobs -p | wc -l)))" ${_HI_POWERLINE_GO_OPTS-})"
      }
      PROMPT_COMMAND="__hi_plgo_ps1${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
      ;;
    oh-my-bash)
      # not loaded by the rc: all of it but plugins, aliases, and completions
      # (none listed), and hi's aliases put back over its libraries'
      if ! declare -F _omb_module_require >/dev/null; then
        _hi_a="$(alias -p)"
        OSH="${OSH:-$HOME/.oh-my-bash}"
        # shellcheck source=/dev/null
        DISABLE_AUTO_UPDATE=true OSH_THEME="" source "$OSH/oh-my-bash.sh"
        unalias -a
        eval "$_hi_a"
        unset _hi_a
      fi
      # shellcheck source=/dev/null
      [ -f "$_hi_omb_theme" ] && source "$_hi_omb_theme"
      ;;
    bash-it)
      # not loaded by the rc: bash_it.sh's own loader takes a literal path in
      # BASH_IT_THEME (sourced directly, no name lookup), so unlike oh-my-bash
      # this needs no separate theme step - _hi_prompt_fw already required a
      # home theme to exist before selecting bash-it here in the first place
      if ! declare -F _bash-it-log-prefix-by-path >/dev/null; then
        BASH_IT="${BASH_IT:-$HOME/.bash_it}"
        # shellcheck source=/dev/null
        BASH_IT_THEME="$_hi_bashit_theme" DISABLE_AUTO_UPDATE=true source "$BASH_IT/bash_it.sh"
      else
        # already loaded with its own theme, whose precmd_functions entry
        # (prompt_command, the fixed name most bundled themes use) survives
        # sourcing a different theme file over it - bash-preexec's
        # safe_append_prompt_command only ever adds, so the rc's own theme
        # would keep redrawing every prompt after this one otherwise. Clear
        # it first, as the hi-named unhook below does.
        _hi_drop_prompt_command precmd_functions
        # shellcheck source=/dev/null
        [ -f "$_hi_bashit_theme" ] && source "$_hi_bashit_theme"
      fi
      ;;
    *) eval "$("$_hi_pt" init bash)" ;;
    esac
  else
    # `\$` renders as $ for a user and # for root - see core.sh's _hi_prompt_end
    HI_PS1_END=""
    _hi_prompt_end BASH HI_PS1_END
    _hi_ps1_lead=" "
    [[ "${_HI_DISABLE_LEAD_SPACE:-0}" == 1 ]] && _hi_ps1_lead=""
    # bash is the one shell where another tool's prefix cannot survive: ps1()
    # below rebuilds $PS1 from scratch on every draw, so there is nothing to
    # defer to and hi renders the environment segment itself. GLOSSARY: HI.54
    _HI_ENV_DEFER=0
    if _hi_has_color; then
      # the *_var forms: a cache read, not a $( ) fork. Spelled empty first, so
      # the linter sees the `printf -v` assignment (SC2154); file scope, no `local`.
      _hi_ps1_u="" _hi_ps1_h="" _hi_ps1_at="$NC"
      _hi_user_escape _hi_ps1_u
      _hi_host_escape _hi_ps1_h
      [ -n "${SSH_TTY:-}" ] && _hi_ps1_at="$YELLOW"
      HI_PS1="${debian_chroot:-}\[$_hi_ps1_u\]\u\[$_hi_ps1_at\]@\[$_hi_ps1_h\]\h\[$NC\] \[$BRBLUE\]\w\[$NC\]"
      unset _hi_ps1_u _hi_ps1_h _hi_ps1_at
    else
      HI_PS1="${debian_chroot:-}\u@\h:\w"
    fi
    # `hi` named in the list takes the prompt back from a program the rc
    # already started, whose PROMPT_COMMAND hook would redraw over hi's ps1()
    # every prompt; each known hook becomes a `:`. PROMPT_COMMAND is an array
    # from bash 5.1 when the rc made it one. Unset, or a list that ran out,
    # leaves the rc's own choice alone.
    if _hi_prompt_named_hi; then
      _hi_pcd="$(declare -p PROMPT_COMMAND 2>/dev/null)" # once: the type never changes below
      for _hi_h in starship_precmd _omp_hook _omp_precmd __hi_plgo_ps1; do
        # the array arm is eval'd: to the linter PROMPT_COMMAND is the string
        # every other line here treats it as
        case "$_hi_pcd" in
        "declare -a"*) eval 'PROMPT_COMMAND=("${PROMPT_COMMAND[@]//$_hi_h/:}")' ;;
        *) PROMPT_COMMAND="${PROMPT_COMMAND//$_hi_h/:}" ;;
        esac
      done
      unset _hi_h
      # robbyrussell and some other bash-it themes assign
      # PROMPT_COMMAND=prompt_command directly rather than going through
      # bash-preexec. A whole-element/whole-segment check, not the loop
      # above's substring one: "prompt_command" is also a real suffix other
      # tools' own hook names legitimately end in (mise's
      # _mise_hook_prompt_command, for one), which the substring form of
      # this check corrupted into "_mise_hook_:" the first time this shipped.
      case "$_hi_pcd" in
      "declare -a"*)
        # eval'd for the same reason as the loop above: a literal array
        # assignment here would have the linter treat every later scalar
        # PROMPT_COMMAND assignment in this file, line 355's included, as
        # the wrong type
        eval 'for _hi_i in "${!PROMPT_COMMAND[@]}"; do [ "${PROMPT_COMMAND[_hi_i]}" = prompt_command ] && PROMPT_COMMAND[_hi_i]=:; done'
        unset _hi_i
        ;;
      *)
        # sentinel-padded so a global replace only ever hits a segment
        # bounded by ";" on both sides, never a substring mid-name
        _hi_pc=";${PROMPT_COMMAND:-};"
        _hi_pc="${_hi_pc//;prompt_command;/;:;}"
        PROMPT_COMMAND="${_hi_pc#;}"
        PROMPT_COMMAND="${PROMPT_COMMAND%;}"
        unset _hi_pc
        ;;
      esac
      unset _hi_pcd
      # Other bash-it themes call bash-preexec's safe_append_prompt_command,
      # which never touches PROMPT_COMMAND at all - it puts bash-preexec's
      # own dispatcher there (during bash-it's unconditional library load)
      # and keeps prompt_command in these two indexed arrays instead. Absent
      # for every other framework/program above, so a no-op without it.
      _hi_drop_prompt_command precmd_functions
      _hi_drop_prompt_command preexec_functions
    fi
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
    # dropped, and tmux passes 133 through.
    _hi_marks_a=$'\[\e]133;A\a\]'
    _hi_marks_b=$'\[\e]133;B\a\]'
    if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4))); then
      PS0=$'\e]133;C\a'"${PS0:-}"
    fi
    function ps1() {
      local _hi_ec=$?
      printf '\e]133;D;%s\a\e]7;file://%s%s\a' "$_hi_ec" "${HOSTNAME:-}" "$PWD"
      # git info through a reference, never expanded into PS1: expanding user
      # strings is the pw3nage class of bug (github.com/njhartwell/pw3nage)
      _hi_git_prompt __powerline_git_info # out-var form: no $( ) fork per prompt
      _hi_ps_mark __powerline_git_info
      # the one color is in the template below, inside \[ \]; the mark after
      # the plugin segments is for any color a segment prints itself
      _hi_env_prompt __hi_env_info
      # each plugin's $_HI_SEGMENT, run per draw; empty output draws nothing
      local _hi_c _hi_o
      for _hi_c in ${_hi_segments[@]+"${_hi_segments[@]}"}; do
        _hi_o="$(eval "$_hi_c" 2>/dev/null)" && [ -n "$_hi_o" ] && __hi_env_info+="$_hi_o "
      done
      _hi_ps_mark __hi_env_info
      # the segments as references; no expansion happens without promptvars,
      # so there the values go in as text
      # shellcheck disable=SC2016 # the single quotes are the reference
      local e='${__hi_env_info}' g='${__powerline_git_info}'
      # shellcheck disable=SC2154 # assigned by the printf -v calls above
      shopt -q promptvars || e="$__hi_env_info" g="$__powerline_git_info"
      PS1="$_hi_marks_a$_hi_ps1_lead\[$BRCYAN\]$e\[$NC\]$HI_PS1$g\[$NC\] $HI_PS1_END $_hi_marks_b"
    }
    PROMPT_COMMAND="ps1${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
  fi
fi
unset _hi_pt _hi_omb_theme _hi_bashit_theme

# Last in the required block, once every alias has expanded its paths:
# children inherit core.sh's _HI_CHILD_ENV and nothing else with the prefix.
# The overlay's bash.sh below can still `export` anything. GLOSSARY: HI.47
_hi_unexport
# === end required configuration ===

# The user's own bashrc from the overlay, last. The directive is NOT
# optional: .shellcheckrc's source-path=SCRIPTDIR makes `shellcheck -x`
# follow a bare basename, and core.sh and aliases.sh guard their overlay
# sources the same way.
# shellcheck source=/dev/null # user config, may not exist
[[ -f "$_HI_CONFIG_DIR/bashrc" ]] && source "$_HI_CONFIG_DIR/bashrc"
# a local interactive shell greets with hi's header, as config.fish's
# fish_greeting does - never a script's or `bash -i -c`'s (fish greets
# neither), nor on a target, where load.sh prints the Connected one. A
# subshell keeps header.sh's functions out of this one.
# shellcheck source=./header.sh
[[ $- == *i* && -z "${BASH_EXECUTION_STRING-}" && "$_HI_REMOTE_SESSION" != 1 &&
  "${_HI_DISABLE_HEADER:-0}" != 1 ]] && (source "$_HI_HEADER" && hi_header Online)
unset _hi_rc_loading
