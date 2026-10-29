#!/usr/bin/env bash
# Unit tests for scripts/add_tag.sh - `hi --add-tag`, which writes the
# `# Tags:` comment above a host's Host line in ~/.ssh/config.
#
# Driven through `hi.sh --add-tag`, as add_package_test.sh drives its
# command, so the common/flags row and the dispatch are covered with it. Each
# case gets its own $HOME, and so its own ~/.ssh/config.
#
# GLOSSARY: HI.34.
# shellcheck disable=SC2329,SC2317
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# _hi_addtag_fixture <name> - a tree with scripts/, and a home whose ssh
# config tags web1, leaves web2 bare, covers *.prod by a wildcard only, and
# Includes one more file. Prints the home, which is also the fixture's
# _HI_HOME.
function _hi_addtag_fixture() {
  local home
  home="$(_hi_scratch_tree "$1" common config load.sh hi.sh link:scripts)"
  mkdir -p "$home/.ssh/config.d"
  printf '%s\n' 'Include config.d/*' '# Tags: old' 'Host web1' '  HostName 10.0.0.1' '' \
    'Host web2' '  HostName 10.0.0.2' '' 'Host *.prod' '  User deploy' >"$home/.ssh/config"
  printf 'Host inc1\n' >"$home/.ssh/config.d/01-inc"
  chmod 600 "$home/.ssh/config"
  printf '%s' "$home"
}

# _hi_addtag_run <home> <args...>
function _hi_addtag_run() {
  local home="$1"
  shift
  HOME="$home" _HI_CONFIG_DIR="$home/overlay" _hi_subcmd_run "$home" --add-tag "$@"
}

# a host with no tag gets one directly above its Host line
function test_add_tag_writes_above_the_host() {
  local home
  home="$(_hi_addtag_fixture addtag-new)"
  _hi_addtag_run "$home" web2 lab >/dev/null || _hi_why home || return 1
  grep -A1 -x '# Tags: lab' "$home/.ssh/config" | grep -qx 'Host web2' || _hi_why home
}

# a tag already there is replaced, not stacked - the walk reads only one
function test_add_tag_replaces_an_existing_tag() {
  local home got
  home="$(_hi_addtag_fixture addtag-replace)"
  _hi_addtag_run "$home" web1 prod >/dev/null || _hi_why home || return 1
  got="$(grep -c '^# Tags:' "$home/.ssh/config")"
  { [ "$got" -eq 1 ] && grep -A1 -x '# Tags: prod' "$home/.ssh/config" | grep -qx 'Host web1'; } || _hi_why got home
}

