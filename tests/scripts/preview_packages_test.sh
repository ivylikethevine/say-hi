#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# scripts/preview.sh's packages subject: the header's colors named, the
# examples, and the tables it renders.
# A part of preview_test.sh, a suite of its own so the Windows shards split them.
# The preamble's source line is preview_test.sh's - it sources the harness, and
# holds the helpers the parts share (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

_HI_PREVIEW_PART=packages
# shellcheck source=./preview_test.sh
source "${BASH_SOURCE[0]%/*}/preview_test.sh"

# every entry in the header's two ramps has to be a name the user can look up
# in config/colors, or the legend prints something meaningless - checked for
# the shipped ramp and for one of the user's own, since the ramps are
# _hi_packages_palette's output and this suite never sets
# $_HI_PACKAGES_PALETTE itself
function test_legend_names_every_header_color() {
  local ramp entry
  for ramp in "" "$_HI_TEST_RAMP"; do
    _HI_PACKAGES_PALETTE="$ramp" _hi_packages_palette
    for entry in "${_HI_YES_NAMES[@]}" "${_HI_NO_NAMES[@]}"; do
      [ -n "$entry" ] || _hi_why entry || return 1
      printf '%s\n' "${_HI_COLOR_NAMES[@]}" | grep -qx "$entry" || _hi_why entry _HI_COLOR_NAMES || return 1
    done
  done
  _hi_packages_palette || _hi_why
}

# one slot per group in file order, slot 0 the rows above the first header;
# each group's state from _hi_group_on, its tier from _hi_group_tier, and its
# row count
function test_collect_records_every_group() {
  [ "${_HI_PG_NAME[*]}" = "(no group) core useful deprecated extras platform" ] &&
    [ "${_HI_PG_ON[*]}" = "1 1 1 1 0 0" ] &&
    [ "${_HI_PG_TIER[*]}" = "1 3 2 3 1 0" ] &&
    [ "${_HI_PG_ROWS[*]}" = "1 3 2 4 2 2" ] || _hi_why _HI_PG_NAME _HI_PG_ON _HI_PG_TIER _HI_PG_ROWS
}

function test_collect_counts_every_listed_package() {
  [ "$_HI_PKG_LISTED" -eq 14 ] || _hi_why _HI_PKG_LISTED
}

# an absent `-` row and an installed `+` row print nothing, so of the 14 rows
# 2 are silent; the 4 in extras and platform would print but their groups are
# off; the other 8 are what the header shows
function test_collect_splits_shown_silent_and_off() {
  [ "$_HI_PKG_SHOWN" -eq 8 ] && [ "$_HI_PKG_SILENT" -eq 2 ] && [ "$_HI_PKG_OFF" -eq 4 ] || _hi_why _HI_PKG_SHOWN _HI_PKG_SILENT _HI_PKG_OFF
}

function test_collect_finds_an_installed_example() {
  [[ "${_HI_EX_OK[1]:-}" == *hialpha* ]] || _hi_why _HI_EX_OK
}

function test_collect_finds_a_missing_example() {
  [[ "${_HI_EX_NO[1]:-}" == *highost3* ]] || _hi_why _HI_EX_NO
}

# the rows above the first header are a group of their own, slot 0
function test_collect_keeps_the_ungrouped_rows_in_slot_zero() {
  [[ "${_HI_EX_OK[0]:-}" == *hitop* ]] && [ -z "${_HI_EX_NO[0]:-}" ] || _hi_why _HI_EX_OK _HI_EX_NO
}

# an installed `-` row is a warning, and a warning sits on the missing side:
# deprecated's only installed row is hiecho, and it is not an OK example
function test_collect_files_a_warning_as_missing() {
  [ -z "${_HI_EX_OK[3]:-}" ] &&
    [[ "${_HI_EX_NO[3]:-}" == *hiecho*"$YELLOW$_HI_MARK_WARN$NC" ]] || _hi_why _HI_EX_OK _HI_EX_NO _HI_MARK_WARN
}

