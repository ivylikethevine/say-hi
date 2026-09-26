#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Unit tests for scripts/set_color.sh - `hi --set-color`, which pins a color
# in a [type] section of ~/.config/say-hi/colors, and `hi --unset-color`,
# which removes a pin.
#
# Driven through `hi.sh --set-color` rather than by calling the script
# directly, so the common/flags rows and _hi_dispatch_subcommand are covered
# with it, as add_package_test.sh drives --add-package. Each case gets its own
# $_HI_CONFIG_DIR, so one case's colors file cannot bleed into another's.
#
# GLOSSARY: HI.34.
# shellcheck disable=SC2329,SC2317
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# _hi_setcolor_fixture <name> - a target-shaped tree with scripts/ added, the
# one thing that makes --set-color reachable at all. Prints its _HI_HOME.
function _hi_setcolor_fixture() {
  _hi_scratch_tree "$1" common config load.sh hi.sh scripts
}

# _hi_setcolor_run <home> <config> <args...> - `hi --set-color` with its own
# overlay directory
function _hi_setcolor_run() {
  local home="$1" cfg="$2"
  shift 2
  _HI_CONFIG_DIR="$cfg" _hi_subcmd_run "$home" --set-color "$@"
}

# _hi_unsetcolor_run <home> <config> <args...> - the same, for --unset-color
function _hi_unsetcolor_run() {
  local home="$1" cfg="$2"
  shift 2
  _HI_CONFIG_DIR="$cfg" _hi_subcmd_run "$home" --unset-color "$@"
}

# _hi_setcolor_overlay <config> <body> - an existing overlay colors file
# holding <body> (%b, so \n is a line break)
function _hi_setcolor_overlay() {
  mkdir -p "$1"
  printf '%b' "$2" >"$1/colors"
}

# _hi_setcolor_is <file> <body> - <file> holds exactly <body> (%b)
function _hi_setcolor_is() {
  local want
  want="$(printf '%b' "$2")"
  [ "$(cat "$1")" = "$want" ] && return 0
  _hi_cecho " | got: [$(cat "$1")]" "$RED"
  return 1
}

# _hi_setcolor_refused <home> <config> <message> <args...> - --set-color with
# <args> fails, says <message>, and writes no file
function _hi_setcolor_refused() {
  local home="$1" cfg="$2" msg="$3" out rc=0
  shift 3
  out="$(_hi_setcolor_run "$home" "$cfg" "$@")" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"$msg"* ]] && [ ! -e "$cfg/colors" ] && return 0
  _hi_cecho " | [$*] gave rc $rc: $out" "$RED"
  return 1
}

# _hi_setcolor_tree_lines <home> - how many lines the fixture tree's own
# colors file has, which every first write copies in
function _hi_setcolor_tree_lines() {
  wc -l <"$1/say-hi/config/colors"
}

# --- arguments ---------------------------------------------------------------

# the set help names the four types and the color vocabulary
function test_set_color_help_is_its_own() {
  local home cfg out
  home="$(_hi_setcolor_fixture setcolor-help)"
  cfg="$_HI_WORKDIR/setcolor-help-cfg"
  out="$(_hi_setcolor_run "$home" "$cfg" --help)" || return 1
  [[ "$out" == "Usage: hi --set-color <type> <name> <color> [rrggbb]"* ]] &&
    [[ "$out" == *"hosttag usertag username hostname"* && "$out" == *lavender* ]] &&
    [[ "$out" == *"-n, --dry-run"* ]] && [ ! -e "$cfg" ]
}

function test_unset_color_help_is_its_own() {
  local home cfg out
  home="$(_hi_setcolor_fixture unsetcolor-help)"
  cfg="$_HI_WORKDIR/unsetcolor-help-cfg"
  out="$(_hi_unsetcolor_run "$home" "$cfg" --help)" || return 1
  [[ "$out" == "Usage: hi --unset-color <type> <name> [--dry-run]"* && "$out" == *"-n, --dry-run"* ]]
}

