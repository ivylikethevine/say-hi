#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Unit tests for hi.sh's transport over a container: the command shapes, the
# no-bash probe the --plain path reads, and _say_hi's boot ladder on a
# container arm.
#
# WHY THIS IS NOT AN E2E SUITE. tests/targets/docker_test.sh reaches this code
# through a real daemon, and reaches the happy path and "no writable temp
# directory" alone. The short landing, a missing base64, a refused path, and
# an exec that fails are transport failures nothing can provoke on a working
# container, and they are where the arm's error handling lives. So the
# backend here is a shim: `docker exec [-i|-it] <name> sh -c <script>` runs
# <script> locally with $TMPDIR pointed at a scratch tree standing in for the
# container's, and a handful of _HI_CT_* knobs make one call fail.
# Everything hi.sh does either side of that call is the real thing, including
# a real payload tar.
#
# The shim answers *only* the argv shapes hi.sh builds, and exits 1 on
# anything else - the discipline tests/lib/fixtures.sh's _hi_probe_shims uses,
# so a changed command shape fails here loudly instead of passing silently.
#
# GLOSSARY: HI.34. The linter follows hi.sh's trailing `_hi "$@"` and marks
# this file unreachable (SC2317); the single-quoted target-side words are the
# target's to expand (SC2016).
# shellcheck disable=SC2329,SC2317,SC2016
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"
# shellcheck source=../../hi.sh
source "$_HI_LAUNCHER"

# ---------------------------------------------------------------------------
# the shim
# ---------------------------------------------------------------------------

# _hi_ct_shim - a docker/podman on $PATH, into $_HI_CT_BIN. Written once and
# steered per case through the environment, so a case reads as the one knob it
# turns rather than as a second fixture.
#
#   _HI_CT_TMPDIR      the "container's" ${TMPDIR:-/tmp}
#   _HI_CT_PATH        the $PATH a script runs under there
#   _HI_CT_SHORT=<n>   the first <n> boots land 64 bytes of the script at most
#                      - the race the boot's byte check is for
#   _HI_CT_GONE=1      every exec fails as one into a container that is gone
#
# The boot is logged as `boot`. The attach - `sh <dir>/bootloader` - is logged
# with its script, its bootloader copied beside the log, and its directory
# removed as the real one does; it is not run, since it would hand over a
# session. A bare shell name is the --plain path's attach, logged alike.
function _hi_ct_shim() {
  _HI_CT_BIN="$_HI_WORKDIR/ctbin"
  mkdir -p "$_HI_CT_BIN"
  cat >"$_HI_CT_BIN/docker" <<'SHIM'
#!/bin/sh
case "$1" in
ps) exit 0 ;;
container)
  [ "$2 $3" = "inspect -f" ] || exit 1
  printf 'true\n'
  exit 0
  ;;
exec) shift ;;
*) exit 1 ;;
esac
while [ "$1" = -i ] || [ "$1" = -it ] || [ "$1" = -t ]; do shift; done
if [ "${_HI_CT_GONE:-0}" = 1 ]; then
  printf 'Error response from daemon: No such container: %s\n' "$1" >&2
  exit 1
fi
shift # the container name
if [ "$1" != sh ] || [ "$2" != -c ]; then
  printf 'attach:%s\n' "$*" >>"$_HI_CT_LOG"
  exit 0
fi
SH="$(command -v sh)"
script="$3"
case "$script" in
_HI_CONNECT_TIME=*)
  printf 'attach:%s\n' "$script" >>"$_HI_CT_LOG"
  dir="${script#*sh \"}"
  dir="${dir%%/bootloader\"*}"
  cp "$dir/bootloader" "$_HI_CT_LOG.landed"
  rm -rf "$dir"
  exit 0
  ;;
*'cat > "$d/bootloader"'*)
  printf 'boot\n' >>"$_HI_CT_LOG"
  if [ "$(grep -c '^boot$' "$_HI_CT_LOG")" -le "${_HI_CT_SHORT:-0}" ]; then
    # dd rather than head -c, which OpenBSD's head lacks
    dd bs=64 count=1 2>/dev/null | PATH="${_HI_CT_PATH:-$PATH}" TMPDIR="$_HI_CT_TMPDIR" "$SH" -c "$script"
    exit $?
  fi
  ;;
esac
PATH="${_HI_CT_PATH:-$PATH}" TMPDIR="$_HI_CT_TMPDIR" exec "$SH" -c "$script"
SHIM
  cp "$_HI_CT_BIN/docker" "$_HI_CT_BIN/podman"
  chmod +x "$_HI_CT_BIN/docker" "$_HI_CT_BIN/podman"
}

