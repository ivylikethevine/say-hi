#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Unit tests for scripts/convert_settings.sh, which rewrites overlay files an
# older hi wrote - name:N packages rows, type,name,color colors rows, and
# _HI_PACKAGES_MIN_PRIORITY - into the shapes this hi reads.
#
# The three converters are filters (stdin to stdout) and run in-process
# through the script's source hatch; the entry point runs as a process
# against a scratch overlay directory per case.
#
# GLOSSARY: HI.34.
# shellcheck disable=SC2329,SC2317
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

_HI_CONVERT="$_HI_ROOT/scripts/convert_settings.sh"
# its own hatch stops it before the entry point; sourcing hands over the
# converters
# shellcheck source=../../scripts/convert_settings.sh
source "$_HI_CONVERT"
# full_check and _hi_colors_lookup, for the shipped-file cases
# shellcheck source=../../common/header.sh
source "$_HI_HEADER"
# core.sh, which both source, ends with `set +euo pipefail`
set -euo pipefail

# _hi_conv_is <converter> <input> <want> - <converter> turns <input> into
# exactly <want>, both %b; the mismatch printed when it does not
function _hi_conv_is() {
  local got want
  got="$(printf '%b' "$2" | "$1")"
  want="$(printf '%b' "$3")"
  [ "$got" = "$want" ] && return 0
  _hi_cecho " | got:  [$got]" "$RED"
  _hi_cecho " | want: [$want]" "$RED"
  return 1
}

# _hi_conv_dir <name> - a fresh overlay directory holding one old-shape file
# of each kind, printed
function _hi_conv_dir() {
  local dir="$_HI_WORKDIR/$1"
  mkdir -p "$dir"
  printf '# mine\nbat:3,batcat:3\n-sudo:2\n' >"$dir/packages"
  printf '# mine\nhostname,box,red\nusername,me,blue,3ba55d\n' >"$dir/colors"
  printf '#!/bin/sh\nexport _HI_PACKAGES_MIN_PRIORITY=3\nexport _HI_MAX_WIDTH=100\n' >"$dir/settings.sh"
  printf '%s' "$dir"
}

# _hi_conv_run <args...> - the entry point as a process
function _hi_conv_run() {
  bash "$_HI_CONVERT" "$@" 2>&1
}

# --- packages ----------------------------------------------------------------

# a row's group is the tier its highest N named: 3 core, 2 useful, 1 extras,
# 0 trivia, and the groups come out in that order whatever the file's order
function test_packages_map_each_tier_to_its_group() {
  _hi_conv_is _hi_convert_packages 'd:0\nc:1\nb:2\na:3\n' \
    '\n[core]\na\n\n[useful]\nb\n\n[extras]\nc\n\n[trivia]\nd'
}

# alternatives are sorted highest N first, file order within one N, and an N
# above 3 reads as 3
function test_packages_sort_alternatives_highest_first() {
  _hi_conv_is _hi_convert_packages 'x:1,y:3,z:1,w:3\nq:5,r:3\n' \
    '\n[core]\ny,w,x,z\nq,r'
}

# an old `-` row (heard only when missing) is a `+` row now, in the group of
# its tier - below 2, [base]
function test_packages_dash_rows_become_required() {
  _hi_conv_is _hi_convert_packages '-m:3\n-n:2,o:1\n-p:1\n-s:0,t:1\n' \
    '\n[core]\n+m\n\n[useful]\n+n,o\n\n[base]\n+p\n+t,s'
}

# an old `+` row (heard only when installed) has no counterpart, and lands as
# a plain row in [platform] whatever its N
function test_packages_plus_rows_become_platform() {
  _hi_conv_is _hi_convert_packages '+k:0,l:2\n+kitty:3\n' \
    '\n[platform]\nl,k\nkitty'
}

# comments above the first row stay on top; the rest travel with the row
# below them into its group, and those after the last row close the file.
# Blank lines go, and a row's own spaces with them.
function test_packages_comments_travel_with_their_row() {
  _hi_conv_is _hi_convert_packages '# top\n# more\n\nb:2\n# about a\n a : 3 \n\n# trailing\n' \
    '# top\n# more\n\n[core]\n# about a\na\n\n[useful]\nb\n\n# trailing'
}

