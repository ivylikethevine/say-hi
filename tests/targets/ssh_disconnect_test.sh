#!/usr/bin/env bash
# End-to-end test that hi's ephemeral-target cleanup (_say_hi's `trap 'rm -rf
# $_HI_CLEANUP' exit`) survives an abrupt disconnect, not just a clean `exit`.
#
# Freezing the session takes *two* SIGSTOPs: _say_hi multiplexes over one
# connection, so a backgrounded ControlPersist master holds the socket beside
# the visible `ssh -t`, and it is the master that answers sshd's ClientAlive
# probes. Freeze only the client and sshd correctly keeps the session - that is
# a hung terminal, not a dead link. Hence _hi_ssh_mux_pids, and hence a missing
# master being a hard failure below.
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

function _hi_cleanup_dir_gone() {
  ! docker exec "$_HI_CONTAINER" test -d "$1" 2>/dev/null
}

function test_clean_exit_removes_cleanup_dir() {
  local out_file="$_HI_WORKDIR/clean.out" cleanup_dir

  _hi_pty_wrap 0 auto "no tty and no python3 to fake one - results may be unreliable"
  _hi_ssh_launch "$_HI_SSH_PORT"
  # shellcheck disable=SC2016 # $_HI_CLEANUP expands on the target, not here
  "${_HI_SSH_LAUNCH[@]}" 'echo READY:$_HI_CLEANUP' >"$out_file" 2>&1 || true

  cleanup_dir="$(_hi_ready_dir READY "$out_file")"
  [ -n "$cleanup_dir" ] || return 1
  ! docker exec "$_HI_CONTAINER" test -d "$cleanup_dir" 2>/dev/null
}

function test_sudden_disconnect_removes_cleanup_dir() {
  local out_file="$_HI_WORKDIR/disconnect.out" cleanup_dir launcher_pid ok=0
  : >"$out_file"

  _hi_pty_wrap 0 force "no python3 to give the launcher its own pty - ssh will raw-mode this terminal and the test kills it before it can restore, expect garbled output afterwards"
  _hi_ssh_launch "$_HI_SSH_PORT"
  # the remote sleep has to outlast every poll below by a wide margin: if it
  # can expire inside the window, the session ends on its own timer and the
  # assertion passes without the disconnect having proved anything
  # shellcheck disable=SC2016 # $_HI_CLEANUP expands on the target, not here
  "${_HI_SSH_LAUNCH[@]}" 'echo READY:$_HI_CLEANUP; sleep 600' </dev/null >"$out_file" 2>&1 &
  launcher_pid=$!

  # generous: this covers the whole connect + install-probe + tar copy of say-hi,
  # which is slow on a cold, small CI runner
  cleanup_dir="$(_hi_poll_value 60 0.5 _hi_ready_dir READY "$out_file")" || cleanup_dir=""
  if [ -z "$cleanup_dir" ] || ! docker exec "$_HI_CONTAINER" test -d "$cleanup_dir" 2>/dev/null; then
    if [ -z "$cleanup_dir" ]; then
      _hi_dump_log "session never printed READY:\$_HI_CLEANUP - it never came up" "$out_file"
    else
      _hi_cecho " | cleanup dir $cleanup_dir was never created on the target" "$RED"
    fi
    kill -9 "$launcher_pid" 2>/dev/null || true
    return 1
  fi

  # client *and* mux master - see _hi_freeze_session, which says why both
  if ! _hi_freeze_session; then
    kill -9 "$launcher_pid" 2>/dev/null || true
    return 1
  fi

  # sshd's ClientAliveInterval=2/ClientAliveCountMax=1 reaps a frozen client in
  # ~4-6s; the rest is headroom for a loaded runner
  _hi_poll_bool 60 0.5 _hi_cleanup_dir_gone "$cleanup_dir" && ok=1
  [ "$ok" -eq 1 ] || _hi_cecho " | $cleanup_dir survived the disconnect" "$RED"

  _hi_thaw_frozen
  _hi_wait_pid "$launcher_pid" 5

  [ "$ok" -eq 1 ]
}

function run_ssh_disconnect_test() {
  _hi_require_backend docker
  _hi_require pgrep

  _hi_workdir sshdisconnecttest _hi_thaw_frozen
  _hi_h1 "Testing hi's ssh cleanup trap survives an abrupt disconnect"
  _hi_ssh_keypair

  _hi_h2 "Building test image"
  _hi_sshd_image "this suite" || _hi_stand_down "sshd image build failed"

  _HI_CONTAINER="hi-sshdisconnecttest-$$"
  _hi_sshd_container "$_HI_CONTAINER" "$_HI_SSHD_IMAGE" \
    -e "SSHD_OPTS=-o ClientAliveInterval=2 -o ClientAliveCountMax=1" || exit 1

  _hi_suite_begin

  _hi_h2 "Cleanup on disconnect"
  _hi_check "Clean exit removes the cleanup dir" test_clean_exit_removes_cleanup_dir
  _hi_check "Sudden (frozen-connection) disconnect still removes it" test_sudden_disconnect_removes_cleanup_dir

  _hi_suite_end "" \
    "hi's ssh cleanup trap survived every case ($_HI_TOTAL cases)" \
    "hi's ssh cleanup trap FAILED: $_HI_FAILED/$_HI_TOTAL cases"
}

run_ssh_disconnect_test
