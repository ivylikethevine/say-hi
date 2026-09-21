#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Unit tests for scripts/add_package.sh - `hi --add-package`, which adds
# rows to ~/.config/say-hi/packages.
#
# Driven through `hi.sh --add-package` rather than by calling the script
# directly, so the common/flags row and _hi_dispatch_subcommand are covered
# with it, the way tests/scripts/update_test.sh drives --update. Each case
# gets its own $_HI_CONFIG_DIR (an env override on the _hi_subcmd_run call,
# GNUPGHOME's idiom in update_test.sh) rather than sharing test_lib.sh's one
# throwaway overlay, so one case's packages file cannot bleed into another's.
#
# GLOSSARY: HI.34.
# shellcheck disable=SC2329,SC2317
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# _hi_addpkg_fixture <name> - a target-shaped tree with scripts/ added, the
# one thing that makes --add-package reachable at all (a bare session has no
# scripts/, and hi.sh says so and stops - that case is tests/hi/parse_test.sh's
# with the other subcommands, not this file's). Prints the fixture's _HI_HOME.
function _hi_addpkg_fixture() {
  _hi_scratch_tree "$1" common config load.sh hi.sh scripts
}

# _hi_addpkg_run <home> <config> <args...> - _hi_subcmd_run with its own
# overlay directory, so the packages file each case writes is one nothing
# else reads.
function _hi_addpkg_run() {
  local home="$1" cfg="$2"
  shift 2
  _HI_CONFIG_DIR="$cfg" _hi_subcmd_run "$home" --add-package "$@"
}

# a real row known to be in the tree's config/packages, used by several
# cases below to probe the copied/cascaded content without a second fixture
_HI_ADDPKG_KNOWN_ROW='bat:3,batcat:3,ccat:3,cat:2'

# _hi_addpkg_tree_lines <home> - how many lines the fixture tree's own
# packages file has, which every first write copies in ahead of its rows
function _hi_addpkg_tree_lines() {
  wc -l <"$1/say-hi/config/packages"
}

function test_add_package_creates_the_overlay_file() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-default)"
  cfg="$_HI_WORKDIR/addpkg-default-cfg"
  out="$(_hi_addpkg_run "$home" "$cfg" 'hi-no-such:3,hi-no-such-alt:3')" || return 1
  [[ "$out" == *"+ hi-no-such:3,hi-no-such-alt:3"* && "$out" == *"$cfg/packages updated"* ]] || return 1
  [ "$(tail -n 1 "$cfg/packages")" = "hi-no-such:3,hi-no-such-alt:3" ]
}

function test_add_package_several_arguments_are_several_rows() {
  local home cfg
  home="$(_hi_addpkg_fixture addpkg-multi)"
  cfg="$_HI_WORKDIR/addpkg-multi-cfg"
  _hi_addpkg_run "$home" "$cfg" foo:3 baz:3 >/dev/null || return 1
  [ "$(wc -l <"$cfg/packages")" -eq "$(($(_hi_addpkg_tree_lines "$home") + 2))" ] &&
    grep -qxF foo:3 "$cfg/packages" && grep -qxF baz:3 "$cfg/packages"
}

# a second call reads the overlay file the first one wrote and appends to it
function test_add_package_second_call_appends() {
  local home cfg
  home="$(_hi_addpkg_fixture addpkg-append)"
  cfg="$_HI_WORKDIR/addpkg-append-cfg"
  _hi_addpkg_run "$home" "$cfg" foo:3 >/dev/null || return 1
  _hi_addpkg_run "$home" "$cfg" baz:3 >/dev/null || return 1
  grep -qxF foo:3 "$cfg/packages" && grep -qxF baz:3 "$cfg/packages"
}

# a row naming the same first package replaces it in place rather than
# duplicating it - here the tree's own bat row, carried over by the copy
function test_add_package_replaces_same_first_package() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-replace)"
  cfg="$_HI_WORKDIR/addpkg-replace-cfg"
  out="$(_hi_addpkg_run "$home" "$cfg" 'bat:1')" || return 1
  [[ "$out" == *"~ bat:1 (replacing the row for bat)"* ]] || return 1
  [ "$(wc -l <"$cfg/packages")" -eq "$(_hi_addpkg_tree_lines "$home")" ] &&
    grep -qxF bat:1 "$cfg/packages" && ! grep -qxF "$_HI_ADDPKG_KNOWN_ROW" "$cfg/packages"
}

# the exact same row a second time changes nothing and writes nothing
function test_add_package_identical_row_is_a_no_op() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-noop)"
  cfg="$_HI_WORKDIR/addpkg-noop-cfg"
  _hi_addpkg_run "$home" "$cfg" 'foo:3' >/dev/null || return 1
  out="$(_hi_addpkg_run "$home" "$cfg" 'foo:3')" || return 1
  [[ "$out" == *"$cfg/packages: foo:3 is already there"* ]] || return 1
  [ "$(grep -cxF foo:3 "$cfg/packages")" -eq 1 ]
}

