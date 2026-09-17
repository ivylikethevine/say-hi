#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Unit tests for scripts/add_package.sh - `hi --add-package`, which appends
# rows to a ~/.config/say-hi/packages.d/ group.
#
# Driven through `hi.sh --add-package` rather than by calling the script
# directly, so the common/flags row and _hi_dispatch_subcommand are covered
# with it, the way tests/scripts/update_test.sh drives --update. Each case
# gets its own $_HI_CONFIG_DIR (an env override on the _hi_subcmd_run call,
# GNUPGHOME's idiom in update_test.sh) rather than sharing test_lib.sh's one
# throwaway overlay, so one case's group file cannot bleed into another's.
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
  _hi_scratch_tree "$1" common settings load.sh hi.sh scripts
}

# _hi_addpkg_run <home> <config> <args...> - _hi_subcmd_run with its own
# overlay directory, so the group file each case writes is one nothing else
# reads.
function _hi_addpkg_run() {
  local home="$1" cfg="$2"
  shift 2
  _HI_CONFIG_DIR="$cfg" _hi_subcmd_run "$home" --add-package "$@"
}

function test_add_package_creates_the_default_group() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-default)"
  cfg="$_HI_WORKDIR/addpkg-default-cfg"
  out="$(_hi_addpkg_run "$home" "$cfg" 'bat:3,batcat:3')" || return 1
  [[ "$out" == *"+ bat:3,batcat:3"* ]] || return 1
  [ -f "$cfg/packages.d/custom" ] || return 1
  [ "$(cat "$cfg/packages.d/custom")" = "bat:3,batcat:3" ]
}

function test_add_package_group_names_another_file() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-group)"
  cfg="$_HI_WORKDIR/addpkg-group-cfg"
  out="$(_hi_addpkg_run "$home" "$cfg" go:3,cargo:3 --group lang)" || return 1
  [[ "$out" == *"+ go:3,cargo:3"* ]] || return 1
  [ -f "$cfg/packages.d/lang" ] && [ ! -e "$cfg/packages.d/custom" ]
}

function test_add_package_several_arguments_are_several_rows() {
  local home cfg
  home="$(_hi_addpkg_fixture addpkg-multi)"
  cfg="$_HI_WORKDIR/addpkg-multi-cfg"
  _hi_addpkg_run "$home" "$cfg" bat:3 jq:3 >/dev/null || return 1
  [ "$(wc -l <"$cfg/packages.d/custom")" -eq 2 ] &&
    grep -qxF bat:3 "$cfg/packages.d/custom" && grep -qxF jq:3 "$cfg/packages.d/custom"
}

# a second call appends, rather than the group file replacing the way a
# hand-made ~/.config/say-hi/packages would
function test_add_package_second_call_appends() {
  local home cfg
  home="$(_hi_addpkg_fixture addpkg-append)"
  cfg="$_HI_WORKDIR/addpkg-append-cfg"
  _hi_addpkg_run "$home" "$cfg" bat:3 >/dev/null || return 1
  _hi_addpkg_run "$home" "$cfg" jq:3 >/dev/null || return 1
  grep -qxF bat:3 "$cfg/packages.d/custom" && grep -qxF jq:3 "$cfg/packages.d/custom"
}

# a row naming the same first package replaces it in place rather than
# duplicating the group
function test_add_package_replaces_same_first_package() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-replace)"
  cfg="$_HI_WORKDIR/addpkg-replace-cfg"
  _hi_addpkg_run "$home" "$cfg" 'bat:2' >/dev/null || return 1
  out="$(_hi_addpkg_run "$home" "$cfg" 'bat:3,batcat:3')" || return 1
  [[ "$out" == *"~ bat:3,batcat:3"* ]] || return 1
  [ "$(wc -l <"$cfg/packages.d/custom")" -eq 1 ] &&
    [ "$(cat "$cfg/packages.d/custom")" = "bat:3,batcat:3" ]
}

# the exact same row a second time changes nothing and writes nothing
function test_add_package_identical_row_is_a_no_op() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-noop)"
  cfg="$_HI_WORKDIR/addpkg-noop-cfg"
  _hi_addpkg_run "$home" "$cfg" 'bat:3' >/dev/null || return 1
  out="$(_hi_addpkg_run "$home" "$cfg" 'bat:3')" || return 1
  [[ "$out" == *"already there"* ]] || return 1
  [ "$(wc -l <"$cfg/packages.d/custom")" -eq 1 ] && [ "$(cat "$cfg/packages.d/custom")" = "bat:3" ]
}

# a color= line and comments already in the group survive a write - the
# read-rewrite loop carries every line it does not itself replace or append
function test_add_package_preserves_comments_and_color_line() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-color)"
  cfg="$_HI_WORKDIR/addpkg-color-cfg"
  mkdir -p "$cfg/packages.d"
  printf 'color=orange\n# a hand-written note\ngo:3\n' >"$cfg/packages.d/lang"
  out="$(_hi_addpkg_run "$home" "$cfg" cargo:3 --group lang)" || return 1
  [[ "$out" == *"+ cargo:3"* ]] || return 1
  grep -qxF 'color=orange' "$cfg/packages.d/lang" &&
    grep -qxF '# a hand-written note' "$cfg/packages.d/lang" &&
    grep -qxF 'go:3' "$cfg/packages.d/lang" &&
    grep -qxF 'cargo:3' "$cfg/packages.d/lang"
}

