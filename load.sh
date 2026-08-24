#!/bin/bash
# The target half (forked from sshrc): header, rc grafts, shell handoff, undo.

# `bash --rcfile` skips the startup chain; restore it before strict mode
# (profile scripts aren't -e/-u safe), at source time ($CMDARG needs PATH too).
function _hi_restore_profile() {
  if [ -r /etc/profile ]; then source /etc/profile; fi
  # shellcheck disable=SC1090 # target-specific files, no fixed location
  if [ -r ~/.bash_profile ]; then
    source ~/.bash_profile
  elif [ -r ~/.bash_login ]; then
    source ~/.bash_login
  elif [ -r ~/.profile ]; then
    source ~/.profile
  fi
  export PATH="$PATH:$_HI_ROOT"
}

# _HI_LOAD_NO_INIT=1: functions only, no profile chain - install.sh's source
# guard as an env var, since this file is only ever sourced
[ "${_HI_LOAD_NO_INIT:-0}" = 1 ] || _hi_restore_profile

set -euo pipefail

# only hi's remote paths chainload this file - how common/paths.sh tells
# "reached via hi" from "the machine say-hi lives on"
export _HI_REMOTE_SESSION=1

: "${_HI_HOME:=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=./common/core.sh
source "$_HI_HOME/say-hi/common/core.sh"
# shellcheck source=./common/header.sh
source "$_HI_HEADER"

_HI_CONFIG_START="# hi-config-start"
_HI_CONFIG_END="# hi-config-end"

# rc file <- hi config; fish only when installed (no config dir otherwise).
# "<shell>|<hi's rc>|<the user's rc>", from core.sh's _HI_SHELL_TABLE rows
# flagged `graft` - the same roster scripts/install.sh reads for its local
# half. The shell name is carried, not re-derived from the rc's suffix: it is
# what picks the guard dialect below, and a graft whose rc is not named
# *.fish would otherwise get sh syntax appended to a real fish config.
_HI_CONFIGS=()
while IFS='|' read -r _hi_shell _hi_label _hi_tree_rc _hi_home_rc _hi_check _hi_flags; do
  _HI_CONFIGS+=("$_hi_shell|$_hi_tree_rc|$_hi_home_rc")
done < <(_hi_shell_rows graft)
unset _hi_shell _hi_label _hi_tree_rc _hi_home_rc _hi_check _hi_flags

function configure_files() {
  local row shell target src open body
  for row in "${_HI_CONFIGS[@]}"; do
    shell="${row%%|*}"
    src="${row#*|}"
    src="${src%|*}"
    target="${row##*|}"
    [ -d "${target%/*}" ] || continue # targets are absolute; no dirname fork
    # `: >>` creates without truncating or exec'ing touch, and `$(<f)` is the
    # builtin read where `grep -q` was a second exec - both ran per rc file on
    # every connect. $(<f) slurps where grep short-circuits: fine for an rc.
    : >>"$target"
    case "$(<"$target")" in *"$_HI_CONFIG_START"*) continue ;; esac
    # GLOSSARY: HI.24 - why every graft wraps
    # shellcheck disable=SC2016 # single quotes are the point: the guard expands at shell start, not graft time
    case "$shell" in
    fish)
      open='if set -q _HI_HOME; and test -f $_HI_HOME/say-hi/common/core.sh'
      body="$open"$'\n'"$(<"$src")"$'\n'"end"
      ;;
    *)
      open='if [ -f "${_HI_HOME:-}/say-hi/common/core.sh" ]; then'
      body="$open"$'\n'"$(<"$src")"$'\n'"fi"
      ;;
    esac
    printf '%s\n' "$_HI_CONFIG_START"$'\n'"$body"$'\n'"$_HI_CONFIG_END" >>"$target"
  done
}

function clean_all() {
  local row target pattern
  for row in "${_HI_CONFIGS[@]}"; do
    target="${row##*|}"
    [ -f "$target" ] || continue
    if grep -q "^$_HI_CONFIG_END" "$target"; then
      pattern="/^$_HI_CONFIG_START/,/^$_HI_CONFIG_END/d"
    else
      pattern="/^$_HI_CONFIG_START/d"
    fi
    # core.sh's _hi_rewrite, not `sed -i`: the flag differs BSD/GNU, and -i
    # would replace a symlinked rc with a regular file - the opposite of what
    # configure_files did appending through that same link
    _hi_rewrite "$target" "$pattern"
  done
  [ -n "${_HI_CLEANUP:-}" ] && rm -rf "$_HI_ROOT"
  return 0
}