# comments already in an overlay file survive a write - the read-rewrite loop
# carries every line it does not itself replace or append - and an existing
# overlay file is extended as it is, the tree's rows not copied in again
function test_add_package_preserves_comments() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-comment)"
  cfg="$_HI_WORKDIR/addpkg-comment-cfg"
  mkdir -p "$cfg"
  printf '# a hand-written note\ngo:3\n' >"$cfg/packages"
  out="$(_hi_addpkg_run "$home" "$cfg" cargo:3)" || return 1
  [[ "$out" == *"+ cargo:3"* ]] || return 1
  [ "$(cat "$cfg/packages")" = "$(printf '# a hand-written note\ngo:3\ncargo:3')" ]
}

function test_add_package_rejects_a_bad_priority() {
  local home cfg out rc=0
  home="$(_hi_addpkg_fixture addpkg-badprio)"
  cfg="$_HI_WORKDIR/addpkg-badprio-cfg"
  out="$(_hi_addpkg_run "$home" "$cfg" 'bat:9')" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"not a package-check row"* ]] && [ ! -e "$cfg/packages" ]
}

function test_add_package_rejects_a_bare_package_with_no_colon() {
  local home cfg out rc=0
  home="$(_hi_addpkg_fixture addpkg-nocolon)"
  cfg="$_HI_WORKDIR/addpkg-nocolon-cfg"
  out="$(_hi_addpkg_run "$home" "$cfg" bat)" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"not a package-check row"* ]] && [ ! -e "$cfg/packages" ]
}

function test_add_package_rejects_a_hash_anywhere() {
  local home cfg out rc=0
  home="$(_hi_addpkg_fixture addpkg-hash)"
  cfg="$_HI_WORKDIR/addpkg-hash-cfg"
  out="$(_hi_addpkg_run "$home" "$cfg" 'bat:3 # trailing note')" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"not a package-check row"* ]] && [ ! -e "$cfg/packages" ]
}

# there is one file, so no --group: it is an unknown option like any other,
# refused before anything is written
function test_add_package_rejects_group() {
  local home cfg out rc=0
  home="$(_hi_addpkg_fixture addpkg-group)"
  cfg="$_HI_WORKDIR/addpkg-group-cfg"
  out="$(_hi_addpkg_run "$home" "$cfg" foo:3 --group lang)" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"unknown option --group"* ]] && [ ! -e "$cfg/packages" ]
}

function test_add_package_needs_at_least_one_row() {
  local home cfg out rc=0
  home="$(_hi_addpkg_fixture addpkg-norows)"
  cfg="$_HI_WORKDIR/addpkg-norows-cfg"
  out="$(_hi_addpkg_run "$home" "$cfg" --dry-run)" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"needs at least one"* ]]
}

# with no overlay file yet, --dry-run names the copy the real run would make
# - and makes no directory at all, not just no file
function test_add_package_dry_run_writes_nothing() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-dry)"
  cfg="$_HI_WORKDIR/addpkg-dry-cfg"
  out="$(_hi_addpkg_run "$home" "$cfg" 'foo:3' --dry-run)" || return 1
  [[ "$out" == *"dry run"* && "$out" == *"copy $home/say-hi/config/packages to $cfg/packages, then add there"* ]] &&
    [ ! -d "$cfg" ]
}

# ...and with one, it names a plain write, leaving the file as it was
function test_add_package_dry_run_over_an_overlay() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-dry-overlay)"
  cfg="$_HI_WORKDIR/addpkg-dry-overlay-cfg"
  mkdir -p "$cfg"
  printf 'go:3\n' >"$cfg/packages"
  out="$(_hi_addpkg_run "$home" "$cfg" 'foo:3' --dry-run)" || return 1
  [[ "$out" == *"write $cfg/packages"* && "$out" != *"copy "* ]] && [ "$(cat "$cfg/packages")" = go:3 ]
}

function test_add_package_help_is_its_own() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-help)"
  cfg="$_HI_WORKDIR/addpkg-help-cfg"
  out="$(_hi_addpkg_run "$home" "$cfg" --help)" || return 1
  [[ "$out" == "Usage: hi --add-package"* && "$out" == *"-n, --dry-run"* && "$out" != *"--group"* ]]
}

# the written row is what the check itself reads back, not just a file that
# looks right - $_HI_HEADER is this dev tree's, pointed at the fixture's
# freshly-written packages file
function test_add_package_written_row_reaches_the_check() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-integration)"
  cfg="$_HI_WORKDIR/addpkg-integration-cfg"
  _hi_addpkg_run "$home" "$cfg" "$_HI_REAL_CMD:3" >/dev/null || return 1
  out="$(NO_COLOR=1 _HI_PACKAGES="$cfg/packages" bash -c 'source "$_HI_HEADER"; full_check')"
  [[ "$out" == *"$_HI_REAL_CMD"* ]]
}

