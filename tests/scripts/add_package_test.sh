#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Unit tests for scripts/add_package.sh - `hi --add-package`, which adds
# rows to a group in ~/.config/say-hi/packages, and `hi --remove-package`,
# which takes them out.
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

# _hi_rmpkg_run <home> <config> <args...> - the same, for --remove-package
function _hi_rmpkg_run() {
  local home="$1" cfg="$2"
  shift 2
  _HI_CONFIG_DIR="$cfg" _hi_subcmd_run "$home" --remove-package "$@"
}

# _hi_addpkg_overlay <config> <body> - an existing overlay packages file
# holding <body> (%b, so \n is a line break)
function _hi_addpkg_overlay() {
  mkdir -p "$1"
  printf '%b' "$2" >"$1/packages"
}

# _hi_addpkg_is <file> <body> - <file> holds exactly <body> (%b)
function _hi_addpkg_is() {
  local want
  want="$(printf '%b' "$2")"
  [ "$(cat "$1")" = "$want" ] && return 0
  _hi_cecho " | got: [$(cat "$1")]" "$RED"
  return 1
}

# a real row known to be in the tree's config/packages, in its [core] group,
# used by several cases below to probe the copied/cascaded content without a
# second fixture
_HI_ADDPKG_KNOWN_ROW='bat,batcat,ccat,cat'

# _hi_addpkg_tree_lines <home> - how many lines the fixture tree's own
# packages file has, which every first write copies in ahead of its rows
function _hi_addpkg_tree_lines() {
  wc -l <"$1/say-hi/config/packages"
}

# --- arguments ---------------------------------------------------------------

function test_add_package_help_is_its_own() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-help)"
  cfg="$_HI_WORKDIR/addpkg-help-cfg"
  out="$(_hi_addpkg_run "$home" "$cfg" --help)" || return 1
  [[ "$out" == "Usage: hi --add-package <group> <pkg>[,...]"* && "$out" == *"-n, --dry-run"* && "$out" != *"--group"* ]]
}

function test_add_package_needs_a_group_and_a_row() {
  local home cfg out rc=0
  home="$(_hi_addpkg_fixture addpkg-norows)"
  cfg="$_HI_WORKDIR/addpkg-norows-cfg"
  out="$(_hi_addpkg_run "$home" "$cfg" --dry-run)" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"needs a group and at least one row"* ]] || return 1
  rc=0
  out="$(_hi_addpkg_run "$home" "$cfg" core --dry-run)" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"needs a group and at least one row"* ]]
}

# a group name is what a `[...]` line holds and $_HI_PACKAGES_GROUPS lists:
# no brackets, commas, spaces or leading dash, and not the word `none`
function test_add_package_rejects_a_bad_group_name() {
  local home cfg out rc bad
  home="$(_hi_addpkg_fixture addpkg-badgroup)"
  cfg="$_HI_WORKDIR/addpkg-badgroup-cfg"
  for bad in '[core]' 'a,b' 'my group' '-core' none; do
    rc=0
    out="$(_hi_addpkg_run "$home" "$cfg" "$bad" foo)" || rc=$?
    [ "$rc" -ne 0 ] && [[ "$out" == *"not a group name: $bad"* ]] || {
      _hi_cecho " | accepted group [$bad]" "$RED"
      return 1
    }
  done
  [ ! -e "$cfg/packages" ]
}

# every spelling check_line would misread is refused before anything is
# written: the old name:priority shape, a #, brackets, a space, a doubled
# marker, a marker on a later alternative, an empty alternative
function test_add_package_rejects_a_bad_row() {
  local home cfg out rc bad
  home="$(_hi_addpkg_fixture addpkg-badrow)"
  cfg="$_HI_WORKDIR/addpkg-badrow-cfg"
  for bad in 'bat:3' 'bat # note' '[bat]' 'bat batcat' '-+bat' 'bat,-batcat' 'bat,+batcat' 'bat,' ',bat'; do
    rc=0
    out="$(_hi_addpkg_run "$home" "$cfg" core "$bad")" || rc=$?
    [ "$rc" -ne 0 ] && [[ "$out" == *"not a package-check row"* ]] || {
      _hi_cecho " | accepted row [$bad]" "$RED"
      return 1
    }
  done
  [ ! -e "$cfg/packages" ]
}

