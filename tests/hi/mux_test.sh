#!/usr/bin/env bash
# tests/hi/mux_test.sh - the client-side tmux wrap: --mux, _HI_MUX, the
# session name a target maps to, and the tmux calls _hi_mux_wrap makes. tmux
# is a shim that logs its argv; one case behind a real tmux proves the name
# rule against the real thing. Sources hi.sh, which defines its functions and
# stops (the trailing dispatch is guarded), so nothing here connects.
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329,SC2317,SC2030,SC2031
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"
# shellcheck source=../../hi.sh
source "$_HI_LAUNCHER"

# _hi_mux_shim <log> - a tmux that appends its argv to <log>; has-session says
# no, so the inside-tmux path has to create the session first
function _hi_mux_shim() {
  local bin="$_HI_WORKDIR/muxbin"
  mkdir -p "$bin"
  cat >"$bin/tmux" <<SHIM
#!/bin/sh
printf 'TMUX %s\\n' "\$*" >>"$1"
[ "\$1" != has-session ]
SHIM
  chmod +x "$bin/tmux"
  printf '%s' "$bin"
}

# _hi_mux_run <log> <inside-tmux: 0|1> <parsed-state assignments> - run the
# wrap in a subshell with the shim first on PATH, so its exec ends the subshell
# rather than the suite; the log is what the shim saw, then RETURNED if the
# wrap came back instead of exec'ing
function _hi_mux_run() {
  local log="$1" inside="$2" state="$3" bin
  bin="$(_hi_mux_shim "$log")"
  : >"$log"
  (
    export PATH="$bin:$PATH"
    if [ "$inside" = 1 ]; then export TMUX=/tmp/tmux-0/default,1,0; else unset TMUX; fi
    unset _HI_MUX_INNER
    MUX=1 DOMAIN=myhost SSHARGS=() BACKEND="" PLAIN="" RAWCMD=""
    eval "$state"
    _hi_mux_wrap
    printf 'RETURNED\n' >>"$log"
  ) </dev/null 2>/dev/null || true
  cat "$log"
}

function test_mux_name_drops_what_tmux_rejects() {
  local out
  for out in "$(_hi_mux_name user@host)" "$(_hi_mux_name ctx:ns:pod/ctr)" "$(_hi_mux_name 'db.example.com')"; do
    case "$out" in hi-*) ;; *) return 1 ;; esac
    case "$out" in *[:./@]*) return 1 ;; esac
  done
  [ "$(_hi_mux_name ctx:ns:pod/ctr)" = hi-ctx-ns-pod-ctr ] &&
    [ "$(_hi_mux_name user@host)" = hi-user-host ]
}

# tmux's own rule, not ours: a name the sanitizer produced is one tmux takes
function test_mux_name_is_a_session_name_tmux_accepts() {
  local sock="$_HI_WORKDIR/tmux.sock" name
  name="$(_hi_mux_name 'ctx:ns:pod/ctr')"
  tmux -S "$sock" new-session -d -s "$name" true || return 1
  tmux -S "$sock" kill-server 2>/dev/null || true
}

# --mux ahead of the target is hi's; after it, the remote command's own word
function test_mux_flag_sets_mux_ahead_of_the_target() {
  local out
  out="$(
    unset DOMAIN MUX
    _hi_parse --mux myhost >/dev/null 2>&1
    printf '%s|%s|%s' "${MUX:-0}" "${DOMAIN:-}" "${SSHARGS[*]:-}"
  )"
  [ "$out" = "1|myhost|" ]
}

function test_mux_flag_after_the_target_is_the_commands() {
  local out
  out="$(
    unset DOMAIN MUX
    _hi_parse myhost --mux >/dev/null 2>&1
    printf '%s|%s|%s' "${MUX:-0}" "${DOMAIN:-}" "${SSHARGS[*]:-}"
  )"
  [ "$out" = "0|myhost|--mux" ]
}

# --no-mux is the per-connect way out of _HI_MUX=1, and the last of the two
# flags wins; after the target it is the remote command's word like --mux
function test_no_mux_flag_clears_mux_ahead_of_the_target() {
  local out
  out="$(
    unset DOMAIN MUX
    _hi_parse --mux --no-mux myhost >/dev/null 2>&1
    printf '%s|%s|%s' "${MUX:-unset}" "${DOMAIN:-}" "${SSHARGS[*]:-}"
  )"
  [ "$out" = "0|myhost|" ] || return 1
  out="$(
    unset DOMAIN MUX
    _hi_parse --no-mux --mux myhost >/dev/null 2>&1
    printf '%s' "${MUX:-unset}"
  )"
  [ "$out" = 1 ] || return 1
  out="$(
    unset DOMAIN MUX
    _hi_parse myhost --no-mux >/dev/null 2>&1
    printf '%s|%s' "${MUX:-unset}" "${SSHARGS[*]:-}"
  )"
  [ "$out" = "unset|--no-mux" ]
}

function test_no_mux_beats_the_setting() {
  local log="$_HI_WORKDIR/nomux.log" out
  out="$(_hi_mux_run "$log" 0 'MUX=0; _HI_MUX=1')"
  [ "$out" = RETURNED ]
}

