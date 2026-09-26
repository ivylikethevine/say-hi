#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
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

# Every non-blank line of <text>, ANSI stripped, is exactly <width> columns -
# a closed row's contract (_hi_row_line, full_check), for cases below that
# pin the column a row ends on rather than the presence of a pipe.
function _hi_all_lines_are() {
  local text="$1" want="$2" line n
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    _hi_visible_width n "$(_hi_strip_ansi "$line")"
    [ "$n" -eq "$want" ] || {
      _hi_cecho " | got width $n, want $want: [$line]" "$RED"
      return 1
    }
  done <<<"$text"
}

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

# a normal-width terminal still gets one line for a normal row - the wrap
# logic must not fire when nothing is actually overflowing
function test_header_row_default_width_stays_one_line() {
  local out lines
  out="$(header_row foo bar baz)"
  lines="$(printf '%s\n' "$out" | grep -c .)"
  [ "$lines" -eq 1 ]
}

function test_header_row_wraps_at_max_width() {
  local out lines
  out="$(_HI_MAX_WIDTH=1 header_row foo bar baz)"
  lines="$(printf '%s\n' "$out" | grep -c .)"
  [ "$lines" -ge 2 ]
}

# wrapping happens between cells, never inside one - every original cell's
# text still appears intact somewhere in the (multi-line) output
function test_header_row_wrap_keeps_cells_intact() {
  local out
  out="$(_HI_MAX_WIDTH=5 header_row alpha beta gamma)"
  [[ "$out" == *alpha* && "$out" == *beta* && "$out" == *gamma* ]]
}

# --- the right edge: a row ends in the banner's column, not just a pipe ---

function test_header_row_closes_at_default_width() {
  local out
  out="$(header_row foo bar baz)"
  _hi_all_lines_are "$out" 80
}

function test_header_row_closes_at_narrow_width() {
  local out
  out="$(_HI_MAX_WIDTH=40 header_row cell-one-x cell-two-x cell-three cell-four- cell-five-)"
  _hi_all_lines_are "$out" 40
}

# every wrapped continuation line closes too, not only the first
function test_header_row_closes_every_wrapped_line() {
  local out lines
  out="$(_HI_MAX_WIDTH=24 header_row aaaaaaaa bbbbbbbb cccccccc dddddddd eeeeeeee)"
  lines="$(printf '%s\n' "$out" | grep -c .)"
  [ "$lines" -ge 3 ] && _hi_all_lines_are "$out" 24
}

# $_HI_DISABLE_RIGHT_EDGE gives back the open-ended row: no closing pipe, and
# a row stops short of the pinned width rather than being padded out to it
function test_disable_right_edge_gives_back_the_open_row() {
  local out
  out="$(_HI_DISABLE_RIGHT_EDGE=1 _HI_MAX_WIDTH=40 header_row cell-one-x cell-two-x cell-three)"
  local line n
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    [[ "$(_hi_strip_ansi "$line")" != *"|" ]] || return 1
    _hi_visible_width n "$(_hi_strip_ansi "$line")"
    ((n < 40)) || return 1
  done <<<"$out"
}

# _hi_visible_width's own contract: the color escape does not count
function test_hi_visible_width_strips_a_leading_color() {
  local n
  _hi_visible_width n "${GREEN}hi"
  [ "$n" -eq 2 ]
}

# Columns, never bytes. The header packs by this number, so where ${#}
# answers in bytes - a target under LC_ALL=C drawing the glyph set its client
# shipped it - a three-byte glyph measured as three would wrap a line the
# terminal had room for. GLOSSARY: HI.12
function test_hi_visible_width_counts_columns_not_bytes() {
  local n
  _hi_visible_width n "abc●●●"
  [ "$n" = 6 ]
}

# ...and the byte-counting branch itself, forced on, so the case exercises it
# on a UTF-8 runner too rather than only where the locale happens to trip it
function test_hi_visible_width_counts_columns_where_length_counts_bytes() {
  local n
  (
    _HI_BYTE_COUNTS=1
    _hi_visible_width n "${GREEN}abc●●●"
    [ "$n" = 6 ]
  )
}

function test_hi_visible_width_plain_text_unchanged() {
  local n
  _hi_visible_width n "hi"
  [ "$n" -eq 2 ]
}

# the width math has to be off the visible length, not the byte length - two
# colored cells short enough to share a line must not wrap just because their
# escape bytes would have pushed them over
function test_header_row_width_ignores_color_escape_bytes() {
  local out lines
  out="$(_HI_MAX_WIDTH=20 header_row "${GREEN}short" "${RED}text")"
  lines="$(printf '%s\n' "$out" | grep -c .)"
  [ "$lines" -eq 1 ]
}

# _hi_draw_width's own contract: captured output (this whole suite runs
# inside command substitution, never a tty) stays at $_HI_MAX_WIDTH exactly,
# so every width test above is unaffected by whatever terminal runs it
function test_hi_draw_width_defaults_to_max_width_when_captured() {
  local n
  n="$(_HI_MAX_WIDTH=42 bash -c 'source "$_HI_HEADER"; _hi_draw_width n; printf %s "$n"')"
  [ "$n" = 42 ]
}

# $_HI_TERM_COLS is a deliberate override - it wins whether or not stdout is
# a tty, which is what lets a suite pin a narrow width the same way it
# already pins $_HI_MAX_WIDTH
function test_hi_draw_width_honors_an_explicit_override() {
  local n
  n="$(_HI_MAX_WIDTH=80 _HI_TERM_COLS=30 bash -c 'source "$_HI_HEADER"; _hi_draw_width n; printf %s "$n"')"
  [ "$n" = 30 ]
}

# the terminal only ever narrows the draw width, never widens it past
# $_HI_MAX_WIDTH
function test_hi_draw_width_never_widens_past_max_width() {
  local n
  n="$(_HI_MAX_WIDTH=40 _HI_TERM_COLS=200 bash -c 'source "$_HI_HEADER"; _hi_draw_width n; printf %s "$n"')"
  [ "$n" = 40 ]
}

# header_row wraps at the narrower of the two - the point of the whole
# change: a real terminal narrower than $_HI_MAX_WIDTH breaks at the '|', not
# wherever the terminal itself would hard-wrap mid-cell
function test_header_row_wraps_at_hi_term_cols_override() {
  local out lines
  out="$(_HI_MAX_WIDTH=80 _HI_TERM_COLS=10 header_row alpha beta gamma)"
  lines="$(printf '%s\n' "$out" | grep -c .)"
  [ "$lines" -eq 3 ]
}

# Armed (hi_header's own row loop), a row that overflows hands the rest
# straight to $_HI_ROW_CARRY instead of wrapping within itself - the point of
# the cascade. _HI_ROW_CARRY_ARMED and _HI_ROW_CARRY are `local`-shadowed
# (the same dynamic-scope trick $_HI_HEADER_VERSION uses elsewhere in this
# file), and the call is not wrapped in $(...) - a command substitution forks
# a subshell, and the assignments header_row makes to the shadowed globals
# would never reach back out to this function.
function test_header_row_armed_carries_overflow_to_the_next_call() {
  local _HI_ROW_CARRY_ARMED=1 outfile="$_HI_WORKDIR/row-carry-armed" out
  local -a _HI_ROW_CARRY=()
  _HI_MAX_WIDTH=10 header_row alpha beta gamma >"$outfile"
  out="$(cat "$outfile")"
  [[ "$out" == *alpha* ]] && [[ "$out" != *beta* ]] && [[ "$out" != *gamma* ]] &&
    [ "${#_HI_ROW_CARRY[@]}" -eq 2 ] &&
    [ "${_HI_ROW_CARRY[0]}" = beta ] && [ "${_HI_ROW_CARRY[1]}" = gamma ]
}

# ...and the carried cells reach the very next header_row call, prepended
# ahead of its own - nothing is dropped between rows.
function test_header_row_armed_carry_opens_the_next_row() {
  local _HI_ROW_CARRY_ARMED=1 out
  local -a _HI_ROW_CARRY=()
  _HI_MAX_WIDTH=10 header_row alpha beta gamma >/dev/null
  out="$(header_row delta)"
  [[ "$out" == *beta* ]] && [[ "$out" == *gamma* ]] && [[ "$out" == *delta* ]]
}

# unarmed - every caller but hi_header's own loop - a row still drains
# whatever it couldn't fit on its own, so no carry is left lying around for
# the next unrelated call to inherit
function test_header_row_unarmed_leaves_no_carry_behind() {
  local _HI_ROW_CARRY_ARMED=0
  local -a _HI_ROW_CARRY=()
  _HI_MAX_WIDTH=5 header_row alpha beta gamma >/dev/null
  [ "${#_HI_ROW_CARRY[@]}" -eq 0 ]
}

# _hi_row_line's own documented contract: zero cells is a no-op, not an empty
# line - nothing reaches this arm through header_row (it always has at least
# the un-carried "$@"), so only a direct call exercises it.
function test_row_line_returns_1_and_prints_nothing_for_zero_cells() {
  local out ec=0
  out="$(_hi_row_line)" || ec=$?
  [ "$ec" -eq 1 ] && [ -z "$out" ]
}