# the group is positional, so no --group: it is an unknown option like any
# other, refused before anything is written
function test_add_package_rejects_group() {
  local home cfg out rc=0
  home="$(_hi_addpkg_fixture addpkg-group)"
  cfg="$_HI_WORKDIR/addpkg-group-cfg"
  out="$(_hi_addpkg_run "$home" "$cfg" core foo --group lang)" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"unknown option --group"* ]] && [ ! -e "$cfg/packages" ]
}

# with no overlay file yet, --dry-run names the copy the real run would make
# - and makes no directory at all, not just no file
function test_add_package_dry_run_writes_nothing() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-dry)"
  cfg="$_HI_WORKDIR/addpkg-dry-cfg"
  out="$(_hi_addpkg_run "$home" "$cfg" mine foo --dry-run)" || return 1
  [[ "$out" == *"dry run"* && "$out" == *"copy $home/say-hi/config/packages to $cfg/packages, then change it there"* ]] &&
    [ ! -d "$cfg" ]
}

# ...and with one, it names a plain write, leaving the file as it was
function test_add_package_dry_run_over_an_overlay() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-dry-overlay)"
  cfg="$_HI_WORKDIR/addpkg-dry-overlay-cfg"
  _hi_addpkg_overlay "$cfg" '[core]\ngo\n'
  out="$(_hi_addpkg_run "$home" "$cfg" core foo --dry-run)" || return 1
  [[ "$out" == *"write $cfg/packages"* && "$out" != *"copy "* ]] &&
    _hi_addpkg_is "$cfg/packages" '[core]\ngo'
}

# --- where a row lands -------------------------------------------------------

# a group the file does not have is created at the end, after a blank line
function test_add_package_creates_the_overlay_file_and_group() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-default)"
  cfg="$_HI_WORKDIR/addpkg-default-cfg"
  out="$(_hi_addpkg_run "$home" "$cfg" mine 'hi-no-such,hi-no-such-alt')" || return 1
  [[ "$out" == *"+ hi-no-such,hi-no-such-alt in [mine]"* && "$out" == *"$cfg/packages updated"* ]] || return 1
  [ "$(tail -n 3 "$cfg/packages")" = "$(printf '\n[mine]\nhi-no-such,hi-no-such-alt')" ]
}

function test_add_package_several_arguments_are_several_rows() {
  local home cfg
  home="$(_hi_addpkg_fixture addpkg-multi)"
  cfg="$_HI_WORKDIR/addpkg-multi-cfg"
  _hi_addpkg_overlay "$cfg" '[core]\ngo\n'
  _hi_addpkg_run "$home" "$cfg" mine foo -baz +qux ssh-keygen,x-y >/dev/null || return 1
  _hi_addpkg_is "$cfg/packages" '[core]\ngo\n\n[mine]\nfoo\n-baz\n+qux\nssh-keygen,x-y'
}

# into an existing group: after its last row, ahead of a comment or blank
# line trailing it and of the next group
function test_add_package_joins_an_existing_group() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-join)"
  cfg="$_HI_WORKDIR/addpkg-join-cfg"
  _hi_addpkg_overlay "$cfg" '[a]\nx\n# about b\n\n[b]\ny\n'
  out="$(_hi_addpkg_run "$home" "$cfg" a z)" || return 1
  [[ "$out" == *"+ z in [a]"* ]] &&
    _hi_addpkg_is "$cfg/packages" '[a]\nx\nz\n# about b\n\n[b]\ny'
}

# a row naming the same first package in the same group replaces it in place
# rather than duplicating it - its marker is not part of that name
function test_add_package_replaces_same_first_package() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-replace)"
  cfg="$_HI_WORKDIR/addpkg-replace-cfg"
  _hi_addpkg_overlay "$cfg" '[a]\nbat,batcat\nx\n[b]\ny\n'
  out="$(_hi_addpkg_run "$home" "$cfg" a '-bat')" || return 1
  [[ "$out" == *"~ -bat (replacing the row for bat in [a])"* ]] &&
    _hi_addpkg_is "$cfg/packages" '[a]\n-bat\nx\n[b]\ny'
}

