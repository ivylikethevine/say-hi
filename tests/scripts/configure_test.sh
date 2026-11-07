#!/usr/bin/env bash
# Unit tests for hi --configure's settings write - scripts/configure.sh (the
# rc.sh and table.sh helpers it shares have their own suites): the preset
# plumbing, the validators, and the one write to $_HI_SETTINGS.
# tests/scripts/install_test.sh is the other half: install_tree's
# packaging-mode DESTDIR layout and the
# --uninstall/strip_marker/strip_settings/unlink_hi teardown path.
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# every batch here is plain local processes, no container daemon to spare
_HI_PAR_LOCAL=1
set -- # install.sh reads "$@" for its own args; make sure it sees none
# shellcheck source=../../scripts/install.sh
source "$_HI_INSTALL"

# Nothing is spliced into common/paths.sh - the settings live in
# $_HI_SETTINGS, which every entry point sources *ahead* of paths.sh so that
# paths.sh's local-only gate can read them. That ordering is the load-bearing
# property, and it's spread across three files (no single include line is
# valid in sh, bash, zsh, and fish alike), so assert it in each.
# Comment lines are filtered out first: both files explain themselves in prose
# that names the very files being looked for, and a comment mentioning paths.sh
# above the code that sources settings.sh would read as the wrong order.
# _hi_before is the harness's ordering assertion; the only thing this check
# adds is dropping comment lines first, so a mention in a comment above the
# real source line cannot answer for it.
function _hi_sources_settings_before_paths() {
  _hi_before "$(grep -v '^[[:space:]]*#' "$1")" 'settings\.sh' 'paths\.sh'
}

# hi.sh's fallback rc is the third entry point, but it's *generated* rather
# than sourced, so it's asserted against _hi_fallback_rc's real output over in
# tests/hi/parse_test.sh instead of by grepping the file.

# What the collector sets for a file: every case reads the uncommented lines
# it writes (_hi_set_lines, below) - no tty, so nothing is asked and the file
# is the whole answer; _hi_block_lines is the whole block, comments and all.
function test_prompt_ends_keeps_an_existing_override() {
  _hi_says "export _HI_PROMPT_END_ZSH='::'" _hi_set_lines prompt_keep "export _HI_PROMPT_END_ZSH='::'"
}

# quoted on the way out: a separator is as likely to be $ or > as a letter, and
# the file is sourced by sh, bash, zsh, and fish alike
function test_prompt_ends_quotes_what_it_writes() {
  local out
  out="$(_hi_set_lines prompt_quote "export _HI_PROMPT_END_BASH='>'")"
  [[ "$out" == *"_HI_PROMPT_END_BASH='>'"* ]] || _hi_why out
}

# the prompt is off, so what it ends with is moot right now - and kept, so
# turning the prompt back on finds the separator where it was left.
function test_prompt_ends_kept_when_the_prompt_is_off() {
  local out
  out="$(_hi_set_lines prompt_off "export _HI_DISABLE_PROMPT=1" "export _HI_PROMPT_END_ZSH='::'")"
  [[ "$out" == *"export _HI_DISABLE_PROMPT=1"* && "$out" == *"export _HI_PROMPT_END_ZSH='::'"* ]] || _hi_why out
}

# the scheme and the packages ramp are the colors file's (GLOSSARY: HI.50),
# so a run writes no line for either, even over a settings.sh that still
# holds them; doctor names those lines
function test_collector_writes_no_color_line() {
  local out
  out="$(_hi_set_lines colors_hand \
    "export _HI_PACKAGES_PALETTE='$_HI_TEST_RAMP'" "export _HI_COLOR_SCHEME='$_HI_TEST_SCHEME48'")"
  [[ "$out" != *_HI_PACKAGES_PALETTE* ]] && [[ "$out" != *_HI_COLOR_SCHEME* ]] || _hi_why out
}

function test_ip_hide_keeps_an_existing_override() {
  _hi_says "export _HI_IP_HIDE='none'" _hi_set_lines iphide_keep "export _HI_IP_HIDE='none'"
}