# three or four words to set, two to unset; anything else is refused
function test_set_color_counts_its_arguments() {
  local home cfg out rc=0
  home="$(_hi_setcolor_fixture setcolor-count)"
  cfg="$_HI_WORKDIR/setcolor-count-cfg"
  _hi_setcolor_refused "$home" "$cfg" "needs a type, a name, and a color" hostname box || return 1
  _hi_setcolor_refused "$home" "$cfg" "needs a type, a name, and a color" hostname box red 3ba55d extra || return 1
  out="$(_hi_unsetcolor_run "$home" "$cfg" hostname box red)" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"needs a type and a name"* ]] && [ ! -e "$cfg/colors" ]
}

function test_set_color_refuses_an_unknown_option() {
  local home cfg
  home="$(_hi_setcolor_fixture setcolor-opt)"
  cfg="$_HI_WORKDIR/setcolor-opt-cfg"
  _hi_setcolor_refused "$home" "$cfg" "unknown option --bogus" hostname box red --bogus
}

function test_set_color_refuses_an_unknown_type() {
  local home cfg
  home="$(_hi_setcolor_fixture setcolor-type)"
  cfg="$_HI_WORKDIR/setcolor-type-cfg"
  _hi_setcolor_refused "$home" "$cfg" "not a type: host (one of hosttag usertag username hostname)" host box red
}

# a name is one field of a row: no spaces, and nothing that reads as a
# comment or a section
function test_set_color_refuses_a_bad_name() {
  local home cfg bad
  home="$(_hi_setcolor_fixture setcolor-name)"
  cfg="$_HI_WORKDIR/setcolor-name-cfg"
  for bad in 'a b' '#box' 'box#1' '[box]'; do
    _hi_setcolor_refused "$home" "$cfg" "not a name: $bad" hostname "$bad" red || return 1
  done
}

function test_set_color_refuses_an_unknown_color() {
  local home cfg
  home="$(_hi_setcolor_fixture setcolor-color)"
  cfg="$_HI_WORKDIR/setcolor-color-cfg"
  _hi_setcolor_refused "$home" "$cfg" "not a color: purple" hostname box purple
}

function test_set_color_refuses_a_bad_hex() {
  local home cfg bad
  home="$(_hi_setcolor_fixture setcolor-hex)"
  cfg="$_HI_WORKDIR/setcolor-hex-cfg"
  for bad in 12345 1234567 zzzzzz '##3ba55d'; do
    _hi_setcolor_refused "$home" "$cfg" "not six hex digits: $bad" hostname box red "$bad" || return 1
  done
}

# with no overlay file yet, --dry-run names the copy the real run would make
# - and makes no directory at all
function test_set_color_dry_run_writes_nothing() {
  local home cfg out
  home="$(_hi_setcolor_fixture setcolor-dry)"
  cfg="$_HI_WORKDIR/setcolor-dry-cfg"
  out="$(_hi_setcolor_run "$home" "$cfg" hostname box red --dry-run)" || return 1
  [[ "$out" == *"dry run"* && "$out" == *"copy $home/say-hi/config/colors to $cfg/colors, then change it there"* ]] &&
    [ ! -d "$cfg" ]
}

# ...and with one, it names a plain write, leaving the file as it was
function test_set_color_dry_run_over_an_overlay() {
  local home cfg out
  home="$(_hi_setcolor_fixture setcolor-dry-overlay)"
  cfg="$_HI_WORKDIR/setcolor-dry-overlay-cfg"
  _hi_setcolor_overlay "$cfg" '[hostname]\na red\n'
  out="$(_hi_setcolor_run "$home" "$cfg" hostname box red --dry-run)" || return 1
  [[ "$out" == *"write $cfg/colors"* && "$out" != *"copy "* ]] &&
    _hi_setcolor_is "$cfg/colors" '[hostname]\na red'
}

# --- where a pin lands -------------------------------------------------------

# into its type's section, after the last row there
function test_set_color_joins_its_section() {
  local home cfg out
  home="$(_hi_setcolor_fixture setcolor-join)"
  cfg="$_HI_WORKDIR/setcolor-join-cfg"
  _hi_setcolor_overlay "$cfg" '[hostname]\na red\n\n[username]\nb blue\n'
  out="$(_hi_setcolor_run "$home" "$cfg" hostname box cyan)" || return 1
  [[ "$out" == *"+ box cyan in [hostname]"* && "$out" == *"$cfg/colors updated"* ]] &&
    _hi_setcolor_is "$cfg/colors" '[hostname]\na red\nbox cyan\n\n[username]\nb blue'
}

