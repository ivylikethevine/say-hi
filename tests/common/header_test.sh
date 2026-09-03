#!/usr/bin/env bash
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
# text still appears intact somewhere in the (now multi-line) output
function test_header_row_wrap_keeps_cells_intact() {
  local out
  out="$(_HI_MAX_WIDTH=5 header_row alpha beta gamma)"
  [[ "$out" == *alpha* && "$out" == *beta* && "$out" == *gamma* ]]
}

# _hi_visible_width's own contract: the color escape does not count
function test_hi_visible_width_strips_a_leading_color() {
  local n
  _hi_visible_width n "${GREEN}hi"
  [ "$n" -eq 2 ]
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

# _hi_shorten_describe's own contract - git describe's shapes, folded to at
# most 5 columns of tag plus a 4-column hash (10 total), -dirty always
# dropped, and a tag with no hash (an exact tag, a plain $_HI_RELEASE,
# "unknown") just truncated to 10 since there is nothing to join it to
function test_hi_shorten_describe_folds_tag_and_hash() {
  [ "$(_hi_shorten_describe v1.0.0-5-g9c1dd0f)" = "v1.0.9c1d" ]
}

function test_hi_shorten_describe_drops_the_dirty_suffix() {
  [ "$(_hi_shorten_describe v1.0.0-5-g9c1dd0f-dirty)" = "v1.0.9c1d" ]
}

function test_hi_shorten_describe_trims_a_bare_hash() {
  [ "$(_hi_shorten_describe 9c1dd0fabc)" = "9c1d" ]
}

function test_hi_shorten_describe_leaves_an_exact_tag_alone() {
  [ "$(_hi_shorten_describe v1.0.0)" = "v1.0.0" ]
}

function test_hi_shorten_describe_leaves_a_release_stamp_alone() {
  [ "$(_hi_shorten_describe 1.2.3)" = "1.2.3" ]
}

function test_hi_shorten_describe_leaves_unknown_alone() {
  [ "$(_hi_shorten_describe unknown)" = "unknown" ]
}

function test_hi_shorten_describe_caps_a_long_tag_at_ten() {
  [ "$(_hi_shorten_describe snapshot-6fba937-1-g200cef5-dirty)" = "snaps.200c" ]
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

function test_system_info_includes_static_labels() {
  local out
  out="$(system_info)"
  [[ "$out" == *"Cores:"* && "$out" == *"RAM:"* && "$out" == *"CPU:"* ]]
}

# the uptime cell lives in identity() now - system_info must not carry it too
function test_system_info_no_longer_shows_uptime() {
  local out
  out="$(system_info)"
  [[ "$out" != *"Up:"* ]]
}

# GHz is the only format the CPU cell renders now - one pin so a regression
# back to whole MHz integers is caught
function test_system_info_cpu_cell_is_ghz() {
  local out
  out="$(system_info)"
  [[ "$out" == *"GHz"* ]]
}

# the CPU cell sits right after Cores: now, with RAM: pushed behind it -
# rather than separated from it by RAM: the way it used to be
function test_system_info_cpu_cell_sits_next_to_cores() {
  local out cores_pos cpu_pos ram_pos
  out="$(system_info)"
  cores_pos="$(_hi_pos "$out" "Cores:")"
  cpu_pos="$(_hi_pos "$out" "CPU:")"
  ram_pos="$(_hi_pos "$out" "RAM:")"
  [ -n "$cores_pos" ] && [ -n "$cpu_pos" ] && [ -n "$ram_pos" ] &&
    ((cores_pos < cpu_pos)) && ((cpu_pos < ram_pos))
}

# _hi_cpu_clocks' own contract: two numbers only when there is a real range
# to show, one otherwise - system_info's probe results are out of its
# control, so this is what actually pins the collapse behavior
function test_hi_cpu_clocks_shows_both_when_they_differ() {
  [ "$(_hi_cpu_clocks 2.8 4.5)" = "2.8/4.5" ]
}

function test_hi_cpu_clocks_collapses_when_equal() {
  [ "$(_hi_cpu_clocks 3.0 3.0)" = "3.0" ]
}

function test_hi_cpu_clocks_collapses_when_boost_missing() {
  [ "$(_hi_cpu_clocks 2.8 "")" = "2.8" ]
}

function test_hi_cpu_clocks_falls_back_to_boost_when_base_missing() {
  [ "$(_hi_cpu_clocks "" 4.5)" = "4.5" ]
}

function test_hi_cpu_clocks_question_mark_when_both_missing() {
  [ "$(_hi_cpu_clocks "" "")" = "?" ]
}

# _hi_uptime_cell: at most two units, largest first, or "?" where no probe
# answers - the shape is pinned rather than a value, which moves by the second
function test_uptime_cell_is_humanized() {
  local out
  _hi_uptime_cell out
  [[ "$out" =~ Up:\ ([0-9]+d\ [0-9]+h|[0-9]+h\ [0-9]+m|[0-9]+m|\?) ]]
}

# _hi_humanize_uptime's own contract, independent of what this box's real
# uptime happens to be
function test_hi_humanize_uptime_days_and_hours() {
  [ "$(_hi_humanize_uptime 90000)" = "1d 1h" ] # 25h -> 1d 1h
}

function test_hi_humanize_uptime_hours_and_minutes() {
  [ "$(_hi_humanize_uptime 5400)" = "1h 30m" ]
}

function test_hi_humanize_uptime_minutes_only() {
  [ "$(_hi_humanize_uptime 120)" = "2m" ]
}

# used/total, one unit at the end, or total alone when only that probe
# answers, or "?" when neither does - the shape is pinned, not a value, since
# this box's own usage moves between runs
function test_system_info_ram_cell_is_used_over_total() {
  local out
  out="$(system_info)"
  [[ "$out" =~ RAM:\ ([0-9]+G/[0-9]+G|[0-9]+G|\?) ]]
}

# the load figure, when a probe answers, rides in parens right after "GHz" -
# optional, since a stripped target has no /proc/loadavg or vm.loadavg; a
# figure that showed up would have to be a plain decimal, never garbage from
# an unguarded parse
function test_system_info_load_rides_the_cpu_cell() {
  local out load
  out="$(system_info)"
  load="$(printf '%s' "$out" | sed -n 's/.*GHz (\([^)]*\)).*/\1/p')"
  [[ -z "$load" || "$load" =~ ^[0-9]+\.[0-9]+$ ]]
}

# A target with a shell and awk and nothing else - core_test.sh's barebones
# box, one layer up. The header is the first thing a session prints, so a
# missing uname or date greeting the user with "command not found" across the
# banner would be a bad first impression; the cells say "?" instead, the way
# every other probe in system_info answers a missing binary.
# shellcheck disable=SC2016 # the probe expands in the child bash, not here
function _hi_stripped_header() {
  local nocfg="$_HI_WORKDIR/stripped-nocfg"
  env -i PATH="$(_hi_real_path stripped bash awk)" HOME="$HOME" NO_COLOR=1 \
    XDG_CONFIG_HOME="$nocfg" _HI_CONFIG_DIR="$nocfg/say-hi" \
    _HI_HOME="$_HI_HOME" _HI_CASE_PROBE="$1" bash -c \
    'source "$_HI_HOME/say-hi/common/core.sh"; source "$_HI_HEADER"; eval "$_HI_CASE_PROBE"' 2>&1
}

function test_system_info_without_uname_says_unknown() {
  local out
  out="$(_hi_stripped_header system_info)"
  [[ "$out" == *"?"* ]] && ! grep -qE "$_HI_SHELL_ERROR_RE" <<<"$out"
}

function test_timestamp_without_date_says_unknown() {
  local out
  out="$(_hi_stripped_header timestamp)"
  [[ "$out" == *"?"* ]] && ! grep -qE "$_HI_SHELL_ERROR_RE" <<<"$out"
}

# unlike system_info's other cells, _hi_uptime_cell's only external dependency
# on Linux is awk - which "stripped" still carries, since most probes need it -
# so this stays a smoke test for "no raw shell error leaks out", not a claim
# that the cell renders "?": a real /proc/uptime under a real Linux kernel
# answers it regardless of what else is missing.
# shellcheck disable=SC2016 # $u expands in the stripped child bash, not here
function test_uptime_cell_survives_a_stripped_environment() {
  local out
  out="$(_hi_stripped_header '_hi_uptime_cell u; printf "%s" "$u"')"
  [[ "$out" == *"Up: "* ]] && ! grep -qE "$_HI_SHELL_ERROR_RE" <<<"$out"
}

# the whole banner, since that is what a session actually prints
function test_banner_renders_without_coreutils() {
  local out
  out="$(_hi_stripped_header 'banner Connected "" ""')"
  [[ "$out" == *Connected* ]] && ! grep -qE "$_HI_SHELL_ERROR_RE" <<<"$out"
}

# passthrough_check: the one header line that speaks only when something is
# wrong. Every case below stands a fake `tmux` in front of the real one, so the
# answer is the fixture's rather than this machine's - and so the suite runs
# the same on a box with no tmux at all.
#
# The shim answers `show ... allow-passthrough` with $1 and exits 1 for
# anything else, which is what a tmux too old for the option does.
function _hi_tmux_shim() {
  local dir="$_HI_WORKDIR/tmux-$1"
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    {
      printf '%s\n' '#!/bin/sh'
      printf '%s\n' 'case "$*" in *allow-passthrough*) ;; *) exit 1 ;; esac'
      printf 'printf %%s "%s"\n' "$2"
    } >"$dir/tmux"
    chmod +x "$dir/tmux"
  fi
  printf '%s' "$dir"
}

# passthrough_check with $TMUX set to something, a tmux answering $1, and the
# rest of the environment left alone
function _hi_passthrough() {
  PATH="$(_hi_tmux_shim "$1" "$2"):$PATH" TMUX="/tmp/tmux-0/default,1,0" \
    bash -c 'source "$_HI_HEADER"; passthrough_check' 2>&1
}

# the line itself: names the option, and names the fix
function test_passthrough_warns_when_off() {
  local out
  out="$(_hi_passthrough off off)"
  [[ "$out" == *"passthrough"* && "$out" == *"allow-passthrough on"* ]]
}

# ...and says nothing at all when tmux is passing escapes through, which is the
# half that keeps it from being noise on a correctly configured box
function test_passthrough_quiet_when_on() {
  [ -z "$(_hi_passthrough on on)" ]
}

# `all` is tmux's other yes - passthrough from an invisible pane too - and has
# to count as on rather than as an unrecognised value
function test_passthrough_quiet_when_all() {
  [ -z "$(_hi_passthrough all all)" ]
}

# A tmux too old to have the option answers nothing, and nothing is what to say
# back: the line would name a fix that does not exist on that version.
function test_passthrough_quiet_on_an_old_tmux() {
  [ -z "$(_hi_passthrough old "")" ]
}

# no multiplexer in the way, no line - the check must not fire on the strength
# of a stale $TMUX-less environment having tmux on $PATH
function test_passthrough_quiet_without_tmux_in_the_env() {
  local out
  out="$(PATH="$(_hi_tmux_shim off off):$PATH" \
    bash -c 'unset TMUX; source "$_HI_HEADER"; passthrough_check' 2>&1)"
  [ -z "$out" ]
}

# ...and nothing to warn about once both features it is about are off. Either
# one still on keeps the line, since either one alone is muted by the same
# option.
function test_passthrough_quiet_when_both_features_are_off() {
  local out
  out="$(PATH="$(_hi_tmux_shim off off):$PATH" TMUX="/tmp/tmux-0/default,1,0" \
  _HI_DISABLE_OSC52=1 _HI_DISABLE_NOTIFY=1 \
    bash -c 'source "$_HI_HEADER"; passthrough_check' 2>&1)"
  [ -z "$out" ]
}

function test_passthrough_warns_with_only_notify_on() {
  local out
  out="$(PATH="$(_hi_tmux_shim off off):$PATH" TMUX="/tmp/tmux-0/default,1,0" \
  _HI_DISABLE_OSC52=1 \
    bash -c 'source "$_HI_HEADER"; passthrough_check' 2>&1)"
  [[ "$out" == *"allow-passthrough on"* ]]
}

# it rides the header rather than standing on its own, and last: the line that
# says something is wrong is the one left next to the prompt
function test_passthrough_line_reaches_the_header() {
  local out
  out="$(PATH="$(_hi_tmux_shim off off):$PATH" TMUX="/tmp/tmux-0/default,1,0" \
    bash -c 'source "$_HI_HEADER"; hi_header Connected' 2>&1)"
  [[ "$out" == *Connected* && "$(printf '%s\n' "$out" | tail -n 1)" == *"allow-passthrough on"* ]]
}

function test_identity_includes_static_labels() {
  local out
  out="$(identity)"
  [[ "$out" == *"Auth:"* && "$out" == *"Pub:"* ]]
}

# uptime rides at the end of the identity row now, after Auth:/Pub: - not a
# row of its own
function test_identity_includes_uptime_cell_last() {
  local out auth_pos pub_pos up_pos
  out="$(identity)"
  auth_pos="$(_hi_pos "$out" "Auth:")"
  pub_pos="$(_hi_pos "$out" "Pub:")"
  up_pos="$(_hi_pos "$out" "Up:")"
  [ -n "$auth_pos" ] && [ -n "$pub_pos" ] && [ -n "$up_pos" ] &&
    ((auth_pos < pub_pos)) && ((pub_pos < up_pos))
}

# A restricted PATH with just what identity()/_hi_probe_launch need, and none
# of docker/podman/nomad/kubectl - so "backend absent" is guaranteed
# regardless of what is actually installed on the box running this suite.
function _hi_identity_path() {
  _hi_real_path identity-tools bash sh awk sed grep mktemp rm cat git find \
    timeout date stat sort head tr cut wc
}

# _hi_identity_path with one fake <name> prepended, answering
# _hi_probe_launch's own invocation shape for it - docker/podman get
# "container ls -q" (one line per fake container), nomad gets "job status" (a
# header line, since identity() drops line 1, then one line per fake job).
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

# ...and kubectl, which identity() reaches through targets.sh (sh
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

# identity(), run in a fresh bash with $1 as PATH - isolates which backend
# binaries _hi_probe_launch actually finds from whatever is really installed
# on the box running this suite. _HI_TARGETS_TTL=0 sends the kube lane
# straight past targets.sh's own cache/lock files (real state this suite does
# not own, under /run or $TMPDIR) to a fresh sweep every call.
function _hi_identity_with() {
  PATH="$1" _HI_TARGETS_TTL=0 bash -c 'source "$_HI_HEADER"; identity' 2>&1
}

# One rule for all three: no cell at all when the backend was never found -
# not even the old "No docker/podman :(" fallback text, which used to be the
# one backend that always showed something
function test_identity_hides_all_backend_cells_when_none_found() {
  local out
  out="$(_hi_identity_with "$(_hi_identity_path)")"
  [[ "$out" != *"Containers:"* && "$out" != *"Jobs:"* && "$out" != *"Pods:"* && "$out" != *"docker/podman"* ]]
}

# ...and once found, the count shows even at zero - a probed-and-idle backend
# is no longer indistinguishable from an absent one
function test_identity_shows_containers_zero_when_docker_found_but_empty() {
  local out
  out="$(_hi_identity_with "$(_hi_backend_shim docker 0)")"
  [[ "$out" == *"Containers: 0"* ]]
}

function test_identity_shows_containers_count_when_docker_found() {
  local out
  out="$(_hi_identity_with "$(_hi_backend_shim docker 3)")"
  [[ "$out" == *"Containers: 3"* ]]
}

function test_identity_shows_jobs_zero_when_nomad_found_but_idle() {
  local out
  out="$(_hi_identity_with "$(_hi_backend_shim nomad 0)")"
  [[ "$out" == *"Jobs: 0"* ]]
}

function test_identity_shows_jobs_count_excluding_the_header_row() {
  local out
  out="$(_hi_identity_with "$(_hi_backend_shim nomad 2)")"
  [[ "$out" == *"Jobs: 2"* ]]
}

function test_identity_shows_pods_zero_when_kube_found_but_empty() {
  local out
  out="$(_hi_identity_with "$(_hi_kube_shim 0)")"
  [[ "$out" == *"Pods: 0"* ]]
}

function test_identity_shows_pods_count_when_kube_found() {
  local out
  out="$(_hi_identity_with "$(_hi_kube_shim 2)")"
  [[ "$out" == *"Pods: 2"* ]]
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
  local _HI_HEADER_VERSION=orderprobe pkgfile="$_HI_WORKDIR/order-default" out
  local ts si id ck
  printf '%s:3\n' "$_HI_REAL_CMD" >"$pkgfile"
  out="$(_HI_PACKAGES="$pkgfile" hi_header Connected)"
  ts="$(_hi_pos "$out" orderprobe)"
  si="$(_hi_pos "$out" "Cores:")"
  id="$(_hi_pos "$out" "Auth:")"
  ck="$(_hi_pos "$out" "$_HI_REAL_CMD")"
  [ -n "$ts" ] && [ -n "$si" ] && [ -n "$id" ] && [ -n "$ck" ] &&
    ((ts < si)) && ((si < id)) && ((id < ck))
}

# a reordered $_HI_HEADER_ORDER moves the rows to match, and a row left out of
# it is not printed at all - a second way to hide a row alongside its own
# $_HI_HEADER_* toggle. identity is in this order, so its uptime cell still
# rides along with it.
function test_hi_header_order_setting_reorders_and_can_omit() {
  local _HI_HEADER_VERSION=orderprobe pkgfile="$_HI_WORKDIR/order-custom" out
  local ck id si
  printf '%s:3\n' "$_HI_REAL_CMD" >"$pkgfile"
  out="$(_HI_PACKAGES="$pkgfile" _HI_HEADER_ORDER="check identity sysinfo" hi_header Connected)"
  ck="$(_hi_pos "$out" "$_HI_REAL_CMD")"
  id="$(_hi_pos "$out" "Auth:")"
  si="$(_hi_pos "$out" "Cores:")"
  [[ "$out" != *orderprobe* ]] &&
    [[ "$out" == *"Up:"* ]] &&
    [ -n "$ck" ] && [ -n "$id" ] && [ -n "$si" ] &&
    ((ck < id)) && ((id < si))
}

# "uptime" left $_HI_HEADER_ORDER's vocabulary along with the row - an unknown
# word is ignored rather than erroring or printing anything for it, and that
# is what a word this list no longer understands falls back to
function test_hi_header_order_ignores_an_unknown_word() {
  local out
  out="$(_HI_HEADER_ORDER="bogus sysinfo" hi_header Connected)"
  [[ "$out" == *"Cores:"* ]]
}

function test_hi_header_order_uptime_is_no_longer_a_word() {
  local out
  out="$(_HI_HEADER_ORDER="uptime sysinfo" hi_header Connected)"
  [[ "$out" != *"Up:"* && "$out" == *"Cores:"* ]]
}

# _HI_HEADER_UPTIME=0 hides just the uptime cell, the identity row's other
# cells stay
function test_hi_header_uptime_toggle_hides_the_cell() {
  local out
  out="$(_HI_HEADER_UPTIME=0 hi_header Connected)"
  [[ "$out" != *"Up:"* && "$out" == *"Auth:"* ]]
}

# End to end: hi_header arms the cascade for its own row loop, so identity's
# overflow (its Up: cell, guaranteed last) rides into the packages row's
# first line instead of standing alone. A restricted PATH (no docker/podman/
# nomad/kubectl, the same fixture identity()'s own backend-cell tests use via
# _hi_identity_path) keeps identity's cells short and deterministic; one
# priority-3 package guarantees full_check has something to open with.
function test_hi_header_cascades_identity_overflow_into_check() {
  local pkgfile="$_HI_WORKDIR/cascade-into-check" out line
  printf '%s:3\n' "$_HI_REAL_CMD" >"$pkgfile"
  out="$(PATH="$(_hi_identity_path)" _HI_TARGETS_TTL=0 _HI_PACKAGES="$pkgfile" \
  _HI_MAX_WIDTH=25 _HI_HEADER_ORDER="identity check" \
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
  _HI_MAX_WIDTH=20 _HI_HEADER_ORDER="identity" \
    bash -c 'source "$_HI_HEADER"; hi_header Connected' 2>&1)"
  [[ "$out" == *"Auth:"* && "$out" == *"Up:"* ]]
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

# The scaffold every check_line case shares: run one spec against a fresh row
# sink and assert how many rows it left visible. check_line appends to the
# `visible` these declare (bash's dynamic scoping), and the single row - when
# there is one - lands in the caller's `row`, ready for content checks.
function _hi_one_visible_row() {
  local -a visible=()
  check_line "$1"
  [ "${#visible[@]}" -eq 1 ] || return 1
  row="${visible[0]}"
}

function _hi_no_visible_row() {
  local -a visible=()
  check_line "$1"
  [ "${#visible[@]}" -eq 0 ]
}

function test_check_line_found_primary_is_visible_checked() {
  local row
  _hi_one_visible_row "$_HI_REAL_CMD:3" || return 1
  _hi_contains "$row" "$_HI_REAL_CMD" &&
    _hi_assert_contains "$row" "$_HI_MARK_OK"
}

# `-` is the mode hidden when the tool *is* there: it exists to speak up
# about absence, so a healthy box says nothing.
function test_check_line_dash_mode_hides_installed() {
  _hi_no_visible_row "-$_HI_REAL_CMD:3"
}

# ...and the same line missing is exactly the alarm the mode exists for - with
# the mode character stripped from the printed name.
function test_check_line_dash_mode_missing_is_visible() {
  local row
  _hi_one_visible_row "-$_HI_FAKE_CMD:3" || return 1
  _hi_contains "$row" "$_HI_FAKE_CMD" || return 1
  _hi_assert_contains "$row" "$_HI_MARK_NO" || return 1
  if _hi_contains "$row" "-$_HI_FAKE_CMD"; then return 1; fi
  return 0
}

# `+` is the mirror: presence is the fact worth a row, absence is noise.
function test_check_line_plus_mode_shows_installed() {
  local row
  _hi_one_visible_row "+$_HI_REAL_CMD:0" || return 1
  _hi_contains "$row" "$_HI_REAL_CMD" &&
    _hi_assert_contains "$row" "$_HI_MARK_OK"
}

function test_check_line_plus_mode_hides_missing() {
  _hi_no_visible_row "+$_HI_FAKE_CMD:0"
}

# Every unflagged line speaks when the tool is absent - that is the nudge the
# table exists for, and tier 0, the quietest one there is, is where it is
# worth pinning: if even trivia reports itself missing, nothing above it can
# be silently dropped.
function test_check_line_missing_priority0_is_visible() {
  local row
  _hi_one_visible_row "$_HI_FAKE_CMD:0" || return 1
  _hi_contains "$row" "$_HI_FAKE_CMD" &&
    _hi_assert_contains "$row" "$_HI_MARK_NO"
}

function test_check_line_missing_priority3_is_visible_crossed() {
  local row
  _hi_one_visible_row "$_HI_FAKE_CMD:3" || return 1
  _hi_contains "$row" "$_HI_FAKE_CMD" &&
    _hi_assert_contains "$row" "$_HI_MARK_NO"
}

# an old-format file's 4s and 5s clamp to 3 instead of indexing off the end of
# the four-entry color tables - the degradation rule for a stale overlay
function test_check_line_clamps_a_priority_above_three() {
  local row
  _hi_one_visible_row "$_HI_REAL_CMD:5" || return 1
  case "$row" in 3$'\x1f'*) return 0 ;; esac
  return 1
}

# a line nothing satisfies ranks at the loudest priority it lists, not the
# first: the unmet need is as important as its best answer
function test_check_line_missing_ranks_at_max_priority() {
  local row
  _hi_one_visible_row "$_HI_FAKE_CMD:1,${_HI_FAKE_CMD}-alt:3" || return 1
  _hi_contains "$row" "$_HI_FAKE_CMD" || return 1
  case "$row" in 3$'\x1f'*) return 0 ;; esac
  return 1
}

