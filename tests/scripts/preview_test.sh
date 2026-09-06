#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Unit tests for scripts/preview.sh - `hi --preview colors`, `packages` and
# `header`, one script with a subject switch.
#
# colors: its job is to render the same answers the live prompt would give, so
# what matters is that its own precedence logic (_hi_color_source) agrees with
# common/core.sh's _hi_resolve_color, and that the helpers feeding the table
# read settings/colors the way the rest of hi does. Everything runs against a
# fixture settings/colors and ~/.ssh/config in the scratch dir, so the output
# is fixed rather than "whatever this machine is configured with".
#
# packages: the preview's whole claim is that it shows what the *header* will
# do, so what matters is that it reads its facts from header.sh rather than
# from a copy: the priority meanings out of the comment block, the colors out
# of _HI_YES and _HI_NO, and every example row out of check_line itself. The
# cases pin those seams, plus the table geometry, against a fixture packages
# file and a PATH holding exactly the packages the fixture calls installed.
#
# The child renders (_hi_render_colors, _hi_render_packages) run the real
# script; the in-process cases call its functions through the source hatch.
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"
# its own hatch stops it before it renders anything; sourcing hands over the
# helpers, and (through it) header.sh's check_line
# shellcheck source=../../scripts/preview.sh
source "$_HI_PREVIEW"

# One scratch tree for both halves: the colors fixtures and the ssh config a
# child render derives its paths from, and the packages roster in the tree.
function _hi_write_preview_tree() {
  local home
  home="$(_hi_scratch_tree tree common settings scripts)"
  mkdir -p "$home/.ssh"
  cp "$_HI_WORKDIR/colors" "$home/say-hi/settings/colors"
  cp "$_HI_WORKDIR/ssh_config" "$home/.ssh/config"
  cp "$_HI_WORKDIR/packages" "$home/say-hi/settings/packages"
}

#
# the subject switch
#

# a bare `preview.sh` is a usage error, never a silent default subject
function test_a_missing_subject_is_refused() {
  local out rc=0
  out="$(HOME="$_HI_WORKDIR/tree" _HI_HOME="$_HI_WORKDIR/tree" \
    "$_HI_WORKDIR/tree/say-hi/scripts/preview.sh" 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"one of colors, packages or header"* ]]
}

function test_an_unknown_subject_is_refused() {
  local out rc=0
  out="$(HOME="$_HI_WORKDIR/tree" _HI_HOME="$_HI_WORKDIR/tree" \
    "$_HI_WORKDIR/tree/say-hi/scripts/preview.sh" swatches 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"unknown subject 'swatches'"* ]]
}

# --help with no subject lists the three, and exits 0
function test_bare_help_lists_the_subjects() {
  local out
  out="$(HOME="$_HI_WORKDIR/tree" _HI_HOME="$_HI_WORKDIR/tree" \
    "$_HI_WORKDIR/tree/say-hi/scripts/preview.sh" --help 2>&1)" || return 1
  [[ "$out" == 'Usage: preview.sh <colors|packages|header>'* && "$out" == *header* ]]
}

# the header subject is hi_header itself, under the settings.sh in force
function test_header_subject_renders_the_header() {
  local out
  out="$(HOME="$_HI_WORKDIR/tree" _HI_HOME="$_HI_WORKDIR/tree" _HI_CONFIG_DIR="$_HI_WORKDIR/nocfg" \
    _HI_DISABLE_BANNER=1 _HI_HEADER_ORDER="version" _HI_TARGETS_TTL=0 \
    "$_HI_WORKDIR/tree/say-hi/scripts/preview.sh" header 2>&1)" || return 1
  [[ "$out" == *"| "* ]]
}

function test_header_subject_refuses_an_argument() {
  local out rc=0
  out="$(HOME="$_HI_WORKDIR/tree" _HI_HOME="$_HI_WORKDIR/tree" \
    "$_HI_WORKDIR/tree/say-hi/scripts/preview.sh" header nonsense 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"takes no arguments"* ]]
}

#
# colors
#

function _hi_write_color_fixtures() {
  cat >"$_HI_WORKDIR/colors" <<'EOF'
#type,name,color
username,alice,brmagenta
username,LOCALUSER,brgreen
usertag,ops,brred
hostname,pinned,brcyan
hosttag,work,bryellow
hostname,pat-*,brblue
EOF

  cat >"$_HI_WORKDIR/ssh_config" <<'EOF'
Host plain
  User nobody

Host pinned
  User nobody

# Tags: work
Host tagged
  User nobody

# Tags: unlisted
Host othertag
  User nobody

Host pat-1
  User nobody

# longer than the HOST column's own floor, and grouped with `tagged`, so the
# rendered table has to widen for it and wrap the pair - see
# test_color_tables_are_rectangular
# Tags: work
Host a-considerably-longer-hostname
  User nobody
EOF

  export _HI_COLORS="$_HI_WORKDIR/colors"
  export _HI_SSH_CONFIG="$_HI_WORKDIR/ssh_config"
  # pin the "local" identities so LOCALUSER/LOCALHOSTNAME don't depend on
  # whoever happens to be running the suite
  export _HI_LOCAL_USER=localdev
  export _HI_LOCAL_HOSTNAME=localbox
}

# usernames have no ssh config to carry tags, so the tag branch must not fire
# for them even when a usertag of that name exists
function test_source_never_reports_a_tag_for_a_username() {
  [[ "$(_hi_color_source username ops)" != tag:* ]]
}

