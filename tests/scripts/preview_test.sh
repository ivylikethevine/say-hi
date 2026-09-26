#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Unit tests for scripts/preview.sh - `hi --preview colors`, `packages`,
# and `header`, one script with a subject switch.
#
# colors: its job is to render the same answers the live prompt would give, so
# what matters is that its own precedence logic (_hi_color_source) agrees with
# common/core.sh's _hi_resolve_color, and that the helpers feeding the table
# read config/colors the way the rest of hi does. Everything runs against a
# fixture config/colors and ~/.ssh/config in the scratch dir, so the output
# is fixed rather than "whatever this machine is configured with".
#
# packages: the preview's whole claim is that it shows what the *header* will
# do, so what matters is that it reads its facts from header.sh rather than
# from a copy: each group's state and tier out of _hi_group_on and
# _hi_group_tier, the colors out of _HI_YES and _HI_NO, and every example row
# out of check_line itself. The
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
# Every case below matches a table's edges and marks as ASCII literals, so the
# set is pinned rather than left to the runner's locale - scripts/lib.sh decides
# $_HI_BOX_* at source time, which is why this comes first, and it is exported
# because several cases render in a child. The other side of the switch is
# tests/scripts/table_test.sh's business, plus the one case at the end here that
# renders a real table under it.
export _HI_ASCII=1

# its own hatch stops it before it renders anything; sourcing hands over the
# helpers, and (through it) header.sh's check_line
# shellcheck source=../../scripts/preview.sh
source "$_HI_PREVIEW"

# One scratch tree for both halves: the colors fixtures and the ssh config a
# child render derives its paths from, and the packages roster in the tree.
# _hi_scratch_tree copies the real config/ wholesale, real config/packages
# included - replaced here with the fixture, or every row-count assertion
# below counts the real shipped roster instead.
function _hi_write_preview_tree() {
  local home
  home="$(_hi_scratch_tree tree common config scripts)"
  mkdir -p "$home/.ssh"
  cp "$_HI_WORKDIR/colors" "$home/say-hi/config/colors"
  cp "$_HI_WORKDIR/ssh_config" "$home/.ssh/config"
  cp "$_HI_WORKDIR/packages" "$home/say-hi/config/packages"
}

#
# the subject switch
#