function test_check_line_fallback_uses_second_alternative() {
  local row
  _hi_one_visible_row "$_HI_FAKE_CMD:0,$_HI_REAL_CMD:3" || return 1
  _hi_contains "$row" "$_HI_REAL_CMD" &&
    _hi_assert_contains "$row" "$_HI_MARK_ALT"
}

function test_check_line_picks_highest_priority_installed() {
  local -a visible=()
  check_line "$_HI_REAL_CMD:1,bash:3"
  _hi_contains "${visible[0]}" bash
}

function test_full_check_skips_comments_and_blanks() {
  local pkgfile="$_HI_WORKDIR/comments"
  printf '# a comment\n\n%s:3\n' "$_HI_REAL_CMD" >"$pkgfile"
  (
    _HI_PACKAGES="$pkgfile"
    full_check
  ) | grep -qF "$_HI_REAL_CMD"
}

function test_full_check_empty_when_everything_hidden() {
  local pkgfile="$_HI_WORKDIR/hidden" out
  # an installed `-` line is the one row the check still hides - see the note
  # above _HI_YES. Nothing else renders nothing.
  printf '%s:3\n' "-$_HI_REAL_CMD" >"$pkgfile"
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
# header reads as a check that ran and found nothing rather than one turned
# off. 4 is the documented "off" value: priorities clamp to 3, so nothing can
# ever reach it.
function test_full_check_min_priority_above_everything_is_silent() {
  local pkgfile="$_HI_WORKDIR/floor-all" out
  printf '%s:3\n' "$_HI_REAL_CMD" >"$pkgfile"
  out="$(
    _HI_PACKAGES="$pkgfile"
    _HI_PACKAGES_MIN_PRIORITY=4
    full_check
  )"
  [ -z "$out" ]
}