# ...and in another group, it moves there - even an identical row, which is
# not "already there" when it sits in the wrong group
function test_add_package_moves_a_row_between_groups() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-move)"
  cfg="$_HI_WORKDIR/addpkg-move-cfg"
  _hi_addpkg_overlay "$cfg" '[a]\nbat\nx\n[b]\ny\n'
  out="$(_hi_addpkg_run "$home" "$cfg" b bat)" || return 1
  [[ "$out" == *"~ bat (moving the row for bat from [a] to [b])"* ]] &&
    _hi_addpkg_is "$cfg/packages" '[a]\nx\n[b]\ny\nbat'
}

# a row above the first header is in no group, and moves out of there too
function test_add_package_moves_an_ungrouped_row() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-move-top)"
  cfg="$_HI_WORKDIR/addpkg-move-top-cfg"
  _hi_addpkg_overlay "$cfg" 'top\n[b]\ny\n'
  out="$(_hi_addpkg_run "$home" "$cfg" b top)" || return 1
  [[ "$out" == *"moving the row for top from [no group] to [b]"* ]] &&
    _hi_addpkg_is "$cfg/packages" '[b]\ny\ntop'
}

# the exact same row in the same group changes nothing and writes nothing
function test_add_package_identical_row_is_a_no_op() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-noop)"
  cfg="$_HI_WORKDIR/addpkg-noop-cfg"
  _hi_addpkg_overlay "$cfg" '[a]\nfoo\n'
  out="$(_hi_addpkg_run "$home" "$cfg" a foo)" || return 1
  [[ "$out" == *"$cfg/packages: foo is already in [a]"* && "$out" == *"needs no change - nothing to write"* ]] &&
    _hi_addpkg_is "$cfg/packages" '[a]\nfoo'
}

# comments already in an overlay file survive a write - the read-rewrite loop
# carries every line it does not itself replace or add - and an existing
# overlay file is extended as it is, the tree's rows not copied in again
function test_add_package_preserves_comments() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-comment)"
  cfg="$_HI_WORKDIR/addpkg-comment-cfg"
  _hi_addpkg_overlay "$cfg" '# a hand-written note\n[a]\ngo\n'
  out="$(_hi_addpkg_run "$home" "$cfg" a cargo)" || return 1
  [[ "$out" == *"+ cargo in [a]"* ]] &&
    _hi_addpkg_is "$cfg/packages" '# a hand-written note\n[a]\ngo\ncargo'
}

# the written row is what the check itself reads back, not just a file that
# looks right - $_HI_HEADER is this dev tree's, and its paths.sh finds the
# fixture's freshly-written packages file in $_HI_CONFIG_DIR. The row sits in
# its new group, so it prints when that group runs and not otherwise.
function test_add_package_written_row_reaches_the_check() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-integration)"
  cfg="$_HI_WORKDIR/addpkg-integration-cfg"
  _hi_addpkg_run "$home" "$cfg" mine "$_HI_REAL_CMD" >/dev/null || return 1
  out="$(NO_COLOR=1 _HI_CONFIG_DIR="$cfg" _HI_PACKAGES_GROUPS=mine \
    bash -c 'source "$_HI_HEADER"; full_check')"
  [[ "$out" == *" $_HI_REAL_CMD "* ]] || return 1
  out="$(NO_COLOR=1 _HI_CONFIG_DIR="$cfg" _HI_PACKAGES_GROUPS=none \
    bash -c 'source "$_HI_HEADER"; full_check')"
  [[ "$out" != *" $_HI_REAL_CMD "* ]]
}

# --- the overlay file replaces the tree's wholesale, so the first write
# copies the tree's rows in: nothing shipped vanishes the moment a row is
# added ---------------------------------------------------------------------

