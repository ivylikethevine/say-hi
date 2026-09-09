#!/usr/bin/env bash
# tests/hi/mux_test.sh - the client-side tmux wrap: --mux, --no-mux, the
# session name a target maps to, and the tmux calls _hi_mux_wrap makes. tmux
# is a shim that logs its argv; one case behind a real tmux proves the name
# rule against the real thing. Sources hi.sh, which defines its functions and
# stops (the trailing dispatch is guarded), so nothing here connects.
#
# GLOSSARY: HI.30 + HI.34
# SC2016: the parsed-state strings are evaluated inside _hi_mux_run's subshell
# shellcheck disable=SC2329,SC2317,SC2030,SC2031,SC2016
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"
# shellcheck source=../../hi.sh
source "$_HI_LAUNCHER"

# _hi_mux_shim <log> [tools...] - a shim per multiplexer (tmux alone by
# default) that appends its argv to <log> under its own name in capitals.
# tmux's has-session says no, so the inside-tmux path has to create the
# session first; zellij's list-sessions answers with $_HI_TEST_ZSESSIONS, so a
# case can make the session "already running".
function _hi_mux_shim() {
  local log="$1" bin="$_HI_WORKDIR/muxbin" tool
  shift
  rm -rf "$bin"
  mkdir -p "$bin"
  for tool in "${@:-tmux}"; do
    cat >"$bin/$tool" <<SHIM
#!/bin/sh
printf '$(printf '%s' "$tool" | tr '[:lower:]' '[:upper:]') %s\\n' "\$*" >>"$log"
case "\$1" in
has-session) exit 1 ;;
list-sessions) printf '%s\\n' \${_HI_TEST_ZSESSIONS:-} ;;
esac
exit 0
SHIM
    chmod +x "$bin/$tool"
  done
  printf '%s' "$bin"
}

# _hi_mux_run <log> <inside: 0|1|tmux|screen|zellij> <parsed-state assignments>
# [tools...] - run the wrap in a subshell with the shims first on PATH, so its
# exec ends the subshell rather than the suite; the log is what the shims saw,
# then RETURNED if the wrap came back instead of exec'ing. <inside> names the
# multiplexer the client is already in (1 is tmux, for the older cases).
function _hi_mux_run() {
  local log="$1" inside="$2" state="$3" bin
  shift 3
  bin="$(_hi_mux_shim "$log" "$@")"
  : >"$log"
  (
    export PATH="$bin:$PATH"
    unset TMUX STY ZELLIJ
    case "$inside" in
    1 | tmux) export TMUX=/tmp/tmux-0/default,1,0 ;;
    screen) export STY=1234.pts-0.host ;;
    zellij) export ZELLIJ=0 ;;
    esac
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

# the target ends the options, and hi's own flag after it is refused by
# name rather than run on the far end as a command nobody has
function test_mux_flag_after_the_target_is_the_commands() {
  local out rc=0
  out="$( (_hi_parse myhost --mux 2>&1 >/dev/null) )" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--mux goes before the target"* ]]
}

# --no-mux is the per-connect way out of an `alias hi='hi --mux'`, and the last of the two
# flags wins; after the target it is refused like --mux
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
  local rc=0
  out="$( (_hi_parse myhost --no-mux 2>&1 >/dev/null) )" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--no-mux goes before the target"* ]]
}

function test_mux_wrap_is_a_no_op_without_the_flag() {
  local log="$_HI_WORKDIR/off.log" out
  out="$(_hi_mux_run "$log" 0 'MUX=0')"
  [ "$out" = RETURNED ]
}

# there is no setting behind the flag any more, so a stray _HI_MUX in the
# environment is a name hi does not read - the guard on the retirement
function test_mux_wrap_ignores_a_stray_setting() {
  local log="$_HI_WORKDIR/stray.log" out
  out="$(_hi_mux_run "$log" 0 'MUX=""; export _HI_MUX=1')"
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

# --- screen and zellij -----------------------------------------------------

# the first of tmux, zellij, screen on PATH - here tmux is absent from the
# shim dir and the real PATH is a toolbox without one
function test_mux_tool_picks_the_first_present_in_order() {
  local log="$_HI_WORKDIR/pick.log" out
  # shellcheck disable=SC2016 # evaluated in the subshell
  out="$(_hi_mux_run "$log" 0 'PATH="$bin:$(_hi_real_path muxpick sh sed cat printf grep)"' zellij screen)"
  case "$out" in "ZELLIJ list-sessions --short"*) ;; *) return 1 ;; esac
  case "$out" in *SCREEN*) return 1 ;; esac
}

function test_mux_screen_outside_execs_D_R_named_for_the_target() {
  local log="$_HI_WORKDIR/screen.log" out
  # shellcheck disable=SC2016 # evaluated in the subshell
  out="$(_hi_mux_run "$log" 0 'PATH="$bin:$(_hi_real_path muxonly sh sed cat printf grep)"' screen)"
  case "$out" in
  "SCREEN -D -R -S hi-myhost sh -c "*"_HI_MUX_INNER=1"*"$_HI_LAUNCHER"*"'myhost'"*) ;;
  *) return 1 ;;
  esac
  case "$out" in *RETURNED*) return 1 ;; esac
}