# the default is core.sh's own, so it is written commented, even when the
# file spells it out in full
function test_ip_hide_does_not_write_the_default() {
  _hi_prints "" _hi_set_lines iphide_default "export _HI_IP_HIDE='$_HI_IP_HIDE_DEFAULT'"
}

function test_header_order_keeps_an_existing_override() {
  _hi_says "export _HI_HEADER_ORDER='check gitid'" _hi_set_lines order_keep "export _HI_HEADER_ORDER='check gitid'"
}

function test_header_order_does_not_write_the_default() {
  _hi_prints "" _hi_set_lines order_default "export _HI_HEADER_ORDER='$_HI_HEADER_ORDER_DEFAULT'"
}

# the header is off, so its order is moot - and kept, like the separators
function test_header_order_kept_when_the_header_is_off() {
  local out
  out="$(_hi_set_lines order_off "export _HI_DISABLE_HEADER=1" "export _HI_HEADER_ORDER='check gitid'")"
  [[ "$out" == *"export _HI_DISABLE_HEADER=1"* && "$out" == *"export _HI_HEADER_ORDER='check gitid'"* ]] || _hi_why out
}

# the shipped set writes nothing; no group at all is an answer, spelled `none`
function test_packages_groups_does_not_write_the_default() {
  _hi_prints "" _hi_set_lines groups_default "export _HI_PACKAGES_GROUPS='$_HI_PACKAGES_GROUPS_DEFAULT'"
}

function test_packages_groups_writes_none() {
  _hi_prints "export _HI_PACKAGES_GROUPS='none'" _hi_set_lines groups_none "export _HI_PACKAGES_GROUPS='none'"
}

# the check is off, so which groups it runs is moot - the stored value is kept
# for when 'check' comes back
function test_packages_groups_kept_when_the_check_is_off() {
  local out
  out="$(_hi_set_lines groups_off "export _HI_HEADER_ORDER='gitid'" "export _HI_PACKAGES_GROUPS='core'")"
  [[ "$out" == *"export _HI_HEADER_ORDER='gitid'"* && "$out" == *"export _HI_PACKAGES_GROUPS='core'"* ]] || _hi_why out
}

# the block is every scripts/settings row once, in its order, after the one
# comment saying how to read it: what an edit of the file starts from
function test_block_lists_every_setting_once() {
  local want got
  want="$(awk -F' [|] ' '!/^#/ && NF > 5 { print "# export " $2 "=" }' "$_HI_ROOT/scripts/settings")"
  got="$(_hi_block_lines every | sed -n '2,$p' | sed 's/=.*/=/')"
  [ "$got" = "$want" ] || _hi_because "the block's names are not the table's rows, in order: $(diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") | head -5)"
}

# a default is shown at its value: core.sh's $<name>_DEFAULT, else the row's
# one code span, a `\|` read as `|`; a default decided at run time is empty
function test_block_shows_each_default() {
  local out
  out="$(_hi_block_lines defaults)"
  [[ "$out" == *"# export _HI_MAX_WIDTH=80"* && "$out" == *"# export _HI_PROMPT_END_FISH='|'"* &&
    "$out" == *"# export _HI_HEADER_ORDER='$_HI_HEADER_ORDER_DEFAULT'"* &&
    "$out" == *"# export _HI_TRUECOLOR="$'\n'* ]] || _hi_why out
}

# a setting no preset answers is kept like any other, and a ' in a value is
# written so that sh reads the value back as it was
function test_block_keeps_a_quoted_value() {
  local out got
  out="$(_hi_set_lines quoted "export _HI_KEEP_TIMEOUT=2h" "export _HI_LS_OPTS=\"-F it's\"")"
  [[ "$out" == *"export _HI_KEEP_TIMEOUT=2h"* ]] || _hi_why out || return 1
  got="$(printf '%s\n' "$out" | grep _HI_LS_OPTS)"
  [ "$got" = "export _HI_LS_OPTS='-F it'\\''s'" ] || _hi_why got || return 1
  got="$(sh -c "$got; printf '%s' \"\$_HI_LS_OPTS\"")"
  [ "$got" = "-F it's" ] || _hi_why got
}

