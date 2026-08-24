#!/bin/bash
# Unit tests for common/header.sh - the banner and its detail lines, plus the
# packages check (check_line/full_check) that lives at the bottom of that file.
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"
# shellcheck source=../../common/header.sh
source "$_HI_HEADER"

# Pin the glyph set: most cases below match the multibyte glyphs literally,
# and a runner without a UTF-8 locale (macOS CI) would otherwise get the
# ASCII fallback and fail them all. The fallback has its own cases.
_HI_ASCII=0
_hi_choose_glyphs

function test_header_row_joins_cells() {
  local out
  out="$(header_row foo bar baz)"
  [[ "$out" == *"| foo"* && "$out" == *"| bar"* && "$out" == *"| baz"* ]]
}

function test_header_row_single_cell() {
  local out
  out="$(header_row solo)"
  [[ "$out" == *"| solo"* ]]
}

function test_banner_includes_label_and_host() {
  local out host
  host="$(_hi_hostname)"
  out="$(banner TestBanner)"
  [[ "$out" == *"TestBanner"* && "$out" == *"$host"* ]]
}

# a longer prefix reserves more of the (already-printed) line, so it should
# shrink - never grow - the tilde padding banner prints for itself
#
# The hostname is pinned rather than taken from the machine. banner budgets a
# fixed width between the change count, the label, the host and the prefix, and
# floors the tildes at 4 once that budget is gone - so on a host whose name runs
# past ~54 characters *both* calls floor, the two lines come out the same length
# and this reads as a failure of the padding logic when it is really a failure
# to control the fixture. That is what it did on the macOS CI runner.
# The pin only reaches banner if $_HI_BANNER_HOST is unset, because banner
# memoizes the hostname into it and an earlier case can leave it filled. Unset
# inside the command substitution, never a bare `local` in the function: under
# bash 3.2 `local V` creates V *set and null*, so `${V+x}` is non-empty there and
# banner would skip resolving the hostname and render an empty one. bash 4+ makes
# a bare `local` unset, so that mistake passes everywhere except the macOS job.
function test_banner_prefix_shrinks_padding() {
  local plain prefixed _HI_HOSTNAME_CACHE="pinned-host"
  plain="$(
    unset _HI_BANNER_HOST
    banner TestBanner "$BRGREEN" ""
  )"
  prefixed="$(
    unset _HI_BANNER_HOST
    banner TestBanner "$BRGREEN" "$(printf 'x%.0s' {1..50})"
  )"
  [ "${#prefixed}" -lt "${#plain}" ]
}

# ...and the floor itself, reached on purpose with the hostname pinned long
# rather than by accident on a machine that happens to have a long one.
function test_banner_floors_padding_on_a_long_hostname() {
  local out _HI_HOSTNAME_CACHE
  printf -v _HI_HOSTNAME_CACHE 'h%.0s' {1..60}
  out="$(
    unset _HI_BANNER_HOST
    banner TestBanner
  )"
  [[ "$out" == *"$_HI_HOSTNAME_CACHE"* && "$out" == *"~"* ]]
}

function test_banner_floors_tildes_on_long_label() {
  local out label
  label="$(printf 'x%.0s' {1..200})" # forces the ((tildes < 4)) floor
  out="$(banner "$label")"
  [[ "$out" == *"$label"* && "$out" == *"~"* ]]
}

function test_banner_narrow_width_does_not_error() {
  local out
  out="$(_HI_MAX_WIDTH=10 banner Narrow)"
  [ -n "$out" ]
}

# the C-locale fallback: same banner, ASCII ^ in place of ↑ (the subshell
# re-decides the set; the suite's pinned choice outside is untouched)
function test_banner_ascii_fallback_uses_caret() {
  local out
  out="$(
    _HI_ASCII=1
    _hi_choose_glyphs
    banner TestBanner
  )"
  [[ "$out" == *"^"* ]] && [[ "$out" != *"↑"* ]]
}