# inside a screen there is no client to switch: a new window in this session,
# and the wrap exits once it is made
function test_mux_screen_inside_opens_a_window_and_stops() {
  local log="$_HI_WORKDIR/screen-in.log" out
  # shellcheck disable=SC2016 # evaluated in the subshell
  out="$(_hi_mux_run "$log" screen 'PATH="$bin:$(_hi_real_path muxonly sh sed cat printf grep)"' screen)"
  [ "$(printf '%s\n' "$out" | grep -c '^SCREEN')" = 1 ] || return 1
  case "$out" in "SCREEN -t hi-myhost sh -c "*"'myhost'"*) ;; *) return 1 ;; esac
  case "$out" in *RETURNED*) return 1 ;; esac
}

# zellij starts a command from a layout file: the words of the inner argv,
# each a KDL string, in a pane that closes with the session
function test_mux_zellij_outside_writes_a_layout_and_starts_a_session() {
  local log="$_HI_WORKDIR/zellij.log" out layout
  # shellcheck disable=SC2016 # evaluated in the subshell
  out="$(_hi_mux_run "$log" 0 'PATH="$bin:$(_hi_real_path muxonly sh sed cat printf grep)"; RAWCMD="echo \"it'"'"'s\""' zellij)"
  case "$out" in
  *"ZELLIJ --session hi-myhost --new-session-with-layout "*) ;;
  *) return 1 ;;
  esac
  case "$out" in *RETURNED*) return 1 ;; esac
  layout="$(printf '%s\n' "$out" | sed -n 's/^ZELLIJ --session hi-myhost --new-session-with-layout //p')"
  [ -f "$layout" ] || return 1
  grep -q 'pane command="env" close_on_exit=true' "$layout" || return 1
  grep -q 'args "_HI_MUX_INNER=1" "'"$_HI_LAUNCHER"'" "myhost" "echo \\"it'"'"'s\\""' "$layout"
}

function test_mux_zellij_reattaches_a_running_session() {
  local log="$_HI_WORKDIR/zellij-re.log" out
  # shellcheck disable=SC2016 # evaluated in the subshell
  out="$(_hi_mux_run "$log" 0 'PATH="$bin:$(_hi_real_path muxonly sh sed cat printf grep)"; export _HI_TEST_ZSESSIONS=hi-myhost' zellij)"
  [ "$(printf '%s\n' "$out" | sed -n '1p')" = "ZELLIJ list-sessions --short" ] || return 1
  [ "$(printf '%s\n' "$out" | sed -n '2p')" = "ZELLIJ attach hi-myhost" ] || return 1
  case "$out" in *RETURNED*) return 1 ;; esac
}

function test_mux_zellij_inside_opens_a_tab_and_stops() {
  local log="$_HI_WORKDIR/zellij-in.log" out
  # shellcheck disable=SC2016 # evaluated in the subshell
  out="$(_hi_mux_run "$log" zellij 'PATH="$bin:$(_hi_real_path muxonly sh sed cat printf grep)"' zellij)"
  [ "$(printf '%s\n' "$out" | grep -c '^ZELLIJ')" = 1 ] || return 1
  case "$out" in "ZELLIJ action new-tab --name hi-myhost --layout "*) ;; *) return 1 ;; esac
  case "$out" in *RETURNED*) return 1 ;; esac
}

function test_kdl_quote_escapes_the_two_characters_kdl_reads() {
  local q
  _hi_kdl_quote q 'plain'
  [ "$q" = '"plain"' ] || return 1
  _hi_kdl_quote q 'a\b "c" $d'
  [ "$q" = '"a\\b \"c\" $d"' ]
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
  _hi_check "Without the flag, nothing happens" test_mux_wrap_is_a_no_op_without_the_flag
  _hi_check "A stray _HI_MUX=1 is not read" test_mux_wrap_ignores_a_stray_setting
  _hi_check "The inner hi does not wrap again" test_mux_wrap_stands_down_inside_the_wrapped_session
  _hi_check "No tmux here: connect un-wrapped, with a warning" test_mux_wrap_connects_plain_without_tmux
  _hi_check "Outside tmux: exec new-session -A -s hi-<target>" test_mux_wrap_execs_new_session_A_named_for_the_target
  _hi_check "Inside tmux: create detached, then switch-client" test_mux_wrap_inside_tmux_creates_then_switches
  _hi_check "The inner argv is the parsed state, quoted" test_mux_wrap_rebuilds_the_inner_argv_from_parsed_state
  _hi_h2 "Testing: screen and zellij"
  _hi_check "No setting: first of tmux, zellij, screen on PATH" test_mux_tool_picks_the_first_present_in_order
  _hi_check "screen, outside: exec screen -D -R -S hi-<target>" test_mux_screen_outside_execs_D_R_named_for_the_target
  _hi_check "screen, inside: a new window, then stop" test_mux_screen_inside_opens_a_window_and_stops
  _hi_check "zellij, outside: a layout file, then a new session" test_mux_zellij_outside_writes_a_layout_and_starts_a_session
  _hi_check "zellij: a running session is reattached" test_mux_zellij_reattaches_a_running_session
  _hi_check "zellij, inside: a new tab, then stop" test_mux_zellij_inside_opens_a_tab_and_stops
  _hi_check "_hi_kdl_quote escapes backslash and quote only" test_kdl_quote_escapes_the_two_characters_kdl_reads
  _hi_suite_end "hi.sh (client-side multiplexer wrap)"
}
run_hi_mux_tests