# the rows that print nothing can be no one's example
function test_collect_skips_the_silent_rows() {
  local g
  for g in "${!_HI_PG_NAME[@]}"; do
    [[ "${_HI_EX_OK[g]:-}${_HI_EX_NO[g]:-}" != *highostgone* ]] &&
      [[ "${_HI_EX_OK[g]:-}${_HI_EX_NO[g]:-}" != *hifoxtrot* ]] || _hi_why _HI_EX_OK _HI_EX_NO || return 1
  done
}

# a group that is off still has its examples collected: the legend shows what
# it would print
function test_collect_keeps_an_off_groups_examples() {
  [[ "${_HI_EX_OK[4]:-}" == *hicharlie* ]] && [[ "${_HI_EX_NO[4]:-}" == *highost1* ]] || _hi_why _HI_EX_OK _HI_EX_NO
}

# the installed/missing split reads the mark, so it has to survive a package
# whose *name* contains the ASCII glyph ("x" in highost0): platform has one
# installed package and one absent, and each has to land in its own column
function test_collect_reads_the_mark_not_the_name() {
  [[ "${_HI_EX_OK[5]:-}" == *hidelta* ]] && [[ "${_HI_EX_NO[5]:-}" == *highost0* ]] || _hi_why _HI_EX_OK _HI_EX_NO
}

# The cell is nothing but color escapes and text, so its length is not its
# width; handing the table a measured length is what pushes a column past its
# own rule. core shows both examples: "| hialpha X " and "| highost3 X " -
# each the name plus check_line's constant 5 (the lead, the two spaces, the
# one-column mark).
function test_example_cell_reports_its_printed_width() {
  local text width
  IFS=$'\t' read -r text width <<<"$(_hi_example_cell 1)"
  [ "$width" -eq $((7 + 5 + 8 + 5)) ] &&
    [ "$width" -lt "${#text}" ] || _hi_why width text
}

function test_example_cell_marks_a_group_with_nothing_to_show() {
  local text width
  IFS=$'\t' read -r text width <<<"$(_hi_example_cell 9)"
  [ "$text" = "-" ] && [ "$width" -eq 1 ] || _hi_why text width
}

# One in-process render of the legend (the source hatch hands the function
# over without running it), shared like _HI_PACKAGES_OUT below and for the same
# SIGPIPE reason. In-process rather than through the child render so a failure
# points at the table code, not at whatever the child's environment did.
_HI_GROUPS_OUT=""

function test_groups_table_renders_all_columns() {
  _HI_GROUPS_OUT="$(_HI_PACKAGES_GROUPS="" _hi_print_groups_table)" || _hi_why || return 1
  local stripped
  stripped="$(_hi_strip_ansi "$_HI_GROUPS_OUT")"
  [[ "$stripped" == *"| GROUP "* && "$stripped" == *"| STATE "* ]] &&
    [[ "$stripped" == *"| INSTALLED "* && "$stripped" == *"| MISSING "* ]] &&
    [[ "$stripped" == *"| EXAMPLE "* ]] || _hi_why stripped
}

# file order, the order a reader finds the groups in
function test_groups_table_keeps_file_order() {
  local stripped
  stripped="$(_hi_strip_ansi "$_HI_GROUPS_OUT")"
  { _hi_before "$stripped" '^| (no group) ' '^| core ' &&
    _hi_before "$stripped" '^| core ' '^| deprecated ' &&
    _hi_before "$stripped" '^| deprecated ' '^| platform '; } || _hi_why stripped
}

# STATE is whether $_HI_PACKAGES_GROUPS runs the group
function test_groups_table_says_on_and_off() {
  local stripped
  stripped="$(_hi_strip_ansi "$_HI_GROUPS_OUT")"
  [[ "$(printf '%s\n' "$stripped" | grep '^| core ')" == *"| on "* ]] &&
    [[ "$(printf '%s\n' "$stripped" | grep '^| extras ')" == *"| off "* ]] || _hi_why stripped
}