function test_add_package_rejects_a_bad_priority() {
  local home cfg out rc=0
  home="$(_hi_addpkg_fixture addpkg-badprio)"
  cfg="$_HI_WORKDIR/addpkg-badprio-cfg"
  out="$(_hi_addpkg_run "$home" "$cfg" 'bat:9')" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"not a package-check row"* ]] && [ ! -e "$cfg/packages.d/custom" ]
}

function test_add_package_rejects_a_bare_package_with_no_colon() {
  local home cfg out rc=0
  home="$(_hi_addpkg_fixture addpkg-nocolon)"
  cfg="$_HI_WORKDIR/addpkg-nocolon-cfg"
  out="$(_hi_addpkg_run "$home" "$cfg" bat)" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"not a package-check row"* ]] && [ ! -e "$cfg/packages.d/custom" ]
}

function test_add_package_rejects_a_hash_anywhere() {
  local home cfg out rc=0
  home="$(_hi_addpkg_fixture addpkg-hash)"
  cfg="$_HI_WORKDIR/addpkg-hash-cfg"
  out="$(_hi_addpkg_run "$home" "$cfg" 'bat:3 # trailing note')" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"not a package-check row"* ]] && [ ! -e "$cfg/packages.d/custom" ]
}

function test_add_package_rejects_a_bad_group_name() {
  local home cfg out rc=0
  home="$(_hi_addpkg_fixture addpkg-badgroup)"
  cfg="$_HI_WORKDIR/addpkg-badgroup-cfg"
  out="$(_hi_addpkg_run "$home" "$cfg" bat:3 --group '../escape')" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"is not a plain name"* ]] && [ ! -d "$cfg/packages.d" ]
}

function test_add_package_needs_at_least_one_row() {
  local home cfg out rc=0
  home="$(_hi_addpkg_fixture addpkg-norows)"
  cfg="$_HI_WORKDIR/addpkg-norows-cfg"
  out="$(_hi_addpkg_run "$home" "$cfg" --group lang)" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"needs at least one"* ]]
}

function test_add_package_dry_run_writes_nothing() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-dry)"
  cfg="$_HI_WORKDIR/addpkg-dry-cfg"
  out="$(_hi_addpkg_run "$home" "$cfg" 'bat:3' --dry-run)" || return 1
  [[ "$out" == *"dry run"* ]] && [ ! -e "$cfg/packages.d/custom" ]
}

# --group with no name, joined or next-word, is refused rather than eating a
# row as the name
function test_add_package_group_needs_a_name() {
  local home cfg out rc=0
  home="$(_hi_addpkg_fixture addpkg-groupval)"
  cfg="$_HI_WORKDIR/addpkg-groupval-cfg"
  out="$(_hi_addpkg_run "$home" "$cfg" --group)" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"--group needs a name"* ]]
}

function test_add_package_help_is_its_own() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-help)"
  cfg="$_HI_WORKDIR/addpkg-help-cfg"
  out="$(_hi_addpkg_run "$home" "$cfg" --help)" || return 1
  [[ "$out" == "Usage: hi --add-package"* && "$out" == *"--group <name>"* && "$out" == *"-n, --dry-run"* ]]
}

# the written row is what the check itself reads back, not just a file that
# looks right - $_HI_HEADER is this dev tree's, pointed at the fixture's
# freshly-written packages.d
function test_add_package_written_row_reaches_the_check() {
  local home cfg out
  home="$(_hi_addpkg_fixture addpkg-integration)"
  cfg="$_HI_WORKDIR/addpkg-integration-cfg"
  _hi_addpkg_run "$home" "$cfg" "$_HI_REAL_CMD:3" >/dev/null || return 1
  out="$(NO_COLOR=1 _HI_PACKAGES="$cfg/packages" _HI_PACKAGES_D="$cfg/packages.d" \
    bash -c 'source "$_HI_HEADER"; full_check')"
  [[ "$out" == *"$_HI_REAL_CMD"* ]]
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
  _hi_check "--group with no name is refused" test_add_package_group_needs_a_name
  _hi_check "A bad priority is refused, nothing written" test_add_package_rejects_a_bad_priority
  _hi_check "A bare package with no : is refused" test_add_package_rejects_a_bare_package_with_no_colon
  _hi_check "A # anywhere on the row is refused" test_add_package_rejects_a_hash_anywhere
  _hi_check "A bad --group name is refused, nothing created" test_add_package_rejects_a_bad_group_name
  _hi_check "--dry-run says so and writes nothing" test_add_package_dry_run_writes_nothing

  _hi_h2 "Testing: writing packages.d/custom"
  _hi_check "Creates packages.d/custom by default" test_add_package_creates_the_default_group
  _hi_check "--group names another file instead" test_add_package_group_names_another_file
  _hi_check "Several arguments are several rows" test_add_package_several_arguments_are_several_rows
  _hi_check "A second call appends rather than replacing" test_add_package_second_call_appends
  _hi_check "A row for the same first package replaces it" test_add_package_replaces_same_first_package
  _hi_check "The identical row again is a no-op" test_add_package_identical_row_is_a_no_op
  _hi_check "A color= line and comments survive a write" test_add_package_preserves_comments_and_color_line
  _hi_check "The written row reaches full_check" test_add_package_written_row_reaches_the_check

  _hi_suite_end "scripts/add_package.sh"
}

run_add_package_tests
