#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
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
# shellcheck source=../../scripts/lib.sh
source "$_HI_ROOT/scripts/lib.sh"

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

# Built from the $_HI_BOX_* set in play rather than from a literal "+---+":
# the runner's locale picks the set, so a literal would only pass on one side.
function _hi_rule() { # <left> <junction> <right> <width...>
  local left="$1" mid="$2" right="$3" w fill out="$1"
  shift 3
  for w in "$@"; do
    [ "$out" = "$left" ] || out+="$mid"
    _hi_repeat fill $((w + 2)) "$_HI_BOX_H"
    out+="$fill"
  done
  printf '%s' "$out$right"
}

function test_hbar_pads_each_column_by_two() {
  # width n renders n+2 fills per segment
  local l="$_HI_BOX_L" x="$_HI_BOX_X" r="$_HI_BOX_R"
  [ "$(_hi_hbar mid 1)" = "$(_hi_rule "$l" "$x" "$r" 1)" ] || return 1
  [ "$(_hi_hbar mid 2 3)" = "$(_hi_rule "$l" "$x" "$r" 2 3)" ]
}

# ASCII spells all nine corners `+`, so the three positions are one rule there.
# Forced through a child shell, since scripts/lib.sh decides the set at source time.
function test_hbar_positions_are_one_rule_in_ascii() {
  local out
  out="$(_HI_ASCII=1 bash -c '
    source "$_HI_HOME/say-hi/common/core.sh"
    source "$_HI_HOME/say-hi/scripts/lib.sh"
    source "$_HI_HOME/say-hi/scripts/table.sh"
    _hi_hbar top 2 3
    _hi_hbar mid 2 3
    _hi_hbar bottom 2 3')" || return 1
  [ "$out" = "$(printf '%s\n%s\n%s' '+----+-----+' '+----+-----+' '+----+-----+')" ]
}

function test_hbar_positions_differ_on_the_glyph_set() {
  local out
  out="$(_HI_ASCII=0 bash -c '
    source "$_HI_HOME/say-hi/common/core.sh"
    source "$_HI_HOME/say-hi/scripts/lib.sh"
    source "$_HI_HOME/say-hi/scripts/table.sh"
    _hi_hbar top 1 1
    _hi_hbar mid 1 1
    _hi_hbar bottom 1 1')" || return 1
  [ "$out" = "$(printf '%s\n%s\n%s' '┌───┬───┐' '├───┼───┤' '└───┴───┘')" ]
}

function test_cell_pads_to_the_width() {
  local want padded
  printf -v padded '%-5s' ab
  printf -v want '%s %b ' "$_HI_BOX_V" "${RED}${padded}${NC}"
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
  printf -v want '%s %b ' "$_HI_BOX_V" "${padded}${NC}"
  [ "$(_hi_cell 4 '' '')" = "$want" ]
}

function test_cell_raw_pads_by_the_declared_width() {
  local text want
  printf -v text '%b' "${BRCYAN}ab${NC}"
  # caller says the text prints as 2 columns; the cell pads the other 4
  printf -v want '%s %b%*s ' "$_HI_BOX_V" "${text}${NC}" 4 ''
  [ "$(_hi_cell_raw 6 2 "$text")" = "$want" ]
}

# _hi_hrule/_hi_h1/_hi_h2 (scripts/lib.sh) draw every section heading
# everywhere; nothing asserts their own shape anywhere else, since every
# caller's own output is what gets checked, not the heading around it.
function test_hrule_spans_max_width() {
  local out n
  out="$(_HI_MAX_WIDTH=40 _hi_hrule "label" '-' 2 "$BRCYAN")"
  _hi_visible_len n "$out"
  [ "$n" -eq 40 ]
}

function test_h1_and_h2_span_max_width_too() {
  local out n
  out="$(_HI_MAX_WIDTH=50 _hi_h1 "Heading")"
  _hi_visible_len n "$out"
  [ "$n" -eq 50 ] || return 1
  out="$(_HI_MAX_WIDTH=50 _hi_h2 "Heading")"
  _hi_visible_len n "$out"
  [ "$n" -eq 50 ]
}

