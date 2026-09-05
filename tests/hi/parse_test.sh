#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Unit tests for hi.sh, the client entry point: argument parsing, backend
# dispatch, `--help` and the local sub-commands - everything that decides what
# hi is about to do before it does any of it.
#
# Sourcing hi.sh goes through the same `[[ BASH_SOURCE == $0 ]]` hatch install.sh
# uses, which defines every function without connecting to anything - so the pure
# half is reachable here, where a mis-parse is an assertion rather than a
# confusing connection failure. _say_hi stays e2e-only by nature.
#
# GLOSSARY: HI.30 + HI.34. The linter follows `source "$_HI_LAUNCHER"` into hi.sh's
# trailing `_hi "$@"`, decides it never returns, and marks this file unreachable
# (SC2317) - it does not model the BASH_SOURCE guard. The single-quoted strings
# below are the target's to expand, not ours (SC2016).
# shellcheck disable=SC2329,SC2317,SC2016
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"
# shellcheck source=../../hi.sh
source "$_HI_LAUNCHER"

# The fake backend CLIs come from test_lib.sh's _hi_probe_shims - the one
# home of the exact argv shapes hi.sh's predicates make. "yes" is
# running/Running, anything else is not.
_HI_SHIM_PATH=""

# _hi_parse writes to the globals DOMAIN/CMDARG/SSHARGS and can exit outright,
# so every case runs it in a subshell and prints what it produced. Fields are
# newline-separated: DOMAIN, CMDARG, then one line per SSHARGS entry.
function _hi_parse_out() {
  (
    unset DOMAIN CMDARG
    _hi_parse "$@" >/dev/null 2>&1
    printf '%s\n%s\n' "${DOMAIN:-}" "${CMDARG:-}"
    [ "${#SSHARGS[@]}" -eq 0 ] || printf '%s\n' "${SSHARGS[@]}"
  )
}

function test_parse_handles_several_flags_before_the_target() {
  [ "$(_hi_parse_out -4 -o StrictHostKeyChecking=no -i /tmp/k myhost)" = \
    "$(printf 'myhost\n\n-4\n-o\nStrictHostKeyChecking=no\n-i\n/tmp/k\n')" ]
}

# a trailing command becomes CMDARG - suffixed with "; exit" so the target
# shell closes after it - and never a second target. The spacing between the
# two is incidental (_hi_parse pastes '; ' and ' exit'), so don't pin it.
function test_parse_turns_trailing_words_into_a_command() {
  local out
  out="$(_hi_parse_out myhost echo hello)"
  [[ "$out" == myhost*"echo hello;"*exit* ]]
}

function test_parse_leaves_cmdarg_empty_for_a_plain_session() {
  [ "$(_hi_parse_out myhost | sed -n 2p)" = "" ]
}

# ssh itself takes no "--" option (the loop's own comment says so), so "--"
# just falls into the -* arm like any other unrecognized flag: it does not end
# option parsing, and the word after it is still read as a flag, not a target.
# With no DOMAIN set and SSHARGS non-empty, _hi_parse skips the picker and
# execs a real ssh, then exits 1 unconditionally - it never returns to
# _hi_parse_out, so this shims ssh to log its argv and asserts that instead.
function test_parse_dashdash_does_not_end_option_parsing() {
  local bin="$_HI_WORKDIR/dashdash.bin" log="$_HI_WORKDIR/dashdash.log" rc=0
  mkdir -p "$bin"
  cat >"$bin/ssh" <<SHIM
#!/bin/sh
printf '%s\n' "\$*" >"$log"
exit 0
SHIM
  chmod +x "$bin/ssh"
  (PATH="$bin:$PATH" _hi_parse -- -oddtarget >/dev/null 2>&1) || rc=$?
  [ "$rc" -eq 1 ] || return 1
  [ "$(cat "$log")" = "-- -oddtarget" ]
}

# a value-taking flag with nothing after it must report itself, not die on an
# unbound $2 or swallow the next argument
function test_parse_rejects_a_flag_missing_its_value() {
  local rc=0
  (_hi_parse -p >/dev/null 2>&1) || rc=$?
  [ "$rc" -eq 1 ]
}

function test_parse_names_the_offending_flag() {
  local out
  out="$( (_hi_parse -o 2>&1 >/dev/null) || true)"
  [[ "$out" == *"-o"* ]]
}

# _hi_pick_target - what bare `hi` reaches instead of ssh's usage message.
#
# $_HI_TARGETS is assigned *after* hi.sh is sourced in every case below, never
# exported into it: sourcing hi.sh goes through common/paths.sh, which derives
# that variable from the tree and would overwrite anything the environment had
# to say about it - and the case would then quietly run against this machine's
# real target list.
#
# _hi_pick_rows - a stand-in targets.sh printing three rows, one per backend
# shape: a plain ssh host, a container, and a pod whose name carries a colon.
function _hi_pick_rows() {
  local f="$_HI_WORKDIR/pick-targets.sh"
  if [ ! -f "$f" ]; then
    mkdir -p "$_HI_WORKDIR"
    printf '%s\n' '#!/bin/sh' \
      'printf "web1\tssh\napi\tdocker\nteam:pod\tkube\n"' >"$f"
    chmod +x "$f"
  fi
  printf '%s' "$f"
}

# an empty one, for the "nothing to offer" direction
function _hi_pick_no_rows() {
  local f="$_HI_WORKDIR/pick-empty.sh"
  if [ ! -f "$f" ]; then
    mkdir -p "$_HI_WORKDIR"
    printf '%s\n' '#!/bin/sh' 'exit 0' >"$f"
    chmod +x "$f"
  fi
  printf '%s' "$f"
}

# _hi_pick_shim <name> - a directory whose only executable is <name>, standing
# in for fzf or sk: it takes the row the caller asks for by line number
# ($_HI_PICK_LINE, default 1) and prints it back whole, tab and all, which is
# what both real pickers do.
function _hi_pick_shim() {
  local dir="$_HI_WORKDIR/pick-$1"
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    printf '%s\n' '#!/bin/sh' \
      'sed -n "${_HI_PICK_LINE:-1}p"' >"$dir/$1"
    chmod +x "$dir/$1"
  fi
  printf '%s' "$dir"
}

# _hi_pick <PATH> [stdin] - _hi_pick_target's stdout, then its exit code on a
# line of its own. The PATH is total rather than prepended: fzf really is
# installed on plenty of developer machines, and a case about the `select`
# fallback has to be able to say it is not here.
function _hi_pick() {
  local path="$1" input="${2-}"
  PATH="$path" bash -c '
    source "$_HI_LAUNCHER"
    _HI_TARGETS="$1"
    rc=0
    _hi_pick_target || rc=$?
    printf "\n%s\n" "$rc"' _ "$(_hi_pick_rows)" <<<"$input" 2>/dev/null
}

# the tools _hi_pick_target and hi.sh's own source-time work need, and nothing
# that could pick for them: fzf really is installed on plenty of developer
# machines, and the `select` cases have to be able to say it is not here
function _hi_pick_bare_path() {
  _hi_real_path pickbare bash sh sed cat
}

function test_pick_uses_fzf_when_it_is_there() {
  local out
  out="$(_HI_PICK_LINE=2 _hi_pick "$(_hi_pick_shim fzf):$(_hi_pick_bare_path)")"
  [ "$out" = "$(printf 'api\n0\n')" ]
}

# sk is the second rung of the same ladder, reached only when fzf is absent
function test_pick_falls_through_to_sk() {
  local out
  out="$(_HI_PICK_LINE=3 _hi_pick "$(_hi_pick_shim sk):$(_hi_pick_bare_path)")"
  [ "$out" = "$(printf 'team:pod\n0\n')" ]
}

