#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Unit tests for hi.sh's container arm - the command shapes, the three helpers
# that read their caller's scope, and _say_hi_container's failure ladder.
#
# WHY THIS IS NOT AN E2E SUITE. tests/targets/docker_test.sh reaches this code
# through a real daemon, and reaches exactly one of the ladder's eight
# _hi_fail arms - the happy path plus "no writable temp directory". The other
# seven are transport failures nothing can provoke on a working container, and
# they are where the arm's error handling actually lives. So the backend here
# is a shim: `docker exec [-i|-it] <name> <cmd...>` runs <cmd> locally with
# $TMPDIR pointed at a scratch tree standing in for the container's, and a
# handful of _HI_CT_* knobs make one specific call fail. Everything hi.sh does
# either side of that call is the real thing, including a real payload tar.
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
#   _HI_CT_NO_BASH=1   `command -v bash` finds nothing there
#   _HI_CT_LADDER      what the ladder probe echoes back, verbatim
#   _HI_CT_PUT_FAIL    a `cat > '<path>'` naming a path with this in it writes
#                      nothing - the transport race _hi_container_put retries
#   _HI_CT_CP_FAIL=1   the `cp` of the fallback rc onto .zshrc fails
#   _HI_CT_TAR_FAIL=1  the payload's `tar mxzf` fails
#
# An `exec `-bearing script, a bare shell name, or `fish -C` is the *attach* -
# the session hi would hand over - and is a no-op that records it happened:
# running it for real would block on a terminal that is not there.
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
shift # the container name

# a bare shell name is the attach - the session hi would hand over. Anything
# else that is not `sh -c`/`cat` is an ordinary command (the cleanup's rm),
# logged apart so a case can tell the two apart.
case "$1" in
sh | ash | dash | zsh | fish | bash)
  if [ "$1" != sh ] || [ "$2" != -c ]; then
    printf '%s\n' "attach:$*" >>"$_HI_CT_LOG"
    exit 0
  fi
  ;;
cat) TMPDIR="$_HI_CT_TMPDIR" exec cat "$2" ;;
*)
  printf '%s\n' "cmd:$*" >>"$_HI_CT_LOG"
  exit 0
  ;;
esac

script="$3"
printf '%s\n' "sh:$script" >>"$_HI_CT_LOG"
case "$script" in
*"exec "*)
  printf '%s\n' "attach:$script" >>"$_HI_CT_LOG"
  exit 0
  ;;
esac
case "$script" in
"command -v bash") [ "${_HI_CT_NO_BASH:-0}" = 1 ] && exit 1 ;;
esac
case "$script" in
*'echo "$_hi_s"'*)
  [ -n "${_HI_CT_LADDER:-}" ] && {
    printf '%s' "$_HI_CT_LADDER"
    exit 0
  }
  ;;
esac
case "$script" in
cp\ *) [ "${_HI_CT_CP_FAIL:-0}" = 1 ] && exit 1 ;;
esac
case "$script" in
*'tar -x -m -z -f - -C'*) [ "${_HI_CT_TAR_FAIL:-0}" = 1 ] && exit 1 ;;
esac
case "${_HI_CT_PUT_FAIL:-}" in
"") ;;
*)
  case "$script" in
  "cat > "*"$_HI_CT_PUT_FAIL"*)
    cat >/dev/null
    exit 0
    ;;
  esac
  ;;
esac
TMPDIR="$_HI_CT_TMPDIR" exec sh -c "$script"
SHIM
  cp "$_HI_CT_BIN/docker" "$_HI_CT_BIN/podman"
  chmod +x "$_HI_CT_BIN/docker" "$_HI_CT_BIN/podman"
}

