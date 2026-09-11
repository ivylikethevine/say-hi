#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Unit tests for hi.sh's runtime-directory layer and the three things built on
# it: the overlay cache, the payload cache, and the ControlMaster socket.
# Nothing here connects to anything - _hi_ctl_open only *assembles* ssh's
# options, and both caches are local file work - so the whole suite runs
# offline, which is the point: these arms are otherwise only ever taken on a
# real connect. Sourcing hi.sh goes through the same `[[ BASH_SOURCE == $0 ]]`
# hatch helpers_test.sh and payload_test.sh use.
#
# The cache assertions never compare mtimes (BSD and GNU `stat` disagree on
# every flag). A cold build is marked by appending a byte to the cache file,
# and the file's own mtime is then moved with `touch -t` - POSIX, and exact,
# where a `sleep 1` would only be probably-enough. A warm hit leaves the
# marker; a rebuild drops it.
#
# GLOSSARY: HI.34. The linter follows hi.sh's trailing `_hi "$@"` and marks
# this file unreachable (SC2317); it does not model the guard.
# shellcheck disable=SC2329,SC2317,SC2016
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"
# shellcheck source=../../hi.sh
source "$_HI_LAUNCHER"

# The overlay members every cache case works over, staged into a config dir of
# this suite's own: test_lib.sh points $_HI_CONFIG_DIR at a path that
# deliberately does not exist, and _hi_overlay_tar has to be able to `tar -C`
# into it.
_HI_CACHE_MEMBERS=(settings.sh colors)

function _hi_cache_config() {
  mkdir -p "$_HI_CONFIG_DIR"
  printf 'export _HI_GIT_PROMPT=1\n' >"$_HI_CONFIG_DIR/settings.sh"
  printf 'host,liona,BRCYAN\n' >"$_HI_CONFIG_DIR/colors"
}

# A runtime directory hi will vouch for: $XDG_RUNTIME_DIR is taken as-is when
# it exists, so this is the cheapest way to give a case one.
function _hi_cache_rt() {
  local dir="$_HI_WORKDIR/$1"
  mkdir -p "$dir"
  printf '%s' "$dir"
}

# the marker the warm/stale cases read back
function _hi_cache_mark() { printf 'MARK' >>"$1"; }
function _hi_cache_marked() { grep -q MARK "$1"; }

# ---------------------------------------------------------------------------
# _hi_runtime_dir
# ---------------------------------------------------------------------------

function test_runtime_dir_takes_xdg_runtime_dir_as_is() {
  local out="" dir
  dir="$(_hi_cache_rt rt.xdg)"
  XDG_RUNTIME_DIR="$dir" _hi_runtime_dir out
  [ "$out" = "$dir" ]
}

# an $XDG_RUNTIME_DIR naming something that is not a directory is not hi's to
# trust either - it falls through to the private one below
function test_runtime_dir_ignores_a_missing_xdg_runtime_dir() {
  local out=""
  XDG_RUNTIME_DIR="$_HI_WORKDIR/rt.nope" TMPDIR="$_HI_WORKDIR/rt.tmp1" \
    _hi_runtime_dir out
  mkdir -p "$_HI_WORKDIR/rt.tmp1"
  XDG_RUNTIME_DIR="$_HI_WORKDIR/rt.nope" TMPDIR="$_HI_WORKDIR/rt.tmp1" \
    _hi_runtime_dir out
  [ "$out" = "$_HI_WORKDIR/rt.tmp1/hi-$(id -u)" ] && [ -d "$out" ]
}

# made with `mkdir -m 700`, never adopted from whatever mode was there. The
# mode string is the assertion, so the case asks for mode_bits first: MSYS
# synthesizes one rather than reporting chmod's.
function test_runtime_dir_creates_its_own_at_0700() {
  local out="" mode
  mkdir -p "$_HI_WORKDIR/rt.tmp2"
  XDG_RUNTIME_DIR="" TMPDIR="$_HI_WORKDIR/rt.tmp2" _hi_runtime_dir out
  [ -n "$out" ] || return 1
  # shellcheck disable=SC2012 # a fixed column off one path this case built,
  # not a filename parsed out of a listing - hi.sh's own check reads it the
  # same way, and `stat`'s flags differ BSD/GNU
  mode="$(ls -ld "$out" | cut -c1-10)"
  [ "$mode" = "drwx------" ]
}

