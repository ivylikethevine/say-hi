#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Unit tests for scripts/color_preview.sh - the `hi --color-preview` table.
#
# Its job is to render the same answers the live prompt would give, so what
# matters is that its own precedence logic (_hi_color_source) agrees with
# common/core.sh's _hi_resolve_color, and that the helpers feeding the table
# read settings/colors the way the rest of hi does. Everything runs against a
# fixture settings/colors and ~/.ssh/config in the scratch dir, so the output is
# fixed rather than "whatever this machine is configured with".
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"
# shellcheck source=../../scripts/color_preview.sh
source "$_HI_COLOR_PREVIEW"

function _hi_write_fixtures() {
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
# test_tables_are_rectangular
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
# the later cases read the shared variable, for _HI_PREVIEW_OUT's reasons.
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
# _hi_render_preview above says why TTL=0 is the cure
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
function _hi_render_preview() {
  # _HI_TARGETS_TTL=0: targets.sh's sweep cache is keyed by kind alone
  # (hi.targets.ssh under $XDG_RUNTIME_DIR), so within the TTL a render here
  # would happily reuse the host list a *previous* run's fixtures produced
  HOME="$_HI_WORKDIR/tree" _HI_HOME="$_HI_WORKDIR/tree" \
    _HI_LOCAL_USER=localdev _HI_LOCAL_HOSTNAME=localbox _HI_TARGETS_TTL=0 \
    "$_HI_WORKDIR/tree/say-hi/scripts/color_preview.sh" "$@" 2>&1
}

function _hi_write_preview_tree() {
  local home
  home="$(_hi_scratch_tree tree common settings scripts)"
  mkdir -p "$home/.ssh"
  cp "$_HI_WORKDIR/colors" "$home/say-hi/settings/colors"
  cp "$_HI_WORKDIR/ssh_config" "$home/.ssh/config"
}

# The tables are wide, colored and layout-heavy; asserting their exact shape
# would test the formatting rather than the resolution, so these prove they
# render every group they should without erroring under set -e. One render
# (the slowest thing this suite does - a full script run plus targets.sh)
# shared by all three cases; each reads the whole output from a variable
# rather than piping into grep, because under `set -o pipefail` an
# early-exiting `grep -q` SIGPIPEs the script and a negated case then passes
# no matter what the table said.
_HI_PREVIEW_OUT=""

function test_tables_render_without_error() {
  _HI_PREVIEW_OUT="$(_hi_render_preview)" || return 1
  [[ "$_HI_PREVIEW_OUT" == *pinned* && "$_HI_PREVIEW_OUT" == *tagged* && "$_HI_PREVIEW_OUT" == *alice* ]]
}

# a host with no override and no usable tag would render identically to a bare
# `hi`, so it's deliberately left out of the table
function test_tables_skip_hosts_that_render_by_default() {
  ! printf '%s\n' "$_HI_PREVIEW_OUT" | grep -q '\bplain\b'
}

# the tag column has to name the tag that actually matched, since that's the
# line a user reads to work out which settings/colors entry to edit
function test_tables_name_the_matching_tag() {
  printf '%s\n' "$_HI_PREVIEW_OUT" | grep -q 'tag:work'
}

# a pattern pin gets an example row (its glob never appears in targets.sh's
# list), and a real host it covers joins that same group
function test_tables_show_a_pattern_pin_example_row() {
  printf '%s\n' "$_HI_PREVIEW_OUT" | grep -q 'pattern:pat-\*' || return 1
  printf '%s\n' "$_HI_PREVIEW_OUT" | grep -q 'pat-1'
}

# Not the exact shape the comment above declines to assert - just that each
# table *is* one: every cell is padded to its column's width, so every line of
# a table has to come out the same printed width once the color escapes are
# stripped. Catches a column measured in something other than printed
# characters, which PREVIEW (escape-laden, sized by _hi_group_preview_width)
# and HOST (unwrappably long names) both got wrong.
function test_tables_are_rectangular() {
  _hi_table_is_rectangular "$_HI_PREVIEW_OUT"
}

# --help answers before reading any config, prints the usage text and exits 0
function test_help_prints_usage_and_exits_zero() {
  local out
  out="$(_hi_render_preview --help)" || return 1
  [[ "$out" == 'Usage: color_preview.sh'* ]]
}

# -h through the sourced form: source passes its arguments along, and the
# subshell keeps the `exit 0` contained. The inner ( ) is load-bearing twice
# over: a bare `source` directly inside $( ) crashes shellcheck 0.11.0
# ("Non-exhaustive patterns in checkCmd"), and the space before it keeps $( (
# from reading as arithmetic.
function test_h_flag_prints_the_same_usage() {
  local out
  # shellcheck source=../../scripts/color_preview.sh
  out="$( (source "$_HI_COLOR_PREVIEW" -h) )" || return 1
  [[ "$out" == 'Usage: color_preview.sh'* ]]
}

function run_color_preview_tests() {
  _hi_workdir colorpreviewtest
  _hi_write_fixtures
  _hi_write_preview_tree

  _hi_h1 "Testing scripts/color_preview.sh"

  _hi_suite_begin

  _hi_h2 "Testing: _hi_color_source"
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

  _hi_h2 "Testing: agreement with _hi_resolve_color"
  _hi_check "Agrees on overrides" test_source_agrees_with_resolve_color_on_overrides
  _hi_check "Agrees on tags" test_source_agrees_with_resolve_color_on_tags
  _hi_check "Agrees on patterns" test_source_agrees_with_resolve_color_on_patterns
  _hi_check "Default still resolves to a palette color" test_default_source_still_resolves_to_a_palette_color

  _hi_h2 "Testing: table inputs"
  _hi_check "_hi_colors_names dedupes and skips" test_colors_names_dedupes_and_skips
  _hi_check "Known users include the current user" test_known_users_includes_the_current_user
  _hi_check "Known users include override names" test_known_users_includes_override_names
  _hi_check "Known users exclude the LOCALUSER placeholder" test_known_users_excludes_the_localuser_placeholder
  _hi_check "Known users are deduplicated" test_known_users_are_deduplicated
  _hi_check "Known usertags exclude hosttags" test_known_usertags_lists_only_usertags
  _hi_check "Preview users add a row per usertag" test_preview_users_adds_a_row_per_usertag
  _hi_check "Preview users are deduplicated" test_preview_users_are_deduplicated

  _hi_h2 "Testing: subnet-style pins"
  _hi_check_eq "A covered name answers with its glob" "pat-*" _hi_pattern_for pat-1
  _hi_check "Uncovered and exact-pinned names miss" test_pattern_for_misses_uncovered_names
  _hi_check "Pins dedupe in file order" test_pattern_pins_dedupe_in_file_order
  _hi_check "A missing colors file is not an error" test_pattern_helpers_tolerate_a_missing_colors_file

  _hi_h2 "Testing: layout helpers"
  # each column is padded by one space either side, so a width of n renders n+2
  # dashes between the separators
  _hi_check_eq "hbar sizes each column" "+-----+---+" _hi_hbar 3 1
  _hi_check_eq "hbar handles a single column" "+----+" _hi_hbar 2
  _hi_check "Group preview width sums its hosts" test_group_preview_width_sums_its_hosts
  _hi_check "Group index finds an existing key" test_group_index_finds_an_existing_key
  _hi_check "Group index misses a new key" test_group_index_misses_a_new_key
  _hi_check "Group index handles an empty table" test_group_index_handles_an_empty_table

  _hi_h2 "Testing: the users table"
  _hi_check "Renders every override row" test_users_table_renders_override_rows
  _hi_check "Skips users that render by default" test_users_table_skips_default_users
  _hi_check "Shows the LOCALUSER pin as its own row" test_users_table_shows_the_localuser_pin
  _hi_check "Shows each usertag as its own row" test_users_table_shows_each_usertag

  _hi_h2 "Testing: the hosts table"
  _hi_check "Groups hosts that render identically" test_hosts_table_groups_identical_renders
  _hi_check "Merges pattern hosts into the example row" test_hosts_table_merges_pattern_hosts_into_the_example_row
  _hi_check "Leads with a LOCALHOSTNAME pin" test_hosts_table_leads_with_a_localhostname_pin
  _hi_check "Reports a missing ssh config" test_hosts_table_reports_a_missing_ssh_config

  _hi_h2 "Testing: the rendered tables"
  _hi_check "Render without error" test_tables_render_without_error
  _hi_check "Skip hosts that render by default" test_tables_skip_hosts_that_render_by_default
  _hi_check "Name the matching tag" test_tables_name_the_matching_tag
  _hi_check "A pattern pin gets an example row" test_tables_show_a_pattern_pin_example_row
  _hi_check "Every line of a table is the same width" test_tables_are_rectangular

  _hi_h2 "Testing: --help"
  _hi_check "--help prints usage and exits 0" test_help_prints_usage_and_exits_zero
  _hi_check "-h prints the same usage" test_h_flag_prints_the_same_usage

  _hi_suite_end "color_preview.sh"
}

run_color_preview_tests
