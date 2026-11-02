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

# Every non-blank line of <text>, ANSI stripped, is exactly <width> columns -
# a closed row's contract (_hi_row_line, full_check), for cases below that
# pin the column a row ends on rather than the presence of a pipe.
function _hi_all_lines_are() {
  local text="$1" want="$2" line n
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    _hi_visible_width n "$(_hi_strip_ansi "$line")"
    [ "$n" -eq "$want" ] || _hi_because "got width $n, want $want: [$line]" || return 1
  done <<<"$text"
}

function test_header_row_joins_cells() {
  local out
  out="$(header_row foo bar baz)"
  [[ "$out" == *"| foo"* && "$out" == *"| bar"* && "$out" == *"| baz"* ]] || _hi_why out
}

function test_header_row_single_cell() {
  local out
  out="$(header_row solo)"
  [[ "$out" == *"| solo"* ]] || _hi_why out
}

# a normal-width terminal still gets one line for a normal row - the wrap
# logic must not fire when nothing is actually overflowing
function test_header_row_default_width_stays_one_line() {
  local out lines
  out="$(header_row foo bar baz)"
  lines="$(printf '%s\n' "$out" | grep -c .)"
  [ "$lines" -eq 1 ] || _hi_why lines
}

function test_header_row_wraps_at_max_width() {
  local out lines
  out="$(_HI_MAX_WIDTH=1 header_row foo bar baz)"
  lines="$(printf '%s\n' "$out" | grep -c .)"
  [ "$lines" -ge 2 ] || _hi_why lines
}

# wrapping happens between cells, never inside one - every original cell's
# text still appears intact somewhere in the (multi-line) output
function test_header_row_wrap_keeps_cells_intact() {
  local out
  out="$(_HI_MAX_WIDTH=5 header_row alpha beta gamma)"
  [[ "$out" == *alpha* && "$out" == *beta* && "$out" == *gamma* ]] || _hi_why out
}

# --- the right edge: a row ends in the banner's column, not just a pipe ---

function test_header_row_closes_at_default_width() {
  local out
  out="$(header_row foo bar baz)"
  _hi_all_lines_are "$out" 80 || _hi_why out
}

function test_header_row_closes_at_narrow_width() {
  local out
  out="$(_HI_MAX_WIDTH=40 header_row cell-one-x cell-two-x cell-three cell-four- cell-five-)"
  _hi_all_lines_are "$out" 40 || _hi_why out
}

# every wrapped continuation line closes too, not only the first
function test_header_row_closes_every_wrapped_line() {
  local out lines
  out="$(_HI_MAX_WIDTH=24 header_row aaaaaaaa bbbbbbbb cccccccc dddddddd eeeeeeee)"
  lines="$(printf '%s\n' "$out" | grep -c .)"
  { [ "$lines" -ge 3 ] && _hi_all_lines_are "$out" 24; } || _hi_why lines out
}

# $_HI_DISABLE_RIGHT_EDGE gives back the open-ended row: no closing pipe, and
# a row stops short of the pinned width rather than being padded out to it
function test_disable_right_edge_gives_back_the_open_row() {
  local out got
  out="$(_HI_DISABLE_RIGHT_EDGE=1 _HI_MAX_WIDTH=40 header_row cell-one-x cell-two-x cell-three)"
  local line n
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    got="$(_hi_strip_ansi "$line")"
    [[ "$got" != *"|" ]] || _hi_why got line || return 1
    _hi_visible_width n "$(_hi_strip_ansi "$line")"
    ((n < 40)) || _hi_why || return 1
  done <<<"$out"
}

# _hi_visible_width's own contract: the color escape does not count
function test_hi_visible_width_strips_a_leading_color() {
  local n
  _hi_visible_width n "${GREEN}hi"
  [ "$n" -eq 2 ] || _hi_why n
}

# ...and one opened midway too: load()'s greeting cell changes color after
# "hi loaded: "
function test_hi_visible_width_strips_a_color_midway() {
  local n
  _hi_visible_width n "${BRCYAN}hi loaded: ${BRBLUE}bash"
  [ "$n" -eq 15 ] || _hi_why n
}

