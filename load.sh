#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# The target half (forked from sshrc): header, session rc, shell handoff, undo.

# `bash --rcfile` skips the startup chain; restore it before strict mode
# (profile scripts aren't -e/-u safe), at source time ($CMDARG needs PATH too).
#
# $_HI_HOME and $_HI_ROOT are taken back afterwards. A target with a say-hi of
# its own announces it in this very chain - a package's
# /etc/profile.d/say-hi.sh exports `_HI_HOME=/usr/share` - and that export
# would otherwise point this session at a tree hi did not ship: every path
# below is derived from $_HI_HOME, so the session would unpack one tree and
# then load another (a different version, in the general case) while its own
# cleanup still removed the one it unpacked. hi does not read a target's
# install; that tree is for that machine's own shells. Nothing else the
# profile sets is touched.
#
# $_HI_ROOT is deliberately *not* put on $PATH: on a disposable session it is
# a directory under /tmp, which every hardening baseline greps for, and it
# would buy nothing - paths.sh already aliases `hi` to $_HI_LAUNCHER in all
# four shells.
function _hi_restore_profile() {
  local _hi_rp_home="${_HI_HOME:-}" _hi_rp_root="${_HI_ROOT:-}"
  if [ -r /etc/profile ]; then source /etc/profile; fi
  # shellcheck disable=SC1090 # target-specific files, no fixed location
  if [ -r ~/.bash_profile ]; then
    source ~/.bash_profile
  elif [ -r ~/.bash_login ]; then
    source ~/.bash_login
  elif [ -r ~/.profile ]; then
    source ~/.profile
  fi
  [ -n "$_hi_rp_home" ] && export _HI_HOME="$_hi_rp_home"
  [ -n "$_hi_rp_root" ] && export _HI_ROOT="$_hi_rp_root"
  return 0
}

# _HI_LOAD_NO_INIT=1: functions only, no profile chain - install.sh's source
# guard as an env var, since this file is only ever sourced.
[ "${_HI_LOAD_NO_INIT:-0}" = 1 ] || _hi_restore_profile

set -euo pipefail

# only hi's remote paths chainload this file, so this is how paths.sh tells
# "reached via hi" from "the machine say-hi lives on"
export _HI_REMOTE_SESSION=1

: "${_HI_HOME:=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=./common/core.sh
source "$_HI_HOME/say-hi/common/core.sh"
# shellcheck source=./common/header.sh
source "$_HI_HEADER"

# The bootloader shell: `hi <target> <cmd>` runs <cmd> here and load() starts
# the session shell from here, so what is exported now is what both inherit.
# Everything above still has the full set as shell variables; children get
# _HI_CHILD_ENV. The session's own pointers are exported later by
# _hi_session_rc_setup. Not under _HI_LOAD_NO_INIT: install.sh and the suites
# source this file for its functions and keep their environment.
# GLOSSARY: HI.47
[ "${_HI_LOAD_NO_INIT:-0}" = 1 ] || _hi_unexport

# Everything hi put on the target and nothing the target had. hi never writes
# to a target's own login files, so there is nothing to strip back out.
function clean_all() {
  # the rc directory nests under $_HI_CLEANUP when there is one; this removal
  # is for a session with no disposable tree - a local install's own shells
  [ -n "${_HI_SESSION_RC_DIR:-}" ] && rm -rf "$_HI_SESSION_RC_DIR"
  # $_HI_CLEANUP is $_HI_ROOT's parent - the whole disposable tree
  [ -n "${_HI_CLEANUP:-}" ] && rm -rf "$_HI_CLEANUP"
  return 0
}

