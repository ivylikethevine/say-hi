#!/usr/bin/env bash
# tests/hi/mux_test.sh - the session name a target maps to, which a kept
# session is found by (GLOSSARY: HI.65): one case behind a real tmux proves
# the name rule against the real thing. And the flag that once wrapped a
# connect in a local multiplexer is a stranger now. Sources hi.sh, which
# defines its functions and stops (the trailing dispatch is guarded), so
# nothing here connects.
#
# GLOSSARY: HI.30 + HI.34
# SC2016: the KDL case quotes a dollar on purpose
# shellcheck disable=SC2329,SC2317,SC2030,SC2031,SC2016
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"
# shellcheck source=../../hi.sh
source "$_HI_LAUNCHER"

# the client's username, whose hash ends every name: pinned, and $_HI_MUX_KEY
# is what the cases expect after the target
_HI_LOCAL_USER=me
_hi_hash me _HI_MUX_KEY
printf -v _HI_MUX_KEY '%x' "$_HI_MUX_KEY"

function test_mux_name_drops_what_tmux_rejects() {
  local out got got2
  for out in "$(_hi_mux_name user@host)" "$(_hi_mux_name ctx:ns:pod/ctr)" "$(_hi_mux_name 'db.example.com')"; do
    case "$out" in hi-*) ;; *) _hi_why out || return 1 ;; esac
    case "$out" in *[:./@]*) _hi_why out || return 1 ;; esac
  done
  got="$(_hi_mux_name ctx:ns:pod/ctr)"
  got2="$(_hi_mux_name user@host)"
  [ "$got" = "hi-ctx-ns-pod-ctr-$_HI_MUX_KEY" ] && [ "$got2" = "hi-user-host-$_HI_MUX_KEY" ] || _hi_why got got2
}

# the key is the client's username and nothing else: another user's name
# differs, the same user's from another machine does not, and the username
# itself is not in it
function test_mux_name_keys_on_the_client_s_user() {
  local mine theirs elsewhere
  mine="$(_hi_mux_name host)"
  theirs="$(_HI_LOCAL_USER=them _hi_mux_name host)"
  elsewhere="$(_HI_LOCAL_HOSTNAME=other _hi_mux_name host)"
  [ "$mine" != "$theirs" ] && [ "$mine" = "$elsewhere" ] || _hi_why mine theirs elsewhere || return 1
  case "$mine" in *me*) _hi_because "the username is spelled out: $mine" ;; esac
}

function test_mux_name_is_a_session_name_tmux_accepts() {
  local sock="$_HI_WORKDIR/tmux.sock" name
  name="$(_hi_mux_name 'ctx:ns:pod/ctr')"
  tmux -S "$sock" new-session -d -s "$name" true || _hi_why sock name || return 1
  tmux -S "$sock" kill-server 2>/dev/null || true
}

function test_mux_flags_are_unknown_options() {
  local flag out rc
  for flag in --mux --no-mux; do
    rc=0
    out="$( (_hi_parse "$flag" myhost 2>&1 >/dev/null) )" || rc=$?
    [ "$rc" -eq 1 ] && [[ "$out" == *"hi: unknown option $flag"* ]] || _hi_because "$flag: $rc, $out" || return 1
  done
}

function run_hi_mux_tests() {
  _hi_workdir himuxtest
  _hi_suite_begin
  _hi_h1 "Testing hi.sh: the session name"
  _hi_h2 "Testing: the session name"
  _hi_check_eq "A plain host is hi-<host>-<id>" "hi-host-$_HI_MUX_KEY" _hi_mux_name host
  _hi_check "Characters tmux rejects become dashes" test_mux_name_drops_what_tmux_rejects
  _hi_check "The key is the client's username, hashed" test_mux_name_keys_on_the_client_s_user
  _hi_check_requires tmux "tmux accepts the name" test_mux_name_is_a_session_name_tmux_accepts
  _hi_check "--mux and --no-mux are unknown options" test_mux_flags_are_unknown_options
  _hi_suite_end "hi.sh (session name)"
}
run_hi_mux_tests