# a symlink where the private directory belongs is refused outright: the
# caller degrades to no cache rather than write through it
function test_runtime_dir_refuses_a_symlinked_private_dir() {
  local out="" base="$_HI_WORKDIR/rt.tmp3"
  mkdir -p "$base" "$_HI_WORKDIR/rt.elsewhere"
  ln -s "$_HI_WORKDIR/rt.elsewhere" "$base/hi-$(id -u)"
  XDG_RUNTIME_DIR="" TMPDIR="$base" _hi_runtime_dir out
  [ -z "$out" ]
}

# mkdir cannot answer under a path that is not a directory, and nothing is
# vouched for
function test_runtime_dir_is_empty_when_it_cannot_create_one() {
  local out="" base="$_HI_WORKDIR/rt.file"
  printf 'not a directory\n' >"$base"
  XDG_RUNTIME_DIR="" TMPDIR="$base" _hi_runtime_dir out
  [ -z "$out" ]
}

# The owner check reads a fixed column out of `ls -ld`, which is empty on a
# host with no passwd entry for the caller - the arm the SC2012 comment in
# hi.sh names. A no-op `ls` on $PATH is exactly that host.
function test_runtime_dir_is_empty_when_the_owner_cannot_be_read() {
  local out="" base="$_HI_WORKDIR/rt.tmp4" fake
  mkdir -p "$base"
  fake="$(_hi_fake_path noowner ls)"
  XDG_RUNTIME_DIR="" TMPDIR="$base" PATH="$fake:$PATH" _hi_runtime_dir out
  [ -z "$out" ]
}

# ---------------------------------------------------------------------------
# the cache keys
# ---------------------------------------------------------------------------

function test_overlay_cache_key_is_stable_for_one_member_list() {
  local a b
  a="$(_hi_overlay_cache_key settings.sh colors)"
  b="$(_hi_overlay_cache_key settings.sh colors)"
  [ -n "$a" ] && [ "$a" = "$b" ]
}

# the list is in the key precisely so a toggle that trims a member gets its
# own cache file rather than reusing the fuller one
function test_overlay_cache_key_changes_with_the_member_list() {
  local full trimmed reordered
  full="$(_hi_overlay_cache_key settings.sh colors packages)"
  trimmed="$(_hi_overlay_cache_key settings.sh colors)"
  reordered="$(_hi_overlay_cache_key colors settings.sh)"
  [ "$full" != "$trimmed" ] && [ "$full" != "$reordered" ]
}

# ---------------------------------------------------------------------------
# _hi_overlay_cached
# ---------------------------------------------------------------------------

function test_overlay_cached_refuses_an_empty_member_list() {
  local out="" dir
  dir="$(_hi_cache_rt oc.empty)"
  ! XDG_RUNTIME_DIR="$dir" _hi_overlay_cached out
}

function test_overlay_cached_is_off_when_the_toggle_is_zero() {
  local out="" dir
  dir="$(_hi_cache_rt oc.off)"
  ! XDG_RUNTIME_DIR="$dir" _HI_PAYLOAD_CACHE=0 \
    _hi_overlay_cached out "${_HI_CACHE_MEMBERS[@]}"
}

# no directory hi can vouch for means no cache, and the caller builds fresh
function test_overlay_cached_refuses_without_a_runtime_dir() {
  local out="" base="$_HI_WORKDIR/oc.nodir"
  printf 'not a directory\n' >"$base"
  ! XDG_RUNTIME_DIR="" TMPDIR="$base" \
    _hi_overlay_cached out "${_HI_CACHE_MEMBERS[@]}"
}

function test_overlay_cached_builds_cold_and_names_the_file() {
  local out="" dir
  dir="$(_hi_cache_rt oc.cold)"
  XDG_RUNTIME_DIR="$dir" _hi_overlay_cached out "${_HI_CACHE_MEMBERS[@]}" || return 1
  [ "$out" = "$dir/hi.overlay.$(_hi_overlay_cache_key "${_HI_CACHE_MEMBERS[@]}")" ] || return 1
  [ -s "$out" ]
}

