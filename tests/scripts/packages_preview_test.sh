#!/usr/bin/env bash
# Unit tests for scripts/packages_preview.sh - the `hi --packages-preview` legend.
#
# The preview's whole claim is that it shows what the *header* will do, so what
# matters is that it reads its facts from header.sh rather than from a copy:
# the priority meanings out of the comment block, the colors out of _HI_YES and
# _HI_NO, and every example row out of check_line itself. The cases below pin
# those seams, plus the table geometry, against a fixture packages file and a
# PATH holding exactly the packages the fixture calls installed.
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"
# its own hatch stops it before it renders anything; sourcing hands over the
# helpers, and (through it) header.sh's check_line
# shellcheck source=../../scripts/packages_preview.sh
source "$_HI_PACKAGES_PREVIEW"

# Six packages that exist and seven that do not: one installed/missing pair
# per priority 0-3, a `-` line each way and a `+` line each way (the two mode
# characters), plus one line whose *second* name is the installed one (the ~
# mark). Names nothing else answers to: a shell builtin or a real tool of the
# same name would make "installed" an accident of the machine rather than
# something set up here.
function _hi_write_fixtures() {
  _hi_fake_path pkgbin hialpha hibravo hicharlie hidelta hiecho hifoxtrot >/dev/null

  cat >"$_HI_WORKDIR/packages" <<'EOF'
# a comment, and a blank line, both of which the header skips
hialpha:3
highost3:3
hibravo:2
highost2:2
hicharlie:1
highost1:1
hidelta:0
highost0:0
-hiecho:3
-highostcore:3
+hifoxtrot:0
+highostplus:0
highostalt:3,hibravo:3
EOF
  export _HI_PACKAGES="$_HI_WORKDIR/packages"
}

# the fixture's packages, and the coreutils the script itself shells out to
function _hi_pkg_path() {
  printf '%s:%s' "$(_hi_fake_path pkgbin)" "$(_hi_real_path pkgtools bash awk sort sed cat)"
}

# collect once - it is the same work for every case that reads the results
function _hi_collect_once() {
  local saved="$PATH"
  PATH="$(_hi_pkg_path)"
  _hi_collect_examples
  PATH="$saved"
}

# The pin that keeps the legend honest: header.sh's comment block is the only
# description of the priorities there is, so every priority its color tables
# define has to come back with a meaning. A renumbered or reworded block fails
# here rather than rendering a table with a blank column.
function test_every_priority_has_a_meaning() {
  local p meaning i=0
  for i in "${!_HI_YES[@]}"; do
    meaning="$(_hi_priority_meanings | awk -v p="$i" -F'\t' '$1 == p { print $2 }')"
    [ -n "$meaning" ] || return 1
  done
  [ "${#_HI_YES[@]}" -eq "${#_HI_NO[@]}" ]
}

function test_meanings_are_one_per_priority() {
  [ "$(_hi_priority_meanings | wc -l)" -eq "${#_HI_YES[@]}" ]
}

# the parenthetical examples in header.sh's comment are dropped - the EXAMPLE
# column shows real ones, from the file the header will actually read
function test_meanings_drop_the_parenthetical() {
  ! _hi_priority_meanings | grep -q '('
}

function test_meanings_name_the_top_priority() {
  _hi_priority_meanings | grep -q "^3$(printf '\t')favorites and core$"
}

# an unrelated "# 2 ..." comment earlier in header.sh must not join the block
function test_meanings_take_only_the_block_above_the_table() {
  [ "$(_hi_priority_meanings | awk -F'\t' '$1 == 2' | wc -l)" -eq 1 ]
}

function test_color_name_of_names_a_palette_entry() {
  [ "$(_hi_color_name_of "$BRGREEN")" = brgreen ] &&
    [ "$(_hi_color_name_of "$YELLOW")" = yellow ]
}