function _hi_login_shell() {
  local shell="${SHELL:-}" user
  if [ -z "$shell" ]; then
    user="$(_hi_whoami)" # memoized in core.sh; this path forked `id` twice
    shell="$(getent passwd "$user" 2>/dev/null | awk -F: '{ print $NF }')"
    [ -n "$shell" ] || shell="$(awk -F: -v u="$user" '$1 == u { print $NF }' /etc/passwd 2>/dev/null)"
  fi
  printf '%s' "${shell##*/}"
}

# The default tail is core.sh's $_HI_SHELL_TREE, not a literal of its own. The
# case below is the allow list, so the tree's bash-less tiers fall through it
# unmatched - they are reachable only where bash is absent, and this file is
# bash. What survives is fish > zsh > bash, $_HI_SHELL_PREFERENCE's documented
# default. GLOSSARY: HI.25 - why login leads the default
function _hi_session_shell() {
  local want
  for want in ${_HI_SHELL_PREFERENCE:-login} $_HI_SHELL_TREE; do
    [ "$want" = login ] && want="$(_hi_login_shell)"
    case "$want" in
    bash | zsh | fish) command -v "$want" >/dev/null 2>&1 && {
      printf '%s' "$want"
      return 0
    } ;;
    esac
  done
  printf 'bash'
}

function load() {
  local start
  start="$(_hi_now)"
  _hi_on_exit clean_all

  set +euo pipefail

  hi_header Connected "" "${_HI_CONNECT_PREFIX:-}"

  # vim only: setting VIMINIT when all we have is vi breaks it. Gated on
  # _HI_DISABLE_EDITORS as well: VIMINIT pointing at hi's vimrc *is* the vim
  # config override that toggle turns off, and setting it needs the file to be
  # there - which is what lets hi.sh trim settings/vim.rc out of the payload when
  # the toggle is off.
  [[ "${_HI_DISABLE_EDITORS:-0}" != 1 ]] &&
    command -v vim &>/dev/null &&
    export VIMINIT="let \$MYVIMRC='$_HI_VIMRC' | source \$MYVIMRC"
  configure_files
  _hi_cecho " | " "$NC" 1
  _hi_cecho "hi loaded with... " "$BRCYAN" 1

  local shell greeting color
  shell="$(_hi_session_shell)"
  case "$shell" in
  fish) greeting="fish shell! :^)" color="$GREEN" ;;
  zsh) greeting="zsh shell! :)" color="$PURPLE" ;;
  *) greeting="only bash today :(" color="$RED" ;;
  esac
  _hi_cecho "$greeting" "$color" 1
  _hi_cecho " | load: $(_hi_elapsed "$start" "$(_hi_now)")s | copy: ${_HI_COPY_TIME:--1}s"

  local shell_ec=0
  local -a shell_cmd=("$shell" -i)
  # the header above is our greeting
  [ "$shell" = fish ] && shell_cmd=(fish -C "set fish_greeting ''" -i)
  "${shell_cmd[@]}" || shell_ec=$?

  local size dur
  size="$(_hi_du_size "$_HI_ROOT")"
  # $start is load()'s own entry, before the "Connected" banner - so this is
  # the whole session, not just the setup the "load:" line above timed
  dur="$(_hi_human_duration "$(_hi_elapsed "$start" "$(_hi_now)")")"
  _hi_cecho " $size | session: $dur" "$NC" 1
  if [[ "${_HI_DISABLE_HEADER:-0}" != 1 ]]; then
    banner Disconnected "$BRRED" " $size | session: $dur"
    [[ "${_HI_HEADER_TIMESTAMP:-1}" == 0 ]] || timestamp
  fi
  _hi_cecho " | " "$NC" 1
  _hi_cecho "hi closing! " "$BRPURPLE"
  exit "$shell_ec"
}