# ...and the tag is cut back off, whichever picker answered: fzf is shown two
# columns so the backend is visible, but only the name is a target
function test_pick_returns_the_name_without_its_tag() {
  local out
  out="$(_HI_PICK_LINE=1 _hi_pick "$(_hi_pick_shim fzf):$(_hi_pick_bare_path)")"
  [ "$out" = "$(printf 'web1\n0\n')" ]
}

# neither picker installed: a numbered `select`, so nothing has to be installed
# for bare `hi` to work at all. The menu goes to stderr, the pick to stdout.
function test_pick_falls_back_to_a_numbered_select() {
  local out
  out="$(_hi_pick "$(_hi_pick_bare_path)" 3)"
  [ "$out" = "$(printf 'team:pod\n0\n')" ]
}

# the fallback names the backend beside each row, the way the pickers do
function test_select_menu_tags_each_row() {
  local menu
  menu="$(PATH="$(_hi_pick_bare_path)" bash -c '
    source "$_HI_LAUNCHER"
    _HI_TARGETS="$1"
    _hi_pick_target >/dev/null' _ "$(_hi_pick_rows)" <<<"3" 2>&1)"
  [[ "$menu" == *"web1 (ssh)"* && "$menu" == *"api (docker)"* && "$menu" == *"team:pod (kube)"* ]]
}

# dismissed rather than chosen - a real fzf answers empty on Ctrl-C, and the
# shim does the same asked for a line that is not there. 1, not 2: hi.sh tells
# the two apart, because only one of them still owes the user ssh's usage.
function test_pick_reports_a_dismissal_as_one() {
  local out
  out="$(_HI_PICK_LINE=99 _hi_pick "$(_hi_pick_shim fzf):$(_hi_pick_bare_path)")"
  [ "$out" = "$(printf '\n1\n')" ]
}

# nothing to offer is 2, which is what sends hi.sh back to ssh's usage rather
# than exiting quietly on a machine that simply has no targets yet
function test_pick_reports_an_empty_list_as_two() {
  local out
  out="$(PATH="$(_hi_pick_shim fzf):$(_hi_pick_bare_path)" bash -c '
    source "$_HI_LAUNCHER"
    _HI_TARGETS="$1"
    rc=0
    _hi_pick_target || rc=$?
    printf "\n%s\n" "$rc"' _ "$(_hi_pick_no_rows)" </dev/null 2>/dev/null)"
  [ "$out" = "$(printf '\n2\n')" ]
}

# ...and the arm itself: a bare `hi` on a terminal comes out of _hi_parse with
# $DOMAIN filled in, which is what makes it land a session. Under a pty,
# because the arm is gated on both ends of one - see the case below for why.
# The PATH is narrowed *inside* the child rather than around it: the pty
# wrapper is python3, and a PATH with no picker on it has no python3 either.
function test_bare_hi_takes_a_target_from_the_picker() {
  local out
  out="$(_HI_PICK_LINE=2 "${_HI_PTY_FORCED[@]}" bash -c '
      source "$_HI_LAUNCHER"
      PATH="$2"
      _HI_TARGETS="$1"
      _hi_parse
      printf "DOMAIN=%s\n" "${DOMAIN:-}"' _ "$(_hi_pick_rows)" \
    "$(_hi_pick_shim fzf):$(_hi_pick_bare_path)" 2>/dev/null)"
  [[ "$out" == *"DOMAIN=api"* ]]
}

# No terminal, no picker. A `hi` in a script or a CI job has nobody to answer a
# menu, so it has to go on failing the way it always has rather than hang on
# one - which is what the `-t 0` half of the guard is for.
function test_bare_hi_without_a_terminal_still_reaches_ssh() {
  local out rc=0
  out="$(PATH="$(_hi_pick_shim fzf):$(_hi_real_path pickssh bash sh sed cat ssh)" bash -c '
    source "$_HI_LAUNCHER"
    _HI_TARGETS="$1"
    _hi_parse' _ "$(_hi_pick_rows)" </dev/null 2>&1)" || rc=$?
  # ssh with no arguments prints its usage and fails; either way the picker
  # must not have spoken, so no target name can be in what came back
  [ "$rc" -ne 0 ] && [[ "$out" != *api* ]]
}

# an ssh option with no host is ssh's error to report, not a target to guess
# at: `hi -V` has to stay `ssh -V`. The stub prints its argv, so the case can
# say the flag arrived rather than merely that the picker stayed quiet.
function test_an_ssh_option_without_a_target_never_picks() {
  local dir out rc=0
  dir="$_HI_WORKDIR/pick-sshstub"
  mkdir -p "$dir"
  printf '%s\n' '#!/bin/sh' 'echo "ssh-stub: $*"' >"$dir/ssh"
  chmod +x "$dir/ssh"
  out="$("${_HI_PTY_FORCED[@]}" bash -c '
      source "$_HI_LAUNCHER"
      PATH="$2"
      _HI_TARGETS="$1"
      _hi_parse -4' _ "$(_hi_pick_rows)" \
    "$dir:$(_hi_pick_shim fzf):$(_hi_pick_bare_path)" 2>&1)" || rc=$?
  [[ "$out" == *"ssh-stub: -4"* ]] && [[ "$out" != *api* ]]
}

function test_is_docker_container_accepts_a_running_one() {
  PATH="$_HI_SHIM_PATH" _hi_is_docker_container yes
}

function test_is_docker_container_rejects_a_stopped_one() {
  ! PATH="$_HI_SHIM_PATH" _hi_is_docker_container no
}

function test_is_podman_container_accepts_a_running_one() {
  PATH="$_HI_SHIM_PATH" _hi_is_podman_container yes
}

function test_is_nomad_alloc_accepts_a_running_one() {
  PATH="$_HI_SHIM_PATH" _hi_is_nomad_alloc yes
}

function test_is_nomad_alloc_rejects_a_pending_one() {
  ! PATH="$_HI_SHIM_PATH" _hi_is_nomad_alloc no
}

function test_is_k8s_pod_accepts_a_running_one() {
  PATH="$_HI_SHIM_PATH" _hi_is_k8s_pod yes
}

function test_is_k8s_pod_rejects_a_pending_one() {
  ! PATH="$_HI_SHIM_PATH" _hi_is_k8s_pod no
}

# with no backend CLI on $PATH at all, every predicate must answer "no"
# rather than erroring - that is what lets _hi fall through to ssh
function test_predicates_are_false_without_their_cli() {
  local empty="$_HI_WORKDIR/empty"
  mkdir -p "$empty"
  ! PATH="$empty" _hi_is_docker_container yes &&
    ! PATH="$empty" _hi_is_podman_container yes &&
    ! PATH="$empty" _hi_is_nomad_alloc yes &&
    ! PATH="$empty" _hi_is_k8s_pod yes
}

# The predicates run together now, so the guarantee worth pinning is that the
# *answer* is still the roster's first match rather than whichever CLI
# happened to reply first. The shims answer for target "yes", so a target
# every backend claims must still resolve to docker - the row at the top of
# $_HI_BACKENDS.

function test_resolve_backend_picks_the_first_matching_row() {
  [ "$(PATH="$_HI_SHIM_PATH" _hi_resolve_backend yes)" = docker ]
}

# ...and the roster order is the thing being asserted, not "docker": prove it
# moves with the table rather than being baked into the resolver
function test_resolve_backend_follows_the_roster_order() {
  local out
  out="$(
    # SC2030: subshell-local is exactly the intent - the swap must not leak
    # into the cases below, which read the real roster
    # shellcheck disable=SC2030
    _HI_BACKENDS=("${_HI_BACKENDS[1]}" "${_HI_BACKENDS[0]}")
    PATH="$_HI_SHIM_PATH" _hi_resolve_backend yes
  )"
  [ "$out" = podman ]
}

