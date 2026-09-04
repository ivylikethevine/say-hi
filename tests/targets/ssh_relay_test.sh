#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# End-to-end test that `hi` chains: from this machine (A, which has say-hi) to a
# throwaway sshd container (B, which does not), and then *from inside that
# session* on to a second one (C). What it establishes:
#
#   - the relay works from a **disposable** session at all. hi.sh rides the
#     payload tar (it is in $_HI_PAYLOAD), so it is unpacked to
#     "$_HI_ROOT/hi.sh" with its executable mode on both transports, and every
#     bash-capable session has a launcher - the `hi` alias paths.sh defines
#     points at a real file. The one tier that does not is the container
#     transport's bash-less fallback, which ships aliases.sh alone and never
#     sources paths.sh - there `hi` is simply undefined, not broken.
#   - the config lands intact on the *final* hop, not just the first.
#   - the cleanup traps fire on **both** B and C: on a clean exit, and on the
#     link being killed mid-relay, which is the case that can only be proven
#     from outside.
#
# B reaches C by container name over a private docker network; B gets the
# suite's throwaway private key and a one-host ssh config written in after it
# boots, so neither container needs an image of its own.
#
# Nearly every function below is invoked indirectly - by name, through
# _hi_case's/_hi_poll_bool's "$@", or as a feeder hook - which SC2329 can't
# see.
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

_HI_RELAY_NET=""
_HI_RELAY_B=""
_HI_RELAY_C=""
_HI_RELAY_OUT=""
_HI_TEST_MARKER="HI_RELAY_TEST_OK"

# The host alias B connects to C by. It is an ssh-config Host stanza rather
# than the container name on the command line, so the second hop exercises the
# same "name resolved through ~/.ssh/config" path a real relay would.
_HI_RELAY_HOST=relayc

# _hi_test_cleanup takes the containers down; the network can only go after
# them, hence a suite hook rather than a trap of its own. The thaw rides along
# because _hi_workdir takes one hook and this suite freezes processes too -
# an abort mid-kill must not leave a stopped ssh client behind.
# Also registered on the teardown ledger by _hi_relay_pair, which is what covers
# an abort; this is the eager path, so a finished case frees its network rather
# than leaving it for the trap.
function _hi_relay_cleanup() {
  _hi_thaw_frozen
  [ -n "${_HI_RELAY_NET:-}" ] || return 0
  docker network rm "$_HI_RELAY_NET" >/dev/null 2>&1 || true
  return 0
}

# Everything B needs to be a client: the private half of the suite's keypair,
# and a config naming C. Written after boot through `docker exec` rather than
# baked into an image, so this suite builds nothing the other ssh suites
# haven't already built.
function _hi_relay_arm_client() {
  docker exec -i -u root "$_HI_RELAY_B" sh -c '
    install -d -m 700 -o hitest -g hitest /home/hitest/.ssh
    cat > /home/hitest/.ssh/id
    chmod 600 /home/hitest/.ssh/id
    chown hitest:hitest /home/hitest/.ssh/id
  ' <"$_HI_WORKDIR/id" || return 1
  # StrictHostKeyChecking/UserKnownHostsFile: C is a container that has never
  # been seen before and will never be seen again, and hi opens this
  # connection non-interactively - an unanswerable host-key prompt would read
  # as "the relay is broken"
  docker exec -i -u root "$_HI_RELAY_B" sh -c "
    cat > /home/hitest/.ssh/config <<'CFG'
Host $_HI_RELAY_HOST
  HostName $_HI_RELAY_C
  User hitest
  IdentityFile ~/.ssh/id
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
CFG
    chmod 600 /home/hitest/.ssh/config
    chown hitest:hitest /home/hitest/.ssh/config
  " || return 1
}

