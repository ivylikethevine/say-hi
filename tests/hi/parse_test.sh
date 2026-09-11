#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Unit tests for hi.sh, the client entry point: argument parsing, backend
# dispatch, `--help`, and the local sub-commands - everything that decides what
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

# ...dashed or not: the target ends the options, and `hi host -la` is ssh's
# `ssh host -la` - the command's word, never an ssh argument
function test_parse_dashed_word_after_the_target_is_the_command() {
  local out
  out="$(_hi_parse_out myhost -la)"
  [[ "$out" == myhost*"-la;"*exit* ]] && [ "$(printf '%s\n' "$out" | wc -l)" -eq 2 ]
}

function test_parse_leaves_cmdarg_empty_for_a_plain_session() {
  [ "$(_hi_parse_out myhost | sed -n 2p)" = "" ]
}

# "--" is ssh's own option terminator and rides along as one more ssh
# argument: it does not end option parsing, and the word after it is still
# read as a flag, not a target. With no DOMAIN set and SSHARGS non-empty,
# _hi_parse skips the help and runs a real ssh, then exits with ssh's own
# status - it never returns to _hi_parse_out, so this shims ssh to log its
# argv and exit 3, and asserts both.
function test_parse_dashdash_does_not_end_option_parsing() {
  local bin="$_HI_WORKDIR/dashdash.bin" log="$_HI_WORKDIR/dashdash.log" rc=0
  mkdir -p "$bin"
  cat >"$bin/ssh" <<SHIM
#!/bin/sh
printf '%s\n' "\$*" >"$log"
exit 3
SHIM
  chmod +x "$bin/ssh"
  (PATH="$bin:$PATH" _hi_parse -- -oddtarget >/dev/null 2>&1) || rc=$?
  [ "$rc" -eq 3 ] || return 1
  [ "$(cat "$log")" = "-- -oddtarget" ]
}

# ssh takes no option that starts with two dashes, so every --word is hi's:
# a stranger is hi's error and exit 1, never ssh's usage message
function test_parse_unknown_double_dash_word_is_his_error() {
  local out rc=0
  out="$( (_hi_parse --docter myhost 2>&1 >/dev/null) )" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"hi: unknown option --docter"* ]]
}

# a local command is dispatched on the first word alone; behind an ssh
# option it is named as out of place, not as a stranger
function test_parse_local_command_behind_an_option_is_named() {
  local out rc=0
  out="$( (_hi_parse -v --doctor myhost 2>&1 >/dev/null) )" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--doctor goes first"* ]]
}

# the target ends the options: a dashed word after it is the remote
# command's, the way `ssh host ls -la` reads - and one of hi's own flags
# there is refused by name rather than run on the far end
function test_parse_own_flag_after_the_target_is_refused() {
  local out rc=0
  out="$( (_hi_parse myhost --use docker 2>&1 >/dev/null) )" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--use goes before the target"* ]]
}

# hi's own flags with nothing to connect to:
# hi's error, never ssh's usage message (ssh saw none of them)
function test_parse_own_flag_without_a_target_is_his_error() {
  local out rc=0
  out="$( (_hi_parse --plain </dev/null 2>&1 >/dev/null) )" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"no target to connect to"* ]] || return 1
  rc=0
  out="$( (_hi_parse --use docker </dev/null 2>&1 >/dev/null) )" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"no target to connect to"* ]]
}

# a bare flag given a joined value is told so, not told to go first
function test_parse_bare_flag_with_a_value_is_refused() {
  local out rc=0
  out="$( (_hi_parse --plain=1 myhost 2>&1 >/dev/null) )" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--plain takes no value"* ]]
}

# ...and which flags are bare is common/flags' empty <argument> column plus
# -h/-V, not a list of hi.sh's own: every such row is refused a value
function test_parse_every_bare_flag_refuses_a_value() {
  local flag out rc
  for flag in $(sed -n 's/^\(--[a-z-]*\)||.*/\1/p' "$_HI_ROOT/common/flags") -h -V; do
    rc=0
    out="$( (_hi_parse "$flag=1" myhost 2>&1 >/dev/null) )" || rc=$?
    [ "$rc" -eq 1 ] && [[ "$out" == *"$flag takes no value"* ]] || {
      _hi_cecho " | $flag=1: exit $rc, [$out]" "$RED"
      return 1
    }
  done
}

# -h behind an ssh option is still hi's question, not ssh's usage
function test_parse_help_is_honoured_behind_an_ssh_option() {
  local out
  out="$(_hi_help_out -o StrictHostKeyChecking=no -h)" || return 1
  [[ "$out" == "Usage: hi "* && "$out" != *"ssh was called"* ]]
}

# the bare words help and version are targets like any other: -h and -V are
# the only spellings hi claims, so a host called help needs no escaping
function test_bare_help_and_version_words_are_targets() {
  [ "$(_hi_parse_out help | sed -n 1p)" = help ] &&
    [ "$(_hi_parse_out version | sed -n 1p)" = version ] &&
    [ "$(_hi_parse_out -4 help | sed -n 1p)" = help ]
}

# _hi_is_ssh_host reads literal Host entries only: a `Host *` block claims
# nothing, so a container of any name still reaches its own backend. The
# tag walker itself keeps matching wildcards (core_test pins that), since
# a `# Tags:` comment over `Host prod-*` is how a whole fleet gets a color.
function _hi_wild_ssh_config() {
  local f="$_HI_WORKDIR/wild_ssh_config"
  [ -f "$f" ] || printf 'Host *\n    ForwardAgent no\n\nHost literal\n    HostName 1.2.3.4\n' >"$f"
  printf '%s' "$f"
}

function test_is_ssh_host_ignores_a_wildcard_block() {
  local cfg
  cfg="$(_hi_wild_ssh_config)"
  _HI_SSH_CONFIG="$cfg" _hi_is_ssh_host literal || return 1
  ! _HI_SSH_CONFIG="$cfg" _hi_is_ssh_host yes
}