# The header's identity() row counts the same backends this roster dispatches
# on, but it cannot read $_HI_BACKENDS - hi.sh is never sourced in a session,
# and a shared roster would cost the ssh payload bytes for a list that changes
# about once a year. So the drift is caught here instead of prevented there -
# the header is the copy a user sees on every single connect. Add a backend to
# the roster and this goes red until common/header.sh's _hi_probe_launch
# counts it too.
function test_header_probes_every_backend_in_the_roster() {
  local row name launch
  launch="$(sed -n '/^function _hi_probe_launch()/,/^}/p' "$_HI_HEADER")"
  [ -n "$launch" ] || return 1
  # SC2031: the roster swap above happens inside a $( ) and never reaches here;
  # this reads the file-scope table, which is the whole point of the check
  # shellcheck disable=SC2031
  for row in "${_HI_BACKENDS[@]}"; do
    name="${row%%|*}"
    # podman is docker's drop-in and shares its probe, so either name counts;
    # kube is probed by its CLI's name rather than the roster's
    case "$name" in
    podman) [[ "$launch" == *podman* || "$launch" == *docker* ]] || return 1 ;;
    kube) [[ "$launch" == *kubectl* || "$launch" == *kube* ]] || return 1 ;;
    *) [[ "$launch" == *"$name"* ]] || return 1 ;;
    esac
  done
}

function test_resolve_backend_prints_nothing_for_a_stranger() {
  [ -z "$(PATH="$_HI_SHIM_PATH" _hi_resolve_backend no)" ]
}

# no CLI at all: every predicate is false, and _hi falls through to ssh
function test_resolve_backend_prints_nothing_without_any_cli() {
  local empty="$_HI_WORKDIR/empty"
  mkdir -p "$empty"
  [ -z "$(PATH="$empty" _hi_resolve_backend yes)" ]
}

# common/flags is what --help and completion read; drift here means a backend
# a user can reach through the roster has no flag to force it with, or a flag
# _hi_backend_flag doesn't actually recognize.
#
# SC2031: the roster swap above (test_resolve_backend_follows_the_roster_order)
# happens inside a $( ) and never reaches here; this reads the file-scope table
function test_every_backend_has_a_flag_row() {
  local name
  # shellcheck disable=SC2031
  for name in ssh "${_HI_BACKENDS[@]%%|*}"; do
    grep -q "^--$name|" "$_HI_ROOT/common/flags" || return 1
    [ "$(_hi_backend_flag "--$name")" = "$name" ] || return 1
  done
}

function test_backend_flag_rejects_a_stranger() {
  ! _hi_backend_flag --frobnicate >/dev/null 2>&1
}

# BACKEND and PLAIN are _hi_parse's other outputs, alongside DOMAIN/CMDARG/
# SSHARGS - _hi_parse_out predates them and pins an exact line count, so each
# reads through this helper instead of disturbing that one. Never folded into
# SSHARGS either way: _hi_parse_out's exact-output form would catch an extra
# line if one leaked through. ${!var}, not a nameref - the bash 3.2 floor has
# none.
function _hi_var_parse_out() { # <var> <default> <args...>
  local var="$1" default="$2"
  shift 2
  (
    unset DOMAIN CMDARG "$var"
    _hi_parse "$@" >/dev/null 2>&1
    printf '%s\n%s\n' "${DOMAIN:-}" "${!var:-$default}"
  )
}

function _hi_backend_parse_out() {
  _hi_var_parse_out BACKEND "" "$@"
}

function test_parse_backend_flags_set_backend_for_every_name() {
  local name
  for name in ssh docker podman nomad kube; do
    [ "$(_hi_backend_parse_out "--$name" myhost)" = "$(printf 'myhost\n%s\n' "$name")" ] || return 1
  done
}

# a backend flag is consumed outright, not folded into SSHARGS the way an
# ssh option is - _hi_parse_out's existing exact-output form catches an extra
# SSHARGS line if it ever leaked through
function test_parse_backend_flag_does_not_reach_sshargs() {
  [ "$(_hi_parse_out --docker myhost)" = "$(printf 'myhost\n\n')" ]
}

function test_parse_two_backend_flags_refuse_each_other() {
  local rc=0
  (_hi_parse --docker --ssh myhost >/dev/null 2>&1) || rc=$?
  [ "$rc" -eq 1 ]
}

function test_parse_names_both_conflicting_flags() {
  local out
  out="$( (_hi_parse --docker --ssh myhost 2>&1 >/dev/null) || true)"
  [[ "$out" == *"--ssh"*"--docker"* ]]
}

# the same flag twice is not a conflict
function test_parse_repeating_a_backend_flag_is_fine() {
  [ "$(_hi_backend_parse_out --docker --docker myhost)" = "$(printf 'myhost\ndocker\n')" ]
}

# once DOMAIN is set, a following -word is ssh's business again (today's
# behaviour, unchanged: only ahead of the target does a backend flag mean
# anything to hi itself)
function test_parse_backend_flag_after_the_target_is_not_claimed() {
  [ "$(_hi_backend_parse_out myhost --docker)" = "$(printf 'myhost\n\n')" ]
}

function _hi_plain_parse_out() {
  _hi_var_parse_out PLAIN 0 "$@"
}

function test_parse_plain_sets_plain_not_sshargs() {
  [ "$(_hi_plain_parse_out --plain myhost)" = "$(printf 'myhost\n1\n')" ] &&
    [ "$(_hi_parse_out --plain myhost)" = "$(printf 'myhost\n\n')" ]
}

# combines freely with a backend flag - orthogonal, checked in either order
function test_parse_plain_combines_with_a_backend_flag() {
  [ "$(_hi_plain_parse_out --plain --docker myhost)" = "$(printf 'myhost\n1\n')" ] &&
    [ "$(_hi_backend_parse_out --plain --docker myhost)" = "$(printf 'myhost\ndocker\n')" ]
}

# RAWCMD is CMDARG's raw material, without the "; exit" suffix baked in for
# the bootloader's own embedding - --plain execs the words directly and has
# no bootloader to close out
function test_parse_rawcmd_has_no_exit_suffix() {
  local out
  out="$(
    unset RAWCMD CMDARG
    _hi_parse myhost echo hello >/dev/null 2>&1
    printf '%s\n%s\n' "$RAWCMD" "$CMDARG"
  )"
  [ "$(printf '%s\n' "$out" | sed -n 1p)" = "echo hello" ] &&
    [[ "$(printf '%s\n' "$out" | sed -n 2p)" == *"exit"* ]]
}

# _hi_select_arm is what _hi calls to choose $arm; testing it directly means
# asserting the choice without a real connect
function test_select_arm_backend_flag_wins_over_a_real_match() {
  local DOMAIN=yes BACKEND=ssh
  [ -z "$(PATH="$_HI_SHIM_PATH" _hi_select_arm)" ]
}

function test_select_arm_backend_flag_names_the_arm_with_no_probe() {
  local DOMAIN=no BACKEND=docker
  # PATH has nothing at all: a probe would find no CLI and print nothing, so
  # a printed "docker" here can only have come from $BACKEND
  local empty="$_HI_WORKDIR/empty"
  mkdir -p "$empty"
  [ "$(PATH="$empty" _hi_select_arm)" = docker ]
}

function test_select_arm_falls_back_to_resolution_when_backend_unset() {
  local DOMAIN=yes BACKEND=
  [ "$(PATH="$_HI_SHIM_PATH" _hi_select_arm)" = docker ]
}

function test_report_failure_is_silent_once_hi_already_said_it() {
  local _HI_SAID=1
  [ -z "$(_hi_report_failure 255 "" "" 2>&1)" ]
}

# ssh reserves 255 for its own failures; anything else through the ssh arm is
# the session's or the remote command's own exit status, which ssh itself
# never announces either
function test_report_failure_is_silent_for_a_non_255_ssh_exit() {
  [ -z "$(_hi_report_failure 1 "" "" 2>&1)" ]
}

function test_report_failure_speaks_on_255() {
  local DOMAIN=myhost f="$_HI_WORKDIR/ssh255.log"
  : >"$f"
  [[ "$(_hi_report_failure 255 "" "$f" 2>&1)" == *"could not reach [myhost]"* ]]
}