# _hi_relay_pair <label> - boots C then B on one network, and arms B. Leaves B's
# mapped port in $_HI_SSH_PORT (the launcher below connects to it), which is why
# B is second.
#
# Every name carries the case label, not just $$: the two cases here run
# concurrently, and a network both of them called "hi-relaytest-net-$$" is one
# network - torn down by whichever case finished first, out from under the other.
# The network goes on the teardown ledger before it is created, like the
# containers, so an abort between the two does not leave it behind.
function _hi_relay_pair() {
  local label="$1"
  _HI_RELAY_NET="hi-relaytest-net-$label-$$"
  _hi_track_network "$_HI_RELAY_NET"
  docker network create "$_HI_RELAY_NET" >/dev/null 2>&1 ||
    _hi_stand_down "no docker network" "could not create a docker network, skipping"

  _HI_RELAY_C="hi-relaytest-c-$label-$$"
  _HI_RELAY_B="hi-relaytest-b-$label-$$"
  # ClientAlive on both, as ssh_disconnect_test.sh sets it: it is what reaps a
  # frozen client in seconds rather than hours, and the kill case needs it on
  # each hop - B to notice this machine, C to notice B
  local alive="SSHD_OPTS=-o ClientAliveInterval=2 -o ClientAliveCountMax=1"
  _hi_h2 "Booting the far end (C: $_HI_RELAY_C)"
  _hi_sshd_container "$_HI_RELAY_C" "$_HI_SSHD_IMAGE" \
    --network "$_HI_RELAY_NET" -e "$alive" || return 1
  _hi_h2 "Booting the middle (B: $_HI_RELAY_B)"
  _hi_sshd_container "$_HI_RELAY_B" "$_HI_SSHD_IMAGE" \
    --network "$_HI_RELAY_NET" -e "$alive" || return 1
  _hi_relay_arm_client || {
    _hi_cecho " | could not arm B as an ssh client" "$RED"
    return 1
  }
}

# How many sessions the transcript has seen come up, and how many have closed.
# Both counts are the point of this suite: one of each is the plain ssh case
# every other suite already covers, two is a relay.
#
# `grep -c` prints its 0 and *then* exits 1, so the count is kept and the
# status thrown away; the ${n:-0} covers the file not existing yet, where grep
# prints nothing at all and a bare [ "" -ge 2 ] would be a shell error rather
# than an answer.
function _hi_relay_count() {
  local n
  n="$(grep -c "$1" "$_HI_RELAY_OUT" 2>/dev/null || true)"
  [ "${n:-0}" -ge "$2" ]
}

function _hi_relay_sessions() { _hi_relay_count "$_HI_SESSION_LOADED_RE" "$1"; }
function _hi_relay_closings() { _hi_relay_count 'hi closing' "$1"; }

# What the far end has to say for itself: _hi_probe_cmd's `bash` shape - the
# shared statement of "hi's tree landed here and its aliases load" - with
# $(hostname) as the marker's own first field. Two things fall out of that
# one substitution:
#
#   - the line is echo-proof. A pty echoes what we type, so a marker typed
#     whole would satisfy its own grep; here the typed line carries the
#     literal `$(hostname)` and only the *output* carries C's name.
#   - and it is location-proof, which is the whole assertion: B is a hi
#     session too, so a marker that merely appeared proves nothing about
#     which hop produced it. C's hostname can only come from C.
# shellcheck disable=SC2016 # $(hostname) expands on C, which is the point
_HI_RELAY_PROOF='$(hostname)-CONFIG-OK'

# Typed into the live session on B by _hi_interactive_case's -f hook, after it
# has seen B's own marker come back. Each step waits on the transcript rather
# than sleeping: the second hop ships a payload over a fresh connection, and
# how long that takes is not something to guess at.
function _hi_relay_feeder() {
  printf 'hi %s\n' "$_HI_RELAY_HOST"
  _hi_poll_bool 120 0.5 _hi_relay_sessions 2 || true
  printf '%s\n' "$(_hi_probe_cmd "$_HI_RELAY_PROOF" bash)"
  printf 'exit\n'
  # C's session closing, before the outer exit goes anywhere near the pipe
  _hi_poll_bool 60 0.5 _hi_relay_closings 2 || true
}

# _hi_relay_clean <container> - no session tree and no bootloader dir left
# behind. Both halves matter: the tree is what the exit trap removes, the
# boot dir is what the client removes after the session, and a relay has to
# leave neither on either host.
function _hi_relay_clean() {
  ! docker exec "$1" sh -c 'ls -d /tmp/*.hi.* /tmp/hi.boot.* >/dev/null 2>&1'
}

