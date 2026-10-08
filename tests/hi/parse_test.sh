#!/usr/bin/env bash
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
    "$(printf 'myhost\n\n-4\n-o\nStrictHostKeyChecking=no\n-i\n/tmp/k\n')" ] || _hi_why
}

# a trailing command becomes CMDARG - suffixed with "; exit" so the target
# shell closes after it - and never a second target. The spacing between the
# two is incidental (_hi_parse pastes '; ' and ' exit'), so don't pin it.
function test_parse_turns_trailing_words_into_a_command() {
  local out
  out="$(_hi_parse_out myhost echo hello)"
  [[ "$out" == myhost*"echo hello;"*exit* ]] || _hi_why out
}

# ...dashed or not: the target ends the options, and `hi host -la` is ssh's
# `ssh host -la` - the command's word, never an ssh argument
function test_parse_dashed_word_after_the_target_is_the_command() {
  local out
  out="$(_hi_parse_out myhost -la)"
  [[ "$out" == myhost*"-la;"*exit* ]] && [ "$(printf '%s\n' "$out" | wc -l)" -eq 2 ] || _hi_why out
}

function test_parse_leaves_cmdarg_empty_for_a_plain_session() {
  [ "$(_hi_parse_out myhost | sed -n 2p)" = "" ] || _hi_why
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
  [ "$rc" -eq 3 ] || _hi_why rc || return 1
  [ "$(cat "$log")" = "-- -oddtarget" ] || _hi_why log
}

# ssh takes no option that starts with two dashes, so every --word is hi's:
# a stranger is hi's error and exit 1, never ssh's usage message
function test_parse_unknown_double_dash_word_is_his_error() {
  local out rc=0
  out="$( (_hi_parse --docter myhost 2>&1 >/dev/null) )" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"hi: unknown option --docter"* ]] || _hi_why rc out
}

# a local command is dispatched on the first word alone; behind an ssh
# option it is named as out of place, not as a stranger
function test_parse_local_command_behind_an_option_is_named() {
  local out rc=0
  out="$( (_hi_parse -v --doctor myhost 2>&1 >/dev/null) )" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--doctor goes first"* ]] || _hi_why rc out
}

# the target ends the options: a dashed word after it is the remote
# command's, the way `ssh host ls -la` reads - and one of hi's own flags
# there is refused by name rather than run on the far end
function test_parse_own_flag_after_the_target_is_refused() {
  local out rc=0
  out="$( (_hi_parse myhost --use docker 2>&1 >/dev/null) )" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--use goes before the target"* ]] || _hi_why rc out
}

# hi's own flags with nothing to connect to:
# hi's error, never ssh's usage message (ssh saw none of them)
function test_parse_own_flag_without_a_target_is_his_error() {
  local out rc=0
  out="$( (_hi_parse --plain </dev/null 2>&1 >/dev/null) )" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"no target to connect to"* ]] || _hi_why rc out || return 1
  rc=0
  out="$( (_hi_parse --use docker </dev/null 2>&1 >/dev/null) )" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"no target to connect to"* ]] || _hi_why rc out
}

# a bare flag given a joined value is told so, not told to go first
function test_parse_bare_flag_with_a_value_is_refused() {
  local out rc=0
  out="$( (_hi_parse --plain=1 myhost 2>&1 >/dev/null) )" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--plain takes no value"* ]] || _hi_why rc out
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
  out="$(_hi_help_out -o StrictHostKeyChecking=no -h)" || _hi_why || return 1
  [[ "$out" == "Usage: hi "* && "$out" != *"ssh was called"* ]] || _hi_why out
}

# the bare words help and version are targets like any other: -h and -V are
# the only spellings hi claims, so a host called help needs no escaping
function test_bare_help_and_version_words_are_targets() {
  [ "$(_hi_parse_out help | sed -n 1p)" = help ] &&
    [ "$(_hi_parse_out version | sed -n 1p)" = version ] &&
    [ "$(_hi_parse_out -4 help | sed -n 1p)" = help ] || _hi_why
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
  _HI_SSH_CONFIG="$cfg" _hi_is_ssh_host literal || _hi_why cfg || return 1
  ! _HI_SSH_CONFIG="$cfg" _hi_is_ssh_host yes || _hi_why cfg
}