# a type the file has no section for gets one at the end, after a blank line,
# and the hex is written without its #
function test_set_color_creates_a_section() {
  local home cfg
  home="$(_hi_setcolor_fixture setcolor-section)"
  cfg="$_HI_WORKDIR/setcolor-section-cfg"
  _hi_setcolor_overlay "$cfg" '[hostname]\na red\n'
  _hi_setcolor_run "$home" "$cfg" usertag ops brred '#3BA55D' >/dev/null || return 1
  _hi_setcolor_is "$cfg/colors" '[hostname]\na red\n\n[usertag]\nops brred 3BA55D'
}

# a name already pinned under the type is replaced in place
function test_set_color_replaces_a_pin() {
  local home cfg out
  home="$(_hi_setcolor_fixture setcolor-replace)"
  cfg="$_HI_WORKDIR/setcolor-replace-cfg"
  _hi_setcolor_overlay "$cfg" '[hostname]\nbox red 3ba55d\nz blue\n'
  out="$(_hi_setcolor_run "$home" "$cfg" hostname box green)" || return 1
  [[ "$out" == *"~ box green (replacing box red 3ba55d in [hostname])"* ]] &&
    _hi_setcolor_is "$cfg/colors" '[hostname]\nbox green\nz blue'
}

# the same name under another type is a different pin, left alone
function test_set_color_keeps_to_its_type() {
  local home cfg
  home="$(_hi_setcolor_fixture setcolor-scope)"
  cfg="$_HI_WORKDIR/setcolor-scope-cfg"
  _hi_setcolor_overlay "$cfg" '[username]\nbox red\n'
  _hi_setcolor_run "$home" "$cfg" hostname box blue >/dev/null || return 1
  _hi_setcolor_is "$cfg/colors" '[username]\nbox red\n\n[hostname]\nbox blue'
}

# the identical pin changes nothing and writes nothing
function test_set_color_identical_pin_is_a_no_op() {
  local home cfg out
  home="$(_hi_setcolor_fixture setcolor-noop)"
  cfg="$_HI_WORKDIR/setcolor-noop-cfg"
  _hi_setcolor_overlay "$cfg" '# mine\n[hostname]\nbox red\n'
  out="$(_hi_setcolor_run "$home" "$cfg" hostname box red)" || return 1
  [[ "$out" == *"$cfg/colors: box red is already in [hostname] - nothing to write"* ]] &&
    _hi_setcolor_is "$cfg/colors" '# mine\n[hostname]\nbox red'
}

# a pin in the shipped file's padded spelling is the same pin: re-pinning the
# same color and hex compares field by field, and writes nothing
function test_set_color_same_pin_padded_is_a_no_op() {
  local home cfg out
  home="$(_hi_setcolor_fixture setcolor-padded)"
  cfg="$_HI_WORKDIR/setcolor-padded-cfg"
  _hi_setcolor_overlay "$cfg" '[hostname]\nbox             red   #3ba55d  a note\nz    blue\n'
  out="$(_hi_setcolor_run "$home" "$cfg" hostname box red 3ba55d)" || return 1
  [[ "$out" == *"is already in [hostname] - nothing to write"* ]] || return 1
  out="$(_hi_setcolor_run "$home" "$cfg" hostname z blue)" || return 1
  [[ "$out" == *"is already in [hostname] - nothing to write"* ]] &&
    _hi_setcolor_is "$cfg/colors" '[hostname]\nbox             red   #3ba55d  a note\nz    blue'
}

# ...and through the cascade: re-pinning a shipped pin as it stands makes no
# overlay at all
function test_set_color_shipped_pin_is_a_no_op() {
  local home cfg out
  home="$(_hi_setcolor_fixture setcolor-shipped)"
  cfg="$_HI_WORKDIR/setcolor-shipped-cfg"
  grep -Eq '^root +red$' "$home/say-hi/config/colors" || return 1
  out="$(_hi_setcolor_run "$home" "$cfg" username root red)" || return 1
  [[ "$out" == *"is already in [username] - nothing to write"* ]] && [ ! -d "$cfg" ]
}