# _hi_ct_run <slug> [NAME=VALUE...] - one interactive-shaped _say_hi docker
# run against a scratch tree of its own, its stderr into $_HI_CT_ERR, the
# exec's words into $_HI_CT_ERRLOG, and its exit status into $_HI_CT_RC.
# DOMAIN and the tree are per-case so no two share a root.
function _hi_ct_run() {
  local slug="$1"
  shift
  local case_dir="$_HI_WORKDIR/ct.$slug"
  mkdir -p "$case_dir/tmp"
  _HI_CT_ERR="$case_dir/err"
  _HI_CT_ERRLOG="$case_dir/errlog"
  _HI_CT_LOG="$case_dir/log"
  : >"$_HI_CT_LOG"
  : >"$_HI_CT_ERRLOG"
  _HI_CT_RC=0
  DOMAIN="ct-$slug" \
    env PATH="$_HI_CT_BIN:$PATH" _HI_CT_TMPDIR="$case_dir/tmp" \
    _HI_CT_LOG="$_HI_CT_LOG" "$@" \
    bash -c '
      set -uo pipefail
      source "$_HI_LAUNCHER"
      CMDARG="" KEEP=""
      _say_hi docker "$1"
    ' -- "$_HI_CT_ERRLOG" 2>"$_HI_CT_ERR" </dev/null || _HI_CT_RC=$?
}

# A miss prints what the case *did* say. The harness reports a bare label and
# nothing else (tests/lib/fixtures.sh's _hi_assert), so on a runner nobody can
# reach a shell on - the Windows and macOS jobs - the captured stderr is the
# only evidence a red case leaves, and dropping it makes one undebuggable.
function _hi_ct_said() {
  grep -qF -e "$1" "$_HI_CT_ERR" && return 0
  {
    printf ' _hi_ct_said: rc=%s, no "%s" in:\n' "$_HI_CT_RC" "$1"
    sed 's/^/ | /' "$_HI_CT_ERR"
  } >&2
  return 1
}

# _hi_ct_said's twin over the shim's log, for the cases whose assertion is
# what the boot and the attach looked like
function _hi_ct_logged() {
  grep -q "$1" "$_HI_CT_LOG" && return 0
  {
    printf ' _hi_ct_logged: rc=%s, no /%s/ in:\n' "$_HI_CT_RC" "$1"
    sed 's/^/ | /' "$_HI_CT_LOG"
    sed 's/^/ | stderr: /' "$_HI_CT_ERR"
  } >&2
  return 1
}

# _hi_ct_boots <n> - the boot ran <n> times
function _hi_ct_boots() {
  local n
  n="$(grep -c '^boot$' "$_HI_CT_LOG" || true)"
  [ "$n" = "$1" ] || _hi_because "$n boots, not $1: $(cat "$_HI_CT_LOG")"
}

# ---------------------------------------------------------------------------
# _hi_transport_cmds - the probe/cp/attach shapes, per backend
# ---------------------------------------------------------------------------

# Every case runs with no terminal on stdin (the runner's suites do), which is
# the `-i` half of the -i/-it split: `docker exec -it` with stdin on a pipe
# refuses outright rather than degrading, so this is the shape that matters
# for `hi <container> <cmd> | ...`.
function _hi_ct_cmds() {
  local DOMAIN="$1" label="$2"
  local -a probe cp attach ctl_opts=() SSHARGS=()
  _hi_transport_cmds "$label"
  printf 'probe=%s\ncp=%s\nattach=%s\n' "${probe[*]}" "${cp[*]}" "${attach[*]}"
}

function test_cmds_docker_uses_docker_exec() {
  local out
  out="$(PATH="$_HI_CT_BIN:$PATH" _hi_ct_cmds mybox docker)"
  [ "$out" = "probe=docker exec mybox
cp=docker exec -i mybox
attach=docker exec -i mybox" ] || _hi_why out
}

# the CLI is the arm's own name and the grammar is docker's (GLOSSARY: HI.51)
function test_cmds_podman_is_a_drop_in_for_docker() {
  local out
  out="$(PATH="$_HI_CT_BIN:$PATH" _hi_ct_cmds mybox podman)"
  [ "$out" = "probe=podman exec mybox
cp=podman exec -i mybox
attach=podman exec -i mybox" ] || _hi_why out
}

# nomad wants -i/-t spelled out either way: its stdin-is-a-tty guess lands
# wrong on a wrapped pty and hangs the exec
function test_cmds_nomad_spells_out_both_flags() {
  local out
  out="$(_hi_ct_cmds alloc123 nomad)"
  [ "$out" = "probe=nomad alloc exec -i=false -t=false alloc123
cp=nomad alloc exec -i=true -t=false alloc123
attach=nomad alloc exec -i=true -t=false alloc123" ] || _hi_why out
}

function test_cmds_nomad_names_the_task_when_one_is_given() {
  local out
  out="$(_hi_ct_cmds alloc123/web nomad)"
  case "$out" in
  "probe=nomad alloc exec -task web -i=false -t=false alloc123"*) ;;
  *) _hi_why -3 out || return 1 ;;
  esac
}

function test_cmds_kube_ends_every_shape_with_a_double_dash() {
  local out
  out="$(_hi_ct_cmds mypod kube)"
  [ "$out" = "probe=kubectl exec mypod --
cp=kubectl exec -i mypod --
attach=kubectl exec -i mypod --" ] || _hi_why out
}

function test_cmds_kube_names_the_container_when_one_is_given() {
  local out
  out="$(_hi_ct_cmds mypod/side kube)"
  case "$out" in
  "probe=kubectl exec mypod -c side --"*) ;;
  *) _hi_why -3 out || return 1 ;;
  esac
}

