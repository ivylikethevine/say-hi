#!/bin/bash
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

function test_default_source_still_resolves_to_a_palette_color() {
  local color
  color="$(_hi_resolve_color hostname plain)"
  [ "$(_hi_color_source hostname plain)" = default ] &&
    printf '%s\n' "${_HI_COLOR_NAMES[@]}" | grep -qxF "$color"
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

# widths are per-host: user_width + a space + the host name, plus two spaces
# between each pair of groups
function test_group_preview_width_sums_its_hosts() {
  local user_width=4
  [ "$(_hi_group_preview_width abc de)" = "$((4 + 1 + 3 + 4 + 1 + 2 + 2))" ]
}

# Running the real script can't reuse the exported fixtures above: paths.sh
# re-exports $_HI_COLORS from $_HI_ROOT and $_HI_SSH_CONFIG from $HOME every
# time it's sourced, so the only way to point the script at fixtures is to
# give it a scratch tree and a scratch $HOME to derive them from.
function _hi_render_preview() {
  HOME="$_HI_WORKDIR/tree" _HI_HOME="$_HI_WORKDIR/tree" \
    _HI_LOCAL_USER=localdev _HI_LOCAL_HOSTNAME=localbox \
    "$_HI_WORKDIR/tree/say-hi/scripts/color_preview.sh" 2>&1
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

# Not the exact shape the comment above declines to assert - just that each
# table *is* one: every cell is padded to its column's width, so every line of
# a table has to come out the same printed width once the color escapes are
# stripped. Catches a column measured in something other than printed
# characters, which PREVIEW (escape-laden, sized by _hi_group_preview_width)
# and HOST (unwrappably long names) both got wrong.
function test_tables_are_rectangular() {
  _hi_table_is_rectangular "$_HI_PREVIEW_OUT"
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
EOF
  _hi_check "Never reports a tag for a username" test_source_never_reports_a_tag_for_a_username

  _hi_h2 "Testing: agreement with _hi_resolve_color"
  _hi_check "Agrees on overrides" test_source_agrees_with_resolve_color_on_overrides
  _hi_check "Agrees on tags" test_source_agrees_with_resolve_color_on_tags
  _hi_check "Default still resolves to a palette color" test_default_source_still_resolves_to_a_palette_color

  _hi_h2 "Testing: table inputs"
  _hi_check "Known users include the current user" test_known_users_includes_the_current_user
  _hi_check "Known users include override names" test_known_users_includes_override_names
  _hi_check "Known users exclude the LOCALUSER placeholder" test_known_users_excludes_the_localuser_placeholder
  _hi_check "Known users are deduplicated" test_known_users_are_deduplicated
  _hi_check "Known usertags exclude hosttags" test_known_usertags_lists_only_usertags
  _hi_check "Preview users add a row per usertag" test_preview_users_adds_a_row_per_usertag
  _hi_check "Preview users are deduplicated" test_preview_users_are_deduplicated

  _hi_h2 "Testing: layout helpers"
  # each column is padded by one space either side, so a width of n renders n+2
  # dashes between the separators
  _hi_check_eq "hbar sizes each column" "+-----+---+" _hi_hbar 3 1
  _hi_check_eq "hbar handles a single column" "+----+" _hi_hbar 2
  _hi_check "Group preview width sums its hosts" test_group_preview_width_sums_its_hosts

  _hi_h2 "Testing: the rendered tables"
  _hi_check "Render without error" test_tables_render_without_error
  _hi_check "Skip hosts that render by default" test_tables_skip_hosts_that_render_by_default
  _hi_check "Name the matching tag" test_tables_name_the_matching_tag
  _hi_check "Every line of a table is the same width" test_tables_are_rectangular

  _hi_suite_end "color_preview.sh"
}

run_color_preview_tests
