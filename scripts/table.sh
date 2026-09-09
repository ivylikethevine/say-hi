#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# The boxed table the preview scripts draw with: measure every column, then
# print a rule, padded cells, and a closing rule.
#
# It sits in scripts/ rather than common/ on purpose - common/ ships in the ssh
# payload and wears a CI-enforced size budget, and nothing a target runs draws
# a table. Source it *after* common/core.sh, whose $NC and _hi_repeat it uses,
# and after scripts/lib.sh, which decides the $_HI_BOX_* set every rule and
# edge below is drawn from; sourcing it does nothing else.
#
# The measure-then-render split is the contract. Every column's width has to be
# settled before the first cell prints, because a cell padded wider than the
# rule allowed for is exactly what a broken table looks like - and the two
# measurements are not interchangeable: _hi_widen sizes a column to text it can
# measure, _hi_widen_to to a width the caller already worked out (a cell full of
# color escapes has no length worth taking).

# _hi_visible_len <var> <text> - <text>'s printed width into <var>: the ANSI
# escapes stripped, then the characters counted. It lives here rather than in a
# caller because measuring is half of this file's measure-then-render contract.
# An out-var, not stdout: show_preview measures every line twice (once to size
# the box, once to pad it), and through $( ) each of those is a fork plus an
# extglob save/restore. extglob is needed for the *(...) pattern and restored
# to whatever it was, rather than left on for the rest of the caller. The
# pattern matches test_lib.sh's _hi_strip_ansi: *(...) and not +(...), so a
# bare `\e[m` reset counts as zero columns in both.
function _hi_visible_len() {
  local restore=0 stripped
  shopt -q extglob || {
    shopt -s extglob
    restore=1
  }
  stripped="${2//$'\e'\[*([0-9;])m/}"
  ((restore)) && shopt -u extglob
  # the same byte-vs-column split common/header.sh's _hi_visible_width takes,
  # and for the same reason: the box glyphs a rule is drawn from are three
  # bytes each, so a shell whose ${#} answers in bytes would size a column to
  # three times the rule it has to fit under. GLOSSARY: HI.12
  ((_HI_BYTE_COUNTS)) && stripped="${stripped//[$'\200'-$'\277']/}"
  printf -v "$1" '%s' "${#stripped}"
}

# _hi_widen <var> <string...> - grow the width variable named <var> to the
# longest of the strings.
function _hi_widen() {
  local var="$1" s cur
  shift
  eval "cur=\$$var"
  for s in "$@"; do
    ((${#s} > cur)) && cur=${#s}
  done
  eval "$var=\$cur"
}

# _hi_widen_to <var> <count...> - like _hi_widen, but the arguments are already
# widths rather than things to measure. Passing a number through _hi_widen would
# size the column to the length of its *digits*.
function _hi_widen_to() {
  local var="$1" n cur
  shift
  eval "cur=\$$var"
  for n in "$@"; do
    ((n > cur)) && cur=$n
  done
  eval "$var=\$cur"
}

# _hi_hbar <top|mid|bottom> <width...> - one horizontal rule; each column is
# padded by one space either side, so a width of n renders n+2 fills. The
# position picks the corners and the junction from lib.sh's $_HI_BOX_* set:
# every one of them is `+` on the ASCII side, so the three positions render
# identically there and differ only where the box glyphs do.
function _hi_hbar() {
  local pos="$1" left mid right w fill seg
  shift
  case "$pos" in
  top) left="$_HI_BOX_TL" mid="$_HI_BOX_T" right="$_HI_BOX_TR" ;;
  bottom) left="$_HI_BOX_BL" mid="$_HI_BOX_B" right="$_HI_BOX_BR" ;;
  *) left="$_HI_BOX_L" mid="$_HI_BOX_X" right="$_HI_BOX_R" ;;
  esac
  seg="$left"
  for w in "$@"; do
    [ "$seg" = "$left" ] || seg+="$mid"
    _hi_repeat fill $((w + 2)) "$_HI_BOX_H"
    seg+="$fill"
  done
  printf '%s\n' "$seg$right"
}

# _hi_row_end - the closing edge every row ends with, so no caller spells the
# glyph and a row cannot end in a different vocabulary than its rules
function _hi_row_end() {
  printf '%s\n' "$_HI_BOX_V"
}

# _hi_cell <width> <escape> <text> - one padded, colored cell of plain text; an
# empty escape and text render the blank cell continuation rows use.
function _hi_cell() {
  local padded
  printf -v padded '%-*s' "$1" "$3"
  printf '%s %b ' "$_HI_BOX_V" "$2$padded$NC"
}

# _hi_cell_raw <width> <printed-width> <text> - a cell whose text carries its own
# escapes (so it cannot be measured, and the caller hands in what it will print
# as) and its own colors (so it is emitted as-is rather than wrapped in one).
function _hi_cell_raw() {
  printf '%s %b%*s ' "$_HI_BOX_V" "$3$NC" "$(($1 - $2))" ''
}