# ...and the marks swap with it, keeping check_line's width math honest
# (the ASCII ok is two columns and declares itself as such)
function test_marks_swap_to_ascii_with_the_set() {
  (
    _HI_ASCII=1
    _hi_choose_glyphs
    [ "$_HI_MARK_OK" = ok ] && [ "$_HI_MARK_OK_W" = 2 ] &&
      [ "$_HI_MARK_NO" = x ] && [ "$_HI_MARK_NO_W" = 1 ]
  )
}

function test_timestamp_runs_and_has_three_cells() {
  local out
  out="$(_HI_RELEASE="" timestamp)"
  [ "$(grep -o '|' <<<"$out" | wc -l)" -eq 3 ]
}

# the version is the middle cell, between the two clocks, and is printed bare
# - no "say-hi" in front of it. The palette is blanked for the row rather than
# stripped after: the cells are `| `-joined and field 1 is the empty lead.
function test_timestamp_puts_the_version_between_the_clocks() {
  local out
  out="$(NC='' GREEN='' BRBLUE='' BRYELLOW='' _HI_RELEASE=1.2.3 timestamp)"
  [ "$(cut -d'|' -f3 <<<"$out" | tr -d ' ')" = "1.2.3" ] && [[ "$out" != *"say-hi"* ]]
}

# ...and a shell with no stamp still gets one: this checkout answers with git
# describe, and only a stampless, gitless install falls through to "unknown"
function test_timestamp_version_falls_back_without_a_stamp() {
  local out
  out="$(NC='' GREEN='' BRBLUE='' BRYELLOW='' _HI_RELEASE="" timestamp)"
  [ -n "$(cut -d'|' -f3 <<<"$out" | tr -d ' ')" ]
}

function test_system_info_includes_static_labels() {
  local out
  out="$(system_info)"
  [[ "$out" == *"Cores:"* && "$out" == *"RAM:"* && "$out" == *"CPU:"* ]]
}

function test_identity_includes_static_labels() {
  local out
  out="$(identity)"
  [[ "$out" == *"Auth:"* && "$out" == *"Pub:"* ]]
}

function test_banner_disabled_produces_no_output() {
  local out
  out="$(_HI_HEADER_BANNER=0 banner TestBanner)"
  [ -z "$out" ]
}

# guards the default: the toggle is opt-out, so an unset var must still print
function test_banner_prints_when_toggle_unset() {
  local out
  out="$(unset _HI_HEADER_BANNER && banner TestBanner)"
  [[ "$out" == *"TestBanner"* ]]
}

# banner runs twice a session (connect, then load.sh's disconnect) for a change
# count that can't have moved in between, and `git status --short` over the
# checkout is ~10ms a call. The second call has to reuse the first's answer.
# The output goes to a file rather than through $(...): the caching happens in
# a variable, and a command substitution would run banner in a subshell where
# the assignment can't be observed - which is the very thing under test.
function test_banner_change_count_is_computed_once() {
  local first second file
  # under $_HI_WORKDIR, so the teardown trap owns it: the early `return 1`
  # below is on the failure path, where a manual rm never runs
  file="$_HI_WORKDIR/banner.$$"
  # _HI_BANNER_HOST too: banner memoizes the hostname into it, and this is the
  # one case that deliberately runs banner in the suite's own shell, so anything
  # it leaves behind outlives it. Left set, it silently overrides the
  # _HI_HOSTNAME_CACHE pin every later case relies on.
  unset _HI_BANNER_CHANGES _HI_BANNER_HOST
  banner TestBanner >"$file"
  first="$(cat "$file")"
  [ -n "${_HI_BANNER_CHANGES+x}" ] || return 1 # nothing was cached at all
  # a value git could never produce, so a second git call would overwrite it
  _HI_BANNER_CHANGES=4242
  banner TestBanner >"$file"
  second="$(cat "$file")"
  unset _HI_BANNER_CHANGES _HI_BANNER_HOST
  [ -n "$first" ] && [[ "$second" == *4242* ]]
}

