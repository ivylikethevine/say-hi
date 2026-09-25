#!/bin/zsh
# SPDX-License-Identifier: MIT

# === start required configuration ===
# see common/bash.sh: re-entered while loading, return. GLOSSARY: HI.55
[[ -z "${_hi_rc_loading-}" ]] || return 0
_hi_rc_loading=1
# The tree from this file's own path: %x is this file, :A absolute, :h up one.
# GLOSSARY: HI.33
: "${_HI_HOME:=${${(%):-%x}:A:h:h:h}}"
# see common/bash.sh: an rc re-sourced after an in-place upgrade re-derives
unset _hi_core_loaded
source "$_HI_HOME/say-hi/common/core.sh"
source "$_HI_GIT_PROMPT"
source "$_HI_ENV_PROMPT"
source "$_HI_ALIASES"
_hi_load_plugins

# NOT setopt KSH_ARRAYS: it is global, hi's block runs after oh-my-zsh's, and
# their code assumes zsh's 1-based arrays - core.sh counts instead.
# prompt_subst only for a prompt hi draws or hands over, never over the
# user's own choice with the prompt disabled
[[ "${_HI_DISABLE_PROMPT:-0}" == 1 ]] || setopt prompt_subst

_hi_interactive_extras

# Primed unconditionally, so a custom PROMPT in the user's own zsh.zsh
# (sourced at the end of this file) can use hi's color hashing with
# _HI_DISABLE_PROMPT=1 - $_HI_HOST_COLOR/$_HI_USER_COLOR are the names; %F{} wants
# _hi_color_base's answer for one of the extras.
_hi_prime_identity

# the frameworks _hi_prompt_tool asks after (GLOSSARY: HI.32): each counts
# once the rc loaded it, or - on a target only - where it installs, with the
# file from home to draw: the overlay's theme or p10k config. At home the rc
# is the user's whole answer, so an installed-but-unloaded framework (a
# distro's powerlevel10k package nobody adopted) is never started, and the
# two paths stay empty there. bash.sh's oh-my-bash half is the same shape.
_hi_omz_theme="" _hi_p10k_cfg=""
[[ "$_HI_REMOTE_SESSION" == 1 ]] && _hi_omz_theme="$_HI_CONFIG_DIR/oh-my-zsh.zsh-theme" _hi_p10k_cfg="$_HI_CONFIG_DIR/p10k.zsh"
_hi_p10k_theme() {
  local d
  for d in ~/powerlevel10k "${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}/themes/powerlevel10k" \
    /usr/share/zsh-theme-powerlevel10k {/opt/homebrew,/usr/local,/home/linuxbrew/.linuxbrew}/share/powerlevel10k; do
    [[ -f $d/powerlevel10k.zsh-theme ]] && REPLY="$d/powerlevel10k.zsh-theme" && return 0
  done
  return 1
}
_hi_prompt_fw() {
  case $1 in
  powerlevel10k) (( $+functions[p10k] )) || { [[ -f $_hi_p10k_cfg ]] && _hi_p10k_theme } ;;
  oh-my-zsh) (( $+functions[git_prompt_info] )) || [[ -f $_hi_omz_theme && -f ${ZSH:-$HOME/.oh-my-zsh}/lib/git.zsh ]] ;;
  esac
}

