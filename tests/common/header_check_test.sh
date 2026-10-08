#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# common/header.sh's package check: check_line, the groups, full_check, and
# the palette it paints with.
# A part of header_test.sh, a suite of its own so the Windows shards split them.
# The preamble's source line is header_test.sh's - it sources the harness, and
# holds the helpers the parts share (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

_HI_HEADER_PART=check
# shellcheck source=./header_test.sh
source "${BASH_SOURCE[0]%/*}/header_test.sh"

_HI_FAKE_CMD=definitely-not-a-real-hi-test-command-xyz

# Does $1 contain the bytes of $2? A byte-exact `grep -F` under LC_ALL=C rather
# than `[[ $1 == *"$2"* ]]`, because two of the three marks are multibyte and
# bash's pattern engine consults the locale to decide what a character even is.
# The macOS runner failed exactly the two cases that looked for ✓ and ✗ while
# passing the one that looked for the ASCII ~, which is that difference and
# nothing else. Bytes are bytes in every locale.
#
# The needle always comes from header.sh's own $_HI_MARK_* rather than a second
# literal here, so this compares the shipped glyph against itself.
function _hi_contains() {
  printf '%s' "$1" | LC_ALL=C grep -qF -- "$2"
}

# _hi_contains with the mismatch printed, so a failure on a machine this suite
# cannot be run on interactively still says what it actually got.
function _hi_assert_contains() {
  _hi_contains "$1" "$2" && return 0
  _hi_cecho "   expected to find: $(printf '%s' "$2" | od -An -tx1 | tr -d ' \n')" "$RED"
  _hi_cecho "   in: $(printf '%s' "$1" | od -An -tx1 | tr -d ' \n')" "$RED"
  return 1
}

# The scaffold every check_line case shares: run one row (and optional tier)
# against a fresh row sink and assert how many records it left. check_line
# appends to the array it is named, and the single record - when there is
# one - lands in the caller's `row`, ready for content checks.
function _hi_one_visible_row() {
  local -a visible=()
  check_line visible "$@"
  [ "${#visible[@]}" -eq 1 ] || return 1
  row="${visible[0]}"
}

function _hi_no_visible_row() {
  local -a visible=()
  check_line visible "$@"
  [ "${#visible[@]}" -eq 0 ]
}

# _hi_row_is <rank> <color> <name> <mark> - $row is exactly the record
# check_line builds for these: rank, width (name + 5), then the painted cell.
# Compared whole and byte for byte, so a wrong tier, a wrong color, a leaked
# -/+ or the wrong alternative all fail here, in any locale.
function _hi_row_is() {
  local want="$1"$'\x1f'"$((${#3} + 5))"$'\x1f'"$2 $3 $4"
  [ "$row" = "$want" ] && return 0
  _hi_cecho "   want: $(printf '%s' "$want" | od -An -tx1 | tr -d ' \n')" "$RED"
  _hi_cecho "   got:  $(printf '%s' "$row" | od -An -tx1 | tr -d ' \n')" "$RED"
  return 1
}

# No marker: installed under the first name is a check in the tier's
# installed color, ranked at the tier
function test_check_line_installed_first_name_is_checked() {
  local row
  _hi_one_visible_row "$_HI_REAL_CMD" 3 || _hi_why _HI_REAL_CMD || return 1
  _hi_row_is 3 "${_HI_YES[3]}" "$_HI_REAL_CMD" "$GREEN$_HI_MARK_OK" || _hi_why _HI_YES _HI_REAL_CMD _HI_MARK_OK
}

# ...installed only as a later alternative: that alternative's name, with ~
function test_check_line_installed_alternative_is_tilded() {
  local row
  _hi_one_visible_row "$_HI_FAKE_CMD,$_HI_REAL_CMD" 2 || _hi_why _HI_FAKE_CMD _HI_REAL_CMD || return 1
  _hi_row_is 2 "${_HI_YES[2]}" "$_HI_REAL_CMD" "$YELLOW$_HI_MARK_ALT$NC" || _hi_why _HI_YES _HI_REAL_CMD _HI_MARK_ALT
}