# ssh's three are one connection's: no stdin for the probe, none of the
# ControlMaster's options missing from any
function test_cmds_ssh_rides_the_control_master() {
  local out
  out="$(
    local DOMAIN=box
    local -a probe cp attach ctl_opts=(-o ControlPath=/s) SSHARGS=(-p 22)
    _hi_transport_cmds ssh
    printf 'probe=%s\ncp=%s\nattach=%s\n' "${probe[*]}" "${cp[*]}" "${attach[*]}"
  )"
  [ "$out" = "probe=ssh -n -o ControlPath=/s -p 22 box
cp=ssh -o ControlPath=/s -p 22 box
attach=ssh -o ControlPath=/s -p 22 box" ] || _hi_why out
}

# ---------------------------------------------------------------------------
# _hi_container_fallback_shell - a word read back from the container
# ---------------------------------------------------------------------------

# the probe stands in for the container: whatever word the case wants, back
# through the same channel the real one uses
function _hi_ct_word() {
  local w="$_HI_WORKDIR/echoword"
  cat >"$w" <<'EOF'
#!/bin/sh
printf '%s' "$1"
EOF
  chmod +x "$w"
  printf '%s' "$w"
}

# test_fallback_shell_answer <answer> [expected] - checked against the fixed
# list of right answers rather than sanitized: a word off the ladder did not
# come from the probe, and a busybox echo with a mind of its own (or a shell
# that wrote something extra on the way past) is one word or it is nothing
function test_fallback_shell_answer() {
  local got
  local -a probe
  probe=("$(_hi_ct_word)" "$1")
  got="$(_hi_container_fallback_shell)"
  [ "$got" = "${2-}" ] || _hi_why got
}

# ---------------------------------------------------------------------------
# _say_hi over a container
# ---------------------------------------------------------------------------

# One boot and one attach, the attach the script's own `sh <dir>/bootloader`
# and the removal after it; what landed is the script an ssh target gets -
# the preamble, the kept session's reattach, the bash handoff, and the no-bash
# ladder - whole, since the boot checked its bytes.
function test_say_hi_boots_once_and_attaches_once() {
  local landed
  _hi_ct_run ok
  [ "$_HI_CT_RC" = 0 ] || _hi_why _HI_CT_RC _HI_CT_ERR || return 1
  _hi_ct_boots 1 || return 1
  _hi_ct_logged '^attach:_HI_CONNECT_TIME=[0-9.]* sh ".*/hi\.boot\.[A-Za-z0-9]*/bootloader"; _hi_e=\$?; rm -rf ".*"; exit \$_hi_e$' || return 1
  landed="$(cat "$_HI_CT_LOG.landed")"
  [[ "$landed" == *'_hi_t0=$(_hi_now)'* && "$landed" == *'_hi_kept()'* &&
    "$landed" == *'bash --rcfile "$_hi_rc_dir/hi.bashrc" -i'* &&
    "$landed" == *'no bash on [%s]'* ]] || _hi_because "the script that landed: ${landed:0:400}" || return 1
  local left
  for left in "$_HI_WORKDIR"/ct.ok/tmp/hi.boot.*; do
    [ ! -e "$left" ] || _hi_because "the boot directory stayed: $left" || return 1
  done
}

# a landing short of the script is tried again, and the session goes on
function test_say_hi_retries_a_short_landing() {
  _hi_ct_run short _HI_CT_SHORT=2
  { [ "$_HI_CT_RC" = 0 ] && _hi_ct_boots 3 && _hi_ct_logged '^attach:_HI_CONNECT_TIME='; } || _hi_why _HI_CT_RC
}

# ...three times, and then the container's own shell, said
function test_say_hi_hands_over_after_three_short_landings() {
  _hi_ct_run shorter _HI_CT_SHORT=9
  { _hi_ct_boots 3 && _hi_ct_said "hi's script reached [ct-shorter] short, three times over - handing over" &&
    _hi_ct_logged '^attach:bash$'; } || _hi_why _HI_CT_RC
}