# --- colors ------------------------------------------------------------------

# types come out in the order they first appear, rows in file order within
# one - so a pattern keeps its place ahead of an exact row after it - and the
# result reads back through core.sh as the old rows did
function test_colors_group_rows_by_type_in_order() {
  local f="$_HI_WORKDIR/colors.converted"
  printf 'hostname,web-*,red\nusername,me,blue\nhostname,web-1,green,#ff0000\nhosttag,prod,brred,ff5f5f\n' |
    _hi_convert_colors >"$f"
  [ "$(grep '^\[' "$f" | tr '\n' ' ')" = "[hostname] [username] [hosttag] " ] || return 1
  _hi_before "$(cat "$f")" '^web-\*' '^web-1 ' || return 1
  [ "$(_HI_COLORS="$f" _hi_colors_pattern hostname web-2)" = red ] &&
    [ "$(_HI_COLORS="$f" _hi_colors_lookup hostname web-1)" = 'green#ff0000' ] &&
    [ "$(_HI_COLORS="$f" _hi_colors_lookup username me)" = blue ] &&
    [ "$(_HI_COLORS="$f" _hi_colors_lookup hosttag prod)" = 'brred#ff5f5f' ]
}

# the same comment rule as packages: the leading block on top, the rest with
# the row below
function test_colors_comments_travel_with_their_row() {
  local got
  got="$(printf '# top\nhostname,a,red\n# about b\nusername,b,blue\n' | _hi_convert_colors)"
  [ "$(printf '%s\n' "$got" | grep -v '^$' | sed 's/  */ /g')" = "$(printf '# top\n[hostname]\na red\n[username]\n# about b\nb blue')" ]
}

# --- settings.sh -------------------------------------------------------------

# the old floor becomes the groups that show the same tiers; 2 was the
# default and goes, and every other line stays as it was
function test_settings_map_the_floor_to_groups() {
  _hi_conv_is _hi_convert_settings '#!/bin/sh\nexport _HI_PACKAGES_MIN_PRIORITY=0\nexport X=1\n' \
    "#!/bin/sh\nexport _HI_PACKAGES_GROUPS='core useful deprecated extras trivia base platform'\nexport X=1" || return 1
  _hi_conv_is _hi_convert_settings "export _HI_PACKAGES_MIN_PRIORITY='1'\n" \
    "export _HI_PACKAGES_GROUPS='core useful deprecated extras base'" || return 1
  _hi_conv_is _hi_convert_settings 'export X=1\nexport _HI_PACKAGES_MIN_PRIORITY=2\n' 'export X=1' || return 1
  _hi_conv_is _hi_convert_settings '_HI_PACKAGES_MIN_PRIORITY="3"\n' \
    "export _HI_PACKAGES_GROUPS='core deprecated'" || return 1
  _hi_conv_is _hi_convert_settings 'export _HI_PACKAGES_MIN_PRIORITY=4\n' \
    "export _HI_PACKAGES_GROUPS='none'"
}

# a trailing comment rides onto the replacement - the marker install writes
# on its own lines included, so the line stays install's to rewrite
function test_settings_keep_the_trailing_comment() {
  local line
  printf -v line '%-45s %s' 'export _HI_PACKAGES_MIN_PRIORITY=3' "$_HI_MARKER"
  [ "$(printf '%s\n' "$line" | _hi_convert_settings)" = "export _HI_PACKAGES_GROUPS='core deprecated' ${line##*=3 }" ] || return 1
  _hi_conv_is _hi_convert_settings 'export _HI_PACKAGES_MIN_PRIORITY=1 # mine\n' \
    "export _HI_PACKAGES_GROUPS='core useful deprecated extras base' # mine"
}

# a _HI_PACKAGES_GROUPS line already says what to show, before or after the
# old one: the old line just goes
function test_settings_drop_the_floor_beside_groups() {
  _hi_conv_is _hi_convert_settings "export _HI_PACKAGES_MIN_PRIORITY=0\nexport _HI_PACKAGES_GROUPS='core'\n" \
    "export _HI_PACKAGES_GROUPS='core'"
}

