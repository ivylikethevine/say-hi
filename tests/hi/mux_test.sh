#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
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

function test_mux_name_drops_what_tmux_rejects() {
  local out
  for out in "$(_hi_mux_name user@host)" "$(_hi_mux_name ctx:ns:pod/ctr)" "$(_hi_mux_name 'db.example.com')"; do
    case "$out" in hi-*) ;; *) return 1 ;; esac
    case "$out" in *[:./@]*) return 1 ;; esac
  done
  [ "$(_hi_mux_name ctx:ns:pod/ctr)" = hi-ctx-ns-pod-ctr ] &&
    [ "$(_hi_mux_name user@host)" = hi-user-host ]
}

function test_mux_name_is_a_session_name_tmux_accepts() {
  local sock="$_HI_WORKDIR/tmux.sock" name
  name="$(_hi_mux_name 'ctx:ns:pod/ctr')"
  tmux -S "$sock" new-session -d -s "$name" true || return 1
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
  _hi_h1 "Testing hi.sh: the session name"
  _hi_h2 "Testing: the session name"
  _hi_check_eq "A plain host is hi-<host>" hi-host _hi_mux_name host
  _hi_check "Characters tmux rejects become dashes" test_mux_name_drops_what_tmux_rejects
  _hi_check_requires tmux "tmux accepts the name" test_mux_name_is_a_session_name_tmux_accepts
  _hi_check "--mux and --no-mux are unknown options" test_mux_flags_are_unknown_options
  _hi_check "_hi_kdl_quote escapes backslash and quote only" test_kdl_quote_escapes_the_two_characters_kdl_reads
  _hi_suite_end "hi.sh (session name)"
}
run_hi_mux_tests
