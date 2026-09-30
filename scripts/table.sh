#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# The display every script draws through: the column pad, the pieces a line
# is painted from, the boxed table the previews draw (measure every column,
# then print a rule, padded cells, and a closing rule), and the section of
# rows a report lists.
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

# _hi_pad_to <var> <width> <text> [right] - <text> into <var>, spaces after
# it to <width> printed columns as _hi_visible_len measures them (before it,
# right-aligned, with `right`): the one column pad every script draws with,
# escapes and multibyte glyphs counted as what they print. A text already
# that wide or wider goes in as it is.
function _hi_pad_to() {
  local _hi_pt_n _hi_pt_s
  _hi_visible_len _hi_pt_n "$3"
  _hi_repeat _hi_pt_s $(($2 - _hi_pt_n)) ' '
  if [ "${4:-}" = right ]; then
    printf -v "$1" '%s' "$_hi_pt_s$3"
  else
    printf -v "$1" '%s' "$3$_hi_pt_s"
  fi
}

# _hi_pad_cols <width> - stdin to stdout, each line's text ahead of a \037
# padded to <width> and joined to the rest by a space: a column for a writer
# with no bash of its own (awk emits the \037). Other lines pass as they are.
function _hi_pad_cols() {
  local line nl cell us=$'\037'
  while :; do
    if IFS= read -r line; then nl=$'\n'; else
      [ -n "$line" ] || break
      nl=""
    fi
    case "$line" in *"$us"*)
      _hi_pad_to cell "$1" "${line%%"$us"*}"
      line="$cell ${line#*"$us"}"
      ;;
    esac
    printf '%s%s' "$line" "$nl"
  done
}

# _hi_paint <outvar> <color> <text> - <text> in <color>, the palette's
# escapes expanded so the result can be joined into a row or a `read -p`
# prompt. Under $NO_COLOR both halves are empty (core.sh) and it is plain.
function _hi_paint() {
  printf -v "$1" '%b%s%b' "$2" "$3" "$NC"
}

# _hi_hotkey <name> <letter> <outvar> - <name> with its shortcut letter in
# brackets, [e]verything or p[r]ompt: how every menu spells an option whose
# letter is typed rather than its number, so the key and the word are read
# together and nothing has to say "or type e". The key is painted
# $BRYELLOW, the color of everything a menu has you type.
function _hi_hotkey() {
  local name="$1" key="$2" head
  head="${name%%"$key"*}"
  if [ "$head" = "$name" ]; then
    printf -v "$3" '%s' "$name"
  else
    printf -v "$3" '%s%b[%s]%b%s' "$head" "$BRYELLOW" "$key" "$NC" "${name#*"$key"}"
  fi
}