# Columns, never bytes. The header packs by this number, so where ${#}
# answers in bytes - a target under LC_ALL=C drawing the glyph set its client
# shipped it - a three-byte glyph measured as three would wrap a line the
# terminal had room for. GLOSSARY: HI.12
function test_hi_visible_width_counts_columns_not_bytes() {
  _hi_var_is 6 _hi_visible_width "abc●●●"
}

# ...and the byte-counting branch itself, forced on, so the case exercises it
# on a UTF-8 runner too rather than only where the locale happens to trip it
function test_hi_visible_width_counts_columns_where_length_counts_bytes() {
  local n
  (
    _HI_BYTE_COUNTS=1
    _hi_visible_width n "${GREEN}abc●●●"
    [ "$n" = 6 ]
  ) || _hi_why n
}

function test_hi_visible_width_plain_text_unchanged() {
  local n
  _hi_visible_width n "hi"
  [ "$n" -eq 2 ] || _hi_why n
}

# the width math has to be off the visible length, not the byte length - two
# colored cells short enough to share a line must not wrap just because their
# escape bytes would have pushed them over
function test_header_row_width_ignores_color_escape_bytes() {
  local out lines
  out="$(_HI_MAX_WIDTH=20 header_row "${GREEN}short" "${RED}text")"
  lines="$(printf '%s\n' "$out" | grep -c .)"
  [ "$lines" -eq 1 ] || _hi_why lines
}

# _hi_draw_width's own contract: captured output (this whole suite runs
# inside command substitution, never a tty) stays at $_HI_MAX_WIDTH exactly,
# so every width test above is unaffected by whatever terminal runs it
function _hi_draw_width_out() {
  local n
  _hi_draw_width n
  printf '%s' "$n"
}

function test_hi_draw_width_defaults_to_max_width_when_captured() {
  _HI_MAX_WIDTH=42 _HI_TERM_COLS="" _hi_prints 42 _hi_draw_width_out
}

# $_HI_TERM_COLS is a deliberate override - it wins whether or not stdout is
# a tty, which is what lets a suite pin a narrow width the same way it
# already pins $_HI_MAX_WIDTH
function test_hi_draw_width_honors_an_explicit_override() {
  _HI_MAX_WIDTH=80 _HI_TERM_COLS=30 _hi_prints 30 _hi_draw_width_out
}

# the terminal only ever narrows the draw width, never widens it past
# $_HI_MAX_WIDTH
function test_hi_draw_width_never_widens_past_max_width() {
  _HI_MAX_WIDTH=40 _HI_TERM_COLS=200 _hi_prints 40 _hi_draw_width_out
}

# header_row wraps at the narrower of the two - the point of the whole
# change: a real terminal narrower than $_HI_MAX_WIDTH breaks at the '|', not
# wherever the terminal itself would hard-wrap mid-cell
function test_header_row_wraps_at_hi_term_cols_override() {
  local out lines
  out="$(_HI_MAX_WIDTH=80 _HI_TERM_COLS=10 header_row alpha beta gamma)"
  lines="$(printf '%s\n' "$out" | grep -c .)"
  [ "$lines" -eq 3 ] || _hi_why lines
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
    [ "${_HI_ROW_CARRY[0]}" = beta ] && [ "${_HI_ROW_CARRY[1]}" = gamma ] || _hi_why out _HI_ROW_CARRY
}

# ...and the carried cells reach the very next header_row call, prepended
# ahead of its own - nothing is dropped between rows.
function test_header_row_armed_carry_opens_the_next_row() {
  local _HI_ROW_CARRY_ARMED=1 out
  local -a _HI_ROW_CARRY=()
  _HI_MAX_WIDTH=10 header_row alpha beta gamma >/dev/null
  out="$(header_row delta)"
  [[ "$out" == *beta* ]] && [[ "$out" == *gamma* ]] && [[ "$out" == *delta* ]] || _hi_why out
}