# --- the entry point ---------------------------------------------------------

# each file in the old shape is converted in place, the original kept as
# <file>.old
function test_entry_converts_each_old_file() {
  local dir out f
  dir="$(_hi_conv_dir conv-all)"
  cp "$dir/packages" "$dir/packages.orig"
  cp "$dir/colors" "$dir/colors.orig"
  cp "$dir/settings.sh" "$dir/settings.sh.orig"
  out="$(_hi_conv_run "$dir")" || return 1
  for f in packages colors settings.sh; do
    if [[ "$out" != *"converted $dir/$f to the current format"* ]] || ! cmp -s "$dir/$f.old" "$dir/$f.orig"; then
      _hi_cecho " | $f: $out" "$RED"
      return 1
    fi
  done
  grep -qx '\[core\]' "$dir/packages" && grep -qx 'bat,batcat' "$dir/packages" &&
    grep -qx '\[hostname\]' "$dir/colors" &&
    grep -qx "export _HI_PACKAGES_GROUPS='core deprecated'" "$dir/settings.sh" &&
    ! grep -q MIN_PRIORITY "$dir/settings.sh" && grep -qx 'export _HI_MAX_WIDTH=100' "$dir/settings.sh"
}

# --dry-run names each conversion and writes nothing
function test_entry_dry_run_writes_nothing() {
  local dir out f
  dir="$(_hi_conv_dir conv-dry)"
  cp "$dir/packages" "$dir/packages.orig"
  out="$(_hi_conv_run --dry-run "$dir")" || return 1
  for f in packages colors settings.sh; do
    [[ "$out" == *"would convert $dir/$f"* ]] && [ ! -e "$dir/$f.old" ] || return 1
  done
  cmp -s "$dir/packages" "$dir/packages.orig"
}

# a second run finds nothing in the old shape: it says nothing, changes
# nothing, and the .old files stay the originals
function test_entry_is_idempotent() {
  local dir out f
  dir="$(_hi_conv_dir conv-twice)"
  cp "$dir/colors" "$dir/colors.orig"
  _hi_conv_run "$dir" >/dev/null || return 1
  for f in packages colors settings.sh; do cp "$dir/$f" "$dir/$f.first"; done
  out="$(_hi_conv_run "$dir")" || return 1
  [ -z "$out" ] || return 1
  for f in packages colors settings.sh; do
    cmp -s "$dir/$f" "$dir/$f.first" || return 1
  done
  cmp -s "$dir/colors.old" "$dir/colors.orig"
}

# files already in the current shape, or absent, are left alone; a
# sectioned packages file with a stray name:N row is current too
function test_entry_leaves_current_files_alone() {
  local dir="$_HI_WORKDIR/conv-current" out
  mkdir -p "$dir"
  printf '[core]\nbat\nold:3\n' >"$dir/packages"
  printf '[hostname]\nbox red\n' >"$dir/colors"
  out="$(_hi_conv_run "$dir")" || return 1
  [ -z "$out" ] && [ ! -e "$dir/packages.old" ] && [ ! -e "$dir/colors.old" ] &&
    [ ! -e "$dir/settings.sh" ]
}

# with no directory, $_HI_CONFIG_DIR is the one converted
function test_entry_defaults_to_the_overlay() {
  local dir out
  dir="$(_hi_conv_dir conv-default)"
  out="$(_HI_CONFIG_DIR="$dir" _hi_conv_run)" || return 1
  [[ "$out" == *"converted $dir/packages"* ]] && [ -f "$dir/packages.old" ]
}

function test_entry_help_and_unknown_option() {
  local out rc=0
  out="$(_hi_conv_run --help)" || return 1
  [[ "$out" == "Usage: convert_settings.sh [--dry-run] [<dir>]"* ]] || return 1
  out="$(_hi_conv_run --bogus)" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"unknown option --bogus"* ]]
}

# --- the shipped files of an older hi ----------------------------------------

# config/packages and config/colors as the last release in the old shapes
# shipped them, kept verbatim beside this suite so the cases never depend on
# how much history a checkout carries
_HI_CONV_OLD="$_HI_ROOT/tests/scripts/convert_settings"