function _hi_relay_report_leftovers() {
  local host
  for host in "$_HI_RELAY_B" "$_HI_RELAY_C"; do
    _hi_relay_clean "$host" && continue
    _hi_cecho " | [$1] -- $host still has a session tree:" "$RED"
    docker exec "$host" sh -c 'ls -d /tmp/*.hi.* /tmp/hi.boot.* 2>/dev/null' |
      sed 's/^/      /' || true
  done
}

# The clean-exit relay: A -> B -> C, the marker echoed on C, then out of both
# in turn. Asserted on the transcript (two sessions up, two closed, C's marker
# present) and then on both containers (nothing left behind).
function _hi_relay_case() {
  local ok=0 c_host
  # the fixtures this case owns - locals, so the case beside it owns its own
  local _HI_SSH_PORT="" _HI_RELAY_NET="" _HI_RELAY_B="" _HI_RELAY_C="" _HI_RELAY_OUT=""
  _hi_relay_pair relay || return 1
  _hi_ssh_launch "$_HI_SSH_PORT"
  _HI_RELAY_OUT="$_HI_WORKDIR/relay.interactive.out"
  # what $(hostname) will print on C - docker gives an unnamed container its
  # own short id, and that is the name the proof line has to come back with
  c_host="$(docker inspect -f '{{.Config.Hostname}}' "$_HI_RELAY_C")"

  # -m: the far end's proof, on top of B's own marker, which
  # _hi_interactive_case asserts for us
  if _hi_interactive_case -f _hi_relay_feeder -m "$c_host-CONFIG-OK" \
    relay "relay A -> B -> C" "$_HI_TEST_MARKER" 180 "${_HI_SSH_LAUNCH_BARE[@]}"; then
    ok=1
    if ! _hi_relay_sessions 2; then
      _hi_cecho " | [relay] -- only one session came up; C was never reached" "$RED"
      ok=0
    fi
    if ! _hi_relay_closings 2; then
      _hi_cecho " | [relay] -- only one session closed; C's load() never ran its exit path" "$RED"
      ok=0
    fi
    # the traps, on both hops. C's tree goes when C's session ends, B's when
    # B's does, and the suite has just watched both happen.
    if ! _hi_relay_clean "$_HI_RELAY_B" || ! _hi_relay_clean "$_HI_RELAY_C"; then
      _hi_relay_report_leftovers relay
      ok=0
    fi
  fi
  [ "$ok" -eq 1 ] || _hi_note_failure "[relay] clean-exit relay"
  _hi_rm_container "$_HI_RELAY_B"
  _hi_rm_container "$_HI_RELAY_C"
  _hi_relay_cleanup
  [ "$ok" -eq 1 ]
}

# The clean case proves the traps fire when both shells are asked to leave.
# This one proves they fire when nobody asks: the client and its mux master
# are frozen and killed while both hops are live, and *neither* host may keep
# its tree. C is the interesting half - its link only drops once B's shell has
# been reaped, so the trap it runs is two levels removed from what was killed.
#
# Command-shaped rather than interactive, like ssh_disconnect_test.sh: it is
# the same trap either way (it lives in _say_hi's remote preamble, not in
# load()), and a command-shaped session can print the tree it made and then
# sit still while the test does its work. The second hop goes through
# $_HI_LAUNCHER rather than the `hi` alias because alias *expansion* is off in
# a non-interactive shell - the alias itself is what the case above exercises.
function _hi_relay_b_dir() { _hi_ready_dir READY "$1"; }
function _hi_relay_c_dir() { _hi_ready_dir READYC "$1"; }

function _hi_relay_dirs_gone() {
  ! docker exec "$_HI_RELAY_B" test -d "$1" 2>/dev/null &&
    ! docker exec "$_HI_RELAY_C" test -d "$2" 2>/dev/null
}