# a container arm with nothing filed in its errlog means nothing hi ran on
# the way in complained, so the exit is the session's, not hi's to announce
function test_report_failure_is_silent_for_a_quiet_container_errlog() {
  local f="$_HI_WORKDIR/empty.log"
  : >"$f"
  [ -z "$(_hi_report_failure 1 docker "$f" 2>&1)" ]
}

function test_report_failure_speaks_with_a_filed_container_error() {
  local DOMAIN=mybox f="$_HI_WORKDIR/filed.log"
  printf 'copy failed\n' >"$f"
  local out
  out="$(_hi_report_failure 1 docker "$f" 2>&1)"
  [[ "$out" == *"could not reach [mybox]"* && "$out" == *"copy failed"* ]]
}

# no \r anywhere when stderr is not a terminal - a captured/piped failure
# gets a plain newline instead of a cursor move that has nothing to move
function test_report_failure_has_no_carriage_return_off_a_tty() {
  local DOMAIN=myhost f="$_HI_WORKDIR/notty.log"
  : >"$f"
  [[ "$(_hi_report_failure 255 "" "$f" 2>&1)" != *$'\r'* ]]
}

# _hi_attach_is <backend> <domain> <want-glob> - run _hi_container_cmds for
# <backend> against <domain> and match the attach line against <want-glob>
# (a leading ! inverts the match). DOMAIN and the command arrays land in the
# caller's own locals through bash's dynamic scoping, so a case can still
# read cp or probe after its last run.
function _hi_attach_is() {
  local want="$3" negate=0 why="want"
  case "$want" in !*)
    negate=1
    why="did not want"
    want="${want#!}"
    ;;
  esac
  DOMAIN="$2"
  _hi_container_cmds "$1"
  # SC2254: the unquoted expansion is the point - $want is a glob
  # shellcheck disable=SC2254
  case "${attach[*]}" in
  $want) [ "$negate" -eq 0 ] && return 0 ;;
  *) [ "$negate" -eq 1 ] && return 0 ;;
  esac
  _hi_cecho " | $1 $2: attach was '${attach[*]}', $why '$want'" "$RED"
  return 1
}

# `pod/container` and `alloc/task`: one spelling for both, because a task and a
# container are the same idea. The plain form has to stay byte-identical - this
# syntax is additive or it breaks every existing target.
function test_container_cmds_pick_the_inner_unit() {
  local -a probe cp attach
  # a tty, pinned: these cases are about the target *grammar* - the inner unit
  # and the kube prefixes - and a suite has no tty of its own, so without this
  # they would be asserting the tty probe's answer by accident
  local DOMAIN _HI_TTY=1

  _hi_attach_is kube mypod '!* -c *' || return 1
  _hi_attach_is kube mypod/sidecar '*exec -it mypod -c sidecar --' || return 1
  _hi_attach_is nomad 685afd67/worker '*-task worker*685afd67' || return 1
  # docker has no inner unit and `/` is legal in a container name, so it is
  # taken whole - splitting one would break a real target
  _hi_attach_is docker some/name '*exec -it some/name'
}

# The other arm of that probe, which is the one `hi <target> <cmd> | ...` takes:
# `docker exec -it` does not fall back to a pipe when stdin is not a terminal,
# it refuses ("cannot attach stdin to a TTY-enabled container"), so the command
# form failed at the transport before the command ran. Every container backend
# has to drop the `-t` and keep the `-i`; nomad spells both out either way,
# because its own stdin-is-a-tty guess hangs the exec on a wrapped pty.
function test_container_cmds_drop_the_tty_without_one() {
  local -a probe cp attach
  local DOMAIN _HI_TTY=0

  _hi_attach_is kube mypod '*exec -i mypod --' || return 1
  _hi_attach_is docker somebox '*exec -i somebox' || return 1
  _hi_attach_is nomad 685afd67 '*-i=true -t=false*' || return 1

  # ...and the copy stream never wanted a tty in the first place, either way.
  # Matched on the *enabled* spellings, not a bare "-t": nomad's cp line says
  # `-t=false` on purpose, and a glob for "-t" calls that a tty.
  case "${cp[*]}" in
  *"-it"* | *"-t=true"*)
    _hi_cecho " | the cp stream grew a tty: '${cp[*]}'" "$RED"
    return 1
    ;;
  esac
  return 0
}

# The kube prefixes: `namespace:pod` and `context:namespace:pod`, with or
# without a `/container`, each landing as kubectl's own flags ahead of `exec`.
function test_kube_prefixes_become_kubectl_flags() {
  local -a probe cp attach
  # a tty, pinned: these cases are about the target *grammar* - the inner unit
  # and the kube prefixes - and a suite has no tty of its own, so without this
  # they would be asserting the tty probe's answer by accident
  local DOMAIN _HI_TTY=1

  _hi_attach_is kube staging:web \
    'kubectl --namespace staging exec -it web --' || return 1
  _hi_attach_is kube prod:staging:web/sidecar \
    'kubectl --context prod --namespace staging exec -it web -c sidecar --'
}

# A docker shim scoped to --plain: exec-only, and it refuses (exit 9) any
# invocation shaped like a write - mkdir, tar, or a `cat >` redirect target -
# so a plain path that ever tried to copy something would fail loudly here
# instead of a real /tmp write silently passing on this machine's own docker.
# $HI_FAKE_BASH answers the bash probe; the ladder probe always answers
# "dash" (a real $_HI_SHELL_LADDER member, so the caller's own validation
# against it passes) since which one hi picks is not what these cases are about.
function _hi_plain_container_shim() {
  local dir="$_HI_WORKDIR/plainshims"
  [ -d "$dir" ] && {
    printf '%s' "$dir"
    return 0
  }
  mkdir -p "$dir"
  cat >"$dir/docker" <<'EOF'
#!/bin/sh
for a in "$@"; do
  case "$a" in
  *mkdir*'-p'*|*'tar '*|*'cat >'*)
    echo "docker shim: unexpected write: $*" >&2
    exit 9
    ;;
  esac
done
[ "$1" = exec ] || exit 1
shift
for a in "$@"; do
  case "$a" in
  'command -v bash') [ "${HI_FAKE_BASH:-0}" = 1 ] && exit 0 || exit 1 ;;
  'for _hi_s in'*) printf 'dash\n'; exit 0 ;;
  esac
done
# neither marker present: this is the attach call, shaped -i/-it <target>
# "$shell" [-c "$cmd"] - drop the flag and the target, keep the rest
case "$1" in -i | -it) shift ;; esac
shift
printf 'ATTACHED:%s\n' "$*"
EOF
  chmod +x "$dir/docker"
  printf '%s' "$dir"
}

function test_plain_container_attaches_with_no_write() {
  local out DOMAIN RAWCMD=""
  DOMAIN=mybox
  out="$(PATH="$(_hi_plain_container_shim):$PATH" HI_FAKE_BASH=1 _say_hi_container_plain docker)"
  [[ "$out" == "ATTACHED:bash" ]]
}

function test_plain_container_falls_back_to_the_ladder_without_bash() {
  local out DOMAIN RAWCMD=""
  DOMAIN=mybox
  out="$(PATH="$(_hi_plain_container_shim):$PATH" HI_FAKE_BASH=0 _say_hi_container_plain docker)"
  [[ "$out" == "ATTACHED:dash" ]]
}

function test_plain_container_runs_rawcmd_with_dash_c() {
  local out DOMAIN RAWCMD
  DOMAIN=mybox
  RAWCMD="echo hi"
  out="$(PATH="$(_hi_plain_container_shim):$PATH" HI_FAKE_BASH=1 _say_hi_container_plain docker)"
  [[ "$out" == "ATTACHED:bash -c echo hi" ]]
}