# ...but only when there is a checkout to count. A shipped tree has no .git,
# and the banner there must simply carry no counter rather than a stale one.
function test_banner_omits_the_count_without_a_git_dir() {
  local out dir
  dir="$_HI_WORKDIR/nogit.$$"
  mkdir -p "$dir"
  out="$(
    _HI_ROOT="$dir"
    unset _HI_BANNER_CHANGES
    banner TestBanner
  )"
  [[ "$out" == *"TestBanner"* ]] && [[ "$out" != *"↑"* ]]
}

# The branch-indicator cases below each stand a tiny checkout up via
# test_lib.sh's _hi_git_fixture (one commit on main), so HEAD can be moved to
# a working branch or detached per case.

# the roadmap contract: the Online banner on a working branch names it, in
# parentheses, right after the change count
function test_banner_online_names_an_off_main_branch() {
  local dir out
  dir="$(_hi_git_fixture)"
  git -C "$dir" checkout -qb feature-x
  out="$(
    _HI_ROOT="$dir"
    unset _HI_BANNER_CHANGES _HI_BANNER_BRANCH
    banner Online
  )"
  [[ "$out" == *"(feature-x)"* ]]
}

# ...but main is the expected state and earns no callout
function test_banner_online_stays_quiet_on_main() {
  local dir out
  dir="$(_hi_git_fixture)"
  out="$(
    _HI_ROOT="$dir"
    unset _HI_BANNER_CHANGES _HI_BANNER_BRANCH
    banner Online
  )"
  [[ "$out" == *"↑"* && "$out" != *"("* ]]
}

# ...nor does a detached HEAD, which is what a release-tag checkout is
function test_banner_online_stays_quiet_when_detached() {
  local dir out
  dir="$(_hi_git_fixture)"
  git -C "$dir" checkout -q --detach
  out="$(
    _HI_ROOT="$dir"
    unset _HI_BANNER_CHANGES _HI_BANNER_BRANCH
    banner Online
  )"
  [[ "$out" == *"↑"* && "$out" != *"("* ]]
}

# Online only: the same branch stays out of the Connected and Disconnected
# banners a session prints
function test_banner_branch_stays_out_of_remote_banners() {
  local dir out label
  dir="$(_hi_git_fixture)"
  git -C "$dir" checkout -qb feature-x
  for label in Connected Disconnected; do
    out="$(
      _HI_ROOT="$dir"
      unset _HI_BANNER_CHANGES _HI_BANNER_BRANCH
      banner "$label"
    )"
    [[ "$out" == *"↑"* && "$out" != *"("* ]] || return 1
  done
}

# the branch spends the tilde budget, not line width: same label, same repo,
# fewer tildes once the indicator is on the line
#
# _HI_BANNER_HOST is unset alongside the rest for the same reason the sibling at
# the top of this file pins the hostname: banner memoizes it, and a real host
# name long enough to floor the padding (macOS CI) makes both calls print 4
# tildes, which reads as a padding bug and is really an uncontrolled fixture.
function test_banner_branch_shrinks_padding() {
  local dir plain branched _HI_HOSTNAME_CACHE="pinned-host"
  dir="$(_hi_git_fixture)"
  plain="$(
    _HI_ROOT="$dir"
    unset _HI_BANNER_CHANGES _HI_BANNER_BRANCH _HI_BANNER_HOST
    banner Online
  )"
  git -C "$dir" checkout -qb feature-x
  branched="$(
    _HI_ROOT="$dir"
    unset _HI_BANNER_CHANGES _HI_BANNER_BRANCH _HI_BANNER_HOST
    banner Online
  )"
  [ "$(tr -dc '~' <<<"$branched" | wc -c)" -lt "$(tr -dc '~' <<<"$plain" | wc -c)" ]
}