# the old shipped config/packages converts into a file full_check reads
# without an error and with no name:N row left, every group on
function test_shipped_old_packages_convert_and_parse() {
  local old="$_HI_WORKDIR/shipped.packages.old" new="$_HI_WORKDIR/shipped.packages"
  local err="$_HI_WORKDIR/shipped.packages.err" out
  cp "$_HI_CONV_OLD/packages" "$old"
  grep -q '^[^#]*:[0-9]' "$old" || return 1
  _hi_convert_packages <"$old" >"$new"
  ! grep -q '^[^#]*:[0-9]' "$new" || return 1
  out="$(_HI_PACKAGES="$new" _HI_PACKAGES_GROUPS="core useful extras trivia base platform" full_check 2>"$err")"
  [ ! -s "$err" ] && [ -n "$out" ]
}

# ...and the old shipped config/colors into one core.sh resolves the same
# pins from: every old row's name reads back its old color
function test_shipped_old_colors_convert_and_resolve() {
  local old="$_HI_WORKDIR/shipped.colors.old" new="$_HI_WORKDIR/shipped.colors" type name color hex want got n=0
  cp "$_HI_CONV_OLD/colors" "$old"
  grep -Eq '^[a-z]+,[^,#]+,' "$old" || return 1
  _hi_convert_colors <"$old" >"$new"
  while IFS=, read -r type name color hex; do
    case "$type" in '' | '#'*) continue ;; esac
    case "$name" in *[\*\?]*) continue ;; esac
    want="$color"
    hex="${hex#\#}"
    [ -z "$hex" ] || want="$color#$hex"
    got="$(_HI_COLORS="$new" _hi_colors_lookup "$type" "$name")" || got=""
    [ "$got" = "$want" ] || {
      _hi_cecho " | $type $name: got [$got], want [$want]" "$RED"
      return 1
    }
    n=$((n + 1))
  done <"$old"
  [ "$n" -gt 0 ]
}

function run_convert_settings_tests() {
  _hi_workdir convertsettings
  _hi_suite_begin

  _hi_h2 "Testing: _hi_convert_packages"
  _hi_check "Each tier maps to its group, in group order" test_packages_map_each_tier_to_its_group
  _hi_check "Alternatives sort highest N first, stably" test_packages_sort_alternatives_highest_first
  _hi_check "A - row becomes a + row, low tiers in [base]" test_packages_dash_rows_become_required
  _hi_check "A + row becomes a plain [platform] row" test_packages_plus_rows_become_platform
  _hi_check "Comments travel with the row below" test_packages_comments_travel_with_their_row

  _hi_h2 "Testing: _hi_convert_colors"
  _hi_check "Types in first-appearance order, rows in file order" test_colors_group_rows_by_type_in_order
  _hi_check "Comments travel with the row below" test_colors_comments_travel_with_their_row

  _hi_h2 "Testing: _hi_convert_settings"
  _hi_check "The floor maps to groups; 2 goes" test_settings_map_the_floor_to_groups
  _hi_check "Beside a groups line the floor just goes" test_settings_drop_the_floor_beside_groups
  _hi_check "A trailing comment, install's marker too, is kept" test_settings_keep_the_trailing_comment

  _hi_h2 "Testing: convert_settings.sh"
  _hi_check "Converts each old file, keeping <file>.old" test_entry_converts_each_old_file
  _hi_check "--dry-run writes nothing" test_entry_dry_run_writes_nothing
  _hi_check "A second run is a no-op" test_entry_is_idempotent
  _hi_check "Current or absent files are left alone" test_entry_leaves_current_files_alone
  _hi_check "No directory means the overlay" test_entry_defaults_to_the_overlay
  _hi_check "--help, and an unknown option refused" test_entry_help_and_unknown_option

  _hi_h2 "Testing: an older hi's shipped files"
  _hi_check "config/packages converts and parses" test_shipped_old_packages_convert_and_parse
  _hi_check "config/colors converts and resolves the same" test_shipped_old_colors_convert_and_resolve

  _hi_suite_end "scripts/convert_settings.sh"
}

run_convert_settings_tests
