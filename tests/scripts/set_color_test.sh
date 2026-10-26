#!/usr/bin/env bash
# Unit tests for scripts/set_color.sh - `hi --add-color`, which pins a color
# in a [type] section of ~/.config/say-hi/colors, and `hi --remove-color`,
# which removes a pin.
#
# Driven through `hi.sh --add-color` rather than by calling the script
# directly, so the common/flags rows and _hi_dispatch_subcommand are covered
# with it, as add_package_test.sh drives --add-package. Each case gets its own
# $_HI_CONFIG_DIR, so one case's colors file cannot bleed into another's.
#
# GLOSSARY: HI.34.
# shellcheck disable=SC2329,SC2317
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# _hi_color_run <add|remove> <config> <args...> - `hi --<add|remove>-color`
# on the suite's tree, with its own overlay directory
function _hi_color_run() {
  _HI_CONFIG_DIR="$2" _hi_subcmd_run "$_HI_SETCOLOR_HOME" "--$1-color" "${@:3}"
}

# _hi_setcolor_overlay <config> <body> - an existing overlay colors file
# holding <body> (%b, so \n is a line break)
function _hi_setcolor_overlay() {
  mkdir -p "$1"
  printf '%b' "$2" >"$1/colors"
}

# _hi_setcolor_refused <config> <message> <args...> - --add-color with <args>
# fails, says <message>, and writes no file
function _hi_setcolor_refused() {
  local cfg="$1" msg="$2" out rc=0
  shift 2
  out="$(_hi_color_run add "$cfg" "$@")" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"$msg"* ]] && [ ! -e "$cfg/colors" ] || _hi_because "[$*] gave rc $rc: $out"
}

# --- arguments ---------------------------------------------------------------

# the set help names the four types and the color vocabulary
function test_set_color_help_is_its_own() {
  local home="$_HI_SETCOLOR_HOME" cfg="$_HI_WORKDIR/cfg" out
  out="$(_hi_color_run add "$cfg" --help)" || _hi_why home cfg || return 1
  [[ "$out" == "Usage: hi --add-color <type> <name> <color> [rrggbb]"* ]] &&
    [[ "$out" == *"hosttag usertag username hostname"* && "$out" == *lavender* ]] &&
    [[ "$out" == *"-n, --dry-run"* ]] && [ ! -e "$cfg" ] || _hi_why out cfg
}

function test_unset_color_help_is_its_own() {
  local home="$_HI_SETCOLOR_HOME" cfg="$_HI_WORKDIR/cfg" out
  out="$(_hi_color_run remove "$cfg" --help)" || _hi_why home cfg || return 1
  [[ "$out" == "Usage: hi --remove-color <type> <name> [--dry-run]"* && "$out" == *"-n, --dry-run"* ]] || _hi_why out
}

# three or four words to set, two to unset; anything else is refused
function test_set_color_counts_its_arguments() {
  local home="$_HI_SETCOLOR_HOME" cfg="$_HI_WORKDIR/cfg" out rc=0
  _hi_setcolor_refused "$cfg" "needs a type, a name, and a color" hostname box || _hi_why home cfg || return 1
  _hi_setcolor_refused "$cfg" "needs a type, a name, and a color" hostname box red 3ba55d extra || _hi_why home cfg || return 1
  out="$(_hi_color_run remove "$cfg" hostname box red)" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"needs a type and a name"* ]] && [ ! -e "$cfg/colors" ] || _hi_why rc out cfg
}

function test_set_color_refuses_an_unknown_option() {
  local home="$_HI_SETCOLOR_HOME" cfg="$_HI_WORKDIR/cfg"
  _hi_setcolor_refused "$cfg" "unknown option --bogus" hostname box red --bogus || _hi_why home cfg
}

function test_set_color_refuses_an_unknown_type() {
  local home="$_HI_SETCOLOR_HOME" cfg="$_HI_WORKDIR/cfg"
  _hi_setcolor_refused "$cfg" "not a type: host (one of hosttag usertag username hostname)" host box red || _hi_why home cfg
}

# a name is one key of a row: no spaces, and nothing that reads as a
# comment or a table, or that a quoted key would have to escape
function test_set_color_refuses_a_bad_name() {
  local home="$_HI_SETCOLOR_HOME" cfg="$_HI_WORKDIR/cfg" bad
  for bad in 'a b' '#box' 'box#1' '[box]' 'bo"x'; do
    _hi_setcolor_refused "$cfg" "not a name: $bad" hostname "$bad" red || _hi_why home cfg bad || return 1
  done
}