# _hi_pending_set replaces an earlier answer for the same var in place - a
# section opened twice must not leave two entries for pending_answer's
# first-match scan to disagree over
function test_pending_set_replaces_in_place() {
  (
    _HI_SETTING_PENDING=()
    _hi_pending_set _HI_A 1
    _hi_pending_set _HI_B two
    _hi_pending_set _HI_A ""
    [ "${#_HI_SETTING_PENDING[@]}" = 2 ] &&
      [ -z "$(pending_answer _HI_A)" ] && pending_answer _HI_A &&
      [ "$(pending_answer _HI_B)" = two ]
  ) || _hi_why _HI_SETTING_PENDING
}

# The input validators guarding what ask_value will write into settings.sh -
# the single-quote one is what keeps a typed value from ending the sh word the
# written `export NAME='value'` line wraps it in.
function test_validators_hold_their_grammars() {
  _hi_is_number 42 || _hi_why || return 1
  ! _hi_is_number 4.2 || _hi_why || return 1
  ! _hi_is_number '' || _hi_why || return 1
  ! _hi_is_number 4x || _hi_why || return 1
  _hi_has_no_single_quote "plain value" || _hi_why || return 1
  ! _hi_has_no_single_quote "don't" || _hi_why || return 1
  _hi_is_ip_hide none || _hi_why || return 1
  _hi_is_ip_hide '172.*' || _hi_why || return 1
  _hi_is_ip_hide '10.* 192.168.?.*' || _hi_why || return 1
  ! _hi_is_ip_hide "" || _hi_why || return 1
  ! _hi_is_ip_hide "172.*;rm" || _hi_why || return 1
  _hi_is_ip_hide 'docker* br-* eth1' || _hi_why || return 1
  ! _hi_is_ip_hide "it's" || _hi_why || return 1
  _hi_is_package_groups none || _hi_why || return 1
  _hi_is_package_groups 'core useful' || _hi_why || return 1
  _hi_is_package_groups 'core,my-tools.2' || _hi_why || return 1
  ! _hi_is_package_groups "" || _hi_why || return 1
  ! _hi_is_package_groups 'core;rm' || _hi_why || return 1
  ! _hi_is_package_groups "[core]" || _hi_why || return 1
  _hi_is_header_order utc || _hi_why || return 1
  _hi_is_header_order check || _hi_why || return 1
  ! _hi_is_header_order bogus || _hi_why || return 1
  ! _hi_is_header_order "" || _hi_why
}

# _hi_setting_check, the one verdict the wizard takes an answer by and doctor
# judges a hand-written line by: each kind of scripts/settings <check> against
# a value it takes and one it does not, and 2 for a kind it does not know.
# pack.sh in a subshell, as hi.sh has it loaded ahead of doctor: `plugins`
# reads the plugin tables through it. Each row: <check>|<value>|<status>
function test_setting_check_gives_each_kind_its_verdict() {
  (
    # not followed: its background jobs' $! would read, to shellcheck, as
    # this file's own (SC2031 at every later "$!")
    # shellcheck source=/dev/null
    source "$_HI_ROOT/scripts/pack.sh" || _hi_because "pack.sh did not load" || exit 1
    _hi_setting_check_rows
  )
}
function _hi_setting_check_rows() {
  local check value want got
  while IFS='|' read -r check value want; do
    got=0
    _hi_setting_check "$check" "$value" || got=$?
    [ "$got" = "$want" ] || _hi_because "$check [$value]: $got, not $want" || return 1
  done <<'ROWS'
toggle|1|0
toggle|0|0
toggle|2|1
flag|yes|1
number:5|5|0
number:5|12|0
number:5|4|1
number:5|x|1
duration|30|0
duration|30s|0
duration|5m|0
duration|2h|0
duration|1d|0
duration|1.5h|1
duration|5x|1
duration|m|1
duration||1
header|utc check|0
header|utc bogus|1
header||1
prompts|hi|0
prompts|bash:hi starship|0
prompts|fish:tide zsh:powerlevel10k|0
prompts|bash:tide|1
prompts|bogus|1
plugins|vim, tmux|0
plugins|vim bogus-plugin|1
editor|nvim|0
editor|notepad|1
shells|login|0
shells|zsh fish login|0
shells|nope|1
shells|bash nope|1
shells||1
globs|10.* 192.168.?.*|0
globs|172.*;rm|1
groups|core useful|0
groups|core;rm|1
noquote|plain value|0
noquote|don't|1
-|anything|0
bogus-kind|1|2
ROWS
}