# the write is `>$cache.$$` then `mv`, so a reader never sees a half-built
# archive - and nothing is left behind under the temp name
function test_overlay_cached_leaves_no_temp_file() {
  local out="" dir
  dir="$(_hi_cache_rt oc.tmp)"
  XDG_RUNTIME_DIR="$dir" _hi_overlay_cached out "${_HI_CACHE_MEMBERS[@]}" || return 1
  [ -z "$(find "$dir" -name 'hi.overlay.*.[0-9]*' -print)" ]
}

# a builder that fails leaves nothing behind - not the temp file it was
# writing, not a cache under the real name - and answers rc 1, "build it
# yourself", with the outvar untouched
function test_cached_cleans_up_after_a_failed_build() {
  local out="" dir
  dir="$(_hi_cache_rt c.fail)"
  ! XDG_RUNTIME_DIR="$dir" _hi_cached out fail k "$_HI_CONFIG_DIR/" false settings.sh || return 1
  [ -z "$out" ] && [ -z "$(find "$dir" -name 'hi.fail.k*' -print)" ]
}

function test_overlay_cached_reuses_a_warm_cache() {
  local out="" dir
  dir="$(_hi_cache_rt oc.warm)"
  XDG_RUNTIME_DIR="$dir" _hi_overlay_cached out "${_HI_CACHE_MEMBERS[@]}" || return 1
  _hi_cache_mark "$out"
  touch -t 203001010000 "$out"
  XDG_RUNTIME_DIR="$dir" _hi_overlay_cached out "${_HI_CACHE_MEMBERS[@]}" || return 1
  _hi_cache_marked "$out"
}

# a member touched past the cache's own mtime is what makes it stale - not the
# cache's age, and not a checksum
function test_overlay_cached_rebuilds_when_a_member_is_newer() {
  local out="" dir
  dir="$(_hi_cache_rt oc.stale)"
  XDG_RUNTIME_DIR="$dir" _hi_overlay_cached out "${_HI_CACHE_MEMBERS[@]}" || return 1
  _hi_cache_mark "$out"
  touch -t 200001010000 "$out"
  XDG_RUNTIME_DIR="$dir" _hi_overlay_cached out "${_HI_CACHE_MEMBERS[@]}" || return 1
  ! _hi_cache_marked "$out"
}

# a trimmed member list is a different key, so it cannot be served the fuller
# archive off the warm one
function test_overlay_cached_keys_the_file_by_member_list() {
  local full="" trimmed="" dir
  dir="$(_hi_cache_rt oc.key)"
  XDG_RUNTIME_DIR="$dir" _hi_overlay_cached full "${_HI_CACHE_MEMBERS[@]}" || return 1
  XDG_RUNTIME_DIR="$dir" _hi_overlay_cached trimmed settings.sh || return 1
  [ "$full" != "$trimmed" ] && [ -s "$full" ] && [ -s "$trimmed" ]
}

# ---------------------------------------------------------------------------
# _hi_overlay_stream / _hi_payload_stream
# ---------------------------------------------------------------------------

# both arms have to emit the same *shape* of armored line, whichever answered:
# the caller bakes the result into the wire script and cannot tell them apart
function test_overlay_stream_emits_an_armored_line_either_way() {
  local dir warm cold
  dir="$(_hi_cache_rt os.line)"
  warm="$(XDG_RUNTIME_DIR="$dir" _hi_overlay_stream "${_HI_CACHE_MEMBERS[@]}")"
  cold="$(XDG_RUNTIME_DIR="$dir" _HI_PAYLOAD_CACHE=0 _hi_overlay_stream "${_HI_CACHE_MEMBERS[@]}")"
  case "$warm" in *'tar -x -m -z -f - -C "$_HI_ROOT/config"'*) ;; *) return 1 ;; esac
  case "$cold" in *'tar -x -m -z -f - -C "$_HI_ROOT/config"'*) ;; *) return 1 ;; esac
}