function test_select_arm_wildcard_host_does_not_shadow_a_container() {
  local DOMAIN=yes BACKEND=
  [ "$(_HI_SSH_CONFIG="$(_hi_wild_ssh_config)" PATH="$_HI_SHIM_PATH" _hi_select_arm)" = docker ]
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

# Bare `hi` - no target, no ssh option - prints the help and exits 0, terminal
# or not: help is safe to print from a script, and nothing in that arm can wait
# on input. Run in a child bash because the arm exits.
function _hi_bare_hi() {
  bash -c '
    source "$_HI_LAUNCHER"
    _hi_parse' </dev/null 2>/dev/null
}

function test_bare_hi_prints_help() {
  local out rc=0
  out="$(_hi_bare_hi)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"${_HI_USAGE%%$'\n'*}"* ]] &&
    [[ "$out" == *"hi's own options"* ]]
}

# ...and the same under a pty, terminal or not
function test_bare_hi_prints_help_on_a_terminal_too() {
  local out rc=0
  out="$("${_HI_PTY_FORCED[@]}" bash -c '
      source "$_HI_LAUNCHER"
      _hi_parse' 2>/dev/null)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"hi's own options"* ]]
}

# an ssh option with no host is ssh's error to report, not hi's help to print:
# `hi -V` has to stay `ssh -V`. The stub prints its argv, so the case can say
# the flag arrived.
function test_an_ssh_option_without_a_target_reaches_ssh() {
  local dir out rc=0
  dir="$_HI_WORKDIR/sshstub"
  mkdir -p "$dir"
  printf '%s\n' '#!/bin/sh' 'echo "ssh-stub: $*"' >"$dir/ssh"
  chmod +x "$dir/ssh"
  out="$(PATH="$dir:$(_hi_real_path sshbare bash sh sed cat)" bash -c '
    source "$_HI_LAUNCHER"
    _hi_parse -4' </dev/null 2>&1)" || rc=$?
  [[ "$out" == *"ssh-stub: -4"* ]] && [[ "$out" != *"hi's own options"* ]]
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

# The predicates run together, so the guarantee worth pinning is that the
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
    # kube and nomad are probed by their own CLI's name. Every docker-compatible
    # family row comes off core.sh's $_HI_CONTAINER_CLIS, which hi.sh's roster
    # and header.sh's probe fan-out both read - so this checks that the row's
    # name is a member of that one list, and that _hi_probe_launch reads it
    # rather than spelling its own - GLOSSARY: HI.51.
    case "$name" in
    kube) [[ "$launch" == *kubectl* || "$launch" == *kube* ]] || return 1 ;;
    nomad) [[ "$launch" == *nomad* ]] || return 1 ;;
    *)
      case " $_HI_CONTAINER_CLIS " in
      *" $name "*) [[ "$launch" == *'_HI_CONTAINER_CLIS'* ]] || return 1 ;;
      *) return 1 ;;
      esac
      ;;
    esac
  done
}

