#!/usr/bin/env bash
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
  # a wired ~/.bashrc in the chain sourced that tree's core.sh too, and its
  # load guard would skip ours: every path would stay pointed at that tree
  unset _hi_core_loaded
  return 0
}

# only hi's remote paths chainload this file, so this is how paths.sh tells
# "reached via hi" from "the machine say-hi lives on". Ahead of the profile
# chain: a Debian ~/.profile sources ~/.bashrc, and a target with its own hi
# wired there would otherwise greet with its Online header before ours.
export _HI_REMOTE_SESSION=1

# _HI_LOAD_NO_INIT=1: functions only, no profile chain - install.sh's source
# guard as an env var, since this file is only ever sourced.
[ "${_HI_LOAD_NO_INIT:-0}" = 1 ] || _hi_restore_profile

# The profile chain ran in an interactive bash, and bash expands aliases when
# it parses a function: a target's `alias mv='mv -v'` would chatter from every
# function below. Back on at the end of the file, for the `hi <target> <cmd>`
# line the bootloader runs after it (hi_info is an alias).
_hi_load_aliases=0
! shopt -q expand_aliases || _hi_load_aliases=1
shopt -u expand_aliases

set -euo pipefail

: "${_HI_HOME:=$(CDPATH='' builtin cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=./common/core.sh
source "$_HI_HOME/say-hi/common/core.sh"
# with the header off, the client sent no header.sh
# shellcheck source=./common/header.sh
[[ "${_HI_DISABLE_HEADER:-0}" == 1 ]] || source "$_HI_HEADER"

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
  # a kept session's timeout watcher, by process group: its `sleep` goes too
  if [ -n "${_hi_keep_watch_pid:-}" ]; then
    kill -- "-$_hi_keep_watch_pid" 2>/dev/null || kill "$_hi_keep_watch_pid" 2>/dev/null
  fi
  # the rc directory nests under $_HI_CLEANUP when there is one; this removal
  # is for a session with no disposable tree - a local install's own shells
  [ -n "${_HI_SESSION_RC_DIR:-}" ] && rm -rf "$_HI_SESSION_RC_DIR"
  [ -n "${_HI_CLEANUP:-}" ] || return 0
  # a session kept from inside another shares that one's tree, and the last
  # of the two to go removes it: hi.kept is the kept one's claim, which it
  # gives up here, and $_HI_KEEP_OUTER the shell it was kept from
  if [ -n "${_HI_KEEP_OUTER:-}" ]; then
    rm -f "$_HI_ROOT/hi.kept"
    ! kill -0 "$_HI_KEEP_OUTER" 2>/dev/null || return 0
  elif [ -e "$_HI_ROOT/hi.kept" ]; then
    return 0
  fi
  # $_HI_CLEANUP is $_HI_ROOT's parent - the whole disposable tree
  rm -rf "$_HI_CLEANUP"
  return 0
}

# [outvar]: with $SHELL set the body is all builtins, so a $( ) around it was
# a fork for a value the shell already had. GLOSSARY: HI.05
function _hi_login_shell() {
  local shell="${SHELL:-}" user
  if [ -z "$shell" ]; then
    _hi_whoami >/dev/null # primes the memo; read the variable, not a $( )
    user="$_HI_WHOAMI_CACHE"
    shell="$(getent passwd "$user" 2>/dev/null | awk -F: '{ print $NF }')"
    [ -n "$shell" ] || shell="$(awk -F: -v u="$user" '$1 == u { print $NF }' /etc/passwd 2>/dev/null)"
  fi
  _hi_out "${1:-}" "${shell##*/}"
}

# fish before 3.4 cannot parse config.fish (a top-level `return`, and
# aliases.sh's `$( )`), so a target with one gets the next shell down. A
# version that will not read counts as new enough.
function _hi_fish_new_enough() {
  local v
  v="$(fish --version 2>/dev/null)" || return 0
  case "${v##* }" in [0-2].* | 3.[0-3] | 3.[0-3].*) return 1 ;; esac
  return 0
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
    if _hi_shell_wired "$_hi_ss_want" && command -v "$_hi_ss_want" >/dev/null 2>&1 &&
      { [ "$_hi_ss_want" != fish ] || _hi_fish_new_enough; }; then
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
# bash-less target: --rcfile, ZDOTDIR, $ENV, and fish's -C.
#
# Each file sources the target's own rc *first*, then hi's on top.
#
# mktemp rather than a path under $_HI_ROOT: a *permanent* say-hi tree is
# often root-owned and read-only. %q on every interpolated path, since
# $TMPDIR is the target's to choose.
#
# _hi_session_sh_rc <target lines> <hi rc> <out> - the shape bash and zsh
# share: the lines that source the target's own rc, the client's verdicts
# ($sh_vars, the caller's local), then hi's rc
function _hi_session_sh_rc() {
  local q
  printf -v q '%q' "$2"
  {
    printf '%s\n' "$1"
    printf '%s' "$sh_vars"
    printf '. %s\n' "$q"
  } >"$3"
}