# unset behaves as 2, not 0: rank 2 prints and rank 1 does not. Both halves
# again, for the reason the boundary case above gives - a default that hid
# everything would pass a test that only checked the hidden side.
function test_full_check_min_priority_defaults_to_two() {
  local pkgfile="$_HI_WORKDIR/floor-default" out
  printf '%s:2\nbash:1\n' "$_HI_REAL_CMD" >"$pkgfile"
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
  printf '%s:3\nbash:3\n' "$_HI_REAL_CMD" >"$pkgfile"
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

# full_check is the cascade's landing point: it absorbs an incoming
# $_HI_ROW_CARRY as its own first cells, ahead of the packages it reads
# itself, rather than leaving it for a caller that has nowhere left to send
# it. `local -a _HI_ROW_CARRY` shadows the global the same way other cases in
# this file shadow $_HI_HEADER_VERSION, and the call is not wrapped in
# $(...) where inspecting its post-call state is needed.
function test_full_check_absorbs_an_incoming_carry() {
  local pkgfile="$_HI_WORKDIR/carry-absorb" out
  printf '%s:3\n' "$_HI_REAL_CMD" >"$pkgfile"
  local -a _HI_ROW_CARRY=(carriedcell)
  out="$(_HI_PACKAGES="$pkgfile" full_check)"
  [[ "$out" == *carriedcell* ]] && [[ "$out" == *"$_HI_REAL_CMD"* ]] &&
    [ -n "$(_hi_pos "$out" carriedcell)" ] && [ -n "$(_hi_pos "$out" "$_HI_REAL_CMD")" ] &&
    [ "$(_hi_pos "$out" carriedcell)" -lt "$(_hi_pos "$out" "$_HI_REAL_CMD")" ]
}

# ...and takes ownership of it: nothing is left for a caller after it to
# flush a second time.
function test_full_check_consumes_the_carry() {
  local pkgfile="$_HI_WORKDIR/carry-consume"
  printf '%s:3\n' "$_HI_REAL_CMD" >"$pkgfile"
  local -a _HI_ROW_CARRY=(carriedcell)
  _HI_PACKAGES="$pkgfile" full_check >/dev/null
  [ "${#_HI_ROW_CARRY[@]}" -eq 0 ]
}

# a carry still has to print even when the packages file itself yields
# nothing visible - guards the floor check that used to be `return 0` the
# moment $visible was empty, before it had a second source to consider
function test_full_check_prints_carry_even_with_no_visible_packages() {
  local pkgfile="$_HI_WORKDIR/carry-no-packages" out
  : >"$pkgfile"
  local -a _HI_ROW_CARRY=(onlycell)
  out="$(_HI_PACKAGES="$pkgfile" full_check)"
  [[ "$out" == *onlycell* ]]
}

# ...and the original guard still holds with nothing on either side
function test_full_check_empty_carry_and_no_packages_prints_nothing() {
  local pkgfile="$_HI_WORKDIR/carry-empty-none" out
  : >"$pkgfile"
  local -a _HI_ROW_CARRY=()
  out="$(_HI_PACKAGES="$pkgfile" full_check)"
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
  local pkgfile="$_HI_WORKDIR/emits" out
  printf '%s:3\n' "$_HI_REAL_CMD" >"$pkgfile"
  out="$(
    _HI_PACKAGES="$pkgfile"
    full_check
  )"
  [[ "$out" == *"$_HI_REAL_CMD"* ]]
}

