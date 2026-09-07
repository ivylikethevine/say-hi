#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# What hi actually puts on the wire, measured rather than computed. Two
# containers, one session each through a byte-counting ProxyCommand: a bare
# target, where the whole tree goes over, and one with say-hi already
# installed, where only the bootloader should. Each count is set against the
# figure hi prints on its connect line - the number _hi_wire_bytes computes,
# and what the README's payload badge tracks - so the claim is checked against
# reality on both ends of its range.
#
# The proxy sits between ssh and the socket, so it counts every byte of the
# SSH stream in each direction: key exchange, authentication, the install
# probe, the script carrying the armored payload, the session's own traffic.
# That is the true cost of a connection, and the assertion is that hi's
# figure is that cost minus a bounded, small overhead - if the overhead grows,
# something is being sent that the figure does not account for. The
# container's own eth0 counter is printed beside it (TCP/IP framing included)
# for the reader, not asserted: docker's port mapping sits between the two.
#
# Needs docker and a real ssh client, like every ssh-family suite; stands down
# yellow without them. Not parallel: two cases, and the counts read cleanest
# one at a time.
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

_HI_SSH_CASE_PREFIX=hi-wiretest

# The counting proxy. Threads pump stdin -> socket and socket -> stdout, each
# summing what it forwarded; the counts land in <prefix>.up and <prefix>.down
# (renamed into place, so a reader never sees a half-written file) once both
# directions have closed. The down pump gets ten seconds after the up pump
# ends: sshd closes the connection on the client's disconnect message, and a
# target that does not is a hang this proxy must not turn into.
#
# SIGHUP is ignored: ssh hangs up its ProxyCommand when the mux master exits
# (hi's own `ssh -O exit` after the session), and a proxy that died on it
# would take the counts with it. Everything it had forwarded by then is the
# whole connection, so the same close is what makes the pumps end normally.
_HI_WIRE_PROXY_PY='
import os, signal, socket, sys, threading
signal.signal(signal.SIGHUP, signal.SIG_IGN)
signal.signal(signal.SIGPIPE, signal.SIG_DFL)
host, port, prefix = sys.argv[1], int(sys.argv[2]), sys.argv[3]
sock = socket.create_connection((host, port))
counts = {"up": 0, "down": 0}

def write_all(fd, data):
    while data:
        n = os.write(fd, data)
        data = data[n:]

def up():
    while True:
        try:
            data = os.read(0, 65536)
        except OSError:
            data = b""
        if not data:
            break
        counts["up"] += len(data)
        try:
            sock.sendall(data)
        except OSError:
            break
    try:
        sock.shutdown(socket.SHUT_WR)
    except OSError:
        pass

def down():
    while True:
        try:
            data = sock.recv(65536)
        except OSError:
            data = b""
        if not data:
            break
        counts["down"] += len(data)
        try:
            write_all(1, data)
        except OSError:
            break
    try:
        os.close(1)
    except OSError:
        pass

t_up = threading.Thread(target=up, daemon=True)
t_down = threading.Thread(target=down, daemon=True)
t_up.start()
t_down.start()
t_up.join()
t_down.join(10)
for key in ("up", "down"):
    tmp = prefix + "." + key + ".tmp"
    with open(tmp, "w") as f:
        f.write("%d\n" % counts[key])
    os.rename(tmp, prefix + "." + key)
'

function _hi_wire_proxy_file() {
  printf '%s\n' "$_HI_WIRE_PROXY_PY" >"$_HI_WORKDIR/wire_proxy.py"
}

# _hi_wire_claim[_human] <probe> - the figure hi claims for the session the
# case is about to run, exact bytes and the human form the connect line prints:
# hi.sh's own functions, in a fresh bash so nothing of this suite's shell leaks
# into the assembled script.
#
# $DOMAIN and the remote command are the two details that change the script's
# length - the command rides it three times over, armored, once per fallback
# shell arm, and once more in the bootloader where it replaces `load`. So the
# claim is built from the case's own argv through _hi_parse, hi.sh's own
# splitter, rather than by setting $DOMAIN here and leaving $CMDARG unset:
# that measured an interactive session (which is what the badge and doctor
# ask for) while the case ran a command-shaped one, and the two round to
# different figures.
function _hi_wire_claim() {
  bash -c 'source "$1" && _hi_parse "$2" "$3" && _hi_wire_bytes' \
    bash "$_HI_LAUNCHER" hitest@127.0.0.1 "$1"
}
function _hi_wire_claim_human() {
  bash -c 'source "$1" && _hi_parse "$2" "$3" && _hi_wire_estimate' \
    bash "$_HI_LAUNCHER" hitest@127.0.0.1 "$1"
}