function test_pending_answer_reads_this_runs_answers() {
  (
    _HI_SETTING_PENDING=("_HI_A=1" "_HI_B=two words")
    [ "$(pending_answer _HI_A)" = 1 ] &&
      [ "$(pending_answer _HI_B)" = "two words" ] &&
      ! pending_answer _HI_C
  ) || _hi_why
}

# settings.sh is sourced by sh, bash, zsh, and fish, so line 1 has to be the
# `#!/bin/sh` all four read as a comment - and has to stay line 1 once
# config_shell has written the settings block under it.
function _hi_shebang_fresh() { ensure_settings_shebang; }

function test_shebang_is_written_to_a_new_settings_file() {
  local got
  _hi_settings_fixture shebang_new _hi_shebang_fresh
  got="$(head -n 1 "$(_hi_fixture_settings shebang_new)")"
  [ "$got" = "#!/bin/sh" ] || _hi_why got
}

function _hi_shebang_then_settings() {
  ensure_settings_shebang
  config_shell settings "$_HI_SETTINGS" "export _HI_DISABLE_PROMPT=1"
}

function test_shebang_stays_first_under_the_settings_block() {
  local got
  _hi_settings_fixture shebang_block _hi_shebang_then_settings
  local f
  f="$(_hi_fixture_settings shebang_block)"
  got="$(head -n 1 "$f")"
  { [ "$got" = "#!/bin/sh" ] && grep -qF "export _HI_DISABLE_PROMPT=1" "$f"; } || _hi_why got f
}

# re-running must not stack a second shebang
function _hi_shebang_twice() {
  ensure_settings_shebang
  ensure_settings_shebang
}

function test_shebang_is_not_duplicated_on_reruns() {
  local got
  _hi_settings_fixture shebang_twice _hi_shebang_twice
  got="$(grep -c '^#!' "$(_hi_fixture_settings shebang_twice)")"
  [ "$got" -eq 1 ] || _hi_why got
}

# a hand-edited shebang for the wrong shell is replaced, not left alongside:
# dash and fish both source this file, so sh is the only correct one
function _hi_shebang_wrong() {
  printf '%s\n%s\n' '#!/bin/bash' 'export _HI_MAX_WIDTH=120' >"$_HI_SETTINGS"
  ensure_settings_shebang
}

function test_shebang_replaces_a_different_one_and_keeps_content() {
  local got got2
  _hi_settings_fixture shebang_wrong _hi_shebang_wrong
  local f
  f="$(_hi_fixture_settings shebang_wrong)"
  got="$(head -n 1 "$f")"
  got2="$(grep -c '^#!' "$f")"
  { [ "$got" = "#!/bin/sh" ] && [ "$got2" -eq 1 ] && grep -qF "export _HI_MAX_WIDTH=120" "$f"; } || _hi_why got got2 f
}

# same mode-preservation contract as config_shell, and the same reason its own
# check compares a file to its earlier self rather than to a separately
# chmod'd reference: two files that never shared a history can end up with
# different `ls -l` strings for the same nominal mode wherever the platform's
# permission bits are a derived/ACL-backed approximation rather than a stored
# POSIX field (seen on a real Windows runner - the two `chmod 604`s disagreed
# even though nothing here should ever move a bit). Stashed to a workdir file
# because $_HI_WORKDIR is the only channel back out - _hi_settings_fixture
# swallows stdout and its $_HI_SETTINGS is local to its own call.
function _hi_shebang_mode() {
  printf 'X=1\n' >"$_HI_SETTINGS"
  chmod 604 "$_HI_SETTINGS"
  _hi_mode_string "$_HI_SETTINGS" >"$_HI_WORKDIR/shebang_mode.before"
  ensure_settings_shebang
}

function test_settings_shebang_preserves_mode() {
  local got got2
  _hi_settings_fixture shebang_mode _hi_shebang_mode
  got="$(_hi_mode_string "$(_hi_fixture_settings shebang_mode)")"
  got2="$(cat "$_HI_WORKDIR/shebang_mode.before")"
  [ "$got" = "$got2" ] || _hi_why got got2
}