# ...nothing installed: the first name, crossed, in the tier's missing color
function test_check_line_missing_shows_the_first_name_crossed() {
  local row
  _hi_one_visible_row "$_HI_FAKE_CMD,${_HI_FAKE_CMD}-alt" 0 || _hi_why _HI_FAKE_CMD || return 1
  _hi_row_is 0 "${_HI_NO[0]}" "$_HI_FAKE_CMD" "$RED$_HI_MARK_NO" || _hi_why _HI_NO _HI_FAKE_CMD _HI_MARK_NO
}

# ...and with no tier argument the row paints and ranks at tier 1
function test_check_line_tier_defaults_to_one() {
  local row
  _hi_one_visible_row "$_HI_FAKE_CMD" || _hi_why _HI_FAKE_CMD || return 1
  _hi_row_is 1 "${_HI_NO[1]}" "$_HI_FAKE_CMD" "$RED$_HI_MARK_NO" || _hi_why _HI_NO _HI_FAKE_CMD _HI_MARK_NO
}

# The first installed alternative wins, whatever follows it: the list is an
# order of preference, not a ranking to search
function test_check_line_first_installed_alternative_wins() {
  local row
  _hi_one_visible_row "$_HI_REAL_CMD,bash" 1 || _hi_why _HI_REAL_CMD || return 1
  _hi_row_is 1 "${_HI_YES[1]}" "$_HI_REAL_CMD" "$GREEN$_HI_MARK_OK" || _hi_why _HI_YES _HI_REAL_CMD _HI_MARK_OK
}

# `-` unwanted, installed: a warning at rank 4 in the loudest missing color,
# whatever the group's tier, with the marker stripped from the name
function test_check_line_unwanted_installed_warns() {
  local row
  _hi_one_visible_row "-$_HI_REAL_CMD" 0 || _hi_why _HI_REAL_CMD || return 1
  _hi_row_is 4 "${_HI_NO[3]}" "$_HI_REAL_CMD" "$YELLOW$_HI_MARK_WARN$NC" || _hi_why _HI_NO _HI_REAL_CMD _HI_MARK_WARN
}

# ...and an alternative counts: the warning names the one installed
function test_check_line_unwanted_alternative_installed_warns() {
  local row
  _hi_one_visible_row "-$_HI_FAKE_CMD,$_HI_REAL_CMD" 2 || _hi_why _HI_FAKE_CMD _HI_REAL_CMD || return 1
  _hi_row_is 4 "${_HI_NO[3]}" "$_HI_REAL_CMD" "$YELLOW$_HI_MARK_WARN$NC" || _hi_why _HI_NO _HI_REAL_CMD _HI_MARK_WARN
}

# `+` required, missing: an alarm at rank 4 in the loudest missing color,
# whatever the group's tier, with the marker stripped from the name
function test_check_line_required_missing_alarms() {
  local row
  _hi_one_visible_row "+$_HI_FAKE_CMD" 0 || _hi_why _HI_FAKE_CMD || return 1
  _hi_row_is 4 "${_HI_NO[3]}" "$_HI_FAKE_CMD" "$RED$_HI_MARK_NO" || _hi_why _HI_NO _HI_FAKE_CMD _HI_MARK_NO
}

function test_full_check_skips_comments_and_blanks() {
  (
    _HI_PACKAGES="$(_hi_pkg_one comments "# a comment\n$_HI_REAL_CMD = []\n")"
    full_check
  ) | grep -qF "$_HI_REAL_CMD" || _hi_why _HI_REAL_CMD
}

# the two rows with nothing to say - an absent `-` row, an installed `+` row -
# leave the check empty, not a bare line
function test_full_check_empty_when_everything_is_silent() {
  local out
  out="$(
    _HI_PACKAGES="$(_hi_pkg_one silent "[required]\n$_HI_REAL_CMD = []\n[unwanted]\n$_HI_FAKE_CMD = []\n")"
    full_check
  )"
  [ -z "$out" ] || _hi_why out
}