# the INSTALLED/MISSING cells name the colors of the group's tier: core is
# tier 3, the shipped ramp's brgreen/brred, and platform tier 0, cyan/blue
function test_groups_table_names_the_ramp_colors() {
  local stripped row
  stripped="$(_hi_strip_ansi "$_HI_GROUPS_OUT")"
  row="$(printf '%s\n' "$stripped" | grep '^| core ')"
  [[ "$row" == *brgreen* && "$row" == *brred* ]] || _hi_why row || return 1
  row="$(printf '%s\n' "$stripped" | grep '^| platform ')"
  [[ "$row" == *"| cyan "* && "$row" == *"| blue "* ]] || _hi_why row
}

# the EXAMPLE column shows the fixture's own rows, an off group's included
function test_groups_table_shows_the_real_examples() {
  local stripped
  stripped="$(_hi_strip_ansi "$_HI_GROUPS_OUT")"
  [[ "$(printf '%s\n' "$stripped" | grep '^| core ')" == *hialpha*highost3* ]] &&
    [[ "$(printf '%s\n' "$stripped" | grep '^| extras ')" == *hicharlie*highost1* ]] || _hi_why stripped
}

# the "(no group)" row is there only when the file has rows above its first
# header
function test_groups_table_drops_an_empty_no_group_row() {
  local out
  out="$(
    _HI_PG_ROWS[0]=0
    _hi_print_groups_table
  )" || _hi_why || return 1
  [[ "$(_hi_strip_ansi "$out")" != *"(no group)"* && "$out" == *core* ]] || _hi_why out
}

# the two lines under the table: the tally, and the note naming the setting
# that leaves groups off - the same numbers the child render asserts, proved
# here to come from the table code itself
function test_groups_table_counts_below_the_table() {
  [[ "$_HI_GROUPS_OUT" == *"14 listed, 8 shown, 2 silent by their table"* ]] &&
    [[ "$_HI_GROUPS_OUT" == *"4 more in groups \$_HI_PACKAGES_GROUPS leaves off (core useful deprecated run)"* ]] || _hi_why _HI_GROUPS_OUT _HI_PACKAGES_GROUPS
}

# nothing off, nothing to explain
function test_groups_table_drops_the_off_note_at_zero() {
  local out
  out="$(_HI_PKG_OFF=0 _hi_print_groups_table)" || _hi_why || return 1
  [[ "$out" != *"leaves off"* && "$out" == *"14 listed"* ]] || _hi_why out
}

# a file of the user's own says, under the table, which of the tree's groups
# it lacks and which rows hold a name led by a marker; the tree's own says
# nothing
function test_packages_drift_names_groups_and_stray_markers() {
  local out want
  _HI_PACKAGES="$_HI_ROOT/config/packages" _hi_package_groups want
  want="${want#core }"
  printf '[core]\nhialpha = []\nhibravo = ["-hiecho", "+hidelta"]\n[mine.required]\nhitop = []\n' >"$_HI_WORKDIR/packages.drift"
  out="$(_HI_PACKAGES="$_HI_WORKDIR/packages.drift" _hi_print_packages_drift)" || _hi_why || return 1
  [[ "$out" == *"never checked: ${want// /, } ("* ]] || _hi_because "groups: $out" || return 1
  [[ "$out" == *"the row hibravo,-hiecho,+hidelta never matches: a - or + leading a name"* ]] ||
    _hi_because "marker: $out" || return 1
  out="$(_HI_PACKAGES="$_HI_ROOT/config/packages" _hi_print_packages_drift)" || _hi_why || return 1
  [ -z "$out" ] || _hi_because "the tree's own file: $out"
}

function test_marks_table_explains_every_mark() {
  local out
  out="$(_hi_strip_ansi "$(_hi_print_marks_table)")" || _hi_why || return 1
  [[ "$out" == *"| MARK "* && "$out" == *"| MEANS "* ]] &&
    [[ "$out" == *"installed, under the first name the row lists"* ]] &&
    [[ "$out" == *"installed, but via one of the alternatives after it"* ]] &&
    [[ "$out" == *"not installed - no name on the row resolved"* ]] &&
    [[ "$out" == *"installed, under .unwanted: a package you don't want"* ]] || _hi_why out
}