# unarmed - every caller but hi_header's own loop - a row still drains
# whatever it couldn't fit on its own, so no carry is left lying around for
# the next unrelated call to inherit
function test_header_row_unarmed_leaves_no_carry_behind() {
  local _HI_ROW_CARRY_ARMED=0
  local -a _HI_ROW_CARRY=()
  _HI_MAX_WIDTH=5 header_row alpha beta gamma >/dev/null
  [ "${#_HI_ROW_CARRY[@]}" -eq 0 ] || _hi_why _HI_ROW_CARRY
}

# _hi_row_line's own documented contract: zero cells is a no-op, not an empty
# line - nothing reaches this arm through header_row (it always has at least
# the un-carried "$@"), so only a direct call exercises it.
function test_row_line_returns_1_and_prints_nothing_for_zero_cells() {
  local out ec=0
  out="$(_hi_row_line)" || ec=$?
  [ "$ec" -eq 1 ] && [ -z "$out" ] || _hi_why ec out
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
    [ "$lines" -eq 3 ] && [ "${#_HI_ROW_CARRY[@]}" -eq 0 ] || _hi_why out lines _HI_ROW_CARRY
}

function test_timestamp_runs_and_has_three_cells() {
  local out got
  out="$(_HI_RELEASE="" timestamp)"
  # four pipes for three cells: the one that opens the row, the two that join
  # the cells, and the one that closes it on the right - and that last one
  # sits in the banner's own column, not merely somewhere in the row
  got="$(grep -o '|' <<<"$out" | wc -l)"
  { [ "$got" -eq 4 ] && _hi_all_lines_are "$out" 80; } || _hi_why got out
}

# the version is the middle cell, between the two clocks, and is printed bare
# - no "say-hi" in front of it. The palette is blanked for the row rather than
# stripped after: the cells are `| `-joined and field 1 is the empty lead.
function test_timestamp_puts_the_version_between_the_clocks() {
  local out got
  out="$(NC='' GREEN='' BRBLUE='' BRYELLOW='' _HI_RELEASE=1.2.3 timestamp)"
  got="$(cut -d'|' -f3 <<<"$out" | tr -d ' ')"
  [ "$got" = "1.2.3" ] && [[ "$out" != *"say-hi"* ]] || _hi_why got out
}

# ...and a shell with no stamp still gets one: this checkout answers with git
# describe, and only a stampless, gitless install falls through to "unknown"
function test_timestamp_version_falls_back_without_a_stamp() {
  local out got
  out="$(NC='' GREEN='' BRBLUE='' BRYELLOW='' _HI_RELEASE="" timestamp)"
  got="$(cut -d'|' -f3 <<<"$out" | tr -d ' ')"
  [ -n "$got" ] || _hi_why got out
}

# _hi_header_version's own memo - "resolved once per shell (the row prints
# twice a session)" - captured by direct call rather than $( ), which would
# fork away the assignment to $_HI_HEADER_VERSION before it ever landed.
function test_header_version_resolves_once_per_shell() {
  (
    unset _HI_HEADER_VERSION
    _HI_RELEASE=1.0.0
    _hi_header_version
    local first="$_HI_HEADER_VERSION"
    _HI_RELEASE=2.0.0 # a later change must not reach an already-memoized version
    _hi_header_version
    [ "$_HI_HEADER_VERSION" = "$first" ] && [ "$first" = 1.0.0 ]
  ) || _hi_why -6 first _HI_HEADER_VERSION
}

# the header cell itself carries the shortened form, not just the helper in
# isolation - this checkout's own git describe is what timestamp renders
function test_timestamp_version_cell_is_shortened() {
  local out version
  out="$(NC='' GREEN='' BRBLUE='' BRYELLOW='' _HI_RELEASE="" timestamp)"
  version="$(cut -d'|' -f3 <<<"$out" | tr -d ' ')"
  [[ "$version" != *-g[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]* && "$version" != *-dirty ]] &&
    [ "${#version}" -le 10 ] || _hi_why version
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
  [[ "$out" == *"Cores:"* && "$out" == *"RAM:"* && "$out" == *"CPU:"* ]] || _hi_why out
}

# the uptime cell is an identity-group word - the sysinfo row must not carry it
function test_system_info_does_not_show_uptime() {
  local out
  out="$(_hi_sysinfo_row)"
  [[ "$out" != *"Up:"* ]] || _hi_why out
}