# [outvar]: with $SHELL set the body is all builtins, so a $( ) around it was
# a fork for a value the shell already had. GLOSSARY: HI.05
function _hi_login_shell() {
  local shell="${SHELL:-}" user
  if [ -z "$shell" ]; then
    user="$(_hi_whoami)" # memoized; this path forked `id` twice
    shell="$(getent passwd "$user" 2>/dev/null | awk -F: '{ print $NF }')"
    [ -n "$shell" ] || shell="$(awk -F: -v u="$user" '$1 == u { print $NF }' /etc/passwd 2>/dev/null)"
  fi
  _hi_out "${1:-}" "${shell##*/}"
}

# The tail is $_HI_SHELL_TREE, not a literal of its own; its bash-less tiers
# are reachable only where bash is absent, and this file is bash, so what
# survives is fish > zsh > bash behind the login shell.
# GLOSSARY: HI.25 - why login leads. [outvar] for _hi_login_shell's reason.
function _hi_session_shell() {
  # bash as the starting value, not a second exit point: the loop only
  # narrows it. Prefixed locals (GLOSSARY: HI.04), since $1 is an outvar name.
  local _hi_ss_want _hi_ss_found=bash
  for _hi_ss_want in login $_HI_SHELL_TREE; do
    [ "$_hi_ss_want" = login ] && _hi_login_shell _hi_ss_want
    if _hi_shell_wired "$_hi_ss_want" && command -v "$_hi_ss_want" >/dev/null 2>&1; then
      _hi_ss_found="$_hi_ss_want"
      break
    fi
  done
  _hi_out "${1:-}" "$_hi_ss_found"
}

# Where the session shell's rc files go: a directory of hi's own, never the
# target's $HOME. Made by _hi_session_rc_setup, removed by clean_all on the
# *same* exit hook - _hi_on_exit is a `trap ... EXIT`, and a second call
# would replace the first.
_HI_SESSION_RC_DIR=""

# <value> as one single-quoted fish word: fish's single quotes know only \'
# and \\. Walked a character at a time because bash 3.2 unescapes a
# ${x//a/b} replacement differently from bash 4+, and a backslash that comes
# out doubled ends the fish string early.
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
# How hi's rc reaches the session without writing to the target's own rc
# files. `bash --rcfile` in hi.sh starts the *bootloader*; the shell the user
# types at is started below, and a bare `bash -i` would read ~/.bashrc, so it
# is pointed here instead. Every mechanism is one hi already relies on for a
# bash-less target: --rcfile, ZDOTDIR, $ENV and fish's -C.
#
# Each file sources the target's own rc *first*, then hi's on top.
#
# mktemp rather than a path under $_HI_ROOT: a *permanent* say-hi tree is
# often root-owned and read-only. %q on every interpolated path, since
# $TMPDIR is the target's to choose.
#
# shellcheck disable=SC2016 # the single quotes are the point: $HOME is the
# *target's* to expand when it reads these files, not this script's to expand
# while writing them
function _hi_session_sh_rc() {
  # the shape bash and zsh share: the target's rc, the client's verdicts
  # ($sh_vars, the caller's local), then hi's rc
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

  # The client's verdicts ($_HI_SESSION_VARS, exported into this process by
  # hi.sh) as plain assignments in each rc. The session shell unexports every
  # _HI_* name outside _HI_CHILD_ENV - two of these name the operator's
  # workstation - so a nested shell gets them from here, not the environment.
  # Only the set ones: an empty tag and an absent one read the same.
  # GLOSSARY: HI.47
  local v sh_vars="" fish_vars=""
  for v in "${_HI_SESSION_VARS[@]}"; do
    [ -n "${!v-}" ] || continue
    printf -v q '%q' "${!v}"
    sh_vars="$sh_vars$v=$q"$'\n'
    _hi_fishquote q "${!v}"
    fish_vars="${fish_vars}set -g $v $q"$'\n'
  done

  _hi_session_sh_rc .bashrc "$_HI_BASHRC" "$dir/bashrc"

  # ZDOTDIR moves *all* of zsh's startup files, so the target's .zshenv needs
  # a shim or the environment it sets is lost. .zprofile/.zlogin are
  # login-shell only, and this is `zsh -i`.
  printf '[ -r "$HOME/.zshenv" ] && . "$HOME/.zshenv"\n' >"$dir/.zshenv"
  _hi_session_sh_rc .zshrc "$_HI_ZSHRC" "$dir/.zshrc"

  # fish reads config.fish before -C, so the host's config is already in place
  # by the time this is sourced - the same order as above, for free. The
  # header is our greeting, hence fish_greeting.
  printf -v q '%q' "$_HI_FISH_CONFIG"
  {
    printf "set fish_greeting ''\n"
    printf '%s' "$fish_vars"
    printf 'source %s\n' "$q"
  } >"$dir/fish.config"

  # $ENV is what sh, dash and ash read for an *interactive* shell. Aliases and
  # paths only, the same subset the bash-less fallback gets.
  printf -v q '%q' "$_HI_ROOT"
  {
    printf '[ -r %s/common/paths.sh ] && . %s/common/paths.sh\n' "$q" "$q"
    printf '[ -r %s/settings/aliases.sh ] && . %s/settings/aliases.sh\n' "$q" "$q"
  } >"$dir/shrc"

  # Exported, so a shell started *inside* the session inherits them. ZDOTDIR
  # and ENV do the whole job for zsh and sh/dash/ash, even when the starter is
  # not a shell. bash and fish have no such variable, so aliases.sh defines a
  # wrapper for each off $_HI_SESSION_RC. GLOSSARY: HI.46
  export _HI_SESSION_RC="$dir"
  export ZDOTDIR="$dir"
  export ENV="$dir/shrc"
  return 0
}