# each glyph is painted in the color the header paints it - the raw render has
# to carry the resolved escape directly ahead of the mark
function test_marks_table_paints_each_glyph() {
  local out
  out="$(_hi_print_marks_table)" || _hi_why || return 1
  { _hi_has_rendered "$out" "$GREEN$_HI_MARK_OK" && _hi_has_rendered "$out" "$RED$_HI_MARK_NO" &&
    _hi_has_rendered "$out" "$YELLOW$_HI_MARK_ALT" && _hi_has_rendered "$out" "$YELLOW$_HI_MARK_WARN"; } || _hi_why out _HI_MARK_OK _HI_MARK_NO _HI_MARK_ALT
}

function test_marks_table_is_rectangular() {
  _hi_table_is_rectangular "$(_hi_print_marks_table)" || _hi_why
}

# the third axis, the table a row sits in, is two lines under the marks: both
# kinds and the default, which names none
function test_marks_table_explains_the_markers() {
  local out
  out="$(_hi_strip_ansi "$(_hi_print_marks_table)")" || _hi_why || return 1
  [[ "$out" == *"a row under [group.unwanted] speaks only when installed, one under"* ]] &&
    [[ "$out" == *"only when missing; one under [group] both ways"* ]] || _hi_why out
}

# ...and the same table under the glyph set the rest of this suite pins away:
# real corners and junctions, and still rectangular, since a column measured in
# bytes rather than columns is exactly what a three-byte edge would expose
# (GLOSSARY: HI.12)
function test_marks_table_renders_the_glyph_set() {
  local out
  out="$(_HI_ASCII=0 bash -c '
    source "$_HI_HOME/say-hi/scripts/preview.sh"
    _hi_print_marks_table')" || _hi_why || return 1
  { [[ "$out" == *"┌─"* && "$out" == *"├─"* && "$out" == *"└─"* && "$out" == *"│ MARK "* ]] &&
    _hi_table_is_rectangular "$out"; } || _hi_why out
}

# The real script, in this tree, reading the exported fixture: a child
# re-sources paths.sh, which re-derives $_HI_PACKAGES from $_HI_CONFIG_DIR
# and finds the overlay's packages file built below. The real file rather than
# a scratch copy so that what these cases
# exercise counts in the coverage sweep, which only sees files under the
# checkout; $HOME is pointed at the workdir so no overlay of the user's can
# win the automatic lookup. The ordinary path - the file the *tree* carries,
# nothing exported - is pinned once, by test_preview_reads_the_trees_own_file
# on a scratch tree below.
function _hi_render_packages() {
  PATH="$(_hi_pkg_path)" HOME="$_HI_WORKDIR/tree" \
  _HI_CONFIG_DIR="$_HI_WORKDIR/cfg" \
    "$_HI_ROOT/scripts/preview.sh" packages 2>&1
}

# the help path: same PATH as the render, plus the one argument
function _hi_render_packages_help() {
  PATH="$(_hi_pkg_path)" HOME="$_HI_WORKDIR/tree" \
  _HI_CONFIG_DIR="$_HI_WORKDIR/cfg" \
    "$_HI_ROOT/scripts/preview.sh" packages "$1" 2>&1
}

# the ordinary path: nothing exported, the tree's own config/packages is
# the roster - a scratch tree, because this checkout's real files are not the
# fixture
function test_preview_reads_the_trees_own_file() {
  local out
  out="$(PATH="$(_hi_pkg_path)" HOME="$_HI_WORKDIR/tree" _HI_HOME="$_HI_WORKDIR/tree" \
  _HI_CONFIG_DIR="$_HI_WORKDIR/nocfg" \
    "$_HI_WORKDIR/tree/say-hi/scripts/preview.sh" packages 2>&1)" || _hi_why || return 1
  [[ "$out" == *hialpha* ]] && [[ "$out" == *'14 listed'* ]] || _hi_why out
}