# _hi_header_flush's termination argument, proven rather than assumed: three
# cells at a width that fits exactly one per line takes three rounds of the
# while loop, and every cell still reaches output with the carry left empty.
function test_header_flush_drains_across_multiple_overflow_rounds() {
  local outfile="$_HI_WORKDIR/header-flush-multi" out lines
  local -a _HI_ROW_CARRY=(alpha beta gamma)
  _HI_MAX_WIDTH=5 _hi_header_flush >"$outfile"
  out="$(cat "$outfile")"
  lines="$(printf '%s\n' "$out" | grep -c .)"
  [[ "$out" == *alpha* && "$out" == *beta* && "$out" == *gamma* ]] &&
    [ "$lines" -eq 3 ] && [ "${#_HI_ROW_CARRY[@]}" -eq 0 ]
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
# fixed width between the change count, the label, the host, and the prefix, and
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

# One arm per half, each naming itself: the tildes cannot go missing by
# construction (the floor is 4, and start_len caps at tildes - 1), so if this
# fails on the label it means banner printed nothing at all - a different bug,
# and one a bare FAILED has hidden twice on Windows arm64.
function test_banner_floors_tildes_on_long_label() {
  local out label
  label="$(printf 'x%.0s' {1..200})" # forces the ((tildes < 4)) floor
  out="$(banner "$label")"
  [[ "$out" == *"$label"* ]] ||
    _hi_because "banner dropped the label, printing ${#out} chars: [$out]" || return 1
  [[ "$out" == *"~"* ]] ||
    _hi_because "banner printed no tilde: [$out]"
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

# ...and the marks swap with it. All four are one visible column in either
# set, which is what lets check_line's width math treat the mark as a constant
function test_marks_swap_to_ascii_with_the_set() {
  (
    _HI_ASCII=1
    _hi_choose_glyphs
    [ "$_HI_MARK_OK" = "+" ] && [ "$_HI_MARK_NO" = x ] &&
      [ "$_HI_MARK_ALT" = "~" ] && [ "$_HI_MARK_WARN" = "!" ]
  )
}

function test_timestamp_runs_and_has_three_cells() {
  local out
  out="$(_HI_RELEASE="" timestamp)"
  # four pipes for three cells: the one that opens the row, the two that join
  # the cells, and the one that closes it on the right - and that last one
  # sits in the banner's own column, not merely somewhere in the row
  [ "$(grep -o '|' <<<"$out" | wc -l)" -eq 4 ] && _hi_all_lines_are "$out" 80
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

# _hi_header_version's own memo - "resolved once per shell (the row prints
# twice a session)" - captured by direct call rather than $( ), which would
# fork away the assignment to $_HI_HEADER_VERSION before it ever landed.
function test_header_version_resolves_once_per_shell() {
  (
    unset _HI_HEADER_VERSION
    _HI_RELEASE=1.0.0
    _hi_header_version >/dev/null
    local first="$_HI_HEADER_VERSION"
    _HI_RELEASE=2.0.0 # a later change must not reach an already-memoized version
    _hi_header_version >/dev/null
    [ "$_HI_HEADER_VERSION" = "$first" ] && [ "$first" = 1.0.0 ]
  )
}

# the header cell itself carries the shortened form, not just the helper in
# isolation - this checkout's own git describe is what timestamp renders
function test_timestamp_version_cell_is_shortened() {
  local out version
  out="$(NC='' GREEN='' BRBLUE='' BRYELLOW='' _HI_RELEASE="" timestamp)"
  version="$(cut -d'|' -f3 <<<"$out" | tr -d ' ')"
  [[ "$version" != *-g[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]* && "$version" != *-dirty ]] &&
    [ "${#version}" -le 10 ]
}

# The two row renders the suite asserts on, kept here rather than in header.sh
# since hi_header draws through _hi_cell_* directly and nothing else wants a
# whole row at once. The text form is what a fresh-bash case evals after
# sourcing header.sh (_hi_stripped_header, _hi_identity_with).
# shellcheck disable=SC2016 # function text, expanded where it is eval'd
_HI_ROW_FNS='
function _hi_sysinfo_row() {
  local arch os cores cpu ram
  _hi_cell_arch arch
  _hi_cell_os os
  _hi_cell_cores cores
  _hi_cell_cpu cpu
  _hi_cell_ram ram
  header_row "$arch" "$os" "$cores" "$cpu" "$ram"
}
function _hi_identity_row() {
  local gitid containers jobs pods auth pub up_cell
  local -a cells
  _hi_cell_gitid gitid
  _hi_cell_containers containers
  _hi_cell_jobs jobs
  _hi_cell_pods pods
  _hi_cell_auth auth
  _hi_cell_pub pub
  _hi_cell_uptime up_cell
  cells=("$gitid")
  [ -n "$containers" ] && cells+=("$containers")
  [ -n "$jobs" ] && cells+=("$jobs")
  [ -n "$pods" ] && cells+=("$pods")
  cells+=("$auth" "$pub" "$up_cell")
  header_row "${cells[@]}"
}'
eval "$_HI_ROW_FNS"

function test_system_info_includes_static_labels() {
  local out
  out="$(_hi_sysinfo_row)"
  [[ "$out" == *"Cores:"* && "$out" == *"RAM:"* && "$out" == *"CPU:"* ]]
}

# the uptime cell is an identity-group word - the sysinfo row must not carry it
function test_system_info_does_not_show_uptime() {
  local out
  out="$(_hi_sysinfo_row)"
  [[ "$out" != *"Up:"* ]]
}

# GHz is the only format the CPU cell renders now - one pin so a regression
# back to whole MHz integers is caught
function test_system_info_cpu_cell_is_ghz() {
  local out
  out="$(_hi_sysinfo_row)"
  [[ "$out" == *"GHz"* ]]
}

# the CPU cell sits right after Cores:, with RAM: behind it
function test_system_info_cpu_cell_sits_next_to_cores() {
  local out cores_pos cpu_pos ram_pos
  out="$(_hi_sysinfo_row)"
  cores_pos="$(_hi_pos "$out" "Cores:")"
  cpu_pos="$(_hi_pos "$out" "CPU:")"
  ram_pos="$(_hi_pos "$out" "RAM:")"
  [ -n "$cores_pos" ] && [ -n "$cpu_pos" ] && [ -n "$ram_pos" ] &&
    ((cores_pos < cpu_pos)) && ((cpu_pos < ram_pos))
}

# _hi_ghz's own contract, from its comment: rounded to tenths *before*
# splitting, so a carry lands in the whole-GHz digit (2950 -> 3.0) rather than
# spilling into a second decimal (2.10) - the CPU cell's cases above only
# ever see the already-rounded strings this produces.
function test_ghz_rounds_the_carry_into_the_whole_digit() {
  local out
  _hi_ghz out 2950
  [ "$out" = 3.0 ] || return 1
  _hi_ghz out 2949
  [ "$out" = 2.9 ] || return 1
  _hi_ghz out 2100
  [ "$out" = 2.1 ]
}

# _hi_load_pct's own contract: load divided by cores, rounded to a whole
# percent, empty rather than a garbled or divide-by-zero cell whenever either
# input can't back that math up
function test_hi_load_pct_divides_load_by_cores() {
  local out
  _hi_load_pct out 2.00 4
  [ "$out" = 50 ]
}

# _hi_load_pct_out <load> <cores> - _hi_load_pct's out-variable on stdout, so
# its answers can be pinned as _hi_check_eq roster lines
function _hi_load_pct_out() {
  local out=""
  _hi_load_pct out "$@"
  printf '%s' "$out"
}

# _hi_cell_uptime: at most two units, largest first, or "?" where no probe
# answers - the shape is pinned rather than a value, which moves by the second
function test_uptime_cell_is_humanized() {
  local out
  _hi_cell_uptime out
  [[ "$out" =~ Up:\ ([0-9]+d\ [0-9]+h|[0-9]+h\ [0-9]+m|[0-9]+m|\?) ]]
}

# _hi_cell_ip: dotted-quad addresses joined with ", ", or "?" - the shape is
# pinned rather than a value, which depends on this box's own network config
function test_ip_cell_has_a_shape() {
  local out
  # none: in a container the only address is often docker's 172.*, hidden by
  # default, and an empty cell has no shape to check
  _HI_IP_HIDE=none _hi_cell_ip out
  [[ "$out" =~ IP:\ ([0-9]{1,3}(\.[0-9]{1,3}){3}(,\ [0-9]{1,3}(\.[0-9]{1,3}){3})*|\?) ]]
}

# used/total, one unit on total only ("6/60G", not "6G/60G" - the used
# figure's own G is redundant next to it), or total alone when only that
# probe answers, or "?" when neither does - the shape is pinned, not a
# value, since this box's own usage moves between runs. The second
# alternative alone would also match a regressed "6G/60G" (its "6G" prefix
# satisfies `[0-9]+G`), so the explicit "no G/" check carries the real
# assertion.
function test_system_info_ram_cell_is_used_over_total() {
  local out
  out="$(_hi_sysinfo_row)"
  [[ "$out" =~ RAM:\ ([0-9]+/[0-9]+G|[0-9]+G|\?) ]] && [[ "$out" != *"G/"* ]]
}

# the load-average figure, when a probe answers, rides in parens right after
# "Cores: N" as a percentage of that count - not next to "GHz", where a bare
# decimal meant nothing without knowing how many cores it was dividing by.
# Optional, since a stripped target has no /proc/loadavg or vm.loadavg, or no
# core count to divide by; a figure that showed up would have to be a plain
# integer percentage, never garbage from an unguarded parse.
function test_system_info_load_rides_the_cores_cell() {
  local out load
  out="$(_hi_sysinfo_row)"
  load="$(printf '%s' "$out" | sed -n 's/.*Cores: [0-9?]* (\([^)]*\)).*/\1/p')"
  [[ -z "$load" || "$load" =~ ^[0-9]+%$ ]]
}

# ...and the GHz cell carries nothing of its own in parens - the one
# thing this rides on is the clock figure itself
function test_system_info_cpu_cell_has_no_parenthetical() {
  local out
  out="$(_hi_sysinfo_row)"
  [[ "$out" != *"GHz ("* ]]
}

# A target with a shell and awk and nothing else - core_test.sh's barebones
# box, one layer up. The header is the first thing a session prints, so a
# missing uname greeting the user with "command not found" across the
# banner would be a bad first impression; the cells say "?" instead, the way
# every other sysinfo probe answers a missing binary.
# shellcheck disable=SC2016 # the probe expands in the child bash, not here
function _hi_stripped_header() {
  _hi_bare_bash stripped 'bash awk' \
    'source "$_HI_HOME/say-hi/common/core.sh"; source "$_HI_HEADER"; eval "$_HI_CASE_PROBE"' \
    _HI_CASE_PROBE="$1"
}

function test_system_info_without_uname_says_unknown() {
  local out
  out="$(_hi_stripped_header "$_HI_ROW_FNS; _hi_sysinfo_row")"
  [[ "$out" == *"?"* ]] && ! grep -qE "$_HI_SHELL_ERROR_RE" <<<"$out" && return 0
  # once red on Windows arm64 with nothing to say; the row itself says why
  _hi_cecho " | the row without uname came out as:" "$RED"
  printf '%s\n' "$out" | sed 's/^/      /'
  return 1
}

# ...except the clocks, which bash 4.2+ formats itself (printf's %(...)T): a
# missing date(1) costs them nothing there, and 3.2 (macOS's) still says "?"
function test_timestamp_answers_without_date() {
  local out
  out="$(_hi_stripped_header timestamp)"
  ! grep -qE "$_HI_SHELL_ERROR_RE" <<<"$out" || return 1
  if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 2))); then
    [[ "$out" =~ [0-9]{2}:[0-9]{2}:[0-9]{2}\ UTC ]]
  else
    [[ "$out" == *"?"* ]]
  fi
}

# unlike the other sysinfo cells, _hi_cell_uptime's only external dependency
# on Linux is awk - which "stripped" still carries, since most probes need it -
# so this stays a smoke test for "no raw shell error leaks out", not a claim
# that the cell renders "?": a real /proc/uptime under a real Linux kernel
# answers it regardless of what else is missing.
# shellcheck disable=SC2016 # $u expands in the stripped child bash, not here
function test_uptime_cell_survives_a_stripped_environment() {
  local out
  out="$(_hi_stripped_header '_hi_cell_uptime u; printf "%s" "$u"')"
  [[ "$out" == *"Up: "* ]] && ! grep -qE "$_HI_SHELL_ERROR_RE" <<<"$out"
}

# The exact case the comment above contrasts itself with: every branch of
# _hi_cell_ip's first stage is an external binary ("ip", "hostname",
# "ifconfig", "ipconfig") the stripped ("bash and awk only") target has none
# of, so unlike uptime this doubles as a claim about the value, not only
# about failing quietly - "?" is the only answer this environment can give.
# shellcheck disable=SC2016 # $i expands in the stripped child bash, not here
function test_ip_cell_says_unknown_under_a_stripped_environment() {
  local out
  out="$(_hi_stripped_header '_hi_cell_ip i; printf "%s" "$i"')"
  [[ "$out" == *"IP: ?"* ]] && ! grep -qE "$_HI_SHELL_ERROR_RE" <<<"$out"
}

# the whole banner, since that is what a session actually prints
function test_banner_renders_without_coreutils() {
  local out
  out="$(_hi_stripped_header 'banner Connected "" ""')"
  [[ "$out" == *Connected* ]] && ! grep -qE "$_HI_SHELL_ERROR_RE" <<<"$out"
}

function test_identity_includes_static_labels() {
  local out
  out="$(_hi_identity_row)"
  [[ "$out" == *"Auth:"* && "$out" == *"Pub:"* ]]
}

# uptime rides at the end of the identity row, after Auth:/Pub: - not a
# row of its own
function test_identity_includes_uptime_cell_last() {
  local out auth_pos pub_pos up_pos
  out="$(_hi_identity_row)"
  auth_pos="$(_hi_pos "$out" "Auth:")"
  pub_pos="$(_hi_pos "$out" "Pub:")"
  up_pos="$(_hi_pos "$out" "Up:")"
  [ -n "$auth_pos" ] && [ -n "$pub_pos" ] && [ -n "$up_pos" ] &&
    ((auth_pos < pub_pos)) && ((pub_pos < up_pos))
}

# A restricted PATH with just what the identity cells/_hi_probe_launch need, and none
# of docker/podman/nomad/kubectl - so "backend absent" is guaranteed
# regardless of what is actually installed on the box running this suite.
function _hi_identity_path() {
  _hi_real_path identity-tools bash sh awk sed grep mktemp rm cat git find \
    timeout date stat sort head tr cut wc
}

# _hi_identity_path with one fake <name> prepended, answering
# _hi_probe_launch's own invocation shape for it - docker/podman get
# "container ls -q" (one line per fake container), nomad gets "job status" (a
# header line, since the jobs cell drops line 1, then one line per fake job).
function _hi_backend_shim() {
  local name="$1" count="$2" i=0
  local dir="$_HI_WORKDIR/backend-$name-$count"
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    {
      printf '%s\n' '#!/bin/sh'
      [ "$name" = nomad ] && printf '%s\n' 'echo "ID  Status"'
      while [ "$i" -lt "$count" ]; do
        printf 'echo line%d\n' "$i"
        i=$((i + 1))
      done
    } >"$dir/$name"
    chmod +x "$dir/$name"
  fi
  printf '%s:%s' "$dir" "$(_hi_identity_path)"
}

# ...and kubectl, which the pods cell reaches through targets.sh (sh
# "$_HI_TARGETS" kube) rather than a direct call - a fake answering both
# invocations targets.sh's kube lane makes: `config view ...` (the namespace
# lookup, left empty here) and `get pods ...` ($1 fake running pods, one
# namespace/pod/container triple per line, the shape kube_rows reads).
function _hi_kube_shim() {
  local count="$1" i=0
  local dir="$_HI_WORKDIR/backend-kube-$count"
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    {
      printf '%s\n' '#!/bin/sh'
      # shellcheck disable=SC2016 # $1 belongs to the fake kubectl script, not this shell
      printf '%s\n' 'case "$1" in'
      printf '%s\n' 'config) exit 0 ;;'
      printf '%s\n' 'get)'
      while [ "$i" -lt "$count" ]; do
        printf 'echo "default pod%d c1"\n' "$i"
        i=$((i + 1))
      done
      printf '%s\n' ';;'
      printf '%s\n' 'esac'
    } >"$dir/kubectl"
    chmod +x "$dir/kubectl"
  fi
  printf '%s:%s' "$dir" "$(_hi_identity_path)"
}

# The identity row, run in a fresh bash with $1 as PATH - isolates which backend
# binaries _hi_probe_launch actually finds from whatever is really installed
# on the box running this suite. _HI_TARGETS_TTL=0 sends the kube lane
# straight past targets.sh's own cache/lock files (real state this suite does
# not own, under /run or $TMPDIR) to a fresh sweep every call.
function _hi_identity_with() {
  PATH="$1" _HI_TARGETS_TTL=0 bash -c "source \"\$_HI_HEADER\"; $_HI_ROW_FNS; _hi_identity_row" 2>&1
}

