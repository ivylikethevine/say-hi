#!/usr/bin/env bash
# The target half (forked from sshrc): header, session rc, shell handoff, undo.

# `bash --rcfile` skips the startup chain; restore it before strict mode
# (profile scripts aren't -e/-u safe), at source time ($CMDARG needs PATH too).
#
# $_HI_ROOT is deliberately *not* appended to $PATH here: on a disposable
# session it is a directory under /tmp, and a /tmp path on $PATH is what
# every hardening baseline greps for. Putting it there would buy nothing
# anyway - common/paths.sh already defines `alias hi="$_HI_LAUNCHER"` in all
# four shells, which is how an interactive session reaches the launcher to
# relay `hi` onward, with no PATH entry needed for it.
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

# This is the bootloader shell: `hi <target> <cmd>` runs <cmd> right here, and
# load() starts the session shell from here, so what is exported at this point
# is what both inherit. Everything above needed the full set as shell
# variables and still has it; children get core.sh's _HI_CHILD_ENV. The
# session's own pointers ($_HI_SESSION_RC, $ZDOTDIR, $ENV) are exported later,
# by _hi_session_rc_setup, and the client's verdicts reach the session shell
# through the rc it writes. Not under _HI_LOAD_NO_INIT: install.sh and the
# suites source this file for its functions and keep their environment.
# GLOSSARY: HI.47
[ "${_HI_LOAD_NO_INIT:-0}" = 1 ] || _hi_unexport

