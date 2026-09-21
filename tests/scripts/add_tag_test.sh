#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Unit tests for scripts/add_tag.sh - `hi --add-tag`, which writes the
# `# Tags:` comment above a host's Host line in ~/.ssh/config.
#
# Driven through `hi.sh --add-tag`, as add_package_test.sh drives its
# command, so the common/flags row and the dispatch are covered with it. Each
# case gets its own $HOME, and so its own ~/.ssh/config.
#
# GLOSSARY: HI.34.
# shellcheck disable=SC2329,SC2317
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# _hi_addtag_fixture <name> - a tree with scripts/, and a home whose ssh
# config tags web1, leaves web2 bare, covers *.prod by a wildcard only, and
# Includes one more file. Prints the home, which is also the fixture's
# _HI_HOME.
function _hi_addtag_fixture() {
  local home
  home="$(_hi_scratch_tree "$1" common config load.sh hi.sh scripts)"
  mkdir -p "$home/.ssh/config.d"
  printf '%s\n' 'Include config.d/*' '# Tags: old' 'Host web1' '  HostName 10.0.0.1' '' \
    'Host web2' '  HostName 10.0.0.2' '' 'Host *.prod' '  User deploy' >"$home/.ssh/config"
  printf 'Host inc1\n' >"$home/.ssh/config.d/01-inc"
  chmod 600 "$home/.ssh/config"
  printf '%s' "$home"
}

# _hi_addtag_run <home> <args...>
function _hi_addtag_run() {
  local home="$1"
  shift
  HOME="$home" _HI_CONFIG_DIR="$home/overlay" _hi_subcmd_run "$home" --add-tag "$@"
}

# a host with no tag gets one directly above its Host line
function test_add_tag_writes_above_the_host() {
  local home
  home="$(_hi_addtag_fixture addtag-new)"
  _hi_addtag_run "$home" web2 lab >/dev/null || return 1
  grep -A1 -x '# Tags: lab' "$home/.ssh/config" | grep -qx 'Host web2'
}

# a tag already there is replaced, not stacked - the walk reads only one
function test_add_tag_replaces_an_existing_tag() {
  local home
  home="$(_hi_addtag_fixture addtag-replace)"
  _hi_addtag_run "$home" web1 prod >/dev/null || return 1
  [ "$(grep -c '^# Tags:' "$home/.ssh/config")" -eq 1 ] &&
    grep -A1 -x '# Tags: prod' "$home/.ssh/config" | grep -qx 'Host web1'
}

# a host that lives in an Included file is tagged there
function test_add_tag_writes_the_included_file() {
  local home
  home="$(_hi_addtag_fixture addtag-include)"
  _hi_addtag_run "$home" inc1 lab >/dev/null || return 1
  [ "$(cat "$home/.ssh/config.d/01-inc")" = '# Tags: lab
Host inc1' ] && ! grep -q lab "$home/.ssh/config"
}

# a name only a wildcard covers is refused, naming the block to tag instead
function test_add_tag_refuses_a_wildcard_only_host() {
  local home out
  home="$(_hi_addtag_fixture addtag-wild)"
  out="$(_hi_addtag_run "$home" db.prod prod)" && return 1
  [[ "$out" == *"only 'Host *.prod' covers it"* ]] && ! grep -q '^# Tags: prod' "$home/.ssh/config"
}

# ...and the pattern itself can be tagged
function test_add_tag_tags_a_pattern() {
  local home
  home="$(_hi_addtag_fixture addtag-pattern)"
  _hi_addtag_run "$home" '*.prod' prod >/dev/null || return 1
  grep -A1 -x '# Tags: prod' "$home/.ssh/config" | grep -qx 'Host \*.prod'
}

function test_add_tag_refuses_an_unknown_host_and_a_bad_tag() {
  local home before
  home="$(_hi_addtag_fixture addtag-refuse)"
  before="$(cat "$home/.ssh/config")"
  ! _hi_addtag_run "$home" nothere lab >/dev/null || return 1
  ! _hi_addtag_run "$home" web2 'two words' >/dev/null || return 1
  ! _hi_addtag_run "$home" web2 >/dev/null || return 1
  [ "$(cat "$home/.ssh/config")" = "$before" ]
}

function test_add_tag_dry_run_writes_nothing() {
  local home before out
  home="$(_hi_addtag_fixture addtag-dry)"
  before="$(cat "$home/.ssh/config")"
  out="$(_hi_addtag_run "$home" web2 lab --dry-run)" || return 1
  [[ "$out" == *"dry run: would write"* ]] && [ "$(cat "$home/.ssh/config")" = "$before" ]
}

# the file keeps its mode through the rewrite (ssh refuses a loose config)
function test_add_tag_keeps_the_config_mode() {
  local home mode
  home="$(_hi_addtag_fixture addtag-mode)"
  _hi_addtag_run "$home" web2 lab >/dev/null || return 1
  mode="$(stat -c '%a' "$home/.ssh/config" 2>/dev/null || stat -f '%Lp' "$home/.ssh/config")"
  [ "$mode" = 600 ]
}

# The round trip the command exists for: tagged, then drawn by
# `hi --preview colors` in the hosttag row's color, under that tag
function test_add_tag_round_trips_through_preview_colors() {
  local home out
  home="$(_hi_addtag_fixture addtag-preview)"
  mkdir -p "$home/overlay"
  printf 'hosttag,lab,brred\n' >"$home/overlay/colors"
  _hi_addtag_run "$home" web2 lab >/dev/null || return 1
  out="$(HOME="$home" _HI_HOME="$home" _HI_CONFIG_DIR="$home/overlay" _HI_TARGETS_TTL=0 \
    "$home/say-hi/scripts/preview.sh" colors 2>&1)" || return 1
  out="$(_hi_strip_ansi "$out")"
  printf '%s\n' "$out" | grep 'web2' | grep -q 'tag:lab'
}

function run_add_tag_tests() {
  _hi_workdir addtag
  _hi_suite_begin

  _hi_h1 "Testing scripts/add_tag.sh"
  _hi_check "Writes a tag above the Host line" test_add_tag_writes_above_the_host
  _hi_check "Replaces an existing tag" test_add_tag_replaces_an_existing_tag
  _hi_check "Tags a host in the file it is Included from" test_add_tag_writes_the_included_file
  _hi_check "Refuses a wildcard-only host, naming the block" test_add_tag_refuses_a_wildcard_only_host
  _hi_check "Tags a pattern" test_add_tag_tags_a_pattern
  _hi_check "Refuses an unknown host and a bad tag" test_add_tag_refuses_an_unknown_host_and_a_bad_tag
  _hi_check "--dry-run writes nothing" test_add_tag_dry_run_writes_nothing
  _hi_check "Keeps the config's mode" test_add_tag_keeps_the_config_mode
  _hi_check "Round-trips through hi --preview colors" test_add_tag_round_trips_through_preview_colors

  _hi_suite_end "scripts/add_tag.sh"
}

run_add_tag_tests