# _hi_packages_palette's contract: each named ramp is exactly four entries -
# one per priority 0-3 - in both tables. `VAR=val func` on a shell function
# (not an external command) reverts VAR once the call returns, so this leaves
# no _HI_PACKAGES_PALETTE behind for a case after it.
function test_packages_palette_each_name_has_four_entries() {
  local name
  for name in cool warm mono; do
    _HI_PACKAGES_PALETTE="$name" _hi_packages_palette
    [ "${#_HI_YES[@]}" -eq 4 ] && [ "${#_HI_NO[@]}" -eq 4 ] || return 1
  done
}

# an unrecognized name falls back to the same tables an unset one resolves to
# (cool) - checked by content, not by name, since header.sh's own comment
# above _HI_YES is the only place "cool" is defined as those four escapes
function test_packages_palette_unknown_falls_back_to_cool() {
  local -a cool_yes cool_no
  unset _HI_PACKAGES_PALETTE
  _hi_packages_palette
  cool_yes=("${_HI_YES[@]}") cool_no=("${_HI_NO[@]}")
  _HI_PACKAGES_PALETTE=bogus _hi_packages_palette
  [ "${_HI_YES[*]}" = "${cool_yes[*]}" ] && [ "${_HI_NO[*]}" = "${cool_no[*]}" ]
}