# a warm cache is the same bytes twice: gzip stamps an mtime, so two *fresh*
# builds would not be, and reading the file back is what makes a repeat
# connect byte-identical
function test_overlay_stream_is_byte_identical_off_a_warm_cache() {
  local dir a b out=""
  dir="$(_hi_cache_rt os.same)"
  XDG_RUNTIME_DIR="$dir" _hi_overlay_cached out "${_HI_CACHE_MEMBERS[@]}" || return 1
  touch -t 203001010000 "$out"
  a="$(XDG_RUNTIME_DIR="$dir" _hi_overlay_stream "${_HI_CACHE_MEMBERS[@]}")"
  b="$(XDG_RUNTIME_DIR="$dir" _hi_overlay_stream "${_HI_CACHE_MEMBERS[@]}")"
  [ -n "$a" ] && [ "$a" = "$b" ]
}

function test_payload_cached_builds_cold_then_reuses_it() {
  local out="" dir
  dir="$(_hi_cache_rt pc.warm)"
  XDG_RUNTIME_DIR="$dir" _hi_payload_cached out || return 1
  [ "$out" = "$dir/hi.payload.tree" ] || return 1
  [ -s "$out" ] || return 1
  _hi_cache_mark "$out"
  touch -t 203001010000 "$out"
  XDG_RUNTIME_DIR="$dir" _hi_payload_cached out || return 1
  _hi_cache_marked "$out"
}

function test_payload_cached_rebuilds_when_a_source_file_is_newer() {
  local out="" dir
  dir="$(_hi_cache_rt pc.stale)"
  XDG_RUNTIME_DIR="$dir" _hi_payload_cached out || return 1
  _hi_cache_mark "$out"
  touch -t 200001010000 "$out"
  XDG_RUNTIME_DIR="$dir" _hi_payload_cached out || return 1
  ! _hi_cache_marked "$out"
}

function test_payload_cached_is_off_when_the_toggle_is_zero() {
  local out="" dir
  dir="$(_hi_cache_rt pc.off)"
  ! XDG_RUNTIME_DIR="$dir" _HI_PAYLOAD_CACHE=0 _hi_payload_cached out
}

function test_payload_stream_is_byte_identical_off_a_warm_cache() {
  local dir a b out=""
  dir="$(_hi_cache_rt ps.same)"
  XDG_RUNTIME_DIR="$dir" _hi_payload_cached out || return 1
  touch -t 203001010000 "$out"
  a="$(XDG_RUNTIME_DIR="$dir" _hi_payload_stream)"
  b="$(XDG_RUNTIME_DIR="$dir" _hi_payload_stream)"
  [ -n "$a" ] && [ "$a" = "$b" ]
}

# ...and with the cache off it armors a fresh build instead: through the
# target's own unarmor, the same members either way (sorted - two staging
# dirs need not list alike)
function test_payload_stream_is_the_same_tree_with_the_cache_off() {
  local dir warm cold
  dir="$(_hi_cache_rt ps.off)"
  warm="$(XDG_RUNTIME_DIR="$dir" _hi_payload_stream | eval "$_HI_UNARMOR" | tar tzf - | sort)"
  cold="$(XDG_RUNTIME_DIR="$dir" _HI_PAYLOAD_CACHE=0 _hi_payload_stream | eval "$_HI_UNARMOR" | tar tzf - | sort)"
  [ -n "$cold" ] && [ "$cold" = "$warm" ]
}

# ---------------------------------------------------------------------------
# _hi_ctl_open / _hi_ctl_close
#
# Every case declares the four outvars _hi_ctl_open writes into, the way its
# real callers do, plus the DOMAIN/SSHARGS it keys on.
#
# ...and every case that wants a socket built pins $OSTYPE to a client that
# multiplexes. The CI matrix runs this suite under Git Bash, where bash's own
# $OSTYPE is "msys" and _hi_ctl_open returns before assembling anything, so a
# case reading the host's value would assert against the MSYS arm - vacuously,
# since an unset ctl_path satisfies the "short name" and "no socket" checks.
# ---------------------------------------------------------------------------

function _hi_ctl_vars() {
  ctl_dir=""
  ctl_path=""
  ctl_opts=()
  ctl_shared=0
}