function test_set_color_refuses_an_unknown_color() {
  local home="$_HI_SETCOLOR_HOME" cfg="$_HI_WORKDIR/cfg"
  _hi_setcolor_refused "$cfg" "not a color: purple" hostname box purple || _hi_why home cfg
}

function test_set_color_refuses_a_bad_hex() {
  local home="$_HI_SETCOLOR_HOME" cfg="$_HI_WORKDIR/cfg" bad
  for bad in 12345 1234567 zzzzzz '##3ba55d'; do
    _hi_setcolor_refused "$cfg" "not six hex digits: $bad" hostname box red "$bad" || _hi_why home cfg bad || return 1
  done
}

# with no overlay file yet, --dry-run names the copy the real run would make
# - and makes no directory at all
function test_set_color_dry_run_writes_nothing() {
  local home="$_HI_SETCOLOR_HOME" cfg="$_HI_WORKDIR/cfg" out
  out="$(_hi_color_run add "$cfg" hostname box red --dry-run)" || _hi_why home cfg || return 1
  [[ "$out" == *"dry run"* && "$out" == *"copy $home/say-hi/config/colors to $cfg/colors, then change it there"* ]] &&
    [ ! -d "$cfg" ] || _hi_why out home cfg
}

# ...and with one, it names a plain write, leaving the file as it was
function test_set_color_dry_run_over_an_overlay() {
  local home="$_HI_SETCOLOR_HOME" cfg="$_HI_WORKDIR/cfg" out
  _hi_setcolor_overlay "$cfg" '[hostname]\na = "red"\n'
  out="$(_hi_color_run add "$cfg" hostname box red --dry-run)" || _hi_why home cfg || return 1
  { [[ "$out" == *"write $cfg/colors"* && "$out" != *"copy "* ]] &&
    _hi_file_is "$cfg/colors" '[hostname]\na = "red"'; } || _hi_why out cfg
}

# --- where a pin lands -------------------------------------------------------

# into its type's section, after the last row there
function test_set_color_joins_its_section() {
  local home="$_HI_SETCOLOR_HOME" cfg="$_HI_WORKDIR/cfg" out
  _hi_setcolor_overlay "$cfg" '[hostname]\na = "red"\n\n[username]\nb = "blue"\n'
  out="$(_hi_color_run add "$cfg" hostname box cyan)" || _hi_why home cfg || return 1
  { [[ "$out" == *"+ box cyan in [hostname]"* && "$out" == *"$cfg/colors updated"* ]] &&
    _hi_file_is "$cfg/colors" '[hostname]\na = "red"\nbox = "cyan"\n\n[username]\nb = "blue"'; } || _hi_why out cfg
}

# a type the file has no section for gets one at the end, after a blank line,
# and the hex is written without its #
function test_set_color_creates_a_section() {
  local home="$_HI_SETCOLOR_HOME" cfg="$_HI_WORKDIR/cfg"
  _hi_setcolor_overlay "$cfg" '[hostname]\na = "red"\n'
  _hi_color_run add "$cfg" usertag ops brred '#3BA55D' >/dev/null || _hi_why home cfg || return 1
  _hi_file_is "$cfg/colors" '[hostname]\na = "red"\n\n[usertag]\nops = "brred 3BA55D"' || _hi_why cfg || return 1
  # a name TOML would not read bare is written in quotes, and found there
  _hi_color_run add "$cfg" hostname '10.0.*' red >/dev/null || _hi_why home cfg || return 1
  _hi_color_run add "$cfg" hostname '10.0.*' blue >/dev/null || _hi_why home cfg || return 1
  _hi_file_is "$cfg/colors" '[hostname]\na = "red"\n"10.0.*" = "blue"\n\n[usertag]\nops = "brred 3BA55D"' || _hi_why cfg
}

# a name already pinned under the type is replaced in place
function test_set_color_replaces_a_pin() {
  local home="$_HI_SETCOLOR_HOME" cfg="$_HI_WORKDIR/cfg" out
  _hi_setcolor_overlay "$cfg" '[hostname]\nbox = "red 3ba55d"\nz = "blue"\n'
  out="$(_hi_color_run add "$cfg" hostname box green)" || _hi_why home cfg || return 1
  { [[ "$out" == *"~ box green (replacing box red 3ba55d in [hostname])"* ]] &&
    _hi_file_is "$cfg/colors" '[hostname]\nbox = "green"\nz = "blue"'; } || _hi_why out cfg
}