# _hi_fit <outvar> <text> <room> - <text> cut to <room> characters, the cut
# marked with "..."; plain text only, painted after
function _hi_fit() {
  local _hi_ft="$2"
  ((${#_hi_ft} > $3)) && _hi_ft="${_hi_ft:0:$(($3 > 3 ? $3 - 3 : 0))}..."
  printf -v "$1" '%s' "$_hi_ft"
}

# _hi_widen_to <var> <count...> - grow the width variable named <var> to the
# largest of the counts; the primitive _hi_widen below measures into.
# Arguments are already widths rather than things to measure - passing a
# number through _hi_widen would size the column to the length of its
# *digits*.
function _hi_widen_to() {
  local var="$1" n cur
  shift
  cur="${!var}"
  for n in "$@"; do
    ((n > cur)) && cur=$n
  done
  printf -v "$var" '%s' "$cur"
}

# _hi_widen <var> <string...> - grow the width variable named <var> to the
# longest of the strings.
function _hi_widen() {
  local s
  local -a lens=()
  local var="$1"
  shift
  for s in "$@"; do lens+=("${#s}"); done
  _hi_widen_to "$var" ${lens[@]+"${lens[@]}"}
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

# _hi_head_row <width> <label>... - the header row, each label padded to its column
function _hi_head_row() {
  local out="$_HI_BOX_V" cell
  while [ $# -ge 2 ]; do
    _hi_pad_to cell "$1" "$2"
    out="$out $cell $_HI_BOX_V"
    shift 2
  done
  printf '%s\n' "$out"
}

# _hi_row_end - the closing edge every row ends with, so no caller spells the
# glyph and a row cannot end in a different vocabulary than its rules
function _hi_row_end() {
  printf '%s\n' "$_HI_BOX_V"
}

# _hi_cell <width> <escape> <text> - one padded, colored cell of plain text; an
# empty escape and text render the blank cell continuation rows use. Only the
# escapes go through %b: the text is printed as-is, backslashes and all.
function _hi_cell() {
  local padded
  _hi_pad_to padded "$1" "$3"
  _hi_paint padded "$2" "$padded"
  printf '%s %s ' "$_HI_BOX_V" "$padded"
}

# _hi_cell_raw <width> <printed-width> <text> - a cell whose text carries its own
# escapes (so it cannot be measured, and the caller hands in what it will print
# as) and its own colors (so it is emitted as-is rather than wrapped in one).
function _hi_cell_raw() {
  local pad
  _hi_repeat pad $(($1 - $2)) ' '
  printf '%s %b%s ' "$_HI_BOX_V" "$3$NC" "$pad"
}

# The report every listing draws: a section's rows buffered as parallel arrays
# (bash 3.2 has no other kind) - a label, a text, and a severity: "" or info
# plain, ok green, warn yellow, bad red - and drawn as one boxed table by
# _hi_rows_flush once every width is known. `hi --doctor` and `hi --plugins`
# both draw through it.
_HI_ROWS_LABEL=() _HI_ROWS_TEXT=() _HI_ROWS_SEV=()

# _hi_section <title> - a section's banner, $HOME shortened to ~
function _hi_section() {
  _hi_tilde "$1"
  _hi_h2 "$_HI_TILDED"
}

# _hi_row <label> <text> [severity] - one row of the open section
function _hi_row() {
  _HI_ROWS_LABEL+=("$1") _HI_ROWS_TEXT+=("$2") _HI_ROWS_SEV+=("${3:-info}")
}

# _hi_rows_flush - draw the open section's rows and empty the buffer; nothing
# for a section with no rows
function _hi_rows_flush() {
  _hi_rows_box
  _HI_ROWS_LABEL=() _HI_ROWS_TEXT=() _HI_ROWS_SEV=()
}

# _hi_tilde <text> - <text> with $HOME shortened to ~, into
# $_HI_TILDED, for the boxed report only: --json keeps whole paths for
# whatever parses it. A plain variable, since bash 3.2's printf -v cannot
# write an array element; the ~ from one too, since 3.2 keeps a \~
# replacement's backslash.
_HI_TILDED=""
function _hi_tilde() {
  local tilde='~'
  _HI_TILDED="$1"
  [ -n "${HOME:-}" ] && [ "$HOME" != / ] || return 0
  _HI_TILDED="${_HI_TILDED//"$HOME"\//$tilde/}"
  [ "$_HI_TILDED" != "$HOME" ] || _HI_TILDED="$tilde"
}

# _hi_glyph <sev> - the severity's mark and color into $glyph and $color
# (the caller's locals). The marks are core.sh's one-column $_HI_MARK_* pair,
# ASCII where the locale is, so a report with no color still says which row
# is which; ! is the same in both sets.
function _hi_glyph() {
  case "$1" in
  ok) glyph="$_HI_MARK_OK" color="$GREEN" ;;
  warn) glyph="!" color="$YELLOW" ;;
  bad) glyph="$_HI_MARK_NO" color="$RED" ;;
  *) glyph="" color="" ;;
  esac
}

# _hi_wrap <width> <line> - <line> cut at spaces into pieces no wider than
# <width> (a word wider than that is split), appended to the caller's $pieces
function _hi_wrap() {
  local w="$1" rest="$2" cut
  while [ "${#rest}" -gt "$w" ]; do
    cut="${rest:0:w+1}"
    cut="${cut% *}"
    if [ -z "$cut" ] || [ "${#cut}" -gt "$w" ]; then
      cut="${rest:0:w}"
      rest="${rest:w}"
    else
      rest="${rest:${#cut}+1}"
    fi
    pieces+=("$cut")
  done
  pieces+=("$rest")
}

# _hi_rows_box - the rows in $_HI_ROWS_* as one boxed table: a mark column,
# the label, and the text. A text of several
# lines (ssh's stderr) is one row whose later lines leave the first two
# columns blank. On a terminal the text column is cut down to fit the width
# lib.sh's _hi_out_width gives, and a longer line wraps; captured, a row
# stays one line, whole for a grep or a bug report.
function _hi_rows_box() {
  local wl=0 wt=0 i=0 n line first glyph color fit
  local -a pieces
  _hi_rows_fold
  n="${#_HI_ROWS_SEV[@]}"
  [ "$n" -gt 0 ] || return 0
  while [ "$i" -lt "$n" ]; do
    _hi_tilde "${_HI_ROWS_LABEL[i]}"
    _HI_ROWS_LABEL[i]="$_HI_TILDED"
    _hi_tilde "${_HI_ROWS_TEXT[i]}"
    _HI_ROWS_TEXT[i]="$_HI_TILDED"
    _hi_widen wl "${_HI_ROWS_LABEL[i]}"
    # a carriage return (ssh ends its stderr lines in one) or a tab would
    # print narrower or wider than it measures, so both are gone first
    line="${_HI_ROWS_TEXT[i]//$'\r'/}"
    _HI_ROWS_TEXT[i]="${line//$'\t'/ }"
    while IFS= read -r line; do _hi_widen wt "$line"; done <<<"${_HI_ROWS_TEXT[i]}"
    i=$((i + 1))
  done
  if [ -t 1 ] || [ -n "${_HI_TERM_COLS+x}" ]; then
    # four edges and a space either side of three cells: wl + wt + 11 columns
    _hi_out_width fit
    fit=$((fit - wl - 11))
    [ "$fit" -ge 20 ] || fit=20
    [ "$wt" -le "$fit" ] || wt=$fit
  fi
  _hi_hbar top 1 "$wl" "$wt"
  i=0
  while [ "$i" -lt "$n" ]; do
    _hi_glyph "${_HI_ROWS_SEV[i]}"
    pieces=()
    while IFS= read -r line; do _hi_wrap "$wt" "$line"; done <<<"${_HI_ROWS_TEXT[i]}"
    first=1
    for line in "${pieces[@]}"; do
      if [ "$first" = 1 ]; then
        _hi_cell 1 "$color" "$glyph"
        _hi_cell "$wl" "" "${_HI_ROWS_LABEL[i]}"
        first=0
      else
        _hi_cell 1 "" ""
        _hi_cell "$wl" "" ""
      fi
      _hi_cell "$wt" "$color" "$line"
      _hi_row_end
    done
    i=$((i + 1))
  done
  _hi_hbar bottom 1 "$wl" "$wt"
}

# _hi_rows_fold - plain rows sharing one line of text become one row, the
# shared text as its label and theirs as its text (`not installed | podman
# finch nomad`), in the first one's place. Only the box folds: --json keeps a
# row per check.
function _hi_rows_fold() {
  local i j n="${#_HI_ROWS_SEV[@]}" names
  local -a f_label=() f_text=() f_sev=() f_used=()
  for ((i = 0; i < n; i++)); do
    [ -z "${f_used[i]:-}" ] || continue
    names=""
    if [ "${_HI_ROWS_SEV[i]}" = info ] && [ -n "${_HI_ROWS_LABEL[i]}" ] && [[ "${_HI_ROWS_TEXT[i]}" != *$'\n'* ]]; then
      for ((j = i + 1; j < n; j++)); do
        [ -z "${f_used[j]:-}" ] && [ "${_HI_ROWS_SEV[j]}" = info ] && [ -n "${_HI_ROWS_LABEL[j]}" ] &&
          [ "${_HI_ROWS_TEXT[j]}" = "${_HI_ROWS_TEXT[i]}" ] || continue
        names="$names ${_HI_ROWS_LABEL[j]}"
        f_used[j]=1
      done
    fi
    if [ -n "$names" ]; then
      f_label+=("${_HI_ROWS_TEXT[i]}") f_text+=("${_HI_ROWS_LABEL[i]}$names") f_sev+=(info)
    else
      f_label+=("${_HI_ROWS_LABEL[i]}") f_text+=("${_HI_ROWS_TEXT[i]}") f_sev+=("${_HI_ROWS_SEV[i]}")
    fi
  done
  _HI_ROWS_LABEL=(${f_label[@]+"${f_label[@]}"}) _HI_ROWS_TEXT=(${f_text[@]+"${f_text[@]}"}) _HI_ROWS_SEV=(${f_sev[@]+"${f_sev[@]}"})
}