# ctl_opts carries an option and its argument as two array elements, so a
# lookup is "this element, exactly"
function _hi_ctl_has_opt() {
  local want="$1" el
  for el in ${ctl_opts[@]+"${ctl_opts[@]}"}; do
    [ "$el" = "$want" ] && return 0
  done
  return 1
}

function test_ctl_open_shared_uses_the_runtime_dir() {
  local DOMAIN=liona dir ctl_dir ctl_path ctl_shared
  local -a SSHARGS=() ctl_opts=()
  local OSTYPE=linux-gnu
  _hi_ctl_vars
  dir="$(_hi_cache_rt ctl.shared)"
  XDG_RUNTIME_DIR="$dir" _hi_ctl_open 60 shared
  [ "$ctl_shared" = 1 ] || return 1
  [ -z "$ctl_dir" ] || return 1
  case "$ctl_path" in "$dir"/hi.ctl.[0-9]*) ;; *) return 1 ;; esac
  _hi_ctl_has_opt "ControlPath=$ctl_path"
}

# the socket name is short on purpose - a sockaddr_un caps near 104 bytes and
# macOS's per-user $TMPDIR already spends about half of it
function test_ctl_open_shared_socket_name_stays_short() {
  local DOMAIN=liona dir ctl_dir ctl_path ctl_shared base
  local -a SSHARGS=() ctl_opts=()
  local OSTYPE=linux-gnu
  _hi_ctl_vars
  dir="$(_hi_cache_rt ctl.short)"
  XDG_RUNTIME_DIR="$dir" _hi_ctl_open 60 shared
  base="${ctl_path##*/}"
  [ "${#base}" -le 20 ]
}

# the key is a cksum of the target *and* its ssh args, so a -p/-l/-o naming a
# different connection to the same host cannot join the wrong socket
function test_ctl_open_shared_key_splits_on_ssh_args() {
  local DOMAIN=liona dir ctl_dir ctl_path ctl_shared plain ported
  local -a SSHARGS=() ctl_opts=()
  local OSTYPE=linux-gnu
  dir="$(_hi_cache_rt ctl.key)"
  _hi_ctl_vars
  XDG_RUNTIME_DIR="$dir" _hi_ctl_open 60 shared
  plain="$ctl_path"
  SSHARGS=(-p 2222)
  _hi_ctl_vars
  XDG_RUNTIME_DIR="$dir" _hi_ctl_open 60 shared
  ported="$ctl_path"
  [ "$plain" != "$ported" ]
}

function test_ctl_open_shared_key_splits_on_the_target() {
  local dir ctl_dir ctl_path ctl_shared one two DOMAIN
  local -a SSHARGS=() ctl_opts=()
  local OSTYPE=linux-gnu
  dir="$(_hi_cache_rt ctl.dom)"
  DOMAIN=liona
  _hi_ctl_vars
  XDG_RUNTIME_DIR="$dir" _hi_ctl_open 60 shared
  one="$ctl_path"
  DOMAIN=tiger
  _hi_ctl_vars
  XDG_RUNTIME_DIR="$dir" _hi_ctl_open 60 shared
  two="$ctl_path"
  [ "$one" != "$two" ]
}

# _HI_CTL_PERSIST=0 is the documented opt-out: back to a fresh per-run socket
function test_ctl_open_shared_falls_back_when_persist_is_zero() {
  local DOMAIN=liona dir ctl_dir ctl_path ctl_shared
  local -a SSHARGS=() ctl_opts=()
  local OSTYPE=linux-gnu
  _hi_ctl_vars
  dir="$(_hi_cache_rt ctl.zero)"
  XDG_RUNTIME_DIR="$dir" _HI_CTL_PERSIST=0 _hi_ctl_open 45 shared
  [ "$ctl_shared" = 0 ] || return 1
  [ -n "$ctl_dir" ] && [ "$ctl_path" = "$ctl_dir/s" ] &&
    _hi_ctl_has_opt "ControlPersist=45"
}