# the roster is the whole docker-compatible family and nothing in the
# environment edits it: every member always has a row to resolve through, and
# a stale _HI_CONTAINER_CLIS from an older install changes nothing
function test_backend_roster_is_the_whole_family() {
  local names
  # sourced in a child bash with $0 left as "bash", so hi.sh's
  # `[[ BASH_SOURCE == $0 ]]` hatch reads it as a library, not a run
  names="$(_HI_CONTAINER_CLIS=nerdctl bash -c 'source "$1" >/dev/null 2>&1; printf "%s\n" "${_HI_BACKENDS[@]%%|*}"' bash "$_HI_LAUNCHER")"
  [ "$names" = "$(printf 'docker\npodman\nnerdctl\nfinch\nnomad\nkube\n')" ]
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

# --use is the one way to force an arm: every roster name and ssh resolve
# through it, and common/flags carries no per-backend row that could drift
# from the roster (GLOSSARY: HI.51).
#
# SC2031: the roster swap above (test_resolve_backend_follows_the_roster_order)
# happens inside a $( ) and never reaches here; this reads the file-scope table
function test_every_arm_resolves_through_use() {
  local name
  # shellcheck disable=SC2031
  for name in ssh "${_HI_BACKENDS[@]%%|*}"; do
    [ "$(_hi_use_backend "$name" 2>/dev/null)" = "$name" ] || return 1
    ! grep -q "^--$name|" "$_HI_ROOT/common/flags" || return 1
  done
  grep -q '^--use|' "$_HI_ROOT/common/flags"
}

function test_use_backend_rejects_a_stranger() {
  ! _hi_use_backend frobnicate >/dev/null 2>&1
}

# --use=<backend> is the same flag with its word joined, the spelling
# install.sh's --prefix and --preset already take, and must not fall through
# to ssh as an unknown option
function test_parse_use_takes_the_equals_spelling() {
  [ "$(_hi_backend_parse_out --use=nerdctl myhost)" = "$(printf 'myhost\nnerdctl\n')" ] &&
    [ "$(_hi_parse_out --use=podman myhost)" = "$(printf 'myhost\n\n')" ]
}

function test_parse_use_equals_rejects_a_stranger() {
  local rc=0
  (_hi_parse --use=frobnicate myhost >/dev/null 2>&1) || rc=$?
  [ "$rc" -eq 1 ]
}

function test_parse_use_rejects_a_stranger() {
  local rc=0 out
  out="$( (_hi_parse --use frobnicate myhost 2>&1 >/dev/null) || true)"
  (_hi_parse --use frobnicate myhost >/dev/null 2>&1) || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--use"*ssh*docker*kube* ]]
}

# --use reaches every arm, not only the family: ssh (the empty arm) and the
# orchestrators too, the same values their shorthand flags set
function test_parse_use_names_every_arm() {
  local name
  for name in ssh docker podman nomad kube; do
    [ "$(_hi_backend_parse_out --use "$name" myhost)" = "$(printf 'myhost\n%s\n' "$name")" ] || return 1
  done
}

function test_parse_use_without_a_word_exits_one() {
  local rc=0
  (_hi_parse --use >/dev/null 2>&1) || rc=$?
  [ "$rc" -eq 1 ]
}

# the same arm twice is no conflict; two different arms are one, and the
# message names both
function test_parse_use_twice_agrees_or_refuses() {
  local rc=0 out
  [ "$(_hi_backend_parse_out --use docker --use docker myhost)" = "$(printf 'myhost\ndocker\n')" ] || return 1
  (_hi_parse --use podman --use docker myhost >/dev/null 2>&1) || rc=$?
  [ "$rc" -eq 1 ] || return 1
  out="$( (_hi_parse --use docker --use ssh myhost 2>&1 >/dev/null) || true)"
  [[ "$out" == *"--use ssh"*"--use docker"* ]]
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

function _hi_plain_parse_out() {
  _hi_var_parse_out PLAIN 0 "$@"
}

function test_parse_plain_sets_plain_not_sshargs() {
  [ "$(_hi_plain_parse_out --plain myhost)" = "$(printf 'myhost\n1\n')" ] &&
    [ "$(_hi_parse_out --plain myhost)" = "$(printf 'myhost\n\n')" ]
}

# combines freely with --use - orthogonal, checked in either order
function test_parse_plain_combines_with_use() {
  [ "$(_hi_plain_parse_out --plain --use docker myhost)" = "$(printf 'myhost\n1\n')" ] &&
    [ "$(_hi_backend_parse_out --use docker --plain myhost)" = "$(printf 'myhost\ndocker\n')" ]
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

# The alternate-screen exit is the one mode byte a terminal still on its
# normal screen answers with a cursor move (Konsole restores from a slot
# nothing saved, i.e. home), so it rides between a DECSC and a DECRC and the
# whole string is inert on a terminal that never left the normal screen.
# GLOSSARY: HI.53
function test_reset_terminal_wraps_the_alt_screen_exit_in_decsc_decrc() {
  local out
  out="$(_HI_DISABLE_MARKS=1 _hi_reset_terminal 255 2>/dev/null)"
  [[ "$out" == *$'\e7\e[?1049l\e8'* ]]
}

# the OSC 133 "command done" carries the status, so a Konsole left mid-command
# by a drop stops reading the arrow keys as an edit of the last one
function test_reset_terminal_closes_the_prompt_mark_with_the_status() {
  local out
  out="$(_hi_reset_terminal 130 2>/dev/null)"
  [[ "$out" == *$'\e]133;D;130\a'* ]]
}

function test_reset_terminal_omits_the_prompt_mark_when_marks_are_off() {
  local out
  out="$(_HI_DISABLE_MARKS=1 _hi_reset_terminal 130 2>/dev/null)"
  [[ "$out" != *'133;D'* ]]
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

# _hi_attach_is <tty> <backend> <domain> <want-glob> - run _hi_container_cmds
# for <backend> against <domain> and match the attach line against <want-glob>
# (a leading ! inverts the match). The tty decision is `[ -t 0 ]` in
# _hi_container_cmds itself and a suite has no tty of its own, so the command
# runs in a child bash: under $_HI_PTY_FORCED for the tty arm, on /dev/null
# for the other. The child prints the attach and cp lines; _HI_ATTACH_CP
# keeps the cp line for a case that wants it after its last run.
_HI_ATTACH_CP=""
# _hi_container_child <tty:1|0> <backend> <domain> - the attach line on stdout
function _hi_container_child() {
  local tty="$1" backend="$2" domain="$3" out
  local -a wrap=()
  [ "$tty" = 1 ] && wrap=("${_HI_PTY_FORCED[@]}")
  out="$(
    ${wrap[@]+"${wrap[@]}"} bash -c '
      source "$_HI_LAUNCHER"
      DOMAIN="$1"
      _hi_container_cmds "$2"
      printf "ATTACH=%s\nCP=%s\n" "${attach[*]}" "${cp[*]}"' _ "$domain" "$backend" \
      </dev/null 2>/dev/null | tr -d '\r'
  )"
  _HI_ATTACH_CP="$(printf '%s\n' "$out" | sed -n 's/^CP=//p')"
  printf '%s\n' "$out" | sed -n 's/^ATTACH=//p'
}

function _hi_attach_is() {
  local want="$4" negate=0 why="want" attach
  case "$want" in !*)
    negate=1
    why="did not want"
    want="${want#!}"
    ;;
  esac
  attach="$(_hi_container_child "$1" "$2" "$3")"
  # SC2254: the unquoted expansion is the point - $want is a glob
  # shellcheck disable=SC2254
  case "$attach" in
  $want) [ "$negate" -eq 0 ] && return 0 ;;
  *) [ "$negate" -eq 1 ] && return 0 ;;
  esac
  _hi_cecho " | $2 $3: attach was '$attach', $why '$want'" "$RED"
  return 1
}

# `pod/container` and `alloc/task`: one spelling for both, because a task and a
# container are the same idea. The plain form has to stay byte-identical - this
# syntax is additive or it breaks every existing target.
function test_container_cmds_pick_the_inner_unit() {
  _hi_attach_is 1 kube mypod '!* -c *' || return 1
  _hi_attach_is 1 kube mypod/sidecar '*exec -it mypod -c sidecar --' || return 1
  _hi_attach_is 1 nomad 685afd67/worker '*-task worker*685afd67' || return 1
  # docker has no inner unit and `/` is legal in a container name, so it is
  # taken whole - splitting one would break a real target
  _hi_attach_is 1 docker some/name '*exec -it some/name'
}