function test_select_arm_wildcard_host_does_not_shadow_a_container() {
  local DOMAIN=yes BACKEND=
  [ "$(_HI_SSH_CONFIG="$(_hi_wild_ssh_config)" PATH="$_HI_SHIM_PATH" _hi_select_arm)" = docker ] || _hi_why _HI_SHIM_PATH
}

# a value-taking flag with nothing after it must report itself, not die on an
# unbound $2 or swallow the next argument
function test_parse_rejects_a_flag_missing_its_value() {
  local rc=0
  (_hi_parse -p >/dev/null 2>&1) || rc=$?
  [ "$rc" -eq 1 ] || _hi_why rc
}

function test_parse_names_the_offending_flag() {
  local out
  out="$( (_hi_parse -o 2>&1 >/dev/null) || true)"
  [[ "$out" == *"-o"* ]] || _hi_why out
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
    [[ "$out" == *"hi's own options"* ]] || _hi_why rc out _HI_USAGE
}

# ...and the same under a pty, terminal or not
function test_bare_hi_prints_help_on_a_terminal_too() {
  local out rc=0
  out="$("${_HI_PTY_FORCED[@]}" bash -c '
      source "$_HI_LAUNCHER"
      _hi_parse' 2>/dev/null)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"hi's own options"* ]] || _hi_why rc out
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
  [[ "$out" == *"ssh-stub: -4"* ]] && [[ "$out" != *"hi's own options"* ]] || _hi_why out
}

# test_backend_predicate <predicate> <yes|no> - against the shims, a
# predicate (a command line, as the roster holds it) accepts the running
# target (yes) and rejects the stopped or pending one (no)
# shellcheck disable=SC2086 # the predicate's word split is the point
function test_backend_predicate() {
  if [ "$2" = yes ]; then
    PATH="$_HI_SHIM_PATH" $1 yes
  elif PATH="$_HI_SHIM_PATH" $1 no; then
    _hi_why -3 _HI_SHIM_PATH || return 1
  fi
}

# with no backend CLI on $PATH at all, every predicate must answer "no"
# rather than erroring - that is what lets _hi fall through to ssh
function test_predicates_are_false_without_their_cli() {
  local empty="$_HI_WORKDIR/empty"
  mkdir -p "$empty"
  { ! PATH="$empty" _hi_is_family_container docker yes &&
    ! PATH="$empty" _hi_is_family_container podman yes &&
    ! PATH="$empty" _hi_is_nomad_alloc yes &&
    ! PATH="$empty" _hi_is_k8s_pod yes; } || _hi_why empty
}

# The predicates run together, so the guarantee worth pinning is that the
# *answer* is still the roster's first match rather than whichever CLI
# happened to reply first. The shims answer for target "yes", so a target
# every backend claims must still resolve to docker - the row at the top of
# $_HI_BACKENDS.

function test_resolve_backend_picks_the_first_matching_row() {
  [ "$(PATH="$_HI_SHIM_PATH" _hi_resolve_backend yes)" = docker ] || _hi_why _HI_SHIM_PATH
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
  [ "$out" = podman ] || _hi_why out
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
  [ -n "$launch" ] || _hi_why launch || return 1
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
      *) _hi_why -3 name launch _HI_CONTAINER_CLIS || return 1 ;;
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
  [ "$names" = "$(printf 'docker\npodman\nnerdctl\nfinch\nnomad\nkube\n')" ] || _hi_why names
}

function test_resolve_backend_prints_nothing_for_a_stranger() {
  [ -z "$(PATH="$_HI_SHIM_PATH" _hi_resolve_backend no)" ] || _hi_why _HI_SHIM_PATH
}