# --- the overlay file replaces the tree's wholesale, so the first write
# copies the tree's rows in: nothing shipped vanishes the moment a row is
# added ---------------------------------------------------------------------

function test_add_package_first_call_copies_the_tree_in() {
  local home cfg n
  home="$(_hi_addpkg_fixture addpkg-seed)"
  cfg="$_HI_WORKDIR/addpkg-seed-cfg"
  _hi_addpkg_run "$home" "$cfg" foo:1 >/dev/null || return 1
  n="$(_hi_addpkg_tree_lines "$home")"
  [ "$(wc -l <"$cfg/packages")" -eq "$((n + 1))" ] &&
    head -n "$n" "$cfg/packages" | cmp -s - "$home/say-hi/config/packages"
}

# a second call does not re-copy or clobber what the first one wrote
function test_add_package_second_call_does_not_recopy() {
  local home cfg
  home="$(_hi_addpkg_fixture addpkg-noreseed)"
  cfg="$_HI_WORKDIR/addpkg-noreseed-cfg"
  _hi_addpkg_run "$home" "$cfg" foo:1 >/dev/null || return 1
  printf 'truncated:1\n' >"$cfg/packages"
  _hi_addpkg_run "$home" "$cfg" bar:1 >/dev/null || return 1
  [ "$(cat "$cfg/packages")" = "$(printf 'truncated:1\nbar:1')" ]
}

# --dry-run reads through the cascade too: a row already in the tree's file
# reports "already there" against the tree, not "+" against an empty file it
# never wrote - pins the read/write split in add_package.sh
function test_add_package_dry_run_reads_through_the_cascade() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-dry-cascade)"
  cfg="$_HI_WORKDIR/addpkg-dry-cascade-cfg"
  out="$(_hi_addpkg_run "$home" "$cfg" "$_HI_ADDPKG_KNOWN_ROW" --dry-run)" || return 1
  [[ "$out" == *"config/packages: $_HI_ADDPKG_KNOWN_ROW is already there"* && "$out" != *"+ $_HI_ADDPKG_KNOWN_ROW"* ]] &&
    [ ! -d "$cfg" ]
}

# ...and without --dry-run: a true no-op (the row is already covered by the
# tree) creates no overlay at all
function test_add_package_true_noop_creates_no_overlay() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-true-noop)"
  cfg="$_HI_WORKDIR/addpkg-true-noop-cfg"
  out="$(_hi_addpkg_run "$home" "$cfg" "$_HI_ADDPKG_KNOWN_ROW")" || return 1
  [[ "$out" == *"config/packages already has every row given - nothing to write"* ]] && [ ! -d "$cfg" ]
}

function run_add_package_tests() {
  _hi_workdir addpackage
  _hi_suite_begin
  # a real command already on PATH, so the integration case's check_line
  # probe finds it installed regardless of what this box has - header_test.sh's
  # own fixture command
  # shellcheck disable=SC2209
  _HI_REAL_CMD=sh

  _hi_h2 "Testing: scripts/add_package.sh"
  _hi_check "--add-package --help is its own text" test_add_package_help_is_its_own
  _hi_check "No rows is refused" test_add_package_needs_at_least_one_row
  _hi_check "--group is an unknown option, nothing written" test_add_package_rejects_group
  _hi_check "A bad priority is refused, nothing written" test_add_package_rejects_a_bad_priority
  _hi_check "A bare package with no : is refused" test_add_package_rejects_a_bare_package_with_no_colon
  _hi_check "A # anywhere on the row is refused" test_add_package_rejects_a_hash_anywhere
  _hi_check "--dry-run names the copy and writes nothing" test_add_package_dry_run_writes_nothing
  _hi_check "--dry-run over an overlay names a plain write" test_add_package_dry_run_over_an_overlay

  _hi_h2 "Testing: writing ~/.config/say-hi/packages"
  _hi_check "Creates the overlay's packages file" test_add_package_creates_the_overlay_file
  _hi_check "Several arguments are several rows" test_add_package_several_arguments_are_several_rows
  _hi_check "A second call appends rather than replacing" test_add_package_second_call_appends
  _hi_check "A row for the same first package replaces it" test_add_package_replaces_same_first_package
  _hi_check "The identical row again is a no-op" test_add_package_identical_row_is_a_no_op
  _hi_check "Comments survive, an overlay file is kept as is" test_add_package_preserves_comments
  _hi_check "The written row reaches full_check" test_add_package_written_row_reaches_the_check

  _hi_h2 "Testing: wholesale replace, and the first write's copy"
  _hi_check "First call copies the tree's rows in" test_add_package_first_call_copies_the_tree_in
  _hi_check "A second call does not re-copy or clobber" test_add_package_second_call_does_not_recopy
  _hi_check "--dry-run reads through the cascade" test_add_package_dry_run_reads_through_the_cascade
  _hi_check "A true no-op creates no overlay" test_add_package_true_noop_creates_no_overlay

  _hi_suite_end "scripts/add_package.sh"
}

run_add_package_tests