# nowhere to make the boot directory: said, and the container's own shell. A
# regular file rather than a /proc path: mktemp has to fail for the same
# reason everywhere, and /proc is Linux's alone.
function test_say_hi_no_writable_temp_directory() {
  printf 'not a directory\n' >"$_HI_WORKDIR/ct.notmp.file"
  _hi_ct_run notmp "_HI_CT_TMPDIR=$_HI_WORKDIR/ct.notmp.file"
  { _hi_ct_said "no writable temp directory on [ct-notmp] - handing over" &&
    _hi_ct_logged '^attach:bash$'; } || _hi_why _HI_CT_RC
}

# no base64 or openssl: nothing to unarmor the tree with, and the plain path
# lands in the best shell of the ladder
function test_say_hi_no_armor_hands_over_the_ladder_shell() {
  local path
  path="$(_hi_real_path ct-noarmor sh mktemp cat wc rm)"
  _hi_ct_run noarmor "_HI_CT_PATH=$path"
  { _hi_ct_said "no base64 or openssl on [ct-noarmor] - handing over" &&
    _hi_ct_logged '^attach:sh$'; } || _hi_why _HI_CT_RC path
}

# the path comes back from the target and is interpolated into every command
# run there, so it is refused rather than escaped. A comma rather than a
# semicolon: both are outside _hi_safe_path's class, which is the whole
# assertion, but MSYS rewrites an argument that looks like a `;`-joined path
# list and would answer a different question under Git Bash.
function test_say_hi_refuses_a_scratch_path_it_will_not_use() {
  mkdir -p "$_HI_WORKDIR/ct.badroot/od,ir"
  _hi_ct_run badroot "_HI_CT_TMPDIR=$_HI_WORKDIR/ct.badroot/od,ir"
  { _hi_ct_said "named a scratch directory hi will not use" &&
    ! grep -q '^attach:_HI_CONNECT_TIME=' "$_HI_CT_LOG"; } || _hi_why _HI_CT_RC
}

# an exec that fails outright reached nothing: no attach, the exec's own words
# kept for the report, and a failing status
function test_say_hi_keeps_a_failed_exec_s_words() {
  _hi_ct_run gone _HI_CT_GONE=1
  { [ "$_HI_CT_RC" != 0 ] && grep -q 'No such container: ct-gone' "$_HI_CT_ERRLOG" &&
    ! grep -q '^attach:' "$_HI_CT_LOG"; } || _hi_why _HI_CT_RC _HI_CT_ERRLOG
}

function run_container_tests() {
  _hi_h1 "Testing hi.sh's transport over a container"
  _hi_workdir hicontainer
  _hi_suite_begin
  _hi_ct_shim

  _hi_h2 "Testing: _hi_transport_cmds"
  _hi_check "docker: docker exec" test_cmds_docker_uses_docker_exec
  _hi_check "podman is a drop-in" test_cmds_podman_is_a_drop_in_for_docker
  _hi_check "nomad spells out -i and -t" test_cmds_nomad_spells_out_both_flags
  _hi_check "nomad names the task" test_cmds_nomad_names_the_task_when_one_is_given
  _hi_check "kube ends every shape with --" test_cmds_kube_ends_every_shape_with_a_double_dash
  _hi_check "kube names the container" test_cmds_kube_names_the_container_when_one_is_given
  _hi_check "ssh rides the ControlMaster" test_cmds_ssh_rides_the_control_master

  _hi_h2 "Testing: _hi_container_fallback_shell"
  _hi_check "Takes a ladder name" test_fallback_shell_answer sh sh
  _hi_check "Rejects a word off the ladder" test_fallback_shell_answer bogusshell
  _hi_check "Rejects a word with extra output" test_fallback_shell_answer "sh and then some"
  _hi_check "Rejects an empty answer" test_fallback_shell_answer ""

  _hi_h2 "Testing: _say_hi over a container"
  _hi_check "Boots once, attaches once, ssh's script" test_say_hi_boots_once_and_attaches_once
  _hi_check "Retries a short landing" test_say_hi_retries_a_short_landing
  _hi_check "Hands over after three short landings" test_say_hi_hands_over_after_three_short_landings
  _hi_check "No writable temp directory" test_say_hi_no_writable_temp_directory
  _hi_check "No armor: the ladder's shell" test_say_hi_no_armor_hands_over_the_ladder_shell
  _hi_check "Refuses a scratch path it will not use" test_say_hi_refuses_a_scratch_path_it_will_not_use
  _hi_check "Keeps a failed exec's words" test_say_hi_keeps_a_failed_exec_s_words

  _hi_suite_end "hi.sh container transport"
}

run_container_tests