# no CLI at all: every predicate is false, and _hi falls through to ssh
function test_resolve_backend_prints_nothing_without_any_cli() {
  local empty="$_HI_WORKDIR/empty"
  mkdir -p "$empty"
  [ -z "$(PATH="$empty" _hi_resolve_backend yes)" ] || _hi_why empty
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
    [ "$(_hi_use_backend "$name" 2>/dev/null)" = "$name" ] || _hi_why name || return 1
    ! grep -q "^--$name|" "$_HI_ROOT/common/flags" || _hi_why name || return 1
  done
  grep -q '^--use|' "$_HI_ROOT/common/flags" || _hi_why
}

function test_use_backend_rejects_a_stranger() {
  ! _hi_use_backend frobnicate >/dev/null 2>&1 || _hi_why
}

# [chosen] is an earlier --use's arm: naming it again is fine, naming another
# is refused here, once, for _hi_parse and doctor both - on stderr, with
# nothing on stdout for a caller's $( ) to take as an arm
function test_use_backend_refuses_a_second_arm() {
  local out err
  [ "$(_hi_use_backend docker docker 2>/dev/null)" = docker ] || _hi_why || return 1
  err="$(_hi_use_backend podman docker 2>&1 >/dev/null)" && return 1
  out="$(_hi_use_backend podman docker 2>/dev/null)" && return 1
  [ -z "$out" ] && [[ "$err" == *"--use podman and --use docker both name a backend; pick one"* ]] || _hi_why out err
}

# --use=<backend> is the same flag with its word joined, the spelling
# install.sh's --prefix and --preset already take, and must not fall through
# to ssh as an unknown option
function test_parse_use_takes_the_equals_spelling() {
  [ "$(_hi_backend_parse_out --use=nerdctl myhost)" = "$(printf 'myhost\nnerdctl\n')" ] &&
    [ "$(_hi_parse_out --use=podman myhost)" = "$(printf 'myhost\n\n')" ] || _hi_why
}

function test_parse_use_equals_rejects_a_stranger() {
  local rc=0
  (_hi_parse --use=frobnicate myhost >/dev/null 2>&1) || rc=$?
  [ "$rc" -eq 1 ] || _hi_why rc
}

function test_parse_use_rejects_a_stranger() {
  local rc=0 out
  out="$( (_hi_parse --use frobnicate myhost 2>&1 >/dev/null) || true)"
  (_hi_parse --use frobnicate myhost >/dev/null 2>&1) || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--use"*ssh*docker*kube* ]] || _hi_why rc out
}

# --use reaches every arm, not only the family: ssh (the empty arm) and the
# orchestrators too, the same values their shorthand flags set
function test_parse_use_names_every_arm() {
  local name
  for name in ssh docker podman nomad kube; do
    [ "$(_hi_backend_parse_out --use "$name" myhost)" = "$(printf 'myhost\n%s\n' "$name")" ] || _hi_why name || return 1
  done
}

function test_parse_use_without_a_word_exits_one() {
  local rc=0
  (_hi_parse --use >/dev/null 2>&1) || rc=$?
  [ "$rc" -eq 1 ] || _hi_why rc
}