# GHz is the only format the CPU cell renders now - one pin so a regression
# back to whole MHz integers is caught
function test_system_info_cpu_cell_is_ghz() {
  local out
  out="$(_hi_sysinfo_row)"
  [[ "$out" == *"GHz"* ]] || _hi_why out
}

# the CPU cell sits right after Cores:, with RAM: behind it
function test_system_info_cpu_cell_sits_next_to_cores() {
  local out cores_pos cpu_pos ram_pos
  out="$(_hi_sysinfo_row)"
  cores_pos="$(_hi_pos "$out" "Cores:")"
  cpu_pos="$(_hi_pos "$out" "CPU:")"
  ram_pos="$(_hi_pos "$out" "RAM:")"
  { [ -n "$cores_pos" ] && [ -n "$cpu_pos" ] && [ -n "$ram_pos" ] &&
    ((cores_pos < cpu_pos)) && ((cpu_pos < ram_pos)); } || _hi_why cores_pos cpu_pos ram_pos
}

# _hi_ghz's own contract, from its comment: rounded to tenths *before*
# splitting, so a carry lands in the whole-GHz digit (2950 -> 3.0) rather than
# spilling into a second decimal (2.10) - the CPU cell's cases above only
# ever see the already-rounded strings this produces.
function test_ghz_rounds_the_carry_into_the_whole_digit() {
  local out
  _hi_ghz out 2950
  [ "$out" = 3.0 ] || _hi_why out || return 1
  _hi_var_is 2.9 _hi_ghz 2949 || return 1
  _hi_var_is 2.1 _hi_ghz 2100
}

# _hi_load_pct's own contract: load divided by cores, rounded to a whole
# percent, empty rather than a garbled or divide-by-zero cell whenever either
# input can't back that math up
function test_hi_load_pct_divides_load_by_cores() {
  _hi_var_is 50 _hi_load_pct 2.00 4
}

# _hi_cell_uptime: at most two units, largest first, or "?" where no probe
# answers - the shape is pinned rather than a value, which moves by the second
function test_uptime_cell_is_humanized() {
  local out
  _hi_cell_uptime out
  [[ "$out" =~ Up:\ ([0-9]+d\ [0-9]+h|[0-9]+h\ [0-9]+m|[0-9]+m|\?) ]] || _hi_why out
}

# _hi_cell_ip: dotted-quad addresses joined with ", ", or "?" - the shape is
# pinned rather than a value, which depends on this box's own network config
function test_ip_cell_has_a_shape() {
  local out
  # none: in a container the only address is often docker's 172.*, hidden by
  # default, and an empty cell has no shape to check
  _HI_IP_HIDE=none _hi_cell_ip out
  [[ "$out" =~ IP:\ ([0-9]{1,3}(\.[0-9]{1,3}){3}(,\ [0-9]{1,3}(\.[0-9]{1,3}){3})*|\?) ]] || _hi_why out
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
  [[ "$out" =~ RAM:\ ([0-9]+/[0-9]+G|[0-9]+G|\?) ]] && [[ "$out" != *"G/"* ]] || _hi_why out
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
  [[ -z "$load" || "$load" =~ ^[0-9]+%$ ]] || _hi_why load
}

# ...and the GHz cell carries nothing of its own in parens - the one
# thing this rides on is the clock figure itself
function test_system_info_cpu_cell_has_no_parenthetical() {
  local out
  out="$(_hi_sysinfo_row)"
  [[ "$out" != *"GHz ("* ]] || _hi_why out
}

function test_identity_includes_static_labels() {
  local out
  out="$(_hi_identity_row)"
  [[ "$out" == *"Auth:"* && "$out" == *"Pub:"* ]] || _hi_why out
}