# shellcheck disable=SC2016 # the single quotes are the point: $HOME and
# $ZDOTDIR are the *target's* to expand when it reads these files, not this
# script's to expand while writing them
function _hi_session_rc_setup() {
  [ -z "$_HI_SESSION_RC_DIR" ] || return 0
  if [ -n "${_HI_CLEANUP:-}" ]; then
    _HI_SESSION_RC_DIR="$(mktemp -d "$_HI_CLEANUP/hi.rc.XXXXXX")" || return 1
  else
    _HI_SESSION_RC_DIR="$(mktemp -d -t hi.rc.XXXXXX)" || return 1
  fi
  local dir="$_HI_SESSION_RC_DIR" q zsh_rc

  # The client's verdicts ($_HI_SESSION_VARS, exported into this process by
  # hi.sh) as plain assignments in each rc. The session shell unexports every
  # _HI_* name outside _HI_CHILD_ENV - two of these name the operator's
  # workstation - so a nested shell gets them from here, not the environment.
  # Only the set ones: an empty tag and an absent one read the same.
  # GLOSSARY: HI.47
  local v sh_vars="" fish_vars=""
  # ...and this session's tree, re-pointed after the target's rc: one wired
  # for a say-hi of its own exports _HI_HOME at that tree and loads its
  # core.sh, whose load guard would skip ours
  for v in _HI_HOME _HI_ROOT _HI_CONFIG_DIR; do
    printf -v q '%q' "${!v}"
    sh_vars="${sh_vars}export $v=$q"$'\n'
    _hi_fishquote q "${!v}"
    fish_vars="${fish_vars}set -gx $v $q"$'\n'
  done
  sh_vars="${sh_vars}unset _hi_core_loaded"$'\n'
  for v in "${_HI_SESSION_VARS[@]}"; do
    [ -n "${!v-}" ] || continue
    printf -v q '%q' "${!v}"
    sh_vars="$sh_vars$v=$q"$'\n'
    _hi_fishquote q "${!v}"
    fish_vars="${fish_vars}set -g $v $q"$'\n'
  done

  _hi_session_sh_rc '[ -r "$HOME/.bashrc" ] && . "$HOME/.bashrc"' "$_HI_BASHRC" "$dir/bashrc"

  # ZDOTDIR moves *all* of zsh's startup files, so the target's .zshenv needs
  # a shim or the environment it sets is lost. .zprofile/.zlogin are
  # login-shell only, and this is `zsh -i`. A .zshenv that sets ZDOTDIR
  # itself (a ~/.config/zsh layout) would have zsh read that directory's
  # .zshrc and never hi's, so the shim runs it with ZDOTDIR unset, as a plain
  # zsh would, keeps what it chose, and points zsh back here. The .zshrc
  # sources the target's from there, under that ZDOTDIR.
  printf -v q '%q' "$dir"
  {
    printf 'unset ZDOTDIR\n'
    printf '[ -r "$HOME/.zshenv" ] && . "$HOME/.zshenv"\n'
    printf '_hi_zdotdir="${ZDOTDIR:-$HOME}"\n'
    printf 'export ZDOTDIR=%s\n' "$q"
  } >"$dir/.zshenv"
  printf -v zsh_rc '%s\n%s\n%s\n%s' \
    'ZDOTDIR="${_hi_zdotdir:-$HOME}"' \
    '[ -r "$ZDOTDIR/.zshrc" ] && . "$ZDOTDIR/.zshrc"' \
    "export ZDOTDIR=$q" \
    'unset _hi_zdotdir'
  _hi_session_sh_rc "$zsh_rc" "$_HI_ZSHRC" "$dir/.zshrc"

  # fish reads config.fish before -C, so the host's config is already in place
  # by the time this is sourced - the same order as above, for free. The
  # header is our greeting, hence fish_greeting.
  _hi_fishquote q "$_HI_FISH_CONFIG"
  {
    printf "set fish_greeting ''\n"
    printf '%s' "$fish_vars"
    printf 'source %s\n' "$q"
  } >"$dir/fish.config"

  # $ENV is what sh, dash, and ash read for an *interactive* shell. Settings,
  # aliases and paths only, the same subset the bash-less fallback gets - the
  # settings first, since _hi_unexport kept their toggles out of the
  # environment and aliases.sh reads them
  printf -v q '%q' "$_HI_ROOT"
  {
    printf '[ -r %s/config/settings.sh ] && . %s/config/settings.sh\n' "$q" "$q"
    printf '[ -r %s/common/paths.sh ] && . %s/common/paths.sh\n' "$q" "$q"
    printf '[ -r %s/common/aliases.sh ] && . %s/common/aliases.sh\n' "$q" "$q"
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

# _hi_session_editor [name...] - the editor a session exports, with hi's
# config flags: the first installed here of $_HI_EDITOR, the names given (the
# client's own $EDITOR and $VISUAL), and the ladder. The flags
# are read off the alias wiring.sh gave it, or the overlay's aliases.sh
# (sourced here, in the caller's $( ) subshell, so nothing leaks into load())
# - one spelling of each editor's invocation, so an overlay's own
# `alias vim=...` reaches $EDITOR the way it reaches the alias. An editor
# with no alias (one whose config stayed home) goes bare, hence the
# ${body:-$e} tail.
function _hi_session_editor() {
  local e body
  # shellcheck source=./common/aliases.sh
  source "$_HI_ALIASES" >/dev/null 2>&1
  for e in ${_HI_EDITOR:-} "$@" $_HI_EDITORS; do
    type -P "$e" &>/dev/null || continue
    body="$(alias "$e" 2>/dev/null)"
    body="${body#alias "$e"=\'}"
    body="${body%\'}"
    printf '%s' "${body:-$e}"
    return 0
  done
  return 0
}

# The connect and disconnect lines are each assembled by several writers that
# print no newline of their own - hi.sh's payload size, the totals in load()
# below, and banner(), which widens its fill by the prefix already on the
# line instead of starting a new one. Whoever writes last closes it, so with
# the header off (no banner) and nothing optional left to print, this does.
function _hi_line_close() {
  [[ "${_HI_DISABLE_HEADER:-0}" == 1 ]] && printf '\n'
  return 0
}

# _hi_nano_glob <pattern> - adds the files <pattern> matches here to the
# caller's _hi_files; false when it matches none
function _hi_nano_glob() {
  local f n="${#_hi_files[@]}"
  # shellcheck disable=SC2086 # the glob is the point; the path holds no space
  for f in $1; do [[ -f "$f" ]] && _hi_files+=("$f"); done
  [[ "${#_hi_files[@]}" -gt "$n" ]]
}

# _hi_nano_fallback - a syntax include outside /usr/share/nano was dropped on
# the client (its comment survives the strip for this), so the carried
# nanorc highlights nothing. Under each such comment goes its include again
# where an absolute path matches files here, else, under the first, the
# target's stock set. nano resolves an `extendsyntax` as it reads it, so
# placement matters, and so does the name: each takes the spelling of a
# syntax those files define, compared without case (nano-syntax-highlighting
# spells `GO` what the stock set spells `go`), and one naming no syntax here
# is dropped. Rewritten each session from the comments, since the copy rides
# on to a next hop's target. Only a nanorc inside the disposable tree is
# touched.
function _hi_nano_fallback() {
  local rc="${_HI_NANORC:-}" tag='# hi dropped: ' fb='include "/usr/share/nano/*.nanorc"'
  local l r p f adds="" own=$'\n' hit=""
  local -a _hi_files=()
  [[ -n "${_HI_CLEANUP:-}" && "$rc" == "$_HI_CLEANUP"/* && -f "$rc" ]] || return 0
  grep -q '^# hi dropped: include .*\.nanorc' "$rc" || return 0
  while IFS= read -r l || [[ -n "$l" ]]; do
    r="${l#"$tag"}"
    p="${r#"${r%%[![:space:]]*}"}"
    case "$p" in include[[:space:]]*) ;; *) continue ;; esac
    f="${p#include}"
    f="${f#"${f%%[![:space:]]*}"}"
    f="${f#[\"\']}"
    f="${f%%[\"\'[:space:]]*}"
    if [[ "$l" != "$r" ]]; then
      own="$own$r"$'\n'
      [[ "$f" == /* ]] && _hi_nano_glob "$f" && hit=1 && adds="$adds$r"
      adds="$adds"$'\n'
    elif [[ "$l" != "$fb" && "$own" != *$'\n'"$l"$'\n'* ]]; then
      [[ "$f" == \~/* ]] && f="$HOME/${f#??}"
      _hi_nano_glob "$f"
    fi
  done <"$rc"
  [[ -z "$hit" ]] && _hi_nano_glob '/usr/share/nano/*.nanorc' && adds="$fb$adds"
  HI_NANO_RC="$rc" HI_NANO_ADDS="$adds" HI_NANO_FB="$fb" awk '
function syn(s) { gsub(/"/, "", s); have[s] = 1; if (!(tolower(s) in low)) low[tolower(s)] = s }
BEGIN { split(ENVIRON["HI_NANO_ADDS"], add, "\n"); fb = ENVIRON["HI_NANO_FB"] }
FILENAME != ENVIRON["HI_NANO_RC"] { if ($1 == "syntax") syn($2); next }
/^# hi dropped: extendsyntax / { $0 = substr($0, 15) }
/^# hi dropped: include / { print; own[substr($0, 15)] = 1; if (add[++m] != "") print add[m]; next }
$0 == fb || ($0 in own) { next }
$1 == "syntax" { syn($2) }
$1 == "extendsyntax" && !($2 in have) {
  if (!(tolower($2) in low)) { print "# hi dropped: " $0; next }
  match($0, /extendsyntax[ \t]+[^ \t]+/)
  $0 = substr($0, 1, RSTART - 1) "extendsyntax " low[tolower($2)] substr($0, RSTART + RLENGTH)
}
{ print }' ${_hi_files[@]+"${_hi_files[@]}"} "$rc" >"$rc.hi"
  mv -f "$rc.hi" "$rc"
}

# What `hi --keep` typed in this session starts its owner pane with, a
# NAME=value a line for hi.sh's _hi_keep_here: the target's name as the
# client typed it, the client's verdicts, the tree, and this shell, whose
# exit that pane waits out before it removes the tree. GLOSSARY: HI.65
function _hi_keep_file() {
  local v
  for v in _HI_KEEP_AS "${_HI_SESSION_VARS[@]}" NO_COLOR _HI_ROOT _HI_CLEANUP \
    _HI_CONNECT_PREFIX _HI_CONNECT_TIME _HI_COPY_TIME; do
    [ -z "${!v-}" ] || printf '%s=%s\n' "$v" "${!v}"
  done
  printf '_HI_KEEP_OUTER=%s\n' "$$"
}

# A kept session (GLOSSARY: HI.65) runs load() in the owner pane of a tmux,
# zellij, or screen session hi.sh started: $_HI_KEEP_MUX names the multiplexer
# and $_HI_KEEP_NAME the session. The three functions below are that pane's.

# _hi_keep_seconds <duration> <outvar> - <n>, or <n> with s, m, h, or d, as
# seconds; false for anything else
function _hi_keep_seconds() {
  local _hi_kd_n="${1%[smhd]}" _hi_kd_u="${1#"${1%?}"}"
  case "$_hi_kd_n" in '' | *[!0-9]*) return 1 ;; esac
  _hi_kd_n=$((10#$_hi_kd_n))
  case "$_hi_kd_u" in
  m) _hi_kd_n=$((_hi_kd_n * 60)) ;;
  h) _hi_kd_n=$((_hi_kd_n * 3600)) ;;
  d) _hi_kd_n=$((_hi_kd_n * 86400)) ;;
  esac
  printf -v "$2" '%s' "$_hi_kd_n"
}

# Is a client attached to the session this pane owns? zellij lists its
# clients a line each under a header. With no header to read - a zellij too
# old to list them, or one still starting, which answers with nothing - it
# counts as attached, so nothing closes a session somebody may be in.
function _hi_keep_attached() {
  local n
  case "${_HI_KEEP_MUX:-}" in
  tmux)
    n="$(tmux display-message -p -t "=$_HI_KEEP_NAME:" '#{session_attached}' 2>/dev/null)"
    [ "${n:-0}" != 0 ]
    ;;
  zellij)
    n="$(zellij --session "$_HI_KEEP_NAME" action list-clients 2>/dev/null)" || return 0
    [[ "$n" != CLIENT_ID* || "$n" == *$'\n'* ]]
    ;;
  screen) screen -ls 2>/dev/null | grep -F "${STY:-.$_HI_KEEP_NAME}" | grep -F '(Attached)' >/dev/null ;;
  *) return 1 ;;
  esac
}

# The timeout: a background job of the owner pane that ends the session once
# no client has been attached for $_HI_KEEP_TIMEOUT (24h; 0 is never). The
# pane takes the hangup and its exit hook removes the tree, so nothing of
# hi's outlives the session. <step> is the poll, a test's to shorten.
function _hi_keep_watch() {
  local limit step="${1:-60}" idle=0
  [ -n "${_HI_KEEP_NAME:-}" ] || return 0
  _hi_keep_seconds "${_HI_KEEP_TIMEOUT:-24h}" limit || limit=86400
  ((limit > 0)) || return 0
  ((step <= limit)) || step="$limit"
  (
    while sleep "$step"; do
      if _hi_keep_attached; then
        idle=0
      else
        idle=$((idle + step))
        ((idle < limit)) || break
      fi
    done
    case "$_HI_KEEP_MUX" in
    tmux) tmux kill-session -t "=$_HI_KEEP_NAME" ;;
    zellij) zellij kill-session "$_HI_KEEP_NAME" ;;
    screen) screen -S "${STY:-$_HI_KEEP_NAME}" -X quit ;;
    esac
  ) </dev/null >/dev/null 2>&1 &
  _hi_keep_watch_pid=$!
}

# Asked when the owner pane's shell exits with a client attached, since an
# `exit` typed from habit would otherwise end every pane. True to stay: the
# client is detached and load() starts a fresh shell. zellij has no command
# that detaches a client, so there the fresh shell comes with the key that
# does. With nobody attached there is nobody to ask, and the session closes.
function _hi_keep_stays() {
  local reply=""
  [ -n "${_HI_KEEP_NAME:-}" ] && [ -t 0 ] && _hi_keep_attached || return 1
  _hi_cecho " hi: close the kept session? [y/N] " "$YELLOW" 1
  read -r reply || return 1
  case "$reply" in [yY]*) return 1 ;; esac
  case "$_HI_KEEP_MUX" in
  tmux) tmux detach-client -s "=$_HI_KEEP_NAME" ;;
  zellij) _hi_cecho " hi: kept - zellij's own key detaches, Ctrl+o d unless rebound" "$YELLOW" ;;
  screen) screen -S "${STY:-$_HI_KEEP_NAME}" -X detach ;;
  esac
  return 0
}

function load() {
  local start total
  start="$(_hi_now)"
  _hi_on_exit clean_all

  set +euo pipefail

  # an ordinary ssh session can be kept from inside; an owner pane already is
  [ -z "${_HI_KEEP_AS:-}" ] || [ -n "${_HI_KEEP_MUX:-}" ] || _hi_keep_file >"$_HI_ROOT/hi.keep"

  # connect (the client's leg) plus copy (this one), each measured wholly on
  # one machine, since clock skew makes a client/target subtraction
  # meaningless. `load` is not in it - this prints before that leg starts. It
  # continues the size hi.sh printed with no newline, so the total has to
  # widen $_HI_CONNECT_PREFIX or the banner's fill come out wrong.
  total="$(_hi_sum "${_HI_CONNECT_TIME:-0}" "${_HI_COPY_TIME:-0}")"
  # a kept session's owner pane (GLOSSARY: HI.65) opens on an empty line: the
  # size hi.sh printed stayed outside the multiplexer
  [ -z "${_HI_KEEP_NAME:-}" ] || printf '%s' "${_HI_CONNECT_PREFIX:-}"
  _hi_cecho " | ${total}s" "$NC" 1
  [[ "${_HI_DISABLE_HEADER:-0}" == 1 ]] || hi_header Connected "" "${_HI_CONNECT_PREFIX:-} | ${total}s"

  # with the editors off (the settings.sh that rode says so) nothing of
  # theirs rode, and $EDITOR stays the target's own
  local off=" ${_HI_PLUGINS_OFF:-} "
  if [[ "${off//,/ }" != *" editors "* ]]; then
    _hi_nano_fallback
    # vim only: VIMINIT breaks a target that has just vi. Only with the rc
    # here: a client without the editor, or with vim switched off, sends none
    # and wiring.sh names none. nvim reads $VIMINIT too and `:source`
    # runs a .lua file as lua, so a box with nvim and no vim gets init.lua
    # here; a command-line `-u` beats $VIMINIT, so the aliases decide on a box
    # that has both, and this is only for the vim nothing else invokes.
    local vimrc=""
    [[ -f "${_HI_VIMRC:-}" ]] && command -v vim &>/dev/null && vimrc="$_HI_VIMRC"
    [[ -z "$vimrc" && -f "${_HI_NVIMRC:-}" ]] && command -v nvim &>/dev/null && vimrc="$_HI_NVIMRC"
    [[ -n "$vimrc" ]] &&
      export VIMINIT="let \$MYVIMRC='$vimrc' | source \$MYVIMRC"
    # $EDITOR, $VISUAL, and $SUDO_EDITOR: an alias reaches an interactive
    # prompt and nothing else, so `git commit`, `crontab -e`, and `sudo -e` on
    # the target would still open whatever vi it has. Exported for the
    # session shell to inherit, carrying the same flags the alias does. The
    # client's own two stay two - each tried first for its own variable, the
    # other one next - and sudo -e takes $EDITOR's.
    local editor visual
    editor="$(_hi_session_editor "${_HI_CLIENT_EDITOR:-}" "${_HI_CLIENT_VISUAL:-}")"
    visual="$(_hi_session_editor "${_HI_CLIENT_VISUAL:-}" "${_HI_CLIENT_EDITOR:-}")"
    [[ -n "$editor" ]] && export EDITOR="$editor" SUDO_EDITOR="$editor"
    [[ -n "$visual" ]] && export VISUAL="$visual"
  fi
  # $shell is needed either way - _hi_session_shell_cmd below runs it - but
  # the greeting and its three timers are a line of their own, and not part of
  # the header: they survive $_HI_DISABLE_HEADER, which is why they answer to a
  # toggle of their own rather than that one.
  local shell greeting color timer max width close=0 pad=""
  _hi_session_shell shell
  if [[ "${_HI_DISABLE_GREETING:-0}" != 1 ]]; then
    case "$shell" in
    fish) greeting="fish shell! :^)" color="$GREEN" ;;
    zsh) greeting="zsh shell! :)" color="$PURPLE" ;;
    *) greeting="bash today :(" color="$RED" ;;
    esac
    _hi_cecho " | " "$NC" 1
    _hi_cecho "hi loaded: " "$BRCYAN" 1
    _hi_cecho "$greeting" "$color" 1
    # wrapped and closed like the header rows above it; with the header off
    # this line continues hi.sh's, whose width is not known here, so it runs on
    max=0 width=$((14 + ${#greeting}))
    if [[ "${_HI_DISABLE_HEADER:-0}" != 1 ]]; then
      _hi_draw_width max
      [[ "${_HI_DISABLE_RIGHT_EDGE:-0}" == 1 ]] || { close=1 max=$((max - 2)); }
    fi
    for timer in "init: ${_HI_CONNECT_TIME:--1}" "copy: ${_HI_COPY_TIME:--1}" \
      "load: $(_hi_elapsed "$start" "$(_hi_now)")"; do
      timer=" | ${timer}s"
      if ((max && width + ${#timer} > max)); then
        _hi_repeat pad $((max - width)) ' '
        ((close)) && printf '%s |' "$pad"
        printf '\n'
        width=0
      fi
      printf '%s' "$timer"
      width=$((width + ${#timer}))
    done
    _hi_repeat pad $((max - width)) ' '
    ((close)) && printf '%s |' "$pad"
    printf '\n'
  else
    _hi_line_close
  fi

  local shell_ec
  local -a shell_cmd=()
  _hi_session_rc_setup
  _hi_session_shell_cmd "$shell" shell_cmd
  _hi_keep_watch
  while :; do
    shell_ec=0
    "${shell_cmd[@]}" || shell_ec=$?
    _hi_keep_stays || break
  done

  # The shell's last prompt mark was C - `exit` is a command like any other -
  # and the D closing the pair never came, since the shell is gone. A terminal
  # tracking OSC 133 is left "inside a command" until the next D, and Konsole
  # turns the up arrow into a left arrow while it waits.
  printf '\e]133;D;%s\a' "$shell_ec"

  local size dur
  size="$(_hi_du_size "$_HI_ROOT")"
  # $start is load()'s entry, so this is the whole session, not the setup the
  # "load:" line above timed
  _hi_human_duration "$(_hi_elapsed "$start" "$(_hi_now)")" dur
  _hi_cecho " $size | session: $dur" "$NC" 1
  [[ "${_HI_DISABLE_HEADER:-0}" == 1 ]] || hi_footer Disconnected "$BRRED" " $size | session: $dur"
  _hi_line_close
  exit "$shell_ec"
}

# every function above is parsed; the command line after this file is not
[ "$_hi_load_aliases" = 0 ] || shopt -s expand_aliases
unset _hi_load_aliases