# the regression this toggle exists for: silencing the banner must leave the
# rest of the header alone, unlike _HI_DISABLE_HEADER which kills all of it
function test_hi_header_banner_off_keeps_detail_lines() {
  local out
  out="$(_HI_HEADER_BANNER=0 hi_header Connected)"
  [[ "$out" != *"Connected"* && "$out" == *"Cores:"* && "$out" == *"RAM:"* ]]
}

function test_hi_header_disabled_produces_no_output() {
  local out
  out="$(_HI_DISABLE_HEADER=1 hi_header Connected)"
  [ -z "$out" ]
}

function test_hi_header_enabled_prints_banner() {
  local out
  out="$(_HI_DISABLE_HEADER=0 hi_header Connected)"
  [[ "$out" == *"Connected"* ]]
}

# shellcheck disable=SC2209 # the literal command name "sh" is intentional, not a botched `sh` invocation
_HI_REAL_CMD=sh
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

function test_check_line_found_primary_is_visible_checked() {
  local -a visible=()
  check_line "$_HI_REAL_CMD:5"
  [ "${#visible[@]}" -eq 1 ] || return 1
  _hi_contains "${visible[0]}" "$_HI_REAL_CMD" &&
    _hi_assert_contains "${visible[0]}" "$_HI_MARK_OK"
}

# 4 is the one tier hidden when the tool *is* there: it exists to speak up
# about absence, so a healthy box says nothing.
function test_check_line_found_priority4_is_hidden() {
  local -a visible=()
  check_line "$_HI_REAL_CMD:4"
  [ "${#visible[@]}" -eq 0 ]
}

# Every tier now speaks when the tool is absent - that is the nudge the table
# exists for, and tier 0, the quietest one there is, is where it is worth
# pinning: if even trivia reports itself missing, nothing above it can be
# silently dropped.
function test_check_line_missing_priority0_is_visible() {
  local -a visible=()
  check_line "$_HI_FAKE_CMD:0"
  [ "${#visible[@]}" -eq 1 ] || return 1
  _hi_contains "${visible[0]}" "$_HI_FAKE_CMD" &&
    _hi_assert_contains "${visible[0]}" "$_HI_MARK_NO"
}

function test_check_line_missing_priority5_is_visible_crossed() {
  local -a visible=()
  check_line "$_HI_FAKE_CMD:5"
  [ "${#visible[@]}" -eq 1 ] || return 1
  _hi_contains "${visible[0]}" "$_HI_FAKE_CMD" &&
    _hi_assert_contains "${visible[0]}" "$_HI_MARK_NO"
}

function test_check_line_fallback_uses_second_alternative() {
  local -a visible=()
  check_line "$_HI_FAKE_CMD:0,$_HI_REAL_CMD:5"
  [ "${#visible[@]}" -eq 1 ] || return 1
  _hi_contains "${visible[0]}" "$_HI_REAL_CMD" &&
    _hi_assert_contains "${visible[0]}" "$_HI_MARK_ALT"
}

function test_check_line_picks_highest_priority_installed() {
  local -a visible=()
  check_line "$_HI_REAL_CMD:1,bash:5"
  _hi_contains "${visible[0]}" bash
}

function test_full_check_skips_comments_and_blanks() {
  local pkgfile="$_HI_WORKDIR/comments"
  printf '# a comment\n\n%s:5\n' "$_HI_REAL_CMD" >"$pkgfile"
  (
    _HI_PACKAGES="$pkgfile"
    full_check
  ) | grep -qF "$_HI_REAL_CMD"
}

function test_full_check_empty_when_everything_hidden() {
  local pkgfile="$_HI_WORKDIR/hidden" out
  # installed at tier 4 is the one cell the table still hides - see the note
  # above _HI_YES. Nothing else renders nothing.
  printf '%s:4\n' "$_HI_REAL_CMD" >"$pkgfile"
  out="$(
    _HI_PACKAGES="$pkgfile"
    full_check
  )"
  [ -z "$out" ]
}