# One rule for all three: no cell at all when the backend was never found -
# no fallback text either
function test_identity_hides_all_backend_cells_when_none_found() {
  local out
  out="$(_hi_identity_with "$(_hi_identity_path)")"
  [[ "$out" != *"Containers:"* && "$out" != *"Jobs:"* && "$out" != *"Pods:"* && "$out" != *"docker/podman"* ]]
}

# test_identity_shows_count <backend> <n> <label> - once found, the count
# shows even at zero: a probed-and-idle backend is distinguishable from an
# absent one
function test_identity_shows_count() {
  local shim
  if [ "$1" = kube ]; then shim="$(_hi_kube_shim "$2")"; else shim="$(_hi_backend_shim "$1" "$2")"; fi
  [[ "$(_hi_identity_with "$shim")" == *"$3: $2"* ]]
}

function test_banner_disabled_produces_no_output() {
  local out
  out="$(_HI_DISABLE_BANNER=1 banner TestBanner)"
  [ -z "$out" ]
}

# guards the default: the toggle is opt-out, so an unset var must still print
function test_banner_prints_when_toggle_unset() {
  local out
  out="$(unset _HI_DISABLE_BANNER && banner TestBanner)"
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

# _hi_fixture_banner <dir> <label> - banner, run against the fixture checkout
# rather than this repo, with its memoized state cleared so every case
# computes fresh. _HI_BANNER_HOST is unset alongside the change/branch caches
# for the same reason the sibling at the top of this file pins the hostname:
# banner memoizes it, and a real host name long enough to floor the padding
# (macOS CI) makes every call print 4 tildes, which reads as a padding bug and
# is really an uncontrolled fixture. Runs in a subshell, so nothing leaks.
function _hi_fixture_banner() {
  (
    _HI_ROOT="$1"
    unset _HI_BANNER_CHANGES _HI_BANNER_BRANCH _HI_BANNER_HOST
    banner "$2"
  )
}

# the roadmap contract: the Online banner on a working branch names it, in
# parentheses, right after the change count
function test_banner_online_names_an_off_main_branch() {
  local dir out
  dir="$(_hi_git_fixture)"
  git -C "$dir" checkout -qb feature-x
  out="$(_hi_fixture_banner "$dir" Online)"
  [[ "$out" == *"(feature-x)"* ]]
}

# ...but main is the expected state and earns no callout
function test_banner_online_stays_quiet_on_main() {
  local dir out
  dir="$(_hi_git_fixture)"
  out="$(_hi_fixture_banner "$dir" Online)"
  [[ "$out" == *"↑"* && "$out" != *"("* ]]
}

# ...nor does a detached HEAD, which is what a release-tag checkout is
function test_banner_online_stays_quiet_when_detached() {
  local dir out
  dir="$(_hi_git_fixture)"
  git -C "$dir" checkout -q --detach
  out="$(_hi_fixture_banner "$dir" Online)"
  [[ "$out" == *"↑"* && "$out" != *"("* ]]
}

# Online only: the same branch stays out of the Connected and Disconnected
# banners a session prints
function test_banner_branch_stays_out_of_remote_banners() {
  local dir out label
  dir="$(_hi_git_fixture)"
  git -C "$dir" checkout -qb feature-x
  for label in Connected Disconnected; do
    out="$(_hi_fixture_banner "$dir" "$label")"
    [[ "$out" == *"↑"* && "$out" != *"("* ]] || return 1
  done
}

# the branch spends the tilde budget, not line width: same label, same repo,
# fewer tildes once the indicator is on the line - the hostname pinned so the
# padding being compared is a controlled fixture (see _hi_fixture_banner)
function test_banner_branch_shrinks_padding() {
  local dir plain branched _HI_HOSTNAME_CACHE="pinned-host"
  dir="$(_hi_git_fixture)"
  plain="$(_hi_fixture_banner "$dir" Online)"
  git -C "$dir" checkout -qb feature-x
  branched="$(_hi_fixture_banner "$dir" Online)"
  [ "$(tr -dc '~' <<<"$branched" | wc -c)" -lt "$(tr -dc '~' <<<"$plain" | wc -c)" ]
}

# the regression this toggle exists for: silencing the banner must leave the
# rest of the header alone, unlike _HI_DISABLE_HEADER which kills all of it
function test_hi_header_banner_off_keeps_detail_lines() {
  local out
  out="$(_HI_DISABLE_BANNER=1 hi_header Connected)"
  [[ "$out" != *"Connected"* && "$out" == *"Cores:"* && "$out" == *"RAM:"* ]]
}

function test_hi_header_disabled_produces_no_output() {
  local out
  out="$(_HI_DISABLE_HEADER=1 hi_header Connected)"
  [ -z "$out" ]
}

# On a failure, what it rendered instead - the bare glob cannot tell an empty
# capture (the subshell died: a Git Bash runner under load has done this) from
# a full header whose banner() returned early, and those want opposite fixes.
function test_hi_header_enabled_prints_banner() {
  local out
  out="$(_HI_DISABLE_HEADER=0 hi_header Connected)"
  [[ "$out" == *"Connected"* ]] && return 0
  _hi_cecho " | no 'Connected' in ${#out} bytes of header:" "$RED"
  _hi_strip_ansi "$out" | sed 's/^/      /'
  return 1
}

# The eager probe launch fires when a backend word is in the order and
# identity is not yet memoized...
function test_hi_header_launches_probes_for_a_backend_word() {
  local out
  out="$(
    function _hi_probe_launch() { echo LAUNCHED; }
    _HI_HEADER_ORDER="containers gitid" hi_header Connected
  )"
  [[ "$out" == *LAUNCHED* ]]
}

# ...and stands down once it is: configure.sh renders hi_header over and over
# in subshells that inherit the memo, and a relaunch there would start
# backends nobody waits on and leave _hi_probe_launch's mktemp dir behind
# _hi_draw_width at a terminal: $COLUMNS first, tput when that is unset (and
# memoized into $_HI_TERM_COLS), and never past $_HI_MAX_WIDTH
# shellcheck disable=SC2016 # single quotes on purpose: the shim and the child expand these
function test_draw_width_reads_columns_then_tput_under_a_tty() {
  local dir out
  dir="$_HI_WORKDIR/drawwidth"
  mkdir -p "$dir"
  printf '#!/bin/sh\n[ "$1" = cols ] && echo 50\n' >"$dir/tput"
  chmod +x "$dir/tput"
  out="$(env _HI_HOME="$_HI_HOME" PATH="$dir:$PATH" "${_HI_PTY_FORCED[@]}" bash -c '
    source "$_HI_HOME/say-hi/common/core.sh"
    source "$_HI_HEADER"
    COLUMNS=40 _hi_draw_width w
    printf "cols=%s " "$w"
    unset _HI_TERM_COLS
    COLUMNS="" _hi_draw_width w
    printf "tput=%s memo=%s " "$w" "$_HI_TERM_COLS"
    _HI_TERM_COLS=""
    _HI_MAX_WIDTH=30 COLUMNS=40 _hi_draw_width w
    printf "max=%s\n" "$w"' 2>&1 | tr -d '\r')"
  [[ "$out" == *"cols=40 tput=50 memo=50 max=30"* ]]
}

# with no docker on the PATH, podman is the container prober - and the probe
# file it writes is the same one docker would have
function test_probe_launch_takes_podman_when_docker_is_absent() {
  local dir out
  dir="$_HI_WORKDIR/podman-only"
  [ -d "$dir" ] || _hi_probe_shims "$dir" runningbox
  rm -f "$dir/docker" "$dir/nomad" "$dir/kubectl"
  printf '#!/bin/sh\necho abc123\n' >"$dir/podman"
  chmod +x "$dir/podman"
  out="$(
    PATH="$dir:$(_hi_identity_path)"
    _HI_PROBE_DIR=""
    _HI_PROBE_PIDS=()
    _hi_probe_launch
    _hi_probe_wait
    [ -n "$_HI_PROBE_DIR" ] || exit 1
    [ -f "$_HI_PROBE_DIR/containers.podman" ] && [ ! -e "$_HI_PROBE_DIR/containers.docker" ] && [ ! -e "$_HI_PROBE_DIR/nomad" ] && echo PODMAN_PROBED
    rm -rf "$_HI_PROBE_DIR"
  )"
  [ "$out" = PODMAN_PROBED ]
}

function test_hi_header_skips_probe_launch_once_identity_is_memoized() {
  local out
  out="$(
    function _hi_probe_launch() { echo LAUNCHED; }
    _HI_ID_PROBED=1 _HI_ID_GITID=gitid _HI_ID_CONTAINERS="" _HI_ID_JOBS="" _HI_ID_PODS=""
    _HI_ID_AUTH=auth _HI_ID_PUB=pub
    _HI_HEADER_ORDER="containers gitid" hi_header Connected
  )"
  [[ "$out" != *LAUNCHED* && "$out" == *gitid* ]]
}

# shellcheck disable=SC2209 # the literal command name "sh" is intentional, not a botched `sh` invocation
_HI_REAL_CMD=sh
_HI_FAKE_CMD=definitely-not-a-real-hi-test-command-xyz

# _hi_pkg_one <name> <body> - a packages file at $_HI_WORKDIR/<name>/packages
# holding <body> (%b, so \n is a line break). Prints the file, for
# $_HI_PACKAGES. Rows above the first `[group]` line always run, so a body
# with no section needs no $_HI_PACKAGES_GROUPS.
function _hi_pkg_one() {
  mkdir -p "$_HI_WORKDIR/$1"
  printf '%b' "$2" >"$_HI_WORKDIR/$1/packages"
  printf '%s' "$_HI_WORKDIR/$1/packages"
}

# hi_header's default row order: timestamp, then sysinfo, then identity
# (uptime's cell rides inside it), then the packages check - each pinned by a
# marker unique to it, checked in the order they appear in the joined output.
# $_HI_HEADER_VERSION is `local`-shadowed (bash's dynamic scope reaches into
# every row function hi_header calls) so timestamp's marker is a literal
# instead of whatever this checkout's git describe happens to say, and the
# packages fixture (the _hi_pos helper's own pattern, from
# test_full_check_emits_a_row_for_an_installed_package) guarantees full_check
# has something to print regardless of what is actually installed on the box
# running this suite.
function test_hi_header_default_order() {
  local _HI_HEADER_VERSION=orderprobe out
  local ts si id ck
  out="$(_HI_PACKAGES="$(_hi_pkg_one order-default "$_HI_REAL_CMD\n")" hi_header Connected)"
  ts="$(_hi_pos "$out" orderprobe)"
  si="$(_hi_pos "$out" "Cores:")"
  id="$(_hi_pos "$out" "Auth:")"
  ck="$(_hi_pos "$out" "$_HI_REAL_CMD")"
  [ -n "$ts" ] && [ -n "$si" ] && [ -n "$id" ] && [ -n "$ck" ] &&
    ((ts < si)) && ((si < id)) && ((id < ck))
}

# a real render, banner included - every line ends in the same column, at a
# width comfortable enough that the banner's own floor behavior (its narrow-
# width cases, above) doesn't kick in and confound this one
function test_hi_header_closes_every_line() {
  local out _HI_HOSTNAME_CACHE=short-host
  out="$(
    unset _HI_BANNER_HOST
    _HI_PACKAGES="$(_hi_pkg_one close-e2e "$_HI_REAL_CMD\nbash\n")" \
    _HI_MAX_WIDTH=40 _HI_HEADER_ORDER="utc version localtime uptime check" hi_header Connected
  )"
  _hi_all_lines_are "$out" 40
}

# ...and hi_footer's banner-plus-timestamp shape closes the same way
function test_hi_footer_closes_every_line() {
  local out _HI_HOSTNAME_CACHE=short-host
  out="$(
    unset _HI_BANNER_HOST
    _HI_MAX_WIDTH=40 _HI_HEADER_ORDER="utc version localtime" hi_footer Disconnected
  )"
  _hi_all_lines_are "$out" 40
}

# a reordered $_HI_HEADER_ORDER moves the features to match, and a feature
# left out of it is not printed at all - that omission is the whole toggle,
# with no separate $_HI_HEADER_* switch behind it. uptime
# is in this order, so its cell still shows.
function test_hi_header_order_setting_reorders_and_can_omit() {
  local _HI_HEADER_VERSION=orderprobe out
  local ck up si
  out="$(_HI_PACKAGES="$(_hi_pkg_one order-custom "$_HI_REAL_CMD\n")" \
  _HI_HEADER_ORDER="check uptime cores" hi_header Connected)"
  ck="$(_hi_pos "$out" "$_HI_REAL_CMD")"
  up="$(_hi_pos "$out" "Up:")"
  si="$(_hi_pos "$out" "Cores:")"
  [[ "$out" != *orderprobe* ]] &&
    [ -n "$ck" ] && [ -n "$up" ] && [ -n "$si" ] &&
    ((ck < up)) && ((up < si))
}

# an unknown word is ignored rather than erroring or printing anything for it
function test_hi_header_order_ignores_an_unknown_word() {
  local out
  out="$(_HI_HEADER_ORDER="bogus cores" hi_header Connected)"
  [[ "$out" == *"Cores:"* ]]
}