# so does a runtime directory hi will not vouch for - the temp dir is
# perfectly good here, so `run`'s fresh socket still gets made; only the
# sharing is given up. The unreadable owner is the no-passwd-entry host
# _hi_runtime_dir's own SC2012 comment names.
function test_ctl_open_shared_falls_back_without_a_runtime_dir() {
  local DOMAIN=liona ctl_dir ctl_path ctl_shared base="$_HI_WORKDIR/ctl.nodir" fake
  local -a SSHARGS=() ctl_opts=()
  local OSTYPE=linux-gnu
  _hi_ctl_vars
  mkdir -p "$base"
  fake="$(_hi_fake_path noowner ls)"
  XDG_RUNTIME_DIR="" TMPDIR="$base" PATH="$fake:$PATH" _hi_ctl_open 60 shared
  [ "$ctl_shared" = 0 ] || return 1
  [ -n "$ctl_dir" ] && [ "$ctl_path" = "$ctl_dir/s" ]
}

# and with neither a runtime dir nor a usable temp dir there is no socket at
# all: ctl_opts stays empty, ssh authenticates twice, everything still works.
#
# The $TMPDIR-is-a-file half is what denies _hi_runtime_dir; the mktemp on
# $PATH is what denies the fallback, shimmed the way targets_test.sh shims
# `ls`. Leaning on the bogus $TMPDIR for both would only work under GNU
# mktemp - BSD's -t reads its argument as a prefix and resolves $TMPDIR on its
# own terms - and that is hi's dependency to be free of, not the case's to
# assert.
function test_ctl_open_gives_up_quietly_with_nowhere_to_put_a_socket() {
  local DOMAIN=liona ctl_dir ctl_path ctl_shared bin="$_HI_WORKDIR/ctl.nomktemp"
  local base="$_HI_WORKDIR/ctl.nowhere"
  local -a SSHARGS=() ctl_opts=()
  local OSTYPE=linux-gnu
  _hi_ctl_vars
  printf 'not a directory\n' >"$base"
  mkdir -p "$bin"
  printf '%s\n' '#!/bin/sh' 'exit 1' >"$bin/mktemp"
  chmod +x "$bin/mktemp"
  XDG_RUNTIME_DIR="" TMPDIR="$base" PATH="$bin:$PATH" _hi_ctl_open 60 shared
  [ "$ctl_shared" = 0 ] && [ -z "$ctl_dir" ] && [ -z "$ctl_path" ] &&
    [ "${#ctl_opts[@]}" -eq 0 ]
}

# An MSYS/Cygwin client gets no socket at all, whatever the runtime dir says:
# ssh's mux hands file descriptors over an AF_UNIX socket and that runtime
# does not carry them, so a ControlPath there kills the connection rather than
# degrading it. $OSTYPE is bash's own, set at build time, so a case can set it.
function test_ctl_open_declines_to_multiplex_on_msys() {
  local DOMAIN=liona dir ctl_dir ctl_path ctl_shared
  local -a SSHARGS=() ctl_opts=()
  _hi_ctl_vars
  dir="$(_hi_cache_rt ctl.msys)"
  OSTYPE=msys XDG_RUNTIME_DIR="$dir" _hi_ctl_open 60 shared
  [ "$ctl_shared" = 0 ] && [ -z "$ctl_dir" ] && [ -z "$ctl_path" ] &&
    [ "${#ctl_opts[@]}" -eq 0 ] || return 1
  # ...and the run scope, which reaches the mktemp arm instead
  OSTYPE=cygwin XDG_RUNTIME_DIR="$dir" _hi_ctl_open 30 run -o BatchMode=yes
  # the two extra words are all that is left: no ControlMaster, no ControlPath
  [ -z "$ctl_dir" ] && [ -z "$ctl_path" ] &&
    [ "${#ctl_opts[@]}" -eq 2 ] && _hi_ctl_has_opt "BatchMode=yes"
}

# `run` never shares, even with a perfectly good runtime dir - scripts/doctor.sh
# asks for it precisely so a diagnostic leaves no socket behind
function test_ctl_open_run_never_shares() {
  local DOMAIN=liona dir ctl_dir ctl_path ctl_shared
  local -a SSHARGS=() ctl_opts=()
  local OSTYPE=linux-gnu
  _hi_ctl_vars
  dir="$(_hi_cache_rt ctl.run)"
  XDG_RUNTIME_DIR="$dir" _hi_ctl_open 30 run
  [ "$ctl_shared" = 0 ] || return 1
  [ -d "$ctl_dir" ] && [ "$ctl_path" = "$ctl_dir/s" ] &&
    _hi_ctl_has_opt "ControlPersist=30"
}