# the preview exists to show what the prompt will do; if these two ever
# disagree the table is confidently wrong, which is worse than no table
function test_source_agrees_with_resolve_color_on_overrides() {
  [ "$(_hi_resolve_color hostname pinned)" = brcyan ] &&
    [ "$(_hi_color_source hostname pinned)" = "override:hostname" ]
}

function test_source_agrees_with_resolve_color_on_tags() {
  [ "$(_hi_resolve_color hostname tagged)" = bryellow ] &&
    [ "$(_hi_color_source hostname tagged)" = "tag:work" ]
}

function test_source_agrees_with_resolve_color_on_patterns() {
  [ "$(_hi_resolve_color hostname pat-1)" = brblue ] &&
    [ "$(_hi_color_source hostname pat-1)" = "pattern:pat-*" ]
}

function test_default_source_still_resolves_to_a_palette_color() {
  local color
  color="$(_hi_resolve_color hostname plain)"
  [ "$(_hi_color_source hostname plain)" = default ] &&
    printf '%s\n' "${_HI_COLOR_NAMES[@]}" | grep -qxF "$color"
}

function test_colors_names_dedupes_and_skips() {
  local colors="$_HI_WORKDIR/colors.names" out
  printf 'hostname,a,red\nhostname,b,blue\nhostname,a,green\nusername,c,red\n' >"$colors"
  out="$(_HI_COLORS="$colors" _hi_colors_names hostname)"
  [ "$out" = "a
b" ] || return 1
  [ "$(_HI_COLORS="$colors" _hi_colors_names hostname a)" = b ]
}

function test_known_users_includes_the_current_user() {
  _hi_known_users | grep -qxF "$(whoami)"
}

function test_known_users_includes_override_names() {
  _hi_known_users | grep -qxF alice
}

# LOCALUSER is a placeholder for "whoever is running this", not a login name -
# listing it verbatim would offer a user that doesn't exist
function test_known_users_excludes_the_localuser_placeholder() {
  ! _hi_known_users | grep -qxF LOCALUSER
}

function test_known_users_are_deduplicated() {
  [ "$(_hi_known_users | sort | uniq -d | wc -l)" -eq 0 ]
}

function test_known_usertags_lists_only_usertags() {
  local out
  out="$(_hi_known_usertags)"
  printf '%s\n' "$out" | grep -qxF ops || return 1
  ! printf '%s\n' "$out" | grep -qxF work # that one's a hosttag
}

function test_preview_users_adds_a_row_per_usertag() {
  _hi_preview_users | grep -qxF ops
}

function test_preview_users_are_deduplicated() {
  [ "$(_hi_preview_users | sort | uniq -d | wc -l)" -eq 0 ]
}

# `plain` is covered by no glob, and `pinned`'s exact row must not answer
# either - exact pins are _hi_colors_lookup's business, never a pattern's
function test_pattern_for_misses_uncovered_names() {
  ! _hi_pattern_for plain || return 1
  ! _hi_pattern_for pinned
}

# every subnet-style pin once, in file order; exact rows and other types
# don't qualify
function test_pattern_pins_dedupe_in_file_order() {
  local colors="$_HI_WORKDIR/colors.pins"
  printf 'hostname,net-*,red\nhostname,exact,blue\nusername,u-*,green\nhostname,db-?,cyan\nhostname,net-*,green\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _hi_pattern_pins)" = 'net-*
db-?' ]
}

# no colors file: no glob to answer with, no pins to list, and no error
# under set -e
function test_pattern_helpers_tolerate_a_missing_colors_file() {
  ! _HI_COLORS="$_HI_WORKDIR/absent" _hi_pattern_for pat-1 || return 1
  [ -z "$(_HI_COLORS="$_HI_WORKDIR/absent" _hi_pattern_pins)" ]
}

# _hi_group_index reads the caller's group_order through dynamic scoping,
# exactly as _hi_print_hosts_table uses it
function test_group_index_finds_an_existing_key() {
  local group_order=(alpha beta gamma)
  [ "$(_hi_group_index beta)" = 1 ] && [ "$(_hi_group_index gamma)" = 2 ]
}

function test_group_index_misses_a_new_key() {
  local group_order=(alpha beta)
  ! _hi_group_index gamma
}

# no groups yet leaves group_order empty, which must read as a miss rather
# than tripping set -u (the ${a[@]+...} guard the file leans on throughout)
function test_group_index_handles_an_empty_table() {
  local group_order=()
  ! _hi_group_index anything
}

# widths are per-host: user_width + a space + the host name, plus two spaces
# between each pair of groups
function test_group_preview_width_sums_its_hosts() {
  local user_width=4
  [ "$(_hi_group_preview_width abc de)" = "$((4 + 1 + 3 + 4 + 1 + 2 + 2))" ]
}

# The two table renderers, called in-process against the exported fixtures
# (they read $_HI_COLORS/$_HI_SSH_CONFIG directly, unlike the full-script
# render below). _HI_WHOAMI_CACHE pins the current user's name so "a user with
# no pin" doesn't depend on who runs the suite; each table renders once and
# the later cases read the shared variable, for _HI_COLORS_OUT's reasons.
_HI_USERS_OUT=""
_HI_HOSTS_OUT=""

function test_users_table_renders_override_rows() {
  _HI_USERS_OUT="$(_HI_WHOAMI_CACHE=defaultuser _hi_print_users_table)" || return 1
  [[ "$_HI_USERS_OUT" == *alice* && "$_HI_USERS_OUT" == *brmagenta* && "$_HI_USERS_OUT" == *override:username* ]]
}

# a user with no pin renders exactly as a bare `hi` does, so the table leaves
# the row out - same rule as the hosts the script's help text explains
function test_users_table_skips_default_users() {
  [[ "$_HI_USERS_OUT" != *defaultuser* ]]
}

# LOCALUSER is a placeholder, not a login name, so its pin renders as its own
# example row rather than as a user
function test_users_table_shows_the_localuser_pin() {
  [[ "$_HI_USERS_OUT" == *LOCALUSER* && "$_HI_USERS_OUT" == *local:username* ]]
}

function test_users_table_shows_each_usertag() {
  [[ "$_HI_USERS_OUT" == *usertag:ops* && "$_HI_USERS_OUT" == *brred* ]]
}

# targets.sh's sweep cache would happily serve a previous render's host list;
# _hi_render_colors below says why TTL=0 is the cure
function _hi_render_hosts_table() {
  _HI_TARGETS_TTL=0 _hi_print_hosts_table 2>&1
}

# tagged and a-considerably-longer-hostname share a tag and a color, so they
# collapse into one tag:work group row - grouping is the table's whole point
function test_hosts_table_groups_identical_renders() {
  _HI_HOSTS_OUT="$(_hi_render_hosts_table)" || return 1
  [[ "$_HI_HOSTS_OUT" == *tagged* && "$_HI_HOSTS_OUT" == *a-considerably-longer-hostname* ]] || return 1
  [ "$(printf '%s\n' "$_HI_HOSTS_OUT" | grep -c 'tag:work')" -eq 1 ]
}

# the glob seeds its own example row, and a real host it covers joins that
# same group rather than getting a second one
function test_hosts_table_merges_pattern_hosts_into_the_example_row() {
  [ "$(printf '%s\n' "$_HI_HOSTS_OUT" | grep -c 'pattern:pat-')" -eq 1 ] || return 1
  [[ "$_HI_HOSTS_OUT" == *'pat-*, pat-1'* ]]
}

# a LOCALHOSTNAME pin renders the current machine as its own single-host
# group ahead of the ssh ones
function test_hosts_table_leads_with_a_localhostname_pin() {
  local colors="$_HI_WORKDIR/colors.localhost" out
  cat "$_HI_WORKDIR/colors" >"$colors"
  printf 'hostname,LOCALHOSTNAME,brgreen\n' >>"$colors"
  out="$(_HI_COLORS="$colors" _hi_render_hosts_table)" || return 1
  [[ "$out" == *localbox* && "$out" == *local:hostname* ]] || return 1
  # ahead of: nothing before the localbox row but the header
  [[ "${out%%localbox*}" != *override:hostname* ]]
}

# with no ssh config there is nothing to walk; the table says so instead of
# quietly rendering an empty box
function test_hosts_table_reports_a_missing_ssh_config() {
  local out
  out="$(_HI_SSH_CONFIG="$_HI_WORKDIR/absent" _hi_render_hosts_table)" || return 1
  [[ "$out" == *"No ssh config found at $_HI_WORKDIR/absent"* ]]
}

# Running the real script can't reuse the exported fixtures above: paths.sh
# re-exports $_HI_COLORS from $_HI_ROOT and $_HI_SSH_CONFIG from $HOME every
# time it's sourced, so the only way to point the script at fixtures is to
# give it a scratch tree and a scratch $HOME to derive them from.
function _hi_render_colors() {
  # _HI_TARGETS_TTL=0: targets.sh's sweep cache is keyed by kind alone
  # (hi.targets.ssh under $XDG_RUNTIME_DIR), so within the TTL a render here
  # would happily reuse the host list a *previous* run's fixtures produced
  HOME="$_HI_WORKDIR/tree" _HI_HOME="$_HI_WORKDIR/tree" \
    _HI_LOCAL_USER=localdev _HI_LOCAL_HOSTNAME=localbox _HI_TARGETS_TTL=0 \
    "$_HI_WORKDIR/tree/say-hi/scripts/preview.sh" colors "$@" 2>&1
}

# The tables are wide, colored and layout-heavy; asserting their exact shape
# would test the formatting rather than the resolution, so these prove they
# render every group they should without erroring under set -e. One render
# (the slowest thing this suite does - a full script run plus targets.sh)
# shared by all three cases; each reads the whole output from a variable
# rather than piping into grep, because under `set -o pipefail` an
# early-exiting `grep -q` SIGPIPEs the script and a negated case then passes
# no matter what the table said.
_HI_COLORS_OUT=""

function test_tables_render_without_error() {
  _HI_COLORS_OUT="$(_hi_render_colors)" || return 1
  [[ "$_HI_COLORS_OUT" == *pinned* && "$_HI_COLORS_OUT" == *tagged* && "$_HI_COLORS_OUT" == *alice* ]]
}

# a host with no override and no usable tag would render identically to a bare
# `hi`, so it's deliberately left out of the table
# a scheme paints the swatches with the 24-bit tail, and the header line
# says which scheme it is (HI.50)
function test_tables_render_under_a_scheme() {
  local out
  out="$(_HI_COLOR_SCHEME=catppuccin _HI_TRUECOLOR=1 _hi_render_colors)" || return 1
  [[ "$out" == *"scheme: catppuccin"* && "$out" == *";38;2;"* ]] || return 1
  out="$(_HI_COLOR_SCHEME="" _HI_TRUECOLOR=0 _hi_render_colors)" || return 1
  [[ "$out" == *"scheme: default"* && "$out" != *";38;2;"* ]]
}

function test_tables_skip_hosts_that_render_by_default() {
  ! printf '%s\n' "$_HI_COLORS_OUT" | grep -q '\bplain\b'
}

# the tag column has to name the tag that actually matched, since that's the
# line a user reads to work out which settings/colors entry to edit
function test_tables_name_the_matching_tag() {
  printf '%s\n' "$_HI_COLORS_OUT" | grep -q 'tag:work'
}

# a pattern pin gets an example row (its glob never appears in targets.sh's
# list), and a real host it covers joins that same group
function test_tables_show_a_pattern_pin_example_row() {
  printf '%s\n' "$_HI_COLORS_OUT" | grep -q 'pattern:pat-\*' || return 1
  printf '%s\n' "$_HI_COLORS_OUT" | grep -q 'pat-1'
}

# --help answers before reading any config, prints the usage text and exits 0
function test_help_prints_usage_and_exits_zero() {
  local out
  out="$(_hi_render_colors --help)" || return 1
  [[ "$out" == 'Usage: preview.sh colors'* ]]
}

# -h through the sourced form: source passes its arguments along, and the
# subshell keeps the `exit 0` contained. The inner ( ) is load-bearing twice
# over: a bare `source` directly inside $( ) crashes shellcheck 0.11.0
# ("Non-exhaustive patterns in checkCmd"), and the space before it keeps $( (
# from reading as arithmetic.
function test_colors_stray_argument_is_refused() {
  local out rc=0
  out="$(_hi_render_colors nonsense)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"takes no arguments"* ]]
}

function test_h_flag_prints_the_same_usage() {
  local out
  # source=/dev/null, not the script: followed into this subshell, shellcheck
  # reads every packages global the script assigns as lost on the way out
  # shellcheck source=/dev/null
  out="$( (source "$_HI_PREVIEW" colors -h) )" || return 1
  [[ "$out" == 'Usage: preview.sh colors'* ]]
}

#
# packages
#

function _hi_write_package_fixtures() {
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
  # in-process cases read $_HI_PACKAGES; a child script re-derives it from
  # $_HI_CONFIG_DIR, so the fixture is also an overlay directory
  export _HI_PACKAGES="$_HI_WORKDIR/packages"
  mkdir -p "$_HI_WORKDIR/cfg"
  cp "$_HI_WORKDIR/packages" "$_HI_WORKDIR/cfg/packages"
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
  for name in $(_hi_palette_names); do
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

# One in-process render of the legend (the source hatch hands the function
# over without running it), shared like _HI_PACKAGES_OUT below and for the same
# SIGPIPE reason. In-process rather than through the child render so a failure
# points at the table code, not at whatever the child's environment did.
_HI_PRIO_OUT=""

function test_priorities_table_renders_all_columns() {
  _HI_PRIO_OUT="$(_hi_print_priorities_table)" || return 1
  local stripped
  stripped="$(_hi_strip_ansi "$_HI_PRIO_OUT")"
  [[ "$stripped" == *"| PRIORITY "* && "$stripped" == *"| MEANING "* ]] &&
    [[ "$stripped" == *"| INSTALLED "* && "$stripped" == *"| MISSING "* ]] &&
    [[ "$stripped" == *"| EXAMPLE "* ]]
}

# highest first - the order full_check sorts its own output into, so the two
# halves of the preview read in the same direction
function test_priorities_table_sorts_highest_first() {
  local stripped top bottom
  stripped="$(_hi_strip_ansi "$_HI_PRIO_OUT")"
  top="$(printf '%s\n' "$stripped" | grep -n 'favorites and core' | head -1 | cut -d: -f1)"
  bottom="$(printf '%s\n' "$stripped" | grep -n 'platform trivia' | head -1 | cut -d: -f1)"
  [ -n "$top" ] && [ -n "$bottom" ] && [ "$top" -lt "$bottom" ]
}

# the INSTALLED/MISSING cells name the active ramp's colors - cool is the
# default, whose priority-3 pair is brgreen/brred (header.sh's tables)
function test_priorities_table_names_the_ramp_colors() {
  local row
  row="$(_hi_strip_ansi "$_HI_PRIO_OUT" | grep '^| 3 ')"
  [[ "$row" == *brgreen* && "$row" == *brred* ]]
}

# the EXAMPLE column shows the fixture's own rows, and "below floor" where the
# default floor of 2 keeps a rank off the header entirely
function test_priorities_table_shows_the_real_examples() {
  local stripped
  stripped="$(_hi_strip_ansi "$_HI_PRIO_OUT")"
  [[ "$(printf '%s\n' "$stripped" | grep '^| 3 ')" == *hialpha*highost3* ]] &&
    [[ "$(printf '%s\n' "$stripped" | grep '^| 0 ')" == *"below floor"* ]]
}

# the two lines under the table: the tally, and the floor note naming the
# setting responsible - the same numbers the child render asserts, proved here
# to come from the table code itself
function test_priorities_table_counts_below_the_table() {
  [[ "$_HI_PRIO_OUT" == *"13 listed, 6 shown, 2 hidden"* ]] &&
    [[ "$_HI_PRIO_OUT" == *"\$_HI_PACKAGES_MIN_PRIORITY=2"* ]]
}

# a floor of 0 floors nothing: every rank shows its example and the note has
# nothing to explain. The tally pair is overridden too - the script sets both
# from the same floor before collecting, so a render at floor 0 sees 0 floored.
function test_priorities_table_drops_the_floor_note_at_zero() {
  local out
  out="$(_HI_PKG_MIN=0 _HI_PKG_FLOORED=0 _hi_print_priorities_table)" || return 1
  [[ "$out" != *"below floor"* && "$out" != *_HI_PACKAGES_MIN_PRIORITY* ]] &&
    [[ "$out" == *hidelta* && "$out" == *"13 listed, 11 shown, 2 hidden"* ]]
}

function test_marks_table_explains_every_mark() {
  local out
  out="$(_hi_strip_ansi "$(_hi_print_marks_table)")" || return 1
  [[ "$out" == *"| MARK "* && "$out" == *"| MEANS "* ]] &&
    [[ "$out" == *"installed, under the first name the line lists"* ]] &&
    [[ "$out" == *"installed, but via one of the alternatives after it"* ]] &&
    [[ "$out" == *"not installed - no name on the line resolved"* ]]
}

# each glyph is painted in the color the header paints it - the raw render has
# to carry the resolved escape directly ahead of the mark
function test_marks_table_paints_each_glyph() {
  local out
  out="$(_hi_print_marks_table)" || return 1
  [[ "$out" == *"$(printf '%b' "$GREEN")$_HI_MARK_OK"* ]] &&
    [[ "$out" == *"$(printf '%b' "$RED")$_HI_MARK_NO"* ]]
}

function test_marks_table_is_rectangular() {
  _hi_table_is_rectangular "$(_hi_print_marks_table)"
}

# all three modes, not just the `-` row the child render checks; `none` is a
# literal cell, not a mode character
function test_modes_table_explains_every_mode() {
  local out
  out="$(_hi_strip_ansi "$(_hi_print_modes_table)")" || return 1
  [[ "$out" == *"| MODE "* ]] &&
    [[ "$out" == *"speaks only when the whole line is missing"* ]] &&
    [[ "$out" == *"speaks only when something on the line is installed"* ]] &&
    [[ "$(printf '%s\n' "$out" | grep '^| none ')" == *"speaks both ways - the default"* ]]
}

function test_modes_table_is_rectangular() {
  _hi_table_is_rectangular "$(_hi_print_modes_table)"
}

# The real script, in this tree, reading the exported fixture ($_HI_PACKAGES
# does reach a child: paths.sh keeps a value it did not derive - the per-file
# overlay). The real file rather than a scratch copy so that what these cases
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

# the ordinary path: nothing exported, the tree's own settings/packages is the
# roster - a scratch tree, because this checkout's real file is not the fixture
function test_preview_reads_the_trees_own_file() {
  local out
  out="$(PATH="$(_hi_pkg_path)" HOME="$_HI_WORKDIR/tree" _HI_HOME="$_HI_WORKDIR/tree" \
  _HI_CONFIG_DIR="$_HI_WORKDIR/nocfg" \
    "$_HI_WORKDIR/tree/say-hi/scripts/preview.sh" packages 2>&1)" || return 1
  [[ "$out" == *hialpha* ]] && [[ "$out" == *'13 listed'* ]]
}

# --help exits 0 before any table renders: usage text, the files it reads, and
# nothing of the legend itself
function test_help_prints_usage_and_stops() {
  local out
  out="$(_hi_render_packages_help --help)" || return 1
  [[ "$out" == *"Usage: preview.sh packages"* ]] &&
    [[ "$out" == *"Takes no arguments"* ]] &&
    [[ "$out" != *"| PRIORITY"* ]]
}

# anything that is not -h/--help is an error: the flag takes no arguments,
# and a stray one used to be ignored
function test_packages_stray_argument_is_refused() {
  local out rc=0
  out="$(_hi_render_packages_help nonsense)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"takes no arguments"* && "$out" != *"| PRIORITY"* ]]
}

# One render (the slowest thing this suite does) shared by the cases below;
# each reads it from a variable rather than piping into grep, because under
# `set -o pipefail` an early-exiting `grep -q` SIGPIPEs the script and a
# negated case then passes no matter what the table said.
_HI_PACKAGES_OUT=""

function test_preview_renders_without_error() {
  _HI_PACKAGES_OUT="$(_hi_render_packages)" || return 1
  [[ "$_HI_PACKAGES_OUT" == *PRIORITY* && "$_HI_PACKAGES_OUT" == *MARK* ]]
}

# the eyeball pass _HI_PACKAGES_PALETTE's roadmap entry leans on: the legend
# has to say which named ramp is on screen, not just render one
function test_preview_names_the_active_palette() {
  [[ "$_HI_PACKAGES_OUT" == *"palette: cool"* && "$_HI_PACKAGES_OUT" == *"scheme: default"* ]]
}

# under a scheme the escapes carry a 24-bit tail, and the reverse map still
# has to name them - through a fresh bash, since _HI_COLOR_ESCAPES is
# resolved when the script is sourced (HI.50)
function test_color_name_of_names_scheme_escapes() {
  local out
  # shellcheck disable=SC2016 # the script expands in the child bash, not here
  out="$(env _HI_COLOR_SCHEME=onedark _HI_TRUECOLOR=1 _HI_HOME="$_HI_HOME" bash -c '
    . "$_HI_HOME/say-hi/common/core.sh"
    . "$_HI_HOME/say-hi/scripts/preview.sh"
    printf "%s %s %s" "$(_hi_color_name_of "$BRGREEN")" "$(_hi_color_name_of "$RED")" "$(_hi_color_name_of "$NC")"')"
  [ "$out" = "brgreen red plain" ]
}

# a scheme of the user's own is named by its shape, and a 24-word one paints
# the legend from its second bank - which the reverse map still names, since
# the name is the 16-color half (HI.50)
function test_preview_names_a_custom_scheme_and_its_bank() {
  local out row
  out="$(_HI_COLOR_SCHEME="$_HI_TEST_L24" _HI_TRUECOLOR=1 _hi_render_packages)" || return 1
  [[ "$out" == *"scheme: custom (24)"* ]] || return 1
  row="$(printf '%s\n' "$out" | grep '^| 3 ')"
  # bank 2's brgreen (23d18b) and brred (f14c4c), named as such
  [[ "$row" == *";38;2;35;209;139m"*brgreen* && "$row" == *";38;2;241;76;76m"*brred* ]] || return 1
  out="$(_HI_COLOR_SCHEME="not a scheme" _HI_TRUECOLOR=1 _hi_render_packages)" || return 1
  [[ "$out" == *"scheme: not a scheme (ignored - not a scheme)"* ]]
}

function test_color_name_of_names_second_bank_escapes() {
  local out
  # shellcheck disable=SC2016 # the script expands in the child bash, not here
  out="$(env _HI_COLOR_SCHEME="$_HI_TEST_L24" _HI_TRUECOLOR=1 _HI_HOME="$_HI_HOME" bash -c '
    . "$_HI_HOME/say-hi/common/core.sh"
    . "$_HI_HOME/say-hi/scripts/preview.sh"
    _hi_color_escape_at e 17; _hi_color_escape_at f 12
    printf "%s %s %s" "$(_hi_color_name_of "$e")" "$(_hi_color_name_of "$f")" "$(_hi_color_name_of "$BRGREEN")"')"
  [ "$out" = "cyan red brgreen" ]
}

function test_preview_names_every_priority() {
  local i stripped
  stripped="$(_hi_strip_ansi "$_HI_PACKAGES_OUT")"
  for i in "${!_HI_YES[@]}"; do
    printf '%s\n' "$stripped" | grep -q "^| $i  *| " || return 1
  done
}

# the MODE table is the only place the two mode characters are explained, so
# the render has to carry it and the row that says what `-` does
function test_preview_explains_the_modes() {
  [[ "$_HI_PACKAGES_OUT" == *MODE* ]] &&
    printf '%s\n' "$_HI_PACKAGES_OUT" | grep -q 'speaks only when the whole line is missing'
}

function test_preview_counts_what_it_read() {
  # 6 shown: the default floor of 2 keeps the mode-visible rows of rank 2-3;
  # the three rank-0 and two rank-1 rows sit below it
  printf '%s\n' "$_HI_PACKAGES_OUT" | grep -q '13 listed, 6 shown, 2 hidden'
}

# the check itself is the last thing the preview prints, so a package the
# header would show has to appear below the tables as well as inside them
function test_preview_ends_with_the_real_check() {
  [[ "$(printf '%s\n' "$_HI_PACKAGES_OUT" | tail -3)" == *hialpha* ]]
}

# Every section of the preview reads the packages file, so a missing one is
# said out loud and stops the run - the bare redirect it replaces fails with a
# path and no hint of which file the tool wanted.
# $_HI_CONFIG_DIR points the child at an empty overlay, so the tree's file
# is the only candidate - and the tree has none.
function test_preview_reports_a_missing_packages_file() {
  local home out
  home="$(_hi_scratch_tree nopackages common settings scripts)"
  rm -f "$home/say-hi/settings/packages"
  out="$(PATH="$(_hi_pkg_path)" HOME="$home" _HI_HOME="$home" \
  _HI_CONFIG_DIR="$_HI_WORKDIR/nocfg" \
    "$home/say-hi/scripts/preview.sh" packages 2>&1)" && return 1
  [[ "$out" == *"No packages file"* ]]
}

# ...and an exported $_HI_PACKAGES is not a way in: the script's paths.sh
# re-derives the path from $_HI_CONFIG_DIR and the tree, so the export is
# ignored and the tree's roster comes out. The overlay is the one way to
# point the check at a file of your own.
function test_preview_ignores_an_exported_packages_path() {
  local home out
  home="$(_hi_scratch_tree exportedpkgs common settings scripts)"
  cp "$_HI_WORKDIR/packages" "$home/say-hi/settings/packages"
  printf 'hionlyone:3\n' >"$_HI_WORKDIR/exported-packages"
  out="$(PATH="$(_hi_pkg_path)" HOME="$home" _HI_HOME="$home" \
  _HI_CONFIG_DIR="$_HI_WORKDIR/nocfg" _HI_PACKAGES="$_HI_WORKDIR/exported-packages" \
    "$home/say-hi/scripts/preview.sh" packages 2>&1)" || return 1
  [[ "$out" == *hibravo* ]] && [[ "$out" != *hionlyone* ]]
}

function run_preview_tests() {
  _hi_workdir previewtest
  _hi_write_color_fixtures
  _hi_write_package_fixtures
  _hi_write_preview_tree
  _hi_collect_once

  _hi_h1 "Testing scripts/preview.sh"

  _hi_suite_begin

  _hi_h2 "Testing: the subject switch"
  _hi_check "A missing subject is refused" test_a_missing_subject_is_refused
  _hi_check "An unknown subject is refused" test_an_unknown_subject_is_refused
  _hi_check "--help alone lists the subjects" test_bare_help_lists_the_subjects
  _hi_check "header renders the header" test_header_subject_renders_the_header
  _hi_check "header refuses an argument" test_header_subject_refuses_an_argument

  _hi_h2 "Testing: colors - _hi_color_source"
  # <label>|<kind>|<name>|<want>. Five _hi_color_source cases that differed
  # only in those columns, through _hi_check_eq so a wrong verdict prints what
  # it was instead of a bare FAILED.
  while IFS='|' read -r _label _kind _name _want; do
    case "$_label" in '' | '#'*) continue ;; esac
    _hi_check_eq "$_label" "$_want" _hi_color_source "$_kind" "$_name"
  done <<'EOF'
Exact hostname override|hostname|pinned|override:hostname
Exact username override|username|alice|override:username
Names the ssh tag that matched|hostname|tagged|tag:work
Falls back to default|hostname|plain|default
# a host carrying a tag with no hosttag entry has nothing to inherit, so it
# must read as default rather than claiming a tag it can't resolve
Ignores a tag with no override|hostname|othertag|default
Subnet pattern names its glob|hostname|pat-1|pattern:pat-*
EOF
  _hi_check "Never reports a tag for a username" test_source_never_reports_a_tag_for_a_username

  _hi_h2 "Testing: colors - agreement with _hi_resolve_color"
  _hi_check "Agrees on overrides" test_source_agrees_with_resolve_color_on_overrides
  _hi_check "Agrees on tags" test_source_agrees_with_resolve_color_on_tags
  _hi_check "Agrees on patterns" test_source_agrees_with_resolve_color_on_patterns
  _hi_check "Default still resolves to a palette color" test_default_source_still_resolves_to_a_palette_color

  _hi_h2 "Testing: colors - table inputs"
  _hi_check "_hi_colors_names dedupes and skips" test_colors_names_dedupes_and_skips
  _hi_check "Known users include the current user" test_known_users_includes_the_current_user
  _hi_check "Known users include override names" test_known_users_includes_override_names
  _hi_check "Known users exclude the LOCALUSER placeholder" test_known_users_excludes_the_localuser_placeholder
  _hi_check "Known users are deduplicated" test_known_users_are_deduplicated
  _hi_check "Known usertags exclude hosttags" test_known_usertags_lists_only_usertags
  _hi_check "Preview users add a row per usertag" test_preview_users_adds_a_row_per_usertag
  _hi_check "Preview users are deduplicated" test_preview_users_are_deduplicated

  _hi_h2 "Testing: colors - subnet-style pins"
  _hi_check_eq "A covered name answers with its glob" "pat-*" _hi_pattern_for pat-1
  _hi_check "Uncovered and exact-pinned names miss" test_pattern_for_misses_uncovered_names
  _hi_check "Pins dedupe in file order" test_pattern_pins_dedupe_in_file_order
  _hi_check "A missing colors file is not an error" test_pattern_helpers_tolerate_a_missing_colors_file

  _hi_h2 "Testing: colors - layout helpers"
  # each column is padded by one space either side, so a width of n renders n+2
  # dashes between the separators
  _hi_check_eq "hbar sizes each column" "+-----+---+" _hi_hbar 3 1
  _hi_check_eq "hbar handles a single column" "+----+" _hi_hbar 2
  _hi_check "Group preview width sums its hosts" test_group_preview_width_sums_its_hosts
  _hi_check "Group index finds an existing key" test_group_index_finds_an_existing_key
  _hi_check "Group index misses a new key" test_group_index_misses_a_new_key
  _hi_check "Group index handles an empty table" test_group_index_handles_an_empty_table

  _hi_h2 "Testing: colors - the users table"
  _hi_check "Renders every override row" test_users_table_renders_override_rows
  _hi_check "Skips users that render by default" test_users_table_skips_default_users
  _hi_check "Shows the LOCALUSER pin as its own row" test_users_table_shows_the_localuser_pin
  _hi_check "Shows each usertag as its own row" test_users_table_shows_each_usertag

  _hi_h2 "Testing: colors - the hosts table"
  _hi_check "Groups hosts that render identically" test_hosts_table_groups_identical_renders
  _hi_check "Merges pattern hosts into the example row" test_hosts_table_merges_pattern_hosts_into_the_example_row
  _hi_check "Leads with a LOCALHOSTNAME pin" test_hosts_table_leads_with_a_localhostname_pin
  _hi_check "Reports a missing ssh config" test_hosts_table_reports_a_missing_ssh_config

  _hi_h2 "Testing: colors - the rendered tables"
  _hi_check "Render without error" test_tables_render_without_error
  _hi_check "Render under a scheme, and name it" test_tables_render_under_a_scheme
  _hi_check "Skip hosts that render by default" test_tables_skip_hosts_that_render_by_default
  _hi_check "Name the matching tag" test_tables_name_the_matching_tag
  _hi_check "A pattern pin gets an example row" test_tables_show_a_pattern_pin_example_row
  # Not the exact table shape - just that each table *is* one: every cell is
  # padded to its column's width, so every line has to come out the same printed
  # width once the color escapes are stripped. Catches a column measured in
  # something other than printed characters, which PREVIEW (escape-laden, sized
  # by _hi_group_preview_width) and HOST (unwrappably long names) both got
  # wrong. The packages half asserts the same invariant through literally the
  # same code, so the two cannot segment tables differently.
  _hi_check "Every line of a table is the same width" _hi_table_is_rectangular "$_HI_COLORS_OUT"

  _hi_h2 "Testing: colors - --help"
  _hi_check "--help prints usage and exits 0" test_help_prints_usage_and_exits_zero
  _hi_check "-h prints the same usage" test_h_flag_prints_the_same_usage
  _hi_check "A stray argument is refused" test_colors_stray_argument_is_refused

  _hi_h2 "Testing: packages - the priority meanings"
  _hi_check "Every priority has a meaning" test_every_priority_has_a_meaning
  _hi_check "One meaning per priority" test_meanings_are_one_per_priority
  _hi_check "Parenthetical examples dropped" test_meanings_drop_the_parenthetical
  _hi_check "Names the top priority" test_meanings_name_the_top_priority
  _hi_check "Reads only the block above the tables" test_meanings_take_only_the_block_above_the_table

  _hi_h2 "Testing: packages - naming the header's colors"
  _hi_check "Names a palette entry" test_color_name_of_names_a_palette_entry
  _hi_check "Names every color the header uses" test_color_name_of_names_every_header_color
  # $NC is not a palette color, and neither is anything under $NO_COLOR
  _hi_check_eq "Calls a reset plain" plain _hi_color_name_of "$NC"
  # ...and under $NO_COLOR every escape *is* the empty string - the short-
  # circuit branch, not the table walk
  _hi_check_eq "Calls an empty escape plain" plain _hi_color_name_of ""

  _hi_h2 "Testing: packages - examples, via the header's check_line"
  _hi_check "Counts every listed package" test_collect_counts_every_listed_package
  _hi_check "Counts only what the header shows" test_collect_counts_only_what_the_header_shows
  _hi_check "Finds an installed example" test_collect_finds_an_installed_example
  _hi_check "Finds a missing example" test_collect_finds_a_missing_example
  _hi_check "Skips a mode-suppressed example" test_collect_skips_a_mode_suppressed_example
  _hi_check "Keeps a missing example as a nudge" test_collect_keeps_a_missing_example_as_a_nudge
  _hi_check "Reads the mark, not the name" test_collect_reads_the_mark_not_the_name

  _hi_h2 "Testing: packages - the example cell"
  _hi_check "Reports its printed width" test_example_cell_reports_its_printed_width
  _hi_check "Marks a priority with nothing to show" test_example_cell_marks_a_priority_with_nothing_to_show
  _hi_check "Marks a priority below the floor" test_example_cell_marks_a_priority_below_the_floor

  _hi_h2 "Testing: packages - the tables, rendered in-process"
  _hi_check "Legend renders all five columns" test_priorities_table_renders_all_columns
  _hi_check "Legend sorts highest priority first" test_priorities_table_sorts_highest_first
  _hi_check "Legend names the ramp's colors" test_priorities_table_names_the_ramp_colors
  _hi_check "Legend shows the real examples" test_priorities_table_shows_the_real_examples
  _hi_check "Legend counts below the table" test_priorities_table_counts_below_the_table
  _hi_check "Floor note vanishes at floor 0" test_priorities_table_drops_the_floor_note_at_zero
  _hi_check "Legend is rectangular" _hi_table_is_rectangular "$_HI_PRIO_OUT"
  _hi_check "Marks table explains every mark" test_marks_table_explains_every_mark
  _hi_check "Marks table paints each glyph" test_marks_table_paints_each_glyph
  _hi_check "Marks table is rectangular" test_marks_table_is_rectangular
  _hi_check "Modes table explains every mode" test_modes_table_explains_every_mode
  _hi_check "Modes table is rectangular" test_modes_table_is_rectangular

  _hi_h2 "Testing: packages - the rendered preview"
  _hi_check "Help prints usage and stops" test_help_prints_usage_and_stops
  _hi_check "A stray argument is refused" test_packages_stray_argument_is_refused
  _hi_check_eq "-h matches --help" "$(_hi_render_packages_help --help)" _hi_render_packages_help -h
  _hi_check "Renders without error" test_preview_renders_without_error
  _hi_check "Names the active palette" test_preview_names_the_active_palette
  _hi_check "Names a scheme's escapes" test_color_name_of_names_scheme_escapes
  _hi_check "Names a custom scheme, and its second bank" test_preview_names_a_custom_scheme_and_its_bank
  _hi_check "Names second-bank escapes" test_color_name_of_names_second_bank_escapes
  _hi_check "Names every priority" test_preview_names_every_priority
  _hi_check "Explains the mode characters" test_preview_explains_the_modes
  _hi_check "Counts what it read" test_preview_counts_what_it_read
  _hi_check "Ends with the real check" test_preview_ends_with_the_real_check
  _hi_check "Every line of a table is the same width" _hi_table_is_rectangular "$_HI_PACKAGES_OUT"
  _hi_check "Reports a missing packages file" test_preview_reports_a_missing_packages_file
  _hi_check "An exported $_HI_PACKAGES is ignored" test_preview_ignores_an_exported_packages_path
  _hi_check "Reads the tree's own file when nothing is exported" test_preview_reads_the_trees_own_file

  _hi_suite_end "preview.sh"
}

run_preview_tests