# the three config_* groups accumulate rather than each calling config_shell,
# because one config_shell call per group against one file would have each
# wipe the other two's lines
function _hi_settings_one_write() {
  local -a _HI_SETTING_LINES=("export _HI_DISABLE_PROMPT=1" "" "export _HI_DISABLE_GIT_STATUS=1")
  config_shell settings "$_HI_SETTINGS" "${_HI_SETTING_LINES[@]}"
}

function test_config_settings_writes_every_group_at_once() {
  _hi_settings_fixture onewrite _hi_settings_one_write
  local f
  f="$(_hi_fixture_settings onewrite)"
  { grep -qF "export _HI_DISABLE_PROMPT=1" "$f" && grep -qF "export _HI_DISABLE_GIT_STATUS=1" "$f"; } || _hi_why f
}

# the whole point of the overlay: a fresh install leaves the tree untouched, so
# `hi --update`'s tag checkout still applies and a root-owned tree still works
function test_settings_are_written_outside_the_tree() {
  local got
  _hi_settings_fixture outside _hi_shebang_fresh
  got="$(_hi_fixture_settings outside)"
  [ -f "$got" ] && [ ! -e "$_HI_WORKDIR/outside/config/settings.sh" ] || _hi_why got
}

# the line as config_shell really writes it: marker-padded, unquoted - the
# exact spelling hi.sh's payload trim has to read correctly
function test_setting_get_reads_marker_padded_line() {
  local target="$_HI_WORKDIR/padded"
  printf '%-45s %s\n' 'export _HI_DISABLE_FOO=1' "$_HI_MARKER" >"$target"
  _hi_prints 1 _hi_setting_get "$target" _HI_DISABLE_FOO
}

# _hi_setting_get sources the file for real rather than hand-scanning
# `export NAME=value` text: a computed value real bash would honour reads the
# same way here, exactly as a settings.sh sourced on a target would resolve it.
function test_setting_get_reads_a_computed_value() {
  local target="$_HI_WORKDIR/computed"
  # shellcheck disable=SC2016 # the file's own text, for it to expand when sourced - not ours to expand now
  printf 'export _HI_DISABLE_FOO=$((1))\n' >"$target"
  _hi_prints 1 _hi_setting_get "$target" _HI_DISABLE_FOO
}

# ...and a two-statement assignment, which a bare `export NAME=` line-start
# check would never match
function test_setting_get_reads_a_two_statement_assignment() {
  local target="$_HI_WORKDIR/twostatement"
  printf '_HI_DISABLE_FOO=1\nexport _HI_DISABLE_FOO\n' >"$target"
  _hi_prints 1 _hi_setting_get "$target" _HI_DISABLE_FOO
}

# a settings.sh that references another real variable ($_HI_CONFIG_DIR, say)
# still resolves normally - only the queried name is unset going in
function test_setting_get_leaves_other_variables_ambient() {
  local target="$_HI_WORKDIR/ambient"
  # shellcheck disable=SC2016 # the file's own text, for it to expand when sourced - not ours to expand now
  printf 'export _HI_DISABLE_FOO="$_HI_CONFIG_DIR/marker"\n' >"$target"
  _HI_CONFIG_DIR=/probe-dir _hi_prints /probe-dir/marker _hi_setting_get "$target" _HI_DISABLE_FOO
}

# _hi_block_lines <name> [settings-line ...] - the block the collector writes
# for a file holding those lines, a line each
function _hi_block_lines() {
  local dir="$_HI_WORKDIR/block_$1"
  local _HI_SETTINGS="$dir/settings.sh"
  local -a _HI_SETTING_LINES=()
  _HI_SETTING_PENDING=()
  mkdir -p "$dir"
  shift
  [ "$#" -eq 0 ] && : >"$_HI_SETTINGS" || printf '%s\n' "$@" >"$_HI_SETTINGS"
  collect_setting_lines
  printf '%s\n' "${_HI_SETTING_LINES[@]}"
}

# _hi_set_lines <name> [settings-line ...] - its uncommented lines alone
function _hi_set_lines() {
  _hi_block_lines "$@" | sed -n '/^export /p'
}