# The other arm of that probe, which is the one `hi <target> <cmd> | ...` takes:
# `docker exec -it` does not fall back to a pipe when stdin is not a terminal,
# it refuses ("cannot attach stdin to a TTY-enabled container"), so the command
# form failed at the transport before the command ran. Every container backend
# has to drop the `-t` and keep the `-i`; nomad spells both out either way,
# because its own stdin-is-a-tty guess hangs the exec on a wrapped pty.
function test_container_cmds_drop_the_tty_without_one() {
  _hi_attach_is 0 kube mypod '*exec -i mypod --' || return 1
  _hi_attach_is 0 docker somebox '*exec -i somebox' || return 1
  _hi_attach_is 0 nomad 685afd67 '*-i=true -t=false*' || return 1

  # ...and the copy stream never wanted a tty in the first place, either way.
  # Matched on the *enabled* spellings, not a bare "-t": nomad's cp line says
  # `-t=false` on purpose, and a glob for "-t" calls that a tty.
  case "$_HI_ATTACH_CP" in
  *"-it"* | *"-t=true"*)
    _hi_cecho " | the cp stream grew a tty: '$_HI_ATTACH_CP'" "$RED"
    return 1
    ;;
  esac
  return 0
}

# The kube prefixes: `namespace:pod` and `context:namespace:pod`, with or
# without a `/container`, each landing as kubectl's own flags ahead of `exec`.
function test_kube_prefixes_become_kubectl_flags() {
  _hi_attach_is 1 kube staging:web \
    'kubectl --namespace staging exec -it web --' || return 1
  _hi_attach_is 1 kube prod:staging:web/sidecar \
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
    DOMAIN=myhost SSHARGS=() RAWCMD="echo hi"
    PATH="$dir:$PATH" _say_hi_plain </dev/null
  )"
  [[ "$out" == "SSH:myhost echo hi" ]]
}

function test_plain_ssh_with_no_command_passes_none() {
  # the same argv-echoing shim, written by the RAWCMD case above - the two
  # run in registration order
  local dir="$_HI_WORKDIR/plainssh"
  local out
  out="$(
    DOMAIN=myhost SSHARGS=()
    unset RAWCMD
    PATH="$dir:$PATH" _say_hi_plain </dev/null
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

# -V is hi's version, not ssh's: the one short option claimed beside -h
function test_version_short_flag_is_hi_s_own() {
  local short long
  short="$(_hi_help_out -V)" || return 1
  long="$(_hi_help_out --version)" || return 1
  [ -n "$short" ] && [ "$short" = "$long" ] && [[ "$short" != OpenSSH* ]]
}

# the version line also says which kind of tree answered, and where - the
# next thing a bug report asks; this tree has a .git, so it is a checkout
function test_version_line_names_the_tree() {
  local out
  out="$(_hi_help_out --version)" || return 1
  [[ "$out" == *" (checkout at $_HI_ROOT)" ]]
}

# --help and --version take nothing after them, the short forms alike; the
# stray word is named
function test_help_and_version_refuse_a_trailing_word() {
  local spec out rc
  for spec in '--help extra' '-h extra' '--version extra' '-V extra'; do
    rc=0
    # shellcheck disable=SC2086 # the spec is two words on purpose
    out="$(_hi_help_out $spec)" || rc=$?
    [ "$rc" -eq 1 ] && [[ "$out" == *"${spec%% *} takes no arguments (got: ${spec#* })"* ]] || {
      _hi_cecho " | hi $spec: rc $rc, said: $out" "$RED"
      return 1
    }
  done
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

# Every `--word` a stretch of roff names, unescaped (`\-\-dry\-run` is
# --dry-run) and one per line; the font escapes and brackets around them are
# what the [a-z-] class stops at. Used on the page's headings and synopsis
# lines below, where every long option is hi's or one of a local command's
# own switches.
function _hi_roff_switches() {
  printf '%s\n' "$1" | sed 's/\\-/-/g' | grep -oE -- '--[a-z][a-z-]*' | sort -u
}

# The `--switches` common/flags' <argument> column names for one flag - the
# sub-switches a local command takes (`--doctor` takes --json and --use,
# `--install` takes --yes, --link, --preset, and --dry-run). Empty for a flag
# whose argument is a bare positional (`--use <backend>`, `--update [<tag>]`
# has --dry-run beside it).
function _hi_flag_switches() {
  local row arg
  row="$(grep -- "^$1|" "$_HI_ROOT/common/flags")" || return 1
  arg="$(printf '%s\n' "$row" | cut -d'|' -f2)"
  printf '%s\n' "$arg" | grep -oE -- '--[a-z][a-z-]*' | sort -u
}

# The local commands: every common/flags row whose <needs> column is not `-`,
# the ones that want scripts/ or .git and so have a synopsis line and an
# OPTIONS heading of their own with sub-switches after the name.
function _hi_local_flags() {
  grep -vE '^(#|$)' "$_HI_ROOT/common/flags" | awk -F'|' '$3 != "-" { print $1 }'
}

# ...and the check above is one-way: a flag --help knows has to be in the
# page, but a `--word` the page invents is never asked about, and the page
# said `--used` where --help said --use without anything noticing, because
# the grep there is a substring match. The reverse: every long option the
# SYNOPSIS (`.RB [ \-\-yes ]`, `.B hi \-\-doctor`) or an OPTIONS heading
# (`.B \-\-install \fR[\fB\-\-yes\fR] ...`, the line after a `.TP`) names has
# to be one of hi's own flags, one of the sub-switches common/flags'
# <argument> column gives a local command, or --prefix - scripts/install.sh's
# packaging switch, which the page describes in prose under --install and
# which is deliberately not a row, since a user never types it. The match is
# on the whole word, so --used cannot ride on --use.
function test_man_page_options_are_all_hi_s() {
  local man="$_HI_HOME/say-hi/docs/hi.1" text known flag name bad=0
  [ -f "$man" ] || return 1
  # common/flags' own columns rather than the live roster, which withholds
  # --update on a checkout without .git and would report the page for it
  known="$(grep -vE '^(#|$)' "$_HI_ROOT/common/flags" | cut -d'|' -f1,2 |
    grep -oE -- '--[a-z][a-z-]*')"$'\n'"--prefix"
  [ -n "$known" ] || return 1
  # the synopsis lines, and the OPTIONS headings (the `.B`/`.BR` line that
  # follows a `.TP`), nothing else - the prose names ssh's and kubectl's
  # options too, and those are not hi's to keep
  text="$(awk '
    /^\.SH / { syn = ($0 == ".SH SYNOPSIS"); opt = ($0 == ".SH OPTIONS") }
    syn { print }
    opt && prev == ".TP" && /^\.BR? / { print }
    { prev = $0 }
  ' "$man")"
  [ -n "$text" ] || return 1
  # a scrape that found no option at all would pass as an empty loop
  name="$(_hi_roff_switches "$text")"
  [ -n "$name" ] || return 1
  while IFS= read -r flag; do
    [ -n "$flag" ] || continue
    case $'\n'"$known"$'\n' in *$'\n'"$flag"$'\n'*) continue ;; esac
    _hi_cecho "   hi.1 names $flag in its synopsis or an OPTIONS heading, and neither hi nor common/flags knows it" "$RED"
    bad=1
  done <<<"$name"
  [ "$bad" = 0 ]
}