# _hi_group_tier: the named groups' tiers, and 1 for any other name
function test_group_tier_maps_names_to_tiers() {
  local spec t
  for spec in core=3 base=3 deprecated=3 useful=2 trivia=0 platform=0 \
    extras=1 mine=1 cores=1; do
    _hi_group_tier t "${spec%=*}"
    [ "$t" = "${spec#*=}" ] || _hi_why t spec || return 1
  done
}

# _hi_group_on: whole names out of a space- or comma-separated list, unset
# meaning the shipped default and `none` naming nothing
function test_group_on_reads_the_list() {
  (
    unset _HI_PACKAGES_GROUPS
    { _hi_group_on core && _hi_group_on useful && _hi_group_on deprecated; } || _hi_why || exit 1
    ! _hi_group_on extras || _hi_why || exit 1
    _HI_PACKAGES_GROUPS="alpha,beta gamma"
    { _hi_group_on alpha && _hi_group_on beta && _hi_group_on gamma; } || _hi_why || exit 1
    # a whole-word match: neither a prefix nor an extension of a listed name
    { ! _hi_group_on alp && ! _hi_group_on alphas; } || _hi_why || exit 1
    _HI_PACKAGES_GROUPS=none
    ! _hi_group_on core || _hi_why || exit 1
    # `none` is the setting's word, never a group of its own
    ! _hi_group_on none || _hi_why || exit 1
    _HI_PACKAGES_GROUPS="none core"
    ! _hi_group_on none
  ) || _hi_why
}

# _hi_package_groups: the tables in file order, a group once however many
# tables it has, a comment behind one read past, and a commented one skipped
function test_package_groups_lists_sections_in_file_order() {
  local got
  _HI_PACKAGES="$(_hi_pkg_one list-groups "top = []\n[required]\nneed = []\n[beta.unwanted]\nx = []\n#[gone]\n[alpha] # c\n[beta]\n[alpha.required]\n")" \
    _hi_package_groups got
  [ "$got" = "beta alpha" ] || _hi_why got
}

# a row is its key and its array, whatever pads or follows them: a quoted
# key, a comment behind the row, and the alternatives in the order given
function test_full_check_reads_a_toml_row() {
  local out
  out="$(
    _HI_PACKAGES="$(_hi_pkg_one toml-row "[alpha]\n  \"$_HI_FAKE_CMD\"   =   [ \"$_HI_FAKE_CMD-2\",\"$_HI_REAL_CMD\" ]  # a note\n$_HI_FAKE_CMD-3 = \"not an array\"\nbare words\n")"
    _HI_PACKAGES_GROUPS=alpha
    full_check
  )"
  _hi_contains "$out" " $_HI_REAL_CMD " && _hi_contains "$out" "$_HI_FAKE_CMD-3" || _hi_why out _HI_REAL_CMD _HI_FAKE_CMD || return 1
  case "$out" in *words* | *note*) _hi_why out || return 1 ;; esac
  return 0
}

# a group is its three tables, each saying what its rows are, and one switch
# turns all three off
function test_full_check_reads_a_group_by_its_tables() {
  local out body
  body="[alpha]\nls = []\n[alpha.required]\n$_HI_FAKE_CMD = []\n$_HI_REAL_CMD = []\n[alpha.unwanted]\ncat = []\n$_HI_FAKE_CMD-2 = []\n"
  out="$(
    _HI_PACKAGES="$(_hi_pkg_one tables "$body")"
    _HI_PACKAGES_GROUPS=alpha
    full_check
  )"
  _hi_contains "$out" " ls " && _hi_contains "$out" " cat " && _hi_contains "$out" " $_HI_FAKE_CMD " || _hi_why out _HI_FAKE_CMD || return 1
  case "$out" in *" $_HI_REAL_CMD "* | *"$_HI_FAKE_CMD-2"*) _hi_why out _HI_REAL_CMD _HI_FAKE_CMD || return 1 ;; esac
  out="$(
    _HI_PACKAGES="$_HI_WORKDIR/tables/packages"
    _HI_PACKAGES_GROUPS=none
    full_check
  )"
  [ -z "$out" ] || _hi_why out
}