# The pty rig (configure_pty): config_pick_preset is `[ -t 0 ]`-gated, and a
# pty reaches it. The child points the settings at a scratch dir, runs the
# configure function named on its argv with the pty as stdin, and reports
# the exit code and the collected lines on one greppable tail line. Feeding
# a question an extra newline is harmless (it sits unread); feeding one too
# few hangs the child, which _hi_wait_pid turns into the kill this helper
# reports.
# shellcheck disable=SC2016 # single quotes on purpose: every expansion in here
# is the child shell's to make, after the pty has put it on the other side
_HI_CFG_CHILD='
  _hi_dir="$1"
  shift
  _hi_cfg_argv=("$@")
  source "$_HI_TEST_LIB"
  set --
  source "$_HI_INSTALL"
  _HI_CONFIG_DIR="$_hi_dir/overlay"
  _HI_SETTINGS="$_hi_dir/overlay/settings.sh"
  _HI_SETTING_LINES=()
  _HI_SETTING_PENDING=()
  _HI_FEATURES_ONLY=1
  _hi_cfg_rc=0
  "${_hi_cfg_argv[@]}" || _hi_cfg_rc=$?
  collect_setting_lines
  _hi_cfg_set=""
  for _hi_cfg_l in "${_HI_SETTING_LINES[@]}"; do
    case "$_hi_cfg_l" in export\ *) _hi_cfg_set="$_hi_cfg_set$_hi_cfg_l " ;; esac
  done
  printf "CFGRC=%s CFGLINES=%s\n" "$_hi_cfg_rc" "${_hi_cfg_set% }" |
    tee "$_hi_dir/verdict"
'

# _hi_configure_begin - what every part of this suite starts from, and the tally
function _hi_configure_begin() {
  _hi_workdir configuretest
  # the header validator reads header.sh's vocabulary, as doctor has it loaded
  # shellcheck source=../../common/header.sh
  source "$_HI_HEADER"
  _hi_suite_begin
}

function run_configure_tests() {
  _hi_configure_begin

  _hi_h1 "Testing scripts/configure.sh's reusable logic"

  _hi_h2 "Testing: settings are sourced ahead of paths.sh"
  _hi_check "common/core.sh" _hi_sources_settings_before_paths "$_HI_ROOT/common/core.sh"
  _hi_check "common/config.fish" _hi_sources_settings_before_paths "$_HI_ROOT/common/config.fish"

  _hi_h2 "Testing: the collector"
  _hi_check "Separators: an existing override is kept" test_prompt_ends_keeps_an_existing_override
  _hi_check "Separators: written values are quoted" test_prompt_ends_quotes_what_it_writes
  _hi_check "Separators: kept when the prompt is off" test_prompt_ends_kept_when_the_prompt_is_off
  _hi_check "Colors: no scheme or ramp line is written" test_collector_writes_no_color_line
  _hi_check "Hidden addresses: an existing override is kept" test_ip_hide_keeps_an_existing_override
  _hi_check "Hidden addresses: the default is commented" test_ip_hide_does_not_write_the_default
  _hi_check "Order: an existing override is kept" test_header_order_keeps_an_existing_override
  _hi_check "Order: the default is commented" test_header_order_does_not_write_the_default
  _hi_check "Order: kept when the header is off" test_header_order_kept_when_the_header_is_off
  _hi_check "Package groups: the default set is commented" test_packages_groups_does_not_write_the_default
  _hi_check "Package groups: none is written out" test_packages_groups_writes_none
  _hi_check "Package groups: kept when the check is off" test_packages_groups_kept_when_the_check_is_off
  _hi_check "The block lists every setting once, in order" test_block_lists_every_setting_once
  _hi_check "A commented line shows its default" test_block_shows_each_default
  _hi_check "Any setting is kept, a quote escaped" test_block_keeps_a_quoted_value

  _hi_h2 "Testing: the answer plumbing"
  _hi_check "The input validators hold their grammars" test_validators_hold_their_grammars
  _hi_check "_hi_setting_check gives each kind its verdict" test_setting_check_gives_each_kind_its_verdict
  _hi_check "pending_answer reads this run's answers" test_pending_answer_reads_this_runs_answers
  _hi_check "_hi_pending_set replaces in place" test_pending_set_replaces_in_place

  _hi_h2 "Testing: ensure_settings_shebang"
  _hi_check "Written to a new settings.sh" test_shebang_is_written_to_a_new_settings_file
  _hi_check "Stays first under the settings block" test_shebang_stays_first_under_the_settings_block
  _hi_check "Not duplicated on reruns" test_shebang_is_not_duplicated_on_reruns
  _hi_check "Replaces a different shebang" test_shebang_replaces_a_different_one_and_keeps_content
  _hi_check_capable mode_bits "Preserves settings.sh's mode" test_settings_shebang_preserves_mode

  _hi_h2 "Testing: config_settings"
  _hi_check "Writes every group at once" test_config_settings_writes_every_group_at_once
  _hi_check "Written outside the tree" test_settings_are_written_outside_the_tree

  _hi_h2 "Testing: _hi_setting_get sources the file for real"
  _hi_check "Reads the marker-padded line config_shell writes" test_setting_get_reads_marker_padded_line
  _hi_check "Reads a computed value" test_setting_get_reads_a_computed_value
  _hi_check "Reads a two-statement assignment" test_setting_get_reads_a_two_statement_assignment
  _hi_check "Leaves other variables ambient" test_setting_get_leaves_other_variables_ambient

  _hi_suite_end "configure.sh logic"
}