# ssh itself is "just get me a shell" with no target, so --plain's ssh path
# is real ssh with no bootstrap - asserted through a shim that echoes its own
# argv, proving nothing beyond SSHARGS/DOMAIN/RAWCMD ever reaches it
function test_plain_ssh_execs_real_ssh_with_rawcmd() {
  local dir="$_HI_WORKDIR/plainssh" out
  mkdir -p "$dir"
  cat >"$dir/ssh" <<'EOF'
#!/bin/sh
echo "SSH:$*"
EOF
  chmod +x "$dir/ssh"
  out="$(
    DOMAIN=myhost SSHARGS=() RAWCMD="echo hi" _HI_TTY=0
    PATH="$dir:$PATH" _say_hi_plain
  )"
  [[ "$out" == "SSH:myhost echo hi" ]]
}

function test_plain_ssh_with_no_command_passes_none() {
  # the same argv-echoing shim, written by the RAWCMD case above - the two
  # run in registration order
  local dir="$_HI_WORKDIR/plainssh"
  local out
  out="$(
    DOMAIN=myhost SSHARGS=() _HI_TTY=0
    unset RAWCMD
    PATH="$dir:$PATH" _say_hi_plain
  )"
  [[ "$out" == "SSH:myhost" ]]
}

# The one arm of the dispatch block that has to be *executed* rather than
# sourced: sourcing hi.sh stops at the BASH_SOURCE guard, which is above the
# `case "${1:-}"`. So these run the real launcher as a subprocess, with an ssh
# that fails loudly on $PATH - proof that the flag is caught before it ever
# reaches ssh, rather than falling through to ssh's own usage block.

# --help is asserted four separate ways and its output cannot differ between
# them, so it is launched once and kept; the ssh shim that makes a stray
# connect attempt loud is built once for the same reason.
_HI_HELP_OUT=""

function _hi_help_out() {
  local dir="$_HI_WORKDIR/nossh" out rc=0
  [ -x "$dir/ssh" ] || {
    mkdir -p "$dir"
    cat >"$dir/ssh" <<'EOF'
#!/bin/sh
echo "ssh was called: $*" >&2
exit 97
EOF
    chmod +x "$dir/ssh"
  }
  if [ "$*" = "--help" ] && [ -n "$_HI_HELP_OUT" ]; then
    printf '%s\n' "$_HI_HELP_OUT"
    return 0
  fi
  out="$(PATH="$dir:$PATH" "$_HI_LAUNCHER" "$@" 2>&1)" || rc=$?
  [ "$*" = "--help" ] && [ "$rc" -eq 0 ] && _HI_HELP_OUT="$out"
  printf '%s\n' "$out"
  return "$rc"
}

function test_help_long_flag_prints_usage() {
  local out
  out="$(_hi_help_out --help)" || return 1
  [[ "$out" == "Usage: hi "* && "$out" != *"ssh was called"* ]]
}

# the two things a usage block is for: what the flags are, and how a name is
# resolved - hi's target ladder is the part no ssh user can guess
function test_help_lists_hi_s_own_flags() {
  local out flag
  out="$(_hi_help_out --help)" || return 1
  for flag in --doctor --version; do
    [[ "$out" == *"$flag"* ]] || return 1
  done
  [[ "$out" == *docker* && "$out" == *podman* && "$out" == *nomad* && "$out" == *kubernetes* ]]
}

# The same drift guard tests/test_runner.sh's suite table gets: a flag hi
# answers itself but the man page never mentions is a flag nobody finds.
# $_HI_USAGE's synopsis has to match the man page's .SH SYNOPSIS too. The
# flag list is scraped from the live --help output rather than copied here,
# so a flag added there is guarded the moment it exists - with a floor on the
# scrape's size, so a broken scrape can't pass as an empty loop.
function test_help_flags_are_all_in_the_man_page() {
  local man="$_HI_HOME/say-hi/docs/hi.1" out flags flag
  [ -f "$man" ] || return 1
  out="$(_hi_help_out --help)" || return 1
  _hi_read_lines flags < <(printf '%s\n' "$out" | grep -oE -- '\-\-[a-z][a-z-]+' | sort -u)
  [ "${#flags[@]}" -ge 4 ] || return 1
  for flag in -h "${flags[@]}"; do
    # the man page escapes every dash as \- for roff
    grep -q -- "${flag//-/\\\\-}" "$man" || return 1
  done
}

# ...and that check asks only whether a flag appears in the page at all, which
# is why the page's *grouping* drifted twice without failing anything. hi.1
# splits OPTIONS at "The following act on this machine": above it is what works
# anywhere, below it is what needs a part of the tree the payload does not
# carry, and that paragraph names the exceptions to itself. common/targets.sh
# makes the same split at runtime, so the two are one fact written twice - and
# they disagreed in both directions at once. --doctor was documented in the top
# group while the roster correctly withheld it in a session (scripts/doctor.sh
# is not in $_HI_PAYLOAD), and --packages-preview was documented in the bottom
# group while the roster correctly still offered it there (it falls back to the
# shipped common/header.sh instead of refusing).
function test_man_page_option_groups_match_the_roster() {
  local man="$_HI_HOME/say-hi/docs/hi.1" zones all session flag bad=0
  [ -f "$man" ] || return 1
  all="$(sh "$_HI_ROOT/common/targets.sh" flags)" || return 1
  session="$(_HI_REMOTE_SESSION=1 sh "$_HI_ROOT/common/targets.sh" flags)" || return 1
  # One "<flag> <zone>" line per mention. top = its own entry above the
  # paragraph, grouped = its own entry below it, named = spelled out inside the
  # paragraph as an exception. A flag can be both grouped and named, which is
  # how --test and --update read: in the group, and called out in the prose.
  zones="$(awk '
    function emit(line, zone,   f) {
      while (match(line, /\\-\\-[a-z]([a-z]|\\-)*/)) {
        f = substr(line, RSTART, RLENGTH)
        gsub(/\\/, "", f)
        print f, zone
        line = substr(line, RSTART + RLENGTH)
      }
    }
    BEGIN { zone = "top" }
    /^The following act on this machine/ { zone = "para" }
    zone == "para" && $0 == ".TP" { zone = "grouped" }
    /^Everything else is passed through/ { zone = "tail" }
    zone == "para" { emit($0, "named") }
    (zone == "top" || zone == "grouped") && prev == ".TP" && /^\.BR? / { emit($0, zone) }
    { prev = $0 }
  ' "$man")" || return 1
  # a scrape that found nothing would pass every case below as an empty loop
  [ -n "$zones" ] || return 1
  while read -r flag; do
    [ -n "$flag" ] || continue
    case $'\n'"$session"$'\n' in
    *$'\n'"$flag"$'\n'*)
      # works in a session, so the page must not file it under the group -
      # unless the group's own paragraph names it as the exception it is
      case $'\n'"$zones"$'\n' in
      *$'\n'"$flag top"$'\n'* | *$'\n'"$flag named"$'\n'*) ;;
      *)
        _hi_cecho "   $flag works in a session, but hi.1 files it under the needs-a-checkout group without naming it an exception" "$RED"
        bad=1
        ;;
      esac
      ;;
    *)
      # withheld in a session, so the page has to say so - below the paragraph
      case $'\n'"$zones"$'\n' in
      *$'\n'"$flag grouped"$'\n'*) ;;
      *)
        _hi_cecho "   $flag is withheld in a session, but hi.1 documents it as working anywhere" "$RED"
        bad=1
        ;;
      esac
      ;;
    esac
  done < <(printf '%s\n' "$all")
  [ "$bad" = 0 ]
}

# The ladders drift the same way the flags do - doctor.sh once still promised
# a stale list after the tree changed (the comment above $_HI_SHELL_LADDER
# tells it), and the man page repeated the trick with the session shells. Every
# shell either ladder can land you in has to be named in the page. The
# no-bash half reads the live variable; the session half is spelled out here
# because load.sh's default ranking is a literal inside _hi_session_shell -
# a stale copy of it fails this test the same way a stale man page would.
function test_shell_ladders_are_in_the_man_page() {
  local man="$_HI_HOME/say-hi/docs/hi.1" shell
  [ -f "$man" ] || return 1
  for shell in $_HI_SHELL_LADDER fish zsh bash; do
    # -w keeps "sh" from riding on "ssh"
    grep -Eqw -- "$shell" "$man" || return 1
  done
}