function test_add_package_first_call_copies_the_tree_in() {
  local home cfg n
  home="$(_hi_addpkg_fixture addpkg-seed)"
  cfg="$_HI_WORKDIR/addpkg-seed-cfg"
  _hi_addpkg_run "$home" "$cfg" mine foo >/dev/null || return 1
  n="$(_hi_addpkg_tree_lines "$home")"
  # the tree's lines, then a blank, [mine], and the row
  [ "$(wc -l <"$cfg/packages")" -eq "$((n + 3))" ] &&
    head -n "$n" "$cfg/packages" | cmp -s - "$home/say-hi/config/packages"
}

# a second call does not re-copy or clobber what the first one wrote
function test_add_package_second_call_does_not_recopy() {
  local home cfg
  home="$(_hi_addpkg_fixture addpkg-noreseed)"
  cfg="$_HI_WORKDIR/addpkg-noreseed-cfg"
  _hi_addpkg_run "$home" "$cfg" a foo >/dev/null || return 1
  printf '[a]\ntruncated\n' >"$cfg/packages"
  _hi_addpkg_run "$home" "$cfg" a bar >/dev/null || return 1
  _hi_addpkg_is "$cfg/packages" '[a]\ntruncated\nbar'
}

# --dry-run reads through the cascade too: a row already in the tree's file
# reports "already in" against the tree, not "+" against an empty file it
# never wrote - pins the read/write split in add_package.sh
function test_add_package_dry_run_reads_through_the_cascade() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-dry-cascade)"
  cfg="$_HI_WORKDIR/addpkg-dry-cascade-cfg"
  out="$(_hi_addpkg_run "$home" "$cfg" core "$_HI_ADDPKG_KNOWN_ROW" --dry-run)" || return 1
  [[ "$out" == *"config/packages: $_HI_ADDPKG_KNOWN_ROW is already in [core]"* && "$out" != *"+ $_HI_ADDPKG_KNOWN_ROW"* ]] &&
    [ ! -d "$cfg" ]
}

# ...and without --dry-run: a true no-op (the row is already covered by the
# tree) creates no overlay at all
function test_add_package_true_noop_creates_no_overlay() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-true-noop)"
  cfg="$_HI_WORKDIR/addpkg-true-noop-cfg"
  out="$(_hi_addpkg_run "$home" "$cfg" core "$_HI_ADDPKG_KNOWN_ROW")" || return 1
  [[ "$out" == *"config/packages needs no change - nothing to write"* ]] && [ ! -d "$cfg" ]
}

# --- --remove-package -------------------------------------------------------

function test_remove_package_help_is_its_own() {
  local home cfg out
  home="$(_hi_addpkg_fixture rmpkg-help)"
  cfg="$_HI_WORKDIR/rmpkg-help-cfg"
  out="$(_hi_rmpkg_run "$home" "$cfg" --help)" || return 1
  [[ "$out" == "Usage: hi --remove-package <pkg>..."* && "$out" == *"-n, --dry-run"* ]]
}

function test_remove_package_needs_a_package() {
  local home cfg out rc=0
  home="$(_hi_addpkg_fixture rmpkg-none)"
  cfg="$_HI_WORKDIR/rmpkg-none-cfg"
  out="$(_hi_rmpkg_run "$home" "$cfg" --dry-run)" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"needs at least one package"* ]]
}

# a row goes by its first package, whatever group it sits in and whatever
# marker it carries; the group headers stay
function test_remove_package_removes_by_first_package() {
  local home cfg out
  home="$(_hi_addpkg_fixture rmpkg-rows)"
  cfg="$_HI_WORKDIR/rmpkg-rows-cfg"
  _hi_addpkg_overlay "$cfg" '[a]\n-exa\nx\n[b]\nbat,batcat\n'
  out="$(_hi_rmpkg_run "$home" "$cfg" exa bat)" || return 1
  [[ "$out" == *"- -exa (from [a])"* && "$out" == *"- bat,batcat (from [b])"* ]] &&
    _hi_addpkg_is "$cfg/packages" '[a]\nx\n[b]'
}