# The pty part's readers (configure_pty).

# _hi_pty_field <label> <tag> [capture] - the field after <tag> on
# a pty transcript's tail line, CR-normalised first (a pty writes CR-LF) -
# everything to the end of the line by default, or just what <capture>
# matches (a sed bracket expression body) when the tag's value can have
# trailing text of its own. The one shape behind _hi_cfg_rc and
# _hi_cfg_lines. The child also writes that line to
# <label>/verdict, which is read first: a BSD pty can drop the last output of
# a child that exits at once, and the transcript is only the fallback.
function _hi_pty_field() {
  local src="$_HI_WORKDIR/$1/verdict"
  [ -s "$src" ] || src="$_HI_WORKDIR/$1.cfg.out"
  tr '\r' '\n' <"$src" | sed -n "s/.*$2\\(${3:-.*}\\).*/\\1/p" | head -1
}

# _hi_cfg_pty <label> <input> <settings-line> <fn> [arg...] - one configure
# function under a forced pty with <input> (printf %b) on its stdin and a
# scratch settings.sh. Transcript lands in $_HI_WORKDIR/<label>.cfg.out; killed
# and non-zero once it has written nothing for the deadline.
function _hi_cfg_pty() {
  local label="$1" input="$2" line="${3:-}"
  local dir="$_HI_WORKDIR/$label" out="$_HI_WORKDIR/$label.cfg.out"
  shift 3
  mkdir -p "$dir/common" "$dir/config" "$dir/overlay"
  printf '#!/bin/sh\n%s\n' "$line" >"$dir/overlay/settings.sh"
  : >"$out"
  rm -f "$dir/verdict"
  printf '%b' "$input" |
    "${_HI_PTY_FORCED[@]}" bash -c "$_HI_CFG_CHILD" bash "$dir" "$@" >"$out" 2>&1 &
  _hi_wait_quiet "$!" "${_HI_CASE_TIMEOUT:-60}" "$out" "$label"
  [ "$_HI_WAIT_EXIT" != 124 ]
}

# the readers: the transcript's visible text for substrings (fixed strings
# only - a pty writes CR-LF, so nothing here anchors a line; the menu paints
# inside a row, so its escapes come out first), the tail line's fields
# through the same CR normalisation the groups loop's readers use
function _hi_cfg_has() { _hi_strip_ansi "$(<"$_HI_WORKDIR/$1.cfg.out")" | grep -qF "$2"; }

function _hi_cfg_rc() { _hi_pty_field "$1" 'CFGRC=' '[0-9]*'; }

function _hi_cfg_lines() { _hi_pty_field "$1" 'CFGLINES='; }

# a part (configure_*_test.sh) sources this file for what is above and runs its own
[ -n "${_HI_CONFIGURE_PART:-}" ] || run_configure_tests