# How to start the session's shell so that it reads hi's rc without that rc
# having been written into the target's $HOME.
function _hi_session_shell_cmd() {
  local _hi_sc_shell="$1" _hi_sc_dir="$_HI_SESSION_RC_DIR"
  local -a _hi_sc=()
  case "$_hi_sc_shell" in
  bash) _hi_sc=(bash --rcfile "$_hi_sc_dir/bashrc" -i) ;;
  fish) _hi_sc=(fish -C "source $_hi_sc_dir/fish.config" -i) ;;
  # zsh included: _hi_session_rc_setup already exported ZDOTDIR, so `zsh -i`
  # needs nothing more than any other shell here
  *) _hi_sc=("$_hi_sc_shell" -i) ;;
  esac
  # one eval, and only to copy out: bash 3.2 has no namerefs
  eval "$2=(\"\${_hi_sc[@]}\")"
}

# The editor a session exports, with hi's config flags: $_HI_EDITOR's pick when
# it names something installed here, else the first of the ladder. The flags
# are read off the alias settings/aliases.sh builds (sourced here, in the
# caller's $( ) subshell, so nothing leaks into load()) - one spelling of each
# editor's invocation, and the overlay's own _HI_MICRO_OPTS reaches $EDITOR
# the way it reaches the alias. kak goes bare - sudoedit splits the value on
# whitespace with no quoting, and kak's config flag needs one quoted word.
function _hi_session_editor() {
  local e name body
  # shellcheck source=./settings/aliases.sh
  source "$_HI_ALIASES" >/dev/null 2>&1
  for e in ${_HI_EDITOR:-} nvim vim hx helix micro nano emacs kak; do
    type -P "$e" &>/dev/null || continue
    case "$e" in
    nvim) name=vim ;;
    helix) name=hx ;;
    kak) name="" ;;
    *) name="$e" ;;
    esac
    body="$([ -n "$name" ] && alias "$name" 2>/dev/null)"
    body="${body#alias "$name"=\'}"
    body="${body%\'}"
    printf '%s' "${body:-$e}"
    return 0
  done
  return 0
}