# uptime is its own word, independent of every other identity cell
function test_hi_header_order_uptime_is_its_own_word() {
  local out
  out="$(_HI_HEADER_ORDER="uptime cores" hi_header Connected)"
  [[ "$out" == *"Up:"* && "$out" == *"Cores:"* && "$out" != *"Auth:"* ]]
}

function test_hi_header_order_ip_is_its_own_word() {
  local out
  out="$(_HI_IP_HIDE=none _HI_HEADER_ORDER="ip cores" hi_header Connected)"
  [[ "$out" == *"IP:"* && "$out" == *"Cores:"* && "$out" != *"Auth:"* ]]
}

# leaving uptime out of the order hides just that cell - the other identity
# words stay, with no separate toggle behind it
function test_hi_header_order_omitting_uptime_hides_just_that_cell() {
  local out
  out="$(_HI_HEADER_ORDER="gitid auth" hi_header Connected)"
  [[ "$out" != *"Up:"* && "$out" == *"Auth:"* ]]
}

# End to end: hi_header arms the cascade for its own accumulate/flush loop,
# so uptime's overflow (guaranteed last of the identity-group words here)
# rides into the packages row's first line instead of standing alone. A
# restricted PATH (no docker/podman/nomad/kubectl, the same fixture
# the identity row's own backend-cell tests use via _hi_identity_path) keeps these
# cells short and deterministic; one installed package guarantees
# full_check has something to open with.
function test_hi_header_cascades_identity_overflow_into_check() {
  local cfg="$_HI_WORKDIR/cascade-into-check" out line
  mkdir -p "$cfg"
  printf '%s\n' "$_HI_REAL_CMD" >"$cfg/packages"
  out="$(PATH="$(_hi_identity_path)" _HI_TARGETS_TTL=0 _HI_CONFIG_DIR="$cfg" \
  _HI_MAX_WIDTH=25 _HI_HEADER_ORDER="gitid auth pub uptime check" \
    bash -c 'source "$_HI_HEADER"; hi_header Connected' 2>&1)"
  [[ "$out" == *"Up:"* && "$out" == *"$_HI_REAL_CMD"* ]] || return 1
  while IFS= read -r line; do
    case "$line" in *"Up:"*) [[ "$line" == *"$_HI_REAL_CMD"* ]] && return 0 ;; esac
  done <<<"$out"
  return 1
}

# ...and when "check" is left out of the order entirely, the same leftover
# still reaches the header as its own line instead of vanishing - hi_header's
# post-loop flush, not full_check, is what catches it here.
function test_hi_header_flushes_leftover_when_check_is_absent() {
  local out
  out="$(PATH="$(_hi_identity_path)" _HI_TARGETS_TTL=0 \
  _HI_MAX_WIDTH=20 _HI_HEADER_ORDER="gitid auth pub uptime" \
    bash -c 'source "$_HI_HEADER"; hi_header Connected' 2>&1)"
  [[ "$out" == *"Auth:"* && "$out" == *"Up:"* ]]
}

# a reordered $_HI_HEADER_ORDER packs onto one line like any other order -
# only width-driven packing decides where a line breaks
function test_hi_header_order_packs_across_former_group_boundaries() {
  local out lines
  out="$(_HI_HEADER_ORDER="cpu gitid utc" hi_header Connected)"
  lines="$(printf '%s\n' "$out" | grep -c .)"
  # banner + one packed line (cpu, gitid, and utc all short enough to share it)
  [ "$lines" -eq 2 ] &&
    [[ "$out" == *"CPU:"* && "$out" == *"No Git ID"* || "$out" == *"@"* ]]
}

# --- the non-Linux arms of the sysinfo cells, uptime and ip, on shims ------
#
# The macOS and Windows probes cannot run here, so each platform is a PATH
# dir of fake tools answering exactly the invocations header.sh makes, and
# _HI_LINUX_RELEASE pointed at nothing so the kernel string decides the arm.
# What each case asserts is the parse: the figures below are chosen so a
# wrong field, a wrong page size, or a byte order read the wrong way round
# gives a different number.

# _hi_platform_header <shims> <probe> [env...] - <probe> in a child bash
# whose PATH is <shims> plus the coreutils the probes themselves fork
# shellcheck disable=SC2016 # the probe expands in the child bash, not here
function _hi_platform_header() {
  local shims="$1" probe="$2"
  shift 2
  # _HI_LINUX_RELEASE is set after the source: paths.sh (via core.sh) writes
  # its /etc/os-release default over whatever the environment carried in
  env "$@" PATH="$shims:$(_hi_real_path platform-tools bash sh awk sed date fold mktemp rm sleep)" \
    NO_COLOR=1 _HI_CASE_PROBE="$probe" \
    bash -c 'source "$_HI_HEADER"; _HI_LINUX_RELEASE=/nonexistent; eval "$_HI_CASE_PROBE"' 2>&1
}

# an Apple Silicon mac: sysctl has no hw.cpufrequency (the cpu cell fails
# closed to "?"), and vm_stat's page size is 16K and read from its own header
function _hi_mac_shims() {
  local dir="$_HI_WORKDIR/mac-shims"
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    printf '#!/bin/sh\necho "Darwin arm64"\n' >"$dir/uname"
    printf '#!/bin/sh\necho 15.1\n' >"$dir/sw_vers"
    cat >"$dir/sysctl" <<'EOF'
#!/bin/sh
case "$2" in
hw.ncpu) echo 8 ;;
hw.memsize) echo 17179869184 ;;
vm.loadavg) echo "{ 2.00 1.50 1.00 }" ;;
# 5430, not 5400: header.sh reads its own `date +%s` on the other side
# of the pipe, so the two clock reads can straddle a second tick and
# land a second either way. Half a minute in puts the figure in the
# middle of the minute the case asserts instead of on its edge.
kern.boottime) echo "{ sec = $(($(date +%s) - 5430)), usec = 0 } Thu Jan  1 00:00:00 2026" ;;
*) exit 1 ;;
esac
EOF
    cat >"$dir/vm_stat" <<'EOF'
#!/bin/sh
printf '%s\n' 'Mach Virtual Memory Statistics: (page size of 16384 bytes)' \
  'Pages free:                              100000.' \
  'Pages active:                            200000.' \
  'Pages wired down:                         50000.' \
  'Pages occupied by compressor:             12500.'
EOF
    cat >"$dir/ifconfig" <<'EOF'
#!/bin/sh
printf '%s\n' 'lo0: flags=8049<UP,LOOPBACK,RUNNING,MULTICAST> mtu 16384' \
  '	inet 127.0.0.1 netmask 0xff000000' \
  'en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500' \
  '	inet6 fe80::1%en0 prefixlen 64 secured scopeid 0x4' \
  '	inet 192.0.2.10 netmask 0xffffff00 broadcast 192.0.2.255'