# a host that lives in an Included file is tagged there
function test_add_tag_writes_the_included_file() {
  local home got
  home="$(_hi_addtag_fixture addtag-include)"
  _hi_addtag_run "$home" inc1 lab >/dev/null || _hi_why home || return 1
  got="$(cat "$home/.ssh/config.d/01-inc")"
  { [ "$got" = '# Tags: lab
Host inc1' ] && ! grep -q lab "$home/.ssh/config"; } || _hi_why got home
}

# ...where the file's own name already tags it: asked for that tag, nothing
# is written, and another is said to go over it
function test_add_tag_knows_a_config_d_file_s_name() {
  local home out got
  home="$(_hi_addtag_fixture addtag-configd)"
  out="$(_hi_addtag_run "$home" inc1 01-inc)" || _hi_why home || return 1
  got="$(cat "$home/.ssh/config.d/01-inc")"
  [[ "$out" == *"inc1 is already tagged 01-inc, by the file's name"* ]] && [ "$got" = 'Host inc1' ] || _hi_why out got home || return 1
  out="$(_hi_addtag_run "$home" inc1 lab)" || _hi_why home || return 1
  { [[ "$out" == *"over the file's own tag 01-inc"* ]] && grep -qx '# Tags: lab' "$home/.ssh/config.d/01-inc"; } || _hi_why out home
}

# a name only a wildcard covers is refused, naming the block to tag instead
function test_add_tag_refuses_a_wildcard_only_host() {
  local home out
  home="$(_hi_addtag_fixture addtag-wild)"
  ! out="$(_hi_addtag_run "$home" db.prod prod)" || _hi_why out home || return 1
  { [[ "$out" == *"only 'Host *.prod' covers it"* ]] && ! grep -q '^# Tags: prod' "$home/.ssh/config"; } || _hi_why out home
}

# ...and the pattern itself can be tagged
function test_add_tag_tags_a_pattern() {
  local home
  home="$(_hi_addtag_fixture addtag-pattern)"
  _hi_addtag_run "$home" '*.prod' prod >/dev/null || _hi_why home || return 1
  grep -A1 -x '# Tags: prod' "$home/.ssh/config" | grep -qx 'Host \*.prod' || _hi_why home
}

function test_add_tag_refuses_an_unknown_host_and_a_bad_tag() {
  local home before got
  home="$(_hi_addtag_fixture addtag-refuse)"
  before="$(cat "$home/.ssh/config")"
  ! _hi_addtag_run "$home" nothere lab >/dev/null || _hi_why home || return 1
  ! _hi_addtag_run "$home" web2 'two words' >/dev/null || _hi_why home || return 1
  # a backend's word is every target of that kind's tag (settings.kube.sh)
  ! _hi_addtag_run "$home" web2 kube >/dev/null || _hi_why home || return 1
  ! _hi_addtag_run "$home" web2 docker >/dev/null || _hi_why home || return 1
  ! _hi_addtag_run "$home" web2 >/dev/null || _hi_why home || return 1
  got="$(cat "$home/.ssh/config")"
  [ "$got" = "$before" ] || _hi_why got home before
}

function test_add_tag_help_is_its_own() {
  local home out
  home="$(_hi_addtag_fixture addtag-help)"
  out="$(_hi_addtag_run "$home" --help)" || _hi_why home || return 1
  [[ "$out" == "Usage: hi --add-tag <host> <tag> [--dry-run]"* ]] &&
    [[ "$out" == *"$home/.ssh/config"* && "$out" == *"-n, --dry-run"* ]] || _hi_why out home
}

function test_add_tag_refuses_an_unknown_option() {
  local got
  local home before out rc=0
  home="$(_hi_addtag_fixture addtag-opt)"
  before="$(cat "$home/.ssh/config")"
  out="$(_hi_addtag_run "$home" web2 lab --bogus)" || rc=$?
  got="$(cat "$home/.ssh/config")"
  [ "$rc" -ne 0 ] && [[ "$out" == *"unknown option --bogus"* ]] && [ "$got" = "$before" ] || _hi_why got rc out home before
}

# the tag a host already carries is said, and nothing is written
function test_add_tag_leaves_a_host_already_tagged() {
  local home before out got
  home="$(_hi_addtag_fixture addtag-same)"
  before="$(cat "$home/.ssh/config")"
  out="$(_hi_addtag_run "$home" web1 old)" || _hi_why home || return 1
  got="$(cat "$home/.ssh/config")"
  [[ "$out" == *"web1 is already tagged old"* && "$out" != *updated* ]] && [ "$got" = "$before" ] || _hi_why got out home before
}

function test_add_tag_dry_run_writes_nothing() {
  local home before out got
  home="$(_hi_addtag_fixture addtag-dry)"
  before="$(cat "$home/.ssh/config")"
  out="$(_hi_addtag_run "$home" web2 lab --dry-run)" || _hi_why home || return 1
  got="$(cat "$home/.ssh/config")"
  [[ "$out" == *"dry run: would write"* ]] && [ "$got" = "$before" ] || _hi_why got out home before
}

# the file keeps its mode through the rewrite (ssh refuses a loose config)
function test_add_tag_keeps_the_config_mode() {
  local home got
  home="$(_hi_addtag_fixture addtag-mode)"
  _hi_addtag_run "$home" web2 lab >/dev/null || _hi_why home || return 1
  got="$(_hi_mode_string "$home/.ssh/config")"
  [ "$got" = -rw------- ] || _hi_why got home
}

# The round trip the command exists for: tagged, then drawn by
# `hi --preview colors` in the hosttag row's color, under that tag
function test_add_tag_round_trips_through_preview_colors() {
  local home out esc
  home="$(_hi_addtag_fixture addtag-preview)"
  # a leading `Host *` of defaults, the shape most real configs open with:
  # it matches web2 too, and must not end the tag walk before web2's block
  { printf 'Host *\n  AddKeysToAgent yes\n\n' && cat "$home/.ssh/config"; } >"$home/.ssh/config.new"
  mv "$home/.ssh/config.new" "$home/.ssh/config"
  mkdir -p "$home/overlay"
  printf '[hosttag]\nlab = "brred"\n' >"$home/overlay/colors"
  _hi_addtag_run "$home" web2 lab >/dev/null || _hi_why home || return 1
  out="$(HOME="$home" _HI_HOME="$home" _HI_CONFIG_DIR="$home/overlay" _HI_TARGETS_TTL=0 \
    "$home/say-hi/scripts/preview.sh" colors 2>&1)" || _hi_why home || return 1
  _hi_color_escape_var esc brred
  printf -v esc '%b' "$esc"
  [[ "$out" == *"${esc}web2"* ]] || _hi_because "web2 is not painted brred" || return 1
  out="$(_hi_strip_ansi "$out")"
  printf '%s\n' "$out" | grep 'web2' | grep -q 'tag:lab' || _hi_why out
}

# --remove-tag takes the line back out, and nothing else
function test_remove_tag_takes_the_line_out() {
  local home before after
  home="$(_hi_addtag_fixture rmtag)"
  before="$(wc -l <"$home/.ssh/config")"
  HOME="$home" _HI_CONFIG_DIR="$home/overlay" _hi_subcmd_run "$home" --remove-tag web1 >/dev/null || _hi_why home || return 1
  after="$(wc -l <"$home/.ssh/config")"
  { ! grep -q '^# Tags:' "$home/.ssh/config" && [ "$after" -eq "$((before - 1))" ] &&
    grep -qx 'Host web1' "$home/.ssh/config"; } || _hi_why before after home
}

# ...a host with no line writes nothing, and says so - naming the file's own
# tag where a config.d file's name gives it one
function test_remove_tag_without_a_line_writes_nothing() {
  local home out sum now
  home="$(_hi_addtag_fixture rmtag-none)"
  sum="$(cksum <"$home/.ssh/config")"
  out="$(HOME="$home" _HI_CONFIG_DIR="$home/overlay" _hi_subcmd_run "$home" --remove-tag web2)" || _hi_why home || return 1
  [[ "$out" == *"web2 has no # Tags: line - nothing to write"* ]] || _hi_why out || return 1
  out="$(HOME="$home" _HI_CONFIG_DIR="$home/overlay" _hi_subcmd_run "$home" --remove-tag inc1)" || _hi_why home || return 1
  [[ "$out" == *"the file's name tags it 01-inc"* ]] || _hi_why out || return 1
  now="$(cksum <"$home/.ssh/config")"
  [ "$now" = "$sum" ] || _hi_why home sum now
}

# --remove-tag takes a host alone, and its --help is its own
function test_remove_tag_takes_a_host_alone() {
  local home out rc=0
  home="$(_hi_addtag_fixture rmtag-args)"
  out="$(HOME="$home" _HI_CONFIG_DIR="$home/overlay" _hi_subcmd_run "$home" --remove-tag web1 lab 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"needs a host"* ]] || _hi_why rc out || return 1
  out="$(HOME="$home" _HI_CONFIG_DIR="$home/overlay" _hi_subcmd_run "$home" --remove-tag --help)" || _hi_why home || return 1
  [[ "$out" == "Usage: hi --remove-tag <host> [--dry-run]"* ]] || _hi_why out
}

# a block that carries ssh's own Tag line: asked for that tag, nothing is
# written; asked for another, the comment is written and the Tag line
# named; and --remove-tag with no comment names it as what still tags the
# host
function test_add_tag_says_when_the_block_carries_a_tag_line() {
  local home out got before
  home="$(_hi_addtag_fixture addtag-native)"
  printf '%s\n' 'Host kw' '  Tag native' '  User x' >>"$home/.ssh/config"
  before="$(cat "$home/.ssh/config")"
  out="$(_hi_addtag_run "$home" kw native)" || _hi_why home || return 1
  got="$(cat "$home/.ssh/config")"
  [[ "$out" == *"kw is already tagged native, by its Tag line"* ]] && [ "$got" = "$before" ] || _hi_why out got home || return 1
  out="$(HOME="$home" _HI_CONFIG_DIR="$home/overlay" _hi_subcmd_run "$home" --remove-tag kw)" || _hi_why home || return 1
  got="$(cat "$home/.ssh/config")"
  [[ "$out" == *"kw has no # Tags: line - its Tag line tags it native"* ]] && [ "$got" = "$before" ] || _hi_why out got home || return 1
  out="$(_hi_addtag_run "$home" kw lab)" || _hi_why home || return 1
  { [[ "$out" == *"kw's block also carries Tag native"* ]] && grep -A1 -x '# Tags: lab' "$home/.ssh/config" | grep -qx 'Host kw' &&
    grep -qx '  Tag native' "$home/.ssh/config"; } || _hi_why out home
}

function run_add_tag_tests() {
  _hi_workdir addtag
  _hi_suite_begin

  _hi_h1 "Testing scripts/add_tag.sh"
  _hi_check "Writes a tag above the Host line" test_add_tag_writes_above_the_host
  _hi_check "Replaces an existing tag" test_add_tag_replaces_an_existing_tag
  _hi_check "Tags a host in the file it is Included from" test_add_tag_writes_the_included_file
  _hi_check "...and knows the tag a config.d file's name gives it" test_add_tag_knows_a_config_d_file_s_name
  _hi_check "Refuses a wildcard-only host, naming the block" test_add_tag_refuses_a_wildcard_only_host
  _hi_check "Tags a pattern" test_add_tag_tags_a_pattern
  _hi_check "Refuses an unknown host and a bad tag" test_add_tag_refuses_an_unknown_host_and_a_bad_tag
  _hi_check "--help is its own text" test_add_tag_help_is_its_own
  _hi_check "Refuses an unknown option, nothing written" test_add_tag_refuses_an_unknown_option
  _hi_check "Leaves a host that already carries the tag" test_add_tag_leaves_a_host_already_tagged
  _hi_check "Says when the block carries ssh's own Tag line" test_add_tag_says_when_the_block_carries_a_tag_line
  _hi_check "--dry-run writes nothing" test_add_tag_dry_run_writes_nothing
  _hi_check_capable mode_bits "Keeps the config's mode" test_add_tag_keeps_the_config_mode
  _hi_check "Round-trips through hi --preview colors" test_add_tag_round_trips_through_preview_colors

  _hi_check "--remove-tag takes the line back out" test_remove_tag_takes_the_line_out
  _hi_check "...writes nothing where there is none, and says why" test_remove_tag_without_a_line_writes_nothing
  _hi_check "...and takes a host alone, with its own --help" test_remove_tag_takes_a_host_alone

  _hi_suite_end "scripts/add_tag.sh"
}

run_add_tag_tests