# A group $_HI_PACKAGES_GROUPS leaves out prints nothing, however installed its
# rows are; the one it names prints. Both installed, so only the group
# separates them.
function test_full_check_runs_only_the_named_groups() {
  local out
  out="$(
    _HI_PACKAGES="$(_hi_pkg_one groups-one "[alpha]\n$_HI_REAL_CMD = []\n[beta]\nbash = []\n")"
    _HI_PACKAGES_GROUPS=alpha
    full_check
  )"
  _hi_contains "$out" " $_HI_REAL_CMD " || _hi_why out _HI_REAL_CMD || return 1
  case "$out" in *bash*) _hi_why out || return 1 ;; esac
  return 0
}

# ...a comma-separated list runs each group it names
function test_full_check_reads_a_comma_separated_list() {
  local out
  out="$(
    _HI_PACKAGES="$(_hi_pkg_one groups-comma "[alpha]\n$_HI_REAL_CMD = []\n[beta]\nbash = []\n")"
    _HI_PACKAGES_GROUPS=alpha,beta
    full_check
  )"
  { _hi_contains "$out" " $_HI_REAL_CMD " && _hi_contains "$out" " bash "; } || _hi_why out _HI_REAL_CMD
}

# ...unset runs the shipped default, core useful deprecated, and no other
function test_full_check_unset_runs_the_default_groups() {
  local out
  out="$(
    _HI_PACKAGES="$(_hi_pkg_one groups-default "[core]\nsh = []\n[useful]\nls = []\n[deprecated.unwanted]\ncat = []\n[extras]\nbash = []\n")"
    unset _HI_PACKAGES_GROUPS
    full_check
  )"
  _hi_contains "$out" " sh " && _hi_contains "$out" " ls " &&
    _hi_contains "$out" " cat " || _hi_why out || return 1
  case "$out" in *bash*) _hi_why out || return 1 ;; esac
  return 0
}

# a hand-written [none] section is not run by the word that turns groups off
function test_full_check_none_is_not_a_group() {
  local out
  out="$(
    _HI_PACKAGES="$(_hi_pkg_one groups-none-section "[none]\n$_HI_REAL_CMD = []\n")"
    _HI_PACKAGES_GROUPS=none
    full_check
  )"
  [ -z "$out" ] || _hi_why out
}

# `none` turns every group off, but rows above the first `[group]` line
# always run
function test_full_check_none_keeps_the_ungrouped_rows() {
  local out
  out="$(
    _HI_PACKAGES="$(_hi_pkg_one groups-none "$_HI_REAL_CMD = []\n[alpha]\nbash = []\n")"
    _HI_PACKAGES_GROUPS=none
    full_check
  )"
  _hi_contains "$out" " $_HI_REAL_CMD " || _hi_why out _HI_REAL_CMD || return 1
  case "$out" in *bash*) _hi_why out || return 1 ;; esac
  return 0
}

function test_full_check_wraps_at_max_width() {
  local out lines
  out="$(
    _HI_PACKAGES="$(_hi_pkg_one wrap "$_HI_REAL_CMD = []\nbash = []\n")"
    _HI_MAX_WIDTH=1
    full_check
  )"
  lines="$(printf '%s\n' "$out" | grep -c .)"
  [ "$lines" -ge 2 ] || _hi_why lines
}

function test_full_check_reads_real_packages_file_without_erroring() {
  full_check >/dev/null || _hi_why
}