# --help exits 0 before any table renders: usage text, the files it reads, and
# nothing of the legend itself
function test_help_prints_usage_and_stops() {
  local out
  out="$(_hi_render_packages_help --help)" || _hi_why || return 1
  [[ "$out" == *"Usage: preview.sh packages"* ]] &&
    [[ "$out" == *"Takes no arguments"* ]] &&
    [[ "$out" == *"\$_HI_PACKAGES_GROUPS"* ]] &&
    [[ "$out" != *"| GROUP"* ]] || _hi_why out _HI_PACKAGES_GROUPS
}

# anything that is not -h/--help is an error: the flag takes no arguments,
# and a stray one must not be ignored
function test_packages_stray_argument_is_refused() {
  local out rc=0
  out="$(_hi_render_packages_help nonsense)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"takes no arguments"* && "$out" != *"| GROUP"* ]] || _hi_why rc out
}

# One render (the slowest thing this suite does) shared by the cases below;
# each reads it from a variable rather than piping into grep, because under
# `set -o pipefail` an early-exiting `grep -q` SIGPIPEs the script and a
# negated case then passes no matter what the table said.
_HI_PACKAGES_OUT=""

function test_preview_renders_without_error() {
  _HI_PACKAGES_OUT="$(_hi_render_packages)" || _hi_why || return 1
  [[ "$_HI_PACKAGES_OUT" == *"| GROUP "* && "$_HI_PACKAGES_OUT" == *MARK* ]] || _hi_why _HI_PACKAGES_OUT
}

# the eyeball pass _HI_PACKAGES_PALETTE leans on: the legend has to say which
# ramp is on screen, not just render one - the same three shapes the scheme
# line prints
function test_preview_names_the_active_palette() {
  local out
  [[ "$_HI_PACKAGES_OUT" == *"palette: default"* && "$_HI_PACKAGES_OUT" == *"scheme: default"* ]] || _hi_why _HI_PACKAGES_OUT || return 1
  out="$(_HI_PACKAGES_PALETTE="$_HI_TEST_RAMP" _hi_render_packages)" || _hi_why || return 1
  [[ "$out" == *"palette: custom"* ]] || _hi_why out || return 1
  out="$(_HI_PACKAGES_PALETTE=mono _hi_render_packages)" || _hi_why || return 1
  [[ "$out" == *"palette: mono (ignored - not eight color names)"* ]] || _hi_why out
}

# a scheme of the user's own is named by its shape, and a 48-word one paints
# the legend from its second bank - which the reverse map still names, since
# the name is the 16-color half (HI.50)
function test_preview_names_a_custom_scheme_and_its_bank() {
  local out row
  out="$(_HI_COLOR_SCHEME="$_HI_TEST_L48" _HI_TRUECOLOR=1 _hi_render_packages)" || _hi_why || return 1
  [[ "$out" == *"scheme: custom (48)"* ]] || _hi_why out || return 1
  row="$(printf '%s\n' "$out" | grep '^| core ')"
  # bank 2's brgreen (23d18b) and brred (f14c4c), named as such
  [[ "$row" == *";38;2;35;209;139m"*brgreen* && "$row" == *";38;2;241;76;76m"*brred* ]] || _hi_why row || return 1
  out="$(_HI_COLOR_SCHEME="not a scheme" _HI_TRUECOLOR=1 _hi_render_packages)" || _hi_why || return 1
  [[ "$out" == *"scheme: not a scheme (ignored - not a scheme)"* ]] || _hi_why out
}

function test_preview_names_every_group() {
  local g stripped
  stripped="$(_hi_strip_ansi "$_HI_PACKAGES_OUT")"
  for g in core useful deprecated extras platform; do
    printf '%s\n' "$stripped" | grep -q "^| $g  *| " || _hi_why stripped g || return 1
  done
}

# the lines under the marks are the only place the three tables are
# explained, so the render has to carry them
function test_preview_explains_the_markers() {
  printf '%s\n' "$_HI_PACKAGES_OUT" | grep -qF 'a row under [group.unwanted] speaks only when installed' || _hi_why _HI_PACKAGES_OUT
}

