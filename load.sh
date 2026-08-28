#!/usr/bin/env bash
# The target half (forked from sshrc): header, rc grafts, shell handoff, undo.

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

_HI_CONFIG_START="# hi-config-start"
_HI_CONFIG_END="# hi-config-end"

# rc file <- hi config; fish only when installed (no config dir otherwise).
# "<dialect>|<hi's rc>|<the user's rc>", from core.sh's _HI_SHELL_TABLE rows
# flagged `graft` - the same roster scripts/install.sh reads for its local
# half. The dialect is the table's, not re-derived from the rc's suffix: it
# picks the guard below, and a graft whose rc is not named *.fish would
# otherwise get sh syntax appended to a real fish config.
_HI_CONFIGS=()
while IFS='|' read -r _hi_shell _hi_label _hi_tree_rc _hi_home_rc _hi_check _hi_flags _hi_dialect; do
  _HI_CONFIGS+=("$_hi_dialect|$_hi_tree_rc|$_hi_home_rc")
done < <(_hi_shell_rows graft)
unset _hi_shell _hi_label _hi_tree_rc _hi_home_rc _hi_check _hi_flags _hi_dialect

function configure_files() {
  local row dialect target src body
  for row in "${_HI_CONFIGS[@]}"; do
    dialect="${row%%|*}"
    src="${row#*|}"
    src="${src%|*}"
    target="${row##*|}"
    [ -d "${target%/*}" ] || continue # targets are absolute; no dirname fork
    # `: >>` creates without truncating or exec'ing touch, and `$(<f)` is the
    # builtin read where `grep -q` was a second exec - both ran per rc file on
    # every connect. $(<f) slurps where grep short-circuits: fine for an rc.
    : >>"$target"
    case "$(<"$target")" in *"$_HI_CONFIG_START"*) continue ;; esac
    # core.sh's _hi_rc_guard, in the row's dialect (GLOSSARY: HI.24)
    body="$(_hi_rc_guard "$dialect" open)"$'\n'"$(<"$src")"$'\n'"$(_hi_rc_guard "$dialect" close)"
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
  # the session shell's rc directory, which is hi's own and never the target's
  [ -n "${_HI_SESSION_RC_DIR:-}" ] && rm -rf "$_HI_SESSION_RC_DIR"
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

# Where the session shell's rc files are written: a directory of hi's own, never
# the target's $HOME. Made once by _hi_session_rc_setup and removed by clean_all
# - the *same* exit hook, deliberately, because core.sh's _hi_on_exit is a
# `trap ... EXIT` in bash and a second call would replace the first rather than
# adding to it.
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
# This is the load-bearing half of _HI_GRAFT_RC being optional. `bash --rcfile`
# in hi.sh starts the *bootloader*, which sources this file and calls load();
# the shell the user actually types at is started below, and a bare `bash -i`
# reads ~/.bashrc - so until this existed, hi's prompt and aliases reached the
# session only because the graft had written them into that file. Every
# mechanism here is one hi already relies on for a bash-less target (hi.sh's
# _hi_remote_suffix): --rcfile, ZDOTDIR, $ENV and fish's -C.
#
# Each file sources the target's own rc *first*, so the ordering the graft
# produced is preserved exactly: the host's config, then hi's on top of it.
#
# mktemp rather than a path under $_HI_ROOT: on a target with a *permanent*
# say-hi that tree is often root-owned and read-only, which is the whole reason
# your config lives elsewhere. %q on every interpolated path, since $TMPDIR is
# the target's to choose.
#
# shellcheck disable=SC2016 # the single quotes are the point: $HOME is the
# *target's* to expand when it reads these files, not this script's to expand
# while writing them
function _hi_session_rc_setup() {
  [ -z "$_HI_SESSION_RC_DIR" ] || return 0
  _HI_SESSION_RC_DIR="$(mktemp -d -t hi.rc.XXXXXX)" || return 1
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

  printf -v q '%q' "$_HI_BASHRC"
  {
    printf '[ -r "$HOME/.bashrc" ] && . "$HOME/.bashrc"\n'
    printf '%s' "$sh_vars"
    printf '. %s\n' "$q"
  } >"$dir/bashrc"

  # ZDOTDIR moves *all* of zsh's startup files, not just .zshrc, so the
  # target's .zshenv needs a shim of its own or the environment it sets is
  # simply lost. .zprofile/.zlogin are login-shell only, and this is `zsh -i`.
  printf -v q '%q' "$_HI_ZSHRC"
  printf '[ -r "$HOME/.zshenv" ] && . "$HOME/.zshenv"\n' >"$dir/.zshenv"
  {
    printf '[ -r "$HOME/.zshrc" ] && . "$HOME/.zshrc"\n'
    printf '%s' "$sh_vars"
    printf '. %s\n' "$q"
  } >"$dir/.zshrc"

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
# $HOME first. _hi_session_rc_setup has already exported ZDOTDIR, so zsh needs
# nothing here.
function _hi_session_shell_cmd() {
  local shell="$1" out="$2" dir="$_HI_SESSION_RC_DIR"
  case "$shell" in
  bash) eval "$out=(bash --rcfile \"\$dir/bashrc\" -i)" ;;
  zsh) eval "$out=(zsh -i)" ;;
  fish) eval "$out=(fish -C \"source \$dir/fish.config\" -i)" ;;
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
  # Opt-in, and off by default. The graft appends a block to the *target's*
  # ~/.bashrc, ~/.zshrc and fish config so that a shell started inside the
  # session - a `bash` typed at the prompt, a tmux pane - looks like the
  # session around it.
  #
  # The graft is not what styles the session's *own* shell:
  # _hi_session_shell_cmd above starts that shell directly against hi's rc
  # (--rcfile / ZDOTDIR / fish -C), independent of the target's own rc files.
  # What the graft is for is a shell started *inside* the session - a `bash`
  # typed at the prompt, a tmux pane - which spawns via the target's own
  # ~/.bashrc/~/.zshrc/fish config and would otherwise come up unstyled, `hi`
  # inside it reading as "command not found".
  #
  # What it costs is a write to a login file on someone else's machine, twice
  # per session, for every host anyone ever says hi to: an entry in whatever
  # file-integrity monitor watches those paths, a window in which another
  # login on a shared account reads a half-written rc, and a block left behind
  # whenever the process dies between the write and clean_all. None of that is
  # a fair price for a convenience most sessions never use, so it is something
  # a user turns on for the hosts they want it on, rather than a default.
  #
  # clean_all stays unconditional: it must still take out a block left by a
  # session that ran with this on, or by a build that shipped before it existed.
  [ "${_HI_GRAFT_RC:-0}" = 1 ] && configure_files
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
    [[ "${_HI_HEADER_TIMESTAMP:-1}" == 0 ]] || timestamp
  fi
  _hi_cecho " | " "$NC" 1
  _hi_cecho "hi closing! " "$BRPURPLE"
  exit "$shell_ec"
}