# full_check is the cascade's landing point: it absorbs an incoming
# $_HI_ROW_CARRY as its own first cells, ahead of the packages it reads
# itself, rather than leaving it for a caller that has nowhere left to send
# it. `local -a _HI_ROW_CARRY` shadows the global the same way other cases in
# this file shadow $_HI_HEADER_VERSION, and the call is not wrapped in
# $(...) where inspecting its post-call state is needed.
function test_full_check_absorbs_an_incoming_carry() {
  local out got got2
  local -a _HI_ROW_CARRY=(carriedcell)
  out="$(_HI_PACKAGES="$(_hi_pkg_one carry-absorb "$_HI_REAL_CMD = []\n")" full_check)"
  got="$(_hi_pos "$out" carriedcell)"
  got2="$(_hi_pos "$out" "$_HI_REAL_CMD")"
  [[ "$out" == *carriedcell* ]] && [[ "$out" == *"$_HI_REAL_CMD"* ]] && [ -n "$got" ] && [ -n "$got2" ] && [ "$got" -lt "$got2" ] || _hi_why got got2 out _HI_REAL_CMD
}

# ...and takes ownership of it: nothing is left for a caller after it to
# flush a second time.
function test_full_check_consumes_the_carry() {
  local -a _HI_ROW_CARRY=(carriedcell)
  _HI_PACKAGES="$(_hi_pkg_one carry-consume "$_HI_REAL_CMD = []\n")" full_check >/dev/null
  [ "${#_HI_ROW_CARRY[@]}" -eq 0 ] || _hi_why _HI_ROW_CARRY
}

# a carry still has to print even when the packages file itself yields
# nothing visible - full_check must not return the moment $visible is
# empty, before it considers its second source
function test_full_check_prints_carry_even_with_no_visible_packages() {
  local out
  local -a _HI_ROW_CARRY=(onlycell)
  out="$(_HI_PACKAGES="$(_hi_pkg_one carry-no-packages "")" full_check)"
  [[ "$out" == *onlycell* ]] || _hi_why out
}

# ...and the original guard still holds with nothing on either side
function test_full_check_empty_carry_and_no_packages_prints_nothing() {
  local out
  local -a _HI_ROW_CARRY=()
  out="$(_HI_PACKAGES="$(_hi_pkg_one carry-empty-none "")" full_check)"
  [ -z "$out" ] || _hi_why out
}

# The assertion that would have caught the BSD-sort bug where it happened. That
# sort ran under the ambient locale, and on macOS it exited with "Illegal byte
# sequence" and printed nothing - so full_check rendered an empty check while
# still exiting 0, and only the downstream output assertions noticed. stderr is
# the direct signal; everything else is a symptom.
function test_full_check_is_silent_on_stderr() {
  local err
  err="$({ full_check >/dev/null; } 2>&1)"
  [ -z "$err" ] || _hi_why err
}

# ...and the other half of that failure mode: sorting produced no rows at all.
# A visible package must actually reach the output, not just fail to error.
function test_full_check_emits_a_row_for_an_installed_package() {
  local out
  out="$(
    _HI_PACKAGES="$(_hi_pkg_one emits "$_HI_REAL_CMD = []\n")"
    full_check
  )"
  [[ "$out" == *"$_HI_REAL_CMD"* ]] || _hi_why out _HI_REAL_CMD
}

# Highest tier first, and file order within one - one pass per rank, no sort:
# ls (core, 3) prints ahead of sh (useful, 2) ahead of cat (extras, 1),
# though the file lists them the other way round
function test_full_check_orders_by_tier_then_file_order() {
  local out got got2 got3
  out="$(
    _HI_PACKAGES="$(_hi_pkg_one rank-order "[extras]\ncat = []\n[useful]\nsh = []\n[core]\nls = []\n")"
    _HI_PACKAGES_GROUPS="extras useful core"
    full_check
  )"
  got="$(_hi_pos "$out" " cat ")"
  got2="$(_hi_pos "$out" " ls ")"
  got3="$(_hi_pos "$out" " sh ")"
  [ -n "$got" ] && [ -n "$got2" ] && [ -n "$got3" ] || _hi_why got got2 got3 out || return 1
  got="$(_hi_pos "$out" " ls ")"
  got2="$(_hi_pos "$out" " sh ")"
  got3="$(_hi_pos "$out" " cat ")"
  [ "$got" -lt "$got2" ] && [ "$got2" -lt "$got3" ] || _hi_why got got2 got3 out
}