# every escape in the header's two tables has to name something, or the legend
# prints a color the user cannot look up in settings/colors - checked for
# every named palette, not just whichever one is active when the suite runs,
# since _HI_YES/_HI_NO are _hi_packages_palette's output and this suite never
# sets $_HI_PACKAGES_PALETTE itself
function test_color_name_of_names_every_header_color() {
  local name escape
  for name in cool warm mono; do
    _HI_PACKAGES_PALETTE="$name" _hi_packages_palette
    for escape in "${_HI_YES[@]}" "${_HI_NO[@]}"; do
      [ "$(_hi_color_name_of "$escape")" = plain ] && return 1
    done
  done
  # back to whatever the suite's own fixtures assume elsewhere
  unset _HI_PACKAGES_PALETTE
  _hi_packages_palette
  return 0
}

function test_collect_counts_every_listed_package() {
  [ "$_HI_PKG_LISTED" -eq 13 ]
}

# the installed `-` line and the missing `+` line are the two rows the modes
# suppress, so of the 13 lines the header prints 11
function test_collect_counts_only_what_the_header_shows() {
  [ "$_HI_PKG_SHOWN" -eq 11 ]
}

function test_collect_finds_an_installed_example() {
  [[ "${_HI_EX_OK[3]:-}" == *hialpha* ]]
}

function test_collect_finds_a_missing_example() {
  [[ "${_HI_EX_NO[3]:-}" == *highost3* ]]
}

# an installed `-` line and a missing `+` line show nothing, so neither can be
# anyone's example - the mode rows in the fixture must not surface anywhere
function test_collect_skips_a_mode_suppressed_example() {
  [[ "${_HI_EX_OK[3]:-}" != *hiecho* ]] && [[ "${_HI_EX_NO[0]:-}" != *highostplus* ]]
}

# The nudge, which is what the table was rebuilt for: a favorite you have not
# installed is collected and shown rather than silently dropped.
function test_collect_keeps_a_missing_example_as_a_nudge() {
  [[ "${_HI_EX_NO[3]:-}" == *highost3* ]] && [[ "${_HI_EX_OK[3]:-}" == *hialpha* ]]
}

# the installed/missing split reads the mark, so it has to survive a package
# whose *name* contains the ASCII glyph ("x" in highost0) and the alternatives
# mark, which is neither of the two
# Both halves of a tier come back, told apart by the mark rather than by the
# name - tier 0 has one installed package and one absent, and each has to land
# in its own column.
function test_collect_reads_the_mark_not_the_name() {
  [[ "${_HI_EX_OK[0]:-}" == *hidelta* ]] && [[ "${_HI_EX_NO[0]:-}" == *highost0* ]]
}

# The cell is nothing but color escapes and text, so its length is not its
# width; handing the table a measured length is what pushes a column past its
# own rule. Priority 3 shows both examples: "| hialpha X " and "| highost3 X ".
function test_example_cell_reports_its_printed_width() {
  local text width
  IFS=$'\t' read -r text width <<<"$(_hi_example_cell 3)"
  [ "$width" -eq $((7 + 4 + _HI_MARK_OK_W + 8 + 4 + _HI_MARK_NO_W)) ] &&
    [ "$width" -lt "${#text}" ]
}

function test_example_cell_marks_a_priority_with_nothing_to_show() {
  local text width
  IFS=$'\t' read -r text width <<<"$(_hi_example_cell 9)"
  [ "$text" = "-" ] && [ "$width" -eq 1 ]
}

# The other reason a cell shows no example, and the one every stock config now
# hits: the floor defaults to 2, so priorities 0-1 have examples collected but
# never printed, and the cell says why instead of showing one the header will
# not.
function test_example_cell_marks_a_priority_below_the_floor() {
  local text width
  IFS=$'\t' read -r text width <<<"$(_hi_example_cell 0)"
  [ "$text" = "below floor" ] && [ "$width" -eq 11 ]
}