# a label wider than the rule clamps the bar split to 8 rather than going
# negative - the overlong label then overflows the line instead of crashing
function test_hrule_clamps_and_overflows_for_a_wide_label() {
  local out n label
  label="$(printf 'x%.0s' $(seq 1 100))"
  out="$(_HI_MAX_WIDTH=40 _hi_hrule "$label" '=' 1 "$BRBLUE")"
  _hi_visible_len n "$out"
  [ "$n" -gt 40 ]
}

# _hi_scheme_label's four answers (scripts/lib.sh): the preview line and the
# doctor report both print it, and only the default arm is reached by their
# cases. A custom scheme is twenty-four (or forty-eight) hex words.
function test_scheme_label_names_each_kind() {
  local label custom
  custom="$(printf 'abcdef %.0s' $(seq 1 24))"
  custom="${custom% }"
  _HI_COLOR_SCHEME="" _hi_scheme_label label
  [ "$label" = default ] || return 1
  _HI_COLOR_SCHEME="$custom" _hi_scheme_label label
  [ "$label" = "custom (24)" ] || return 1
  _HI_COLOR_SCHEME="$custom $custom" _hi_scheme_label label
  [ "$label" = "custom (48)" ] || return 1
  _HI_COLOR_SCHEME=nope _hi_scheme_label label
  [ "$label" = "nope (ignored - not a scheme)" ]
}

# the box glyphs are chosen once at source time off _hi_use_ascii, so each
# side is proven by re-sourcing lib.sh in a child with _HI_ASCII forced. All
# eleven, in reading order: the three rules, then the fill and the edge.
_HI_BOX_NAMES="TL T TR L X R BL B BR H V"
function _hi_box_glyphs() {
  _HI_ASCII="$1" bash -c '
    source "$_HI_HOME/say-hi/common/core.sh"
    source "$_HI_HOME/say-hi/scripts/lib.sh"
    for n in '"$_HI_BOX_NAMES"'; do eval "printf %s \"\$_HI_BOX_$n\""; done'
}
function test_box_glyphs_follow_the_ascii_switch() {
  local out
  out="$(_hi_box_glyphs 1)" || return 1
  [ "$out" = '+++++++++-|' ] || return 1
  out="$(_hi_box_glyphs 0)" || return 1
  [ "$out" = '┌┬┐├┼┤└┴┘─│' ]
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
  _hi_check "_hi_hbar: each column is width+2 dashes" test_hbar_pads_each_column_by_two
  _hi_check "_hi_hbar: one rule for all three positions in ASCII" test_hbar_positions_are_one_rule_in_ascii
  _hi_check "_hi_hbar: corners and junctions on the glyph set" test_hbar_positions_differ_on_the_glyph_set

  _hi_h2 "Testing: _hi_cell / _hi_cell_raw"
  _hi_check "Pads to the width" test_cell_pads_to_the_width
  _hi_check "Visible width is width + frame" test_cell_visible_width_is_stable
  _hi_check "Empty cell is the continuation blank" test_cell_empty_renders_the_continuation_blank
  _hi_check "_hi_cell_raw pads by the declared width" test_cell_raw_pads_by_the_declared_width

  _hi_h2 "Testing: _hi_hrule / _hi_h1 / _hi_h2 (scripts/lib.sh)"
  _hi_check "Spans _HI_MAX_WIDTH" test_hrule_spans_max_width
  _hi_check "_hi_h1/_hi_h2 span it too" test_h1_and_h2_span_max_width_too
  _hi_check "A wide label clamps and overflows" test_hrule_clamps_and_overflows_for_a_wide_label

  _hi_h2 "Testing: _hi_scheme_label / the box glyphs (scripts/lib.sh)"
  _hi_check "_hi_scheme_label names each kind of scheme" test_scheme_label_names_each_kind
  _hi_check "Box glyphs follow _HI_ASCII" test_box_glyphs_follow_the_ascii_switch

  _hi_suite_end "table.sh"
}

run_table_tests