function test_preview_counts_what_it_read() {
  { printf '%s\n' "$_HI_PACKAGES_OUT" | grep -q '14 listed, 8 shown, 2 silent by their table' &&
    printf '%s\n' "$_HI_PACKAGES_OUT" | grep -q '4 more in groups'; } || _hi_why _HI_PACKAGES_OUT
}

# the check itself is the last thing the preview prints, so a package the
# header would show has to appear below the tables as well as inside them -
# and one from a group that is off, only inside them
function test_preview_ends_with_the_real_check() {
  local tail
  tail="$(printf '%s\n' "$_HI_PACKAGES_OUT" | tail -3)"
  [[ "$tail" == *hialpha* && "$tail" != *hicharlie* ]] || _hi_why tail
}

# the check follows $_HI_PACKAGES_GROUPS: naming extras alone turns core off
# in the legend and in the check, extras on, and the rows above the first
# header still print
function test_preview_follows_the_groups_setting() {
  local out stripped tail
  out="$(_HI_PACKAGES_GROUPS=extras _hi_render_packages)" || _hi_why || return 1
  stripped="$(_hi_strip_ansi "$out")"
  [[ "$(printf '%s\n' "$stripped" | grep '^| core ')" == *"| off "* ]] &&
    [[ "$(printf '%s\n' "$stripped" | grep '^| extras ')" == *"| on "* ]] &&
    [[ "$out" == *"(extras run)"* ]] || _hi_why stripped out || return 1
  tail="$(printf '%s\n' "$out" | tail -3)"
  [[ "$tail" == *hicharlie* && "$tail" == *hitop* && "$tail" != *hialpha* ]] || _hi_why tail
}

# Every section of the preview reads the packages file, so none at all is
# said out loud and stops the run - the bare redirect it replaces fails with a
# path and no hint of which file the tool wanted.
# $_HI_CONFIG_DIR points the child at an empty overlay, so the tree's
# config/packages is the only candidate - and the tree has none.
function test_preview_reports_no_packages_file() {
  local home out
  home="$(_hi_scratch_tree nopackages common config link:scripts)"
  rm -f "$home/say-hi/config/packages"
  out="$(PATH="$(_hi_pkg_path)" HOME="$home" _HI_HOME="$home" \
  _HI_CONFIG_DIR="$_HI_WORKDIR/nocfg" \
    "$home/say-hi/scripts/preview.sh" packages 2>&1)" && return 1
  [[ "$out" == *"No packages file at $home/say-hi/config/packages"* ]] || _hi_why out home
}

# ...and an exported $_HI_PACKAGES is not a way in: the script's paths.sh
# re-derives the path from $_HI_CONFIG_DIR and the tree, so the export is
# ignored and the tree's roster comes out. The overlay is the one way to
# point the check at a file of your own.
function test_preview_ignores_an_exported_packages() {
  local home decoy out
  home="$(_hi_scratch_tree exportedpkgs common config link:scripts)"
  cp "$_HI_WORKDIR/packages" "$home/say-hi/config/packages"
  decoy="$_HI_WORKDIR/exported-packages"
  printf 'hionlyone\n' >"$decoy"
  out="$(PATH="$(_hi_pkg_path)" HOME="$home" _HI_HOME="$home" \
  _HI_CONFIG_DIR="$_HI_WORKDIR/nocfg" _HI_PACKAGES="$decoy" \
    "$home/say-hi/scripts/preview.sh" packages 2>&1)" || _hi_why home decoy || return 1
  [[ "$out" == *hibravo* ]] && [[ "$out" != *hionlyone* ]] || _hi_why out
}