# every escape in every named palette has to name a real _HI_COLOR_NAMES
# entry, or a candidate ramp would paint the header with something
# packages_preview.sh's _hi_color_name_of could never look up. Both sides go
# through `printf '%b'` before comparing, packages_preview.sh's own
# _hi_color_name_of shape: core.sh's palette variables hold the literal two
# characters `\e`, while _hi_color_escape's format string interprets `\e` as
# the real ESC byte - unexpanded, every comparison here would silently miss.
function test_packages_palette_escapes_are_all_named_colors() {
  local name escape found candidate want
  for name in cool warm mono; do
    _HI_PACKAGES_PALETTE="$name" _hi_packages_palette
    for escape in "${_HI_YES[@]}" "${_HI_NO[@]}"; do
      want="$(printf '%b' "$escape")"
      found=""
      for candidate in "${_HI_COLOR_NAMES[@]}"; do
        [ "$(printf '%b' "$(_hi_color_escape "$candidate")")" = "$want" ] && found=1 && break
      done
      [ -n "$found" ] || return 1
    done
  done
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
  _hi_check "Wrap math ignores color escape bytes" test_header_row_width_ignores_color_escape_bytes
  _hi_check "_hi_draw_width defaults to _HI_MAX_WIDTH when captured" test_hi_draw_width_defaults_to_max_width_when_captured
  _hi_check "_hi_draw_width honors an explicit _HI_TERM_COLS override" test_hi_draw_width_honors_an_explicit_override
  _hi_check "_hi_draw_width never widens past _HI_MAX_WIDTH" test_hi_draw_width_never_widens_past_max_width
  _hi_check "Wraps at a _HI_TERM_COLS override" test_header_row_wraps_at_hi_term_cols_override
  _hi_check "Armed, overflow carries to the next call" test_header_row_armed_carries_overflow_to_the_next_call
  _hi_check "...and opens the next row" test_header_row_armed_carry_opens_the_next_row
  _hi_check "Unarmed, a row leaves no carry behind" test_header_row_unarmed_leaves_no_carry_behind

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
  _hi_check "Folds a tag and its hash together" test_hi_shorten_describe_folds_tag_and_hash
  _hi_check "...drops the -dirty suffix" test_hi_shorten_describe_drops_the_dirty_suffix
  _hi_check "...trims a bare hash too" test_hi_shorten_describe_trims_a_bare_hash
  _hi_check "...leaves an exact tag alone" test_hi_shorten_describe_leaves_an_exact_tag_alone
  _hi_check "...leaves a release stamp alone" test_hi_shorten_describe_leaves_a_release_stamp_alone
  _hi_check "...leaves 'unknown' alone" test_hi_shorten_describe_leaves_unknown_alone
  _hi_check "...caps a long tag+hash at 10 columns" test_hi_shorten_describe_caps_a_long_tag_at_ten
  _hi_check "The version cell itself is shortened" test_timestamp_version_cell_is_shortened
  _hi_check "System_info includes its static labels" test_system_info_includes_static_labels
  _hi_check "System_info no longer shows uptime" test_system_info_no_longer_shows_uptime
  _hi_check "System_info's CPU cell renders GHz" test_system_info_cpu_cell_is_ghz
  _hi_check "System_info's CPU cell sits next to Cores:" test_system_info_cpu_cell_sits_next_to_cores
  _hi_check "_hi_cpu_clocks shows both when they differ" test_hi_cpu_clocks_shows_both_when_they_differ
  _hi_check "...collapses when equal" test_hi_cpu_clocks_collapses_when_equal
  _hi_check "...collapses when boost is missing" test_hi_cpu_clocks_collapses_when_boost_missing
  _hi_check "...falls back to boost when base is missing" test_hi_cpu_clocks_falls_back_to_boost_when_base_missing
  _hi_check "...? when both are missing" test_hi_cpu_clocks_question_mark_when_both_missing
  _hi_check "System_info's RAM cell is used/total" test_system_info_ram_cell_is_used_over_total
  _hi_check "System_info's load figure rides the CPU cell" test_system_info_load_rides_the_cpu_cell
  _hi_check "The uptime cell is humanized" test_uptime_cell_is_humanized
  _hi_check "_hi_humanize_uptime: days and hours" test_hi_humanize_uptime_days_and_hours
  _hi_check "_hi_humanize_uptime: hours and minutes" test_hi_humanize_uptime_hours_and_minutes
  _hi_check "_hi_humanize_uptime: minutes only" test_hi_humanize_uptime_minutes_only
  _hi_check "Identity includes its static labels" test_identity_includes_static_labels
  _hi_check "Identity's uptime cell rides last" test_identity_includes_uptime_cell_last
  _hi_check "No cells at all when no backend is found" test_identity_hides_all_backend_cells_when_none_found
  _hi_check "Containers: 0 when docker is found but empty" test_identity_shows_containers_zero_when_docker_found_but_empty
  _hi_check "Containers count when docker is found" test_identity_shows_containers_count_when_docker_found
  _hi_check "Jobs: 0 when nomad is found but idle" test_identity_shows_jobs_zero_when_nomad_found_but_idle
  _hi_check "Jobs count excludes nomad's header row" test_identity_shows_jobs_count_excluding_the_header_row
  _hi_check "Pods: 0 when kube is found but empty" test_identity_shows_pods_zero_when_kube_found_but_empty
  _hi_check "Pods count when kube is found" test_identity_shows_pods_count_when_kube_found

  _hi_h2 "Testing: a target with no coreutils"
  _hi_check "System_info says ? without uname" test_system_info_without_uname_says_unknown
  _hi_check "Timestamp says ? without date" test_timestamp_without_date_says_unknown
  _hi_check "The uptime cell survives a stripped environment" test_uptime_cell_survives_a_stripped_environment
  _hi_check "The banner still renders" test_banner_renders_without_coreutils

  _hi_h2 "Testing: hi_header"
  _hi_check "No output when disabled" test_hi_header_disabled_produces_no_output
  _hi_check "Prints the banner when enabled" test_hi_header_enabled_prints_banner
  _hi_check "Banner off still prints the detail lines" test_hi_header_banner_off_keeps_detail_lines
  _hi_check "Default row order: timestamp, sysinfo, identity, check" test_hi_header_default_order
  _hi_check "_HI_HEADER_ORDER reorders, and omitting a row hides it" test_hi_header_order_setting_reorders_and_can_omit
  _hi_check "An unknown order word is ignored" test_hi_header_order_ignores_an_unknown_word
  _hi_check "'uptime' is no longer an order word" test_hi_header_order_uptime_is_no_longer_a_word
  _hi_check "_HI_HEADER_UPTIME=0 hides just the uptime cell" test_hi_header_uptime_toggle_hides_the_cell
  _hi_check "A row's overflow cascades into the packages row" test_hi_header_cascades_identity_overflow_into_check
  _hi_check "...and still flushes when 'check' is left out" test_hi_header_flushes_leftover_when_check_is_absent

  _hi_h2 "Testing: passthrough_check"
  _hi_check "Warns under a tmux with passthrough off" test_passthrough_warns_when_off
  _hi_check "Quiet with passthrough on" test_passthrough_quiet_when_on
  _hi_check "Quiet with passthrough all" test_passthrough_quiet_when_all
  _hi_check "Quiet on a tmux too old for the option" test_passthrough_quiet_on_an_old_tmux
  _hi_check "Quiet with no tmux in the environment" test_passthrough_quiet_without_tmux_in_the_env
  _hi_check "Quiet once both features are off" test_passthrough_quiet_when_both_features_are_off
  _hi_check "Warns with only hi_notify left on" test_passthrough_warns_with_only_notify_on
  _hi_check "The line is the header's last" test_passthrough_line_reaches_the_header

  _hi_h2 "Testing: check_line"
  _hi_check "Found primary -> visible, checked" test_check_line_found_primary_is_visible_checked
  _hi_check "Installed on a - line -> hidden" test_check_line_dash_mode_hides_installed
  _hi_check "Missing on a - line -> visible, no leaked flag" test_check_line_dash_mode_missing_is_visible
  _hi_check "Installed on a + line -> visible" test_check_line_plus_mode_shows_installed
  _hi_check "Missing on a + line -> hidden" test_check_line_plus_mode_hides_missing
  _hi_check "Missing priority 0 -> visible" test_check_line_missing_priority0_is_visible
  _hi_check "Missing priority 3 -> visible, crossed" test_check_line_missing_priority3_is_visible_crossed
  _hi_check "A priority above 3 clamps to 3" test_check_line_clamps_a_priority_above_three
  _hi_check "Missing line ranks at its max priority" test_check_line_missing_ranks_at_max_priority
  _hi_check "Fallback alternative used" test_check_line_fallback_uses_second_alternative
  _hi_check_requires bash "Picks the highest-priority installed alternative" test_check_line_picks_highest_priority_installed

  _hi_h2 "Testing: full_check"
  _hi_check "Skips comment/blank lines" test_full_check_skips_comments_and_blanks
  _hi_check "Empty output when everything is hidden" test_full_check_empty_when_everything_hidden
  _hi_check_requires bash "Min priority: at the floor shows, below is gone" test_full_check_min_priority_boundary
  _hi_check "Min priority above every rank prints nothing" test_full_check_min_priority_above_everything_is_silent
  _hi_check_requires bash "Min priority unset floors at 2" test_full_check_min_priority_defaults_to_two
  _hi_check_requires bash "Wraps rows at _HI_MAX_WIDTH" test_full_check_wraps_at_max_width
  _hi_check "Real settings/packages file parses cleanly" test_full_check_reads_real_packages_file_without_erroring
  _hi_check "Writes nothing to stderr" test_full_check_is_silent_on_stderr
  _hi_check "Emits a row for an installed package" test_full_check_emits_a_row_for_an_installed_package
  _hi_check "Absorbs an incoming carry ahead of its own cells" test_full_check_absorbs_an_incoming_carry
  _hi_check "...and consumes it" test_full_check_consumes_the_carry
  _hi_check "A carry still prints with no visible packages" test_full_check_prints_carry_even_with_no_visible_packages
  _hi_check "Empty carry, no packages: still silent" test_full_check_empty_carry_and_no_packages_prints_nothing

  _hi_h2 "Testing: _hi_packages_palette"
  _hi_check "Each named palette has four entries per table" test_packages_palette_each_name_has_four_entries
  _hi_check "An unknown name falls back to cool" test_packages_palette_unknown_falls_back_to_cool
  _hi_check "Every escape names a real color" test_packages_palette_escapes_are_all_named_colors

  _hi_suite_end "header.sh"
}

run_header_tests
