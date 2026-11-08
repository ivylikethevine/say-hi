#!/usr/bin/env bash
# The suite's scratch dir, the teardown ledger, and the exit trap that spends it.
#
# Part of the tests/test_lib.sh harness; sourced by it, never on its own.
# GLOSSARY: HI.30
# shellcheck disable=SC2329

# Each suite's scratch dir, and the ledger of what its exit trap removes
# (containers, networks, SIGSTOPped pids). The ledger is a file, since a
# parallel case's array append dies with its subshell, and every writer
# registers before starting, so a ^C cannot leak a container.
_HI_WORKDIR=""
_HI_SUITE_WORKDIR=""
_HI_EXTRA_CLEANUP=""
_HI_LEDGER=""

# Makes the suite's scratch dir, $_HI_SUITE_WORKDIR (and $_HI_WORKDIR until a
# case gets its own), and the one exit trap. $1 names the mktemp template;
# $2 is an optional suite cleanup run first. `cd -P`, since the product
# resolves paths physically and macOS's $TMPDIR is under a symlink.
# GLOSSARY: HI.33
function _hi_workdir() {
  _HI_SUITE_WORKDIR="$(cd -P "$(mktemp -d -t "hi.$1.XXXXXX")" && pwd)"
  _HI_WORKDIR="$_HI_SUITE_WORKDIR"
  _HI_EXTRA_CLEANUP="${2:-}"
  _HI_LEDGER="$_HI_SUITE_WORKDIR/.ledger"
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

# Every step guarded, ending `return 0`: under `set -e` one failure would
# skip the rest. In order: background cases (which would recreate what is
# removed), the suite hook, frozen pids (thawed before their sshd goes),
# containers, then networks (refused while a container is on one).
function _hi_test_cleanup() {
  local c
  local -a containers
  _hi_par_kill
  if [ -n "$_HI_EXTRA_CLEANUP" ]; then
    "$_HI_EXTRA_CLEANUP" || true
  fi
  _hi_read_lines _HI_FROZEN_PIDS < <(_hi_ledger_rows frozen)
  _hi_thaw_frozen
  # one `rm -f` for the whole ledger rather than one docker-client exec per
  # container: `rm -f` already tolerates a name that never existed, which is
  # what the sweep relies on regardless
  _hi_read_lines containers < <(_hi_ledger_rows container)
  [ "${#containers[@]}" -eq 0 ] ||
    "${_HI_BACKEND:-docker}" rm -f "${containers[@]}" >/dev/null 2>&1 || true
  for c in $(_hi_ledger_rows network); do
    "${_HI_BACKEND:-docker}" network rm "$c" >/dev/null 2>&1 || true
  done
  for c in $(_hi_ledger_rows dir); do
    rm -rf "$c" 2>/dev/null || true
  done
  # Under coverage the tree outlives the suite ($_HI_COV_KEEP), since bashcov
  # credits a copy's lines only while it exists. The suite's dir, never
  # $_HI_WORKDIR, which inside a case is the case's.
  if [ -n "${_HI_COV_KEEP:-}" ] && [ -n "$_HI_SUITE_WORKDIR" ]; then
    printf '%s\n' "$_HI_SUITE_WORKDIR" >>"$_HI_COV_KEEP"
  elif [ -n "$_HI_SUITE_WORKDIR" ]; then
    rm -rf "$_HI_SUITE_WORKDIR" || true
  fi
  # the isolated config overlay and runtime dir from the top of test_lib.sh:
  # the one root it made, by the path it recorded and only in the shape
  # mktemp gave it - never what the XDG variables point at now
  case "${_HI_TEST_ROOT:-}" in */hi.testroot.??????) rm -rf "$_HI_TEST_ROOT" || true ;; esac
  return 0
}

# _hi_rm_container <name> - the eager between-cases teardown, as one idiom:
# every e2e case removes its container the moment its verdict is in rather
# than letting them pile up until _hi_test_cleanup sweeps the stragglers.
function _hi_rm_container() {
  "${_HI_BACKEND:-docker}" rm -f "$1" >/dev/null 2>&1 || true
}