# The tree itself, spelled out here on purpose: hi.sh derives $_HI_SHELL_LADDER
# from core.sh's $_HI_SHELL_TREE, so a test written as that same expression
# would assert nothing. This is the intended order in one place, and both the
# tree and the cut have to match it. The ladder is the tree minus bash because
# a missing bash is the only thing that makes the ladder reachable at all.
function test_the_shell_tree_is_the_documented_order() {
  [ "$_HI_SHELL_TREE" = "fish zsh bash dash ash sh" ] || return 1
  [ "$_HI_SHELL_LADDER" = "fish zsh dash ash sh" ]
}

# hi's local sub-commands - `hi --install` and friends - are the case block at
# the foot of hi.sh, on the far side of the BASH_SOURCE hatch. Unlike every
# function above they cannot be reached by sourcing, so these cases run hi.sh
# as a process against two throwaway trees.
#
# _hi_subcmd_home builds the shape a *target* gets: common/, settings/,
# load.sh and hi.sh copied in, and deliberately no scripts/, no tests/ and
# no .git. That is the shape every one of these flags has to refuse by name,
# and it is the reason $_HI_NO_CHECKOUT exists.
#
# Copied and not symlinked, which is both cheaper to explain and truer: a real
# target unpacks the payload tar, so what it has are regular files. It also
# needs no symlink, which a filesystem may not offer (`_hi_capable` in
# tests/lib/fixtures.sh) - and these five cases have nothing to do with links.
function _hi_subcmd_home() {
  local home="$_HI_WORKDIR/$1" f
  mkdir -p "$home/say-hi"
  for f in common settings load.sh hi.sh; do
    cp -R "$_HI_ROOT/$f" "$home/say-hi/$f"
  done
  printf '%s' "$home"
}

# The same tree plus a stub for every script a flag reaches. Each stub prints
# its own name and its argv verbatim, which is what lets the cases below pin
# the mapping - `hi --configure` has to become install.sh --features-only, not
# just "some install.sh".
function _hi_subcmd_stubs() {
  local home stub dir
  home="$(_hi_subcmd_home subcmd-stubs)"
  mkdir -p "$home/say-hi/scripts" "$home/say-hi/tests"
  for stub in install:scripts/install.sh uninstall:scripts/uninstall.sh \
    color_preview:scripts/color_preview.sh doctor:scripts/doctor.sh \
    packages_preview:scripts/packages_preview.sh test_runner:tests/test_runner.sh; do
    dir="$home/say-hi/${stub#*:}"
    printf '#!/bin/sh\nprintf %s\nfor a in "$@"; do printf " %%s" "$a"; done\nprintf "\\n"\n' \
      "'STUB ${stub%%:*}'" >"$dir"
    chmod +x "$dir"
  done
  printf '%s' "$home"
}

function _hi_subcmd_run() {
  local home="$1"
  shift
  (_HI_HOME="$home" "$home/say-hi/hi.sh" "$@" 2>&1)
}

# every one of them names itself rather than dying on a missing path
function test_local_subcommands_refuse_without_the_checkout() {
  local home flag out
  home="$(_hi_subcmd_home subcmd-bare)"
  for flag in --install --uninstall --configure --check-configs --overlay-init \
    --color-preview --doctor --test; do
    out="$(_hi_subcmd_run "$home" "$flag")" && {
      _hi_cecho " | $flag exited 0 without a checkout" "$RED"
      return 1
    }
    [[ "$out" == *"hi $flag needs the full say-hi checkout"* ]] || {
      _hi_cecho " | $flag said: $out" "$RED"
      return 1
    }
  done
}

# --update is the one that cannot borrow that sentence: .git, not scripts/
function test_update_refuses_without_a_git_dir() {
  local home out
  home="$(_hi_subcmd_home subcmd-bare)"
  out="$(_hi_subcmd_run "$home" --update)" && return 1
  [[ "$out" == *"hi --update: no .git in"* ]]
}

# ...and with a .git it hands the rest of its argv to git pull, in this tree:
# a git shim first on the PATH sees exactly that
function test_update_hands_its_arguments_to_git_pull() {
  local dir out
  dir="$_HI_WORKDIR/updategit"
  mkdir -p "$dir"
  printf '#!/bin/sh\nprintf "GIT %%s\\n" "$*"\n' >"$dir/git"
  chmod +x "$dir/git"
  [ -d "$_HI_ROOT/.git" ] || return 0
  out="$(PATH="$dir:$PATH" "$_HI_ROOT/hi.sh" --update --ff-only 2>&1)" || return 1
  [[ "$out" == *"GIT -C $_HI_ROOT pull --ff-only"* ]]
}

# ...and --packages-preview is the one that does not refuse at all: the check
# itself ships in common/header.sh, so on a target it falls back to that
function test_packages_preview_falls_back_to_the_shipped_check() {
  local home out
  home="$(_hi_subcmd_home subcmd-bare)"
  out="$(_hi_subcmd_run "$home" --packages-preview)" || return 1
  [ -n "$out" ] && [[ "$out" != *"needs the full say-hi checkout"* ]]
}

# the mapping itself: which script, with which arguments
function test_local_subcommands_exec_the_right_script() {
  local home out spec flag want
  home="$(_hi_subcmd_stubs)"
  for spec in \
    '--install|STUB install' \
    '--uninstall|STUB install --uninstall' \
    '--configure|STUB install --features-only' \
    '--check-configs|STUB install --check-configs' \
    '--overlay-init|STUB install --overlay-init' \
    '--color-preview|STUB color_preview' \
    '--packages-preview|STUB packages_preview' \
    '--doctor|STUB doctor' \
    '--test|STUB test_runner'; do
    flag="${spec%%|*}"
    want="${spec#*|}"
    out="$(_hi_subcmd_run "$home" "$flag")" || return 1
    [ "$out" = "$want" ] || {
      _hi_cecho " | $flag ran '$out', wanted '$want'" "$RED"
      return 1
    }
  done
}

# a sub-command is still a command line: what follows the flag rides along
function test_local_subcommands_forward_extra_arguments() {
  local home out
  home="$(_hi_subcmd_stubs)"
  out="$(_hi_subcmd_run "$home" --doctor myhost)" || return 1
  [ "$out" = "STUB doctor myhost" ] || return 1
  out="$(_hi_subcmd_run "$home" --test --group fast)" || return 1
  [ "$out" = "STUB test_runner --group fast" ]
}

# the other half of the move: paths.sh must not grow them back. hi_info is the
# deliberate exception - it is an echo, not a script entry point, and the test
# harness probes for it (see _hi_probe_cmd in test_lib.sh).
function test_paths_defines_no_command_aliases() {
  local stray
  stray="$(grep -oE '^alias hi_[a-z_]+' "$_HI_ROOT/common/paths.sh" | grep -vx 'alias hi_info' || true)"
  [ -z "$stray" ] || {
    _hi_cecho " | paths.sh still defines: $stray" "$RED"
    return 1
  }
}