# the same name under another type is a different pin, left alone
function test_set_color_keeps_to_its_type() {
  local home="$_HI_SETCOLOR_HOME" cfg="$_HI_WORKDIR/cfg"
  _hi_setcolor_overlay "$cfg" '[username]\nbox = "red"\n'
  _hi_color_run add "$cfg" hostname box blue >/dev/null || _hi_why home cfg || return 1
  _hi_file_is "$cfg/colors" '[username]\nbox = "red"\n\n[hostname]\nbox = "blue"' || _hi_why cfg
}

# the identical pin changes nothing and writes nothing
function test_set_color_identical_pin_is_a_no_op() {
  local home="$_HI_SETCOLOR_HOME" cfg="$_HI_WORKDIR/cfg" out
  _hi_setcolor_overlay "$cfg" '# mine\n[hostname]\nbox = "red"\n'
  out="$(_hi_color_run add "$cfg" hostname box red)" || _hi_why home cfg || return 1
  { [[ "$out" == *"$cfg/colors: box red is already in [hostname] - nothing to write"* ]] &&
    _hi_file_is "$cfg/colors" '# mine\n[hostname]\nbox = "red"'; } || _hi_why out cfg
}

# a pin in the shipped file's padded spelling is the same pin: re-pinning the
# same color and hex compares field by field, and writes nothing
function test_set_color_same_pin_padded_is_a_no_op() {
  local home="$_HI_SETCOLOR_HOME" cfg="$_HI_WORKDIR/cfg" out
  _hi_setcolor_overlay "$cfg" '[hostname]\nbox             =   "red   #3ba55d"  # a note\n  z = "blue"\n'
  out="$(_hi_color_run add "$cfg" hostname box red 3ba55d)" || _hi_why home cfg || return 1
  [[ "$out" == *"is already in [hostname] - nothing to write"* ]] || _hi_why out || return 1
  out="$(_hi_color_run add "$cfg" hostname z blue)" || _hi_why home cfg || return 1
  { [[ "$out" == *"is already in [hostname] - nothing to write"* ]] &&
    _hi_file_is "$cfg/colors" '[hostname]\nbox             =   "red   #3ba55d"  # a note\n  z = "blue"'; } || _hi_why out cfg
}

# ...and through the cascade: re-pinning a shipped pin as it stands makes no
# overlay at all
function test_set_color_shipped_pin_is_a_no_op() {
  local home="$_HI_SETCOLOR_HOME" cfg="$_HI_WORKDIR/cfg" out
  grep -Eq '^root += "red b00020"$' "$home/say-hi/config/colors" || _hi_why home || return 1
  out="$(_hi_color_run add "$cfg" username root red b00020)" || _hi_why home cfg || return 1
  [[ "$out" == *"is already in [username] - nothing to write"* ]] && [ ! -d "$cfg" ] || _hi_why out cfg
}

# a different hex on the same color is a change, not a no-op
function test_set_color_new_hex_is_a_change() {
  local home="$_HI_SETCOLOR_HOME" cfg="$_HI_WORKDIR/cfg"
  _hi_setcolor_overlay "$cfg" '[hostname]\nbox = "red 3ba55d"\n'
  _hi_color_run add "$cfg" hostname box red >/dev/null || _hi_why home cfg || return 1
  _hi_file_is "$cfg/colors" '[hostname]\nbox = "red"' || _hi_why cfg
}

# the written pin is what the resolver reads back - $_HI_HEADER is this dev
# tree's, and its paths.sh finds the fixture's freshly-written colors file in
# $_HI_CONFIG_DIR
function test_set_color_pin_reaches_the_lookup() {
  local home="$_HI_SETCOLOR_HOME" cfg="$_HI_WORKDIR/cfg" out
  _hi_color_run add "$cfg" username hi-test-user orange fd971f >/dev/null || _hi_why home cfg || return 1
  out="$(_HI_CONFIG_DIR="$cfg" bash -c 'source "$_HI_HEADER"; _hi_colors_lookup username hi-test-user')"
  [ "$out" = 'orange#fd971f' ] || _hi_why out
}

# --- --remove-color ------------------------------------------------------------