function test_mux_wrap_is_a_no_op_without_the_flag() {
  local log="$_HI_WORKDIR/off.log" out
  out="$(_hi_mux_run "$log" 0 'MUX=0; unset _HI_MUX')"
  [ "$out" = RETURNED ]
}

function test_mux_wrap_stands_down_inside_the_wrapped_session() {
  local log="$_HI_WORKDIR/inner.log" out
  out="$(_hi_mux_run "$log" 0 'export _HI_MUX_INNER=1')"
  [ "$out" = RETURNED ]
}

function test_mux_wrap_connects_plain_without_tmux() {
  local log="$_HI_WORKDIR/notmux.log" out
  # the shim dir is dropped again: no tmux anywhere on this PATH
  # shellcheck disable=SC2016 # the assignment is evaluated in the subshell
  out="$(_hi_mux_run "$log" 0 'PATH="$(_hi_real_path muxreal sh sed cat printf)"')"
  [ "$out" = RETURNED ]
}

function test_mux_wrap_execs_new_session_A_named_for_the_target() {
  local log="$_HI_WORKDIR/outside.log" out
  out="$(_hi_mux_run "$log" 0 :)"
  [ "$(printf '%s\n' "$out" | grep -c '^TMUX')" = 1 ] || return 1
  case "$out" in
  "TMUX new-session -A -s hi-myhost "*"_HI_MUX_INNER=1"*"$_HI_LAUNCHER"*"'myhost'"*) ;;
  *) return 1 ;;
  esac
  case "$out" in *RETURNED*) return 1 ;; esac
}

# the setting alone, no flag: the same wrap
function test_mux_setting_wraps_without_the_flag() {
  local log="$_HI_WORKDIR/setting.log" out
  out="$(_hi_mux_run "$log" 0 'MUX=""; export _HI_MUX=1')"
  case "$out" in "TMUX new-session -A -s hi-myhost "*) ;; *) return 1 ;; esac
}

# inside a tmux nesting is refused: create detached, then switch this client
function test_mux_wrap_inside_tmux_creates_then_switches() {
  local log="$_HI_WORKDIR/inside.log" out
  out="$(_hi_mux_run "$log" 1 :)"
  [ "$(printf '%s\n' "$out" | sed -n '1p')" = "TMUX has-session -t =hi-myhost" ] || return 1
  case "$(printf '%s\n' "$out" | sed -n '2p')" in "TMUX new-session -d -s hi-myhost "*) ;; *) return 1 ;; esac
  [ "$(printf '%s\n' "$out" | sed -n '3p')" = "TMUX switch-client -t =hi-myhost" ]
}

# the inner argv is the parsed state - a picked target, --use, --plain, the
# ssh options and the command all ride along, each as one quoted word
function test_mux_wrap_rebuilds_the_inner_argv_from_parsed_state() {
  local log="$_HI_WORKDIR/argv.log" out
  out="$(_hi_mux_run "$log" 0 "BACKEND=docker PLAIN=1 SSHARGS=(-p 2222) DOMAIN='pod name' RAWCMD=\"echo it's\"")"
  case "$out" in
  *"'--use' 'docker' '--plain' '-p' '2222' 'pod name' 'echo it'\\''s'"*) ;;
  *) return 1 ;;
  esac
}

function run_hi_mux_tests() {
  _hi_workdir himuxtest
  _hi_suite_begin
  _hi_h1 "Testing hi.sh: the client-side tmux wrap"
  _hi_h2 "Testing: the session name"
  _hi_check_eq "A plain host is hi-<host>" hi-host _hi_mux_name host
  _hi_check "Characters tmux rejects become dashes" test_mux_name_drops_what_tmux_rejects
  _hi_check_requires tmux "tmux accepts the name" test_mux_name_is_a_session_name_tmux_accepts
  _hi_h2 "Testing: --mux in _hi_parse"
  _hi_check "--mux ahead of the target sets MUX" test_mux_flag_sets_mux_ahead_of_the_target
  _hi_check "--mux after the target is the command's" test_mux_flag_after_the_target_is_the_commands
  _hi_check "--no-mux clears it, last one wins" test_no_mux_flag_clears_mux_ahead_of_the_target
  _hi_h2 "Testing: _hi_mux_wrap"
  _hi_check "Without the flag or setting, nothing happens" test_mux_wrap_is_a_no_op_without_the_flag
  _hi_check "The inner hi does not wrap again" test_mux_wrap_stands_down_inside_the_wrapped_session
  _hi_check "No tmux here: connect un-wrapped, with a warning" test_mux_wrap_connects_plain_without_tmux
  _hi_check "Outside tmux: exec new-session -A -s hi-<target>" test_mux_wrap_execs_new_session_A_named_for_the_target
  _hi_check "_HI_MUX=1 wraps without the flag" test_mux_setting_wraps_without_the_flag
  _hi_check "--no-mux beats _HI_MUX=1" test_no_mux_beats_the_setting
  _hi_check "Inside tmux: create detached, then switch-client" test_mux_wrap_inside_tmux_creates_then_switches
  _hi_check "The inner argv is the parsed state, quoted" test_mux_wrap_rebuilds_the_inner_argv_from_parsed_state
  _hi_suite_end "hi.sh (client-side tmux wrap)"
}
run_hi_mux_tests