# Warnings and alarms (rank 4) lead even a core row listed before them, in
# file order between themselves
function test_full_check_sorts_warnings_and_alarms_first() {
  local out w a c
  out="$(
    _HI_PACKAGES="$(_hi_pkg_one warn-first "[core]\nls = []\n[extras.unwanted]\n$_HI_REAL_CMD = []\n[extras.required]\n$_HI_FAKE_CMD = []\n")"
    _HI_PACKAGES_GROUPS="core extras"
    full_check
  )"
  w="$(_hi_pos "$out" " $_HI_REAL_CMD ")" a="$(_hi_pos "$out" " $_HI_FAKE_CMD ")"
  c="$(_hi_pos "$out" " ls ")"
  { [ -n "$w" ] && [ -n "$a" ] && [ -n "$c" ] && ((w < a && a < c)); } || _hi_why w a c
}

# $_HI_PACKAGES naming no file prints nothing, and says nothing on stderr -
# the check has no rows, not a failure to report
function test_full_check_with_no_file_prints_nothing() {
  local out
  out="$(_HI_PACKAGES="$_HI_WORKDIR/no-such-packages" full_check 2>&1)"
  [ -z "$out" ] || _hi_why out
}

# _hi_packages_palette's contract: exactly four entries - one per tier
# 0-3 - in both tables, whichever ramp is in force. `VAR=val func` on a shell
# function (not an external command) reverts VAR once the call returns, so
# this leaves no _HI_PACKAGES_PALETTE behind for a case after it.
function test_packages_palette_fills_four_slots_each_way() {
  unset _HI_PACKAGES_PALETTE
  _hi_packages_palette
  [ "${#_HI_YES[@]}" -eq 4 ] && [ "${#_HI_NO[@]}" -eq 4 ] || _hi_why _HI_YES _HI_NO || return 1
  _HI_PACKAGES_PALETTE="$_HI_TEST_RAMP" _hi_packages_palette
  [ "${#_HI_YES[@]}" -eq 4 ] && [ "${#_HI_NO[@]}" -eq 4 ] || _hi_why _HI_YES _HI_NO
}

# eight names of the user's own become the two tables verbatim, in order:
# the first four installed, the last four missing
function test_packages_palette_takes_a_ramp_verbatim() {
  _HI_PACKAGES_PALETTE="$_HI_TEST_RAMP" _hi_packages_palette
  [ "${_HI_YES_NAMES[*]} ${_HI_NO_NAMES[*]}" = "$_HI_TEST_RAMP" ] || _hi_why _HI_YES_NAMES _HI_NO_NAMES
}

# anything that is not eight names resolves to the same tables an unset one
# does - checked by content, not by name, since header.sh's own assignment
# above is the only place the shipped ramp is spelled out. The fallback has
# to survive a *previous* call having installed a ramp of the user's own,
# which is what configure.sh's previews do between renders.
function test_packages_palette_bad_value_falls_back_to_the_shipped_ramp() {
  local -a shipped_yes shipped_no
  local bad
  unset _HI_PACKAGES_PALETTE
  _hi_packages_palette
  shipped_yes=("${_HI_YES[@]}") shipped_no=("${_HI_NO[@]}")
  for bad in bogus "" "cyan green brcyan" "$_HI_TEST_RAMP brred" \
    "cyan green brcyan brgreen blue magenta bryellow nosuch" \
    "cyan  green brcyan brgreen blue magenta bryellow brred" "* * * * * * * *"; do
    _HI_PACKAGES_PALETTE="$_HI_TEST_RAMP" _hi_packages_palette
    _HI_PACKAGES_PALETTE="$bad" _hi_packages_palette
    [ "${_HI_YES[*]}" = "${shipped_yes[*]}" ] && [ "${_HI_NO[*]}" = "${shipped_no[*]}" ] || _hi_why shipped_yes shipped_no _HI_YES _HI_NO || return 1
  done
}