# _hi_record_recent: the client half of recent-targets-first (targets.sh's
# ranking is targets_test.sh's). The file is pointed into the workdir.
function test_record_recent_appends_a_line() {
  local f="$_HI_WORKDIR/recent.append"
  rm -f "$f"
  _HI_RECENT_FILE="$f" _hi_record_recent alpha
  _HI_RECENT_FILE="$f" _hi_record_recent beta
  [ "$(grep -c . "$f")" -eq 2 ] &&
    grep -qE $'^[0-9]+\talpha$' "$f" && grep -qE $'^[0-9]+\tbeta$' "$f"
}
# the promise the roadmap made: nothing about it reaches a target - a relay's
# hi, which is the same file running in a session, records nothing there
function test_record_recent_is_silent_in_a_session() {
  local f="$_HI_WORKDIR/recent.session"
  rm -f "$f"
  _HI_REMOTE_SESSION=1 _HI_RECENT_FILE="$f" _hi_record_recent alpha
  [ ! -e "$f" ]
}
function test_record_recent_is_silent_when_off() {
  local f="$_HI_WORKDIR/recent.off"
  rm -f "$f"
  _HI_RECENT=0 _HI_RECENT_FILE="$f" _hi_record_recent alpha
  [ ! -e "$f" ]
}
function test_record_recent_trims() {
  local f="$_HI_WORKDIR/recent.trim" i
  rm -f "$f"
  for i in $(seq 1 500); do printf '1\told-%s\n' "$i"; done >"$f"
  _HI_RECENT_FILE="$f" _hi_record_recent newest
  [ "$(grep -c . "$f")" -eq 300 ] && [ "$(tail -1 "$f" | cut -f2)" = newest ]
}

# _hi is the dispatch function itself: the missing-$_HI_ROOT exit, the
# PLAIN/arm 2x2 that picks which _say_hi* runs, and the record/report calls
# that follow depending on the exit status. It calls `exit` outright, so
# every case here redefines the four _say_hi* arms plus _hi_parse,
# _hi_select_arm, _hi_record_recent and _hi_report_failure to markers instead
# of the real thing, in a subshell so none of it leaks to the next case.
#
# _hi_dispatch_probe <plain> <arm> <status> - runs _hi with $PLAIN=<plain> and
# _hi_select_arm answering <arm>, the chosen _say_hi* returning <status>.
# Prints _hi's own exit code on one line, then every marker line the stubs
# wrote, in call order.
#
# chosen_arm, not arm: _hi itself declares `local ... arm`, and bash's
# function scoping is dynamic - a nested call to the redefined
# _hi_select_arm, made from inside _hi, would otherwise read _hi's own
# (still-empty) local instead of this one.
function _hi_dispatch_probe() {
  local plain="$1" chosen_arm="$2" status="$3" marker="$_HI_WORKDIR/dispatch-marker" ec
  : >"$marker"
  (
    function _hi_parse() { :; }
    function _hi_select_arm() { printf '%s' "$chosen_arm"; }
    function _say_hi() {
      printf 'say_hi\n' >>"$marker"
      return "$status"
    }
    function _say_hi_container() {
      printf 'say_hi_container:%s\n' "$1" >>"$marker"
      return "$status"
    }
    function _say_hi_plain() {
      printf 'say_hi_plain\n' >>"$marker"
      return "$status"
    }
    function _say_hi_container_plain() {
      printf 'say_hi_container_plain:%s\n' "$1" >>"$marker"
      return "$status"
    }
    function _hi_record_recent() {
      printf 'record_recent:%s\n' "${1:-}" >>"$marker"
    }
    function _hi_report_failure() {
      printf 'report_failure:%s:%s\n' "${1:-}" "${2:-}" >>"$marker"
    }
    PLAIN="$plain" DOMAIN=probehost
    _hi
  )
  ec=$?
  printf '%s\n' "$ec"
  cat "$marker"
}

function test_hi_exits_1_when_root_is_missing() {
  local out ec
  out="$(
    _HI_ROOT="$_HI_WORKDIR/no-such-root"
    _hi 2>&1
  )"
  ec=$?
  [ "$ec" -eq 1 ] && [[ "$out" == *"no such directory"* ]]
}

function test_hi_dispatch_plain0_no_arm_calls_say_hi() {
  local out
  out="$(_hi_dispatch_probe 0 "" 0)"
  [[ "$(printf '%s\n' "$out" | sed -n 2p)" == say_hi ]]
}

function test_hi_dispatch_plain0_with_arm_calls_say_hi_container() {
  local out
  out="$(_hi_dispatch_probe 0 docker 0)"
  [[ "$(printf '%s\n' "$out" | sed -n 2p)" == "say_hi_container:docker" ]]
}

function test_hi_dispatch_plain1_no_arm_calls_say_hi_plain() {
  local out
  out="$(_hi_dispatch_probe 1 "" 0)"
  [[ "$(printf '%s\n' "$out" | sed -n 2p)" == say_hi_plain ]]
}

function test_hi_dispatch_plain1_with_arm_calls_say_hi_container_plain() {
  local out
  out="$(_hi_dispatch_probe 1 docker 0)"
  [[ "$(printf '%s\n' "$out" | sed -n 2p)" == "say_hi_container_plain:docker" ]]
}

function test_hi_exit_code_is_the_arms() {
  local out
  out="$(_hi_dispatch_probe 0 "" 7)"
  [ "$(printf '%s\n' "$out" | sed -n 1p)" = 7 ]
}

# a typo or an unreachable host is not worth offering first next time
function test_hi_records_recent_only_on_success() {
  local out
  out="$(_hi_dispatch_probe 0 "" 0)"
  [[ "$out" == *"record_recent:probehost"* ]] && [[ "$out" != *report_failure* ]]
}

function test_hi_reports_failure_only_on_nonzero_with_arm_and_tmp() {
  local out
  out="$(_hi_dispatch_probe 0 docker 3)"
  [[ "$out" == *"report_failure:3:docker"* ]] && [[ "$out" != *record_recent* ]]
}

