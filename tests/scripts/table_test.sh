#!/usr/bin/env bash
# Unit tests for scripts/table.sh: the measure-then-render contract - the two
# wideners, the rule, and both cell renderers. Everything here is a pure
# string/width function, so every case is an exact-output comparison.
# GLOSSARY: HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"
# shellcheck source=../../scripts/table.sh
source "$_HI_ROOT/scripts/table.sh"

function test_visible_len_counts_plain_text() {
  local n
  _hi_visible_len n "hello"
  [ "$n" = 5 ]
}

function test_visible_len_strips_ansi_escapes() {
  local n colored
  printf -v colored '%b' "${RED}ab${NC}"
  _hi_visible_len n "$colored"
  [ "$n" = 2 ] || return 1
  # a bare reset with no parameters counts as zero columns too
  _hi_visible_len n $'\e[mx'
  [ "$n" = 1 ]
}

function test_widen_grows_to_the_longest_string() {
  local w=0
  _hi_widen w one three seven-x
  [ "$w" = 7 ]
}

function test_widen_never_shrinks() {
  local w=10
  _hi_widen w abc
  [ "$w" = 10 ]
}

function test_widen_to_takes_widths_not_strings() {
  local w=2
  _hi_widen_to w 5 12 7
  [ "$w" = 12 ] || return 1
  # the trap _hi_widen_to exists for: _hi_widen would measure "12" as 2 chars
  w=3
  _hi_widen w 12
  [ "$w" = 3 ]
}

function test_hbar_pads_each_column_by_two() {
  # width n renders n+2 dashes per segment
  [ "$(_hi_hbar 1)" = "+---+" ] || return 1
  [ "$(_hi_hbar 2 3)" = "+----+-----+" ]
}

function test_cell_pads_to_the_width() {
  local want padded
  printf -v padded '%-5s' ab
  printf -v want '| %b ' "${RED}${padded}${NC}"
  [ "$(_hi_cell 5 "$RED" ab)" = "$want" ]
}

function test_cell_visible_width_is_stable() {
  # however the colors render, the printed width must be width + 3 ("| " and
  # the trailing pad space)
  local n
  _hi_visible_len n "$(_hi_cell 6 "$GREEN" abc)"
  [ "$n" = 9 ]
}

function test_cell_empty_renders_the_continuation_blank() {
  local want padded
  printf -v padded '%-4s' ''
  printf -v want '| %b ' "${padded}${NC}"
  [ "$(_hi_cell 4 '' '')" = "$want" ]
}

function test_cell_raw_pads_by_the_declared_width() {
  local text want
  printf -v text '%b' "${BRCYAN}ab${NC}"
  # caller says the text prints as 2 columns; the cell pads the other 4
  printf -v want '| %b%*s ' "${text}${NC}" 4 ''
  [ "$(_hi_cell_raw 6 2 "$text")" = "$want" ]
}

function run_table_tests() {
  _hi_h1 "Testing scripts/table.sh"
  _hi_workdir table
  _hi_suite_begin

  _hi_h2 "Testing: _hi_visible_len"
  _hi_check "Counts plain text" test_visible_len_counts_plain_text
  _hi_check "Strips ANSI escapes before counting" test_visible_len_strips_ansi_escapes

  _hi_h2 "Testing: _hi_widen / _hi_widen_to"
  _hi_check "Grows to the longest string" test_widen_grows_to_the_longest_string
  _hi_check "Never shrinks" test_widen_never_shrinks
  _hi_check "_hi_widen_to takes widths, not strings" test_widen_to_takes_widths_not_strings

  _hi_h2 "Testing: _hi_hbar"
  _hi_check "Each column is width+2 dashes" test_hbar_pads_each_column_by_two

  _hi_h2 "Testing: _hi_cell / _hi_cell_raw"
  _hi_check "Pads to the width" test_cell_pads_to_the_width
  _hi_check "Visible width is width + frame" test_cell_visible_width_is_stable
  _hi_check "Empty cell is the continuation blank" test_cell_empty_renders_the_continuation_blank
  _hi_check "_hi_cell_raw pads by the declared width" test_cell_raw_pads_by_the_declared_width

  _hi_suite_end "table.sh"
}

run_table_tests