# The floor's boundary, which is the whole point of the setting: >= shows, < is
# gone. One file, one run, both sides asserted - a case that only checked the
# hidden half would pass just as well if the floor hid everything.
function test_full_check_min_priority_boundary() {
  local pkgfile="$_HI_WORKDIR/floor" out
  # both installed, so the only thing separating them is the floor. bash is a
  # second real command (the wrap case above leans on it the same way).
  printf '%s:3\nbash:2\n' "$_HI_REAL_CMD" >"$pkgfile"
  out="$(
    _HI_PACKAGES="$pkgfile"
    _HI_PACKAGES_MIN_PRIORITY=3
    full_check
  )"
  _hi_contains "$out" "$_HI_REAL_CMD" || return 1
  # exactly at the floor stays, one below it does not
  case "$out" in *bash*) return 1 ;; esac
  return 0
}

# a floor above every rank prints nothing at all - not a blank line, which in a
# header reads as a check that ran and found nothing rather than one turned off
function test_full_check_min_priority_above_everything_is_silent() {
  local pkgfile="$_HI_WORKDIR/floor-all" out
  printf '%s:5\n' "$_HI_REAL_CMD" >"$pkgfile"
  out="$(
    _HI_PACKAGES="$pkgfile"
    _HI_PACKAGES_MIN_PRIORITY=6
    full_check
  )"
  [ -z "$out" ]
}

# unset behaves as 1, not 0: rank 1 prints and rank 0 does not. Both halves
# again, for the reason the boundary case above gives - a default that hid
# everything would pass a test that only checked the hidden side.
function test_full_check_min_priority_defaults_to_one() {
  local pkgfile="$_HI_WORKDIR/floor-default" out
  printf '%s:1\nbash:0\n' "$_HI_REAL_CMD" >"$pkgfile"
  out="$(
    _HI_PACKAGES="$pkgfile"
    unset _HI_PACKAGES_MIN_PRIORITY
    full_check
  )"
  _hi_contains "$out" "$_HI_REAL_CMD" || return 1
  case "$out" in *bash*) return 1 ;; esac
  return 0
}

function test_full_check_wraps_at_max_width() {
  local pkgfile="$_HI_WORKDIR/wrap" out lines
  printf '%s:5\nbash:5\n' "$_HI_REAL_CMD" >"$pkgfile"
  out="$(
    _HI_PACKAGES="$pkgfile"
    _HI_MAX_WIDTH=1
    full_check
  )"
  lines="$(printf '%s\n' "$out" | grep -c .)"
  [ "$lines" -ge 2 ]
}

function test_full_check_reads_real_packages_file_without_erroring() {
  full_check >/dev/null
}

# The assertion that would have caught the BSD-sort bug where it happened. That
# sort ran under the ambient locale, and on macOS it exited with "Illegal byte
# sequence" and printed nothing - so full_check rendered an empty check while
# still exiting 0, and only the downstream output assertions noticed. stderr is
# the direct signal; everything else is a symptom.
function test_full_check_is_silent_on_stderr() {
  local err
  err="$({ full_check >/dev/null; } 2>&1)"
  [ -z "$err" ]
}

# ...and the other half of that failure mode: sorting produced no rows at all.
# A visible package must actually reach the output, not just fail to error.
function test_full_check_emits_a_row_for_an_installed_package() {
  local pkgfile="$_HI_WORKDIR/emits" out
  printf '%s:5\n' "$_HI_REAL_CMD" >"$pkgfile"
  out="$(
    _HI_PACKAGES="$pkgfile"
    full_check
  )"
  [[ "$out" == *"$_HI_REAL_CMD"* ]]
}