# every name in the shipped ramp has to be a real _HI_COLOR_NAMES entry, or
# _hi_ramp_escape would be asked for a slot that does not exist and the
# header would paint with nothing. A direct membership check, since the ramps
# store names.
function test_shipped_ramp_names_are_all_real_colors() {
  local entry found candidate
  unset _HI_PACKAGES_PALETTE
  _hi_packages_palette
  [ "${_HI_YES_NAMES[*]} ${_HI_NO_NAMES[*]}" = "$_HI_PACKAGES_RAMP" ] || _hi_why _HI_YES_NAMES _HI_NO_NAMES _HI_PACKAGES_RAMP || return 1
  for entry in "${_HI_YES_NAMES[@]}" "${_HI_NO_NAMES[@]}"; do
    found=""
    for candidate in "${_HI_COLOR_NAMES[@]}"; do
      [ "$candidate" = "$entry" ] && found=1 && break
    done
    [ -n "$found" ] || _hi_why found || return 1
  done
}

# A 48-word scheme: the check paints from the second bank, every other cell
# from the first, so bank 2's cyan (slot 17, 11a8cd) is what the shipped
# ramp's tier-0 installed color becomes.
# _HI_TEST_L24/_HI_TEST_L48: tests/lib/fixtures.sh, shared with core_test.sh

function test_packages_palette_uses_the_second_bank_under_48_words() {
  local ok=0
  (
    # shellcheck disable=SC2030,SC2031 # per-scheme, in its own subshell on purpose
    export _HI_COLOR_SCHEME="$_HI_TEST_L48" _HI_TRUECOLOR=1
    local want
    _hi_assign_palette
    unset _HI_PACKAGES_PALETTE
    _hi_packages_palette
    _hi_color_escape_at want 29
    [ "${_HI_YES[0]}" = "$want" ] && [ "${_HI_YES[0]}" != "$CYAN" ] &&
      [ "$want" = '\e[0;36;38;2;17;168;205m' ] &&
      [ "${#_HI_YES[@]}" -eq 4 ] && [ "${#_HI_NO[@]}" -eq 4 ]
  ) && ok=1
  [ "$ok" = 1 ] || _hi_why ok
}

# ...and stays the first bank - the palette variables themselves - under a
# 24-word list or nothing
function test_packages_palette_keeps_the_first_bank_under_24_words() {
  local ok=0
  (
    # shellcheck disable=SC2030,SC2031 # per-scheme, in its own subshell on purpose
    export _HI_COLOR_SCHEME="$_HI_TEST_L24" _HI_TRUECOLOR=1
    _hi_assign_palette
    unset _HI_PACKAGES_PALETTE
    _hi_packages_palette
    [ "${_HI_YES[0]}" = "$CYAN" ] && [ "${_HI_NO[3]}" = "$BRRED" ] && [[ "$CYAN" == *";38;2;"* ]]
  ) && ok=1
  [ "$ok" = 1 ] || _hi_why ok
}

# NO_COLOR empties every palette variable, and the second-bank swap has to
# leave them empty rather than paint over the user's no
function test_packages_palette_second_bank_is_inert_under_no_color() {
  local ok=0
  (
    # shellcheck disable=SC2030,SC2031 # per-scheme, in its own subshell on purpose
    export _HI_COLOR_SCHEME="$_HI_TEST_L48" _HI_TRUECOLOR=1 NO_COLOR=1
    _hi_assign_palette
    _hi_packages_palette
    [ -z "${_HI_YES[0]}" ] && [ -z "${_HI_NO[3]}" ]
  ) && ok=1
  [ "$ok" = 1 ] || _hi_why ok
}