# Running the real script through a scratch tree rather than through the
# exported fixture above, and still deliberately: $_HI_PACKAGES does now reach a
# child (paths.sh keeps a value it did not derive - the per-file override), and
# the case below pins that, but what these cases want proved is the ordinary
# path, where the file is the one the *tree* carries.
function _hi_render_preview() {
  PATH="$(_hi_pkg_path)" HOME="$_HI_WORKDIR/tree" _HI_HOME="$_HI_WORKDIR/tree" \
    "$_HI_WORKDIR/tree/say-hi/scripts/packages_preview.sh" 2>&1
}

function _hi_write_preview_tree() {
  local home
  home="$(_hi_scratch_tree tree common settings scripts)"
  cp "$_HI_WORKDIR/packages" "$home/say-hi/settings/packages"
}

# One render (the slowest thing this suite does) shared by the cases below;
# each reads it from a variable rather than piping into grep, because under
# `set -o pipefail` an early-exiting `grep -q` SIGPIPEs the script and a
# negated case then passes no matter what the table said.
_HI_PREVIEW_OUT=""

function test_preview_renders_without_error() {
  _HI_PREVIEW_OUT="$(_hi_render_preview)" || return 1
  [[ "$_HI_PREVIEW_OUT" == *PRIORITY* && "$_HI_PREVIEW_OUT" == *MARK* ]]
}

# the eyeball pass _HI_PACKAGES_PALETTE's roadmap entry leans on: the legend
# has to say which named ramp is on screen, not just render one
function test_preview_names_the_active_palette() {
  [[ "$_HI_PREVIEW_OUT" == *"palette: cool"* ]]
}

function test_preview_names_every_priority() {
  local i stripped
  stripped="$(_hi_strip_ansi "$_HI_PREVIEW_OUT")"
  for i in "${!_HI_YES[@]}"; do
    printf '%s\n' "$stripped" | grep -q "^| $i  *| " || return 1
  done
}

# the MODE table is the only place the two mode characters are explained, so
# the render has to carry it and the row that says what `-` does
function test_preview_explains_the_modes() {
  [[ "$_HI_PREVIEW_OUT" == *MODE* ]] &&
    printf '%s\n' "$_HI_PREVIEW_OUT" | grep -q 'speaks only when the whole line is missing'
}

function test_preview_counts_what_it_read() {
  # 6 shown: the default floor of 2 keeps the mode-visible rows of rank 2-3;
  # the three rank-0 and two rank-1 rows sit below it
  printf '%s\n' "$_HI_PREVIEW_OUT" | grep -q '13 listed, 6 shown, 2 hidden'
}

# the check itself is the last thing the preview prints, so a package the
# header would show has to appear below the tables as well as inside them
function test_preview_ends_with_the_real_check() {
  [[ "$(printf '%s\n' "$_HI_PREVIEW_OUT" | tail -3)" == *hialpha* ]]
}

# Every section of the preview reads the packages file, so a missing one is
# said out loud and stops the run - the bare redirect it replaces fails with a
# path and no hint of which file the tool wanted.
# $_HI_PACKAGES is cleared for the child, and has to be: the suite exports its
# own fixture into this shell, and an exported value is an *override* that
# paths.sh keeps rather than something the next source overwrites. Leaving it
# set would point the script at a file that exists and prove nothing.
function test_preview_reports_a_missing_packages_file() {
  local home out
  home="$(_hi_scratch_tree nopackages common settings scripts)"
  rm -f "$home/say-hi/settings/packages"
  out="$(PATH="$(_hi_pkg_path)" HOME="$home" _HI_HOME="$home" \
  _HI_PACKAGES="" _HI_PACKAGES_AUTO="" \
    "$home/say-hi/scripts/packages_preview.sh" 2>&1)" && return 1
  [[ "$out" == *"No packages file"* ]]
}