# The synopsis check above stops at the first `.br`, which leaves every local
# command's own form - `hi --install [--yes] [--link ...] ...` - unread. Each
# of those is common/flags' <argument> column written a second time, free to
# drift from it. Every local command has to have a form, and each form has to
# name exactly the switches its column does - as a set, since the page may
# order them for reading; `--link " " {none|user|system}` counts as --link.
function test_local_synopsis_forms_match_common_flags() {
  local man="$_HI_HOME/say-hi/docs/hi.1" flag block page want bad=0
  [ -f "$man" ] || return 1
  while IFS= read -r flag; do
    [ -n "$flag" ] || continue
    # the form is `.B hi \-\-<flag>` up to the next `.br`
    block="$(awk -v head=".B hi ${flag//-/\\\\-}" '
      /^\.SH SYNOPSIS/ { syn = 1; next }
      /^\.SH / { syn = 0 }
      syn && $0 == head { on = 1; next }
      on && /^\.br/ { exit }
      on { print }
    ' "$man")"
    if [ -z "$block" ] && ! grep -qF -- ".B hi ${flag//-/\\-}" "$man"; then
      _hi_cecho "   $flag has no synopsis form of its own in hi.1" "$RED"
      bad=1
      continue
    fi
    page="$(_hi_roff_switches "$block")"
    want="$(_hi_flag_switches "$flag")" || return 1
    [ "$page" = "$want" ] || {
      _hi_cecho "   $flag: hi.1's synopsis says '${page//$'\n'/ }', common/flags says '${want//$'\n'/ }'" "$RED"
      bad=1
    }
  done < <(_hi_local_flags)
  [ "$bad" = 0 ]
}

# ...and the OPTIONS heading for each is the same column a third time
# (`.B \-\-configure \fR[\fB\-\-preset\fR \fIname\fR] [\fB\-\-dry\-run\fR]`),
# held to the same set. The heading is the line after the `.TP` that starts
# with the flag's own name; the name itself is dropped before comparing.
function test_local_option_headings_match_common_flags() {
  local man="$_HI_HOME/say-hi/docs/hi.1" flag head page want bad=0
  [ -f "$man" ] || return 1
  while IFS= read -r flag; do
    [ -n "$flag" ] || continue
    head="$(awk -v name="${flag//-/\\\\-}" '
      /^\.SH / { opt = ($0 == ".SH OPTIONS") }
      opt && prev == ".TP" && index($0, ".B " name) == 1 { print; exit }
      { prev = $0 }
    ' "$man")"
    if [ -z "$head" ]; then
      _hi_cecho "   $flag has no OPTIONS entry of its own in hi.1" "$RED"
      bad=1
      continue
    fi
    page="$(_hi_roff_switches "$head" | grep -vx -- "$flag")"
    want="$(_hi_flag_switches "$flag")" || return 1
    [ "$page" = "$want" ] || {
      _hi_cecho "   $flag: hi.1's OPTIONS heading says '${page//$'\n'/ }', common/flags says '${want//$'\n'/ }'" "$RED"
      bad=1
    }
  done < <(_hi_local_flags)
  [ "$bad" = 0 ]
}

# The synopsis is one sentence written twice - $_HI_USAGE and the page's
# first .SH SYNOPSIS line - and this is the check the comment above
# _HI_USAGE promises. The roff is flattened: the request names, font
# escapes, and quotes dropped, \- unescaped, and every space removed on both
# sides (roff joins .RI/.RB arguments without them), as are --help's angle
# brackets (the page sets those names in italics instead).
function test_usage_line_matches_the_man_page_synopsis() {
  local man="$_HI_HOME/say-hi/docs/hi.1" page help
  page="$(awk '
    /^\.SH SYNOPSIS/ { on = 1; next }
    on && /^\.br/ { exit }
    on {
      sub(/^\.[A-Z]+ /, "")
      gsub(/\\f[IRB]/, ""); gsub(/"/, ""); gsub(/\\-/, "-"); gsub(/[ \t]/, "")
      printf "%s", $0
    }' "$man")"
  help="${_HI_USAGE#Usage: }"
  help="${help//[<> ]/}"
  help="${help//$'\n'/}"
  [ "$page" = "$help" ] || {
    _hi_cecho "   --help: $help" "$RED"
    _hi_cecho "   hi.1:   $page" "$RED"
    return 1
  }
}

# _hi_flag_help wraps a wide label onto its own line so the block fits 80
# columns; a help clause in common/flags is the other way to overflow, and
# nothing wrapped those. Every line of --help is held to the width.
function test_help_fits_eighty_columns() {
  local out wide
  out="$(_hi_help_out --help)" || return 1
  wide="$(printf '%s\n' "$out" | awk 'length > 80')"
  [ -z "$wide" ] || {
    _hi_cecho "   over 80 columns: $wide" "$RED"
    return 1
  }
}

# ...and that check asks only whether a flag appears in the page at all, so
# the page's *grouping* could drift without failing anything. hi.1
# splits OPTIONS at "The local commands act on this machine": above it is what works
# anywhere, below it is what needs a part of the tree the payload does not
# carry, and that paragraph names the exceptions to itself. common/targets.sh
# makes the same split at runtime, so the two are one fact written twice.
function test_man_page_option_groups_match_the_roster() {
  local man="$_HI_HOME/say-hi/docs/hi.1" zones all session flag bad=0
  [ -f "$man" ] || return 1
  all="$(sh "$_HI_ROOT/common/targets.sh" flags | cut -f1)" || return 1
  session="$(_HI_REMOTE_SESSION=1 sh "$_HI_ROOT/common/targets.sh" flags | cut -f1)" || return 1
  # One "<flag> <zone>" line per mention. top = its own entry above the
  # paragraph, grouped = its own entry below it, named = spelled out inside the
  # paragraph as an exception. A flag can be both grouped and named, which is
  # how --update reads: in the group, and called out in the prose.
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
    /^The local commands act on this machine/ { zone = "para" }
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
# tests/lib/fixtures.sh's _hi_scratch_tree builds the shape a *target* gets:
# common/, settings/, load.sh, and hi.sh copied in, and deliberately no
# scripts/, no tests/, and no .git. That is the shape every one of these
# flags has to refuse by name, and it is the reason $_HI_NO_CHECKOUT exists.
# _hi_subcmd_run (same file) runs hi.sh as a process against one.
#
# Copied and not symlinked, which is both cheaper to explain and truer: a real
# target unpacks the payload tar, so what it has are regular files. It also
# needs no symlink, which a filesystem may not offer (`_hi_capable` in
# tests/lib/fixtures.sh) - and these five cases have nothing to do with links.

# The same tree plus a stub for every script a flag reaches. Each stub prints
# its own name and its argv verbatim, which is what lets the cases below pin
# the mapping - `hi --configure` has to become install.sh --configure, not
# just "some install.sh".
function _hi_subcmd_stubs() {
  local home stub dir
  home="$(_hi_scratch_tree subcmd-stubs common settings load.sh hi.sh)"
  mkdir -p "$home/say-hi/scripts" "$home/say-hi/tests"
  for stub in install:scripts/install.sh preview:scripts/preview.sh \
    doctor:scripts/doctor.sh; do
    dir="$home/say-hi/${stub#*:}"
    printf '#!/bin/sh\nprintf %s\nfor a in "$@"; do printf " %%s" "$a"; done\nprintf "\\n"\n' \
      "'STUB ${stub%%:*}'" >"$dir"
    chmod +x "$dir"
  done
  printf '%s' "$home"
}

# every one of them names itself rather than dying on a missing path
function test_local_subcommands_refuse_without_the_checkout() {
  local home flag say out
  home="$(_hi_scratch_tree subcmd-bare common settings load.sh hi.sh)"
  for flag in --install --uninstall --configure "--preview colors" "--preview packages" "--preview header" --doctor --update; do
    # the refusal names the row's flag alone, never a subject or target
    # riding after it - every subcommand agrees, --preview included, since
    # common/flags' row dispatch handles them all
    say="${flag%% *}"
    # shellcheck disable=SC2086 # "--preview colors" is two words on purpose
    out="$(_hi_subcmd_run "$home" $flag)" && {
      _hi_cecho " | $flag exited 0 without a checkout" "$RED"
      return 1
    }
    [[ "$out" == *"hi $say needs the full say-hi checkout"* ]] || {
      _hi_cecho " | $flag said: $out" "$RED"
      return 1
    }
  done
}

# a joined word stands for the row's *first* argument, when that is a
# positional (--doctor's first is --json, so --doctor=json is refused rather
# than probed as a host named json); a row with
# none (switches only) refuses it here, before the script sees a stray word
function test_joined_value_is_refused_where_nothing_is_positional() {
  local home flag out rc
  home="$(_hi_subcmd_stubs)"
  for flag in --install=yes --uninstall=1 --configure=x --doctor=json --doctor=myhost; do
    rc=0
    out="$(_hi_subcmd_run "$home" "$flag")" || rc=$?
    [ "$rc" -eq 1 ] && [[ "$out" == *"${flag%%=*} takes no joined value"* ]] && [[ "$out" != STUB* ]] || {
      _hi_cecho " | $flag: rc $rc, said: $out" "$RED"
      return 1
    }
  done
}

# the mapping itself: which script, with which arguments
function test_local_subcommands_exec_the_right_script() {
  local home out spec flag want
  home="$(_hi_subcmd_stubs)"
  for spec in \
    '--install|STUB install --install' \
    '--uninstall|STUB install --uninstall' \
    '--configure|STUB install --configure' \
    '--doctor myhost|STUB doctor myhost' \
    '--preview colors|STUB preview colors' \
    '--preview=colors|STUB preview colors' \
    '--preview packages|STUB preview packages' \
    '--doctor|STUB doctor'; do
    flag="${spec%%|*}"
    want="${spec#*|}"
    # shellcheck disable=SC2086 # "--preview colors" is two words on purpose
    out="$(_hi_subcmd_run "$home" $flag)" || return 1
    [ "$out" = "$want" ] || {
      _hi_cecho " | $flag ran '$out', wanted '$want'" "$RED"
      return 1
    }
  done
}

# a sub-command is still a command line: what follows the flag rides along

# no subject at all - `hi --preview` must never connect to a host by that
# name. --preview routes through common/flags' row into the real
# scripts/preview.sh (not a case arm of hi.sh's own), and preview.sh's own
# dispatch is what validates the subject - a stub tree proves nothing here,
# so this needs the real script.
function test_preview_refuses_an_unknown_subject() {
  local home out rc=0
  home="$(_hi_scratch_tree preview-real common settings load.sh hi.sh scripts)"
  out="$(_hi_subcmd_run "$home" --preview bogus)" && return 1
  [[ "$out" == *"one of colors, packages, header, or targets"* ]] || return 1
  out="$(_hi_subcmd_run "$home" --preview=bogus)" && return 1
  [[ "$out" == *"one of colors, packages, header, or targets"* ]] || return 1
  out="$(_hi_subcmd_run "$home" --preview)" && return 1
  [[ "$out" == *"one of colors, packages, header, or targets"* ]] || return 1
  out="$(_hi_subcmd_run "$home" --preview --help)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == "Usage: hi --preview"* ]]
}

# `hi --use <TAB>` completes from targets.sh's words roster, which spells the
# arms on its own (a completion can reach it without hi.sh): it has to be
# ssh plus _HI_BACKENDS, in order
function test_use_words_match_the_backend_roster() {
  local want roster
  # shellcheck disable=SC2031
  want="$(printf '%s\n' ssh "${_HI_BACKENDS[@]%%|*}")"
  roster="$(sh "$_HI_ROOT/common/targets.sh" words --use | cut -f1)"
  [ "$roster" = "$want" ] || {
    _hi_cecho "   words --use: ${roster//$'\n'/ } - hi.sh: ${want//$'\n'/ }" "$RED"
    return 1
  }
}

function test_local_subcommands_forward_extra_arguments() {
  local home out
  home="$(_hi_subcmd_stubs)"
  out="$(_hi_subcmd_run "$home" --doctor myhost)" || return 1
  [ "$out" = "STUB doctor myhost" ] || return 1
  out="$(_hi_subcmd_run "$home" --preview colors --help)" || return 1
  [ "$out" = "STUB preview colors --help" ] || return 1
  out="$(_hi_subcmd_run "$home" --preview header --help)" || return 1
  [ "$out" = "STUB preview header --help" ]
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

# _hi is the dispatch function itself: the missing-$_HI_ROOT exit, the
# PLAIN/arm 2x2 that picks which _say_hi* runs, and the record/report calls
# that follow depending on the exit status. It calls `exit` outright, so
# every case here redefines the four _say_hi* arms plus _hi_parse,
# _hi_select_arm, and _hi_report_failure to markers instead
# of the real thing, in a subshell so none of it leaks to the next case.
#
# _hi_dispatch_probe <plain> <backend> <status> - runs _hi with $PLAIN=<plain> and
# _hi_select_arm answering <backend>, the chosen _say_hi* returning <status>.
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

function test_hi_reports_failure_only_on_nonzero_with_arm_and_tmp() {
  local out
  out="$(_hi_dispatch_probe 0 docker 3)"
  [[ "$out" == *"report_failure:3:docker"* ]]
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
  _hi_check_eq "-P's value is not mistaken for the target" "$(printf 'myhost\n\n-P\nmytag\n')" _hi_parse_out -P mytag myhost
  _hi_check "Several flags before the target" test_parse_handles_several_flags_before_the_target
  _hi_check "'--' does not end option parsing, and ssh's status comes back" test_parse_dashdash_does_not_end_option_parsing

  _hi_h2 "Testing: _hi_parse (commands and errors)"
  _hi_check "Trailing words become a command" test_parse_turns_trailing_words_into_a_command
  _hi_check "A dashed word after the target is the command's" test_parse_dashed_word_after_the_target_is_the_command
  _hi_check "A plain session has no command" test_parse_leaves_cmdarg_empty_for_a_plain_session
  _hi_check "Rejects a flag missing its value" test_parse_rejects_a_flag_missing_its_value
  _hi_check "Names the offending flag" test_parse_names_the_offending_flag
  _hi_check "An unknown --word is hi's error, not ssh's" test_parse_unknown_double_dash_word_is_his_error
  _hi_check "A local command behind an option is named" test_parse_local_command_behind_an_option_is_named
  _hi_check "hi's own flag after the target is refused" test_parse_own_flag_after_the_target_is_refused
  _hi_check "hi's own flag with no target is hi's error" test_parse_own_flag_without_a_target_is_his_error
  _hi_check "A bare flag takes no value" test_parse_bare_flag_with_a_value_is_refused
  _hi_check "...every bare row of common/flags, and -h/-V" test_parse_every_bare_flag_refuses_a_value
  _hi_check "-h behind an ssh option is still hi's" test_parse_help_is_honoured_behind_an_ssh_option
  _hi_check "help and version are plain target names" test_bare_help_and_version_words_are_targets
  _hi_check "A Host * block names no target" test_is_ssh_host_ignores_a_wildcard_block

  _hi_h2 "Testing: bare hi prints the help"
  _hi_check "Bare hi prints the help, exit 0" test_bare_hi_prints_help
  _hi_check_capable pty "...on a terminal too" test_bare_hi_prints_help_on_a_terminal_too
  _hi_check "An ssh option with no target still reaches ssh" test_an_ssh_option_without_a_target_reaches_ssh

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
  _hi_check "The family rows are the whole family" test_backend_roster_is_the_whole_family
  _hi_check "Nothing for an unknown target" test_resolve_backend_prints_nothing_for_a_stranger
  _hi_check "Nothing with no backend CLI at all" test_resolve_backend_prints_nothing_without_any_cli

  _hi_h2 "Testing: the arm override (--use <backend>)"
  _hi_check "Every arm resolves through --use, none has a row of its own" test_every_arm_resolves_through_use
  _hi_check "_hi_use_backend rejects a stranger" test_use_backend_rejects_a_stranger
  _hi_check_eq "--use <cli> sets BACKEND to that member" "$(printf 'myhost\nnerdctl\n')" _hi_backend_parse_out --use nerdctl myhost
  _hi_check_eq "--use and its word never reach SSHARGS" "$(printf 'myhost\n\n')" _hi_parse_out --use podman myhost
  _hi_check "--use rejects a stranger, naming every arm" test_parse_use_rejects_a_stranger
  _hi_check "--use=<backend> is the same flag" test_parse_use_takes_the_equals_spelling
  _hi_check "--use=<stranger> is refused" test_parse_use_equals_rejects_a_stranger
  _hi_check "--use <backend> reaches ssh and every backend" test_parse_use_names_every_arm
  _hi_check "--use with no word exits 1" test_parse_use_without_a_word_exits_one
  _hi_check "--use twice: same arm agrees, different arms refuse, both named" test_parse_use_twice_agrees_or_refuses
  _hi_check "--plain sets PLAIN, not SSHARGS" test_parse_plain_sets_plain_not_sshargs
  _hi_check "--plain combines with --use" test_parse_plain_combines_with_use
  _hi_check "RAWCMD carries no \"; exit\" suffix" test_parse_rawcmd_has_no_exit_suffix
  _hi_check "select_arm: the flag wins over a real match" test_select_arm_backend_flag_wins_over_a_real_match
  _hi_check "select_arm: the flag names the arm with no probe" test_select_arm_backend_flag_names_the_arm_with_no_probe
  _hi_check "select_arm: unset falls back to resolution" test_select_arm_falls_back_to_resolution_when_backend_unset
  _hi_check "select_arm: a Host * block does not shadow a container" test_select_arm_wildcard_host_does_not_shadow_a_container
  _hi_check "reset_terminal: the alt-screen exit rides in DECSC/DECRC" test_reset_terminal_wraps_the_alt_screen_exit_in_decsc_decrc
  _hi_check "reset_terminal: closes the prompt mark with the status" test_reset_terminal_closes_the_prompt_mark_with_the_status
  _hi_check "reset_terminal: no prompt mark when marks are off" test_reset_terminal_omits_the_prompt_mark_when_marks_are_off
  _hi_check "report_failure: silent once hi already said it" test_report_failure_is_silent_once_hi_already_said_it
  _hi_check "report_failure: silent for a non-255 ssh exit" test_report_failure_is_silent_for_a_non_255_ssh_exit
  _hi_check "report_failure: speaks on 255" test_report_failure_speaks_on_255
  _hi_check "report_failure: silent for a quiet container errlog" test_report_failure_is_silent_for_a_quiet_container_errlog
  _hi_check "report_failure: speaks with a filed container error" test_report_failure_speaks_with_a_filed_container_error
  _hi_check "report_failure: no \\r off a tty" test_report_failure_has_no_carriage_return_off_a_tty

  _hi_check_capable pty "target/inner picks the container or task" test_container_cmds_pick_the_inner_unit
  _hi_check "no tty, no -t (hi <target> <cmd> | ...)" test_container_cmds_drop_the_tty_without_one
  _hi_check_capable pty "namespace:pod and context:namespace:pod reach kubectl" test_kube_prefixes_become_kubectl_flags

  _hi_h2 "Testing: --plain"
  _hi_check "Container: attaches with no write, prefers bash" test_plain_container_attaches_with_no_write
  _hi_check "Container: falls back to the ladder without bash" test_plain_container_falls_back_to_the_ladder_without_bash
  _hi_check "Container: runs RAWCMD with -c" test_plain_container_runs_rawcmd_with_dash_c
  _hi_check "ssh: execs real ssh with RAWCMD" test_plain_ssh_execs_real_ssh_with_rawcmd
  _hi_check "ssh: no command means no trailing word" test_plain_ssh_with_no_command_passes_none

  _hi_h2 "Testing: _hi (the dispatch)"
  _hi_check "Exits 1 when \$_HI_ROOT is missing" test_hi_exits_1_when_root_is_missing
  _hi_check "PLAIN=0, no arm -> _say_hi" test_hi_dispatch_plain0_no_arm_calls_say_hi
  _hi_check "PLAIN=0, an arm -> _say_hi_container" test_hi_dispatch_plain0_with_arm_calls_say_hi_container
  _hi_check "PLAIN=1, no arm -> _say_hi_plain" test_hi_dispatch_plain1_no_arm_calls_say_hi_plain
  _hi_check "PLAIN=1, an arm -> _say_hi_container_plain" test_hi_dispatch_plain1_with_arm_calls_say_hi_container_plain
  _hi_check "Exits with the arm's own status" test_hi_exit_code_is_the_arms
  _hi_check "Reports failure only on non-zero, with arm+tmp" test_hi_reports_failure_only_on_nonzero_with_arm_and_tmp

  _hi_h2 "Testing: hi's local sub-commands"
  _hi_check "Each refuses by name without the checkout" test_local_subcommands_refuse_without_the_checkout
  _hi_check "--preview wants one of four subjects" test_preview_refuses_an_unknown_subject
  _hi_check "--use's completion roster is hi's backend roster" test_use_words_match_the_backend_roster
  _hi_check "Each execs the right script and args" test_local_subcommands_exec_the_right_script
  _hi_check "A joined word needs a positional to stand for" test_joined_value_is_refused_where_nothing_is_positional
  _hi_check "Extra arguments ride along" test_local_subcommands_forward_extra_arguments
  _hi_check "paths.sh defines no command aliases" test_paths_defines_no_command_aliases

  _hi_h2 "Testing: hi --help"
  _hi_check "--help prints the usage line" test_help_long_flag_prints_usage
  _hi_check "-V prints hi's version, not ssh's" test_version_short_flag_is_hi_s_own
  _hi_check "...and names the tree it came from" test_version_line_names_the_tree
  _hi_check "--help and --version take no trailing word" test_help_and_version_refuse_a_trailing_word
  _hi_check_eq "-h is the same text" "$(_hi_help_out --help)" _hi_help_out -h
  _hi_check "Lists hi's flags and the target ladder" test_help_lists_hi_s_own_flags
  _hi_check "Every flag is in the man page" test_help_flags_are_all_in_the_man_page
  _hi_check "...and every option the man page names is hi's" test_man_page_options_are_all_hi_s
  _hi_check "Each local command's synopsis form is its flags row" test_local_synopsis_forms_match_common_flags
  _hi_check "...and so is its OPTIONS heading" test_local_option_headings_match_common_flags
  _hi_check "The usage line is the man page's synopsis" test_usage_line_matches_the_man_page_synopsis
  _hi_check "Every line fits 80 columns" test_help_fits_eighty_columns
  _hi_check "The man page groups them as the roster does" test_man_page_option_groups_match_the_roster
  _hi_check "Both shell ladders are in the man page" test_shell_ladders_are_in_the_man_page
  _hi_check "The ladder is the shell tree without bash" test_the_shell_tree_is_the_documented_order
  _hi_suite_end "hi.sh (parsing and dispatch)"
}

run_hi_parse_tests
