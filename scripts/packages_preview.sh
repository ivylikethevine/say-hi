#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# preview how the header's packages check will render: what each priority
# means, the colors it paints an installed and a missing package at that
# priority, a real example of each drawn from your own packages file, and the
# check itself as it will actually print. Run via `hi --preview-packages`.
set -euo pipefail

# GLOSSARY: HI.33 - the standalone-entry form, and why $_HI_HOME wins in it
_hi_d="${BASH_SOURCE[0]}"
case "$_hi_d" in */*) _hi_d="${_hi_d%/*}/.." ;; *) _hi_d=".." ;; esac
[ -z "${_HI_HOME:-}" ] || _hi_d="$_HI_HOME/say-hi"
# shellcheck source=../common/core.sh
source "$_hi_d/common/core.sh"
# shellcheck source=./lib.sh
source "$_hi_d/scripts/lib.sh"
unset _hi_d
# The renderer this previews, reused rather than reimplemented - check_line is
# what paints every row below, so the preview cannot drift from the header.
# Sourcing header.sh only defines functions.
# shellcheck source=../common/header.sh
source "$_HI_HEADER"
# shellcheck source=./table.sh
source "$_HI_ROOT/scripts/table.sh"

case "${1:-}" in
-h | --help)
  cat <<'EOF'
Usage: packages_preview.sh

Prints the legend for the header's packages check - every priority, the colors
it renders installed and missing packages in, and one real example of each
taken from your own packages file - then the marks, then the check itself
exactly as a connect will print it.

Takes no arguments. Reads:
  settings/packages      the [-|+]package:priority lines (override with $_HI_PACKAGES;
                     ~/.config/say-hi/packages wins automatically when present)
  common/header.sh   the priority meanings and their two color tables
  $_HI_PACKAGES_PALETTE   which of the named color tables is active (cool, the
                     default; warm; mono) - printed above the legend

A line's leading mode character decides which states speak at all: `-` only
when the whole line is missing, `+` only when something on it is installed,
no flag both ways - the MODE table below the marks spells them out. An
EXAMPLE cell reading "below floor" means $_HI_PACKAGES_MIN_PRIORITY is above
that rank, so the header prints nothing for it whatever its colors say. That
floor defaults to 2, so priorities 0-1 read "below floor" until you set one
of your own; anything above 3 mutes the check entirely. A priority with no
example at all has no package of its own in your file.
EOF
  exit 0
  ;;
esac

# _hi_priority_meanings - "<priority>\t<meaning>" per priority, read from the
# comment block header.sh keeps directly above _HI_YES rather than copied here:
# that block is the only description of the priorities there is, and a copy
# would be a second thing to keep true. Only the run of lines immediately
# preceding _HI_YES counts, so an unrelated "# 2 ..." elsewhere can't join in.
# The parenthetical examples are dropped - the EXAMPLE column below shows real
# ones, from the file the header will actually read.
function _hi_priority_meanings() {
  awk '
    /^_HI_YES=/ {
      for (i = 1; i <= n; i++) print buf[i]
      exit
    }
    /^# [0-9]+ [^ ]/ {
      line = $0
      p = $2
      sub(/^# [0-9]+ +/, "", line)
      sub(/ *\(.*/, "", line)
      buf[++n] = p "\t" line
      next
    }
    { n = 0 }
  ' "$_HI_HEADER"
}

# _hi_color_name_of <escape> - name the palette entry an escape came from, so
# the table can print "brgreen" beside a cell painted with it. _HI_YES/_HI_NO
# hold escapes, not names, and this is the only way back without a second copy
# of the mapping. Both sides go through printf '%b' because core.sh's palette
# variables hold a literal "\e[..." while _hi_color_escape emits a real ESC.
# Anything outside the palette - $NC, and every color under $NO_COLOR - is
# "plain", which is exactly how it will render.
# The escapes for _HI_COLOR_NAMES, in the same order, resolved once. Built
# here rather than inside _hi_color_name_of, which the legend calls four
# times a row - resolving all twelve names on every one of those calls would
# fork _hi_color_escape forty-eight times instead of twelve.
_HI_COLOR_ESCAPES=()
for _hi_cn in "${_HI_COLOR_NAMES[@]}"; do
  _HI_COLOR_ESCAPES+=("$(_hi_color_escape "$_hi_cn")")
