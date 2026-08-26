#!/usr/bin/env bash
# The boxed table the preview scripts draw with: measure every column, then
# print a rule, padded cells, and a closing rule.
#
# It sits in scripts/ rather than common/ on purpose - common/ ships in the ssh
# payload and wears a CI-enforced size budget, and nothing a target runs draws
# a table. Source it *after* common/core.sh, whose $NC and _hi_repeat it uses;
# sourcing it does nothing else.
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

# _hi_hbar <width...> - the +---+---+ rule; each column is padded by one space
# either side, so a width of n renders n+2 dashes
function _hi_hbar() {
  local seg="+" w dashes
  for w in "$@"; do
    _hi_repeat dashes $((w + 2)) '-'
    seg+="$dashes+"
  done
  printf '%s\n' "$seg"
}

# _hi_cell <width> <escape> <text> - one padded, colored cell of plain text; an
# empty escape and text render the blank cell continuation rows use.
function _hi_cell() {
  local padded
  printf -v padded '%-*s' "$1" "$3"
  printf '| %b ' "$2$padded$NC"
}

# _hi_cell_raw <width> <printed-width> <text> - a cell whose text carries its own
# escapes (so it cannot be measured, and the caller hands in what it will print
# as) and its own colors (so it is emitted as-is rather than wrapped in one).
function _hi_cell_raw() {
  printf '| %b%*s ' "$3$NC" "$(($1 - $2))" ''
}