# ...and the other half of the same fact, which is the feature rather than its
# side effect: an exported $_HI_PACKAGES points the check at one file without
# moving the rest of the overlay, and survives the paths.sh the script sources
# on its way in. The tree here has a perfectly good packages file; the export
# names a different one, and the roster that comes out has to be that one's.
function test_preview_reads_an_exported_packages_file() {
  local home out
  home="$(_hi_scratch_tree exportedpkgs common settings scripts)"
  printf 'hionlyone:3
' >"$_HI_WORKDIR/exported-packages"
  out="$(PATH="$(_hi_pkg_path)" HOME="$home" _HI_HOME="$home" \
  _HI_PACKAGES="$_HI_WORKDIR/exported-packages" \
    "$home/say-hi/scripts/packages_preview.sh" 2>&1)" || return 1
  [[ "$out" == *hionlyone* ]] && [[ "$out" != *hibravo* ]]
}

# The same invariant color_preview_test.sh asserts, through literally the same
# code: test_lib.sh's _hi_table_is_rectangular. Shared so the two cannot
# segment tables differently and quietly check different things.
function test_tables_are_rectangular() {
  _hi_table_is_rectangular "$_HI_PREVIEW_OUT"
}

function run_packages_preview_tests() {
  _hi_workdir packagespreviewtest
  _hi_write_fixtures
  _hi_write_preview_tree
  _hi_collect_once

  _hi_h1 "Testing scripts/packages_preview.sh"

  _hi_suite_begin

  _hi_h2 "Testing: the priority meanings"
  _hi_check "Every priority has a meaning" test_every_priority_has_a_meaning
  _hi_check "One meaning per priority" test_meanings_are_one_per_priority
  _hi_check "Parenthetical examples dropped" test_meanings_drop_the_parenthetical
  _hi_check "Names the top priority" test_meanings_name_the_top_priority
  _hi_check "Reads only the block above the tables" test_meanings_take_only_the_block_above_the_table

  _hi_h2 "Testing: naming the header's colors"
  _hi_check "Names a palette entry" test_color_name_of_names_a_palette_entry
  _hi_check "Names every color the header uses" test_color_name_of_names_every_header_color
  # $NC is not a palette color, and neither is anything under $NO_COLOR
  _hi_check_eq "Calls a reset plain" plain _hi_color_name_of "$NC"

  _hi_h2 "Testing: examples, via the header's check_line"
  _hi_check "Counts every listed package" test_collect_counts_every_listed_package
  _hi_check "Counts only what the header shows" test_collect_counts_only_what_the_header_shows
  _hi_check "Finds an installed example" test_collect_finds_an_installed_example
  _hi_check "Finds a missing example" test_collect_finds_a_missing_example
  _hi_check "Skips a mode-suppressed example" test_collect_skips_a_mode_suppressed_example
  _hi_check "Keeps a missing example as a nudge" test_collect_keeps_a_missing_example_as_a_nudge
  _hi_check "Reads the mark, not the name" test_collect_reads_the_mark_not_the_name

  _hi_h2 "Testing: the example cell"
  _hi_check "Reports its printed width" test_example_cell_reports_its_printed_width
  _hi_check "Marks a priority with nothing to show" test_example_cell_marks_a_priority_with_nothing_to_show
  _hi_check "Marks a priority below the floor" test_example_cell_marks_a_priority_below_the_floor

  _hi_h2 "Testing: the rendered preview"
  _hi_check "Renders without error" test_preview_renders_without_error
  _hi_check "Names the active palette" test_preview_names_the_active_palette
  _hi_check "Names every priority" test_preview_names_every_priority
  _hi_check "Explains the mode characters" test_preview_explains_the_modes
  _hi_check "Counts what it read" test_preview_counts_what_it_read
  _hi_check "Ends with the real check" test_preview_ends_with_the_real_check
  _hi_check "Every line of a table is the same width" test_tables_are_rectangular
  _hi_check "Reports a missing packages file" test_preview_reports_a_missing_packages_file
  _hi_check "Reads an exported packages file" test_preview_reads_an_exported_packages_file

  _hi_suite_end "packages_preview.sh"
}

run_packages_preview_tests