# the pin goes, the section header stays
function test_unset_color_removes_a_pin() {
  local home="$_HI_SETCOLOR_HOME" cfg="$_HI_WORKDIR/cfg" out
  _hi_setcolor_overlay "$cfg" '[hostname]\nbox = "red"\nz = "blue"\n'
  out="$(_hi_color_run remove "$cfg" hostname box)" || _hi_why home cfg || return 1
  { [[ "$out" == *"- box red (from [hostname])"* ]] &&
    _hi_file_is "$cfg/colors" '[hostname]\nz = "blue"'; } || _hi_why out cfg
}

# a name pinned only under another type, or not at all, is a no-op
function test_unset_color_without_a_pin_is_a_no_op() {
  local home="$_HI_SETCOLOR_HOME" cfg="$_HI_WORKDIR/cfg" out
  _hi_setcolor_overlay "$cfg" '[username]\nbox = "red"\n'
  out="$(_hi_color_run remove "$cfg" hostname box)" || _hi_why home cfg || return 1
  { [[ "$out" == *"$cfg/colors has no [hostname] pin for box - nothing to write"* ]] &&
    _hi_file_is "$cfg/colors" '[username]\nbox = "red"'; } || _hi_why out cfg
}

# --- the overlay file replaces the tree's wholesale, so the first write
# copies the tree's pins in -------------------------------------------------

function test_set_color_first_call_copies_the_tree_in() {
  local home="$_HI_SETCOLOR_HOME" cfg="$_HI_WORKDIR/cfg" n got
  _hi_color_run add "$cfg" hostname box cyan >/dev/null || _hi_why home cfg || return 1
  n="$(wc -l <"$home/say-hi/config/colors")"
  # the tree's lines plus the one pin, which taken out again leaves the tree
  got="$(wc -l <"$cfg/colors")"
  { [ "$got" -eq "$((n + 1))" ] && grep -vxF 'box = "cyan"' "$cfg/colors" | cmp -s - "$home/say-hi/config/colors"; } || _hi_why got cfg home
}

# a second call does not re-copy or clobber what the first one wrote
function test_set_color_second_call_does_not_recopy() {
  local home="$_HI_SETCOLOR_HOME" cfg="$_HI_WORKDIR/cfg"
  _hi_color_run add "$cfg" hostname a red >/dev/null || _hi_why home cfg || return 1
  printf '[hostname]\ntruncated = "red"\n' >"$cfg/colors"
  _hi_color_run add "$cfg" hostname b blue >/dev/null || _hi_why home cfg || return 1
  _hi_file_is "$cfg/colors" '[hostname]\ntruncated = "red"\nb = "blue"' || _hi_why cfg
}

# unsetting a shipped pin reads through the cascade and copies the tree in
# without it
function test_unset_color_copies_the_tree_in_without_the_pin() {
  local home="$_HI_SETCOLOR_HOME" cfg="$_HI_WORKDIR/cfg" n got
  grep -q '^root ' "$home/say-hi/config/colors" || _hi_why home || return 1
  _hi_color_run remove "$cfg" username root >/dev/null || _hi_why home cfg || return 1
  n="$(wc -l <"$home/say-hi/config/colors")"
  got="$(wc -l <"$cfg/colors")"
  { [ "$got" -eq "$((n - 1))" ] && ! grep -q '^root ' "$cfg/colors"; } || _hi_why got cfg
}

# --dry-run reads through the cascade too: an unset of a name the tree does
# not pin reports against the tree's file, and makes no overlay
function test_unset_color_dry_run_reads_through_the_cascade() {
  local home="$_HI_SETCOLOR_HOME" cfg="$_HI_WORKDIR/cfg" out
  out="$(_hi_color_run remove "$cfg" hostname hi-no-such-host --dry-run)" || _hi_why home cfg || return 1
  [[ "$out" == *"config/colors has no [hostname] pin for hi-no-such-host - nothing to write"* ]] &&
    [ ! -d "$cfg" ] || _hi_why out cfg
}

function run_set_color_tests() {
  _hi_workdir setcolor
  _hi_suite_begin
  # a target-shaped tree with scripts/, which is what makes --add-color
  # reachable at all; the cases only read it
  _HI_SETCOLOR_HOME="$(_hi_scratch_tree setcolor common config load.sh hi.sh link:scripts)"

  _hi_h2 "Testing: scripts/set_color.sh arguments"
  _hi_check "--add-color --help is its own text" test_set_color_help_is_its_own
  _hi_check "--remove-color --help is its own text" test_unset_color_help_is_its_own
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

  _hi_h2 "Testing: --remove-color"
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