function run_hi_parse_tests() {
  _hi_workdir hiparsetest
  _hi_probe_shims "$_HI_WORKDIR/shims"
  _HI_SHIM_PATH="$_HI_WORKDIR/shims:$PATH"

  _hi_suite_begin

  _hi_h1 "Testing hi.sh: parsing and dispatch"

  _hi_h2 "Testing: _hi_parse (targets and flags)"
  _hi_check_eq "A bare target" "$(printf 'myhost\n\n')" _hi_parse_out myhost
  _hi_check_eq "Keeps valueless flags" "$(printf 'myhost\n\n-v\n')" _hi_parse_out -v myhost
  _hi_check_eq "Pairs a flag with its value" "$(printf 'myhost\n\n-p\n2222\n')" _hi_parse_out -p 2222 myhost
  # the regression this list exists for: -J takes a value, so without it in the
  # case arm "bastion" becomes DOMAIN and hi connects to the wrong machine
  _hi_check_eq "-J's value is not mistaken for the target" "$(printf 'myhost\n\n-J\nbastion\n')" _hi_parse_out -J bastion myhost
  _hi_check_eq "-B's value is not mistaken for the target" "$(printf 'myhost\n\n-B\neth0\n')" _hi_parse_out -B eth0 myhost
  _hi_check "Several flags before the target" test_parse_handles_several_flags_before_the_target
  _hi_check "'--' does not end option parsing" test_parse_dashdash_does_not_end_option_parsing

  _hi_h2 "Testing: _hi_parse (commands and errors)"
  _hi_check "Trailing words become a command" test_parse_turns_trailing_words_into_a_command
  _hi_check "A plain session has no command" test_parse_leaves_cmdarg_empty_for_a_plain_session
  _hi_check "Rejects a flag missing its value" test_parse_rejects_a_flag_missing_its_value
  _hi_check "Names the offending flag" test_parse_names_the_offending_flag

  _hi_h2 "Testing: bare hi picks a target"
  _hi_check "fzf when it is there" test_pick_uses_fzf_when_it_is_there
  _hi_check "sk when fzf is not" test_pick_falls_through_to_sk
  _hi_check "The tag is not part of the target" test_pick_returns_the_name_without_its_tag
  _hi_check "A numbered select when neither is" test_pick_falls_back_to_a_numbered_select
  _hi_check "The select menu is backend-tagged" test_select_menu_tags_each_row
  _hi_check "A dismissal is 1" test_pick_reports_a_dismissal_as_one
  _hi_check "An empty list is 2" test_pick_reports_an_empty_list_as_two
  _hi_check_capable pty "Bare hi takes the pick as its target" test_bare_hi_takes_a_target_from_the_picker
  _hi_check "No terminal, no picker" test_bare_hi_without_a_terminal_still_reaches_ssh
  _hi_check_capable pty "An ssh option with no target still reaches ssh" test_an_ssh_option_without_a_target_never_picks

  _hi_h2 "Testing: backend predicates"
  _hi_check "docker: running" test_is_docker_container_accepts_a_running_one
  _hi_check "docker: stopped" test_is_docker_container_rejects_a_stopped_one
  _hi_check "podman: running" test_is_podman_container_accepts_a_running_one
  _hi_check "nomad: running" test_is_nomad_alloc_accepts_a_running_one
  _hi_check "nomad: pending" test_is_nomad_alloc_rejects_a_pending_one
  _hi_check "kube: running" test_is_k8s_pod_accepts_a_running_one
  _hi_check "kube: pending" test_is_k8s_pod_rejects_a_pending_one
  _hi_check "All false with no CLI installed" test_predicates_are_false_without_their_cli

  _hi_h2 "Testing: _hi_resolve_backend"
  _hi_check "Picks the roster's first match" test_resolve_backend_picks_the_first_matching_row
  _hi_check "The roster decides, not the resolver" test_resolve_backend_follows_the_roster_order
  _hi_check "The header counts every backend the roster dispatches" test_header_probes_every_backend_in_the_roster
  _hi_check "Nothing for an unknown target" test_resolve_backend_prints_nothing_for_a_stranger
  _hi_check "Nothing with no backend CLI at all" test_resolve_backend_prints_nothing_without_any_cli

  _hi_h2 "Testing: backend override flags (--ssh, --docker, ...)"
  _hi_check "Every roster backend has a flag row" test_every_backend_has_a_flag_row
  _hi_check "_hi_backend_flag rejects a stranger" test_backend_flag_rejects_a_stranger
  _hi_check "Each flag sets BACKEND to its own name" test_parse_backend_flags_set_backend_for_every_name
  _hi_check "A backend flag never reaches SSHARGS" test_parse_backend_flag_does_not_reach_sshargs
  _hi_check "Two different backend flags refuse each other" test_parse_two_backend_flags_refuse_each_other
  _hi_check "Both conflicting flags are named" test_parse_names_both_conflicting_flags
  _hi_check "The same flag twice is not a conflict" test_parse_repeating_a_backend_flag_is_fine
  _hi_check "A backend flag after the target is ssh's, not hi's" test_parse_backend_flag_after_the_target_is_not_claimed
  _hi_check "--plain sets PLAIN, not SSHARGS" test_parse_plain_sets_plain_not_sshargs
  _hi_check "--plain combines with a backend flag" test_parse_plain_combines_with_a_backend_flag
  _hi_check "RAWCMD carries no \"; exit\" suffix" test_parse_rawcmd_has_no_exit_suffix
  _hi_check "select_arm: the flag wins over a real match" test_select_arm_backend_flag_wins_over_a_real_match
  _hi_check "select_arm: the flag names the arm with no probe" test_select_arm_backend_flag_names_the_arm_with_no_probe
  _hi_check "select_arm: unset falls back to resolution" test_select_arm_falls_back_to_resolution_when_backend_unset
  _hi_check "report_failure: silent once hi already said it" test_report_failure_is_silent_once_hi_already_said_it
  _hi_check "report_failure: silent for a non-255 ssh exit" test_report_failure_is_silent_for_a_non_255_ssh_exit
  _hi_check "report_failure: speaks on 255" test_report_failure_speaks_on_255
  _hi_check "report_failure: silent for a quiet container errlog" test_report_failure_is_silent_for_a_quiet_container_errlog
  _hi_check "report_failure: speaks with a filed container error" test_report_failure_speaks_with_a_filed_container_error
  _hi_check "report_failure: no \\r off a tty" test_report_failure_has_no_carriage_return_off_a_tty

  _hi_check "target/inner picks the container or task" test_container_cmds_pick_the_inner_unit
  _hi_check "no tty, no -t (hi <target> <cmd> | ...)" test_container_cmds_drop_the_tty_without_one
  _hi_check "namespace:pod and context:namespace:pod reach kubectl" test_kube_prefixes_become_kubectl_flags

  _hi_h2 "Testing: --plain"
  _hi_check "Container: attaches with no write, prefers bash" test_plain_container_attaches_with_no_write
  _hi_check "Container: falls back to the ladder without bash" test_plain_container_falls_back_to_the_ladder_without_bash
  _hi_check "Container: runs RAWCMD with -c" test_plain_container_runs_rawcmd_with_dash_c
  _hi_check "ssh: execs real ssh with RAWCMD" test_plain_ssh_execs_real_ssh_with_rawcmd
  _hi_check "ssh: no command means no trailing word" test_plain_ssh_with_no_command_passes_none

  _hi_h2 "Testing: _hi_record_recent"
  _hi_check "Appends a stamped line" test_record_recent_appends_a_line
  _hi_check "Writes nothing in a session" test_record_recent_is_silent_in_a_session
  _hi_check "Writes nothing when off" test_record_recent_is_silent_when_off
  _hi_check "Trims past 500 lines to 300" test_record_recent_trims

  _hi_h2 "Testing: _hi (the dispatch)"
  _hi_check "Exits 1 when \$_HI_ROOT is missing" test_hi_exits_1_when_root_is_missing
  _hi_check "PLAIN=0, no arm -> _say_hi" test_hi_dispatch_plain0_no_arm_calls_say_hi
  _hi_check "PLAIN=0, an arm -> _say_hi_container" test_hi_dispatch_plain0_with_arm_calls_say_hi_container
  _hi_check "PLAIN=1, no arm -> _say_hi_plain" test_hi_dispatch_plain1_no_arm_calls_say_hi_plain
  _hi_check "PLAIN=1, an arm -> _say_hi_container_plain" test_hi_dispatch_plain1_with_arm_calls_say_hi_container_plain
  _hi_check "Exits with the arm's own status" test_hi_exit_code_is_the_arms
  _hi_check "Records recent only on success" test_hi_records_recent_only_on_success
  _hi_check "Reports failure only on non-zero, with arm+tmp" test_hi_reports_failure_only_on_nonzero_with_arm_and_tmp

  _hi_h2 "Testing: hi's local sub-commands"
  _hi_check "Each refuses by name without the checkout" test_local_subcommands_refuse_without_the_checkout
  _hi_check "--update refuses without a .git" test_update_refuses_without_a_git_dir
  _hi_check "--update hands its arguments to git pull" test_update_hands_its_arguments_to_git_pull
  _hi_check "--packages-preview falls back instead" test_packages_preview_falls_back_to_the_shipped_check
  _hi_check "Each execs the right script and args" test_local_subcommands_exec_the_right_script
  _hi_check "Extra arguments ride along" test_local_subcommands_forward_extra_arguments
  _hi_check "paths.sh defines no command aliases" test_paths_defines_no_command_aliases

  _hi_h2 "Testing: hi --help"
  _hi_check "--help prints the usage line" test_help_long_flag_prints_usage
  _hi_check_eq "-h is the same text" "$(_hi_help_out --help)" _hi_help_out -h
  _hi_check "Lists hi's flags and the target ladder" test_help_lists_hi_s_own_flags
  _hi_check "Every flag is in the man page" test_help_flags_are_all_in_the_man_page
  _hi_check "The man page groups them as the roster does" test_man_page_option_groups_match_the_roster
  _hi_check "Both shell ladders are in the man page" test_shell_ladders_are_in_the_man_page
  _hi_check "The ladder is the shell tree without bash" test_the_shell_tree_is_the_documented_order
  _hi_suite_end "hi.sh (parsing and dispatch)"
}

run_hi_parse_tests