# a bare `preview.sh` is a usage error, never a silent default subject
function test_a_missing_subject_is_refused() {
  local out rc=0
  out="$(HOME="$_HI_WORKDIR/tree" _HI_HOME="$_HI_WORKDIR/tree" \
    "$_HI_WORKDIR/tree/say-hi/scripts/preview.sh" 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"one of colors, packages, or header"* ]]
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

# a header that is off says so, and names the toggle: the wizard's preview
# box reads the same line, where a silent exit would look like an empty
# header. The checkout's own script, so the coverage sweep sees the arm.
function test_header_subject_says_when_the_header_is_off() {
  local out
  out="$(HOME="$_HI_WORKDIR/tree" _HI_CONFIG_DIR="$_HI_WORKDIR/nocfg" \
    _HI_DISABLE_HEADER=1 _HI_TARGETS_TTL=0 \
    "$_HI_ROOT/scripts/preview.sh" header 2>&1)" || return 1
  [[ "$out" == *"header off (_HI_DISABLE_HEADER=1"* && "$out" != *"| "* ]]
}

#
# colors
#

function _hi_write_color_fixtures() {
  cat >"$_HI_WORKDIR/colors" <<'EOF'
# [type] sections of: name color [rrggbb]
[username]
alice brmagenta
LOCALUSER brgreen

[usertag]
ops brred

[hostname]
pinned brcyan
pat-* brblue

[hosttag]
work bryellow
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
  [ "$(_hi_color_source hostname plain)" = hash ] &&
    printf '%s\n' "${_HI_COLOR_NAMES[@]}" | grep -qxF "$color"
}

function test_colors_names_dedupes_and_skips() {
  local colors="$_HI_WORKDIR/colors.names" out
  printf '[hostname]\na red\nb blue\na green\n[username]\nc red\n' >"$colors"
  out="$(_HI_COLORS="$colors" _hi_colors_names hostname)"
  [ "$out" = "a
b" ] || return 1
  [ "$(_HI_COLORS="$colors" _hi_colors_names hostname a)" = b ]
}

# _hi_colors_rows reads the [type] sections core.sh's scan does: a name only
# under its own section, a row above the first one nowhere, comments and
# blank lines skipped, a section named twice read both times
function test_colors_rows_are_scoped_to_their_section() {
  local colors="$_HI_WORKDIR/colors.rows"
  printf 'stray red\n[hostname]\n# a note\n\nshared red\nh1 blue\n[username]\nshared green\n[hostname]\nh2 cyan ff0000\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _hi_colors_rows hostname)" = "$(printf 'shared\nh1\nh2')" ] &&
    [ "$(_HI_COLORS="$colors" _hi_colors_rows username)" = shared ] &&
    [ -z "$(_HI_COLORS="$colors" _hi_colors_rows hosttag)" ]
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
  printf '[hostname]\nnet-* red\nexact blue\ndb-? cyan\nnet-* green\n[username]\nu-* green\n' >"$colors"
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

# a user with no pin still renders in its hashed color, so the table lists it
# and names the hash as the reason
function test_users_table_lists_hashed_users() {
  [[ "$_HI_USERS_OUT" == *defaultuser* ]] &&
    _hi_strip_ansi "$_HI_USERS_OUT" | grep -q 'defaultuser.*| hash'
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
# _hi_render_colors below says why TTL=0 is the cure. A render that exits
# non-zero says so on stderr, which _hi_assert inherits: its callers only
# `|| return 1`, and it has failed that way on Windows arm64, twice running,
# with the output that would say why captured and dropped.
function _hi_render_hosts_table() {
  local out rc=0
  out="$(_HI_TARGETS_TTL=0 _hi_print_hosts_table 2>&1)" || rc=$?
  printf '%s\n' "$out"
  [ "$rc" = 0 ] ||
    _hi_because "_hi_print_hosts_table exited $rc; its last lines:"$'\n'"$(printf '%s\n' "$out" | tail -n 20)"
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
# Both arms report on stderr, which _hi_assert inherits: this has failed on
# Windows arm64, and "one row" and "that row reads pat-*, pat-1" fail for
# different reasons - the first if the merge did not happen, the second if it
# did but the names came out in another order.
function test_hosts_table_merges_pattern_hosts_into_the_example_row() {
  local rows found
  rows="$(printf '%s\n' "$_HI_HOSTS_OUT" | grep -c 'pattern:pat-')"
  found="$(printf '%s\n' "$_HI_HOSTS_OUT" | grep 'pattern:pat-')"
  [ "$rows" -eq 1 ] ||
    _hi_because "expected one pattern:pat- row, got $rows: $found" || return 1
  [[ "$_HI_HOSTS_OUT" == *'pat-*, pat-1'* ]] ||
    _hi_because "no \"pat-*, pat-1\" cell; the row was: $found"
}

# a LOCALHOSTNAME pin renders the current machine as its own single-host
# group ahead of the ssh ones
function test_hosts_table_leads_with_a_localhostname_pin() {
  local colors="$_HI_WORKDIR/colors.localhost" out
  cat "$_HI_WORKDIR/colors" >"$colors"
  printf '[hostname]\nLOCALHOSTNAME brgreen\n' >>"$colors"
  out="$(_HI_COLORS="$colors" _hi_render_hosts_table)" || return 1
  [[ "$out" == *localbox* && "$out" == *local:hostname* ]] || return 1
  # ahead of: nothing before the localbox row but the header
  [[ "${out%%localbox*}" != *override:hostname* ]]
}

# a group whose host list wraps onto more lines than there are preview users
# pads the extra line's PREVIEW cell blank: one user (no username or usertag
# pin) against the two work hosts, which wrap
function test_hosts_table_pads_a_wrapped_group_past_its_users() {
  local colors="$_HI_WORKDIR/colors.solo" out row
  printf '[hosttag]\nwork bryellow\n' >"$colors"
  out="$(_HI_COLORS="$colors" _HI_WHOAMI_CACHE=solo _hi_render_hosts_table)" || return 1
  # the wrapped host's own row, with no user@ beside it
  row="$(_hi_strip_ansi "$out" | grep -F '| a-considerably-longer-hostname ')" || return 1
  [[ "$row" != *@* ]] && _hi_table_is_rectangular "$out"
}

# a leading `Host *` of defaults does not end the tag walk, so a tagged block
# after it still paints its HOST cell in the hosttag's color - the escape
# itself, not only the tag:work text the SOURCE cell carries
function test_hosts_table_paints_a_tag_behind_a_leading_wildcard() {
  local cfg="$_HI_WORKDIR/ssh_config.leadingstar" out esc
  printf 'Host *\n  AddKeysToAgent yes\n\n# Tags: work\nHost starbehind\n  User nobody\n' >"$cfg"
  out="$(_HI_SSH_CONFIG="$cfg" _hi_render_hosts_table)" || return 1
  _hi_color_escape_var esc bryellow
  printf -v esc '%b' "$esc"
  _hi_strip_ansi "$out" | grep -F '| starbehind ' | grep -qF 'tag:work' || return 1
  [[ "$out" == *"${esc}starbehind"* ]] || _hi_because "starbehind is not painted bryellow"
}

# a usertag's example row sits only under a host carrying that tag, in the
# usertag's color there; a host without the tag draws no row for it at all
function test_hosts_table_draws_a_usertag_row_only_under_its_tag() {
  local cfg="$_HI_WORKDIR/ssh_config.usertag" colors="$_HI_WORKDIR/colors.usertag" out esc
  printf '# Tags: ops\nHost opsbox\n  User nobody\n\nHost plainbox\n  User nobody\n' >"$cfg"
  printf '[usertag]\nops brred\n' >"$colors"
  out="$(_HI_SSH_CONFIG="$cfg" _HI_COLORS="$colors" _HI_WHOAMI_CACHE=solo _hi_render_hosts_table)" || return 1
  _hi_color_escape_var esc brred
  printf -v esc '%b' "$esc"
  [[ "$out" == *"${esc}ops"* ]] || _hi_because "the ops row is not painted brred" || return 1
  _hi_strip_ansi "$out" | grep -qF 'ops@opsbox' || return 1
  ! _hi_strip_ansi "$out" | grep -qF 'ops@plainbox' &&
    _hi_strip_ansi "$out" | grep -qF 'solo@plainbox' &&
    _hi_table_is_rectangular "$out"
}

# the machine the preview runs on is always listed, pinned or not: the
# fixture colors file has no LOCALHOSTNAME row, so it reads by its own name
function test_hosts_table_lists_the_local_machine_unpinned() {
  local out row
  out="$(_hi_render_hosts_table)" || return 1
  row="$(_hi_strip_ansi "$out" | grep '| localbox ')" || return 1
  [[ "$row" != *local:hostname* && "$row" == *'| hash '* ]]
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

# The tables are wide, colored, and layout-heavy; asserting their exact shape
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

# a scheme paints the swatches with the 24-bit tail, and the header line
# says which scheme it is (HI.50)
function test_tables_render_under_a_scheme() {
  local out
  out="$(_HI_COLOR_SCHEME="$_HI_TEST_L24" _HI_TRUECOLOR=1 _hi_render_colors)" || return 1
  [[ "$out" == *"scheme: custom (24)"* && "$out" == *";38;2;"* ]] || return 1
  out="$(_HI_COLOR_SCHEME="" _HI_TRUECOLOR=0 _hi_render_colors)" || return 1
  [[ "$out" == *"scheme: default"* && "$out" != *";38;2;"* ]]
}

# a host with no override and no usable tag still paints its hashed color on a
# connect, so every ssh-config host gets a row: the point of the hosts table
function test_tables_list_every_ssh_config_host() {
  local out host
  out="$(_hi_strip_ansi "$_HI_COLORS_OUT")"
  for host in plain pinned tagged othertag pat-1 a-considerably-longer-hostname; do
    [[ "$out" == *"$host"* ]] || _hi_because "no row names $host" || return 1
  done
}

# the hashed rows name the hash as their rule and land on a palette color
function test_tables_label_hashed_hosts_hash() {
  local row color
  row="$(_hi_strip_ansi "$_HI_COLORS_OUT" | grep '| plain ')" || return 1
  [[ "$row" == *'| hash '* ]] || _hi_because "the plain row was: $row" || return 1
  color="$(_hi_resolve_color hostname plain)"
  [[ "$row" == *"| $color "* ]] || _hi_because "want $color in: $row"
}

# the tag column has to name the tag that actually matched, since that's the
# line a user reads to work out which config/colors entry to edit
function test_tables_name_the_matching_tag() {
  printf '%s\n' "$_HI_COLORS_OUT" | grep -q 'tag:work'
}

# a pattern pin gets an example row (its glob never appears in targets.sh's
# list), and a real host it covers joins that same group
function test_tables_show_a_pattern_pin_example_row() {
  printf '%s\n' "$_HI_COLORS_OUT" | grep -q 'pattern:pat-\*' || return 1
  printf '%s\n' "$_HI_COLORS_OUT" | grep -q 'pat-1'
}

# the users table carries the LOCALUSER pin and every usertag pin as example
# rows of their own, each naming its source, since neither is a real user
# targets.sh would list
function test_tables_list_the_local_user_and_usertag_pins() {
  printf '%s\n' "$_HI_COLORS_OUT" | grep -q 'LOCALUSER.*local:username' || return 1
  printf '%s\n' "$_HI_COLORS_OUT" | grep -q 'ops.*usertag:ops'
}

# The same render off the checkout's own config/colors (LOCALUSER and a
# usertag are pinned there too), so the coverage sweep sees the users table
# render; $HOME still supplies the fixture ssh config. With truecolor refused
# the scheme line says the 16-color escapes are what is on show.
function test_tables_render_from_the_checkout() {
  local out
  out="$(HOME="$_HI_WORKDIR/tree" _HI_CONFIG_DIR="$_HI_WORKDIR/nocfg" \
    _HI_LOCAL_USER=localdev _HI_LOCAL_HOSTNAME=localbox _HI_TARGETS_TTL=0 _HI_TRUECOLOR=0 \
    "$_HI_ROOT/scripts/preview.sh" colors 2>&1)" || return 1
  [[ "$out" == *"(no truecolor here"* ]] || return 1
  printf '%s\n' "$out" | grep -q 'LOCALUSER.*local:username' || return 1
  printf '%s\n' "$out" | grep -q 'usertag:'
}

# --help answers before reading any config, prints the usage text, and exits 0
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

# One row above the first group (always runs), then a group per case: core
# and useful on by default, deprecated holding every marker outcome, extras
# and platform off by default but still collected.
function _hi_write_package_fixtures() {
  _hi_fake_path pkgbin hitop hialpha hibravo hicharlie hidelta hiecho hifoxtrot >/dev/null

  cat >"$_HI_WORKDIR/packages" <<'EOF'
# a comment, and a blank line, both of which the header skips

hitop
[core]
hialpha
highost3
highostalt,hibravo
[useful]
hibravo
highost2
[deprecated]
-hiecho
-highostgone
+hifoxtrot
+highostplus
[extras]
hicharlie
highost1
[platform]
hidelta
highost0
EOF
  # in-process cases read $_HI_PACKAGES; a child script re-derives it from
  # $_HI_CONFIG_DIR, so the fixture is also an overlay's packages file
  mkdir -p "$_HI_WORKDIR/cfg"
  export _HI_PACKAGES="$_HI_WORKDIR/packages"
  cp "$_HI_WORKDIR/packages" "$_HI_WORKDIR/cfg/packages"
}

# the fixture's packages, and the coreutils the script itself shells out to
function _hi_pkg_path() {
  printf '%s:%s' "$(_hi_fake_path pkgbin)" "$(_hi_real_path pkgtools bash awk sort sed cat)"
}

# collect once - it is the same work for every case that reads the results.
# An empty $_HI_PACKAGES_GROUPS reads as the shipped default, whatever the
# runner's environment carries.
function _hi_collect_once() {
  local saved="$PATH" _HI_PACKAGES_GROUPS=""
  PATH="$(_hi_pkg_path)"
  _hi_collect_examples
  PATH="$saved"
}

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
      [ -n "$entry" ] || return 1
      printf '%s\n' "${_HI_COLOR_NAMES[@]}" | grep -qx "$entry" || return 1
    done
  done
  _hi_packages_palette
}

# one slot per group in file order, slot 0 the rows above the first header;
# each group's state from _hi_group_on, its tier from _hi_group_tier, and its
# row count
function test_collect_records_every_group() {
  [ "${_HI_PG_NAME[*]}" = "(no group) core useful deprecated extras platform" ] &&
    [ "${_HI_PG_ON[*]}" = "1 1 1 1 0 0" ] &&
    [ "${_HI_PG_TIER[*]}" = "1 3 2 3 1 0" ] &&
    [ "${_HI_PG_ROWS[*]}" = "1 3 2 4 2 2" ]
}

function test_collect_counts_every_listed_package() {
  [ "$_HI_PKG_LISTED" -eq 14 ]
}

# an absent `-` row and an installed `+` row print nothing, so of the 14 rows
# 2 are silent; the 4 in extras and platform would print but their groups are
# off; the other 8 are what the header shows
function test_collect_splits_shown_silent_and_off() {
  [ "$_HI_PKG_SHOWN" -eq 8 ] && [ "$_HI_PKG_SILENT" -eq 2 ] && [ "$_HI_PKG_OFF" -eq 4 ]
}

function test_collect_finds_an_installed_example() {
  [[ "${_HI_EX_OK[1]:-}" == *hialpha* ]]
}

function test_collect_finds_a_missing_example() {
  [[ "${_HI_EX_NO[1]:-}" == *highost3* ]]
}

# the rows above the first header are a group of their own, slot 0
function test_collect_keeps_the_ungrouped_rows_in_slot_zero() {
  [[ "${_HI_EX_OK[0]:-}" == *hitop* ]] && [ -z "${_HI_EX_NO[0]:-}" ]
}

# an installed `-` row is a warning, and a warning sits on the missing side:
# deprecated's only installed row is hiecho, and it is not an OK example
function test_collect_files_a_warning_as_missing() {
  [ -z "${_HI_EX_OK[3]:-}" ] &&
    [[ "${_HI_EX_NO[3]:-}" == *hiecho*"$YELLOW$_HI_MARK_WARN$NC" ]]
}

# the rows that print nothing can be no one's example
function test_collect_skips_the_silent_rows() {
  local g
  for g in "${!_HI_PG_NAME[@]}"; do
    [[ "${_HI_EX_OK[g]:-}${_HI_EX_NO[g]:-}" != *highostgone* ]] &&
      [[ "${_HI_EX_OK[g]:-}${_HI_EX_NO[g]:-}" != *hifoxtrot* ]] || return 1
  done
}

# a group that is off still has its examples collected: the legend shows what
# it would print
function test_collect_keeps_an_off_groups_examples() {
  [[ "${_HI_EX_OK[4]:-}" == *hicharlie* ]] && [[ "${_HI_EX_NO[4]:-}" == *highost1* ]]
}

# the installed/missing split reads the mark, so it has to survive a package
# whose *name* contains the ASCII glyph ("x" in highost0): platform has one
# installed package and one absent, and each has to land in its own column
function test_collect_reads_the_mark_not_the_name() {
  [[ "${_HI_EX_OK[5]:-}" == *hidelta* ]] && [[ "${_HI_EX_NO[5]:-}" == *highost0* ]]
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
    [ "$width" -lt "${#text}" ]
}

function test_example_cell_marks_a_group_with_nothing_to_show() {
  local text width
  IFS=$'\t' read -r text width <<<"$(_hi_example_cell 9)"
  [ "$text" = "-" ] && [ "$width" -eq 1 ]
}

# One in-process render of the legend (the source hatch hands the function
# over without running it), shared like _HI_PACKAGES_OUT below and for the same
# SIGPIPE reason. In-process rather than through the child render so a failure
# points at the table code, not at whatever the child's environment did.
_HI_GROUPS_OUT=""

function test_groups_table_renders_all_columns() {
  _HI_GROUPS_OUT="$(_HI_PACKAGES_GROUPS="" _hi_print_groups_table)" || return 1
  local stripped
  stripped="$(_hi_strip_ansi "$_HI_GROUPS_OUT")"
  [[ "$stripped" == *"| GROUP "* && "$stripped" == *"| STATE "* ]] &&
    [[ "$stripped" == *"| INSTALLED "* && "$stripped" == *"| MISSING "* ]] &&
    [[ "$stripped" == *"| EXAMPLE "* ]]
}

# file order, the order a reader finds the groups in
function test_groups_table_keeps_file_order() {
  local stripped
  stripped="$(_hi_strip_ansi "$_HI_GROUPS_OUT")"
  _hi_before "$stripped" '^| (no group) ' '^| core ' &&
    _hi_before "$stripped" '^| core ' '^| deprecated ' &&
    _hi_before "$stripped" '^| deprecated ' '^| platform '
}

# STATE is whether $_HI_PACKAGES_GROUPS runs the group
function test_groups_table_says_on_and_off() {
  local stripped
  stripped="$(_hi_strip_ansi "$_HI_GROUPS_OUT")"
  [[ "$(printf '%s\n' "$stripped" | grep '^| core ')" == *"| on "* ]] &&
    [[ "$(printf '%s\n' "$stripped" | grep '^| extras ')" == *"| off "* ]]
}

# the INSTALLED/MISSING cells name the colors of the group's tier: core is
# tier 3, the shipped ramp's brgreen/brred, and platform tier 0, cyan/blue
function test_groups_table_names_the_ramp_colors() {
  local stripped row
  stripped="$(_hi_strip_ansi "$_HI_GROUPS_OUT")"
  row="$(printf '%s\n' "$stripped" | grep '^| core ')"
  [[ "$row" == *brgreen* && "$row" == *brred* ]] || return 1
  row="$(printf '%s\n' "$stripped" | grep '^| platform ')"
  [[ "$row" == *"| cyan "* && "$row" == *"| blue "* ]]
}

# the EXAMPLE column shows the fixture's own rows, an off group's included
function test_groups_table_shows_the_real_examples() {
  local stripped
  stripped="$(_hi_strip_ansi "$_HI_GROUPS_OUT")"
  [[ "$(printf '%s\n' "$stripped" | grep '^| core ')" == *hialpha*highost3* ]] &&
    [[ "$(printf '%s\n' "$stripped" | grep '^| extras ')" == *hicharlie*highost1* ]]
}

# the "(no group)" row is there only when the file has rows above its first
# header
function test_groups_table_drops_an_empty_no_group_row() {
  local out
  out="$(
    _HI_PG_ROWS[0]=0
    _hi_print_groups_table
  )" || return 1
  [[ "$(_hi_strip_ansi "$out")" != *"(no group)"* && "$out" == *core* ]]
}

# the two lines under the table: the tally, and the note naming the setting
# that leaves groups off - the same numbers the child render asserts, proved
# here to come from the table code itself
function test_groups_table_counts_below_the_table() {
  [[ "$_HI_GROUPS_OUT" == *"14 listed, 8 shown, 2 silent by their marker"* ]] &&
    [[ "$_HI_GROUPS_OUT" == *"4 more in groups \$_HI_PACKAGES_GROUPS leaves off (core useful deprecated run)"* ]]
}

# nothing off, nothing to explain
function test_groups_table_drops_the_off_note_at_zero() {
  local out
  out="$(_HI_PKG_OFF=0 _hi_print_groups_table)" || return 1
  [[ "$out" != *"leaves off"* && "$out" == *"14 listed"* ]]
}

function test_marks_table_explains_every_mark() {
  local out
  out="$(_hi_strip_ansi "$(_hi_print_marks_table)")" || return 1
  [[ "$out" == *"| MARK "* && "$out" == *"| MEANS "* ]] &&
    [[ "$out" == *"installed, under the first name the row lists"* ]] &&
    [[ "$out" == *"installed, but via one of the alternatives after it"* ]] &&
    [[ "$out" == *"not installed - no name on the row resolved"* ]] &&
    [[ "$out" == *"installed, on a - row: a package you don't want"* ]]
}

# each glyph is painted in the color the header paints it - the raw render has
# to carry the resolved escape directly ahead of the mark
function test_marks_table_paints_each_glyph() {
  local out
  out="$(_hi_print_marks_table)" || return 1
  _hi_has_rendered "$out" "$GREEN$_HI_MARK_OK" && _hi_has_rendered "$out" "$RED$_HI_MARK_NO" &&
    _hi_has_rendered "$out" "$YELLOW$_HI_MARK_ALT" && _hi_has_rendered "$out" "$YELLOW$_HI_MARK_WARN"
}

function test_marks_table_is_rectangular() {
  _hi_table_is_rectangular "$(_hi_print_marks_table)"
}

# the third axis, a row's leading marker, is two lines under the marks: both
# markers and the default, which has none
function test_marks_table_explains_the_markers() {
  local out
  out="$(_hi_strip_ansi "$(_hi_print_marks_table)")" || return 1
  [[ "$out" == *"a leading - (unwanted) speaks only when installed, + (required) only"* ]] &&
    [[ "$out" == *"when missing; no marker speaks both ways"* ]]
}

# ...and the same table under the glyph set the rest of this suite pins away:
# real corners and junctions, and still rectangular, since a column measured in
# bytes rather than columns is exactly what a three-byte edge would expose
# (GLOSSARY: HI.12)
function test_marks_table_renders_the_glyph_set() {
  local out
  out="$(_HI_ASCII=0 bash -c '
    source "$_HI_HOME/say-hi/scripts/preview.sh"
    _hi_print_marks_table')" || return 1
  [[ "$out" == *"┌─"* && "$out" == *"├─"* && "$out" == *"└─"* && "$out" == *"│ MARK "* ]] &&
    _hi_table_is_rectangular "$out"
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
    "$_HI_WORKDIR/tree/say-hi/scripts/preview.sh" packages 2>&1)" || return 1
  [[ "$out" == *hialpha* ]] && [[ "$out" == *'14 listed'* ]]
}

# --help exits 0 before any table renders: usage text, the files it reads, and
# nothing of the legend itself
function test_help_prints_usage_and_stops() {
  local out
  out="$(_hi_render_packages_help --help)" || return 1
  [[ "$out" == *"Usage: preview.sh packages"* ]] &&
    [[ "$out" == *"Takes no arguments"* ]] &&
    [[ "$out" == *"\$_HI_PACKAGES_GROUPS"* ]] &&
    [[ "$out" != *"| GROUP"* ]]
}

# anything that is not -h/--help is an error: the flag takes no arguments,
# and a stray one must not be ignored
function test_packages_stray_argument_is_refused() {
  local out rc=0
  out="$(_hi_render_packages_help nonsense)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"takes no arguments"* && "$out" != *"| GROUP"* ]]
}

# One render (the slowest thing this suite does) shared by the cases below;
# each reads it from a variable rather than piping into grep, because under
# `set -o pipefail` an early-exiting `grep -q` SIGPIPEs the script and a
# negated case then passes no matter what the table said.
_HI_PACKAGES_OUT=""

function test_preview_renders_without_error() {
  _HI_PACKAGES_OUT="$(_hi_render_packages)" || return 1
  [[ "$_HI_PACKAGES_OUT" == *"| GROUP "* && "$_HI_PACKAGES_OUT" == *MARK* ]]
}

# the eyeball pass _HI_PACKAGES_PALETTE leans on: the legend has to say which
# ramp is on screen, not just render one - the same three shapes the scheme
# line prints
function test_preview_names_the_active_palette() {
  local out
  [[ "$_HI_PACKAGES_OUT" == *"palette: default"* && "$_HI_PACKAGES_OUT" == *"scheme: default"* ]] || return 1
  out="$(_HI_PACKAGES_PALETTE="$_HI_TEST_RAMP" _hi_render_packages)" || return 1
  [[ "$out" == *"palette: custom"* ]] || return 1
  out="$(_HI_PACKAGES_PALETTE=mono _hi_render_packages)" || return 1
  [[ "$out" == *"palette: mono (ignored - not eight color names)"* ]]
}

# a scheme of the user's own is named by its shape, and a 48-word one paints
# the legend from its second bank - which the reverse map still names, since
# the name is the 16-color half (HI.50)
function test_preview_names_a_custom_scheme_and_its_bank() {
  local out row
  out="$(_HI_COLOR_SCHEME="$_HI_TEST_L48" _HI_TRUECOLOR=1 _hi_render_packages)" || return 1
  [[ "$out" == *"scheme: custom (48)"* ]] || return 1
  row="$(printf '%s\n' "$out" | grep '^| core ')"
  # bank 2's brgreen (23d18b) and brred (f14c4c), named as such
  [[ "$row" == *";38;2;35;209;139m"*brgreen* && "$row" == *";38;2;241;76;76m"*brred* ]] || return 1
  out="$(_HI_COLOR_SCHEME="not a scheme" _HI_TRUECOLOR=1 _hi_render_packages)" || return 1
  [[ "$out" == *"scheme: not a scheme (ignored - not a scheme)"* ]]
}

function test_preview_names_every_group() {
  local g stripped
  stripped="$(_hi_strip_ansi "$_HI_PACKAGES_OUT")"
  for g in core useful deprecated extras platform; do
    printf '%s\n' "$stripped" | grep -q "^| $g  *| " || return 1
  done
}

# the lines under the marks are the only place the two markers are explained,
# so the render has to carry them
function test_preview_explains_the_markers() {
  printf '%s\n' "$_HI_PACKAGES_OUT" | grep -q 'a leading - (unwanted) speaks only when installed'
}

function test_preview_counts_what_it_read() {
  printf '%s\n' "$_HI_PACKAGES_OUT" | grep -q '14 listed, 8 shown, 2 silent by their marker' &&
    printf '%s\n' "$_HI_PACKAGES_OUT" | grep -q '4 more in groups'
}

# the check itself is the last thing the preview prints, so a package the
# header would show has to appear below the tables as well as inside them -
# and one from a group that is off, only inside them
function test_preview_ends_with_the_real_check() {
  local tail
  tail="$(printf '%s\n' "$_HI_PACKAGES_OUT" | tail -3)"
  [[ "$tail" == *hialpha* && "$tail" != *hicharlie* ]]
}

# the check follows $_HI_PACKAGES_GROUPS: naming extras alone turns core off
# in the legend and in the check, extras on, and the rows above the first
# header still print
function test_preview_follows_the_groups_setting() {
  local out stripped tail
  out="$(_HI_PACKAGES_GROUPS=extras _hi_render_packages)" || return 1
  stripped="$(_hi_strip_ansi "$out")"
  [[ "$(printf '%s\n' "$stripped" | grep '^| core ')" == *"| off "* ]] &&
    [[ "$(printf '%s\n' "$stripped" | grep '^| extras ')" == *"| on "* ]] &&
    [[ "$out" == *"(extras run)"* ]] || return 1
  tail="$(printf '%s\n' "$out" | tail -3)"
  [[ "$tail" == *hicharlie* && "$tail" == *hitop* && "$tail" != *hialpha* ]]
}

# Every section of the preview reads the packages file, so none at all is
# said out loud and stops the run - the bare redirect it replaces fails with a
# path and no hint of which file the tool wanted.
# $_HI_CONFIG_DIR points the child at an empty overlay, so the tree's
# config/packages is the only candidate - and the tree has none.
function test_preview_reports_no_packages_file() {
  local home out
  home="$(_hi_scratch_tree nopackages common config scripts)"
  rm -f "$home/say-hi/config/packages"
  out="$(PATH="$(_hi_pkg_path)" HOME="$home" _HI_HOME="$home" \
  _HI_CONFIG_DIR="$_HI_WORKDIR/nocfg" \
    "$home/say-hi/scripts/preview.sh" packages 2>&1)" && return 1
  [[ "$out" == *"No packages file at $home/say-hi/config/packages"* ]]
}

# ...and an exported $_HI_PACKAGES is not a way in: the script's paths.sh
# re-derives the path from $_HI_CONFIG_DIR and the tree, so the export is
# ignored and the tree's roster comes out. The overlay is the one way to
# point the check at a file of your own.
function test_preview_ignores_an_exported_packages() {
  local home decoy out
  home="$(_hi_scratch_tree exportedpkgs common config scripts)"
  cp "$_HI_WORKDIR/packages" "$home/say-hi/config/packages"
  decoy="$_HI_WORKDIR/exported-packages"
  printf 'hionlyone\n' >"$decoy"
  out="$(PATH="$(_hi_pkg_path)" HOME="$home" _HI_HOME="$home" \
  _HI_CONFIG_DIR="$_HI_WORKDIR/nocfg" _HI_PACKAGES="$decoy" \
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
  _hi_check "header says when the header is off" test_header_subject_says_when_the_header_is_off

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
Falls back to the hash|hostname|plain|hash
# a host carrying a tag with no hosttag entry has nothing to inherit, so it
# must read as the hash rather than claiming a tag it can't resolve
Ignores a tag with no override|hostname|othertag|hash
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
  _hi_check "_hi_colors_rows keeps to its [type] section" test_colors_rows_are_scoped_to_their_section
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
  _hi_check_eq "hbar sizes each column" "+-----+---+" _hi_hbar mid 3 1
  _hi_check_eq "hbar handles a single column" "+----+" _hi_hbar mid 2
  _hi_check "Group preview width sums its hosts" test_group_preview_width_sums_its_hosts
  _hi_check "Group index finds an existing key" test_group_index_finds_an_existing_key
  _hi_check "Group index misses a new key" test_group_index_misses_a_new_key
  _hi_check "Group index handles an empty table" test_group_index_handles_an_empty_table

  _hi_h2 "Testing: colors - the users table"
  _hi_check "Renders every override row" test_users_table_renders_override_rows
  _hi_check "Lists users that render by the hash" test_users_table_lists_hashed_users
  _hi_check "Shows the LOCALUSER pin as its own row" test_users_table_shows_the_localuser_pin
  _hi_check "Shows each usertag as its own row" test_users_table_shows_each_usertag

  _hi_h2 "Testing: colors - the hosts table"
  _hi_check "Groups hosts that render identically" test_hosts_table_groups_identical_renders
  _hi_check "Merges pattern hosts into the example row" test_hosts_table_merges_pattern_hosts_into_the_example_row
  _hi_check "Leads with a LOCALHOSTNAME pin" test_hosts_table_leads_with_a_localhostname_pin
  _hi_check "Pads a wrapped group's rows past its users" test_hosts_table_pads_a_wrapped_group_past_its_users
  _hi_check "A tag behind a leading Host * paints its host" test_hosts_table_paints_a_tag_behind_a_leading_wildcard
  _hi_check "A usertag row only under a host with the tag" test_hosts_table_draws_a_usertag_row_only_under_its_tag
  _hi_check "Lists the local machine unpinned" test_hosts_table_lists_the_local_machine_unpinned
  _hi_check "Reports a missing ssh config" test_hosts_table_reports_a_missing_ssh_config

  _hi_h2 "Testing: colors - the rendered tables"
  _hi_check "Render without error" test_tables_render_without_error
  _hi_check "Render under a scheme, and name it" test_tables_render_under_a_scheme
  _hi_check "Lists every ssh-config host" test_tables_list_every_ssh_config_host
  _hi_check "Labels hashed hosts hash" test_tables_label_hashed_hosts_hash
  _hi_check "Name the matching tag" test_tables_name_the_matching_tag
  _hi_check "A pattern pin gets an example row" test_tables_show_a_pattern_pin_example_row
  _hi_check "LOCALUSER and usertag pins get example rows" test_tables_list_the_local_user_and_usertag_pins
  _hi_check "Render from the checkout, without truecolor" test_tables_render_from_the_checkout
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
  _hi_check "Legend is rectangular" _hi_table_is_rectangular "$_HI_GROUPS_OUT"
  _hi_check "Marks table explains every mark" test_marks_table_explains_every_mark
  _hi_check "Marks table paints each glyph" test_marks_table_paints_each_glyph
  _hi_check "Marks table is rectangular" test_marks_table_is_rectangular
  _hi_check "Marks table explains the markers" test_marks_table_explains_the_markers
  _hi_check "Marks table draws the glyph set's corners" test_marks_table_renders_the_glyph_set

  _hi_h2 "Testing: packages - the rendered preview"
  _hi_check "Help prints usage and stops" test_help_prints_usage_and_stops
  _hi_check "A stray argument is refused" test_packages_stray_argument_is_refused
  _hi_check_eq "-h matches --help" "$(_hi_render_packages_help --help)" _hi_render_packages_help -h
  _hi_check "Renders without error" test_preview_renders_without_error
  _hi_check "Names the active palette" test_preview_names_the_active_palette
  _hi_check "Names a custom scheme, and its second bank" test_preview_names_a_custom_scheme_and_its_bank
  _hi_check "Names every group" test_preview_names_every_group
  _hi_check "Explains the markers" test_preview_explains_the_markers
  _hi_check "Counts what it read" test_preview_counts_what_it_read
  _hi_check "Ends with the real check" test_preview_ends_with_the_real_check
  _hi_check "Every line of a table is the same width" _hi_table_is_rectangular "$_HI_PACKAGES_OUT"
  _hi_check "Follows \$_HI_PACKAGES_GROUPS" test_preview_follows_the_groups_setting
  _hi_check "Reports no packages file at all" test_preview_reports_no_packages_file
  _hi_check "An exported \$_HI_PACKAGES is ignored" test_preview_ignores_an_exported_packages
  _hi_check "Reads the tree's own file when nothing is exported" test_preview_reads_the_trees_own_file

  _hi_suite_end "preview.sh"
}

run_preview_tests