function run_header_tests() {
  _hi_workdir headertest

  _hi_h1 "Testing common/header.sh"

  _hi_suite_begin

  _hi_h2 "Testing: header_row"
  _hi_check "Joins multiple cells" test_header_row_joins_cells
  _hi_check "Handles a single cell" test_header_row_single_cell

  _hi_h2 "Testing: banner"
  _hi_check "Includes label and hostname" test_banner_includes_label_and_host
  _hi_check "A longer prefix shrinks the padding" test_banner_prefix_shrinks_padding
  _hi_check "Floors padding on a long hostname" test_banner_floors_padding_on_a_long_hostname
  _hi_check "Floors tilde padding on a pathologically long label" test_banner_floors_tildes_on_long_label
  _hi_check "Survives a narrow _HI_MAX_WIDTH" test_banner_narrow_width_does_not_error
  _hi_check "ASCII fallback swaps the arrow" test_banner_ascii_fallback_uses_caret
  _hi_check "...and the marks with it" test_marks_swap_to_ascii_with_the_set
  _hi_check "No output when _HI_HEADER_BANNER=0" test_banner_disabled_produces_no_output
  _hi_check "Still prints when the toggle is unset" test_banner_prints_when_toggle_unset
  _hi_check "Change count is computed once per session" test_banner_change_count_is_computed_once
  _hi_check "No count without a .git dir" test_banner_omits_the_count_without_a_git_dir
  _hi_check "Online names an off-main branch" test_banner_online_names_an_off_main_branch
  _hi_check "Online stays quiet on main" test_banner_online_stays_quiet_on_main
  _hi_check "Online stays quiet when detached" test_banner_online_stays_quiet_when_detached
  _hi_check "Branch stays out of Connected/Disconnected" test_banner_branch_stays_out_of_remote_banners
  _hi_check "Branch spends tilde budget, not width" test_banner_branch_shrinks_padding

  _hi_h2 "Testing: timestamp / system_info / identity (smoke tests)"
  _hi_check "Timestamp prints three cells" test_timestamp_runs_and_has_three_cells
  _hi_check "The version sits between the clocks" test_timestamp_puts_the_version_between_the_clocks
  _hi_check "Without a stamp the version still resolves" test_timestamp_version_falls_back_without_a_stamp
  _hi_check "System_info includes its static labels" test_system_info_includes_static_labels
  _hi_check "Identity includes its static labels" test_identity_includes_static_labels

  _hi_h2 "Testing: hi_header"
  _hi_check "No output when disabled" test_hi_header_disabled_produces_no_output
  _hi_check "Prints the banner when enabled" test_hi_header_enabled_prints_banner
  _hi_check "Banner off still prints the detail lines" test_hi_header_banner_off_keeps_detail_lines

  _hi_h2 "Testing: check_line"
  _hi_check "Found primary -> visible, checked" test_check_line_found_primary_is_visible_checked
  _hi_check "Found priority 4 -> hidden" test_check_line_found_priority4_is_hidden
  _hi_check "Missing priority 0 -> visible" test_check_line_missing_priority0_is_visible
  _hi_check "Missing priority 5 -> visible, crossed" test_check_line_missing_priority5_is_visible_crossed
  _hi_check "Fallback alternative used" test_check_line_fallback_uses_second_alternative
  _hi_check_requires bash "Picks the highest-priority installed alternative" test_check_line_picks_highest_priority_installed

  _hi_h2 "Testing: full_check"
  _hi_check "Skips comment/blank lines" test_full_check_skips_comments_and_blanks
  _hi_check "Empty output when everything is hidden" test_full_check_empty_when_everything_hidden
  _hi_check_requires bash "Min priority: at the floor shows, below is gone" test_full_check_min_priority_boundary
  _hi_check "Min priority above every rank prints nothing" test_full_check_min_priority_above_everything_is_silent
  _hi_check_requires bash "Min priority unset floors at 1" test_full_check_min_priority_defaults_to_one
  _hi_check_requires bash "Wraps rows at _HI_MAX_WIDTH" test_full_check_wraps_at_max_width
  _hi_check "Real settings/packages file parses cleanly" test_full_check_reads_real_packages_file_without_erroring
  _hi_check "Writes nothing to stderr" test_full_check_is_silent_on_stderr
  _hi_check "Emits a row for an installed package" test_full_check_emits_a_row_for_an_installed_package

  _hi_suite_end "header.sh"
}

run_header_tests