function _hi_relay_disconnect_case() {
  local out_file b_dir c_dir launcher_pid ok=0
  local _HI_SSH_PORT="" _HI_RELAY_NET="" _HI_RELAY_B="" _HI_RELAY_C=""
  _hi_relay_pair relay-disconnect || return 1
  out_file="$_HI_WORKDIR/relay-disconnect.out"
  : >"$out_file"

  _hi_pty_wrap 0 force "no python3 to give the launcher its own pty - ssh will raw-mode this terminal and the test kills it before it can restore, expect garbled output afterwards"
  _hi_ssh_launch "$_HI_SSH_PORT"
  # Two levels of quoting, one per hop: $_HI_CLEANUP and $_HI_LAUNCHER expand
  # on B, and \$_HI_CLEANUP survives B to expand on C. The sleep has to outlast
  # every poll below by a wide margin - if it could expire inside the window,
  # the session would end on its own timer and the assertion would pass with
  # the disconnect having proved nothing.
  # shellcheck disable=SC2016 # every expansion here belongs to a target
  "${_HI_SSH_LAUNCH[@]}" \
    'echo READY:$_HI_CLEANUP; $_HI_LAUNCHER '"$_HI_RELAY_HOST"' "echo READYC:\$_HI_CLEANUP; sleep 600"' \
    </dev/null >"$out_file" 2>&1 &
  launcher_pid=$!

  # generous: this is two connects and two payload copies back to back
  b_dir="$(_hi_poll_value 120 0.5 _hi_relay_b_dir "$out_file")" || b_dir=""
  c_dir="$(_hi_poll_value 120 0.5 _hi_relay_c_dir "$out_file")" || c_dir=""
  if [ -z "$b_dir" ] || [ -z "$c_dir" ]; then
    _hi_dump_log "[relay-disconnect] -- the relay never came up (B: ${b_dir:-none}, C: ${c_dir:-none})" "$out_file"
    kill -9 "$launcher_pid" 2>/dev/null || true
    _hi_note_failure "[relay-disconnect] the relay never came up"
    return 1
  fi
  # both trees really exist before anything is killed, or "gone afterwards"
  # would be satisfied by their never having been there
  if ! docker exec "$_HI_RELAY_B" test -d "$b_dir" 2>/dev/null ||
    ! docker exec "$_HI_RELAY_C" test -d "$c_dir" 2>/dev/null; then
    _hi_cecho " | [relay-disconnect] -- a session tree was never created (B: $b_dir, C: $c_dir)" "$RED"
    kill -9 "$launcher_pid" 2>/dev/null || true
    _hi_note_failure "[relay-disconnect] no session tree to lose"
    return 1
  fi

  if ! _hi_freeze_session; then
    # it said why, in red, above
    _hi_note_failure "[relay-disconnect] nothing to freeze"
  else
    # B's sshd reaps the frozen client in ~4-6s (ClientAliveInterval=2,
    # CountMax=1); C's link then dies with B's shell, so C's trap runs a
    # beat later still - hence one budget covering both
    if _hi_poll_bool 120 0.5 _hi_relay_dirs_gone "$b_dir" "$c_dir"; then
      ok=1
      _hi_align " | [relay-disconnect] -- both hops cleaned up after the kill" "OK" "$GREEN"
    else
      _hi_relay_report_leftovers relay-disconnect
      _hi_note_failure "[relay-disconnect] a tree survived the kill"
    fi
  fi

  _hi_thaw_frozen
  _hi_wait_pid "$launcher_pid" 5
  _hi_rm_container "$_HI_RELAY_B"
  _hi_rm_container "$_HI_RELAY_C"
  _hi_relay_cleanup
  [ "$ok" -eq 1 ]
}

function run_relay_tests() {
  _hi_require_backend docker
  _hi_require pgrep

  _hi_workdir relaytest _hi_relay_cleanup
  _hi_h1 "Testing hi relayed: A -> B -> C"
  _hi_ssh_keypair
  _hi_sshd_image "the relay" || _hi_stand_down "sshd image build failed"

  _hi_pty_stdin auto "no tty and no python3 to fake one - results may be unreliable"

  # Two cases, two three-container fixtures, ~44s of a full run spent almost
  # entirely waiting on them - so they run together, each with its own network
  # and its own pair. The kill case finds the client it freezes by *port*
  # (_hi_ssh_client_pids), which is why the port had to become the case's.
  _hi_suite_begin
  _hi_par_begin "relay cases"
  _hi_h2 "A relay that ends the way it should, and one that is killed mid-session"
  _hi_par_case relay _hi_relay_case
  _hi_par_case relay-disconnect _hi_relay_disconnect_case
  _hi_par_wait
  _hi_suite_end "relay" \
    "hi relayed and left nothing on either hop ($_HI_TOTAL cases)" \
    "the relay FAILED: $_HI_FAILED/$_HI_TOTAL cases"
}

run_relay_tests
