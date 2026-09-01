#!/usr/bin/env bash
# The suite's scratch dir, the teardown ledger, and the exit trap that spends it.
#
# Part of the tests/test_lib.sh harness; sourced by it, never on its own.
# GLOSSARY: HI.30
# shellcheck disable=SC2329

# Scratch dir every suite works in, plus the ledger of everything its exit trap
# has to take away again: containers, docker networks, and processes a case
# SIGSTOPped. Both are set up by _hi_workdir and consumed by _hi_test_cleanup.
#
# The ledger is a *file* and not an array, for two reasons that both cost real
# containers on a real machine. A case may run in a background subshell (see
# _hi_par_case), where an array append dies with the subshell and the container
# it started is never registered. And a file can be written *before* the thing
# exists - the window between `docker run` returning and the name being
# recorded is exactly where a ^C leaks one, so every writer below registers
# first and starts second. Removing something twice is a no-op; removing
# something that never started is a no-op too. Missing one is not.
_HI_WORKDIR=""
_HI_EXTRA_CLEANUP=""
_HI_LEDGER=""

# Creates the suite's scratch dir as $_HI_WORKDIR and registers the one exit
# trap it needs. $1 is a slug for the mktemp template ("checktest", "sshtest",
# ...); $2, if given, names a suite-specific cleanup function (stopping a nomad
# agent, deleting a kind cluster, ...) run before the generic teardown.
# _hi_on_exit installs a *single* trap rather than appending to one, so
# everything that has to happen on the way out goes through here.
#
# Resolved with `cd -P`: the product derives its tree physically
# (GLOSSARY: HI.33), so a $TMPDIR holding a symlink - macOS's /var - would
# leave a suite comparing two spellings of one directory.
function _hi_workdir() {
  _HI_WORKDIR="$(cd -P "$(mktemp -d -t "hi.$1.XXXXXX")" && pwd)"
  _HI_EXTRA_CLEANUP="${2:-}"
  _HI_LEDGER="$_HI_WORKDIR/.ledger"
  : >"$_HI_LEDGER"
  _hi_on_exit _hi_test_cleanup
}

# _hi_ledger <kind> <value> - one line on the teardown ledger. A single short
# printf to a file opened O_APPEND, which is what makes concurrent cases writing
# it safe: one write, far under PIPE_BUF, so lines never interleave.
function _hi_ledger() {
  [ -n "$_HI_LEDGER" ] || return 0
  printf '%s %s\n' "$1" "$2" >>"$_HI_LEDGER"
  return 0
}

# _hi_ledger_rows <kind> - the values registered under <kind>, one per line.
function _hi_ledger_rows() {
  local kind value
  [ -n "$_HI_LEDGER" ] && [ -f "$_HI_LEDGER" ] || return 0
  while read -r kind value; do
    [ "$kind" = "$1" ] && printf '%s\n' "$value"
  done <"$_HI_LEDGER"
  return 0
}

# Registers a container for teardown by _hi_test_cleanup. Suites driving a
# non-docker CLI set _HI_BACKEND (podman) first - every backend that
# reaches here takes docker's `rm -f <name>` shape.
function _hi_track_container() { _hi_ledger container "$1"; }

# The same, for a docker network: the relay suite builds one per case, and it
# can only go after the containers on it (hence the sweep order below).
function _hi_track_network() { _hi_ledger network "$1"; }

# ...and for a directory a suite creates *outside* its workdir - the package
# suites' $_HI_ROOT/dist. Registered only when the suite is the one creating
# it, so a developer's own mkpkg.sh build survives a test run.
function _hi_track_dir() { _hi_ledger dir "$1"; }

# Every step is guarded and the whole thing ends in `return 0`: this runs as
# an exit trap under `set -e`, where one failing step would otherwise skip
# every step after it - leaving containers or the scratch dir behind.
#
# The order is not arbitrary. Background cases are killed first - before the
# suite's own hook, even: a case still running would put a container, a job or a
# pod back behind whatever the hook and the sweep have just taken away. Frozen pids come next, and
# before their containers: a SIGSTOPped process cannot act on SIGKILL until it
# is scheduled again (see _hi_thaw_frozen), and taking its sshd away first
# leaves it stopped forever, holding a socket to nothing. Networks come last,
# because docker refuses to remove one that still has a container on it.
function _hi_test_cleanup() {
  local c
  _hi_par_kill
  if [ -n "$_HI_EXTRA_CLEANUP" ]; then
    "$_HI_EXTRA_CLEANUP" || true
  fi
  for c in $(_hi_ledger_rows frozen); do
    kill -CONT "$c" 2>/dev/null || true
    kill -9 "$c" 2>/dev/null || true
  done
  for c in $(_hi_ledger_rows container); do
    _hi_rm_container "$c"
  done
  for c in $(_hi_ledger_rows network); do
    "${_HI_BACKEND:-docker}" network rm "$c" >/dev/null 2>&1 || true
  done
  for c in $(_hi_ledger_rows dir); do
    rm -rf "$c" 2>/dev/null || true
  done
  if [ -n "$_HI_WORKDIR" ]; then
    rm -rf "$_HI_WORKDIR" || true
  fi
  # the isolated config overlay from the top of this file, if a test made one
  rm -rf "$XDG_CONFIG_HOME" || true
  return 0
}

# _hi_rm_container <name> - the eager between-cases teardown, as one idiom:
# every e2e case removes its container the moment its verdict is in rather
# than letting them pile up until _hi_test_cleanup sweeps the stragglers.
function _hi_rm_container() {
  "${_HI_BACKEND:-docker}" rm -f "$1" >/dev/null 2>&1 || true
}