# The margin every figure in this suite is checked to, as a percentage. Nothing
# here is byte-stable: gzip jitter moves the payload a few dozen bytes run to
# run, and the connect line prints _hi_human_bytes' rounded form, which lands on
# a 1024 B step and turns a handful of bytes either side of it into a whole
# different string. So the checks below are numeric and bounded, never
# equalities - the same 5% the README badge's drift check allows, for the same
# reason. GLOSSARY: HI.44
_HI_WIRE_MARGIN=5

# _hi_wire_transcript_figure <transcript> - the size the connect line printed,
# in its human form ("48K"), or nothing when the line never appeared. It is the
# first figure in the session's output: hi prints " <size>" before the target
# has said anything, so the case's own marker and whatever the shell echoes
# after it cannot be read as the figure. The line is colored, with a reset
# between its leading space and the figure, so the escapes come off first.
function _hi_wire_transcript_figure() {
  _hi_strip_ansi "$(<"$1")" |
    grep -oE '(^| )[0-9]+(\.[0-9])?[BKMG]' | head -1 | tr -d ' '
}

# _hi_wire_figure_bytes <human> - "48K" back to bytes, so a printed figure can
# be compared with the claim as a number. The rounding is not undone (it
# cannot be): "48K" comes back as 49152, up to half a step from what was
# measured, which is well inside the margin above.
function _hi_wire_figure_bytes() {
  awk -v h="$1" 'BEGIN {
    n = h + 0
    u = index("BKMG", substr(h, length(h)))
    for (i = 1; i < u; i++) n *= 1024
    printf "%d", n
  }'
}

function _hi_wire_counted() {
  [ -s "$1.up" ] && [ -s "$1.down" ]
}

function _hi_wire_rx_bytes() {
  docker exec "$1" cat /sys/class/net/eth0/statistics/rx_bytes 2>/dev/null || echo 0
}

# _hi_wire_case <label> <image> <shape> - one measured session. <shape> is
# `payload` (a bare target: the tree goes over, and the count has to be the
# claim plus a bounded overhead) or `installed` (a permanent say-hi: hi loads
# it in place, and the count has to be a small fraction of the claim). Both
# also assert the session itself worked - a count of a failed connection
# measures nothing.
function _hi_wire_case() {
  local label="$1" image="$2" shape="$3" name counts out_file exit_code t0 t1 ok=1
  local up down rx0 rx1 claim human overhead limit probe floor printed printed_bytes
  local _HI_SSH_PORT=""
  # this suite's whole methodology is "the proxy writes its counts once the
  # connection closes, which is hi's own `ssh -O exit`" (below) - a shared,
  # persisted ControlMaster is exactly the opposite of that, so this case
  # forces hi back to a fresh socket closed at the end of the connect,
  # whatever the ambient default is. `-x`: hi.sh reads this from its own
  # environment, not this shell's variables, so a plain `local` would never
  # reach it
  local -x _HI_CTL_PERSIST=0

  name="$_HI_SSH_CASE_PREFIX-$label-$$"
  counts="$_HI_WORKDIR/$label.wire"
  _hi_h3 "Measuring: $label ($shape)"
  _hi_sshd_container "$name" "$image" -e LOGIN_SHELL=/bin/bash || return 1

  case "$shape" in
  payload) probe="$(_hi_probe_cmd "$_HI_TEST_MARKER" bash)" ;;
  installed) probe="$(_hi_probe_cmd "$_HI_TEST_MARKER" installed)" ;;
  esac

  claim="$(_hi_wire_claim "$probe")"
  human="$(_hi_wire_claim_human "$probe")"
  rx0="$(_hi_wire_rx_bytes "$name")"

  # the ProxyCommand rides in ahead of the target, where hi's parser hands
  # every -o to ssh; ControlMaster means the probe and the session share the
  # one connection this proxy carries, so its count is the whole cost
  out_file="$_HI_WORKDIR/$label.ssh.out"
  _hi_cecho " | Running: $_HI_LAUNCHER -p $_HI_SSH_PORT (through the counting proxy) hitest@127.0.0.1 $probe"
  t0="$(_hi_now)"
  # `<&3` pairs with _hi_pty_stdin in run_wire_tests, as in every ssh suite
  ${_HI_PTY_WRAP[@]+"${_HI_PTY_WRAP[@]}"} "$_HI_LAUNCHER" -p "$_HI_SSH_PORT" -i "$_HI_WORKDIR/id" \
    "${_HI_SSH_OPTS[@]}" -o ConnectTimeout=5 \
    -o "ProxyCommand=python3 $_HI_WORKDIR/wire_proxy.py %h %p $counts" \
    hitest@127.0.0.1 "$probe" <&3 >"$out_file" 2>&1 &
  _hi_wait_pid "$!" "${_HI_SSH_CASE_TIMEOUT:-90}"
  exit_code="$_HI_WAIT_EXIT"
  t1="$(_hi_now)"

  _hi_case_result "$label" "session through the proxy" "$exit_code" "$t0" "$t1" "$out_file" "$_HI_TEST_MARKER" || ok=0

  # the proxy writes its counts once the connection closes, which is hi's own
  # `ssh -O exit` on the mux master after the session - a moment after hi
  # itself has returned
  if ! _hi_poll_bool 40 0.25 _hi_wire_counted "$counts"; then
    _hi_cecho " | [$label] the proxy never reported its counts" "$RED"
    _hi_note_failure "[$label] no wire counts"
    _hi_rm_container "$name"
    return 1
  fi
  read -r up <"$counts.up"
  read -r down <"$counts.down"
  rx1="$(_hi_wire_rx_bytes "$name")"
  _hi_rm_container "$name"

  _hi_cecho " | client -> target $up B, target -> client $down B, target eth0 rx $((rx1 - rx0)) B" "$BLUE"
  _hi_cecho " | hi's figure for this target: $claim B ($human)" "$BLUE"

  case "$shape" in
  payload)
    # the claim has to be *in* the count, and what is in the count beyond the
    # claim - key exchange, auth, the install probe, per-packet MACs - has to
    # stay small: a fifth of the figure, or 12KB on a small payload, whichever
    # is more. Printed as a percentage, since that is how a reader will
    # compare two runs.
    overhead=$((up - claim))
    limit=$((claim / 5))
    [ "$limit" -lt 12288 ] && limit=12288
    _hi_cecho " | overhead beyond the figure: $overhead B ($((overhead * 100 / claim))% of it; limit $limit B)" "$BLUE"
    # the floor carries the margin, not an exact claim: see $_HI_WIRE_MARGIN
    floor=$((claim - claim * _HI_WIRE_MARGIN / 100))
    printed="$(_hi_wire_transcript_figure "$out_file")"
    printed_bytes="$(_hi_wire_figure_bytes "${printed:-0}")"
    _hi_cecho " | the connect line printed: ${printed:-(no figure)} ($printed_bytes B; within $_HI_WIRE_MARGIN% of $claim B?)" "$BLUE"
    _hi_assert "[$label] the wire carried at least the claimed script" [ "$up" -ge "$floor" ] || ok=0
    _hi_assert "[$label] the overhead beyond the claim is bounded" [ "$overhead" -le "$limit" ] || ok=0
    _hi_assert "[$label] the connect line's figure is within $_HI_WIRE_MARGIN% of the claim ($human)" \
      _hi_within_percent "$printed_bytes" "$claim" "$_HI_WIRE_MARGIN" || ok=0
    ;;
  installed)
    # no tree crosses: the bootloader, the probe and the handshake are all
    # there is, and that has to be a small fraction of what a bare target
    # costs - the point of finding an install in place
    limit=$((claim / 4))
    [ "$limit" -lt 16384 ] && limit=16384
    _hi_cecho " | a bare target would have cost $claim B; limit here $limit B" "$BLUE"
    _hi_assert "[$label] the session found the install in place" grep -qF 'local say-hi install' "$out_file" || ok=0
    _hi_assert "[$label] the wire carried a fraction of a bare target's cost" [ "$up" -le "$limit" ] || ok=0
    ;;
  esac
  [ "$ok" -eq 1 ]
}