# a package with no row is said so, and nothing is written
function test_remove_package_without_a_row_is_a_no_op() {
  local home cfg out
  home="$(_hi_addpkg_fixture rmpkg-miss)"
  cfg="$_HI_WORKDIR/rmpkg-miss-cfg"
  _hi_addpkg_overlay "$cfg" '[a]\nx\n'
  out="$(_hi_rmpkg_run "$home" "$cfg" nope)" || return 1
  [[ "$out" == *"no row for nope"* && "$out" == *"needs no change - nothing to write"* ]] &&
    _hi_addpkg_is "$cfg/packages" '[a]\nx'
}

# with no overlay yet, removing a shipped row copies the tree in without it
function test_remove_package_copies_the_tree_in_without_the_row() {
  local home cfg n
  home="$(_hi_addpkg_fixture rmpkg-seed)"
  cfg="$_HI_WORKDIR/rmpkg-seed-cfg"
  _hi_rmpkg_run "$home" "$cfg" bat >/dev/null || return 1
  n="$(_hi_addpkg_tree_lines "$home")"
  [ "$(wc -l <"$cfg/packages")" -eq "$((n - 1))" ] &&
    ! grep -qxF "$_HI_ADDPKG_KNOWN_ROW" "$cfg/packages" &&
    grep -qxF '[core]' "$cfg/packages"
}

function run_add_package_tests() {
  _hi_workdir addpackage
  _hi_suite_begin
  # a real command already on PATH, so the integration case's check_line
  # probe finds it installed regardless of what this box has - header_test.sh's
  # own fixture command
  # shellcheck disable=SC2209
  _HI_REAL_CMD=sh

  _hi_h2 "Testing: scripts/add_package.sh arguments"
  _hi_check "--add-package --help is its own text" test_add_package_help_is_its_own
  _hi_check "No group or no row is refused" test_add_package_needs_a_group_and_a_row
  _hi_check "A bad group name is refused, nothing written" test_add_package_rejects_a_bad_group_name
  _hi_check "A row check_line would misread is refused" test_add_package_rejects_a_bad_row
  _hi_check "--group is an unknown option, nothing written" test_add_package_rejects_group
  _hi_check "--dry-run names the copy and writes nothing" test_add_package_dry_run_writes_nothing
  _hi_check "--dry-run over an overlay names a plain write" test_add_package_dry_run_over_an_overlay

  _hi_h2 "Testing: where a row lands in ~/.config/say-hi/packages"
  _hi_check "Creates the overlay file, and a missing group at the end" test_add_package_creates_the_overlay_file_and_group
  _hi_check "Several arguments are several rows, markers and inner dashes kept" test_add_package_several_arguments_are_several_rows
  _hi_check "Joins an existing group after its last row" test_add_package_joins_an_existing_group
  _hi_check "The same first package in the group is replaced" test_add_package_replaces_same_first_package
  _hi_check "...in another group, it moves" test_add_package_moves_a_row_between_groups
  _hi_check "...and out of no group" test_add_package_moves_an_ungrouped_row
  _hi_check "The identical row in its group is a no-op" test_add_package_identical_row_is_a_no_op
  _hi_check "Comments survive, an overlay file is kept as is" test_add_package_preserves_comments
  _hi_check "The written row reaches full_check under its group" test_add_package_written_row_reaches_the_check

  _hi_h2 "Testing: wholesale replace, and the first write's copy"
  _hi_check "First call copies the tree's rows in" test_add_package_first_call_copies_the_tree_in
  _hi_check "A second call does not re-copy or clobber" test_add_package_second_call_does_not_recopy
  _hi_check "--dry-run reads through the cascade" test_add_package_dry_run_reads_through_the_cascade
  _hi_check "A true no-op creates no overlay" test_add_package_true_noop_creates_no_overlay

  _hi_h2 "Testing: --remove-package"
  _hi_check "--remove-package --help is its own text" test_remove_package_help_is_its_own
  _hi_check "No package is refused" test_remove_package_needs_a_package
  _hi_check "Removes by first package, any group or marker" test_remove_package_removes_by_first_package
  _hi_check "A package with no row writes nothing" test_remove_package_without_a_row_is_a_no_op
  _hi_check "First call copies the tree in, minus the row" test_remove_package_copies_the_tree_in_without_the_row

  _hi_suite_end "scripts/add_package.sh"
}

run_add_package_tests