# the key cells count what is there: Auth a line of authorized_keys each, Pub
# a *.pub file each anywhere under ~/.ssh and nothing else; with neither, 0
function test_identity_counts_the_keys() {
  local home="$_HI_WORKDIR/idkeys" out
  mkdir -p "$home/.ssh/old"
  printf '%s\n' 'ssh-ed25519 AAAA one' 'ssh-ed25519 AAAA two' 'ssh-rsa AAAA three' >"$home/.ssh/authorized_keys"
  : >"$home/.ssh/id_ed25519.pub"
  : >"$home/.ssh/old/id_rsa.pub"
  : >"$home/.ssh/id_ed25519"
  : >"$home/.ssh/config"
  out="$(HOME="$home" _hi_identity_with "$(_hi_identity_path)")"
  out="$(_hi_strip_ansi "$out")"
  [[ "$out" == *"Auth: 3"* && "$out" == *"Pub: 2"* ]] || _hi_why out || return 1
  out="$(HOME="$_HI_WORKDIR/idkeys-none" _hi_identity_with "$(_hi_identity_path)")"
  out="$(_hi_strip_ansi "$out")"
  [[ "$out" == *"Auth: 0"* && "$out" == *"Pub: 0"* ]] || _hi_why out
}

# uptime rides at the end of the identity row, after Auth:/Pub: - not a
# row of its own
function test_identity_includes_uptime_cell_last() {
  local out auth_pos pub_pos up_pos
  out="$(_hi_identity_row)"
  auth_pos="$(_hi_pos "$out" "Auth:")"
  pub_pos="$(_hi_pos "$out" "Pub:")"
  up_pos="$(_hi_pos "$out" "Up:")"
  { [ -n "$auth_pos" ] && [ -n "$pub_pos" ] && [ -n "$up_pos" ] &&
    ((auth_pos < pub_pos)) && ((pub_pos < up_pos)); } || _hi_why auth_pos pub_pos up_pos
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
  local dir="${_HI_SUITE_WORKDIR:-$_HI_WORKDIR}/backend-$name-$count"
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
  local dir="${_HI_SUITE_WORKDIR:-$_HI_WORKDIR}/backend-kube-$count"
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
  [[ "$out" != *"Containers:"* && "$out" != *"Jobs:"* && "$out" != *"Pods:"* && "$out" != *"docker/podman"* ]] || _hi_why out
}

# test_identity_shows_count <backend> <n> <label> - once found, the count
# shows even at zero: a probed-and-idle backend is distinguishable from an
# absent one
function test_identity_shows_count() {
  local shim got
  if [ "$1" = kube ]; then shim="$(_hi_kube_shim "$2")"; else shim="$(_hi_backend_shim "$1" "$2")"; fi
  got="$(_hi_identity_with "$shim")"
  [[ "$got" == *"$3: $2"* ]] || _hi_why got shim
}

# shellcheck disable=SC2209 # the literal command name "sh" is intentional, not a botched `sh` invocation
_HI_REAL_CMD=sh

# _hi_pkg_one <name> <body> - a packages file at $_HI_WORKDIR/<name>/packages
# holding <body> (%b, so \n is a line break). Prints the file, for
# $_HI_PACKAGES. Rows above the first `[group]` line always run, so a body
# with no table needs no $_HI_PACKAGES_GROUPS.
function _hi_pkg_one() {
  mkdir -p "$_HI_WORKDIR/$1"
  printf '%b' "$2" >"$_HI_WORKDIR/$1/packages"
  printf '%s' "$_HI_WORKDIR/$1/packages"
}

# a real render, banner included - every line ends in the same column, at a
# width comfortable enough that the banner's own floor behavior (its narrow-
# width cases, above) doesn't kick in and confound this one
function test_hi_header_closes_every_line() {
  local out _HI_HOSTNAME_CACHE=short-host
  out="$(
    unset _HI_BANNER_HOST
    _HI_PACKAGES="$(_hi_pkg_one close-e2e "$_HI_REAL_CMD = []\nbash = []\n")" \
    _HI_MAX_WIDTH=40 _HI_HEADER_ORDER="utc version localtime uptime check" hi_header Connected
  )"
  _hi_all_lines_are "$out" 40 || _hi_why out
}