# a different hex on the same color is a change, not a no-op
function test_set_color_new_hex_is_a_change() {
  local home cfg
  home="$(_hi_setcolor_fixture setcolor-rehex)"
  cfg="$_HI_WORKDIR/setcolor-rehex-cfg"
  _hi_setcolor_overlay "$cfg" '[hostname]\nbox   red 3ba55d\n'
  _hi_setcolor_run "$home" "$cfg" hostname box red >/dev/null || return 1
  _hi_setcolor_is "$cfg/colors" '[hostname]\nbox red'
}

# the written pin is what the resolver reads back - $_HI_HEADER is this dev
# tree's, and its paths.sh finds the fixture's freshly-written colors file in
# $_HI_CONFIG_DIR
function test_set_color_pin_reaches_the_lookup() {
  local home cfg out
  home="$(_hi_setcolor_fixture setcolor-integration)"
  cfg="$_HI_WORKDIR/setcolor-integration-cfg"
  _hi_setcolor_run "$home" "$cfg" username hi-test-user orange fd971f >/dev/null || return 1
  out="$(_HI_CONFIG_DIR="$cfg" bash -c 'source "$_HI_HEADER"; _hi_colors_lookup username hi-test-user')"
  [ "$out" = 'orange#fd971f' ]
}

# --- --unset-color ------------------------------------------------------------

# the pin goes, the section header stays
function test_unset_color_removes_a_pin() {
  local home cfg out
  home="$(_hi_setcolor_fixture unsetcolor-rm)"
  cfg="$_HI_WORKDIR/unsetcolor-rm-cfg"
  _hi_setcolor_overlay "$cfg" '[hostname]\nbox red\nz blue\n'
  out="$(_hi_unsetcolor_run "$home" "$cfg" hostname box)" || return 1
  [[ "$out" == *"- box red (from [hostname])"* ]] &&
    _hi_setcolor_is "$cfg/colors" '[hostname]\nz blue'
}

# a name pinned only under another type, or not at all, is a no-op
function test_unset_color_without_a_pin_is_a_no_op() {
  local home cfg out
  home="$(_hi_setcolor_fixture unsetcolor-miss)"
  cfg="$_HI_WORKDIR/unsetcolor-miss-cfg"
  _hi_setcolor_overlay "$cfg" '[username]\nbox red\n'
  out="$(_hi_unsetcolor_run "$home" "$cfg" hostname box)" || return 1
  [[ "$out" == *"$cfg/colors has no [hostname] pin for box - nothing to write"* ]] &&
    _hi_setcolor_is "$cfg/colors" '[username]\nbox red'
}

# --- the overlay file replaces the tree's wholesale, so the first write
# copies the tree's pins in -------------------------------------------------

function test_set_color_first_call_copies_the_tree_in() {
  local home cfg n
  home="$(_hi_setcolor_fixture setcolor-seed)"
  cfg="$_HI_WORKDIR/setcolor-seed-cfg"
  _hi_setcolor_run "$home" "$cfg" hostname box cyan >/dev/null || return 1
  n="$(_hi_setcolor_tree_lines "$home")"
  # the tree's lines plus the one pin, which taken out again leaves the tree
  [ "$(wc -l <"$cfg/colors")" -eq "$((n + 1))" ] &&
    grep -vxF 'box cyan' "$cfg/colors" | cmp -s - "$home/say-hi/config/colors"
}

# a second call does not re-copy or clobber what the first one wrote
function test_set_color_second_call_does_not_recopy() {
  local home cfg
  home="$(_hi_setcolor_fixture setcolor-noreseed)"
  cfg="$_HI_WORKDIR/setcolor-noreseed-cfg"
  _hi_setcolor_run "$home" "$cfg" hostname a red >/dev/null || return 1
  printf '[hostname]\ntruncated red\n' >"$cfg/colors"
  _hi_setcolor_run "$home" "$cfg" hostname b blue >/dev/null || return 1
  _hi_setcolor_is "$cfg/colors" '[hostname]\ntruncated red\nb blue'
}