function load() {
  local start total
  start="$(_hi_now)"
  _hi_on_exit clean_all

  set +euo pipefail

  # connect (the client's leg) plus copy (this one), each measured wholly on
  # one machine, since clock skew makes a client/target subtraction
  # meaningless. `load` is not in it - this prints before that leg starts. It
  # continues the size hi.sh printed with no newline, so the total has to
  # widen $_HI_CONNECT_PREFIX or the banner's tildes come out wrong.
  total="$(_hi_sum "${_HI_CONNECT_TIME:-0}" "${_HI_COPY_TIME:-0}")"
  _hi_cecho " | ${total}s" "$NC" 1
  hi_header Connected "" "${_HI_CONNECT_PREFIX:-} | ${total}s"

  # vim only: VIMINIT breaks a target that has just vi. Gated on
  # _HI_DISABLE_EDITORS too, since VIMINIT *is* the override that toggle turns
  # off (settings/vim.rc ships either way - the payload roster is static).
  [[ "${_HI_DISABLE_EDITORS:-0}" != 1 ]] &&
    command -v vim &>/dev/null &&
    export VIMINIT="let \$MYVIMRC='$_HI_VIMRC' | source \$MYVIMRC"
  # $EDITOR, $VISUAL and $SUDO_EDITOR: an alias reaches an interactive prompt
  # and nothing else, so `git commit`, `crontab -e` and `sudo -e` on the
  # target would still open whatever vi it has. Exported for the session shell
  # to inherit, carrying the same flags the alias does.
  if [[ "${_HI_DISABLE_EDITORS:-0}" != 1 ]]; then
    local editor
    editor="$(_hi_session_editor)"
    [[ -n "$editor" ]] && export EDITOR="$editor" VISUAL="$editor" SUDO_EDITOR="$editor"
  fi
  _hi_cecho " | " "$NC" 1
  _hi_cecho "hi loaded with... " "$BRCYAN" 1

  local shell greeting color
  _hi_session_shell shell
  case "$shell" in
  fish) greeting="fish shell! :^)" color="$GREEN" ;;
  zsh) greeting="zsh shell! :)" color="$PURPLE" ;;
  *) greeting="only bash today :(" color="$RED" ;;
  esac
  _hi_cecho "$greeting" "$color" 1
  _hi_cecho " | connect: ${_HI_CONNECT_TIME:--1}s | copy: ${_HI_COPY_TIME:--1}s | load: $(_hi_elapsed "$start" "$(_hi_now)")s"

  local shell_ec=0
  local -a shell_cmd=()
  _hi_session_rc_setup
  _hi_session_shell_cmd "$shell" shell_cmd
  "${shell_cmd[@]}" || shell_ec=$?

  # The shell's last prompt mark was C - `exit` is a command like any other -
  # and the D closing the pair never came, since the shell is gone. A terminal
  # tracking OSC 133 is left "inside a command" until the next D, and Konsole
  # turns the up arrow into a left arrow while it waits. Same toggle as the
  # marks themselves.
  [[ "${_HI_DISABLE_MARKS:-0}" != 1 ]] && printf '\e]133;D;%s\a' "$shell_ec"

  local size dur
  size="$(_hi_du_size "$_HI_ROOT")"
  # $start is load()'s entry, so this is the whole session, not the setup the
  # "load:" line above timed
  dur="$(_hi_human_duration "$(_hi_elapsed "$start" "$(_hi_now)")")"
  _hi_cecho " $size | session: $dur" "$NC" 1
  if [[ "${_HI_DISABLE_HEADER:-0}" != 1 ]]; then
    banner Disconnected "$BRRED" " $size | session: $dur"
    # matches the connect header rather than a toggle of its own: shown iff
    # one of its three words survives in $_HI_HEADER_ORDER
    if _hi_order_has utc || _hi_order_has version || _hi_order_has localtime; then
      timestamp
    fi
  fi
  _hi_cecho " | " "$NC" 1
  _hi_cecho "hi closing!" "$BRPURPLE"
  exit "$shell_ec"
}