done
unset _hi_cn

function _hi_color_name_of() {
  local want i=0
  want=$(printf '%b' "$1")
  [[ -n "$want" ]] || {
    printf 'plain'
    return
  }
  while ((i < ${#_HI_COLOR_NAMES[@]})); do
    [[ "$want" = "${_HI_COLOR_ESCAPES[i]}" ]] && {
      printf '%s' "${_HI_COLOR_NAMES[i]}"
      return
    }
    i=$((i + 1))
  done
  printf 'plain'
}

# Filled by _hi_collect_examples, read by the table: per-priority example rows
# and their printed widths, plus the two totals under the table. Indexed by
# priority (a plain indexed array - bash 3.2 has no associative ones), and
# global rather than local because the collector cannot return six things.
_HI_EX_OK=() _HI_EX_OK_W=() _HI_EX_NO=() _HI_EX_NO_W=()
_HI_PKG_LISTED=0 _HI_PKG_SHOWN=0 _HI_PKG_FLOORED=0
# read once, here, rather than at each use: full_check reads the same setting
# and this preview has to answer for the floor the header will actually apply
_HI_PKG_MIN="${_HI_PACKAGES_MIN_PRIORITY:-2}"

# Run the real check over the real packages file and keep the first installed
# and first missing row at each priority. check_line appends what it would print
# to `visible` (bash's dynamic scoping - full_check calls it exactly this way)
# and drops mode-suppressed rows on the floor, which is the point: a `-` line
# that is installed, or a `+` line that is missing, has no example to show
# because it shows nothing.
function _hi_collect_examples() {
  local line entry priority width rendered
  local -a visible=()

  while IFS=$' ' read -r line; do
    # the header's own filter, character for character
    [[ "$line" == *#* || -z "$line" ]] && continue
    _HI_PKG_LISTED=$((_HI_PKG_LISTED + 1))
    check_line "$line"
  done <"$_HI_PACKAGES"
  _HI_PKG_SHOWN=${#visible[@]}

  for entry in ${visible[@]+"${visible[@]}"}; do
    IFS=$'\x1f' read -r priority width rendered <<<"$entry"
    # counted, not skipped: the example is still collected so the table can show
    # what this rank *would* print, with the cell saying the floor is why it
    # does not. full_check applies the same floor for real.
    ((priority >= _HI_PKG_MIN)) || _HI_PKG_FLOORED=$((_HI_PKG_FLOORED + 1))
    # the mark is the last thing check_line renders, and $RED prefixes only
    # that one - a bare "x" (the ASCII glyph) also occurs inside package names
    if [[ "$rendered" == *"$RED$_HI_MARK_NO" ]]; then
      [[ -n "${_HI_EX_NO[priority]:-}" ]] || {
        _HI_EX_NO[priority]="$rendered"
        _HI_EX_NO_W[priority]="$width"
      }
    else
      [[ -n "${_HI_EX_OK[priority]:-}" ]] || {
        _HI_EX_OK[priority]="$rendered"
        _HI_EX_OK_W[priority]="$width"
      }
    fi
  done
}

# _hi_example_cell <priority> - the installed example then the missing one, laid
# out the way full_check lays a row out ("|<rendered> " each), and the printed
# width that comes to. Two values, so it prints them tab-separated rather than
# writing to yet another global.
function _hi_example_cell() {
  local p="$1" text="" width=0
  # the floor's own "hidden": a rank below it renders nothing in the header
  # whatever its colors say, so the cell names the reason rather than showing an
  # example that will never appear
  if ((p < _HI_PKG_MIN)); then
    printf '%s\t%s' "below floor" 11
    return 0
  fi
  if [[ -n "${_HI_EX_OK[p]:-}" ]]; then
    text+="$NC|${_HI_EX_OK[p]} "
    width=$((width + _HI_EX_OK_W[p]))
  fi
  if [[ -n "${_HI_EX_NO[p]:-}" ]]; then
    text+="$NC|${_HI_EX_NO[p]} "
    width=$((width + _HI_EX_NO_W[p]))
  fi
  [[ -n "$text" ]] || {
    text="-" width=1
  }
  printf '%s\t%s' "$text" "$width"
}

# the legend: one row per priority, highest first (the order full_check sorts
# its output into), each painted in the colors that priority actually uses
function _hi_print_priorities_table() {
  local entry p meaning yes_escape no_escape yes_name no_name example ex_width
  local i=0
  local -a rows=() c_yes=() c_no=() c_example=() c_ex_width=()
  local w_prio=8 w_meaning=7 w_yes=9 w_no=7 w_example=7

  _hi_read_lines rows < <(_hi_priority_meanings | LC_ALL=C sort -k1,1nr)

  # The measure pass keeps what it worked out, indexed by row, so the render
  # pass below reads it instead of calling _hi_color_name_of and
  # _hi_example_cell a second time for every row. Same parallel-array shape as
  # _HI_EX_OK/_HI_EX_OK_W above.
  for entry in ${rows[@]+"${rows[@]}"}; do
    IFS=$'\t' read -r p meaning <<<"$entry"
    _hi_widen w_meaning "$meaning"
    c_yes[i]="$(_hi_color_name_of "${_HI_YES[p]:-}")"
    c_no[i]="$(_hi_color_name_of "${_HI_NO[p]:-}")"
    _hi_widen w_yes "${c_yes[i]}"
    _hi_widen w_no "${c_no[i]}"
    IFS=$'\t' read -r example ex_width <<<"$(_hi_example_cell "$p")"
    c_example[i]="$example"
    c_ex_width[i]="$ex_width"
    _hi_widen_to w_example "$ex_width"
    i=$((i + 1))
  done

  _hi_hbar "$w_prio" "$w_meaning" "$w_yes" "$w_no" "$w_example"
  printf '| %-*s | %-*s | %-*s | %-*s | %-*s |\n' \
    "$w_prio" "PRIORITY" "$w_meaning" "MEANING" "$w_yes" "INSTALLED" \
    "$w_no" "MISSING" "$w_example" "EXAMPLE"
  _hi_hbar "$w_prio" "$w_meaning" "$w_yes" "$w_no" "$w_example"

  i=0
  for entry in ${rows[@]+"${rows[@]}"}; do
    IFS=$'\t' read -r p meaning <<<"$entry"
    yes_escape="${_HI_YES[p]:-}"
    no_escape="${_HI_NO[p]:-}"
    yes_name="${c_yes[i]}"
    no_name="${c_no[i]}"
    example="${c_example[i]}"
    ex_width="${c_ex_width[i]}"
    i=$((i + 1))

    _hi_cell "$w_prio" "" "$p"
    _hi_cell "$w_meaning" "" "$meaning"
    _hi_cell "$w_yes" "$yes_escape" "$yes_name"
    _hi_cell "$w_no" "$no_escape" "$no_name"
    _hi_cell_raw "$w_example" "$ex_width" "$example"
    printf '|\n'
  done

  _hi_hbar "$w_prio" "$w_meaning" "$w_yes" "$w_no" "$w_example"
  _hi_cecho " | $_HI_PKG_LISTED listed, $((_HI_PKG_SHOWN - _HI_PKG_FLOORED)) shown, $((_HI_PKG_LISTED - _HI_PKG_SHOWN)) hidden by their priority"
  if ((_HI_PKG_MIN > 0)); then
    _hi_cecho " | $_HI_PKG_FLOORED more below \$_HI_PACKAGES_MIN_PRIORITY=$_HI_PKG_MIN, which this legend marks \"below floor\"" "$YELLOW"
  fi
}

# the other half of a rendered row: which of the three marks it ends in, and
# what each one is saying. The glyphs come from core.sh's _hi_choose_glyphs, so
# this table follows a terminal onto the ASCII set the same way the header does.
function _hi_print_marks_table() {
  local w_mark=4 w_means=5
  local -a marks=(
    "$GREEN$_HI_MARK_OK|$_HI_MARK_OK_W|installed, under the first name the line lists"
    "$YELLOW$_HI_MARK_ALT|$_HI_MARK_ALT_W|installed, but via one of the alternatives after it"
    "$RED$_HI_MARK_NO|$_HI_MARK_NO_W|not installed - no name on the line resolved"
  )
  local entry glyph width means

  for entry in "${marks[@]}"; do
    IFS='|' read -r glyph width means <<<"$entry"
    _hi_widen_to w_mark "$width"
    _hi_widen w_means "$means"
  done

  _hi_hbar "$w_mark" "$w_means"
  printf '| %-*s | %-*s |\n' "$w_mark" "MARK" "$w_means" "MEANS"
  _hi_hbar "$w_mark" "$w_means"
  for entry in "${marks[@]}"; do
    IFS='|' read -r glyph width means <<<"$entry"
    _hi_cell_raw "$w_mark" "$width" "$glyph"
    _hi_cell "$w_means" "" "$means"
    printf '|\n'
  done
  _hi_hbar "$w_mark" "$w_means"
}

# the third axis of a line: its leading mode character, which decides whether
# the row speaks at all. No glyph negotiation here - `-` and `+` are the
# literal characters the packages file uses.
function _hi_print_modes_table() {
  local w_mode=4 w_means=5
  local -a modes=(
    "-|speaks only when the whole line is missing"
    "+|speaks only when something on the line is installed"
    "none|speaks both ways - the default"
  )
  local entry flag means

  for entry in "${modes[@]}"; do
    IFS='|' read -r flag means <<<"$entry"
    _hi_widen w_mode "$flag"
    _hi_widen w_means "$means"
  done

  _hi_hbar "$w_mode" "$w_means"
  printf '| %-*s | %-*s |\n' "$w_mode" "MODE" "$w_means" "MEANS"
  _hi_hbar "$w_mode" "$w_means"
  for entry in "${modes[@]}"; do
    IFS='|' read -r flag means <<<"$entry"
    _hi_cell "$w_mode" "" "$flag"
    _hi_cell "$w_means" "" "$means"
    printf '|\n'
  done
  _hi_hbar "$w_mode" "$w_means"
}

# same hatch as scripts/color_preview.sh: sourcing this file defines its
# functions without rendering anything, which is what
# tests/scripts/packages_preview_test.sh needs
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

# Everything below reads it, so there is no half-preview worth printing - and
# the bare redirect this saves fails as "No such file", naming a path without
# saying which of the two it was looking for.
if [[ ! -f "$_HI_PACKAGES" ]]; then
  _hi_cecho "No packages file at $_HI_PACKAGES - the header has nothing to check" "$RED"
  exit 1
fi

_hi_cecho " | reading $_HI_PACKAGES"
_hi_cecho " | palette: ${_HI_PACKAGES_PALETTE:-cool}"
if _hi_has_truecolor; then
  _hi_cecho " | scheme: ${_HI_COLOR_SCHEME:-default}"
else
  _hi_cecho " | scheme: ${_HI_COLOR_SCHEME:-default} (no truecolor here - the 16-color escapes render)"
fi
printf '\n'
_hi_collect_examples
_hi_print_priorities_table
printf '\n'
_hi_print_marks_table
printf '\n'
_hi_print_modes_table
printf '\n'
_hi_h2 "as the header will print it"
full_check