# unsetting a shipped pin reads through the cascade and copies the tree in
# without it
function test_unset_color_copies_the_tree_in_without_the_pin() {
  local home cfg n
  home="$(_hi_setcolor_fixture unsetcolor-seed)"
  cfg="$_HI_WORKDIR/unsetcolor-seed-cfg"
  grep -q '^root ' "$home/say-hi/config/colors" || return 1
  _hi_unsetcolor_run "$home" "$cfg" username root >/dev/null || return 1
  n="$(_hi_setcolor_tree_lines "$home")"
  [ "$(wc -l <"$cfg/colors")" -eq "$((n - 1))" ] && ! grep -q '^root ' "$cfg/colors"
}

# --dry-run reads through the cascade too: an unset of a name the tree does
# not pin reports against the tree's file, and makes no overlay
function test_unset_color_dry_run_reads_through_the_cascade() {
  local home cfg out
  home="$(_hi_setcolor_fixture unsetcolor-dry)"
  cfg="$_HI_WORKDIR/unsetcolor-dry-cfg"
  out="$(_hi_unsetcolor_run "$home" "$cfg" hostname hi-no-such-host --dry-run)" || return 1
  [[ "$out" == *"config/colors has no [hostname] pin for hi-no-such-host - nothing to write"* ]] &&
    [ ! -d "$cfg" ]
}

function run_set_color_tests() {
  _hi_workdir setcolor
  _hi_suite_begin

  _hi_h2 "Testing: scripts/set_color.sh arguments"
  _hi_check "--set-color --help is its own text" test_set_color_help_is_its_own
  _hi_check "--unset-color --help is its own text" test_unset_color_help_is_its_own
  _hi_check "The wrong number of words is refused" test_set_color_counts_its_arguments
  _hi_check "An unknown option is refused" test_set_color_refuses_an_unknown_option
  _hi_check "An unknown type is refused" test_set_color_refuses_an_unknown_type
  _hi_check "A name with a space, # or bracket is refused" test_set_color_refuses_a_bad_name
  _hi_check "An unknown color is refused" test_set_color_refuses_an_unknown_color
  _hi_check "A hex that is not six digits is refused" test_set_color_refuses_a_bad_hex
  _hi_check "--dry-run names the copy and writes nothing" test_set_color_dry_run_writes_nothing
  _hi_check "--dry-run over an overlay names a plain write" test_set_color_dry_run_over_an_overlay

  _hi_h2 "Testing: where a pin lands in ~/.config/say-hi/colors"
  _hi_check "Joins its type's section" test_set_color_joins_its_section
  _hi_check "Creates a missing section, hex without its #" test_set_color_creates_a_section
  _hi_check "Replaces the name's pin in place" test_set_color_replaces_a_pin
  _hi_check "Leaves the same name under another type be" test_set_color_keeps_to_its_type
  _hi_check "The identical pin is a no-op" test_set_color_identical_pin_is_a_no_op
  _hi_check "...field by field, padding and notes aside" test_set_color_same_pin_padded_is_a_no_op
  _hi_check "...a shipped pin too, with no overlay made" test_set_color_shipped_pin_is_a_no_op
  _hi_check "Dropping the hex is a change" test_set_color_new_hex_is_a_change
  _hi_check "The pin reaches _hi_colors_lookup" test_set_color_pin_reaches_the_lookup

  _hi_h2 "Testing: --unset-color"
  _hi_check "Removes the pin, keeps the section" test_unset_color_removes_a_pin
  _hi_check "No pin under the type writes nothing" test_unset_color_without_a_pin_is_a_no_op

  _hi_h2 "Testing: wholesale replace, and the first write's copy"
  _hi_check "First call copies the tree's pins in" test_set_color_first_call_copies_the_tree_in
  _hi_check "A second call does not re-copy or clobber" test_set_color_second_call_does_not_recopy
  _hi_check "Unset copies the tree in, minus the pin" test_unset_color_copies_the_tree_in_without_the_pin
  _hi_check "--dry-run unset reads through the cascade" test_unset_color_dry_run_reads_through_the_cascade

  _hi_suite_end "scripts/set_color.sh"
}

run_set_color_tests