function run_wire_tests() {
  _hi_require_backend docker
  [ "$_HI_PTY_OK" -eq 1 ] || _hi_stand_down "no python3 to run the counting proxy or drive a pty"

  _hi_workdir wiretest
  _hi_h1 "Measuring what hi puts on the wire, against the figure it prints"
  _hi_ssh_keypair
  _hi_wire_proxy_file

  _hi_h2 "Building test images"
  local debian_ok=1 installed_ok=0
  _hi_sshd_image "the bare-target measurement" || debian_ok=0
  # the repo itself is the build context: the working tree lands at ~/say-hi
  if [ "$debian_ok" -eq 1 ]; then
    _hi_build_image installed "$_HI_SSH_CASE_PREFIX-installed-$$" "the installed-target measurement" \
      --build-arg "BASE=$_HI_SSHD_IMAGE" \
      -f "$(_hi_dockerfile installed)" "$_HI_ROOT" && installed_ok=1
  fi
  [ "$debian_ok" -eq 1 ] || _hi_stand_down "the sshd image did not build"

  _HI_TEST_MARKER="HI_WIRE_TEST_OK"
  _hi_pty_stdin auto

  _hi_suite_begin
  _hi_case _hi_wire_case payload "$_HI_SSHD_IMAGE" payload
  if [ "$installed_ok" -eq 1 ]; then
    _hi_case _hi_wire_case installed "$_HI_SSH_CASE_PREFIX-installed-$$" installed
    docker rmi "$_HI_SSH_CASE_PREFIX-installed-$$" >/dev/null 2>&1 || true
  else
    _hi_skip "[installed] the installed image did not build"
  fi
  _hi_suite_end "wire measurement"
}

run_wire_tests