# Everything hi put on the target, and nothing the target had: the session
# rc directory and, on a disposable tree, the tree itself. hi never writes to
# a target's own login files, so there is nothing to strip back out.
function clean_all() {
  # the session rc directory nests under $_HI_CLEANUP when there is one; the
  # explicit removal is for the permanent-install path, which has no $_HI_CLEANUP
  [ -n "${_HI_SESSION_RC_DIR:-}" ] && rm -rf "$_HI_SESSION_RC_DIR"
  # $_HI_CLEANUP is $_HI_HOME, $_HI_ROOT's parent - the whole disposable tree
  [ -n "${_HI_CLEANUP:-}" ] && rm -rf "$_HI_CLEANUP"
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

# Where the session shell's rc files are written: a directory of hi's own,
# never the target's $HOME. Made once by _hi_session_rc_setup, removed by
# clean_all - the *same* exit hook, since core.sh's _hi_on_exit is a
# `trap ... EXIT` in bash and a second call would replace the first.
_HI_SESSION_RC_DIR=""

# _hi_fishquote <var> <value> - <value> as one single-quoted fish word, into
# <var>. fish's single quotes know two escapes, \' and \\, and nothing else.
# Walked a character at a time: bash 3.2 unescapes the replacement half of a
# ${x//a/b} differently from bash 4+, and a backslash that comes out doubled
# ends the fish string early.
function _hi_fishquote() {
  local _in="$2" _out="" _c
  while [ -n "$_in" ]; do
    _c="${_in%"${_in#?}"}"
    _in="${_in#?}"
    case "$_c" in
    \\ | \') _out="$_out\\$_c" ;;
    *) _out="$_out$_c" ;;
    esac
  done
  printf -v "$1" "'%s'" "$_out"
}

# _hi_session_rc_setup - write every shell's rc into one directory and export
# the three variables that point the session, and anything started inside it,
# at them. Idempotent; safe to call more than once.
#
# This is how hi's rc reaches the session without a write to the target's own
# rc files. `bash --rcfile` in hi.sh starts the *bootloader*, which sources
# this file and calls load(); the shell the user actually types at is started
# below, and a bare `bash -i` reads ~/.bashrc - so it is pointed here instead.
# Every mechanism here is one hi already relies on for a bash-less target
# (hi.sh's _hi_remote_suffix): --rcfile, ZDOTDIR, $ENV and fish's -C.
#
# Each file sources the target's own rc *first*: the host's config, then hi's
# on top of it.
#
# mktemp rather than a path under $_HI_ROOT: a *permanent* say-hi tree is
# often root-owned and read-only. %q on every interpolated path, since
# $TMPDIR is the target's to choose.
#
# shellcheck disable=SC2016 # the single quotes are the point: $HOME is the
# *target's* to expand when it reads these files, not this script's to expand
# while writing them
function _hi_session_sh_rc() {
  # the sh-dialect shape bash and zsh share: the target's own rc first, the
  # client's verdicts ($sh_vars, the caller's local), then hi's rc on top
  local q
  printf -v q '%q' "$2"
  {
    printf '[ -r "$HOME/%s" ] && . "$HOME/%s"\n' "$1" "$1"
    printf '%s' "$sh_vars"
    printf '. %s\n' "$q"
  } >"$3"
}

# shellcheck disable=SC2016 # same rule as _hi_session_sh_rc's: the target
# expands $HOME, not this script
function _hi_session_rc_setup() {
  [ -z "$_HI_SESSION_RC_DIR" ] || return 0
  if [ -n "${_HI_CLEANUP:-}" ]; then
    _HI_SESSION_RC_DIR="$(mktemp -d "$_HI_CLEANUP/hi.rc.XXXXXX")" || return 1
  else
    _HI_SESSION_RC_DIR="$(mktemp -d -t hi.rc.XXXXXX)" || return 1
  fi
  local dir="$_HI_SESSION_RC_DIR" q

  # The client's verdicts - core.sh's _HI_SESSION_VARS, which hi.sh exported
  # into this process - as plain assignments in each rc, between the target's
  # own rc and hi's. The session shell takes the export attribute off every
  # _HI_* name that is not in _HI_CHILD_ENV (two of these name the operator's
  # workstation), so a shell started inside the session gets them from here
  # rather than from its environment. Only the set ones: an empty tag is
  # "no tag" and an absent one reads the same. GLOSSARY: HI.47
  local v sh_vars="" fish_vars=""
  for v in "${_HI_SESSION_VARS[@]}"; do
    [ -n "${!v-}" ] || continue
    printf -v q '%q' "${!v}"
    sh_vars="$sh_vars$v=$q"$'\n'
    _hi_fishquote q "${!v}"
    fish_vars="${fish_vars}set -g $v $q"$'\n'
  done

  _hi_session_sh_rc .bashrc "$_HI_BASHRC" "$dir/bashrc"

  # ZDOTDIR moves *all* of zsh's startup files, not just .zshrc, so the
  # target's .zshenv needs a shim of its own or the environment it sets is
  # simply lost. .zprofile/.zlogin are login-shell only, and this is `zsh -i`.
  printf '[ -r "$HOME/.zshenv" ] && . "$HOME/.zshenv"\n' >"$dir/.zshenv"
  _hi_session_sh_rc .zshrc "$_HI_ZSHRC" "$dir/.zshrc"

  # fish reads its own config.fish before -C runs, so the host's fish config is
  # already in place by the time this is sourced - the same order as above, for
  # free. The header is our greeting, hence fish_greeting.
  printf -v q '%q' "$_HI_FISH_CONFIG"
  {
    printf "set fish_greeting ''\n"
    printf '%s' "$fish_vars"
    printf 'source %s\n' "$q"
  } >"$dir/fish.config"

  # $ENV is what POSIX sh, dash and ash read for an *interactive* shell, which
  # is the only kind this matters for. hi's own aliases and paths, not the full
  # bash rc - this is the same subset the bash-less fallback gets.
  printf -v q '%q' "$_HI_ROOT"
  {
    printf '[ -r %s/common/paths.sh ] && . %s/common/paths.sh\n' "$q" "$q"
    printf '[ -r %s/settings/aliases.sh ] && . %s/settings/aliases.sh\n' "$q" "$q"
  } >"$dir/shrc"

  # Exported, so a shell started *inside* the session inherits them. ZDOTDIR
  # and ENV do the whole job for zsh and for sh/dash/ash respectively - no
  # wrapper needed, and they survive being started by something that is not a
  # shell. bash and fish have no such variable, so settings/aliases.sh defines
  # a wrapper for each off $_HI_SESSION_RC. GLOSSARY: HI.46
  export _HI_SESSION_RC="$dir"
  export ZDOTDIR="$dir"
  export ENV="$dir/shrc"
  return 0
}

# _hi_session_shell_cmd <shell> <outvar> - how to start the session's shell so
# that it reads hi's rc without hi's rc having been written into the target's
# $HOME first.
function _hi_session_shell_cmd() {
  local shell="$1" out="$2" dir="$_HI_SESSION_RC_DIR"
  case "$shell" in
  bash) eval "$out=(bash --rcfile \"\$dir/bashrc\" -i)" ;;
  fish) eval "$out=(fish -C \"source \$dir/fish.config\" -i)" ;;
  # zsh included: _hi_session_rc_setup already exported ZDOTDIR, so `zsh -i`
  # needs nothing more than any other shell here
  *) eval "$out=(\"\$shell\" -i)" ;;
  esac
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
  local -a shell_cmd=()
  _hi_session_rc_setup
  _hi_session_shell_cmd "$shell" shell_cmd
  "${shell_cmd[@]}" || shell_ec=$?

  local size dur
  size="$(_hi_du_size "$_HI_ROOT")"
  # $start is load()'s own entry, before the "Connected" banner - so this is
  # the whole session, not just the setup the "load:" line above timed
  dur="$(_hi_human_duration "$(_hi_elapsed "$start" "$(_hi_now)")")"
  _hi_cecho " $size | session: $dur" "$NC" 1
  if [[ "${_HI_DISABLE_HEADER:-0}" != 1 ]]; then
    banner Disconnected "$BRRED" " $size | session: $dur"
    # matches the connect header rather than a disconnect-specific toggle:
    # shows the timestamp bundle iff any one of its three words survives in
    # $_HI_HEADER_ORDER
    if _hi_order_has utc || _hi_order_has version || _hi_order_has localtime; then
      timestamp
    fi
  fi
  _hi_cecho " | " "$NC" 1
  _hi_cecho "hi closing! " "$BRPURPLE" 1
  exit "$shell_ec"
}