# the socket lives *inside* a mktemp -d, not at a mktemp -u name in a shared
# $TMPDIR: ControlMaster=auto would join a socket already at that path.
# mode_bits for the same reason as the 0700 case above.
function test_ctl_open_run_socket_dir_is_private() {
  local DOMAIN=liona dir ctl_dir ctl_path ctl_shared mode
  local -a SSHARGS=() ctl_opts=()
  local OSTYPE=linux-gnu
  _hi_ctl_vars
  dir="$(_hi_cache_rt ctl.priv)"
  XDG_RUNTIME_DIR="$dir" _hi_ctl_open 30 run
  # shellcheck disable=SC2012 # as above: one path, one fixed column
  mode="$(ls -ld "$ctl_dir" | cut -c1-10)"
  [ "$mode" = "drwx------" ]
}

function test_ctl_open_appends_extra_ssh_options() {
  local DOMAIN=liona dir ctl_dir ctl_path ctl_shared
  local -a SSHARGS=() ctl_opts=()
  local OSTYPE=linux-gnu
  _hi_ctl_vars
  dir="$(_hi_cache_rt ctl.extra)"
  XDG_RUNTIME_DIR="$dir" _hi_ctl_open 60 shared -o BatchMode=yes
  _hi_ctl_has_opt "BatchMode=yes"
}

# a shared socket outlives the call on purpose - that is the whole point of
# _HI_CTL_PERSIST, and closing it here would give the next `hi` nothing to reuse
function test_ctl_close_leaves_a_shared_socket_alone() {
  local DOMAIN=liona dir ctl_dir ctl_path ctl_shared fake
  local -a SSHARGS=() ctl_opts=()
  local OSTYPE=linux-gnu
  _hi_ctl_vars
  dir="$(_hi_cache_rt ctl.keep)"
  XDG_RUNTIME_DIR="$dir" _hi_ctl_open 60 shared
  fake="$(_hi_fake_path ctlssh ssh)"
  PATH="$fake:$PATH" _hi_ctl_close || return 1
  [ -d "$dir" ]
}

function test_ctl_close_removes_a_run_socket_dir() {
  local DOMAIN=liona dir ctl_dir ctl_path ctl_shared fake
  local -a SSHARGS=() ctl_opts=()
  local OSTYPE=linux-gnu
  _hi_ctl_vars
  dir="$(_hi_cache_rt ctl.drop)"
  XDG_RUNTIME_DIR="$dir" _hi_ctl_open 30 run
  [ -d "$ctl_dir" ] || return 1
  fake="$(_hi_fake_path ctlssh ssh)"
  PATH="$fake:$PATH" _hi_ctl_close || return 1
  [ ! -d "$ctl_dir" ]
}

# nothing to close is not a failure: every caller runs it on the way out of
# arms that never opened a socket
function test_ctl_close_is_a_noop_with_nothing_open() {
  local DOMAIN=liona ctl_dir="" ctl_path="" ctl_shared=0 fake
  local -a SSHARGS=() ctl_opts=()
  fake="$(_hi_fake_path ctlssh ssh)"
  PATH="$fake:$PATH" _hi_ctl_close
}