# ...and hi_footer's banner-plus-timestamp shape closes the same way
function test_hi_footer_closes_every_line() {
  local out _HI_HOSTNAME_CACHE=short-host
  out="$(
    unset _HI_BANNER_HOST
    _HI_MAX_WIDTH=40 _HI_HEADER_ORDER="utc version localtime" hi_footer Disconnected
  )"
  _hi_all_lines_are "$out" 40 || _hi_why out
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

# full_check's own wrap loop, not _hi_row_line's - it needs the same closing
# column, on every wrapped line including the last. bash is a second real
# command, the wrap case above leans on it the same way.
function test_full_check_closes_every_row_at_max_width() {
  local out lines
  out="$(_HI_PACKAGES="$(_hi_pkg_one close "$_HI_REAL_CMD = []\nbash = []\n")" _HI_MAX_WIDTH=12 full_check)"
  lines="$(printf '%s\n' "$out" | grep -c .)"
  { [ "$lines" -ge 2 ] && _hi_all_lines_are "$out" 12; } || _hi_why lines out
}

# the carry rides in full_check's own edge too - the path that lost it before
# full_check grew a closing arm of its own
function test_full_check_closes_a_row_that_absorbed_a_carry() {
  local out
  local -a _HI_ROW_CARRY=(carriedcell)
  out="$(_HI_PACKAGES="$(_hi_pkg_one close-carry "$_HI_REAL_CMD = []\nbash = []\n")" _HI_MAX_WIDTH=20 full_check)"
  _hi_all_lines_are "$out" 20 || _hi_why out
}

function test_full_check_right_edge_disabled_stays_under_max_width() {
  local out line n got
  out="$(_HI_PACKAGES="$(_hi_pkg_one no-edge "$_HI_REAL_CMD = []\nbash = []\n")" _HI_MAX_WIDTH=20 _HI_DISABLE_RIGHT_EDGE=1 full_check)"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    got="$(_hi_strip_ansi "$line")"
    [[ "$got" != *"|" ]] || _hi_why got line || return 1
    _hi_visible_width n "$(_hi_strip_ansi "$line")"
    ((n < 20)) || _hi_why || return 1
  done <<<"$out"
}

# _hi_header_begin - what every part of this suite starts from, and the tally
function _hi_header_begin() {
  _hi_workdir headertest
  _hi_suite_begin
}

# _hi_linux_probe_fixtures - the files the Linux probes read, staged once: a
# /proc/meminfo with and without MemAvailable (a pre-3.14 kernel has none,
# and still has a total to print), a /proc/cpuinfo whose model name carries
# the clock with a decimal, one without, one that carries none (AMD), and
# cpufreq directories holding base_frequency, amd-pstate's floor, or a 0.
# Prints the directory.
function _hi_linux_probe_fixtures() {
  local d="$_HI_WORKDIR/linux-probes"
  mkdir -p "$d/freq-base" "$d/freq-amd" "$d/freq-zero"
  printf 'MemTotal:       16384000 kB\nMemFree:         1000000 kB\nMemAvailable:    8192000 kB\n' >"$d/meminfo"
  printf 'MemTotal:       16384000 kB\nMemFree:         1000000 kB\n' >"$d/meminfo-old"
  printf 'processor\t: 0\nmodel name\t: Intel(R) Core(TM) i7-7700HQ CPU @ 2.80GHz\nmodel name\t: other @ 9.99GHz\n' >"$d/cpuinfo-intel"
  printf 'model name\t: Some CPU @ 3GHz\n' >"$d/cpuinfo-whole"
  printf 'model name\t: AMD Ryzen 9 5900X 12-Core Processor\n' >"$d/cpuinfo-amd"
  printf '3700000\n' >"$d/freq-base/base_frequency"
  printf '2800000\n' >"$d/freq-amd/amd_pstate_lowest_nonlinear_freq"
  printf '0\n' >"$d/freq-zero/base_frequency"
  printf '%s' "$d"
}