function run_preview_packages_tests() {
  _hi_preview_begin

  _hi_h1 "Testing scripts/preview.sh (packages)"

  _hi_h2 "Testing: packages - naming the header's colors"
  _hi_check "Names every color the header uses" test_legend_names_every_header_color

  _hi_h2 "Testing: packages - examples, via the header's check_line"
  _hi_check "Records every group, state, tier and row count" test_collect_records_every_group
  _hi_check "Counts every listed package" test_collect_counts_every_listed_package
  _hi_check "Splits shown, silent and off" test_collect_splits_shown_silent_and_off
  _hi_check "Finds an installed example" test_collect_finds_an_installed_example
  _hi_check "Finds a missing example" test_collect_finds_a_missing_example
  _hi_check "Rows above the first group are slot 0" test_collect_keeps_the_ungrouped_rows_in_slot_zero
  _hi_check "Files a warning on the missing side" test_collect_files_a_warning_as_missing
  _hi_check "Skips the silent rows" test_collect_skips_the_silent_rows
  _hi_check "Keeps an off group's examples" test_collect_keeps_an_off_groups_examples
  _hi_check "Reads the mark, not the name" test_collect_reads_the_mark_not_the_name

  _hi_h2 "Testing: packages - the example cell"
  _hi_check "Reports its printed width" test_example_cell_reports_its_printed_width
  _hi_check "Marks a group with nothing to show" test_example_cell_marks_a_group_with_nothing_to_show

  _hi_h2 "Testing: packages - the tables, rendered in-process"
  _hi_check "Legend renders all five columns" test_groups_table_renders_all_columns
  _hi_check "Legend keeps file order" test_groups_table_keeps_file_order
  _hi_check "Legend says on and off" test_groups_table_says_on_and_off
  _hi_check "Legend names the tier's colors" test_groups_table_names_the_ramp_colors
  _hi_check "Legend shows the real examples" test_groups_table_shows_the_real_examples
  _hi_check "No (no group) row without ungrouped rows" test_groups_table_drops_an_empty_no_group_row
  _hi_check "Legend counts below the table" test_groups_table_counts_below_the_table
  _hi_check "Off note vanishes with nothing off" test_groups_table_drops_the_off_note_at_zero
  _hi_check "A file of your own names what it lacks" test_packages_drift_names_groups_and_stray_markers
  _hi_check "Legend is rectangular" _hi_table_is_rectangular "$_HI_GROUPS_OUT"
  _hi_check "Marks table explains every mark" test_marks_table_explains_every_mark
  _hi_check "Marks table paints each glyph" test_marks_table_paints_each_glyph
  _hi_check "Marks table is rectangular" test_marks_table_is_rectangular
  _hi_check "Marks table explains the tables" test_marks_table_explains_the_markers
  _hi_check "Marks table draws the glyph set's corners" test_marks_table_renders_the_glyph_set

  _hi_h2 "Testing: packages - the rendered preview"
  _hi_check "Help prints usage and stops" test_help_prints_usage_and_stops
  _hi_check "A stray argument is refused" test_packages_stray_argument_is_refused
  _hi_check_eq "-h matches --help" "$(_hi_render_packages_help --help)" _hi_render_packages_help -h
  _hi_check "Renders without error" test_preview_renders_without_error
  _hi_check "Names the active palette" test_preview_names_the_active_palette
  _hi_check "Names a custom scheme, and its second bank" test_preview_names_a_custom_scheme_and_its_bank
  _hi_check "Names every group" test_preview_names_every_group
  _hi_check "Explains the tables" test_preview_explains_the_markers
  _hi_check "Counts what it read" test_preview_counts_what_it_read
  _hi_check "Ends with the real check" test_preview_ends_with_the_real_check
  _hi_check "Every line of a table is the same width" _hi_table_is_rectangular "$_HI_PACKAGES_OUT"
  _hi_check "Follows \$_HI_PACKAGES_GROUPS" test_preview_follows_the_groups_setting
  _hi_check "Reports no packages file at all" test_preview_reports_no_packages_file
  _hi_check "An exported \$_HI_PACKAGES is ignored" test_preview_ignores_an_exported_packages
  _hi_check "Reads the tree's own file when nothing is exported" test_preview_reads_the_trees_own_file

  _hi_suite_end "preview.sh (packages)"
}

run_preview_packages_tests