if [[ "${_HI_DISABLE_PROMPT:-0}" != 1 ]]; then
  _hi_pt=""
  if _hi_prompt_tool zsh _hi_pt; then
    # each the way its own README wires it into an rc. GLOSSARY: HI.32
    case $_hi_pt in
    powerline-go)
      # first in line, so $? is still the command's status
      __hi_plgo_precmd() { PS1="$(powerline-go -shell zsh -error $? -jobs ${${(%):-%j}:-0} ${=_HI_POWERLINE_GO_OPTS})"; }
      precmd_functions=(__hi_plgo_precmd "${precmd_functions[@]}")
      ;;
    powerlevel10k)
      # not loaded by the rc (a target, then): the theme, then home's config;
      # loaded, home's config still goes over the target's own
      if (( ! $+functions[p10k] )); then
        typeset -g POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
        _hi_p10k_theme && source "$REPLY"
      fi
      [[ -f $_hi_p10k_cfg ]] && source "$_hi_p10k_cfg"
      ;;
    oh-my-zsh)
      # not loaded by the rc: only the libraries themes call into - no plugins,
      # completion, or key bindings - and hi's aliases put back over theirs
      if (( ! $+functions[git_prompt_info] )); then
        typeset -gA _hi_a
        _hi_a=("${(@kv)aliases}")
        : "${ZSH:=$HOME/.oh-my-zsh}"
        autoload -Uz colors && colors
        for _hi_l in async_prompt bzr git nvm prompt_info_functions spectrum theme-and-appearance vcs_info; do
          [[ -f $ZSH/lib/$_hi_l.zsh ]] && source "$ZSH/lib/$_hi_l.zsh"
        done
        aliases=("${(@kv)_hi_a}")
        unset _hi_a _hi_l
      fi
      [[ -f $_hi_omz_theme ]] && source "$_hi_omz_theme"
      ;;
    *) eval "$("$_hi_pt" init zsh)" ;;
    esac
  elif ! _hi_prompt_named_hi && { (( ${+_LP_VERSION} || ${+SPACESHIP_VERSION} ||
    ${+functions[prompt_pure_setup]} )) || [[ -n ${prompt_theme-} ]]; }; then
    # a prompt hi has no hand-over for draws here - liquidprompt, spaceship,
    # pure, or a promptinit theme (prezto's included) - and stays theirs; `hi`
    # in $_HI_PROMPT_TOOL takes it anyway. GLOSSARY: HI.32
    :
  else
    # `hi` named in the list takes the prompt back from a program the rc
    # already started: its precmd would redraw over hi's every prompt. Unset,
    # or a list that ran out, leaves the rc's own choice alone. starship
    # renamed its zsh hooks in v1.3.0 (prompt_starship_* over the bare
    # starship_*); both names are filtered since either can be loaded.
    # p10k's are _p9k_preexec1/_p9k_preexec2, never a bare _p9k_preexec.
    if _hi_prompt_named_hi; then
      precmd_functions=(${precmd_functions:#(starship_precmd|prompt_starship_precmd|_p9k_precmd|_omp_precmd|_omp_hook|__hi_plgo_precmd)})
      preexec_functions=(${preexec_functions:#(starship_preexec|prompt_starship_preexec|_p9k_preexec1|_p9k_preexec2|_omp_preexec)})
    fi
    # git info through a precmd out-var, never a $( ) in PS1 - the fork-free,
    # pw3nage-safe form bash.sh's __hi_ps1() uses
    # zsh counts what %{ %} holds as zero columns, so each escape goes in
    # alone and the text stays counted; a % in a branch name is doubled
    __hi_git_precmd() {
      setopt local_options extended_glob
      _hi_git_prompt __hi_git_info
      __hi_git_info=${${__hi_git_info//\%/%%}//(#b)($'\e'\[[0-9;]#m)/%\{$match[1]%\}}
    }
    precmd_functions+=(__hi_git_precmd)
    # zsh keeps the $PS1 it was given, so another tool's prefix is still on
    # screen and hi stands down for it. GLOSSARY: HI.54
    _HI_ENV_DEFER=1
    # the lead space goes when a script prepended its own "(name) " to $PS1
    # (a venv's or conda's activate), whose trailing space already separates
    __hi_env_precmd() {
      _hi_env_prompt __hi_env_info
      if [[ $PS1 == '${__hi_ma}'* ]]; then __hi_lead=$_hi_lead; else __hi_lead=""; fi
    }
    precmd_functions+=(__hi_env_precmd)
    # each plugin's $_HI_SEGMENT after it, `%` doubled so prompt_subst draws
    # the output rather than reading it as a prompt escape. GLOSSARY: HI.59
    __hi_segment_precmd() {
      local c o
      for c in "${_hi_segments[@]}"; do
        o="$(eval "$c" 2>/dev/null)" && [[ -n "$o" ]] && __hi_env_info+="${o//\%/%%} "
      done
    }
    ((${#_hi_segments[@]})) && precmd_functions+=(__hi_segment_precmd)
    # OSC 133 prompt marks and OSC 7 cwd reporting, as common/bash.sh's __hi_ps1()
    # emits them
    _hi_marks_a=$'%{\e]133;A\a%}'
    _hi_marks_b=$'%{\e]133;B\a%}'
    __hi_ma="" __hi_mb=""
    # whether a draw carries them, as bash.sh's _hi_marks_on asks
    __hi_marks_on() {
      [[ $TERM != dumb && -t 1 && -z ${ITERM_SHELL_INTEGRATION_INSTALLED-} ]] &&
        (( ! ${+_ksi_state} && ! ${+_ghostty_state} && ! ${+functions[__wezterm_semantic_precmd]} ))
    }
    __hi_marks_precmd() {
      local ec=$? u
      if __hi_marks_on; then
        __hi_ma=$_hi_marks_a __hi_mb=$_hi_marks_b
        _hi_url_path u "$PWD"
        printf '\e]133;D;%s\a\e]7;file://%s%s\a' "$ec" "${HOST:-}" "$u"
      else
        __hi_ma="" __hi_mb=""
      fi
    }
    __hi_marks_preexec() { [[ -z $__hi_ma ]] || printf '\e]133;C\a'; }
    # a shell left from its prompt (Ctrl-D) runs no preexec, so close the last
    # A/B pair on the way out, as bash.sh's _hi_marks_exit does
    __hi_marks_zshexit() {
      local ec=$?
      [[ -n $__hi_ma && -t 1 ]] && printf '\e]133;C\a\e]133;D;%s\a' "$ec"
    }
    precmd_functions=(__hi_marks_precmd "${precmd_functions[@]}")
    preexec_functions+=(__hi_marks_preexec)
    zshexit_functions+=(__hi_marks_zshexit)
    # concatenated onto the $'...' strings, not interpolated, so zsh's prompt
    # expansion happens at render time rather than at assignment - the lead
    # too, which __hi_env_precmd re-decides per draw.
    _hi_prompt_end ZSH HI_PS1_END
    _hi_lead=" "
    [[ "${_HI_DISABLE_LEAD_SPACE:-0}" == 1 ]] && _hi_lead=""
    __hi_lead=$_hi_lead
    if _hi_has_color; then
      export CLICOLOR="${CLICOLOR:-1}" LSCOLORS="${LSCOLORS:-gafacadabaegedabagacad}"
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
      PS1=$'${__hi_ma}${__hi_lead}%F{cyan}${__hi_env_info}%f${debian_chroot:-}%F{$USER_COLOR}%n%f%F{$_hi_at_color}@%f%F{$HOST_COLOR}%m%f%F{cyan} %~%f%F{plain}${__hi_git_info} '"$HI_PS1_END "$'${__hi_mb}'
    else
      PS1=$'${__hi_ma}${__hi_lead}${__hi_env_info}${debian_chroot:-}%n@%m %~${__hi_git_info} '"$HI_PS1_END "$'${__hi_mb}'
    fi
  fi
fi
unset _hi_pt _hi_omz_theme _hi_p10k_cfg

# completion: `hi` from the shared target list, `exa` the same way as `eza`
zmodload zsh/complist
autoload -Uz compinit promptinit
# One compinit per shell: $_comps is compinit's own table, so a framework's
# (oh-my-zsh, prezto, the user's own) already ran it; zinit's queueing
# compdef stub alone does not count. promptinit likewise, by its `prompt`.
if (( ! ${+_comps} )); then
  # bare `compinit` costs 50-150ms a start; full check once a day, -C between.
  # (#qN.mh+24): N tolerates a missing dump, .mh+24 = older than 24h; a glob
  # only under extended_glob, off by default, so set for the test alone. -u on
  # the full check: compaudit's interactive [y/n] on a group-writable $fpath
  # hangs `hi` when piped through something non-interactive (vhs included).
  _hi_dump="${ZDOTDIR:-$HOME}/.zcompdump"
  if () { setopt local_options extended_glob; [[ -n $1(#qN.mh+24) ]]; } "$_hi_dump"; then
    compinit -u
    # compinit leaves an unchanged dump's mtime alone, making this branch
    # permanent once the dump turns a day old - touch restarts the clock
    touch "$_hi_dump" 2>/dev/null || true
  else
    compinit -C
  fi
  # compinit sources a .zwc beside the dump when it is the newer, which halves
  # what -C costs; recompiled whenever the dump moves. Built aside and renamed,
  # so a shell starting meanwhile never reads half a file.
  if [[ -f $_hi_dump && ! $_hi_dump.zwc -nt $_hi_dump ]]; then
    { zcompile "$_hi_dump.$$.zwc" "$_hi_dump" && mv -f "$_hi_dump.$$.zwc" "$_hi_dump.zwc"; } 2>/dev/null ||
      rm -f "$_hi_dump.$$.zwc"
  fi
  unset _hi_dump
fi
(( ${+functions[prompt]} )) || promptinit
# The in-shell TTL cache bash.sh's _hi_complete explains, in zsh's dialect.
# (( )) rather than [ ]: zsh's SECONDS is a float once anything typeset -F's it.
# GLOSSARY: HI.26
_HI_TARGET_ROWS=()
_HI_TARGET_DESCS=()
_HI_TARGET_ROWS_AT=-1

_hi() {
  local name kind sym
  # the word a flag takes (`hi --preview <TAB>`), then hi's own options (or,
  # behind a local command, its switches), targets otherwise - the split
  # bash.sh's _hi_complete makes: a flag list must not wait on a backend probe
  local -a ask
  if [[ " $_HI_WORD_FLAGS " == *" ${words[CURRENT-1]} "* ]]; then
    ask=(words "${words[CURRENT-1]}")
  elif [[ "${words[CURRENT]}" == -* ]]; then
    ask=(flags "${words[2]}")
  fi
  if (( $#ask )); then
    # "<word>\t<help>" lines: the word is the match, the help its description
    local -a flags descs
    local row
    for row in "${(@f)$(sh "$_HI_TARGETS" "${ask[@]}")}"; do
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
[[ -f "$_HI_CONFIG_DIR/zshrc" ]] && source "$_HI_CONFIG_DIR/zshrc"
# see common/bash.sh: a local interactive shell greets with hi's header,
# drawn by bash since header.sh is bash's, handed the session values
# _hi_unexport kept back (as config.fish's __hi_bash does)
__hi_header() {
  local n
  local -a kv
  for n in $_HI_SESSION_VARS; do (( ${+parameters[$n]} )) && kv+=("$n=${(P)n}"); done
  env "${kv[@]}" COLUMNS=$COLUMNS bash -c 'source "$1" && hi_header Online' hi "$_HI_HEADER"
}
if [[ -o interactive && -z "${ZSH_EXECUTION_STRING-}" && "$_HI_REMOTE_SESSION" != 1 &&
  "${_HI_DISABLE_HEADER:-0}" != 1 ]]; then
  # powerlevel10k's instant prompt warns about any output before the real
  # prompt; this is its own call for an rc that has some
  (( ${+__p9k_instant_prompt_active} && ${+functions[p10k]} )) && p10k clear-instant-prompt
  __hi_header
fi
unset _hi_rc_loading