function run_cache_tests() {
  _hi_h1 "Testing hi.sh's runtime dir, caches, and ControlMaster socket"
  _hi_workdir hicache
  _hi_suite_begin
  _hi_cache_config

  _hi_h2 "Testing: _hi_runtime_dir"
  _hi_check "Takes \$XDG_RUNTIME_DIR as-is" test_runtime_dir_takes_xdg_runtime_dir_as_is
  _hi_check "Ignores an \$XDG_RUNTIME_DIR that is not there" test_runtime_dir_ignores_a_missing_xdg_runtime_dir
  _hi_check_capable mode_bits "Creates its own at 0700" test_runtime_dir_creates_its_own_at_0700
  _hi_check_capable symlink "Refuses a symlinked private dir" test_runtime_dir_refuses_a_symlinked_private_dir
  _hi_check "Empty when it cannot create one" test_runtime_dir_is_empty_when_it_cannot_create_one
  _hi_check "Empty when the owner cannot be read" test_runtime_dir_is_empty_when_the_owner_cannot_be_read

  _hi_h2 "Testing: the cache keys"
  _hi_check "Overlay key is stable for one member list" test_overlay_cache_key_is_stable_for_one_member_list
  _hi_check "Overlay key changes with the member list" test_overlay_cache_key_changes_with_the_member_list

  _hi_h2 "Testing: _hi_overlay_cached"
  _hi_check "Refuses an empty member list" test_overlay_cached_refuses_an_empty_member_list
  _hi_check "Off when _HI_PAYLOAD_CACHE=0" test_overlay_cached_is_off_when_the_toggle_is_zero
  _hi_check "Refuses without a runtime dir" test_overlay_cached_refuses_without_a_runtime_dir
  _hi_check "Builds cold and names the file" test_overlay_cached_builds_cold_and_names_the_file
  _hi_check "Leaves no temp file behind" test_overlay_cached_leaves_no_temp_file
  _hi_check "A failed build leaves nothing and answers 1" test_cached_cleans_up_after_a_failed_build
  _hi_check "Reuses a warm cache" test_overlay_cached_reuses_a_warm_cache
  _hi_check "Rebuilds when a member is newer" test_overlay_cached_rebuilds_when_a_member_is_newer
  _hi_check "Keys the file by member list" test_overlay_cached_keys_the_file_by_member_list

  _hi_h2 "Testing: the streams and the payload cache"
  _hi_check "Overlay stream is armored either way" test_overlay_stream_emits_an_armored_line_either_way
  _hi_check "Overlay stream is byte-identical off a warm cache" test_overlay_stream_is_byte_identical_off_a_warm_cache
  _hi_check "Payload cache builds cold then reuses it" test_payload_cached_builds_cold_then_reuses_it
  _hi_check "Payload cache rebuilds on a newer source file" test_payload_cached_rebuilds_when_a_source_file_is_newer
  _hi_check "Payload cache off when _HI_PAYLOAD_CACHE=0" test_payload_cached_is_off_when_the_toggle_is_zero
  _hi_check "Payload stream is byte-identical off a warm cache" test_payload_stream_is_byte_identical_off_a_warm_cache
  _hi_check "Payload stream is the same tree with the cache off" test_payload_stream_is_the_same_tree_with_the_cache_off

  _hi_h2 "Testing: _hi_ctl_open / _hi_ctl_close"
  _hi_check "Shared uses the runtime dir" test_ctl_open_shared_uses_the_runtime_dir
  _hi_check "Shared socket name stays short" test_ctl_open_shared_socket_name_stays_short
  _hi_check "Shared key splits on ssh args" test_ctl_open_shared_key_splits_on_ssh_args
  _hi_check "Shared key splits on the target" test_ctl_open_shared_key_splits_on_the_target
  _hi_check "Shared falls back when persist is 0" test_ctl_open_shared_falls_back_when_persist_is_zero
  _hi_check "Shared falls back without a runtime dir" test_ctl_open_shared_falls_back_without_a_runtime_dir
  _hi_check "Gives up quietly with nowhere to put a socket" test_ctl_open_gives_up_quietly_with_nowhere_to_put_a_socket
  _hi_check "No multiplexing on an MSYS client" test_ctl_open_declines_to_multiplex_on_msys
  _hi_check "run never shares" test_ctl_open_run_never_shares
  _hi_check_capable mode_bits "run's socket dir is private" test_ctl_open_run_socket_dir_is_private
  _hi_check "Extra ssh options are appended" test_ctl_open_appends_extra_ssh_options
  _hi_check "Close leaves a shared socket alone" test_ctl_close_leaves_a_shared_socket_alone
  _hi_check "Close removes a run socket dir" test_ctl_close_removes_a_run_socket_dir
  _hi_check "Close is a no-op with nothing open" test_ctl_close_is_a_noop_with_nothing_open

  _hi_suite_end "hi.sh caches and ControlMaster"
}

run_cache_tests