EOF
    chmod +x "$dir"/*
  fi
  printf '%s' "$dir"
}

# git-bash on Windows: the MINGW kernel string, wmic's two-line answers
# (header, then the value) and ipconfig's CRLF lines
function _hi_windows_shims() {
  local dir="$_HI_WORKDIR/windows-shims"
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    printf '#!/bin/sh\necho "MINGW64_NT-10.0-22631 x86_64"\n' >"$dir/uname"
    cat >"$dir/wmic" <<'EOF'
#!/bin/sh
case "$1 $2 $3" in
"ComputerSystem get TotalPhysicalMemory") printf 'TotalPhysicalMemory\n17179869184\n' ;;
"cpu get MaxClockSpeed") printf 'MaxClockSpeed\n2400\n' ;;
*) exit 1 ;;
esac
EOF
    cat >"$dir/ipconfig" <<'EOF'
#!/bin/sh
printf '%s\r\n' 'Windows IP Configuration' '' 'Ethernet adapter Ethernet:' \
  '   IPv4 Address. . . . . . . . . . . : 10.0.0.5' \
  '   Subnet Mask . . . . . . . . . . . : 255.255.255.0'
EOF
    chmod +x "$dir"/*
  fi
  printf '%s' "$dir"
}

# _hi_platform_header's Linux twin: same shim discipline, but
# $_HI_LINUX_RELEASE points at a real file so the Linux arm is the one taken
# whatever box this runs on - the mac and Windows helpers above get there by
# pointing it at nothing, and there is no third way to reach this branch.
# shellcheck disable=SC2016 # the probe expands in the child bash, not here
function _hi_linux_header() {
  local shims="$1" probe="$2" rel="$_HI_WORKDIR/os-release"
  shift 2
  [ -f "$rel" ] || printf 'PRETTY_NAME="Test Linux 1.0"\n' >"$rel"
  env "$@" PATH="$shims:$(_hi_real_path platform-tools bash sh awk sed date fold mktemp rm sleep)" \
    NO_COLOR=1 _HI_CASE_PROBE="$probe" _HI_TEST_RELEASE="$rel" \
    bash -c 'source "$_HI_HEADER"; _HI_LINUX_RELEASE="$_HI_TEST_RELEASE"; eval "$_HI_CASE_PROBE"' 2>&1
}

# A Linux box whose `ip` can be silenced: the cell's first stage is `ip -4 -o
# addr show scope global`, and `hostname -I` is the fallback for the hosts
# where that prints nothing. Both answer the field layout header.sh's awk
# reads, so a wrong field number changes the answer.
function _hi_linux_ip_shims() {
  local dir="$_HI_WORKDIR/linux-ip-shims"
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    printf '#!/bin/sh\necho "Linux x86_64"\n' >"$dir/uname"
    cat >"$dir/ip" <<'EOF'
#!/bin/sh
[ "${_HI_FAKE_IP_SILENT:-0}" = 1 ] && exit 0
printf '%s\n' '2: eth0    inet 10.0.0.5/24 brd 10.0.0.255 scope global eth0' \
  '3: eth1    inet 192.0.2.10/24 brd 192.0.2.255 scope global eth1'
EOF
    cat >"$dir/hostname" <<'EOF'
#!/bin/sh
[ "$1" = -I ] && printf '198.51.100.7 198.51.100.8 \n'
EOF
    chmod +x "$dir/uname" "$dir/ip" "$dir/hostname"
  fi
  printf '%s' "$dir"
}

function test_ip_cell_on_linux_reads_iproute2() {
  local out
  # shellcheck disable=SC2016 # the probe expands in the child bash, not here
  out="$(_hi_linux_header "$(_hi_linux_ip_shims)" '_hi_cell_ip i; printf "[%s]" "$i"')"
  [[ "$out" == *"[IP: 10.0.0.5, 192.0.2.10]"* ]] || {
    _hi_cecho " | got: $out" "$RED"
    return 1
  }
}

# `ip` exists and answers nothing on a host with no routable address on an
# iproute2-visible link - a container on a host network among them - and
# `hostname -I` is the second opinion. A bare "?" is reserved for "neither
# tool exists nor has anything to say".
function test_ip_cell_on_linux_falls_back_to_hostname() {
  local out
  # shellcheck disable=SC2016 # the probe expands in the child bash, not here
  out="$(_hi_linux_header "$(_hi_linux_ip_shims)" '_hi_cell_ip i; printf "[%s]" "$i"' _HI_FAKE_IP_SILENT=1)"
  [[ "$out" == *"[IP: 198.51.100.7, 198.51.100.8]"* ]] || {
    _hi_cecho " | got: $out" "$RED"
    return 1
  }
}

# The five sysinfo cells share one memoized probe ($_HI_SI_PROBED), which
# is what makes $_HI_HEADER_ORDER's per-word toggles free: asking for arch
# alone pays for exactly one probe, and asking for all five pays for the same
# one. Counted by standing a uname in front of the mac shims' that appends a
# line per call, and reading the counter either side of the five getters.
function test_system_info_probes_once_for_all_five_cells() {
  local dir="$_HI_WORKDIR/probe-count" count out probe
  count="$_HI_WORKDIR/uname.calls"
  mkdir -p "$dir"
  : >"$count"
  cat >"$dir/uname" <<EOF
#!/bin/sh
printf 'x\n' >>"$count"
echo "Darwin arm64"
EOF
  chmod +x "$dir/uname"
  # awk, not wc: _hi_platform_header's PATH carries only the tools the probes
  # themselves fork, and wc is not one of them
  probe="pre=\$(awk 'END { print NR }' '$count')"
  probe="$probe; v=''; _hi_cell_arch v; _hi_cell_os v; _hi_cell_cores v"
  probe="$probe; _hi_cell_cpu v; _hi_cell_ram v"
  probe="$probe; post=\$(awk 'END { print NR }' '$count')"
  probe="$probe; printf 'delta=%s' \$((post - pre))"
  out="$(_hi_platform_header "$dir:$(_hi_mac_shims)" "$probe")"
  [[ "$out" == *"delta=1"* ]] || {
    _hi_cecho " | five cells cost more than one probe: $out" "$RED"
    return 1
  }
}

function test_system_info_on_a_mac() {
  local out
  out="$(_hi_platform_header "$(_hi_mac_shims)" "$_HI_ROW_FNS; _hi_sysinfo_row")"
  # used = (200000 + 50000 + 12500) pages * 16K = 4.0G of 16G; 2.00 on 8
  # cores is 25%; sysctl answered no clock, so the cpu cell fails closed
  [[ "$out" == *"macOS 15.1"* && "$out" == *"arm64"* && "$out" == *"Cores: 8 (25%)"* &&
    "$out" == *"RAM: 4/16G"* && "$out" == *"CPU: ? GHz"* ]] || {
    _hi_cecho " | got: $out" "$RED"
    return 1
  }
}

function test_uptime_and_ip_cells_on_a_mac() {
  local out
  # shellcheck disable=SC2016 # the probe expands in the child bash, not here
  out="$(_hi_platform_header "$(_hi_mac_shims)" '_hi_cell_uptime u; _hi_cell_ip i; printf "%s\n%s\n" "$u" "$i"')"
  # kern.boottime 5430s ago; ifconfig's inet line, not inet6 and not lo0
  [[ "$out" == *"Up: 1h 30m"* && "$out" == *"IP: 192.0.2.10"* ]] || {
    _hi_cecho " | got: $out" "$RED"
    return 1
  }
}

function test_system_info_on_windows() {
  local out
  out="$(_hi_platform_header "$(_hi_windows_shims)" "$_HI_ROW_FNS; _hi_sysinfo_row" NUMBER_OF_PROCESSORS=4)"
  # wmic exposes the rated clock
  [[ "$out" == *"Windows (MINGW64_NT-10.0-22631)"* && "$out" == *"Cores: 4"* &&
    "$out" == *"RAM: 16G"* && "$out" == *"CPU: 2.4 GHz"* ]] || {
    _hi_cecho " | got: $out" "$RED"
    return 1
  }
}

# _HI_IP_HIDE: a docker bridge address is noise on any box that runs
# containers, so the default hides 172.*; `none` shows everything; any other
# value is a list of globs. The filter is checked on its own, then through
# the cell on a mac-shaped box whose ifconfig answers two addresses.
function test_ip_filter_hides_the_bridge_by_default() {
  local out
  unset _HI_IP_HIDE
  _hi_ip_filter out "172.17.0.2,10.0.0.5"
  [ "$out" = "10.0.0.5" ] || return 1
  _hi_ip_filter out "10.0.0.5,172.18.0.1,192.0.2.10"
  [ "$out" = "10.0.0.5,192.0.2.10" ]
}

# `none` hides nothing; an empty value is unset, so it hides the default
# range - what the wizard's preview shows for it too
function test_ip_filter_none_and_empty_keep_everything() {
  local out
  _HI_IP_HIDE=none _hi_ip_filter out "172.17.0.2,10.0.0.5"
  [ "$out" = "172.17.0.2,10.0.0.5" ] || return 1
  _HI_IP_HIDE="" _hi_ip_filter out "172.17.0.2,10.0.0.5"
  [ "$out" = "10.0.0.5" ]
}

function test_ip_filter_takes_a_glob_list() {
  local out
  _HI_IP_HIDE="10.*" _hi_ip_filter out "172.17.0.2,10.0.0.5"
  [ "$out" = "172.17.0.2" ] || return 1
  _HI_IP_HIDE="10.* 172.*" _hi_ip_filter out "172.17.0.2,10.0.0.5,192.0.2.10"
  [ "$out" = "192.0.2.10" ] || return 1
  _HI_IP_HIDE="192.0.2.1?" _hi_ip_filter out "192.0.2.10,192.0.2.100"
  [ "$out" = "192.0.2.100" ]
}

# every address hidden: the cell is empty (so the header drops it), never
# "?", which still means no routable address was found at all
function test_ip_cell_is_empty_when_every_address_is_hidden() {
  local dir="$_HI_WORKDIR/ip-hide-shims" out
  mkdir -p "$dir"
  printf '#!/bin/sh\necho "Darwin arm64"\n' >"$dir/uname"
  printf '#!/bin/sh\nprintf "\tinet 127.0.0.1 netmask 0xff000000\n\tinet 172.17.0.2 netmask 0xffff0000\n\tinet 10.0.0.5 netmask 0xffffff00\n"\n' >"$dir/ifconfig"
  chmod +x "$dir/uname" "$dir/ifconfig"
  # shellcheck disable=SC2016 # the probe expands in the child bash, not here
  out="$(_hi_platform_header "$dir" '_hi_cell_ip i; printf "[%s]" "$i"')"
  [[ "$out" == *"[IP: 10.0.0.5]"* ]] || {
    _hi_cecho " | default got: $out" "$RED"
    return 1
  }
  # shellcheck disable=SC2016 # the probe expands in the child bash, not here
  out="$(_hi_platform_header "$dir" '_hi_cell_ip i; printf "[%s]" "$i"' _HI_IP_HIDE="10.* 172.*")"
  [[ "$out" == *"[]"* ]] || {
    _hi_cecho " | all hidden got: $out" "$RED"
    return 1
  }
  # shellcheck disable=SC2016 # the probe expands in the child bash, not here
  out="$(_hi_platform_header "$dir" '_hi_cell_ip i; printf "[%s]" "$i"' _HI_IP_HIDE=none)"
  [[ "$out" == *"[IP: 172.17.0.2, 10.0.0.5]"* ]] || {
    _hi_cecho " | none got: $out" "$RED"
    return 1
  }
}

# ...and the header itself then prints no IP cell at all. Shimmed the same
# way the sibling above is: hi_header run against the *real* uname/ifconfig
# only proves this on a box whose live network happens to hand back a
# non-loopback IPv4 the parser recognizes - on one that doesn't, _hi_cell_ip
# takes its "nothing routable found" path and prints "IP: ?" regardless of
# $_HI_IP_HIDE, which still contains "IP:" and fails this for a reason that
# has nothing to do with the hiding this test means to check.
function test_header_omits_the_ip_cell_when_hidden() {
  local dir="$_HI_WORKDIR/ip-hide-header-shims" out
  mkdir -p "$dir"
  printf '#!/bin/sh\necho "Darwin arm64"\n' >"$dir/uname"
  printf '#!/bin/sh\nprintf "\tinet 127.0.0.1 netmask 0xff000000\n\tinet 10.0.0.5 netmask 0xffffff00\n"\n' >"$dir/ifconfig"
  chmod +x "$dir/uname" "$dir/ifconfig"
  # shellcheck disable=SC2016 # the probe expands in the child bash, not here
  out="$(_hi_platform_header "$dir" 'hi_header Connected' _HI_HEADER_ORDER='utc ip' _HI_IP_HIDE='*')"
  [[ "$out" == *"Connected"* && "$out" == *" UTC"* && "$out" != *"IP:"* ]] || {
    _hi_cecho " | got: $out" "$RED"
    return 1
  }
}

function test_uptime_and_ip_cells_on_windows() {
  local out
  # shellcheck disable=SC2016 # the probe expands in the child bash, not here
  out="$(_hi_platform_header "$(_hi_windows_shims)" '_hi_cell_uptime u; _hi_cell_ip i; printf "%s\n%s\n" "$u" "$i"')"
  # no sysctl on git-bash: uptime is not probed at all; ipconfig's CR is gone
  [[ "$out" == *"Up: ?"* && "$out" == *"IP: 10.0.0.5"* && "$out" != *$'\r'* ]] || {
    _hi_cecho " | got: $out" "$RED"
    return 1
  }
}

# no uname and no /etc/os-release: nothing says what this box is, and the
# cells say "?" rather than guessing at macOS
function test_system_info_with_no_kernel_and_no_release_says_unknown() {
  local out
  out="$(_hi_platform_header "$(_hi_fake_path no-kernel-tools true)" "$_HI_ROW_FNS; _hi_sysinfo_row")"
  [[ "$out" == *"?"* && "$out" != *"macOS"* ]] && ! grep -qE "$_HI_SHELL_ERROR_RE" <<<"$out"
}

# --- the row painter's two width-neutral switches -----------------------

# $_HI_DISABLE_LEAD_SPACE drops the leading space and only that: the " | " between
# cells stays, on a header row and on the packages check's own rows
function test_no_lead_space_drops_only_the_leading_space() {
  local out
  out="$(NO_COLOR=1 _HI_DISABLE_LEAD_SPACE=1 bash -c 'source "$_HI_HEADER"; header_row alpha beta')"
  # matched by shape, not in full: the row is padded out to its right edge now,
  # and the width that pad answers to is the terminal's. What this case is
  # about is the two ends - no leading space, and the " | " between the cells
  # kept - so it pins those and the closing pipe.
  # the pad still budgets for the leading space this toggle drops, so the
  # closed row lands one column short of the banner rather than at it - a
  # pre-existing wrinkle of the toggle, not this case's concern
  [[ "$out" == "| alpha | beta"*"|" ]] && [ "${#out}" -eq 79 ] || {
    _hi_cecho " | got: [$out]" "$RED"
    return 1
  }
  out="$(NO_COLOR=1 bash -c 'source "$_HI_HEADER"; header_row alpha beta')"
  [[ "$out" == " | alpha | beta"*"|" ]] && [ "${#out}" -eq 80 ]
}

function test_no_lead_space_applies_to_the_packages_check() {
  local out
  mkdir -p "$_HI_WORKDIR/pkgcfg"
  printf '%s\n' "$_HI_REAL_CMD" >"$_HI_WORKDIR/pkgcfg/packages"
  out="$(NO_COLOR=1 _HI_DISABLE_LEAD_SPACE=1 _HI_CONFIG_DIR="$_HI_WORKDIR/pkgcfg" bash -c 'source "$_HI_HEADER"; full_check')"
  [[ "$out" == "|"* && "$out" == *"$_HI_REAL_CMD"* ]]
}

# a row with nothing to place still ends the line: hi_header's own loop
# relies on the reset-and-newline to close whatever color a prior cell left
function test_header_row_with_no_cells_prints_a_bare_line() {
  local out
  out="$(NO_COLOR=1 bash -c 'source "$_HI_HEADER"; header_row; printf END')"
  [ "$out" = $'\nEND' ]
}

# a git identity has to exist to be masked; none at all is its own text
function test_identity_without_a_git_email_says_so() {
  local out
  out="$(cd "$_HI_WORKDIR" && NO_COLOR=1 \
    PATH="$(_hi_identity_path)" _HI_TARGETS_TTL=0 bash -c "source \"\$_HI_HEADER\"; $_HI_ROW_FNS; _hi_identity_row")"
  [[ "$out" == *"No Git ID Found"* ]]
}

# ...and one that exists shows its local part, the domain a run of mask
# glyphs exactly as long (`*` under _HI_ASCII=1), never the domain itself
function test_identity_masks_the_git_email_domain() {
  local cfg="$_HI_WORKDIR/gitconfig-email" out
  printf '[user]\n\temail = alice@example.com\n' >"$cfg"
  out="$(cd "$_HI_WORKDIR" && NO_COLOR=1 _HI_ASCII=1 GIT_CONFIG_GLOBAL="$cfg" \
    PATH="$(_hi_identity_path)" _HI_TARGETS_TTL=0 bash -c "source \"\$_HI_HEADER\"; $_HI_ROW_FNS; _hi_identity_row")"
  [[ "$out" == *'alice@***********'[!*]* && "$out" != *example.com* ]] || {
    _hi_cecho "   identity row: $out" "$RED"
    return 1
  }
}

# the alternate-hue table's two ends: a word with an entry, and one without,
# which reads empty so the caller keeps the primary rather than a stray code
function test_header_word_alt_is_empty_for_an_unknown_word() {
  local v=set
  _hi_header_word_alt no-such-word v
  [ -z "$v" ] || return 1
  _hi_header_word_alt uptime v
  [ "$v" = "$BRGREEN" ]
}

# _hi_cell_hue: the leading escape's hue digit (1 red .. 6 cyan), ignoring
# the bold bit, empty with no leading escape.
function test_hi_cell_hue_reads_the_leading_escape() {
  local h
  _hi_cell_hue h "${CYAN}x"
  [ "$h" = 6 ]
}

# shellcheck disable=SC2153 # $BRCYAN is core.sh's palette variable; `brcyan`
# below is this case's own local, not a misspelling of it
function test_hi_cell_hue_ignores_the_bold_bit() {
  local cyan brcyan blue
  _hi_cell_hue cyan "${CYAN}x"
  _hi_cell_hue brcyan "${BRCYAN}x"
  _hi_cell_hue blue "${BLUE}x"
  [ "$cyan" = "$brcyan" ] && [ "$cyan" != "$blue" ]
}

# NO_COLOR blanks the whole palette (core.sh), so a cell like $_HI_SI_OS is
# then bare text - the trap an unvalidated `${cell%%m*}` would fall into,
# reading a stray "m" out of plain text as a color
function test_hi_cell_hue_is_empty_without_an_escape() {
  local h
  _hi_cell_hue h "macOS 15.1"
  [ -z "$h" ]
}

# under a scheme the escape runs on past the slot digit (HI.50); the digit is
# still the hue, and text is still not
function test_hi_cell_hue_reads_a_truecolor_escape() {
  local h
  _hi_cell_hue h '\e[1;36;38;2;107;215;202mIP: x'
  [ "$h" = 6 ] || return 1
  _hi_cell_hue h '\e[0;33;38;2;249;226;175mUp: 1h'
  [ "$h" = 3 ] || return 1
  _hi_cell_hue h 'RAM: \e[0;33;38;2;1;2;3m6G'
  [ -z "$h" ]
}

function test_header_hues_never_repeat_under_a_scheme() {
  local ok=0
  (
    # shellcheck disable=SC2030,SC2031 # the scheme lives and dies in this subshell
    export _HI_COLOR_SCHEME=vscode _HI_TRUECOLOR=1
    _hi_assign_palette
    _hi_packages_palette
    test_header_hues_never_repeat_in_the_default_order
  ) && ok=1
  [ "$ok" = 1 ]
}

function test_hi_cell_hue_ignores_a_non_leading_escape() {
  local h
  _hi_cell_hue h "RAM: ${CYAN}6/60G"
  [ -z "$h" ]
}

# The correctness argument for skipping a ring-walk fallback: a substitution
# only fires when the previous cell's hue equals the current word's primary
# hue, so as long as every word's alternate has a *different* hue than its
# own primary, the substitution can never itself collide. This is the
# mechanical check of that property - the one thing that actually has to
# stay true as header words are added. GLOSSARY: HI.48
function test_header_word_alt_differs_from_its_own_primary() {
  local words w cell primary_hue alt alt_hue
  words="${_HI_HEADER_ORDER_DEFAULT% check}"
  for w in $words; do
    cell=""
    _hi_header_word_cell "$w" cell
    [ -n "$cell" ] || continue
    primary_hue=""
    _hi_cell_hue primary_hue "$cell"
    [ -n "$primary_hue" ] || continue
    alt=""
    _hi_header_word_alt "$w" alt
    alt_hue=""
    _hi_cell_hue alt_hue "${alt}x"
    [ -n "$alt_hue" ] && [ "$alt_hue" != "$primary_hue" ] || return 1
  done
}

function test_header_word_alt_is_defined_for_every_order_word() {
  local words w alt
  words="${_HI_HEADER_ORDER_DEFAULT% check}"
  for w in $words; do
    alt=""
    _hi_header_word_alt "$w" alt
    [ -n "$alt" ] || return 1
  done
}

# <var> gets $2's leading `\e[<bold>;3<n>m` escape, or "" when there is none.
# The same anchored, validated match _hi_cell_hue and _hi_collect_header_word
# use (common/header.sh) - the palette stores a literal `\e`, not
# an ESC byte, and an unanchored cut would read a stray "m" out of plain text.
function _hi_lead_escape() {
  local s="$2" re='^(\\e\[[01];3[1-6]m)'
  printf -v "$1" '%s' ""
  [[ "$s" =~ $re ]] && printf -v "$1" '%s' "${BASH_REMATCH[1]}"
}

# The default order is the actual bug report: today's word list should never
# need its own resolver - every cell's *color* should come out exactly as
# _hi_header_word_cell renders it on its own, unresolved. This is the case
# that would have caught the shipped jobs/pods collision. Compared by leading
# escape, not the whole cell: utc/localtime re-render with `%S`
# (common/header.sh's _hi_cell_clock), so a byte-exact compare fails on a second tick
# between the two passes below rather than on an actual substitution.
function test_header_default_order_needs_no_alternate() {
  local words w raw want got i=0
  local -a _HI_PENDING_CELLS=()
  local _HI_PREV_HUE=""
  words="${_HI_HEADER_ORDER_DEFAULT% check}"
  for w in $words; do _hi_collect_header_word "$w"; done
  for w in $words; do
    raw=""
    _hi_header_word_cell "$w" raw
    [ -n "$raw" ] || continue
    _hi_lead_escape want "$raw"
    _hi_lead_escape got "${_HI_PENDING_CELLS[$i]}"
    [ "$got" = "$want" ] || return 1
    i=$((i + 1))
  done
}

function test_header_hues_never_repeat_in_the_default_order() {
  local words w cell hue prev=""
  local -a _HI_PENDING_CELLS=()
  local _HI_PREV_HUE=""
  words="${_HI_HEADER_ORDER_DEFAULT% check}"
  for w in $words; do _hi_collect_header_word "$w"; done
  for cell in "${_HI_PENDING_CELLS[@]}"; do
    hue=""
    _hi_cell_hue hue "$cell"
    [ -n "$hue" ] || continue
    [ "$hue" = "$prev" ] && return 1
    prev="$hue"
  done
}

# A worst case no real order would ship: every word the same hue (utc, cpu,
# and uptime are all $BRBLUE), forcing the resolver to actually work rather
# than coasting on Part C's already-clean default.
function test_header_hues_never_repeat_in_a_pathological_order() {
  local words="utc utc cpu uptime" w cell hue prev=""
  local -a _HI_PENDING_CELLS=()
  local _HI_PREV_HUE=""
  for w in $words; do _hi_collect_header_word "$w"; done
  for cell in "${_HI_PENDING_CELLS[@]}"; do
    hue=""
    _hi_cell_hue hue "$cell"
    [ -n "$hue" ] || continue
    [ "$hue" = "$prev" ] && return 1
    prev="$hue"
  done
}

# containers/jobs/pods render only when their own backend answered, so any
# subset of the trio has to read right on its own - three distinct families,
# not just "not identical to the immediate neighbor"
function test_header_backend_trio_hues_are_three_families() {
  local out d_dir n_dir k_dir path
  d_dir="$(_hi_backend_shim docker 1)" d_dir="${d_dir%%:*}"
  n_dir="$(_hi_backend_shim nomad 1)" n_dir="${n_dir%%:*}"
  k_dir="$(_hi_kube_shim 1)" k_dir="${k_dir%%:*}"
  path="$d_dir:$n_dir:$k_dir:$(_hi_identity_path)"
  out="$(PATH="$path" _HI_TARGETS_TTL=0 bash -c '
    source "$_HI_HEADER"
    _hi_identity_probe
    printf "%s\n%s\n%s\n" "$_HI_ID_CONTAINERS" "$_HI_ID_JOBS" "$_HI_ID_PODS"')"
  local containers jobs pods hc hj hp
  containers="$(sed -n 1p <<<"$out")"
  jobs="$(sed -n 2p <<<"$out")"
  pods="$(sed -n 3p <<<"$out")"
  _hi_cell_hue hc "$containers"
  _hi_cell_hue hj "$jobs"
  _hi_cell_hue hp "$pods"
  [ -n "$hc" ] && [ -n "$hj" ] && [ -n "$hp" ] &&
    [ "$hc" != "$hj" ] && [ "$hc" != "$hp" ] && [ "$hj" != "$hp" ]
}

# Under NO_COLOR every color var is blank (core.sh), so _hi_cell_hue reads
# nothing on any cell and the resolver has nothing to compare - the whole
# header comes out with zero escape sequences.
function test_header_hues_are_inert_under_no_color() {
  local out
  out="$(NO_COLOR=1 PATH="$(_hi_identity_path)" _HI_TARGETS_TTL=0 \
    bash -c 'source "$_HI_HEADER"; hi_header Online' 2>&1)"
  [[ "$out" != *$'\e['* ]]
}

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

# _hi_pos <haystack> <needle> - the byte offset of the first match, or empty
# if absent; prefix-stripping rather than a fork, for the row-order tests
# below, which only care which of several markers comes first.
function _hi_pos() {
  case "$1" in
  *"$2"*)
    local before="${1%%"$2"*}"
    printf '%s' "${#before}"
    ;;
  esac
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
  _hi_one_visible_row "$_HI_REAL_CMD" 3 || return 1
  _hi_row_is 3 "${_HI_YES[3]}" "$_HI_REAL_CMD" "$GREEN$_HI_MARK_OK"
}

# ...installed only as a later alternative: that alternative's name, with ~
function test_check_line_installed_alternative_is_tilded() {
  local row
  _hi_one_visible_row "$_HI_FAKE_CMD,$_HI_REAL_CMD" 2 || return 1
  _hi_row_is 2 "${_HI_YES[2]}" "$_HI_REAL_CMD" "$YELLOW$_HI_MARK_ALT$NC"
}

# ...nothing installed: the first name, crossed, in the tier's missing color
function test_check_line_missing_shows_the_first_name_crossed() {
  local row
  _hi_one_visible_row "$_HI_FAKE_CMD,${_HI_FAKE_CMD}-alt" 0 || return 1
  _hi_row_is 0 "${_HI_NO[0]}" "$_HI_FAKE_CMD" "$RED$_HI_MARK_NO"
}

# ...and with no tier argument the row paints and ranks at tier 1
function test_check_line_tier_defaults_to_one() {
  local row
  _hi_one_visible_row "$_HI_FAKE_CMD" || return 1
  _hi_row_is 1 "${_HI_NO[1]}" "$_HI_FAKE_CMD" "$RED$_HI_MARK_NO"
}

# The first installed alternative wins, whatever follows it: the list is an
# order of preference, not a ranking to search
function test_check_line_first_installed_alternative_wins() {
  local row
  _hi_one_visible_row "$_HI_REAL_CMD,bash" 1 || return 1
  _hi_row_is 1 "${_HI_YES[1]}" "$_HI_REAL_CMD" "$GREEN$_HI_MARK_OK"
}

# `-` unwanted, installed: a warning at rank 4 in the loudest missing color,
# whatever the group's tier, with the marker stripped from the name
function test_check_line_unwanted_installed_warns() {
  local row
  _hi_one_visible_row "-$_HI_REAL_CMD" 0 || return 1
  _hi_row_is 4 "${_HI_NO[3]}" "$_HI_REAL_CMD" "$YELLOW$_HI_MARK_WARN$NC"
}

# ...and an alternative counts: the warning names the one installed
function test_check_line_unwanted_alternative_installed_warns() {
  local row
  _hi_one_visible_row "-$_HI_FAKE_CMD,$_HI_REAL_CMD" 2 || return 1
  _hi_row_is 4 "${_HI_NO[3]}" "$_HI_REAL_CMD" "$YELLOW$_HI_MARK_WARN$NC"
}

# `+` required, missing: an alarm at rank 4 in the loudest missing color,
# whatever the group's tier, with the marker stripped from the name
function test_check_line_required_missing_alarms() {
  local row
  _hi_one_visible_row "+$_HI_FAKE_CMD" 0 || return 1
  _hi_row_is 4 "${_HI_NO[3]}" "$_HI_FAKE_CMD" "$RED$_HI_MARK_NO"
}

function test_full_check_skips_comments_and_blanks() {
  (
    _HI_PACKAGES="$(_hi_pkg_one comments "# a comment\n\n$_HI_REAL_CMD\n")"
    full_check
  ) | grep -qF "$_HI_REAL_CMD"
}

# the two rows with nothing to say - an absent `-` row, an installed `+` row -
# leave the check empty, not a bare line
function test_full_check_empty_when_everything_is_silent() {
  local out
  out="$(
    _HI_PACKAGES="$(_hi_pkg_one silent "-$_HI_FAKE_CMD\n+$_HI_REAL_CMD\n")"
    full_check
  )"
  [ -z "$out" ]
}

# _hi_group_tier: the named groups' tiers, and 1 for any other name
function test_group_tier_maps_names_to_tiers() {
  local spec t
  for spec in core=3 base=3 deprecated=3 useful=2 trivia=0 platform=0 \
    extras=1 mine=1 cores=1; do
    _hi_group_tier t "${spec%=*}"
    [ "$t" = "${spec#*=}" ] || return 1
  done
}

# _hi_group_on: whole names out of a space- or comma-separated list, unset
# meaning the shipped default and `none` naming nothing
function test_group_on_reads_the_list() {
  (
    unset _HI_PACKAGES_GROUPS
    _hi_group_on core && _hi_group_on useful && _hi_group_on deprecated || exit 1
    ! _hi_group_on extras || exit 1
    _HI_PACKAGES_GROUPS="alpha,beta gamma"
    _hi_group_on alpha && _hi_group_on beta && _hi_group_on gamma || exit 1
    # a whole-word match: neither a prefix nor an extension of a listed name
    ! _hi_group_on alp && ! _hi_group_on alphas || exit 1
    _HI_PACKAGES_GROUPS=none
    ! _hi_group_on core || exit 1
    # `none` is the setting's word, never a group of its own
    ! _hi_group_on none || exit 1
    _HI_PACKAGES_GROUPS="none core"
    ! _hi_group_on none
  )
}

# _hi_package_groups: the `[...]` lines in file order, a line with a # skipped
# the way full_check skips it
function test_package_groups_lists_sections_in_file_order() {
  local got
  _HI_PACKAGES="$(_hi_pkg_one list-groups "top\n[beta]\nx\n#[gone]\n[alpha] # c\n[alpha]\n")" \
    _hi_package_groups got
  [ "$got" = "beta alpha" ]
}

# A group $_HI_PACKAGES_GROUPS leaves out prints nothing, however installed its
# rows are; the one it names prints. Both installed, so only the group
# separates them.
function test_full_check_runs_only_the_named_groups() {
  local out
  out="$(
    _HI_PACKAGES="$(_hi_pkg_one groups-one "[alpha]\n$_HI_REAL_CMD\n[beta]\nbash\n")"
    _HI_PACKAGES_GROUPS=alpha
    full_check
  )"
  _hi_contains "$out" " $_HI_REAL_CMD " || return 1
  case "$out" in *bash*) return 1 ;; esac
  return 0
}

# ...a comma-separated list runs each group it names
function test_full_check_reads_a_comma_separated_list() {
  local out
  out="$(
    _HI_PACKAGES="$(_hi_pkg_one groups-comma "[alpha]\n$_HI_REAL_CMD\n[beta]\nbash\n")"
    _HI_PACKAGES_GROUPS=alpha,beta
    full_check
  )"
  _hi_contains "$out" " $_HI_REAL_CMD " && _hi_contains "$out" " bash "
}

# ...unset runs the shipped default, core useful deprecated, and no other
function test_full_check_unset_runs_the_default_groups() {
  local out
  out="$(
    _HI_PACKAGES="$(_hi_pkg_one groups-default "[core]\nsh\n[useful]\nls\n[deprecated]\n-cat\n[extras]\nbash\n")"
    unset _HI_PACKAGES_GROUPS
    full_check
  )"
  _hi_contains "$out" " sh " && _hi_contains "$out" " ls " &&
    _hi_contains "$out" " cat " || return 1
  case "$out" in *bash*) return 1 ;; esac
  return 0
}

# a hand-written [none] section is not run by the word that turns groups off
function test_full_check_none_is_not_a_group() {
  local out
  out="$(
    _HI_PACKAGES="$(_hi_pkg_one groups-none-section "[none]\n$_HI_REAL_CMD\n")"
    _HI_PACKAGES_GROUPS=none
    full_check
  )"
  [ -z "$out" ]
}

# `none` turns every group off, but rows above the first `[group]` line
# always run
function test_full_check_none_keeps_the_ungrouped_rows() {
  local out
  out="$(
    _HI_PACKAGES="$(_hi_pkg_one groups-none "$_HI_REAL_CMD\n[alpha]\nbash\n")"
    _HI_PACKAGES_GROUPS=none
    full_check
  )"
  _hi_contains "$out" " $_HI_REAL_CMD " || return 1
  case "$out" in *bash*) return 1 ;; esac
  return 0
}

function test_full_check_wraps_at_max_width() {
  local out lines
  out="$(
    _HI_PACKAGES="$(_hi_pkg_one wrap "$_HI_REAL_CMD\nbash\n")"
    _HI_MAX_WIDTH=1
    full_check
  )"
  lines="$(printf '%s\n' "$out" | grep -c .)"
  [ "$lines" -ge 2 ]
}

function test_full_check_reads_real_packages_file_without_erroring() {
  full_check >/dev/null
}

# full_check's own wrap loop, not _hi_row_line's - it needs the same closing
# column, on every wrapped line including the last. bash is a second real
# command, the wrap case above leans on it the same way.
function test_full_check_closes_every_row_at_max_width() {
  local out lines
  out="$(
    _HI_PACKAGES="$(_hi_pkg_one close "$_HI_REAL_CMD\nbash\n")"
    _HI_MAX_WIDTH=12
    full_check
  )"
  lines="$(printf '%s\n' "$out" | grep -c .)"
  [ "$lines" -ge 2 ] && _hi_all_lines_are "$out" 12
}

# the carry rides in full_check's own edge too - the path that lost it before
# full_check grew a closing arm of its own
function test_full_check_closes_a_row_that_absorbed_a_carry() {
  local out
  local -a _HI_ROW_CARRY=(carriedcell)
  out="$(
    _HI_PACKAGES="$(_hi_pkg_one close-carry "$_HI_REAL_CMD\nbash\n")"
    _HI_MAX_WIDTH=20
    full_check
  )"
  _hi_all_lines_are "$out" 20
}

function test_full_check_right_edge_disabled_stays_under_max_width() {
  local out line n
  out="$(
    _HI_PACKAGES="$(_hi_pkg_one no-edge "$_HI_REAL_CMD\nbash\n")"
    _HI_MAX_WIDTH=20
    _HI_DISABLE_RIGHT_EDGE=1
    full_check
  )"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    [[ "$(_hi_strip_ansi "$line")" != *"|" ]] || return 1
    _hi_visible_width n "$(_hi_strip_ansi "$line")"
    ((n < 20)) || return 1
  done <<<"$out"
}

# full_check is the cascade's landing point: it absorbs an incoming
# $_HI_ROW_CARRY as its own first cells, ahead of the packages it reads
# itself, rather than leaving it for a caller that has nowhere left to send
# it. `local -a _HI_ROW_CARRY` shadows the global the same way other cases in
# this file shadow $_HI_HEADER_VERSION, and the call is not wrapped in
# $(...) where inspecting its post-call state is needed.
function test_full_check_absorbs_an_incoming_carry() {
  local out
  local -a _HI_ROW_CARRY=(carriedcell)
  out="$(_HI_PACKAGES="$(_hi_pkg_one carry-absorb "$_HI_REAL_CMD\n")" full_check)"
  [[ "$out" == *carriedcell* ]] && [[ "$out" == *"$_HI_REAL_CMD"* ]] &&
    [ -n "$(_hi_pos "$out" carriedcell)" ] && [ -n "$(_hi_pos "$out" "$_HI_REAL_CMD")" ] &&
    [ "$(_hi_pos "$out" carriedcell)" -lt "$(_hi_pos "$out" "$_HI_REAL_CMD")" ]
}

# ...and takes ownership of it: nothing is left for a caller after it to
# flush a second time.
function test_full_check_consumes_the_carry() {
  local -a _HI_ROW_CARRY=(carriedcell)
  _HI_PACKAGES="$(_hi_pkg_one carry-consume "$_HI_REAL_CMD\n")" full_check >/dev/null
  [ "${#_HI_ROW_CARRY[@]}" -eq 0 ]
}

# a carry still has to print even when the packages file itself yields
# nothing visible - full_check must not return the moment $visible is
# empty, before it considers its second source
function test_full_check_prints_carry_even_with_no_visible_packages() {
  local out
  local -a _HI_ROW_CARRY=(onlycell)
  out="$(_HI_PACKAGES="$(_hi_pkg_one carry-no-packages "")" full_check)"
  [[ "$out" == *onlycell* ]]
}

# ...and the original guard still holds with nothing on either side
function test_full_check_empty_carry_and_no_packages_prints_nothing() {
  local out
  local -a _HI_ROW_CARRY=()
  out="$(_HI_PACKAGES="$(_hi_pkg_one carry-empty-none "")" full_check)"
  [ -z "$out" ]
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
  local out
  out="$(
    _HI_PACKAGES="$(_hi_pkg_one emits "$_HI_REAL_CMD\n")"
    full_check
  )"
  [[ "$out" == *"$_HI_REAL_CMD"* ]]
}

# Highest tier first, and file order within one - one pass per rank, no sort:
# ls (core, 3) prints ahead of sh (useful, 2) ahead of cat (extras, 1),
# though the file lists them the other way round
function test_full_check_orders_by_tier_then_file_order() {
  local out
  out="$(
    _HI_PACKAGES="$(_hi_pkg_one rank-order "[extras]\ncat\n[useful]\nsh\n[core]\nls\n")"
    _HI_PACKAGES_GROUPS="extras useful core"
    full_check
  )"
  [ -n "$(_hi_pos "$out" " cat ")" ] && [ -n "$(_hi_pos "$out" " ls ")" ] &&
    [ -n "$(_hi_pos "$out" " sh ")" ] || return 1
  [ "$(_hi_pos "$out" " ls ")" -lt "$(_hi_pos "$out" " sh ")" ] &&
    [ "$(_hi_pos "$out" " sh ")" -lt "$(_hi_pos "$out" " cat ")" ]
}

# Warnings and alarms (rank 4) lead even a core row listed before them, in
# file order between themselves
function test_full_check_sorts_warnings_and_alarms_first() {
  local out w a c
  out="$(
    _HI_PACKAGES="$(_hi_pkg_one warn-first "[core]\nls\n[extras]\n-$_HI_REAL_CMD\n+$_HI_FAKE_CMD\n")"
    _HI_PACKAGES_GROUPS="core extras"
    full_check
  )"
  w="$(_hi_pos "$out" " $_HI_REAL_CMD ")" a="$(_hi_pos "$out" " $_HI_FAKE_CMD ")"
  c="$(_hi_pos "$out" " ls ")"
  [ -n "$w" ] && [ -n "$a" ] && [ -n "$c" ] && ((w < a && a < c))
}

# $_HI_PACKAGES naming no file prints nothing, and says nothing on stderr -
# the check has no rows, not a failure to report
function test_full_check_with_no_file_prints_nothing() {
  local out
  out="$(_HI_PACKAGES="$_HI_WORKDIR/no-such-packages" full_check 2>&1)"
  [ -z "$out" ]
}

# _hi_packages_palette's contract: exactly four entries - one per tier
# 0-3 - in both tables, whichever ramp is in force. `VAR=val func` on a shell
# function (not an external command) reverts VAR once the call returns, so
# this leaves no _HI_PACKAGES_PALETTE behind for a case after it.
function test_packages_palette_fills_four_slots_each_way() {
  unset _HI_PACKAGES_PALETTE
  _hi_packages_palette
  [ "${#_HI_YES[@]}" -eq 4 ] && [ "${#_HI_NO[@]}" -eq 4 ] || return 1
  _HI_PACKAGES_PALETTE="$_HI_TEST_RAMP" _hi_packages_palette
  [ "${#_HI_YES[@]}" -eq 4 ] && [ "${#_HI_NO[@]}" -eq 4 ]
}

# eight names of the user's own become the two tables verbatim, in order:
# the first four installed, the last four missing
function test_packages_palette_takes_a_ramp_verbatim() {
  _HI_PACKAGES_PALETTE="$_HI_TEST_RAMP" _hi_packages_palette
  [ "${_HI_YES_NAMES[*]} ${_HI_NO_NAMES[*]}" = "$_HI_TEST_RAMP" ]
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
    [ "${_HI_YES[*]}" = "${shipped_yes[*]}" ] && [ "${_HI_NO[*]}" = "${shipped_no[*]}" ] || return 1
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
  [ "${_HI_YES_NAMES[*]} ${_HI_NO_NAMES[*]}" = "$_HI_PACKAGES_RAMP" ] || return 1
  for entry in "${_HI_YES_NAMES[@]}" "${_HI_NO_NAMES[@]}"; do
    found=""
    for candidate in "${_HI_COLOR_NAMES[@]}"; do
      [ "$candidate" = "$entry" ] && found=1 && break
    done
    [ -n "$found" ] || return 1
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
  [ "$ok" = 1 ]
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
  [ "$ok" = 1 ]
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
  [ "$ok" = 1 ]
}

function test_header_hues_never_repeat_under_a_24_word_scheme() {
  local ok=0
  (
    # shellcheck disable=SC2030,SC2031 # the scheme lives and dies in this subshell
    export _HI_COLOR_SCHEME="$_HI_TEST_L48" _HI_TRUECOLOR=1
    _hi_assign_palette
    _hi_packages_palette
    test_header_hues_never_repeat_in_the_default_order
  ) && ok=1
  [ "$ok" = 1 ]
}

function run_header_tests() {
  _hi_workdir headertest

  _hi_h1 "Testing common/header.sh"

  _hi_suite_begin

  _hi_h2 "Testing: header_row"
  _hi_check "Joins multiple cells" test_header_row_joins_cells
  _hi_check "Handles a single cell" test_header_row_single_cell
  _hi_check "Default width stays one line" test_header_row_default_width_stays_one_line
  _hi_check "Wraps at a narrow _HI_MAX_WIDTH" test_header_row_wraps_at_max_width
  _hi_check "Wrap keeps every cell intact" test_header_row_wrap_keeps_cells_intact
  _hi_check "_hi_visible_width strips a leading color" test_hi_visible_width_strips_a_leading_color
  _hi_check "...plain text is unchanged" test_hi_visible_width_plain_text_unchanged
  _hi_check "...and a glyph counts one column, not three bytes" test_hi_visible_width_counts_columns_not_bytes
  _hi_check "...on a shell whose \${#} answers in bytes too" test_hi_visible_width_counts_columns_where_length_counts_bytes
  _hi_check "Wrap math ignores color escape bytes" test_header_row_width_ignores_color_escape_bytes
  _hi_check "_hi_draw_width defaults to _HI_MAX_WIDTH when captured" test_hi_draw_width_defaults_to_max_width_when_captured
  _hi_check "_hi_draw_width honors an explicit _HI_TERM_COLS override" test_hi_draw_width_honors_an_explicit_override
  _hi_check "_hi_draw_width never widens past _HI_MAX_WIDTH" test_hi_draw_width_never_widens_past_max_width
  _hi_check "Wraps at a _HI_TERM_COLS override" test_header_row_wraps_at_hi_term_cols_override
  _hi_check "Armed, overflow carries to the next call" test_header_row_armed_carries_overflow_to_the_next_call
  _hi_check "...and opens the next row" test_header_row_armed_carry_opens_the_next_row
  _hi_check "Unarmed, a row leaves no carry behind" test_header_row_unarmed_leaves_no_carry_behind
  _hi_check "Zero cells: returns 1, prints nothing" test_row_line_returns_1_and_prints_nothing_for_zero_cells
  _hi_check "_hi_header_flush drains multiple overflow rounds" test_header_flush_drains_across_multiple_overflow_rounds

  _hi_h2 "Testing: the right edge"
  _hi_check "header_row closes at the default width" test_header_row_closes_at_default_width
  _hi_check "...and at a narrow _HI_MAX_WIDTH" test_header_row_closes_at_narrow_width
  _hi_check "...on every wrapped line, not just the first" test_header_row_closes_every_wrapped_line
  _hi_check "_HI_DISABLE_RIGHT_EDGE gives back the open row" test_disable_right_edge_gives_back_the_open_row
  _hi_check_requires bash "full_check closes every row too" test_full_check_closes_every_row_at_max_width
  _hi_check_requires bash "...including one that absorbed a carry" test_full_check_closes_a_row_that_absorbed_a_carry
  _hi_check_requires bash "...and stays open under the toggle" test_full_check_right_edge_disabled_stays_under_max_width
  _hi_check_requires bash "A real hi_header render closes every line, banner included" test_hi_header_closes_every_line
  _hi_check "So does hi_footer's" test_hi_footer_closes_every_line

  _hi_h2 "Testing: banner"
  _hi_check "Includes label and hostname" test_banner_includes_label_and_host
  _hi_check "A longer prefix shrinks the padding" test_banner_prefix_shrinks_padding
  _hi_check "Floors padding on a long hostname" test_banner_floors_padding_on_a_long_hostname
  _hi_check "Floors tilde padding on a pathologically long label" test_banner_floors_tildes_on_long_label
  _hi_check "Survives a narrow _HI_MAX_WIDTH" test_banner_narrow_width_does_not_error
  _hi_check "ASCII fallback swaps the arrow" test_banner_ascii_fallback_uses_caret
  _hi_check "...and the marks with it" test_marks_swap_to_ascii_with_the_set
  _hi_check "No output when _HI_DISABLE_BANNER=1" test_banner_disabled_produces_no_output
  _hi_check "Still prints when the toggle is unset" test_banner_prints_when_toggle_unset
  _hi_check "Change count is computed once per session" test_banner_change_count_is_computed_once
  _hi_check "No count without a .git dir" test_banner_omits_the_count_without_a_git_dir
  _hi_check "Online names an off-main branch" test_banner_online_names_an_off_main_branch
  _hi_check "Online stays quiet on main" test_banner_online_stays_quiet_on_main
  _hi_check "Online stays quiet when detached" test_banner_online_stays_quiet_when_detached
  _hi_check "Branch stays out of Connected/Disconnected" test_banner_branch_stays_out_of_remote_banners
  _hi_check "Branch spends tilde budget, not width" test_banner_branch_shrinks_padding

  _hi_h2 "Testing: timestamp / sysinfo / identity rows (smoke tests)"
  _hi_check "Timestamp prints three cells" test_timestamp_runs_and_has_three_cells
  _hi_check "The version sits between the clocks" test_timestamp_puts_the_version_between_the_clocks
  _hi_check "Without a stamp the version still resolves" test_timestamp_version_falls_back_without_a_stamp
  _hi_check "_hi_header_version resolves once per shell" test_header_version_resolves_once_per_shell
  # _hi_shorten_describe's own contract - not exactly on a tag (commits ahead,
  # or no tag reachable at all) means it isn't a release, so only a 6-column
  # commit hash shows, tag dropped rather than implied; a tag with no hash (an
  # exact tag, a plain $_HI_RELEASE, "unknown") is a release and shows as-is,
  # truncated to 10 since there's nothing to join it to
  _hi_check_eq "Shows a 6-char hash when not on a tag" 9c1dd0 _hi_shorten_describe v1.0.0-5-g9c1dd0f
  _hi_check_eq "...drops the -dirty suffix" 9c1dd0 _hi_shorten_describe v1.0.0-5-g9c1dd0f-dirty
  _hi_check_eq "...trims a bare hash too" 9c1dd0 _hi_shorten_describe 9c1dd0fabc
  _hi_check_eq "...leaves an exact tag alone" v1.0.0 _hi_shorten_describe v1.0.0
  _hi_check_eq "...leaves a release stamp alone" 1.2.3 _hi_shorten_describe 1.2.3
  _hi_check_eq "...leaves 'unknown' alone" unknown _hi_shorten_describe unknown
  _hi_check_eq "...caps a long exact tag at 10 columns" snapshot-6 _hi_shorten_describe snapshot-6fba937
  _hi_check_eq "...drops a long tag when a hash is present" 200cef _hi_shorten_describe snapshot-6fba937-1-g200cef5-dirty
  _hi_check "The version cell itself is shortened" test_timestamp_version_cell_is_shortened
  _hi_check "System_info includes its static labels" test_system_info_includes_static_labels
  _hi_check "System_info does not show uptime" test_system_info_does_not_show_uptime
  _hi_check "System_info's CPU cell renders GHz" test_system_info_cpu_cell_is_ghz
  _hi_check "System_info's CPU cell sits next to Cores:" test_system_info_cpu_cell_sits_next_to_cores
  _hi_check "_hi_ghz rounds the carry into the whole digit" test_ghz_rounds_the_carry_into_the_whole_digit
  _hi_check "_hi_load_pct divides load by cores" test_hi_load_pct_divides_load_by_cores
  _hi_check_eq "...rounds to a whole percent" 33 _hi_load_pct_out 1.00 3
  _hi_check_eq "...empty without a load figure" "" _hi_load_pct_out "" 4
  _hi_check_eq "...empty without a core count" "" _hi_load_pct_out 2.00 ""
  # "?" is the Windows fallback's own unresolved sentinel - never divided
  # into, just passed straight through to the cell as "Cores: ?"
  _hi_check_eq "...empty when cores isn't numeric" "" _hi_load_pct_out 2.00 "?"
  _hi_check_eq "...empty when cores is zero" "" _hi_load_pct_out 2.00 0
  _hi_check "System_info's RAM cell is used/total" test_system_info_ram_cell_is_used_over_total
  _hi_check "System_info's load figure rides the Cores cell" test_system_info_load_rides_the_cores_cell
  _hi_check "...and the GHz cell does not carry it" test_system_info_cpu_cell_has_no_parenthetical
  _hi_check "The uptime cell is humanized" test_uptime_cell_is_humanized
  _hi_check "The ip cell has a shape" test_ip_cell_has_a_shape
  # _hi_humanize_uptime's own contract, independent of what this box's real
  # uptime happens to be
  _hi_check_eq "_hi_humanize_uptime: days and hours" "1d 1h" _hi_humanize_uptime 90000
  _hi_check_eq "_hi_humanize_uptime: hours and minutes" "1h 30m" _hi_humanize_uptime 5400
  _hi_check_eq "_hi_humanize_uptime: minutes only" 2m _hi_humanize_uptime 120
  _hi_check "Identity includes its static labels" test_identity_includes_static_labels
  _hi_check "Identity's uptime cell rides last" test_identity_includes_uptime_cell_last
  _hi_check "No cells at all when no backend is found" test_identity_hides_all_backend_cells_when_none_found
  _hi_check "Containers: 0 when docker is found but empty" test_identity_shows_count docker 0 Containers
  _hi_check "Containers count when docker is found" test_identity_shows_count docker 3 Containers
  _hi_check "Jobs: 0 when nomad is found but idle" test_identity_shows_count nomad 0 Jobs
  _hi_check "Jobs count excludes nomad's header row" test_identity_shows_count nomad 2 Jobs
  _hi_check "Pods: 0 when kube is found but empty" test_identity_shows_count kube 0 Pods
  _hi_check "Pods count when kube is found" test_identity_shows_count kube 2 Pods

  _hi_h2 "Testing: a target with no coreutils"
  _hi_check "System_info says ? without uname" test_system_info_without_uname_says_unknown
  _hi_check "System_info on a mac, from shims" test_system_info_on_a_mac
  _hi_check "Uptime and IP cells on a mac" test_uptime_and_ip_cells_on_a_mac
  _hi_check "The ip cell reads iproute2 on Linux" test_ip_cell_on_linux_reads_iproute2
  _hi_check "The ip cell falls back to hostname -I" test_ip_cell_on_linux_falls_back_to_hostname
  _hi_check "Five cells cost one probe" test_system_info_probes_once_for_all_five_cells
  _hi_check "System_info on Windows (git-bash), from shims" test_system_info_on_windows
  _hi_check "Uptime and IP cells on Windows" test_uptime_and_ip_cells_on_windows
  _hi_check "_HI_IP_HIDE hides the bridge by default" test_ip_filter_hides_the_bridge_by_default
  _hi_check "_HI_IP_HIDE none/empty keep everything" test_ip_filter_none_and_empty_keep_everything
  _hi_check "_HI_IP_HIDE takes a glob list" test_ip_filter_takes_a_glob_list
  _hi_check "The ip cell is empty when every address is hidden" test_ip_cell_is_empty_when_every_address_is_hidden
  _hi_check "The header omits a hidden ip cell" test_header_omits_the_ip_cell_when_hidden
  _hi_check "System_info with no kernel and no os-release says ?" test_system_info_with_no_kernel_and_no_release_says_unknown
  _hi_check "_HI_DISABLE_LEAD_SPACE drops only the leading space" test_no_lead_space_drops_only_the_leading_space
  _hi_check "...on the packages check too" test_no_lead_space_applies_to_the_packages_check
  _hi_check "A row with no cells prints a bare line" test_header_row_with_no_cells_prints_a_bare_line
  _hi_check "Identity without a git email says so" test_identity_without_a_git_email_says_so
  _hi_check "Identity masks a git email's domain" test_identity_masks_the_git_email_domain
  _hi_check "Alternate hue is empty for an unknown word" test_header_word_alt_is_empty_for_an_unknown_word
  _hi_check "Timestamp answers without date" test_timestamp_answers_without_date
  _hi_check "The uptime cell survives a stripped environment" test_uptime_cell_survives_a_stripped_environment
  _hi_check "The ip cell says unknown under a stripped environment" test_ip_cell_says_unknown_under_a_stripped_environment
  _hi_check "The banner still renders" test_banner_renders_without_coreutils

  _hi_h2 "Testing: hi_header"
  _hi_check "No output when disabled" test_hi_header_disabled_produces_no_output
  _hi_check "Prints the banner when enabled" test_hi_header_enabled_prints_banner
  _hi_check "Banner off still prints the detail lines" test_hi_header_banner_off_keeps_detail_lines
  _hi_check "A backend word launches the probes" test_hi_header_launches_probes_for_a_backend_word
  _hi_check "...but not once identity is memoized" test_hi_header_skips_probe_launch_once_identity_is_memoized
  _hi_check "podman probes when docker is absent" test_probe_launch_takes_podman_when_docker_is_absent
  _hi_check_capable pty "_hi_draw_width: COLUMNS, then tput, never past the max" test_draw_width_reads_columns_then_tput_under_a_tty
  _hi_check "Default feature order: timestamp, sysinfo, identity, check" test_hi_header_default_order
  _hi_check "_HI_HEADER_ORDER reorders, and omitting a feature hides it" test_hi_header_order_setting_reorders_and_can_omit
  _hi_check "An unknown order word is ignored" test_hi_header_order_ignores_an_unknown_word
  _hi_check "'uptime' is its own order word" test_hi_header_order_uptime_is_its_own_word
  _hi_check "'ip' is its own order word" test_hi_header_order_ip_is_its_own_word
  _hi_check "Omitting 'uptime' hides just that cell" test_hi_header_order_omitting_uptime_hides_just_that_cell
  _hi_check "A line's overflow cascades into the packages block" test_hi_header_cascades_identity_overflow_into_check
  _hi_check "...and still flushes when 'check' is left out" test_hi_header_flushes_leftover_when_check_is_absent
  _hi_check "Reordering across former group boundaries still packs" test_hi_header_order_packs_across_former_group_boundaries

  _hi_h2 "Testing: header cell hues"
  _hi_check "_hi_cell_hue reads the leading escape" test_hi_cell_hue_reads_the_leading_escape
  _hi_check "_hi_cell_hue ignores the bold bit" test_hi_cell_hue_ignores_the_bold_bit
  _hi_check "_hi_cell_hue is empty without an escape" test_hi_cell_hue_is_empty_without_an_escape
  _hi_check "_hi_cell_hue ignores a non-leading escape" test_hi_cell_hue_ignores_a_non_leading_escape
  _hi_check "_hi_cell_hue reads a truecolor escape" test_hi_cell_hue_reads_a_truecolor_escape
  _hi_check "Every word's alternate differs from its own primary" test_header_word_alt_differs_from_its_own_primary
  _hi_check "Every order word has an alternate defined" test_header_word_alt_is_defined_for_every_order_word
  _hi_check "The default order never needs its own alternate" test_header_default_order_needs_no_alternate
  _hi_check "No two adjacent cells share a hue in the default order" test_header_hues_never_repeat_in_the_default_order
  _hi_check "...nor under a color scheme" test_header_hues_never_repeat_under_a_scheme
  _hi_check "...nor under a 24-word scheme" test_header_hues_never_repeat_under_a_24_word_scheme
  _hi_check "...nor in a pathological same-hue order" test_header_hues_never_repeat_in_a_pathological_order
  _hi_check "containers/jobs/pods are three distinct hue families" test_header_backend_trio_hues_are_three_families
  _hi_check "Hue resolution is inert under NO_COLOR" test_header_hues_are_inert_under_no_color

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

  _hi_suite_end "header.sh"
}

run_header_tests