function run_header_check_tests() {
  _hi_header_begin

  _hi_h1 "Testing common/header.sh (the package check)"

  _hi_h2 "Testing: check_line"
  _hi_check "Installed, first name -> checked, at its tier" test_check_line_installed_first_name_is_checked
  _hi_check "Installed via an alternative -> that name, tilded" test_check_line_installed_alternative_is_tilded
  _hi_check "Missing -> the first name, crossed, at its tier" test_check_line_missing_shows_the_first_name_crossed
  _hi_check "No tier argument paints at tier 1" test_check_line_tier_defaults_to_one
  _hi_check_requires bash "The first installed alternative wins" test_check_line_first_installed_alternative_wins
  _hi_check "Missing on a - row -> nothing" _hi_no_visible_row "-$_HI_FAKE_CMD" 3
  _hi_check "Installed on a - row -> a rank-4 warning" test_check_line_unwanted_installed_warns
  _hi_check "...an installed alternative warns too" test_check_line_unwanted_alternative_installed_warns
  _hi_check "Installed on a + row -> nothing" _hi_no_visible_row "+$_HI_REAL_CMD" 3
  _hi_check "...via an alternative, nothing too" _hi_no_visible_row "+$_HI_FAKE_CMD,$_HI_REAL_CMD" 3
  _hi_check "Missing on a + row -> a rank-4 alarm" test_check_line_required_missing_alarms

  _hi_h2 "Testing: package groups"
  _hi_check "Group names map to tiers" test_group_tier_maps_names_to_tiers
  _hi_check "_HI_PACKAGES_GROUPS: unset, lists, none" test_group_on_reads_the_list
  _hi_check "Sections are listed in file order" test_package_groups_lists_sections_in_file_order
  _hi_check "A row is its key and its array" test_full_check_reads_a_toml_row
  _hi_check "A group is its three tables" test_full_check_reads_a_group_by_its_tables

  _hi_h2 "Testing: full_check"
  _hi_check "Skips comment/blank lines" test_full_check_skips_comments_and_blanks
  _hi_check "Empty output when every row is silent" test_full_check_empty_when_everything_is_silent
  _hi_check_requires bash "Runs only the named groups" test_full_check_runs_only_the_named_groups
  _hi_check_requires bash "...from a comma-separated list" test_full_check_reads_a_comma_separated_list
  _hi_check_requires bash "Unset runs core useful deprecated" test_full_check_unset_runs_the_default_groups
  _hi_check_requires bash "none still runs the rows above the first group" test_full_check_none_keeps_the_ungrouped_rows
  _hi_check "A [none] section never runs" test_full_check_none_is_not_a_group
  _hi_check_requires bash "Wraps rows at _HI_MAX_WIDTH" test_full_check_wraps_at_max_width
  _hi_check "Real config/packages parses cleanly" test_full_check_reads_real_packages_file_without_erroring
  _hi_check "Writes nothing to stderr" test_full_check_is_silent_on_stderr
  _hi_check "Emits a row for an installed package" test_full_check_emits_a_row_for_an_installed_package
  _hi_check "Absorbs an incoming carry ahead of its own cells" test_full_check_absorbs_an_incoming_carry
  _hi_check "...and consumes it" test_full_check_consumes_the_carry
  _hi_check "A carry still prints with no visible packages" test_full_check_prints_carry_even_with_no_visible_packages
  _hi_check "Empty carry, no packages: still silent" test_full_check_empty_carry_and_no_packages_prints_nothing
  _hi_check "Tier high to low, file order within one" test_full_check_orders_by_tier_then_file_order
  _hi_check "Warnings and alarms sort first" test_full_check_sorts_warnings_and_alarms_first
  _hi_check "No packages file prints nothing" test_full_check_with_no_file_prints_nothing

  _hi_h2 "Testing: _hi_packages_palette"
  _hi_check "Four entries per table, either way" test_packages_palette_fills_four_slots_each_way
  _hi_check "Eight names of your own are taken verbatim" test_packages_palette_takes_a_ramp_verbatim
  _hi_check "Anything else falls back to the shipped ramp" test_packages_palette_bad_value_falls_back_to_the_shipped_ramp
  _hi_check "Every shipped entry names a real color" test_shipped_ramp_names_are_all_real_colors
  _hi_check "The check paints from the second bank under 48 words" test_packages_palette_uses_the_second_bank_under_48_words
  _hi_check "...and from the first under 24" test_packages_palette_keeps_the_first_bank_under_24_words
  _hi_check "...and stays empty under NO_COLOR" test_packages_palette_second_bank_is_inert_under_no_color

  _hi_suite_end "header.sh (the package check)"
}

run_header_check_tests