# _hi_ct_run <slug> [NAME=VALUE...] - one _say_hi_container docker run against
# a scratch tree of its own, its stderr into $_HI_CT_ERR and its exit status
# into $_HI_CT_RC. DOMAIN and the tree are per-case so no two share a root.
function _hi_ct_run() {
  local slug="$1"
  shift
  local case_dir="$_HI_WORKDIR/ct.$slug"
  mkdir -p "$case_dir/tmp"
  _HI_CT_ERR="$case_dir/err"
  _HI_CT_LOG="$case_dir/log"
  : >"$_HI_CT_LOG"
  _HI_CT_RC=0
  DOMAIN="ct-$slug" \
    env PATH="$_HI_CT_BIN:$PATH" _HI_CT_TMPDIR="$case_dir/tmp" \
    _HI_CT_LOG="$_HI_CT_LOG" "$@" \
    bash -c '
      set -uo pipefail
      source "$_HI_LAUNCHER"
      _say_hi_container docker "$1"
    ' -- "$case_dir/errlog" 2>"$_HI_CT_ERR" || _HI_CT_RC=$?
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

# _hi_ct_said's twin over the shim's log, for the cases whose whole assertion
# is "the attach hi handed over looked like this"
function _hi_ct_logged() {
  grep -q "$1" "$_HI_CT_LOG" && return 0
  {
    printf ' _hi_ct_logged: rc=%s, no /%s/ in:\n' "$_HI_CT_RC" "$1"
    sed 's/^/ | /' "$_HI_CT_LOG"
  } >&2
  return 1
}

# ---------------------------------------------------------------------------
# _hi_container_cmds - the probe/cp/attach shapes, per backend
# ---------------------------------------------------------------------------

# Every case runs with no terminal on stdin (the runner's suites do), which is
# the `-i` half of the -i/-it split: `docker exec -it` with stdin on a pipe
# refuses outright rather than degrading, so this is the shape that matters
# for `hi <container> <cmd> | ...`.
function _hi_ct_cmds() {
  local DOMAIN="$1" label="$2"
  local -a probe cp attach
  _hi_container_cmds "$label"
  printf 'probe=%s\ncp=%s\nattach=%s\n' "${probe[*]}" "${cp[*]}" "${attach[*]}"
}

function test_cmds_docker_uses_docker_exec() {
  local out
  out="$(PATH="$_HI_CT_BIN:$PATH" _hi_ct_cmds mybox docker)"
  [ "$out" = "probe=docker exec mybox
cp=docker exec -i mybox
attach=docker exec -i mybox" ]
}

# the CLI is the arm's own name and the grammar is docker's (GLOSSARY: HI.51)
function test_cmds_podman_is_a_drop_in_for_docker() {
  local out
  out="$(PATH="$_HI_CT_BIN:$PATH" _hi_ct_cmds mybox podman)"
  [ "$out" = "probe=podman exec mybox
cp=podman exec -i mybox
attach=podman exec -i mybox" ]
}

# nomad wants -i/-t spelled out either way: its stdin-is-a-tty guess lands
# wrong on a wrapped pty and hangs the exec
function test_cmds_nomad_spells_out_both_flags() {
  local out
  out="$(_hi_ct_cmds alloc123 nomad)"
  [ "$out" = "probe=nomad alloc exec -i=false -t=false alloc123
cp=nomad alloc exec -i=true -t=false alloc123
attach=nomad alloc exec -i=true -t=false alloc123" ]
}

function test_cmds_nomad_names_the_task_when_one_is_given() {
  local out
  out="$(_hi_ct_cmds alloc123/web nomad)"
  case "$out" in
  "probe=nomad alloc exec -task web -i=false -t=false alloc123"*) ;;
  *) return 1 ;;
  esac
}

function test_cmds_kube_ends_every_shape_with_a_double_dash() {
  local out
  out="$(_hi_ct_cmds mypod kube)"
  [ "$out" = "probe=kubectl exec mypod --
cp=kubectl exec -i mypod --
attach=kubectl exec -i mypod --" ]
}

function test_cmds_kube_names_the_container_when_one_is_given() {
  local out
  out="$(_hi_ct_cmds mypod/side kube)"
  case "$out" in
  "probe=kubectl exec mypod -c side --"*) ;;
  *) return 1 ;;
  esac
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

function test_fallback_shell_takes_a_ladder_name() {
  local -a probe
  probe=("$(_hi_ct_word)" sh)
  [ "$(_hi_container_fallback_shell)" = sh ]
}

# checked against the fixed list of right answers rather than sanitized: a
# word that is not on the ladder did not come from the probe
function test_fallback_shell_rejects_a_word_off_the_ladder() {
  local -a probe
  probe=("$(_hi_ct_word)" bogusshell)
  [ -z "$(_hi_container_fallback_shell)" ]
}

# a busybox echo with a mind of its own, or a shell that wrote something extra
# on the way past - the answer is one word or it is nothing
function test_fallback_shell_rejects_a_word_with_extra_output() {
  local -a probe
  probe=("$(_hi_ct_word)" "sh and then some")
  [ -z "$(_hi_container_fallback_shell)" ]
}

function test_fallback_shell_rejects_an_empty_answer() {
  local -a probe
  probe=("$(_hi_ct_word)" "")
  [ -z "$(_hi_container_fallback_shell)" ]
}

# ---------------------------------------------------------------------------
# _hi_container_put - proven to have landed, not assumed from a zero exit
# ---------------------------------------------------------------------------

function test_put_lands_the_file() {
  local dir="$_HI_WORKDIR/put.ok" tmp
  local -a cp=(env) probe=(env)
  mkdir -p "$dir"
  tmp="$dir/err"
  printf 'payload\n' >"$dir/src"
  _hi_container_put "$dir/src" "$dir/dest" || return 1
  [ "$(cat "$dir/dest")" = payload ]
}

# the write can succeed at the transport and still deliver nothing - an
# `exec -i` whose stdin closes before the target's cat drains it - so an empty
# landing is a failure however the transport exited
function test_put_fails_when_nothing_lands() {
  local dir="$_HI_WORKDIR/put.empty" tmp
  local -a cp probe=(env)
  mkdir -p "$dir"
  tmp="$dir/err"
  printf 'payload\n' >"$dir/src"
  # a transport that reports success and delivers nothing
  cat >"$dir/blackhole" <<'EOF'
#!/bin/sh
cat >/dev/null
exit 0
EOF
  chmod +x "$dir/blackhole"
  cp=("$dir/blackhole")
  ! _hi_container_put "$dir/src" "$dir/dest"
}

# the race is transient, so a second try is given rather than failing on the
# first empty landing - and $src is a regular file precisely so the retry can
# replay the same bytes
function test_put_retries_and_succeeds_on_a_later_try() {
  local dir="$_HI_WORKDIR/put.retry" tmp
  local -a cp probe=(env)
  mkdir -p "$dir"
  tmp="$dir/err"
  printf 'payload\n' >"$dir/src"
  cat >"$dir/flaky" <<'EOF'
#!/bin/sh
# the first attempt swallows the bytes; every later one delivers
n=0
[ -f "$FLAKY_COUNT" ] && n="$(cat "$FLAKY_COUNT")"
n=$((n + 1))
printf '%s' "$n" >"$FLAKY_COUNT"
if [ "$n" = 1 ]; then
  cat >/dev/null
  exit 0
fi
exec sh -c "$3"
EOF
  chmod +x "$dir/flaky"
  cp=(env "FLAKY_COUNT=$dir/count" "$dir/flaky")
  _hi_container_put "$dir/src" "$dir/dest" || return 1
  [ "$(cat "$dir/dest")" = payload ] && [ "$(cat "$dir/count")" = 2 ]
}

# ---------------------------------------------------------------------------
# _hi_container_cleanup - the client-side sweep on every early exit
# ---------------------------------------------------------------------------

function test_cleanup_removes_the_scratch_tree() {
  local root="$_HI_WORKDIR/clean.root"
  local -a probe=(env)
  mkdir -p "$root/say-hi"
  _hi_container_cleanup || return 1
  [ ! -d "$root" ]
}

# it runs on paths that are already gone, so it must never be the thing that
# fails an exit path
function test_cleanup_is_quiet_when_there_is_nothing_there() {
  local root="$_HI_WORKDIR/clean.gone"
  local -a probe=(env)
  _hi_container_cleanup
}

# ---------------------------------------------------------------------------
# _say_hi_container's failure ladder
# ---------------------------------------------------------------------------

# names the directory it tried, at the probe rather than later at the copy.
# A regular file rather than a /proc path: mkdir has to fail for the same
# reason everywhere, and /proc is Linux's alone.
function test_ladder_no_writable_temp_directory() {
  printf 'not a directory\n' >"$_HI_WORKDIR/ct.notmp.file"
  _hi_ct_run notmp "_HI_CT_TMPDIR=$_HI_WORKDIR/ct.notmp.file"
  [ "$_HI_CT_RC" != 0 ] && _hi_ct_said "no writable temp directory" &&
    _hi_ct_said "--plain needs none"
}

# the path comes back from the target and is interpolated into every command
# run there, so it is refused rather than escaped. A comma rather than a
# semicolon: both are outside _hi_safe_path's class, which is the whole
# assertion, but MSYS rewrites an argument that looks like a `;`-joined path
# list and would answer a different question under Git Bash.
function test_ladder_refuses_a_scratch_path_it_will_not_use() {
  mkdir -p "$_HI_WORKDIR/ct.badroot/od,ir"
  _hi_ct_run badroot "_HI_CT_TMPDIR=$_HI_WORKDIR/ct.badroot/od,ir"
  [ "$_HI_CT_RC" != 0 ] &&
    _hi_ct_said "named a scratch directory hi will not use"
}

# no bash and nothing on the ladder either: hi says so rather than guessing a
# shell out of thin air
function test_ladder_no_shell_hi_asked_about() {
  _hi_ct_run noshell _HI_CT_NO_BASH=1 _HI_CT_LADDER=bogusshell
  [ "$_HI_CT_RC" != 0 ] &&
    _hi_ct_said "named no shell hi asked about - not falling back"
}

# aliases.sh is the whole point of the fallback, so failing to land it is
# fatal to the fancy path - but the session still happens, bare
function test_ladder_aliases_copy_failure_still_attaches() {
  _hi_ct_run noalias _HI_CT_NO_BASH=1 _HI_CT_LADDER=sh \
    _HI_CT_PUT_FAIL=aliases.sh
  _hi_ct_said "failed to copy aliases.sh into" &&
    _hi_ct_logged '^attach:'
}

# the rc carries $CMDARG, so dropping it would leave a bare, uncommanded shell
# with no way to tell that from the ordinary kind - fatal, and swept
function test_ladder_fallback_rc_write_failure_is_fatal() {
  _hi_ct_run norc _HI_CT_NO_BASH=1 _HI_CT_LADDER=sh \
    _HI_CT_PUT_FAIL=.hi_fallback_rc
  [ "$_HI_CT_RC" != 0 ] &&
    _hi_ct_said "failed to write the fallback rc into" &&
    ! grep -q '^attach:' "$_HI_CT_LOG"
}

# zsh reads $ZDOTDIR/.zshrc and nothing else, so the copy is the handoff
function test_ladder_zshrc_write_failure_is_fatal() {
  _hi_ct_run nozshrc _HI_CT_NO_BASH=1 _HI_CT_LADDER=zsh _HI_CT_CP_FAIL=1
  [ "$_HI_CT_RC" != 0 ] && _hi_ct_said "failed to write .zshrc into"
}

# the tree itself failing to land is the last of the fallback-free arms
function test_ladder_payload_copy_failure_is_fatal() {
  _hi_ct_run notar _HI_CT_TAR_FAIL=1
  [ "$_HI_CT_RC" != 0 ] && _hi_ct_said "failed to copy say-hi into"
}

# Every fatal arm past the probe sweeps the scratch tree: it exists on the
# target from the moment the probe returns, so a bare `return` leaves it in
# the container. The shim logs the cleanup as an ordinary command.
function test_ladder_every_fatal_arm_sweeps_the_scratch_tree() {
  _hi_ct_run noshell2 _HI_CT_NO_BASH=1 _HI_CT_LADDER=bogusshell
  _hi_ct_logged '^cmd:rm -rf ' || return 1
  _hi_ct_run notar2 _HI_CT_TAR_FAIL=1
  _hi_ct_logged '^cmd:rm -rf '
}

# the bootloader is the file `bash --rcfile` reads: landing it empty would
# hand over a bare shell that sourced nothing, silently, so it goes through
# _hi_container_put's retry-and-verify like every other copy
function test_ladder_bootloader_write_failure_is_fatal() {
  _hi_ct_run noboot _HI_CT_PUT_FAIL=hi.bashrc
  [ "$_HI_CT_RC" != 0 ] &&
    _hi_ct_said "failed to write hi's bootloader into" &&
    ! grep -q '^attach:' "$_HI_CT_LOG"
}

# a fish fallback takes the rc through -C and the command through -c, as
# _hi_remote_suffix does - never through $ENV, which fish does not read
function test_ladder_fish_fallback_passes_the_rc_through_dash_c() {
  _hi_ct_run fish _HI_CT_NO_BASH=1 _HI_CT_LADDER=fish
  _hi_ct_logged '^attach:fish -C'
}

# every other ladder shell gets it through $ENV instead
function test_ladder_posix_fallback_passes_the_rc_through_env() {
  _hi_ct_run posix _HI_CT_NO_BASH=1 _HI_CT_LADDER=sh
  _hi_ct_logged 'attach:export ENV='
}

function run_container_tests() {
  _hi_h1 "Testing hi.sh's container arm"
  _hi_workdir hicontainer
  _hi_suite_begin
  _hi_ct_shim

  _hi_h2 "Testing: _hi_container_cmds"
  _hi_check "docker: docker exec" test_cmds_docker_uses_docker_exec
  _hi_check "podman is a drop-in" test_cmds_podman_is_a_drop_in_for_docker
  _hi_check "nomad spells out -i and -t" test_cmds_nomad_spells_out_both_flags
  _hi_check "nomad names the task" test_cmds_nomad_names_the_task_when_one_is_given
  _hi_check "kube ends every shape with --" test_cmds_kube_ends_every_shape_with_a_double_dash
  _hi_check "kube names the container" test_cmds_kube_names_the_container_when_one_is_given

  _hi_h2 "Testing: _hi_container_fallback_shell"
  _hi_check "Takes a ladder name" test_fallback_shell_takes_a_ladder_name
  _hi_check "Rejects a word off the ladder" test_fallback_shell_rejects_a_word_off_the_ladder
  _hi_check "Rejects a word with extra output" test_fallback_shell_rejects_a_word_with_extra_output
  _hi_check "Rejects an empty answer" test_fallback_shell_rejects_an_empty_answer

  _hi_h2 "Testing: _hi_container_put / _hi_container_cleanup"
  _hi_check "Lands the file" test_put_lands_the_file
  _hi_check "Fails when nothing lands" test_put_fails_when_nothing_lands
  _hi_check "Retries and succeeds on a later try" test_put_retries_and_succeeds_on_a_later_try
  _hi_check "Cleanup removes the scratch tree" test_cleanup_removes_the_scratch_tree
  _hi_check "Cleanup is quiet when it is already gone" test_cleanup_is_quiet_when_there_is_nothing_there

  # Every case below drives _say_hi_container past its scratch-dir probe,
  # which reads `mkdir -m 700`'s exit status as its verdict. Where that status
  # disagrees with the tree the shim is not exercising the ladder at all: the
  # probe arm answers first and every case after it reports the same "no
  # writable temp directory". The one case that expects that arm is gated too,
  # since there it would pass without having tested anything.
  _hi_h2 "Testing: _say_hi_container's failure ladder"
  _hi_check_capable mkdir_mode "No writable temp directory" test_ladder_no_writable_temp_directory
  _hi_check_capable mkdir_mode "Refuses a scratch path it will not use" test_ladder_refuses_a_scratch_path_it_will_not_use
  _hi_check_capable mkdir_mode "No shell hi asked about" test_ladder_no_shell_hi_asked_about
  _hi_check_capable mkdir_mode "aliases.sh copy failure still attaches" test_ladder_aliases_copy_failure_still_attaches
  _hi_check_capable mkdir_mode "Fallback rc write failure is fatal" test_ladder_fallback_rc_write_failure_is_fatal
  _hi_check_capable mkdir_mode ".zshrc write failure is fatal" test_ladder_zshrc_write_failure_is_fatal
  _hi_check_capable mkdir_mode "Payload copy failure is fatal" test_ladder_payload_copy_failure_is_fatal
  _hi_check_capable mkdir_mode "Bootloader write failure is fatal" test_ladder_bootloader_write_failure_is_fatal
  _hi_check_capable mkdir_mode "Every fatal arm sweeps the tree" test_ladder_every_fatal_arm_sweeps_the_scratch_tree
  _hi_check_capable mkdir_mode "fish takes the rc through -C" test_ladder_fish_fallback_passes_the_rc_through_dash_c
  _hi_check_capable mkdir_mode "POSIX shells take it through \$ENV" test_ladder_posix_fallback_passes_the_rc_through_env

  _hi_suite_end "hi.sh container arm"
}

run_container_tests