# A session's tree comes with an empty hi.probes, which the probes take and
# leave to the tree's removal; one a session before left files in (a held
# tree, taken) is passed over for a directory of their own, removed after
function test_probe_dir_takes_a_trees_empty_one_once() {
  local t="$_HI_WORKDIR/probetree" got
  mkdir -p "$t/hi.probes"
  got="$(
    _HI_CLEANUP="$t" _HI_PROBE_DIR="" _HI_PROBE_HOLD=""
    _hi_probe_dir && printf '%s\n' "$_HI_PROBE_DIR" && : >"$_HI_PROBE_DIR/pf.x"
    _hi_probe_done
    [ -d "$t/hi.probes" ] && printf 'kept\n'
    _hi_probe_dir && printf '%s\n' "$_HI_PROBE_DIR" && d="$_HI_PROBE_DIR"
    _hi_probe_done
    [ -e "$d" ] || printf 'removed\n'
  )"
  case "$got" in
  "$t/hi.probes"$'\nkept\n'*/hi.probes.*$'\nremoved') ;;
  *) _hi_because "the probes' directories: $got" ;;
  esac
}

function run_header_tests() {
  _hi_header_begin

  _hi_h1 "Testing common/header.sh"

  _hi_h2 "Testing: header_row"
  _hi_check "Joins multiple cells" test_header_row_joins_cells
  _hi_check "Handles a single cell" test_header_row_single_cell
  _hi_check "Default width stays one line" test_header_row_default_width_stays_one_line
  _hi_check "Wraps at a narrow _HI_MAX_WIDTH" test_header_row_wraps_at_max_width
  _hi_check "Wrap keeps every cell intact" test_header_row_wrap_keeps_cells_intact
  _hi_check "_hi_visible_width strips a leading color" test_hi_visible_width_strips_a_leading_color
  _hi_check "...plain text is unchanged" test_hi_visible_width_plain_text_unchanged
  _hi_check "...a color opened midway does not count either" test_hi_visible_width_strips_a_color_midway
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

  _hi_h2 "Testing: the probes' directory"
  _hi_check "A tree's empty one is taken once, and left to the tree" test_probe_dir_takes_a_trees_empty_one_once

  _hi_h2 "Testing: timestamp / sysinfo / identity rows (smoke tests)"
  _hi_check "Timestamp prints three cells" test_timestamp_runs_and_has_three_cells
  _hi_check "The version sits between the clocks" test_timestamp_puts_the_version_between_the_clocks
  _hi_check "Without a stamp the version still resolves" test_timestamp_version_falls_back_without_a_stamp
  _hi_check "_hi_header_version resolves once per shell" test_header_version_resolves_once_per_shell
  # _hi_shorten_describe's own contract: 10 columns, no -dirty, a bare hash
  # cut to 6, and a <tag>+N too long for the cap losing its count, not a digit
  _hi_check_eq "Shows <tag>+N past a tag" v1.0.0+5 _hi_shorten_describe v1.0.0+5
  _hi_check_eq "...drops the -dirty suffix" v1.0.0+5 _hi_shorten_describe v1.0.0+5-dirty
  _hi_check_eq "...ends a <tag>+N over the cap at the +" v0.10.10+ _hi_shorten_describe v0.10.10+123
  _hi_check_eq "...trims a bare hash to 6" 9c1dd0 _hi_shorten_describe 9c1dd0fabc
  _hi_check_eq "...leaves an exact tag alone" v1.0.0 _hi_shorten_describe v1.0.0
  _hi_check_eq "...leaves a release stamp alone" 1.2.3 _hi_shorten_describe 1.2.3
  _hi_check_eq "...leaves 'unknown' alone" unknown _hi_shorten_describe unknown
  _hi_check_eq "...caps a long exact tag at 10 columns" snapshot-6 _hi_shorten_describe snapshot-6fba937
  _hi_check "The version cell itself is shortened" test_timestamp_version_cell_is_shortened
  _hi_check "System_info includes its static labels" test_system_info_includes_static_labels
  _hi_check "System_info does not show uptime" test_system_info_does_not_show_uptime
  _hi_check "System_info's CPU cell renders GHz" test_system_info_cpu_cell_is_ghz
  _hi_check "System_info's CPU cell sits next to Cores:" test_system_info_cpu_cell_sits_next_to_cores
  _hi_check "_hi_ghz rounds the carry into the whole digit" test_ghz_rounds_the_carry_into_the_whole_digit
  # the Linux probes, off fixture files rather than this box's own /proc
  local fx
  fx="$(_hi_linux_probe_fixtures)"
  _hi_check "_hi_linux_ram is used/total, kB to GiB" _hi_var_is 8/16G _hi_linux_ram "$fx/meminfo"
  _hi_check "...the total alone without MemAvailable" _hi_var_is 16G _hi_linux_ram "$fx/meminfo-old"
  _hi_check "...empty without the file" _hi_var_is "" _hi_linux_ram "$fx/none"
  _hi_check "_hi_linux_base_mhz reads the first model name's clock" _hi_var_is 2800 _hi_linux_base_mhz "$fx/cpuinfo-intel" "$fx/none"
  _hi_check "...a whole-GHz clock too" _hi_var_is 3000 _hi_linux_base_mhz "$fx/cpuinfo-whole" "$fx/none"
  _hi_check "...ahead of cpufreq" _hi_var_is 2800 _hi_linux_base_mhz "$fx/cpuinfo-intel" "$fx/freq-base"
  _hi_check "...falls to cpufreq's base_frequency" _hi_var_is 3700 _hi_linux_base_mhz "$fx/cpuinfo-amd" "$fx/freq-base"
  _hi_check "...then to amd-pstate's floor" _hi_var_is 2800 _hi_linux_base_mhz "$fx/cpuinfo-amd" "$fx/freq-amd"
  _hi_check "...and a 0 there reads as none" _hi_var_is "" _hi_linux_base_mhz "$fx/cpuinfo-amd" "$fx/freq-zero"
  _hi_check "...empty with neither file" _hi_var_is "" _hi_linux_base_mhz "$fx/none" "$fx/none"
  _hi_check "_hi_load_pct divides load by cores" test_hi_load_pct_divides_load_by_cores
  _hi_check "...rounds to a whole percent" _hi_var_is 33 _hi_load_pct 1.00 3
  _hi_check "...empty without a load figure" _hi_var_is "" _hi_load_pct "" 4
  _hi_check "...empty without a core count" _hi_var_is "" _hi_load_pct 2.00 ""
  # "?" is the Windows fallback's own unresolved sentinel - never divided
  # into, just passed straight through to the cell as "Cores: ?"
  _hi_check "...empty when cores isn't numeric" _hi_var_is "" _hi_load_pct 2.00 "?"
  _hi_check "...empty when cores is zero" _hi_var_is "" _hi_load_pct 2.00 0
  _hi_check "System_info's RAM cell is used/total" test_system_info_ram_cell_is_used_over_total
  _hi_check "System_info's load figure rides the Cores cell" test_system_info_load_rides_the_cores_cell
  _hi_check "...and the GHz cell does not carry it" test_system_info_cpu_cell_has_no_parenthetical
  _hi_check "The uptime cell is humanized" test_uptime_cell_is_humanized
  _hi_check "The ip cell has a shape" test_ip_cell_has_a_shape
  _hi_check "Identity includes its static labels" test_identity_includes_static_labels
  _hi_check "Identity's uptime cell rides last" test_identity_includes_uptime_cell_last
  _hi_check "Auth and Pub count the keys there are" test_identity_counts_the_keys
  _hi_check "No cells at all when no backend is found" test_identity_hides_all_backend_cells_when_none_found
  _hi_check "Containers: 0 when docker is found but empty" test_identity_shows_count docker 0 Containers
  _hi_check "Containers count when docker is found" test_identity_shows_count docker 3 Containers
  _hi_check "Jobs: 0 when nomad is found but idle" test_identity_shows_count nomad 0 Jobs
  _hi_check "Jobs count excludes nomad's header row" test_identity_shows_count nomad 2 Jobs
  _hi_check "Pods: 0 when kube is found but empty" test_identity_shows_count kube 0 Pods
  _hi_check "Pods count when kube is found" test_identity_shows_count kube 2 Pods

  _hi_suite_end "header.sh"
}

# a part (header_*_test.sh) sources this file for what is above and runs its own
[ -n "${_HI_HEADER_PART:-}" ] || run_header_tests