# the same arm twice is no conflict; two different arms are one, and the
# message names both
function test_parse_use_twice_agrees_or_refuses() {
  local rc=0 out
  [ "$(_hi_backend_parse_out --use docker --use docker myhost)" = "$(printf 'myhost\ndocker\n')" ] || _hi_why || return 1
  (_hi_parse --use podman --use docker myhost >/dev/null 2>&1) || rc=$?
  [ "$rc" -eq 1 ] || _hi_why rc || return 1
  out="$( (_hi_parse --use docker --use ssh myhost 2>&1 >/dev/null) || true)"
  [[ "$out" == *"--use ssh"*"--use docker"* ]] || _hi_why out
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

# --no-plain is the pair's other half: the last of the two wins
function test_parse_no_plain_is_the_other_half() {
  [ "$(_hi_var_parse_out PLAIN unset --no-plain myhost)" = "$(printf 'myhost\n0\n')" ] &&
    [ "$(_hi_plain_parse_out --no-plain --plain myhost)" = "$(printf 'myhost\n1\n')" ] &&
    [ "$(_hi_var_parse_out PLAIN unset --plain --no-plain myhost)" = "$(printf 'myhost\n0\n')" ] &&
    [ "$(_hi_var_parse_out PLAIN unset myhost)" = "$(printf 'myhost\nunset\n')" ] || _hi_why
}

function test_parse_plain_sets_plain_not_sshargs() {
  [ "$(_hi_plain_parse_out --plain myhost)" = "$(printf 'myhost\n1\n')" ] &&
    [ "$(_hi_parse_out --plain myhost)" = "$(printf 'myhost\n\n')" ] || _hi_why
}

# combines freely with --use - orthogonal, checked in either order
function test_parse_plain_combines_with_use() {
  [ "$(_hi_plain_parse_out --plain --use docker myhost)" = "$(printf 'myhost\n1\n')" ] &&
    [ "$(_hi_backend_parse_out --use docker --plain myhost)" = "$(printf 'myhost\ndocker\n')" ] || _hi_why
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
    [[ "$(printf '%s\n' "$out" | sed -n 2p)" == *"exit"* ]] || _hi_why out
}

# _hi_select_arm is what _hi calls to choose $arm; testing it directly means
# asserting the choice without a real connect
function test_select_arm_backend_flag_wins_over_a_real_match() {
  local DOMAIN=yes BACKEND=ssh
  [ -z "$(PATH="$_HI_SHIM_PATH" _hi_select_arm)" ] || _hi_why _HI_SHIM_PATH
}

function test_select_arm_backend_flag_names_the_arm_with_no_probe() {
  local DOMAIN=no BACKEND=docker
  # PATH has nothing at all: a probe would find no CLI and print nothing, so
  # a printed "docker" here can only have come from $BACKEND
  local empty="$_HI_WORKDIR/empty"
  mkdir -p "$empty"
  [ "$(PATH="$empty" _hi_select_arm)" = docker ] || _hi_why empty
}

function test_select_arm_falls_back_to_resolution_when_backend_unset() {
  local DOMAIN=yes BACKEND=
  [ "$(PATH="$_HI_SHIM_PATH" _hi_select_arm)" = docker ] || _hi_why _HI_SHIM_PATH
}

# a backend $_HI_BACKENDS_OFF names is not asked, so the name is ssh's: by
# word, a comma or a space apart, and by `all`
function test_select_arm_skips_a_backend_switched_off() {
  local DOMAIN=yes BACKEND=
  [ -z "$(_HI_BACKENDS_OFF="docker,podman nerdctl finch nomad kube" PATH="$_HI_SHIM_PATH" _hi_select_arm)" ] &&
    [ -z "$(_HI_BACKENDS_OFF=all PATH="$_HI_SHIM_PATH" _hi_select_arm)" ] &&
    [ "$(_HI_BACKENDS_OFF=nomad PATH="$_HI_SHIM_PATH" _hi_select_arm)" = docker ] || _hi_why _HI_SHIM_PATH
}

# The alternate-screen exit is the one mode byte a terminal still on its
# normal screen answers with a cursor move (Konsole restores from a slot
# nothing saved, i.e. home), so it rides between a DECSC and a DECRC and the
# whole string is inert on a terminal that never left the normal screen.
# GLOSSARY: HI.53
function test_reset_terminal_wraps_the_alt_screen_exit_in_decsc_decrc() {
  local out
  out="$(_hi_reset_terminal 255 2>/dev/null)"
  [[ "$out" == *$'\e7\e[?1049l\e8'* ]] || _hi_why out
}

# the OSC 133 "command done" carries the status, so a Konsole left mid-command
# by a drop stops reading the arrow keys as an edit of the last one
function test_reset_terminal_closes_the_prompt_mark_with_the_status() {
  local out
  out="$(_hi_reset_terminal 130 2>/dev/null)"
  [[ "$out" == *$'\e]133;D;130\a'* ]] || _hi_why out
}

function test_report_failure_is_silent_once_hi_already_said_it() {
  local _HI_SAID=1
  [ -z "$(_hi_report_failure 255 "" "" 2>&1)" ] || _hi_why
}

# ssh reserves 255 for its own failures; anything else through the ssh arm is
# the session's or the remote command's own exit status, which ssh itself
# never announces either
function test_report_failure_is_silent_for_a_non_255_ssh_exit() {
  [ -z "$(_hi_report_failure 1 "" "" 2>&1)" ] || _hi_why
}

function test_report_failure_speaks_on_255() {
  local DOMAIN=myhost f="$_HI_WORKDIR/ssh255.log"
  : >"$f"
  [[ "$(_hi_report_failure 255 "" "$f" 2>&1)" == *"could not reach [myhost]"* ]] || _hi_why f
}

# a container arm with nothing filed in its errlog means nothing hi ran on
# the way in complained, so the exit is the session's, not hi's to announce
function test_report_failure_is_silent_for_a_quiet_container_errlog() {
  local f="$_HI_WORKDIR/empty.log"
  : >"$f"
  [ -z "$(_hi_report_failure 1 docker "$f" 2>&1)" ] || _hi_why f
}

function test_report_failure_speaks_with_a_filed_container_error() {
  local DOMAIN=mybox f="$_HI_WORKDIR/filed.log"
  printf 'copy failed\n' >"$f"
  local out
  out="$(_hi_report_failure 1 docker "$f" 2>&1)"
  [[ "$out" == *"could not reach [mybox]"* && "$out" == *"copy failed"* ]] || _hi_why out
}

# no \r anywhere when stderr is not a terminal - a captured/piped failure
# gets a plain newline instead of a cursor move that has nothing to move
function test_report_failure_has_no_carriage_return_off_a_tty() {
  local DOMAIN=myhost f="$_HI_WORKDIR/notty.log"
  : >"$f"
  [[ "$(_hi_report_failure 255 "" "$f" 2>&1)" != *$'\r'* ]] || _hi_why f
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
  _hi_attach_is 1 kube mypod '!* -c *' || _hi_why || return 1
  _hi_attach_is 1 kube mypod/sidecar '*exec -it mypod -c sidecar --' || _hi_why || return 1
  _hi_attach_is 1 nomad 685afd67/worker '*-task worker*685afd67' || _hi_why || return 1
  # docker has no inner unit and `/` is legal in a container name, so it is
  # taken whole - splitting one would break a real target
  _hi_attach_is 1 docker some/name '*exec -it some/name' || _hi_why
}

# The other arm of that probe, which is the one `hi <target> <cmd> | ...` takes:
# `docker exec -it` does not fall back to a pipe when stdin is not a terminal,
# it refuses ("cannot attach stdin to a TTY-enabled container"), so the command
# form failed at the transport before the command ran. Every container backend
# has to drop the `-t` and keep the `-i`; nomad spells both out either way,
# because its own stdin-is-a-tty guess hangs the exec on a wrapped pty.
function test_container_cmds_drop_the_tty_without_one() {
  _hi_attach_is 0 kube mypod '*exec -i mypod --' || _hi_why || return 1
  _hi_attach_is 0 docker somebox '*exec -i somebox' || _hi_why || return 1
  _hi_attach_is 0 nomad 685afd67 '*-i=true -t=false*' || _hi_why || return 1

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
    'kubectl --namespace staging exec -it web --' || _hi_why || return 1
  _hi_attach_is 1 kube prod:staging:web/sidecar \
    'kubectl --context prod --namespace staging exec -it web -c sidecar --' || _hi_why
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

# _hi_parse_begin - what every part of this suite starts from, and the tally
function _hi_parse_begin() {
  _hi_workdir hiparsetest
  _hi_probe_shims "$_HI_WORKDIR/shims"
  _HI_SHIM_PATH="$_HI_WORKDIR/shims:$PATH"
  _hi_suite_begin
}

function run_hi_parse_tests() {
  _hi_parse_begin

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
  _hi_check "docker: running" test_backend_predicate "_hi_is_family_container docker" yes
  _hi_check "docker: stopped" test_backend_predicate "_hi_is_family_container docker" no
  _hi_check "podman: running" test_backend_predicate "_hi_is_family_container podman" yes
  _hi_check "nomad: running" test_backend_predicate _hi_is_nomad_alloc yes
  _hi_check "nomad: pending" test_backend_predicate _hi_is_nomad_alloc no
  _hi_check "kube: running" test_backend_predicate _hi_is_k8s_pod yes
  _hi_check "kube: pending" test_backend_predicate _hi_is_k8s_pod no
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
  _hi_check "_hi_use_backend refuses a second, different arm" test_use_backend_refuses_a_second_arm
  _hi_check_eq "--use <cli> sets BACKEND to that member" "$(printf 'myhost\nnerdctl\n')" _hi_backend_parse_out --use nerdctl myhost
  _hi_check_eq "--use and its word never reach SSHARGS" "$(printf 'myhost\n\n')" _hi_parse_out --use podman myhost
  _hi_check "--use rejects a stranger, naming every arm" test_parse_use_rejects_a_stranger
  _hi_check "--use=<backend> is the same flag" test_parse_use_takes_the_equals_spelling
  _hi_check "--use=<stranger> is refused" test_parse_use_equals_rejects_a_stranger
  _hi_check "--use <backend> reaches ssh and every backend" test_parse_use_names_every_arm
  _hi_check "--use with no word exits 1" test_parse_use_without_a_word_exits_one
  _hi_check "--use twice: same arm agrees, different arms refuse, both named" test_parse_use_twice_agrees_or_refuses
  _hi_check "--plain sets PLAIN, not SSHARGS" test_parse_plain_sets_plain_not_sshargs
  _hi_check "--no-plain is the pair's other half" test_parse_no_plain_is_the_other_half
  _hi_check "--plain combines with --use" test_parse_plain_combines_with_use
  _hi_check "RAWCMD carries no \"; exit\" suffix" test_parse_rawcmd_has_no_exit_suffix
  _hi_check "select_arm: the flag wins over a real match" test_select_arm_backend_flag_wins_over_a_real_match
  _hi_check "select_arm: the flag names the arm with no probe" test_select_arm_backend_flag_names_the_arm_with_no_probe
  _hi_check "select_arm: unset falls back to resolution" test_select_arm_falls_back_to_resolution_when_backend_unset
  _hi_check "select_arm: a backend switched off is not asked" test_select_arm_skips_a_backend_switched_off
  _hi_check "select_arm: a Host * block does not shadow a container" test_select_arm_wildcard_host_does_not_shadow_a_container
  _hi_check "reset_terminal: the alt-screen exit rides in DECSC/DECRC" test_reset_terminal_wraps_the_alt_screen_exit_in_decsc_decrc
  _hi_check "reset_terminal: closes the prompt mark with the status" test_reset_terminal_closes_the_prompt_mark_with_the_status
  _hi_check "report_failure: silent once hi already said it" test_report_failure_is_silent_once_hi_already_said_it
  _hi_check "report_failure: silent for a non-255 ssh exit" test_report_failure_is_silent_for_a_non_255_ssh_exit
  _hi_check "report_failure: speaks on 255" test_report_failure_speaks_on_255
  _hi_check "report_failure: silent for a quiet container errlog" test_report_failure_is_silent_for_a_quiet_container_errlog
  _hi_check "report_failure: speaks with a filed container error" test_report_failure_speaks_with_a_filed_container_error
  _hi_check "report_failure: no \\r off a tty" test_report_failure_has_no_carriage_return_off_a_tty

  _hi_check_capable pty "target/inner picks the container or task" test_container_cmds_pick_the_inner_unit
  _hi_check "no tty, no -t (hi <target> <cmd> | ...)" test_container_cmds_drop_the_tty_without_one
  _hi_check_capable pty "namespace:pod and context:namespace:pod reach kubectl" test_kube_prefixes_become_kubectl_flags

  _hi_suite_end "hi.sh (parsing and dispatch)"
}

# a part (parse_*_test.sh) sources this file for what is above and runs its own
[ -n "${_HI_PARSE_PART:-}" ] || run_hi_parse_tests
