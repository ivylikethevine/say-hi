#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Unit tests for hi --configure's settings wizard - scripts/configure.sh (the
# rc.sh and table.sh helpers it shares have their own suites). This half is
# everything a plain install's second stage, or a later `hi --configure`,
# touches - every question, its validation, and the one write to
# $_HI_SETTINGS. tests/scripts/install_test.sh is the other half:
# install_tree's packaging-mode DESTDIR layout and the
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

# The prompt separators, one per shell, all of which have to survive being
# written to a file four shells source. Every case here reads what the
# collector writes for a given file (_hi_collected_lines, defined further
# down with the helpers it serves) - no tty, so nothing is asked and the file
# is the whole answer. The defaults-write-nothing direction is pinned there
# too, by test_opt_in_off_writes_nothing.

function test_prompt_ends_keeps_an_existing_override() {
  local out
  out="$(_hi_collected_lines prompt_keep "export _HI_PROMPT_END_ZSH='::'")"
  [[ "$out" == *"export _HI_PROMPT_END_ZSH='::'"* ]]
}

# quoted on the way out: a separator is as likely to be $ or > as a letter, and
# the file is sourced by sh, bash, zsh, and fish alike
function test_prompt_ends_quotes_what_it_writes() {
  local out
  out="$(_hi_collected_lines prompt_quote "export _HI_PROMPT_END_BASH='>'")"
  [[ "$out" == *"_HI_PROMPT_END_BASH='>'"* ]]
}

# the prompt is off, so what it ends with is moot right now - and kept, so
# turning the prompt back on finds the separator where it was left.
function test_prompt_ends_kept_when_the_prompt_is_off() {
  local out
  out="$(_hi_collected_lines prompt_off "export _HI_DISABLE_PROMPT=1" "export _HI_PROMPT_END_ZSH='::'")"
  [[ "$out" == *"export _HI_DISABLE_PROMPT=1"* && "$out" == *"export _HI_PROMPT_END_ZSH='::'"* ]]
}

# The wizard asks about neither the scheme nor the packages ramp -
# both are hand-written into settings.sh (GLOSSARY: HI.50). So the contract
# here is that a full run leaves whatever they hold exactly as it found it,
# quoted where it holds spaces.
function test_hand_written_colors_survive_a_run() {
  local out
  out="$(_hi_collected_lines colors_hand \
    "export _HI_PACKAGES_PALETTE='$_HI_TEST_RAMP'" "export _HI_COLOR_SCHEME='$_HI_TEST_L48'")"
  [[ "$out" == *"export _HI_PACKAGES_PALETTE='$_HI_TEST_RAMP'"* ]] &&
    [[ "$out" == *"export _HI_COLOR_SCHEME='$_HI_TEST_L48'"* ]]
}

# an unset ramp is the shipped one, so a run that was never told otherwise
# writes no line for it - the rule config_max_width and _hi_group_flip use
# for their own defaults
function test_packages_palette_does_not_write_the_default() {
  local out
  out="$(_hi_collected_lines palette_default)"
  [[ "$out" != *_HI_PACKAGES_PALETTE* ]] && [[ "$out" != *_HI_COLOR_SCHEME* ]]
}

function test_ip_hide_keeps_an_existing_override() {
  local out
  out="$(_hi_section_lines iphide_keep config_ip_hide "export _HI_IP_HIDE='none'")"
  [[ "$out" == *"export _HI_IP_HIDE='none'"* ]]
}

# 172.* is header.sh's own default, so it is never written out
function test_ip_hide_does_not_write_the_default() {
  local out
  out="$(_hi_section_lines iphide_default config_ip_hide)"
  [ -z "$(printf '%s' "$out" | tr -d ' ')" ] || return 1
  out="$(_hi_section_lines iphide_default2 config_ip_hide "export _HI_IP_HIDE='172.*'")"
  [ -z "$(printf '%s' "$out" | tr -d ' ')" ]
}

# the check itself is off, so which colors it would use is moot - the stored
# ramp is still kept for when 'check' comes back
function test_packages_palette_kept_when_the_check_is_off() {
  local out
  out="$(_hi_collected_lines palette_off \
    "export _HI_HEADER_ORDER='gitid'" "export _HI_PACKAGES_PALETTE='$_HI_TEST_RAMP'")"
  [[ "$out" == *"export _HI_HEADER_ORDER='gitid'"* ]] &&
    [[ "$out" == *"export _HI_PACKAGES_PALETTE='$_HI_TEST_RAMP'"* ]]
}

function test_header_order_keeps_an_existing_override() {
  local out
  out="$(_hi_collected_lines order_keep "export _HI_HEADER_ORDER='check gitid'")"
  [[ "$out" == *"export _HI_HEADER_ORDER='check gitid'"* ]]
}

# header.sh's own default order, so writing it out would be a line that means
# nothing - even when the file spells it out in full
function test_header_order_does_not_write_the_default() {
  local out
  _hi_load_preview_sources
  out="$(_hi_collected_lines order_default "export _HI_HEADER_ORDER='$_HI_HEADER_ORDER_DEFAULT'")"
  [ -z "$(printf '%s' "$out" | tr -d ' ')" ]
}

# the header is off, so its order is moot - and kept, like the separators
function test_header_order_kept_when_the_header_is_off() {
  local out
  out="$(_hi_collected_lines order_off "export _HI_DISABLE_HEADER=1" "export _HI_HEADER_ORDER='check gitid'")"
  [[ "$out" == *"export _HI_DISABLE_HEADER=1"* && "$out" == *"export _HI_HEADER_ORDER='check gitid'"* ]]
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
  )
}

# every header preset's word list validates, and the empty one is the
# shipped order by the same spelling $_HI_HEADER_ORDER uses for it
function test_header_presets_hold_the_vocabulary() {
  local row words word
  _hi_load_preview_sources
  for row in "${_HI_HEADER_PRESETS[@]}"; do
    words="${row##*|}"
    [ -z "$words" ] && continue
    # shellcheck disable=SC2086 # the split is the point: one word per feature
    for word in $words; do
      _hi_is_header_word "$word" || return 1
    done
  done
  [ "$(preset_names)" != "" ]
}

# The input validators guarding what ask_value will write into settings.sh -
# the single-quote one is what keeps a typed value from ending the sh word the
# written `export NAME='value'` line wraps it in.
function test_validators_hold_their_grammars() {
  _hi_is_number 42 || return 1
  ! _hi_is_number 4.2 || return 1
  _hi_is_width 80 || return 1
  _hi_is_width 40 || return 1
  ! _hi_is_width 39 || return 1
  ! _hi_is_width 0 || return 1
  ! _hi_is_number '' || return 1
  ! _hi_is_number 4x || return 1
  _hi_has_no_single_quote "plain value" || return 1
  ! _hi_has_no_single_quote "don't" || return 1
  _hi_is_ip_hide none || return 1
  _hi_is_ip_hide '172.*' || return 1
  _hi_is_ip_hide '10.* 192.168.?.*' || return 1
  ! _hi_is_ip_hide "" || return 1
  ! _hi_is_ip_hide "172.*;rm" || return 1
  ! _hi_is_ip_hide "all" || return 1
  _hi_is_package_groups none || return 1
  _hi_is_package_groups 'core useful' || return 1
  _hi_is_package_groups 'core,my-tools.2' || return 1
  ! _hi_is_package_groups "" || return 1
  ! _hi_is_package_groups 'core;rm' || return 1
  ! _hi_is_package_groups "[core]" || return 1
  _hi_is_header_word utc || return 1
  _hi_is_header_word check || return 1
  ! _hi_is_header_word bogus || return 1
  ! _hi_is_header_word ""
}

function test_pending_answer_reads_this_runs_answers() {
  (
    _HI_SETTING_PENDING=("_HI_A=1" "_HI_B=two words")
    [ "$(pending_answer _HI_A)" = 1 ] &&
      [ "$(pending_answer _HI_B)" = "two words" ] &&
      ! pending_answer _HI_C
  )
}

# non-interactive ask_value never prompts: it keeps the current value, and an
# answer equal to the default comes back empty - "write nothing, the default
# applies" is the contract the settings writer relies on
function test_ask_value_non_interactive_keeps_current() {
  [ "$(ask_value "width?" 100 80 _hi_is_number "not a number" </dev/null)" = 100 ] || return 1
  [ -z "$(ask_value "width?" "" 80 _hi_is_number "not a number" </dev/null)" ] || return 1
  [ -z "$(ask_value "width?" 80 80 _hi_is_number "not a number" </dev/null)" ]
}

# settings.sh is sourced by sh, bash, zsh, and fish, so line 1 has to be the
# `#!/bin/sh` all four read as a comment - and has to stay line 1 once
# config_shell has written the settings block under it.
function _hi_shebang_fresh() { ensure_settings_shebang; }

function test_shebang_is_written_to_a_new_settings_file() {
  _hi_settings_fixture shebang_new _hi_shebang_fresh
  [ "$(head -n 1 "$(_hi_fixture_settings shebang_new)")" = "#!/bin/sh" ]
}

function _hi_shebang_then_settings() {
  ensure_settings_shebang
  config_shell settings "$_HI_SETTINGS" "export _HI_DISABLE_PROMPT=1"
}

function test_shebang_stays_first_under_the_settings_block() {
  _hi_settings_fixture shebang_block _hi_shebang_then_settings
  local f
  f="$(_hi_fixture_settings shebang_block)"
  [ "$(head -n 1 "$f")" = "#!/bin/sh" ] && grep -qF "export _HI_DISABLE_PROMPT=1" "$f"
}

# re-running must not stack a second shebang
function _hi_shebang_twice() {
  ensure_settings_shebang
  ensure_settings_shebang
}

function test_shebang_is_not_duplicated_on_reruns() {
  _hi_settings_fixture shebang_twice _hi_shebang_twice
  [ "$(grep -c '^#!' "$(_hi_fixture_settings shebang_twice)")" -eq 1 ]
}

# a hand-edited shebang for the wrong shell is replaced, not left alongside:
# dash and fish both source this file, so sh is the only correct one
function _hi_shebang_wrong() {
  mkdir -p "$_HI_CONFIG_DIR"
  printf '%s\n%s\n' '#!/bin/bash' 'export _HI_MAX_WIDTH=120' >"$_HI_SETTINGS"
  ensure_settings_shebang
}

function test_shebang_replaces_a_different_one_and_keeps_content() {
  _hi_settings_fixture shebang_wrong _hi_shebang_wrong
  local f
  f="$(_hi_fixture_settings shebang_wrong)"
  [ "$(head -n 1 "$f")" = "#!/bin/sh" ] &&
    [ "$(grep -c '^#!' "$f")" -eq 1 ] &&
    grep -qF "export _HI_MAX_WIDTH=120" "$f"
}

# _hi_groups_flipped <stored value> <group...> - the lines a run writes after
# _hi_group_flip flips each <group> in turn over a settings.sh holding
# <stored value>, as the Package check page's numbers do
function _hi_groups_flipped() {
  local g dir line="" _HI_SETTINGS _HI_MENU_NOTE=""
  local -a _HI_SETTING_LINES=() _HI_SETTING_PENDING=()
  dir="$(mktemp -d "$_HI_WORKDIR/groupsflip.XXXXXX")" || return 1
  _HI_SETTINGS="$dir/settings.sh"
  [ -z "$1" ] || line="export _HI_PACKAGES_GROUPS='$1'"
  printf '#!/bin/sh\n%s\n' "$line" >"$_HI_SETTINGS"
  shift
  for g; do _hi_group_flip "$g"; done
  collect_setting_lines
  printf '%s\n' ${_HI_SETTING_LINES[@]+"${_HI_SETTING_LINES[@]}"}
}

# a group that is off goes on after the ones that run, and one that runs off
function test_packages_groups_flip_one() {
  [ "$(_hi_groups_flipped '' extras)" = "export _HI_PACKAGES_GROUPS='core useful deprecated extras'" ] || return 1
  [ "$(_hi_groups_flipped '' useful)" = "export _HI_PACKAGES_GROUPS='core deprecated'" ]
}

# a comma-separated value is read as a list and written back space-separated
function test_packages_groups_normalises_commas() {
  [ "$(_hi_groups_flipped 'core,extras' useful)" = "export _HI_PACKAGES_GROUPS='core extras useful'" ]
}

# the shipped set is header.sh's own default, so writing it out would be a
# line that means nothing - in any order, the same rule config_max_width has
# for 80
function test_packages_groups_does_not_write_the_default() {
  [ -z "$(_hi_groups_flipped 'useful deprecated' core | tr -d '[:space:]')" ]
}

# ...and the other side of that rule: no group at all is an answer, spelled
# `none`, not an empty value that would read as the default - and one flipped
# on from there is the whole list
function test_packages_groups_writes_none() {
  [ "$(_hi_groups_flipped '' core useful deprecated)" = "export _HI_PACKAGES_GROUPS='none'" ] || return 1
  [ "$(_hi_groups_flipped none core)" = "export _HI_PACKAGES_GROUPS='core'" ]
}

# the check is off, so which groups it runs is moot - the stored value is kept
# for when 'check' comes back
function test_packages_groups_kept_when_the_check_is_off() {
  local out
  out="$(_hi_collected_lines groups_off "export _HI_HEADER_ORDER='gitid'" "export _HI_PACKAGES_GROUPS='core'")"
  [[ "$out" == *"export _HI_HEADER_ORDER='gitid'"* && "$out" == *"export _HI_PACKAGES_GROUPS='core'"* ]]
}

# _hi_pty_run <child-script> <suffix> <label> <input> <line> [args...] - the
# pty rig _hi_cfg_pty runs: a scratch settings.sh, the
# input typed at a forced pty, the transcript captured to
# $_HI_WORKDIR/<label>.<suffix>.out, timed out rather than hung forever.
function _hi_pty_run() {
  local child="$1" suffix="$2" label="$3" input="$4" line="${5:-}"
  local dir="$_HI_WORKDIR/$label" out="$_HI_WORKDIR/$label.$suffix.out"
  shift 5
  mkdir -p "$dir/common" "$dir/config" "$dir/overlay"
  printf '#!/bin/sh\n%s\n' "$line" >"$dir/overlay/settings.sh"
  : >"$out"
  rm -f "$dir/verdict"
  printf '%b' "$input" |
    "${_HI_PTY_FORCED[@]}" bash -c "$child" bash "$dir" "$@" >"$out" 2>&1 &
  _hi_wait_pid "$!" "${_HI_CASE_TIMEOUT:-60}" _hi_timed_out "$label" "${_HI_CASE_TIMEOUT:-60}"
  [ "$_HI_WAIT_EXIT" != 124 ]
}

# _hi_pty_field <label> <suffix> <tag> [capture] - the field after <tag> on
# a pty transcript's tail line, CR-normalised first (a pty writes CR-LF) -
# everything to the end of the line by default, or just what <capture>
# matches (a sed bracket expression body) when the tag's value can have
# trailing text of its own. The one shape behind _hi_cfg_rc and
# _hi_cfg_lines. The child also writes that line to
# <label>/verdict, which is read first: a BSD pty can drop the last output of
# a child that exits at once, and the transcript is only the fallback.
function _hi_pty_field() {
  local src="$_HI_WORKDIR/$1/verdict"
  [ -s "$src" ] || src="$_HI_WORKDIR/$1.$2.out"
  tr '\r' '\n' <"$src" | sed -n "s/.*$3\\(${4:-.*}\\).*/\\1/p" | head -1
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
  mkdir -p "$_HI_CONFIG_DIR"
  printf 'X=1\n' >"$_HI_SETTINGS"
  chmod 604 "$_HI_SETTINGS"
  _hi_mode_string "$_HI_SETTINGS" >"$_HI_WORKDIR/shebang_mode.before"
  ensure_settings_shebang
}

function test_settings_shebang_preserves_mode() {
  _hi_settings_fixture shebang_mode _hi_shebang_mode
  [ "$(_hi_mode_string "$(_hi_fixture_settings shebang_mode)")" = "$(cat "$_HI_WORKDIR/shebang_mode.before")" ]
}

# the three config_* groups accumulate rather than each calling config_shell,
# because one config_shell call per group against one file would have each
# wipe the other two's lines
function _hi_settings_one_write() {
  local -a _HI_SETTING_LINES=("export _HI_DISABLE_PROMPT=1" "" "export _HI_DISABLE_BANNER=1")
  mkdir -p "$_HI_CONFIG_DIR"
  config_shell settings "$_HI_SETTINGS" "${_HI_SETTING_LINES[@]}"
}

function test_config_settings_writes_every_group_at_once() {
  _hi_settings_fixture onewrite _hi_settings_one_write
  local f
  f="$(_hi_fixture_settings onewrite)"
  grep -qF "export _HI_DISABLE_PROMPT=1" "$f" && grep -qF "export _HI_DISABLE_BANNER=1" "$f"
}

# the whole point of the overlay: a fresh install leaves the tree untouched, so
# `hi --update`'s tag checkout still applies and a root-owned tree still works
function test_settings_are_written_outside_the_tree() {
  _hi_settings_fixture outside _hi_shebang_fresh
  [ -f "$(_hi_fixture_settings outside)" ] && [ ! -e "$_HI_WORKDIR/outside/config/settings.sh" ]
}

# this run's answer wins over the file, which still holds the previous run's
function test_setting_off_sees_this_runs_answer() {
  local target="$_HI_WORKDIR/pending"
  : >"$target"
  local _HI_SETTING_PENDING=("_HI_DISABLE_HEADER=1")
  setting_off _HI_DISABLE_HEADER "$target" 1 &&
    ! setting_off _HI_DISABLE_PROMPT "$target" 1
}

function test_setting_off_false_when_absent() {
  local target="$_HI_WORKDIR/absent"
  : >"$target"
  ! setting_off _HI_DISABLE_FOO "$target"
}

function test_setting_off_true_when_off_present() {
  local target="$_HI_WORKDIR/off"
  printf 'export _HI_DISABLE_FOO=1\n' >"$target"
  setting_off _HI_DISABLE_FOO "$target"
}

function test_setting_off_respects_custom_off_value() {
  local target="$_HI_WORKDIR/customoff"
  printf 'export _HI_DISABLE_BANNER=1\n' >"$target"
  setting_off _HI_DISABLE_BANNER "$target" 1
}

# the line as config_shell really writes it: marker-padded, unquoted - the
# exact spelling hi.sh's payload trim has to read correctly
function test_setting_off_reads_marker_padded_line() {
  local target="$_HI_WORKDIR/padded"
  printf '%-45s %s\n' 'export _HI_DISABLE_FOO=1' "$_HI_MARKER" >"$target"
  setting_off _HI_DISABLE_FOO "$target" &&
    [ "$(_hi_setting_get "$target" _HI_DISABLE_FOO)" = 1 ]
}

# _hi_setting_get sources the file for real rather than hand-scanning
# `export NAME=value` text: a computed value real bash would honour reads the
# same way here, exactly as a settings.sh sourced on a target would resolve it.
function test_setting_get_reads_a_computed_value() {
  local target="$_HI_WORKDIR/computed"
  # shellcheck disable=SC2016 # the file's own text, for it to expand when sourced - not ours to expand now
  printf 'export _HI_DISABLE_FOO=$((1))\n' >"$target"
  [ "$(_hi_setting_get "$target" _HI_DISABLE_FOO)" = 1 ]
}

# ...and a two-statement assignment, which a bare `export NAME=` line-start
# check would never match
function test_setting_get_reads_a_two_statement_assignment() {
  local target="$_HI_WORKDIR/twostatement"
  printf '_HI_DISABLE_FOO=1\nexport _HI_DISABLE_FOO\n' >"$target"
  [ "$(_hi_setting_get "$target" _HI_DISABLE_FOO)" = 1 ]
}

# a settings.sh that references another real variable ($_HI_CONFIG_DIR, say)
# still resolves normally - only the queried name is unset going in
function test_setting_get_leaves_other_variables_ambient() {
  local target="$_HI_WORKDIR/ambient"
  # shellcheck disable=SC2016 # the file's own text, for it to expand when sourced - not ours to expand now
  printf 'export _HI_DISABLE_FOO="$_HI_CONFIG_DIR/marker"\n' >"$target"
  [ "$(_HI_CONFIG_DIR=/probe-dir _hi_setting_get "$target" _HI_DISABLE_FOO)" = /probe-dir/marker ]
}

#
# A default-on toggle is on unless its off-value is written; an opt-in
# (_HI_DISABLE_LEAD_SPACE=1) is on only when its on-value is. setting_on is the one reader of both, and _hi_setting_flip
# writes both.

function test_setting_on_opt_in_absent_is_off() {
  local target="$_HI_WORKDIR/opt_in_absent"
  : >"$target"
  _HI_SETTING_PENDING=()
  ! setting_on _HI_DISABLE_LEAD_SPACE "$target" 0 1
}

function test_setting_on_opt_in_present_is_on() {
  local target="$_HI_WORKDIR/opt_in_present"
  printf 'export _HI_DISABLE_LEAD_SPACE=1\n' >"$target"
  _HI_SETTING_PENDING=()
  setting_on _HI_DISABLE_LEAD_SPACE "$target" 0 1
}

function test_setting_on_toggle_absent_is_on() {
  local target="$_HI_WORKDIR/toggle_absent"
  : >"$target"
  _HI_SETTING_PENDING=()
  setting_on _HI_DISABLE_FOO "$target" 1
}

# _hi_section_lines <name> <fn> [settings-line ...] - what the run would
# write after <fn>, non-interactively (stdin is /dev/null, so every question
# keeps what the file holds), as one string: the section's answers land in
# pending, and the collector turns pending plus the file into lines
function _hi_section_lines() {
  local dir="$_HI_WORKDIR/section_$1" fn="$2"
  local _HI_SETTINGS="$dir/settings.sh"
  local -a _HI_SETTING_LINES=()
  _HI_SETTING_PENDING=()
  mkdir -p "$dir"
  shift 2
  [ "$#" -eq 0 ] && : >"$_HI_SETTINGS" || printf '%s\n' "$@" >"$_HI_SETTINGS"
  "$fn" </dev/null >/dev/null
  collect_setting_lines
  printf '%s' "${_HI_SETTING_LINES[*]:-}"
}

# _hi_collected_lines <name> [settings-line ...] - the same with no section
# at all: what the collector writes for a file as it stands
function _hi_collected_lines() {
  local name="$1"
  shift
  _hi_section_lines "$name" : "$@"
}

# an opt-in that is off writes nothing - there is no "=0" spelling of it, and
# the shipped defaults are core.sh's own, so writing them out would be noise
# that then has to be kept in sync - the same rule config_max_width has for 80
function test_opt_in_off_writes_nothing() {
  [ -z "$(_hi_collected_lines prompt_default | tr -d ' ')" ]
}

function test_hi_prompt_kept_when_chosen() {
  local out
  out="$(_hi_collected_lines hiprompt "export _HI_PROMPT_TOOL=hi")"
  [[ "$out" == *"export _HI_PROMPT_TOOL=hi"* ]] || return 1
  out="$(_hi_collected_lines hiprompt2 "export _HI_PROMPT_TOOL='bash:starship hi'")"
  [[ "$out" == *"export _HI_PROMPT_TOOL='bash:starship hi'"* ]]
}

# the truecolor question with nobody to answer keeps what the file holds,
# and the collector carries the leading space beside it
function test_advanced_declined_keeps_every_value() {
  local out
  out="$(_hi_section_lines adv_keep config_truecolor \
    "export _HI_DISABLE_LEAD_SPACE=1" "export _HI_TRUECOLOR=0")"
  [[ "$out" == *"export _HI_DISABLE_LEAD_SPACE=1"* &&
    "$out" == *"export _HI_TRUECOLOR=0"* ]]
}

# and with nothing set, writes nothing - the defaults live in the code
function test_advanced_defaults_write_nothing() {
  [ -z "$(_hi_section_lines adv_default config_truecolor | tr -d ' ')" ]
}

# _hi_run_in <name> [settings-line ...] - run_configure with no tty against a
# scratch settings.sh (absent when no line is given), the rc files pointed
# at nothing so no prompt framework of this machine's is found. Prints the
# file afterwards, or nothing when there is none.
function _hi_run_in() {
  local dir="$_HI_WORKDIR/run_$1"
  local _HI_SETTINGS="$dir/settings.sh"
  local _HI_HOME_BASHRC="$dir/none" _HI_HOME_ZSHRC="$dir/none" _HI_HOME_FISH_CONFIG="$dir/none"
  local -a _HI_SETTING_LINES=()
  _HI_SETTING_PENDING=()
  _HI_CONFIGURE_QUIT=""
  mkdir -p "$dir"
  shift
  [ "$#" -eq 0 ] || printf '#!/bin/sh\n%s\n' "$*" >"$_HI_SETTINGS"
  run_configure "" </dev/null >/dev/null || return 1
  [ -f "$_HI_SETTINGS" ] && cat "$_HI_SETTINGS"
  return 0
}

# a line written by hand - the way SETTINGS.md says to set a scheme of your
# own - is adopted into the block rather than written again beside itself
function test_configure_adopts_a_hand_written_line() {
  local out
  out="$(_hi_run_in adopt "export _HI_COLOR_SCHEME='$_HI_TEST_L24'")" || return 1
  [ "$(printf '%s\n' "$out" | grep -c _HI_COLOR_SCHEME)" -eq 1 ] &&
    [[ "$(printf '%s\n' "$out" | grep _HI_COLOR_SCHEME)" == *"$_HI_TEST_L24"*"$_HI_MARKER" ]]
}

# ...and a hand line for a name this run does not write is left as it is
function test_configure_leaves_a_hand_line_it_does_not_write() {
  local out
  out="$(_hi_run_in keephand "export _HI_MY_OWN_LINE='>'")" || return 1
  [ "$(printf '%s\n' "$out" | grep -c _HI_MY_OWN_LINE)" -eq 1 ] &&
    [[ "$(printf '%s\n' "$out" | grep _HI_MY_OWN_LINE)" != *"$_HI_MARKER"* ]]
}

# no tty, no preset, no file, and nothing to say: no file - a shebang alone
# would be a decision record with no decision in it, and its existence is
# what stops the one-shot prompt-framework detection asking again
function test_no_tty_run_with_defaults_writes_no_file() {
  [ -z "$(_hi_run_in notty)" ] && [ ! -e "$_HI_WORKDIR/run_notty/settings.sh" ]
}

# a preset is a decision, so that run creates the file
function test_preset_run_still_creates_the_file() {
  local dir="$_HI_WORKDIR/run_preset"
  local _HI_SETTINGS="$dir/settings.sh"
  local _HI_HOME_BASHRC="$dir/none" _HI_HOME_ZSHRC="$dir/none" _HI_HOME_FISH_CONFIG="$dir/none"
  local -a _HI_SETTING_LINES=()
  _HI_SETTING_PENDING=()
  mkdir -p "$dir"
  run_configure balanced </dev/null >/dev/null || return 1
  grep -qF "_HI_PACKAGES_GROUPS='core,deprecated'" "$_HI_SETTINGS"
}

function test_validators_for_the_advanced_values() {
  _hi_is_truecolor_choice on && _hi_is_truecolor_choice auto && ! _hi_is_truecolor_choice 1
}

# the closing report: what this run wrote against what the block held, as
# +/- lines, read through config_shell's own marker padding
function _hi_diff_run() {
  local -a _HI_SETTING_LINES=("export _HI_DISABLE_PROMPT=1" "export _HI_MAX_WIDTH=120")
  mkdir -p "$_HI_CONFIG_DIR"
  config_shell settings "$_HI_SETTINGS" "export _HI_DISABLE_PROMPT=1" "export _HI_DISABLE_BANNER=1"
  settings_diff_before
  settings_diff_report >"$_HI_CONFIG_DIR/diff.out"
}

function test_settings_diff_reports_added_and_removed() {
  local out
  _hi_settings_fixture diff _hi_diff_run
  out="$(cat "$_HI_WORKDIR/diff/overlay/diff.out")"
  [[ "$out" == *"+ export _HI_MAX_WIDTH=120"* && "$out" == *"- export _HI_DISABLE_BANNER=1"* &&
    "$out" != *"_HI_DISABLE_PROMPT"* ]]
}

function _hi_diff_same_run() {
  local -a _HI_SETTING_LINES=("export _HI_DISABLE_PROMPT=1")
  mkdir -p "$_HI_CONFIG_DIR"
  config_shell settings "$_HI_SETTINGS" "export _HI_DISABLE_PROMPT=1"
  settings_diff_before
  settings_diff_report >"$_HI_CONFIG_DIR/diff.out"
}

function test_settings_diff_says_no_changes() {
  _hi_settings_fixture diff_same _hi_diff_same_run
  grep -q 'no changes' "$_HI_WORKDIR/diff_same/overlay/diff.out"
}

#
# A preset is an absolute answer over its vocabulary: what it names is set,
# everything else in the vocabulary goes back to the default, and nothing
# outside it (width, separators, the advanced section) is touched.

function test_apply_preset_seeds_every_answer() {
  local target="$_HI_WORKDIR/preset_seed"
  printf 'export _HI_DISABLE_PROMPT=1\nexport _HI_MAX_WIDTH=120\n' >"$target"
  _HI_SETTING_PENDING=()
  apply_preset minimal >/dev/null || return 1
  # named by the preset: off; not named: back to on, even though the file
  # says off; outside the vocabulary: still the file's
  setting_off _HI_DISABLE_HEADER "$target" 1 &&
    ! setting_off _HI_DISABLE_PROMPT "$target" 1 &&
    [ "$(setting_value _HI_MAX_WIDTH "$target")" = 120 ]
}

function test_apply_preset_rejects_a_stranger() {
  _HI_SETTING_PENDING=()
  ! apply_preset no-such-preset 2>/dev/null
}

# preset_shorthand is what config_preset's typed reply goes through before
# reaching apply_preset - unit-tested directly rather than through the prompt
# loop it feeds, on the same precedent as apply_preset above: config_preset
# is `[ -t 0 ]`-gated, and the resolution it does has nothing to do with a tty.
function test_preset_shorthand_resolves_each_first_letter() {
  [ "$(preset_shorthand e)" = "everything" ] &&
    [ "$(preset_shorthand b)" = "balanced" ] &&
    [ "$(preset_shorthand m)" = "minimal" ]
}

# the header presets go through the same two helpers as the main ones, so
# they get the ambiguity guard and the exact-name-first order: two presets
# sharing a letter must refuse, and an exact name must beat a later prefix.
function test_preset_shorthand_is_table_agnostic_and_refuses_ambiguity() {
  local -a _HI_TEST_PRESETS=("alpha|first|a b" "apex|second|c d" "zulu|third|e f")
  # unambiguous letter and exact name both resolve
  [ "$(preset_shorthand z _HI_TEST_PRESETS)" = zulu ] || return 1
  [ "$(preset_row apex _HI_TEST_PRESETS)" = "apex|second|c d" ] || return 1
  # two names share "a", so the letter is refused rather than guessed
  ! preset_shorthand a _HI_TEST_PRESETS 2>/dev/null || return 1
  # and the real header table still answers through the same helpers
  [ -n "$(preset_names _HI_HEADER_PRESETS)" ]
}

function test_preset_shorthand_rejects_unknown_letter() {
  ! preset_shorthand z 2>/dev/null
}

function test_preset_shorthand_rejects_multiple_characters() {
  ! preset_shorthand ev 2>/dev/null
}

# ...or a setting outside it, as lean names _HI_PROMPT_TOOL and
# _HI_BACKENDS_OFF: a row of scripts/settings, never an invented name
function test_every_preset_names_only_vocabulary() {
  local row values pair vocab settings
  vocab="$(_hi_preset_vocab)"
  settings="$(sed -n 's/^[a-z]* | \(_HI_[A-Z0-9_]*\) |.*/\1/p' "$_HI_ROOT/scripts/settings")"
  # shellcheck disable=SC2153 # _HI_PRESETS is configure.sh's table, not a typo of --preset's var
  for row in "${_HI_PRESETS[@]}"; do
    values="${row##*|}"
    for pair in $values; do
      case "$vocab" in *"${pair%%=*}"*) continue ;; esac
      case $'\n'"$settings"$'\n' in *$'\n'"${pair%%=*}"$'\n'*) ;; *) return 1 ;; esac
    done
  done
}

# _HI_PACKAGES_PALETTE and _HI_HEADER_ORDER stay out of the vocabulary on
# purpose, on the same reasoning _HI_MAX_WIDTH and the prompt separators
# already follow: a preset is an absolute answer for every var it names, so
# either one joining the vocabulary would make every preset silently reset it
function test_preset_vocab_excludes_palette_and_order() {
  local vocab
  vocab="$(_hi_preset_vocab)"
  ! grep -qx _HI_PACKAGES_PALETTE <<<"$vocab" &&
    ! grep -qx _HI_HEADER_ORDER <<<"$vocab" &&
    ! grep -qx _HI_COLOR_SCHEME <<<"$vocab" &&
    ! grep -qx _HI_IP_HIDE <<<"$vocab" &&
    ! grep -qx _HI_PROMPT_TOOL <<<"$vocab"
}

# the whole run with --preset, no tty: exactly the preset's lines land in the
# block, a value outside the vocabulary survives, and one inside it that the
# preset does not name is gone. The fixture is written through config_shell,
# so the before-state is the marked block a real run would find.
function _hi_preset_run() {
  mkdir -p "$_HI_CONFIG_DIR"
  config_shell settings "$_HI_SETTINGS" "export _HI_PLUGINS_OFF='editors'" "export _HI_MAX_WIDTH=120"
  _HI_SETTING_LINES=()
  _HI_SETTING_PENDING=()
  run_configure balanced </dev/null
}

function test_preset_run_writes_the_preset() {
  local block
  _hi_settings_fixture preset_run _hi_preset_run
  block="$(grep -F "$_HI_MARKER" "$(_hi_fixture_settings preset_run)")"
  [[ "$block" == *"export _HI_PACKAGES_GROUPS='core,deprecated'"* &&
    "$block" == *"export _HI_MAX_WIDTH=120"* && "$block" != *"_HI_PLUGINS_OFF"* ]]
}

# lean names two variables outside the vocabulary: they are written with the
# rest, and a later preset that does not name them leaves them be
function _hi_preset_lean_run() {
  mkdir -p "$_HI_CONFIG_DIR"
  _HI_SETTING_LINES=()
  _HI_SETTING_PENDING=()
  run_configure lean </dev/null || return 1
  _HI_SETTING_LINES=()
  _HI_SETTING_PENDING=()
  cp "$_HI_SETTINGS" "$_HI_SETTINGS.lean"
  run_configure everything </dev/null
}

function test_preset_lean_sets_what_no_other_resets() {
  local f lean block
  _hi_settings_fixture preset_lean _hi_preset_lean_run
  f="$(_hi_fixture_settings preset_lean)"
  lean="$(grep -F "$_HI_MARKER" "$f.lean")"
  block="$(grep -F "$_HI_MARKER" "$f")"
  [[ "$lean" == *"export _HI_PLUGINS_OFF='editors,cli,mux,shell,prompt'"* &&
    "$lean" == *"export _HI_PROMPT_TOOL=hi"* && "$lean" == *"export _HI_BACKENDS_OFF='all'"* ]] &&
    [[ "$block" != *"_HI_PLUGINS_OFF"* && "$block" == *"export _HI_PROMPT_TOOL=hi"* &&
      "$block" == *"export _HI_BACKENDS_OFF='all'"* ]]
}

function test_install_rejects_an_unknown_preset() {
  ! bash "$_HI_INSTALL" --configure --preset nope </dev/null >/dev/null 2>&1
}

function test_config_hi_skips_when_already_linked() {
  local link="$_HI_WORKDIR/already-linked"
  ln -sfn "$_HI_LAUNCHER" "$link"
  (
    _HI_LINK="$link"
    config_hi
  ) | grep -q "already points at"
}

# A packaged tree is root-owned and hi.sh already has its mode from the
# packager. An unconditional `chmod +x` there aborts the whole run under
# `set -e`, so a user could not configure a perfectly good install.
#
# chmod is stubbed rather than the file made genuinely unwritable: the owner of
# a file can always chmod it whatever its mode, so short of running as another
# user this is the only way to reach the failure from a test.
function test_config_hi_survives_an_unwritable_launcher() {
  local dir="$_HI_WORKDIR/rootowned" link="$_HI_WORKDIR/rootowned-link"
  mkdir -p "$dir"
  printf '#!/bin/bash\n' >"$dir/hi.sh"
  ln -sfn "$dir/hi.sh" "$link"
  (
    function chmod() { return 1; }
    _HI_LAUNCHER="$dir/hi.sh"
    _HI_LINK="$link"
    config_hi
  ) | grep -q "couldn't make"
}

# the packaged case proper: hi.sh arrives executable, so no chmod is attempted
# at all and the run carries on to the link check
function test_config_hi_skips_chmod_when_already_executable() {
  local dir="$_HI_WORKDIR/preexec" link="$_HI_WORKDIR/preexec-link"
  mkdir -p "$dir"
  printf '#!/bin/bash\n' >"$dir/hi.sh"
  chmod 555 "$dir/hi.sh"
  ln -sfn "$dir/hi.sh" "$link"
  local out
  out="$(
    function chmod() { echo "CHMOD RAN"; }
    _HI_LAUNCHER="$dir/hi.sh"
    _HI_LINK="$link"
    config_hi
  )"
  [[ "$out" == *"already points at"* && "$out" != *"CHMOD RAN"* ]]
}

# a writable bindir needs no sudo at all - root installs, userland prefixes
function test_config_hi_links_plainly_when_bindir_is_writable() {
  local dir="$_HI_WORKDIR/writablebin"
  mkdir -p "$dir/bin"
  printf '#!/bin/bash\n' >"$dir/hi.sh"
  chmod 755 "$dir/hi.sh"
  (
    function sudo() {
      echo "SUDO RAN"
      return 1
    }
    _HI_LAUNCHER="$dir/hi.sh"
    _HI_LINK="$dir/bin/hi"
    config_hi
  ) >/dev/null
  [ "$(readlink "$dir/bin/hi")" = "$dir/hi.sh" ]
}

# config_hi's own lockout degradation (both the refused-sudo and the
# no-sudo-at-all shape of it) is tests/scripts/install_test.sh's to assert -
# link_hi_by_hand is the one function behind both, and that suite's
# "Instructs when sudo is refused"/"Instructs with no sudo at all" check that
# output, down to the fixture.
#
# The live previews, called straight rather than through show_preview: each is
# the one line of truth its question illustrates, so what it names - the real
# user and host, the real rc paths, what bat/starship resolve to - is the
# assertion. PATH is swapped for the two that probe a command, so both of
# their arms run here whatever this machine has installed.

function test_prompt_preview_shows_this_user_and_host() {
  _hi_load_preview_sources
  local out
  out="$(_hi_strip_ansi "$(_hi_prompt_preview)")"
  [[ "$out" == *"$(_hi_whoami)@$(_hi_hostname)"* ]]
}

# The composite sample (as opposed to _hi_prompt_preview above, which is
# always live): with the colored prompt off, it says so and skips drawing one
# rather than rendering a prompt the run will not actually use.
function test_prompt_sample_preview_says_off_when_disabled() {
  _hi_load_preview_sources
  local _HI_SETTINGS="$_HI_WORKDIR/prompt-sample-off.settings.sh"
  printf 'export _HI_DISABLE_PROMPT=1\n' >"$_HI_SETTINGS"
  local out
  out="$(_hi_strip_ansi "$(_hi_prompt_sample_preview)")"
  [ "$out" = " prompt off - your shell's own" ]
}

# ...and with it on (an empty settings.sh), it draws the line: this
# user@host, ending in bash's shipped end character
function test_prompt_sample_preview_draws_the_prompt_when_on() {
  _hi_load_preview_sources
  local _HI_SETTINGS="$_HI_WORKDIR/prompt-sample-on.settings.sh"
  : >"$_HI_SETTINGS"
  local out
  out="$(_hi_strip_ansi "$(_hi_prompt_sample_preview)")"
  [[ "$out" == *"$(_hi_whoami)@$(_hi_hostname)"* && "$out" == *' $' && "$out" != *"prompt off"* ]]
}

# the sample paints with the settings file's scheme, not the running shell's,
# and leaves this shell's scheme and palette as they were
function test_prompt_sample_preview_paints_with_the_settings_scheme() {
  _hi_load_preview_sources
  local _HI_SETTINGS="$_HI_WORKDIR/prompt-sample-scheme.settings.sh" scheme="" i out before="$RED"
  for ((i = 0; i < 24; i++)); do scheme="$scheme${scheme:+ }abcdef"; done
  printf 'export _HI_COLOR_SCHEME="%s"\n' "$scheme" >"$_HI_SETTINGS"
  out="$(_HI_TRUECOLOR=1 _HI_COLOR_SCHEME='' _hi_prompt_sample_preview)"
  [[ "$out" == *"38;2;171;205;239m"* ]] || _hi_because "no scheme escape in: $(printf '%q' "$out")" || return 1
  [ "$RED" = "$before" ] || _hi_because "the palette changed: $(printf '%q' "$RED")" || return 1
  : >"$_HI_SETTINGS"
  out="$(_HI_TRUECOLOR=1 _HI_COLOR_SCHEME="$scheme" _hi_prompt_sample_preview)"
  [[ "$out" != *"38;2;171;205;239m"* ]] || _hi_because "the shell's scheme leaked in: $(printf '%q' "$out")"
}

# a menu under 60 columns has room for the cwd's last part, not its path
function test_prompt_sample_preview_shortens_the_cwd_in_a_narrow_menu() {
  _hi_load_preview_sources
  local _HI_SETTINGS="$_HI_WORKDIR/prompt-sample-narrow.settings.sh" out
  : >"$_HI_SETTINGS"
  mkdir -p "$_HI_WORKDIR/deep/er/leafdir"
  out="$(PWD="$_HI_WORKDIR/deep/er/leafdir" _HI_MENU_W=40 _hi_prompt_sample_preview)"
  out="$(_hi_strip_ansi "$out")"
  [[ "$out" == *leafdir* && "$out" != *"deep/er"* ]] || _hi_because "narrow: [$out]" || return 1
  out="$(PWD="$_HI_WORKDIR/deep/er/leafdir" _HI_MENU_W=80 _hi_prompt_sample_preview)"
  out="$(_hi_strip_ansi "$out")"
  [[ "$out" == *"er/leafdir"* ]] || _hi_because "wide: [$out]"
}

# the preview lists an editor for every config that would ride, whether or
# not this machine has the editor: the alias is a target's.
function test_editors_preview_names_every_override() {
  local out
  out="$(_hi_editors_preview)"
  [[ "$out" == *"nano  -> nano --rcfile $_HI_CONFIG_DIR/nano/nanorc"* ]] || _hi_because "nano: $out" || return 1
  [[ "$out" == *"emacs -> emacs -nw -q -l $_HI_CONFIG_DIR/emacs/init.el"* ]] || _hi_because "emacs: $out" || return 1
  [[ "$out" == *"vim   -> env XDG_STATE_HOME="*" vim -i NONE -u $_HI_CONFIG_DIR/vim/vimrc"* ]] || _hi_because "vim: $out" || return 1
  # each name carries the rc of the binary behind it: nvim answers to both
  # `vim` and `nvim` and reads init.lua, its state kept in the session tree
  [[ "$out" == *"nvim  -> env XDG_STATE_HOME="*" nvim -u $_HI_CONFIG_DIR/nvim/init.lua"* ]] || _hi_because "nvim: $out" || return 1
  [[ "$out" == *"vim   -> env XDG_STATE_HOME="*" nvim -u $_HI_CONFIG_DIR/nvim/init.lua"* ]] || _hi_because "vim as nvim: $out" || return 1
  [[ "$out" == *"hx    -> hx -c $_HI_CONFIG_DIR/helix/config.toml"* && "$out" == *"helix -> helix -c $_HI_CONFIG_DIR/helix/config.toml"* ]] || _hi_because "helix: $out" || return 1
  # micro's three files share one line
  [[ "$out" == *"micro -> micro -backup false -savehistory false -config-dir $_HI_CONFIG_DIR/micro"* ]] || _hi_because "micro: $out" || return 1
  [ "$(grep -c '^micro ' <<<"$out")" = 1 ] || _hi_because "micro, more than once: $out"
}

# the preview has no second spelling to drift out of step: its line for
# <tool> is the alias a target's shell holds once it has read the wiring.sh
# a client packs for the same configs, the last of two where a name has two.
# <tool> <member> <binary>: the alias, the config behind it, and the command
# a target has to have for the line to land.
function test_editor_preview_matches_its_alias() {
  local tool="$1" member="$2" bin="$3" from_alias from_preview path dir="$_HI_WORKDIR/preview-$1"
  mkdir -p "$dir"
  _hi_wiring_for "$member" >"$dir/wiring.sh" || return 1
  path="$(_hi_fake_path "preview-bin-$bin" "$bin"):$PATH"
  # shellcheck disable=SC2016 # the child bash expands its own script
  from_alias="$(PATH="$path" bash -c '. "$1" && alias "$2"' _ "$dir/wiring.sh" "$tool" 2>/dev/null)"
  [ -n "$from_alias" ] || {
    _hi_cecho " | no $tool alias to compare" "$RED"
    return 1
  }
  from_alias="${from_alias#alias "$tool"=\'}"
  from_alias="${from_alias%\'}"
  # the preview names the session tree as a target will, by its variable
  from_preview="$(_hi_editors_preview | sed -n "s/^$tool *-> //p" | tail -n 1)"
  from_preview="${from_preview//\$_HI_HOME/$_HI_HOME}"
  [ "$from_alias" = "$from_preview" ] || {
    _hi_cecho " | alias: [$from_alias]" "$RED"
    _hi_cecho " | preview: [$from_preview]" "$RED"
    return 1
  }
}

function test_bat_preview_names_the_bat_it_found() {
  local dir out
  dir="$(_hi_fake_path preview_bat bat)"
  # shellcheck disable=SC2031 # the swaps here live and die in their own $( )
  out="$(PATH="$dir:$PATH" _hi_tool_alias_preview)"
  [[ "$out" == "cat -> $dir/bat "* ]]
}

# an empty PATH directory, so `command -v bat` fails even where bat is real
function test_bat_preview_without_bat_says_targets_only() {
  local out
  mkdir -p "$_HI_WORKDIR/preview_none"
  out="$(hash -r && PATH="$_HI_WORKDIR/preview_none" _hi_tool_alias_preview)"
  [[ "$out" == *"bat is not installed here"* ]]
}

# eza (or exa, its predecessor) on PATH: the preview names the ls it
# aliases, each with its own options - a PATH of the fake alone, so a real
# eza further down cannot answer for an exa case
function test_eza_preview_names_the_ls_it_aliases() {
  local tool dir out
  for tool in eza exa; do
    dir="$(_hi_fake_path "preview_$tool" "$tool")"
    out="$(hash -r && PATH="$dir" _hi_tool_alias_preview)"
    [[ "$out" == *"ls -> $dir/$tool "* && "$out" != *"eza is not installed"* ]] ||
      _hi_because "with $tool: $out" || return 1
  done
}

# The environment-segment preview draws the live segment even while the
# setting is off (it previews turning it on), and a sample when nothing is
# active here, rather than a blank
_HI_CFG_ENV_ROSTER="MISE_SHELL ASDF_DIR PYENV_VERSION RBENV_VERSION NODENV_VERSION
  IN_NIX_SHELL GUIX_ENVIRONMENT DEVBOX_SHELL_ENABLED DEVENV_ROOT DIRENV_DIR
  CONDA_DEFAULT_ENV VIRTUAL_ENV VIRTUAL_ENV_PROMPT"
function test_env_status_preview_draws_the_live_segment() {
  _hi_load_preview_sources
  local out
  # shellcheck disable=SC2086 # the roster is a word list on purpose
  out="$(unset $_HI_CFG_ENV_ROSTER && export VIRTUAL_ENV_PROMPT=myproj _HI_DISABLE_ENV_STATUS=1 &&
    _hi_env_status_preview)"
  [ "$(_hi_strip_ansi "$out")" = "(myproj) " ] || _hi_because "preview: $out"
}

function test_env_status_preview_samples_with_nothing_active() {
  _hi_load_preview_sources
  local out
  # shellcheck disable=SC2086 # the roster is a word list on purpose
  out="$(unset $_HI_CFG_ENV_ROSTER && _hi_env_status_preview)"
  [ "$(_hi_strip_ansi "$out")" = "(mise|direnv:proj|myproj) " ] || _hi_because "preview: $out"
}

# the preview names what draws the prompt without the setting - hi.sh's
# list of the programs installed here, under a home with none of the
# frameworks so only the fake $PATH answers
function test_prompt_tool_preview_names_what_is_installed() {
  local dir out
  dir="$(_hi_fake_path preview_star starship)"
  mkdir -p "$_HI_WORKDIR/preview_home"
  # shellcheck disable=SC2031 # the swap lives and dies in its own $( )
  out="$(HOME="$_HI_WORKDIR/preview_home" XDG_CONFIG_HOME="$_HI_WORKDIR/preview_home" \
    PATH="$dir:$(_hi_real_path preview_tools bash sh dirname cat tr sed awk grep uname hostname)" _hi_prompt_tool_preview bash auto)"
  [[ "$out" == *"the first of these a target has, else hi's: starship"* && "$out" == *"starship"*"found here"* ]] ||
    _hi_because "preview: $out"
}

# with the prompt off there is nothing for the setting to choose between,
# and the preview says so rather than listing programs
function test_prompt_tool_preview_is_moot_with_the_prompt_off() {
  local _HI_SETTINGS="$_HI_WORKDIR/prompt-tool-off.settings.sh" out
  printf 'export _HI_DISABLE_PROMPT=1\n' >"$_HI_SETTINGS"
  out="$(_hi_prompt_tool_preview bash auto)"
  [[ "$out" == "moot while the prompt is off"* ]] || _hi_because "preview: $out"
}

function test_prompt_tool_preview_reports_none() {
  local out
  mkdir -p "$_HI_WORKDIR/preview_none" "$_HI_WORKDIR/preview_home"
  out="$(HOME="$_HI_WORKDIR/preview_home" XDG_CONFIG_HOME="$_HI_WORKDIR/preview_home" \
    PATH="$(_hi_real_path preview_tools bash sh dirname cat tr sed awk grep uname hostname):$_HI_WORKDIR/preview_none" _hi_prompt_tool_preview bash auto)"
  [[ "$out" == *"no prompt program is installed here"* ]]
}

# _hi_check_preview_at <settings line> - the Package check page's preview
# over a packages file of one group, [mine], and a settings.sh of that line
function _hi_check_preview_at() {
  local dir _HI_SETTINGS _HI_PACKAGES _HI_MENU_W=80
  local -a _HI_SETTING_PENDING=()
  dir="$(mktemp -d "$_HI_WORKDIR/checkpreview.XXXXXX")" || return 1
  _HI_SETTINGS="$dir/settings.sh" _HI_PACKAGES="$dir/packages"
  printf '[mine]\nsh = []\n' >"$_HI_PACKAGES"
  printf '#!/bin/sh\n%s\n' "$1" >"$_HI_SETTINGS"
  _hi_strip_ansi "$(_hi_check_preview)"
}

# the preview is the check at the groups this run holds
function test_check_preview_renders_the_groups_that_run() {
  _hi_load_preview_sources
  [[ "$(_hi_check_preview_at "export _HI_PACKAGES_GROUPS='mine'")" == *" sh "* ]]
}

# an empty render is a real answer - every group off, or the ones that run
# silent - and so is a header without the check item: the preview says which,
# rather than handing show_preview a blank to drop
function test_check_preview_says_when_nothing_shows() {
  _hi_load_preview_sources
  [[ "$(_hi_check_preview_at "export _HI_PACKAGES_GROUPS='none'")" == *"these groups show nothing here"* ]] || return 1
  [[ "$(_hi_check_preview_at '')" == *"these groups show nothing here"* ]] || return 1
  [[ "$(_hi_check_preview_at "export _HI_HEADER_ORDER='utc gitid'")" == *"the check item is off"* ]]
}

# _hi_plugins_grid_cells <grid> - a plugins grid's cell names, in order
function _hi_plugins_grid_cells() {
  printf '%s\n' "$1" | grep -oE '[0-9]+\) \[[x ]\] [^ ]+' | sed 's/.*\] //' | paste -sd' ' -
}

# _hi_plugins_page <width> <kept> - the Plugins page's rows at that width,
# with <kept> the list kept home
function _hi_plugins_page() {
  local dir line="" _HI_SETTINGS _HI_MENU_DRAW=1 _HI_MENU_W="$1" _HI_MENU_SUM_VALS=""
  local -a _HI_SETTING_PENDING=() _HI_MENU_ITEMS=() _HI_MENU_PLUGINS=()
  dir="$(mktemp -d "$_HI_WORKDIR/pluginspage.XXXXXX")" || return 1
  _HI_SETTINGS="$dir/settings.sh"
  [ -z "$2" ] || line="export _HI_PLUGINS_OFF='$2'"
  printf '#!/bin/sh\n%s\n' "$line" >"$_HI_SETTINGS"
  _hi_strip_ansi "$(_hi_menu_plugins)"
}

# the plugins grid: a group leads its line and its plugins wrap under the
# first of them at the menu's width, two cells a line at the narrowest, in
# _hi_plugin_states' order; a group in the list shows off, and so do its
# plugins
function test_plugins_page_wraps_at_the_menu_width() {
  local narrow wide want
  narrow="$(_hi_plugins_page 40 '')"
  wide="$(_hi_plugins_page 200 '')"
  want="$(_hi_plugin_states '' | awk -F'|' '{ print ($2 == "" ? $1 : $2) }' | paste -sd' ' -)"
  [ -n "$want" ] && [ "$(_hi_plugins_grid_cells "$narrow")" = "$want" ] &&
    [ "$(_hi_plugins_grid_cells "$wide")" = "$want" ] || _hi_because "cells: [$narrow] want [$want]" || return 1
  [ "$(printf '%s\n' "$narrow" | awk '{ n = gsub(/[0-9]+\) \[[x ]\] /, "&"); if (n > m) m = n } END { print m }')" = 2 ] &&
    [ "$(printf '%s\n' "$narrow" | wc -l)" -gt "$(printf '%s\n' "$wide" | wc -l)" ] || _hi_because "no wrap: [$narrow]" || return 1
  [[ "$wide" == *"[x] editors"* && "$wide" == *"[x] nano"* ]] || _hi_because "all on: [$wide]" || return 1
  wide="$(_hi_plugins_page 200 editors)"
  [[ "$wide" == *"[ ] editors"* && "$wide" == *"[ ] nano"* ]] || _hi_because "editors off: [$wide]"
}

# a number flips the word it stands for in the list kept home; a plugin
# switched on under a group that is kept home takes the group off the list
# and leaves the group's other plugins on it
function test_plugin_flip_edits_the_list_kept_home() {
  local dir out="" _HI_SETTINGS _HI_MENU_NOTE=""
  local -a _HI_SETTING_PENDING=()
  local -a _HI_MENU_PLUGINS=("cli||1" "cli|bat|1" "editors||0" "editors|nano|0" "editors|vim|0" "mux||0" "mux|tmux|0")
  dir="$(mktemp -d "$_HI_WORKDIR/pluginflip.XXXXXX")" || return 1
  _HI_SETTINGS="$dir/settings.sh"
  printf '#!/bin/sh\n%s\n' "export _HI_PLUGINS_OFF='editors mux'" >"$_HI_SETTINGS"
  _hi_plugin_flip nano
  _hi_plugin_flip bat
  _hi_plugin_flip mux
  setting_value _HI_PLUGINS_OFF "$_HI_SETTINGS" out
  [ "$out" = "vim bat" ] || _hi_because "the list: [$out]"
}

# with no plugin's file in the overlay or at home, the page says so and
# numbers nothing
function test_plugins_page_says_when_nothing_rides() {
  local h="$_HI_WORKDIR/plugins-none" out
  mkdir -p "$h/cfg"
  out="$(
    # the home candidates test_lib.sh leaves set
    unset RIPGREP_CONFIG_PATH FZF_DEFAULT_OPTS_FILE LG_CONFIG_FILE
    HOME="$h" XDG_CONFIG_HOME="$h/.config" _HI_XDG_CONFIG="$h/.config" _HI_CONFIG_DIR="$h/cfg" _hi_plugins_page 80 ''
  )"
  [ "$out" = " Nothing here to send - hi --plugins lists every plugin" ] || _hi_because "page: [$out]"
}

# the whole run with neither a preset nor a tty: config_preset stands down,
# every question keeps what the file holds, and the rewrite reproduces the
# block it found rather than dropping it
function _hi_no_preset_run() {
  mkdir -p "$_HI_CONFIG_DIR"
  config_shell settings "$_HI_SETTINGS" "export _HI_DISABLE_GIT_STATUS=1"
  _HI_SETTING_LINES=()
  _HI_SETTING_PENDING=()
  run_configure "" </dev/null
}

function test_run_configure_without_a_preset_keeps_the_block() {
  local block
  _hi_settings_fixture nopreset _hi_no_preset_run
  block="$(grep -F "$_HI_MARKER" "$(_hi_fixture_settings nopreset)")"
  [[ "$block" == *"export _HI_DISABLE_GIT_STATUS=1"* ]]
}

# The interactive arms proper: ask_value's typed answers, the menu,
# config_preset, and the intro are all `[ -t 0 ]`-gated, and a pty harness
# reaches them. The child points the settings at a scratch dir, runs the one
# configure function named on its argv with the pty as stdin, and reports
# the exit code, the preset-final flag, and the collected lines on one
# greppable tail line. Feeding a question an extra newline is harmless (it
# sits unread); feeding one too few hangs the child, which _hi_wait_pid turns
# into the kill this helper reports.
# shellcheck disable=SC2016 # single quotes on purpose: every expansion in here
# is the child shell's to make, after the pty has put it on the other side
_HI_CFG_CHILD='
  _hi_dir="$1"
  shift
  _hi_cfg_argv=("$@")
  source "$_HI_TEST_LIB"
  set --
  source "$_HI_INSTALL"
  _HI_ROOT="$_hi_dir"
  # the packer and the shipped plugins rows, which hi.sh reads under $_HI_ROOT
  mkdir -p "$_hi_dir/config" "$_hi_dir/scripts"
  ln -sfn "${_HI_LAUNCHER%/*}/scripts/pack.sh" "$_hi_dir/scripts/pack.sh"
  ln -sfn "${_HI_LAUNCHER%/*}/config/plugins" "$_hi_dir/config/plugins"
  # the editor rcs an overlay carries, the only ones common/aliases.sh flags
  mkdir -p "$_hi_dir/overlay"
  mkdir -p "$_hi_dir/overlay/nano"
  : >"$_hi_dir/overlay/nano/nanorc"
  _HI_CONFIG_DIR="$_hi_dir/overlay"
  _HI_SETTINGS="$_hi_dir/overlay/settings.sh"
  _HI_SETTING_LINES=()
  _HI_SETTING_PENDING=()
  # the menu belongs to hi --configure: an install-mode run_configure asks one
  # question at a terminal and never opens it
  _HI_FEATURES_ONLY=1
  _hi_cfg_rc=0
  "${_hi_cfg_argv[@]}" || _hi_cfg_rc=$?
  collect_setting_lines
  printf "CFGRC=%s CFGQUIT=%s CFGLINES=%s\n" "$_hi_cfg_rc" "${_HI_CONFIGURE_QUIT:-none}" "${_HI_SETTING_LINES[*]:-}" |
    tee "$_hi_dir/verdict"
'

# _hi_cfg_pty <label> <input> <settings-line> <fn> [arg...] - one configure
# function under a pty with <input> (printf %b) on its stdin. Transcript
# lands in $_HI_WORKDIR/<label>.cfg.out; non-zero when the child had to be
# killed at the deadline.
function _hi_cfg_pty() {
  local label="$1" input="$2" line="$3"
  shift 3
  _hi_pty_run "$_HI_CFG_CHILD" cfg "$label" "$input" "$line" "$@"
}

# the readers: the transcript's visible text for substrings (fixed strings
# only - a pty writes CR-LF, so nothing here anchors a line; the menu paints
# inside a row, so its escapes come out first), the tail line's fields
# through the same CR normalisation the groups loop's readers use
function _hi_cfg_has() { _hi_strip_ansi "$(<"$_HI_WORKDIR/$1.cfg.out")" | grep -qF "$2"; }
function _hi_cfg_rc() { _hi_pty_field "$1" cfg 'CFGRC=' '[0-9]*'; }
function _hi_cfg_lines() { _hi_pty_field "$1" cfg 'CFGLINES='; }

# _hi_cfg_screen <label> <n> - the menu's <n>th draw, 0 the first: the pty
# echoes no input, so each ` > ` prompt shares its line with the next draw's
# title, and a draw runs from one prompt line to the line before the next
function _hi_cfg_screen() {
  _hi_strip_ansi "$(<"$_HI_WORKDIR/$1.cfg.out")" | tr -d '\r' |
    awk -v n="$2" 'index($0, " > ") == 1 { s++ } s == n'
}
function _hi_cfg_screen_has() {
  _hi_cfg_screen "$1" "$2" | grep -qF -- "$3" || _hi_because "draw $2 of $1 has no \"$3\""
}
# _hi_cfg_titles <label> - every draw's title, in order, comma-joined
function _hi_cfg_titles() {
  _hi_strip_ansi "$(<"$_HI_WORKDIR/$1.cfg.out")" | tr -d '\r' |
    sed -E -n 's/.*-  (hi --configure(: [A-Za-z ]+)?|Header|Package check|Prompt|Plugins|Aliases|This machine|Advanced)  -.*/\1/p' |
    paste -sd, -
}

# every section's letter in order, then b: the seven pages and the main page
# again, each drawn once
_HI_MENU_EVERY_PAGE='i\nc\nr\ng\na\nm\nv\nb\ns\n'
_HI_MENU_EVERY_TITLE="hi --configure,hi --configure: Header,hi --configure: Package check"
_HI_MENU_EVERY_TITLE="$_HI_MENU_EVERY_TITLE,hi --configure: Prompt,hi --configure: Plugins"
_HI_MENU_EVERY_TITLE="$_HI_MENU_EVERY_TITLE,hi --configure: Aliases,hi --configure: This machine"
_HI_MENU_EVERY_TITLE="$_HI_MENU_EVERY_TITLE,hi --configure: Advanced,hi --configure"

function test_ask_value_takes_a_typed_number() {
  _hi_cfg_pty width_typed '120\n' '' config_max_width || return 1
  [ "$(_hi_cfg_lines width_typed)" = "export _HI_MAX_WIDTH=120" ]
}

# a rejected answer says why and keeps the current value rather than dropping
# it - the message names the value kept, so both halves are one substring
function test_ask_value_rejects_junk_and_keeps_current() {
  _hi_cfg_pty width_junk 'abc\n' 'export _HI_MAX_WIDTH=100' config_max_width || return 1
  _hi_cfg_has width_junk "a number, 40 or more, leaving it at 100" &&
    [ "$(_hi_cfg_lines width_junk)" = "export _HI_MAX_WIDTH=100" ]
}

# typing the shipped default is how an override is cleared interactively
function test_ask_value_typed_default_clears_the_override() {
  _hi_cfg_pty width_default '80\n' 'export _HI_MAX_WIDTH=100' config_max_width || return 1
  [ -z "$(_hi_cfg_lines width_default | tr -d '[:space:]')" ]
}

# _hi_item <kind> - the number the menu gives an item ("word|0" the first
# header item, "end|bash", "width", ...), read off the list itself rather
# than counted by hand, so a row added above it cannot leave a case typing
# the wrong number. The list is the same for every case, so it is built once,
# ahead of the batches: a build forks over a hundred times, and the case that
# walks every row paid that per row.
_HI_ITEM_LIST=()
function _hi_items_load() {
  _hi_read_lines _HI_ITEM_LIST < <(
    _HI_SETTINGS=/dev/null
    # the plugins number by what has a file, so under the overlay the pty
    # child ($_HI_CFG_CHILD) makes: nano's rc alone
    _HI_CONFIG_DIR="$_HI_WORKDIR/item-overlay"
    mkdir -p "$_HI_CONFIG_DIR/nano"
    : >"$_HI_CONFIG_DIR/nano/nanorc"
    _HI_SETTING_PENDING=()
    _hi_header_edit_load
    _hi_menu_list >/dev/null
    printf '%s\n' "${_HI_MENU_ITEMS[@]}"
  )
}
function _hi_item() {
  local i
  ((${#_HI_ITEM_LIST[@]})) || _hi_items_load
  for i in "${!_HI_ITEM_LIST[@]}"; do
    [ "${_HI_ITEM_LIST[$i]}" = "$1" ] || continue
    printf '%d' "$((i + 1))"
    return 0
  done
  return 1
}

# The menu: the real header boxed above the list, and every command
# re-renders. Toggling the first header item off (utc) writes the default
# order minus that word, quoted - read off header.sh's own
# $_HI_HEADER_ORDER_DEFAULT rather than a second copy of it, so a reorder
# there cannot leave this expectation stale.
function test_menu_header_item_toggle_writes_the_order() {
  _hi_cfg_pty hdr_toggle "$(_hi_item 'word|0')\ns\n" '' config_hub || return 1
  local lines want
  want="$(bash -c 'source "$_HI_HEADER"; printf %s "$_HI_HEADER_ORDER_DEFAULT"')"
  want="${want/utc /}"
  lines="$(_hi_cfg_lines hdr_toggle)"
  _hi_cfg_has hdr_toggle "preview" &&
    [[ "$lines" == *"export _HI_HEADER_ORDER='$want'"* ]]
}

# toggled off and back on, the order is the shipped one again and writes
# nothing - the same rule the typed default follows everywhere else
function test_menu_default_order_writes_nothing() {
  local w
  w="$(_hi_item 'word|0')"
  _hi_cfg_pty hdr_default "$w\n$w\ns\n" '' config_hub || return 1
  [ -z "$(_hi_cfg_lines hdr_default | tr -d '[:space:]')" ]
}

# `down N` swaps utc with its neighbor
function test_menu_moves_a_header_item() {
  _hi_cfg_pty hdr_move "down $(_hi_item 'word|0')\ns\n" '' config_hub || return 1
  [[ "$(_hi_cfg_lines hdr_move)" == *"export _HI_HEADER_ORDER='version utc localtime"* ]]
}

# the banner always leads: it toggles but never moves
function test_menu_banner_never_moves() {
  local b
  b="$(_hi_item 'row|_HI_HEADER_PROMPTS|0')"
  _hi_cfg_pty hdr_banner "up $b\n$b\ns\n" '' config_hub || return 1
  local lines
  lines="$(_hi_cfg_lines hdr_banner)"
  _hi_cfg_has hdr_banner "the banner always leads" &&
    [[ "$lines" == *"export _HI_DISABLE_BANNER=1"* && "$lines" != *"_HI_HEADER_ORDER"* ]]
}

# a name off the preset roster is a non-zero return and no pending write
function test_header_edit_preset_refuses_a_stranger() {
  local out
  out="$(
    _HI_SETTING_PENDING=()
    _hi_header_edit_preset nope && exit 1
    printf '%s' "${_HI_SETTING_PENDING[*]:-}"
  )" || return 1
  [ -z "$out" ]
}

# a header preset: its words on and first, in its order, the rest off after,
# as one pending _HI_HEADER_ORDER - and `full`, whose word list is empty,
# lands back on the shipped order, which writes nothing
function test_header_edit_preset_turns_on_its_words_in_order() {
  (
    _HI_SETTINGS=/dev/null
    _HI_SETTING_PENDING=()
    _hi_header_edit_preset quiet || exit 1
    [ "${_HI_SETTING_PENDING[*]}" = "_HI_HEADER_ORDER=utc localtime gitid" ] &&
      [ "${_HI_HDR_WORDS[*]:0:3}" = "utc localtime gitid" ] &&
      [ "$(_hi_header_edit_count_on)" = 3 ] &&
      [[ "$_HI_MENU_NOTE" == *"the 'quiet' preset"* ]] ||
      _hi_because "quiet: pending [${_HI_SETTING_PENDING[*]}], words [${_HI_HDR_WORDS[*]}]" || exit 1
    _hi_header_edit_preset full || exit 1
    [ "${_HI_SETTING_PENDING[*]}" = "_HI_HEADER_ORDER=" ] &&
      [ "$(_hi_header_edit_count_on)" = "${#_HI_HDR_WORDS[@]}" ] ||
      _hi_because "full: pending [${_HI_SETTING_PENDING[*]}]"
  )
}

# up/down off the header items, and at the end the item is already at - two
# refusals, each in words, and the run goes on
function test_menu_refuses_a_move_that_cannot_happen() {
  _hi_cfg_pty hdr_updown "up 99\nup $(_hi_item 'word|0')\ns\n" '' config_hub || return 1
  _hi_cfg_has hdr_updown "up/down take a header item" &&
    _hi_cfg_has hdr_updown "is already at that end"
}

# h, then a name off the roster: said, nothing written, the menu goes on
function test_menu_header_preset_refuses_a_stranger() {
  _hi_cfg_pty hdr_pstranger 'h\nnope\ns\n' '' config_hub || return 1
  _hi_cfg_has hdr_pstranger "no such header preset: nope" &&
    [ -z "$(_hi_cfg_lines hdr_pstranger | tr -d '[:space:]')" ]
}

function test_menu_takes_a_width() {
  _hi_cfg_pty hdr_width "$(_hi_item width)\n120\ns\n" '' config_hub || return 1
  _hi_cfg_has hdr_width "Terminal width for the header/banner (40 or more)?" &&
    [[ "$(_hi_cfg_lines hdr_width)" == *"export _HI_MAX_WIDTH=120"* ]]
}

function test_menu_takes_hidden_addresses() {
  _hi_cfg_pty hdr_iphide "$(_hi_item iphide)\nnone\ns\n" "export _HI_HEADER_ORDER='ip utc'" config_hub || return 1
  _hi_cfg_has hdr_iphide "Hide which addresses from the ip cell" &&
    [[ "$(_hi_cfg_lines hdr_iphide)" == *"export _HI_IP_HIDE='none'"* ]]
}

# a separator with a quote in it is refused rather than written into
# settings.sh
function test_menu_refuses_a_quoted_separator() {
  _hi_cfg_pty pe_quote "$(_hi_item 'end|bash')\n'\ns\n" '' config_hub || return 1
  _hi_cfg_has pe_quote "a single quote can't be written to settings.sh" &&
    [[ "$(_hi_cfg_lines pe_quote)" != *"_HI_PROMPT_END_"* ]]
}

# the truecolor question maps its words both ways: `off` is stored as 0, and
# nothing writes an $_HI_ASCII
function test_truecolor_maps_its_words() {
  _hi_cfg_pty adv_tc 'off\n' '' config_truecolor || return 1
  local lines
  lines="$(_hi_cfg_lines adv_tc)"
  [[ "$lines" == *"export _HI_TRUECOLOR=0"* && "$lines" != *"_HI_ASCII"* ]]
}

function test_menu_takes_a_header_preset() {
  _hi_cfg_pty hdr_preset 'h\nq\ns\n' '' config_hub || return 1
  [[ "$(_hi_cfg_lines hdr_preset)" == *"export _HI_HEADER_ORDER='utc localtime gitid'"* ]]
}

# ...by its full name too, which the one-letter shorthand would refuse
function test_menu_takes_a_header_preset_by_name() {
  _hi_cfg_pty hdr_preset_name 'h\nquiet\ns\n' '' config_hub || return 1
  [[ "$(_hi_cfg_lines hdr_preset_name)" == *"export _HI_HEADER_ORDER='utc localtime gitid'"* ]]
}

# the header feature row turns the whole header off, and the preview says
# so in words rather than showing an empty box
function test_menu_header_off_previews_as_words() {
  _hi_cfg_pty hdr_off "$(_hi_item 'row|_HI_FEATURE_PROMPTS|0')\ns\n" '' config_hub || return 1
  _hi_cfg_has hdr_off "header off - nothing prints" &&
    [[ "$(_hi_cfg_lines hdr_off)" == *"export _HI_DISABLE_HEADER=1"* ]]
}

# an empty $_HI_HEADER_ORDER means the default at runtime, so the last item
# cannot be turned off - the menu says how to get an empty header instead
function test_menu_keeps_the_last_header_item() {
  _hi_cfg_pty hdr_last "$(_hi_item 'word|0')\ns\n" "export _HI_HEADER_ORDER='gitid'" config_hub || return 1
  _hi_cfg_has hdr_last "keep at least one header item" &&
    [[ "$(_hi_cfg_lines hdr_last)" == *"export _HI_HEADER_ORDER='gitid'"* ]]
}

# a stored order lists its words first, in its order, then every word it
# leaves out, unchecked
function test_menu_lists_missing_header_items_off() {
  local w
  w="$(_hi_item 'word|0')"
  _hi_cfg_pty hdr_list 'i\ns\n' "export _HI_HEADER_ORDER='check gitid'" config_hub || return 1
  _hi_cfg_has hdr_list "$w) [x] check" &&
    _hi_cfg_has hdr_list "$((w + 1))) [x] gitid" &&
    _hi_cfg_has hdr_list "$((w + 2))) [ ] utc"
}

# a package group's number flips it: useful, off
function test_menu_flips_a_package_group() {
  _hi_cfg_pty hdr_groups "$(_hi_item 'group|useful')\ns\n" '' config_hub || return 1
  _hi_cfg_has hdr_groups "package group useful: now off" &&
    [[ "$(_hi_cfg_lines hdr_groups)" == *"export _HI_PACKAGES_GROUPS='core deprecated'"* ]]
}

# a group of plugins has a number, and it keeps the whole group home
function test_menu_keeps_a_plugin_group_home() {
  _hi_cfg_pty plug_toggle "$(_hi_item 'plugin|editors')\ns\n" '' config_hub || return 1
  _hi_cfg_has plug_toggle "editors: stays home" &&
    [[ "$(_hi_cfg_lines plug_toggle)" == *"export _HI_PLUGINS_OFF='editors'"* ]]
}

# ...and so has each plugin: the rig's one file is nano's
function test_menu_keeps_a_plugin_home() {
  _hi_cfg_pty plug_num "g\n$(_hi_item 'plugin|nano')\ns\n" '' config_hub || return 1
  _hi_cfg_has plug_num ") [x] editors" && _hi_cfg_has plug_num ") [ ] nano" &&
    [[ "$(_hi_cfg_lines plug_num)" == *"export _HI_PLUGINS_OFF='nano'"* ]]
}

# ...a plugin sent again while its group is kept home takes the group off the
# list: nano is the group's one plugin here, so nothing is left to write
function test_menu_sends_a_plugin_of_a_kept_group() {
  _hi_cfg_pty plug_back "$(_hi_item 'plugin|nano')\ns\n" "export _HI_PLUGINS_OFF='editors'" config_hub || return 1
  _hi_cfg_has plug_back "nano: is sent" &&
    [[ "$(_hi_cfg_lines plug_back)" != *"_HI_PLUGINS_OFF"* ]]
}

# The indices here are positions in $_HI_FEATURE_PROMPTS, so inserting a row
# above the one a case means shifts it: the tool aliases are 4 and
# _HI_DISABLE_ENV_STATUS 3 because the greeting row sits at 1, under the
# header's.

# an opt-in row (the tool aliases, 4) flips on to its on-value
function test_menu_opt_in_row_writes_its_on_value() {
  _hi_cfg_pty feat_opt_in "$(_hi_item 'row|_HI_FEATURE_PROMPTS|4')\ns\n" '' config_hub || return 1
  _hi_cfg_has feat_opt_in "styled tool aliases: now on" &&
    [[ "$(_hi_cfg_lines feat_opt_in)" == *"export _HI_TOOL_ALIASES=1"* ]]
}

# The environment segment sits after git status. Its preview
# falls back to the shape when nothing is active here, which is what a run on
# a bare CI box sees - so the case asserts the toggle and the paren shape, not
# a name only this machine would have.
function test_menu_env_segment_toggles_and_previews() {
  _hi_cfg_pty feat_env "$(_hi_item 'row|_HI_FEATURE_PROMPTS|3')\ns\n" '' config_hub || return 1
  _hi_cfg_has feat_env "environment segment: now off" &&
    _hi_cfg_has feat_env "myproj" &&
    [[ "$(_hi_cfg_lines feat_env)" == *"export _HI_DISABLE_ENV_STATUS=1"* ]]
}

# ...and the header row, off and back on, previews the whole header both ways
function test_menu_header_row_previews_the_header() {
  _hi_cfg_pty feat_header "$(_hi_item 'row|_HI_FEATURE_PROMPTS|0')\n$(_hi_item 'row|_HI_FEATURE_PROMPTS|0')\ns\n" '' config_hub || return 1
  _hi_cfg_has feat_header "header off - nothing prints" &&
    _hi_cfg_has feat_header "Connected" &&
    [ -z "$(_hi_cfg_lines feat_header | tr -d '[:space:]')" ]
}

# a separator typed for bash is single-quoted; zsh's, asked but left alone,
# is never written
function test_prompt_end_typed_interactively_is_quoted() {
  _hi_cfg_pty pe_typed "$(_hi_item 'end|bash')\n>>\ns\n" '' config_hub || return 1
  local lines
  lines="$(_hi_cfg_lines pe_typed)"
  [[ "$lines" == *"export _HI_PROMPT_END_BASH='>>'"* && "$lines" != *"_HI_PROMPT_END_ZSH"* ]]
}

# who draws each shell's prompt is asked shell by shell: starship for bash,
# by name, hi for zsh and fish, by number, is one plain `hi` and bash's entry
function test_menu_picks_a_prompt_program_per_shell() {
  _hi_cfg_pty pe_star "$(_hi_item 'tool|bash')\nstarship\n$(_hi_item 'tool|zsh')\n2\n$(_hi_item 'tool|fish')\n2\ns\n" '' config_hub || return 1
  _hi_cfg_has pe_star "bash prompt: starship" &&
    [[ "$(_hi_cfg_lines pe_star)" == *"export _HI_PROMPT_TOOL='bash:starship hi'"* ]]
}

# ...and auto for every shell clears the line rather than writing one
function test_menu_prompt_program_back_to_auto() {
  _hi_cfg_pty pe_star_off "$(_hi_item 'tool|bash')\nauto\ns\n" "export _HI_PROMPT_TOOL='bash:starship'" config_hub || return 1
  _hi_cfg_has pe_star_off "bash prompt: auto" && _hi_cfg_has pe_star_off "CFGLINES=" &&
    [[ "$(_hi_cfg_lines pe_star_off)" != *"_HI_PROMPT_TOOL"* ]]
}

# a name off the list is said and asked again, and the third in a row leaves
# the shell's entry as it was
function test_menu_prompt_program_rejects_a_stranger() {
  _hi_cfg_pty pe_stranger "$(_hi_item 'tool|bash')\nnope\nstarship\ns\n" '' config_hub || return 1
  _hi_cfg_has pe_stranger "no choice nope - type a number or a name from the list" &&
    [[ "$(_hi_cfg_lines pe_stranger)" == *"export _HI_PROMPT_TOOL=bash:starship"* ]] || return 1
  _hi_cfg_pty pe_strangers "$(_hi_item 'tool|bash')\nnope\n99\nnah\ns\n" "export _HI_PROMPT_TOOL='bash:starship'" config_hub || return 1
  _hi_cfg_has pe_strangers "no choice 99" && ! _hi_cfg_has pe_strangers "no choice nah" &&
    [[ "$(_hi_cfg_lines pe_strangers)" == *"export _HI_PROMPT_TOOL=bash:starship"* ]]
}

# the menu's reading of a value: a shell's own entry first, then the plain
# ones, auto with only other shells' entries, hi when none fits
function test_prompt_choice_reads_the_value() {
  local c
  _hi_prompt_choice bash "bash:starship hi" c && [ "$c" = starship ] || _hi_because "bash: $c" || return 1
  _hi_prompt_choice zsh "bash:starship hi" c && [ "$c" = hi ] || _hi_because "zsh: $c" || return 1
  _hi_prompt_choice fish "bash:starship" c && [ "$c" = auto ] || _hi_because "fish: $c" || return 1
  _hi_prompt_choice bash "tide" c && [ "$c" = hi ] || _hi_because "tide in bash: $c" || return 1
  _hi_prompt_choice fish "tide hi" c && [ "$c" = tide ] || _hi_because "fish tide: $c"
}

# the Advanced rows: an opt-in toggle and a value typed for real, including
# the words-to-flag mapping _HI_TRUECOLOR's question hides behind ("on" is
# stored as 1)
function test_menu_advanced_rows() {
  _hi_cfg_pty adv_typed "$(_hi_item 'row|_HI_ADVANCED_PROMPTS|0')\n$(_hi_item truecolor)\non\ns\n" '' config_hub || return 1
  local lines
  lines="$(_hi_cfg_lines adv_typed)"
  _hi_cfg_has adv_typed "drop the leading space: now on" &&
    [[ "$lines" == *"export _HI_DISABLE_LEAD_SPACE=1"* && "$lines" == *"export _HI_TRUECOLOR=1"* ]]
}

# Enter at the preset question keeps the current settings: nothing seeded,
# and the run carries on rather than failing
function test_preset_question_enter_keeps_current() {
  _hi_cfg_pty pre_enter '\n' '' config_preset || return 1
  [ "$(_hi_cfg_rc pre_enter)" = 0 ] &&
    _hi_cfg_has pre_enter "Start from a preset?" &&
    ! _hi_cfg_has pre_enter "starting from the"
}

# a typo gets the full name list back and the run carries on unseeded - the
# question is an offer, not a gate
function test_preset_question_refuses_a_stranger_and_carries_on() {
  _hi_cfg_pty pre_unknown 'zzz\n' '' config_preset || return 1
  [ "$(_hi_cfg_rc pre_unknown)" = 0 ] && _hi_cfg_has pre_unknown "no such preset: zzz"
}

# a shorthand letter resolves and seeds the run
function test_preset_shorthand_seeds_the_run() {
  _hi_cfg_pty pre_walk 'b\n' '' config_preset || return 1
  _hi_cfg_has pre_walk "starting from the 'balanced' preset" &&
    [[ "$(_hi_cfg_lines pre_walk)" == *"export _HI_PACKAGES_GROUPS='core,deprecated'"* ]]
}

# The whole run. The shortest: the intro orients, p opens the presets, m
# picks minimal, s saves - and the one write at the end is exactly the
# preset's block.
function test_full_run_preset_then_save() {
  _hi_cfg_pty full_walk 'p\nm\ns\n' '' run_configure "" || return 1
  local block
  block="$(grep -F "$_HI_MARKER" "$_HI_WORKDIR/full_walk/overlay/settings.sh")"
  _hi_cfg_has full_walk "Nothing is written until you save" &&
    _hi_cfg_has full_walk "starting from the 'minimal' preset" &&
    _hi_cfg_has full_walk "CFGQUIT=none" &&
    [[ "$block" == *"export _HI_DISABLE_HEADER=1"* && "$block" == *"export _HI_DISABLE_LOCAL=1"* &&
      "$block" == *"export _HI_PLUGINS_OFF='editors'"* ]]
}

# q after the same preset writes nothing at all - no block, not even the
# shebang - and leaves the flag install.sh's closing line reads
function test_full_run_quit_writes_nothing() {
  _hi_cfg_pty full_quit 'p\nm\nq\n' '' run_configure "" || return 1
  _hi_cfg_has full_quit "starting from the 'minimal' preset" &&
    _hi_cfg_has full_quit "nothing written" &&
    _hi_cfg_has full_quit "CFGQUIT=1" &&
    ! grep -qF "$_HI_MARKER" "$_HI_WORKDIR/full_quit/overlay/settings.sh"
}

# EOF at the menu saves what there is - no answer has always meant "keep
# what you have and finish" here - so a driver that stops typing still ends
# in the write
function test_menu_eof_saves() {
  _hi_cfg_pty hub_eof '\004' 'export _HI_DISABLE_GIT_STATUS=1' run_configure "" || return 1
  _hi_cfg_has hub_eof "CFGQUIT=none" &&
    grep -qF "export _HI_DISABLE_GIT_STATUS=1" "$_HI_WORKDIR/hub_eof/overlay/settings.sh"
}

# ...and the third junk answer in a row ends the run too, but as a quit:
# three words that are not menu items are not an instruction to write
function test_menu_junk_is_bounded_and_quits() {
  _hi_cfg_pty hub_junk 'x\ny\nz\nq\n' '' run_configure "" || return 1
  _hi_cfg_has hub_junk "type an item number" &&
    _hi_cfg_has hub_junk "leaving" &&
    _hi_cfg_has hub_junk "CFGQUIT=1"
}

# the main page is a summary line a section, in order, under the preview box
# - its key, name, numbers, [x] count, and values - and none of their rows.
# This machine's one number is _HI_DISABLE_LOCAL's, read off the list.
function test_menu_main_page_sums_up_every_section() {
  local m main keys
  m="$(_hi_item 'row|_HI_FEATURE_PROMPTS|6')" || return 1
  _HI_TERM_COLS=80 _hi_cfg_pty hub_all 's\n' '' run_configure "" || return 1
  main="$(_hi_cfg_screen hub_all 0)"
  keys="$(printf '%s\n' "$main" | sed -n 's/^ \[\([a-z]\)\] .*/\1/p' | paste -sd, -)"
  [ "$keys" = "i,c,r,g,a,m,v" ] || _hi_because "the main page's sections: [$keys]" || return 1
  [[ "$main" == *"preview"* && "$main" == *" [i] Header        1-"*" on, width 80"* ]] &&
    [[ "$main" == *" [c] Package check "*" core useful deprecated"* && "$main" == *" [g] Plugins "*" all sent"* ]] &&
    [[ "$main" == *" [m] This machine  $(printf '%-6s' "$m") 1 of 1 on"* ]] &&
    [[ "$main" == *" [v] Advanced      "*", 24-bit color auto"* ]] &&
    [[ "$main" != *") ["* && "$main" != *"hi --configure:"* && "$main" != *"[b]ack"* ]] &&
    _hi_cfg_has hub_all "CFGQUIT=none"
}

# a section's letter opens its page - titled, [b]ack leading the keys, only its
# own rows, and a preview of what they change or none - and b comes back to
# the main page
function test_menu_section_letters_open_their_pages() {
  local titles end kept sudo core
  end="$(_hi_item 'end|bash')" && kept="$(_hi_item 'plugin|editors')" && core="$(_hi_item 'group|core')" &&
    sudo="$(_hi_item 'row|_HI_FEATURE_PROMPTS|5')" || return 1
  _HI_TERM_COLS=80 _hi_cfg_pty hub_pages "$_HI_MENU_EVERY_PAGE" '' run_configure "" || return 1
  titles="$(_hi_cfg_titles hub_pages)"
  [ "$titles" = "$_HI_MENU_EVERY_TITLE" ] || _hi_because "titles: [$titles]" || return 1
  _hi_cfg_screen_has hub_pages 1 " [b]ack  [h]eader preset" &&
    _hi_cfg_screen_has hub_pages 1 " 1) [x] header" &&
    _hi_cfg_screen_has hub_pages 1 "Connected" &&
    _hi_cfg_screen_has hub_pages 2 "$core) [x] core" &&
    _hi_cfg_screen_has hub_pages 3 "$end)     bash prompt ends with" &&
    _hi_cfg_screen_has hub_pages 4 "$kept) [x] editors" &&
    _hi_cfg_screen_has hub_pages 5 "$sudo) [ ] sudo alias" &&
    _hi_cfg_screen_has hub_pages 7 "24-bit color" &&
    _hi_cfg_screen_has hub_pages 8 " [i] Header" &&
    ! _hi_cfg_screen_has hub_pages 3 " 1) [x] header" 2>/dev/null &&
    ! _hi_cfg_screen_has hub_pages 3 "Connected" 2>/dev/null &&
    ! _hi_cfg_screen_has hub_pages 4 "preview" 2>/dev/null &&
    ! _hi_cfg_screen_has hub_pages 6 "preview" 2>/dev/null &&
    ! _hi_cfg_screen_has hub_pages 8 "[b]ack" 2>/dev/null
}

# This machine's page draws _HI_DISABLE_LOCAL, the one row it holds
function test_menu_this_machine_page_holds_here_too() {
  local m
  m="$(_hi_item 'row|_HI_FEATURE_PROMPTS|6')" || return 1
  _HI_TERM_COLS=80 _hi_cfg_pty hub_local 'm\ns\n' '' run_configure "" || return 1
  _hi_cfg_screen_has hub_local 1 "hi --configure: This machine" &&
    _hi_cfg_screen_has hub_local 1 "$m) [x] here too"
}

# a row whose <needs> command is not here says so, and any one of its
# alternatives being here is enough to say nothing
function test_menu_row_notes_an_absent_needs_command() {
  local out
  local -a _HI_NEEDS_ROWS=('_HI_NO_SUCH|1|||hi-no-such-cmd/hi-none-either|needy - a row' '_HI_NO_SUCH|1|||hi-no-such-cmd/bash|easy - a row')
  out="$(_HI_MENU_ITEMS=() _HI_MENU_DRAW=1 _HI_MENU_W=80 _HI_MENU_SUM_N=0 && _hi_menu_row _HI_NEEDS_ROWS 0 && _hi_menu_row _HI_NEEDS_ROWS 1)"
  out="$(_hi_strip_ansi "$out")"
  [[ "$out" == *"needy"*"(no hi-no-such-cmd here)"*"easy"* && "${out#*easy}" != *" here)"* ]] || _hi_because "the rows: $out"
}

# every row of every table gets a number, whichever page draws it
function test_menu_numbers_every_row() {
  local t i
  local -a rows=()
  for t in _HI_FEATURE_PROMPTS _HI_HEADER_PROMPTS _HI_PROMPT_PROMPTS _HI_ADVANCED_PROMPTS; do
    _hi_prompt_rows "$t" rows
    for i in "${!rows[@]}"; do
      _hi_item "row|$t|$i" >/dev/null || _hi_because "no menu number for $t row $i" || return 1
    done
  done
}

# a number works from any page: the main page's flips a Prompt row and stays
# on the main page, the Advanced page's flips an Aliases row and stays there
function test_menu_number_works_from_any_page() {
  local p t
  p="$(_hi_item 'row|_HI_PROMPT_PROMPTS|0')" && t="$(_hi_item 'row|_HI_FEATURE_PROMPTS|4')" || return 1
  _HI_TERM_COLS=80 _hi_cfg_pty hub_num "$p\nv\n$t\ns\n" '' run_configure "" || return 1
  local lines
  lines="$(_hi_cfg_lines hub_num)"
  _hi_cfg_screen_has hub_num 1 "colored user@host prompt: now off" &&
    _hi_cfg_screen_has hub_num 1 " [i] Header" &&
    _hi_cfg_screen_has hub_num 3 "styled tool aliases: now on" &&
    _hi_cfg_screen_has hub_num 3 "hi --configure: Advanced" &&
    [[ "$lines" == *"export _HI_DISABLE_PROMPT=1"* && "$lines" == *"export _HI_TOOL_ALIASES=1"* ]]
}

# The Header page's grids: the three switches, then the header items, 4 cells
# to a line at 80 columns, folding to 2 at 40, every one drawn
function _hi_menu_grid_at() {
  local w="$1" want="$2" label="grid_$1" cells page first
  cells=$(($(_hi_item width) - 1))
  _HI_TERM_COLS="$w" _hi_cfg_pty "$label" 'i\ns\n' '' run_configure "" || return 1
  page="$(_hi_cfg_screen "$label" 1)"
  first="$(printf '%s\n' "$page" | grep -F " $(_hi_item 'word|0')) [x] utc" | grep -o ') \[[x ]\] ' | wc -l)"
  page="$(printf '%s\n' "$page" | grep -o ') \[[x ]\] ' | wc -l)"
  ((first == want)) || _hi_because "the grid's first line at $w holds $first cells" || return 1
  ((page == cells)) || _hi_because "the grid at $w holds $page cells, not $cells"
}
function test_menu_header_grid_at_80() { _hi_menu_grid_at 80 4; }
function test_menu_header_grid_at_40() { _hi_menu_grid_at 40 2; }

# At 80 columns every page, the main one included, fits a 24-row terminal:
# a draw's lines, then the prompt's own row
function test_menu_pages_fit_24_rows() {
  local k rows
  _HI_TERM_COLS=80 _hi_cfg_pty hub_rows "$_HI_MENU_EVERY_PAGE" '' run_configure "" || return 1
  for k in 1 2 3 4 5 6 7 8; do
    rows=$(($(_hi_cfg_screen hub_rows "$k" | wc -l) + 1))
    ((rows <= 24)) || _hi_because "draw $k is $rows rows" || return 1
  done
}

# The layout, pinned at 80 columns and at 40 the way the header's width is
# ($_HI_TERM_COLS), through every page: no line of the run is wider than the
# terminal, a narrow one cutting help text and summaries rather than wrapping
# them, and the pages draw in the order their letters were typed
function _hi_menu_layout_at() {
  local w="$1" label="layout_$1" line len over=0 titles want
  _HI_TERM_COLS="$w" _hi_cfg_pty "$label" "$_HI_MENU_EVERY_PAGE" '' run_configure "" || return 1
  while IFS= read -r line; do
    case "$line" in *CFGRC=*) continue ;; esac
    # the pty echoes no input, so what follows the ` > ` prompt lands on its
    # line - where a terminal's Enter would have ended it
    line="${line#' > '}"
    _hi_visible_len len "$line"
    ((len > w)) || continue
    _hi_cecho " | $len columns at $w: $line" "$RED"
    over=1
  done < <(_hi_strip_ansi "$(<"$_HI_WORKDIR/$label.cfg.out")" | tr -d '\r')
  titles="$(_hi_cfg_titles "$label")"
  want="$_HI_MENU_EVERY_TITLE"
  # under 60 columns a page's title is its name alone
  ((w >= 60)) || want="${want//hi --configure: /}"
  [ "$titles" = "$want" ] || {
    _hi_cecho " | the pages at $w columns: [$titles]" "$RED"
    return 1
  }
  [ "$over" = 0 ]
}
function test_menu_layout_at_80() { _hi_menu_layout_at 80; }
function test_menu_layout_at_40() { _hi_menu_layout_at 40; }

# a value away from its default says the default beside it; one at it does not
function test_menu_value_shows_its_default() {
  _HI_TERM_COLS=80 _hi_cfg_pty hub_def 'i\ns\n' "export _HI_MAX_WIDTH=100" run_configure "" || return 1
  _hi_cfg_has hub_def "width                 100 (default 80)" &&
    ! _hi_cfg_has hub_def "(default 172.*)"
}

function run_configure_tests() {
  _hi_workdir configuretest
  # the editor configs an overlay carries: without them no editor has an alias
  # for the previews to read back
  mkdir -p "$_HI_CONFIG_DIR"
  local _hi_f
  for _hi_f in vim/vimrc nvim/init.lua helix/config.toml nano/nanorc emacs/init.el; do
    mkdir -p "$_HI_CONFIG_DIR/${_hi_f%/*}"
    : >"$_HI_CONFIG_DIR/$_hi_f"
  done
  mkdir -p "$_HI_CONFIG_DIR/micro"
  : >"$_HI_CONFIG_DIR/micro/settings.json"
  : >"$_HI_CONFIG_DIR/micro/bindings.json"
  _hi_items_load

  _hi_h1 "Testing scripts/configure.sh's reusable logic"

  _hi_suite_begin

  _hi_h2 "Testing: settings are sourced ahead of paths.sh"
  _hi_check "common/core.sh" _hi_sources_settings_before_paths "$_HI_ROOT/common/core.sh"
  _hi_check "common/config.fish" _hi_sources_settings_before_paths "$_HI_ROOT/common/config.fish"

  _hi_h2 "Testing: the collector - prompt separators"
  _hi_check "An existing override is kept" test_prompt_ends_keeps_an_existing_override
  _hi_check "Written values are quoted" test_prompt_ends_quotes_what_it_writes
  _hi_check "Kept when the prompt is off" test_prompt_ends_kept_when_the_prompt_is_off

  _hi_h2 "Testing: the collector - palette and header order"
  _hi_check "Colors: hand-written lines survive a run" test_hand_written_colors_survive_a_run
  _hi_check "Colors: an unset scheme and ramp write nothing" test_packages_palette_does_not_write_the_default
  _hi_check "Palette: kept when the check is off" test_packages_palette_kept_when_the_check_is_off
  _hi_check "Hidden addresses: an existing override is kept" test_ip_hide_keeps_an_existing_override
  _hi_check "Hidden addresses: the default writes nothing" test_ip_hide_does_not_write_the_default
  _hi_check "Order: an existing override is kept" test_header_order_keeps_an_existing_override
  _hi_check "Order: the default writes nothing" test_header_order_does_not_write_the_default
  _hi_check "Order: kept when the header is off" test_header_order_kept_when_the_header_is_off
  _hi_check "Header presets hold the vocabulary" test_header_presets_hold_the_vocabulary

  _hi_h2 "Testing: the answer plumbing"
  _hi_check "The input validators hold their grammars" test_validators_hold_their_grammars
  _hi_check "pending_answer reads this run's answers" test_pending_answer_reads_this_runs_answers
  _hi_check "_hi_pending_set replaces in place" test_pending_set_replaces_in_place
  _hi_check "ask_value: non-interactive keeps current, blanks defaults" test_ask_value_non_interactive_keeps_current

  _hi_h2 "Testing: ensure_settings_shebang"
  _hi_check "Written to a new settings.sh" test_shebang_is_written_to_a_new_settings_file
  _hi_check "Stays first under the settings block" test_shebang_stays_first_under_the_settings_block
  _hi_check "Not duplicated on reruns" test_shebang_is_not_duplicated_on_reruns
  _hi_check "Package groups: a flip turns one on or off" test_packages_groups_flip_one
  _hi_check "Package groups: commas are written as spaces" test_packages_groups_normalises_commas
  _hi_check "Package groups: the default set is not written" test_packages_groups_does_not_write_the_default
  _hi_check "Package groups: none is written out" test_packages_groups_writes_none
  _hi_check "Package groups: kept when the check is off" test_packages_groups_kept_when_the_check_is_off
  _hi_check "Replaces a different shebang" test_shebang_replaces_a_different_one_and_keeps_content
  _hi_check "_hi_header_edit_preset refuses a stranger" test_header_edit_preset_refuses_a_stranger
  _hi_check "...and turns on a preset's words, in its order" test_header_edit_preset_turns_on_its_words_in_order
  _hi_check "Menu: every table row has a number" test_menu_numbers_every_row
  _hi_check "Menu: a row names the command it needs and this machine lacks" test_menu_row_notes_an_absent_needs_command
  _hi_check_capable mode_bits "Preserves settings.sh's mode" test_settings_shebang_preserves_mode

  _hi_h2 "Testing: config_settings"
  _hi_check "Writes every group at once" test_config_settings_writes_every_group_at_once
  _hi_check "Written outside the tree" test_settings_are_written_outside_the_tree
  _hi_check "setting_off sees this run's answer" test_setting_off_sees_this_runs_answer

  _hi_h2 "Testing: setting_off"
  _hi_check "Not off when absent" test_setting_off_false_when_absent
  _hi_check "Off when off-value present" test_setting_off_true_when_off_present
  _hi_check "Respects a custom off value" test_setting_off_respects_custom_off_value
  _hi_check "Reads the marker-padded line config_shell writes" test_setting_off_reads_marker_padded_line

  _hi_h2 "Testing: _hi_setting_get sources the file for real"
  _hi_check "Reads a computed value" test_setting_get_reads_a_computed_value
  _hi_check "Reads a two-statement assignment" test_setting_get_reads_a_two_statement_assignment
  _hi_check "Leaves other variables ambient" test_setting_get_leaves_other_variables_ambient

  _hi_h2 "Testing: opt-ins, the advanced section, and the closing report"
  _hi_check "An absent opt-in is off" test_setting_on_opt_in_absent_is_off
  _hi_check "A written opt-in is on" test_setting_on_opt_in_present_is_on
  _hi_check "An absent toggle is on" test_setting_on_toggle_absent_is_on
  _hi_check "An opt-in that is off writes nothing" test_opt_in_off_writes_nothing
  _hi_check "hi's prompt is kept when chosen" test_hi_prompt_kept_when_chosen
  _hi_check "Advanced: unanswered keeps every value" test_advanced_declined_keeps_every_value
  _hi_check "Advanced: defaults write nothing" test_advanced_defaults_write_nothing
  _hi_check "A hand-written line is adopted, not duplicated" test_configure_adopts_a_hand_written_line
  _hi_check "A hand line this run does not write is left alone" test_configure_leaves_a_hand_line_it_does_not_write
  _hi_check "No tty and nothing to say: no file" test_no_tty_run_with_defaults_writes_no_file
  _hi_check "A preset run creates the file" test_preset_run_still_creates_the_file
  _hi_check "Validators for the advanced values" test_validators_for_the_advanced_values
  _hi_check "Diff reports added and removed lines" test_settings_diff_reports_added_and_removed
  _hi_check "Diff says no changes" test_settings_diff_says_no_changes

  _hi_h2 "Testing: presets"
  _hi_check "A preset seeds every answer in its vocabulary" test_apply_preset_seeds_every_answer
  _hi_check "lean sets what no other preset resets" test_preset_lean_sets_what_no_other_resets
  _hi_check "An unknown preset is refused" test_apply_preset_rejects_a_stranger
  _hi_check "Shorthand resolves each preset's first letter" test_preset_shorthand_resolves_each_first_letter
  _hi_check "Shorthand is table-agnostic and refuses ambiguity" test_preset_shorthand_is_table_agnostic_and_refuses_ambiguity
  _hi_check "Shorthand rejects an unknown letter" test_preset_shorthand_rejects_unknown_letter
  _hi_check "Shorthand rejects more than one character" test_preset_shorthand_rejects_multiple_characters
  _hi_check "Every preset stays inside the vocabulary" test_every_preset_names_only_vocabulary
  _hi_check "The vocabulary excludes the palette and the order" test_preset_vocab_excludes_palette_and_order
  _hi_check "--preset writes exactly the preset" test_preset_run_writes_the_preset
  _hi_check "install.sh refuses an unknown --preset" test_install_rejects_an_unknown_preset
  _hi_check "No preset and no tty keeps the block" test_run_configure_without_a_preset_keeps_the_block

  _hi_h2 "Testing: config_hi (skip path only)"
  _hi_check_capable symlink "Skips when already linked" test_config_hi_skips_when_already_linked
  _hi_check_capable symlink "Survives an unwritable launcher" test_config_hi_survives_an_unwritable_launcher
  _hi_check_capable symlink "Skips chmod when already executable" test_config_hi_skips_chmod_when_already_executable
  _hi_check_capable symlink "Links plainly into a writable bindir" test_config_hi_links_plainly_when_bindir_is_writable

  _hi_h2 "Testing: the question previews"
  _hi_check "Prompt preview shows this user@host" test_prompt_preview_shows_this_user_and_host
  _hi_check "Prompt sample says off when the prompt is disabled" test_prompt_sample_preview_says_off_when_disabled
  _hi_check "...and draws the prompt when it is on" test_prompt_sample_preview_draws_the_prompt_when_on
  _hi_check "...painted with the settings file's scheme" test_prompt_sample_preview_paints_with_the_settings_scheme
  _hi_check "...its cwd cut to the last part in a narrow menu" test_prompt_sample_preview_shortens_the_cwd_in_a_narrow_menu
  _hi_check "Editors preview names every override" test_editors_preview_names_every_override
  _hi_check "The vim preview matches its alias" test_editor_preview_matches_its_alias vim nvim/init.lua nvim
  _hi_check "...and the nvim preview matches its own" test_editor_preview_matches_its_alias nvim nvim/init.lua nvim
  _hi_check "...and the hx preview matches its own" test_editor_preview_matches_its_alias hx helix/config.toml hx
  _hi_check "...and so does helix's, under that name alone" test_editor_preview_matches_its_alias helix helix/config.toml helix
  _hi_check "bat preview names the bat it found" test_bat_preview_names_the_bat_it_found
  _hi_check "...and says so when there is none" test_bat_preview_without_bat_says_targets_only
  _hi_check "the prompt preview names the programs installed here" test_prompt_tool_preview_names_what_is_installed
  _hi_check "...and says when there are none" test_prompt_tool_preview_reports_none
  _hi_check "...and that it is moot with the prompt off" test_prompt_tool_preview_is_moot_with_the_prompt_off
  _hi_check "The menu reads who draws each shell's prompt" test_prompt_choice_reads_the_value
  _hi_check "eza/exa preview names the ls it aliases" test_eza_preview_names_the_ls_it_aliases
  _hi_check "Env segment preview draws the live segment" test_env_status_preview_draws_the_live_segment
  _hi_check "...and a sample with nothing active" test_env_status_preview_samples_with_nothing_active
  _hi_check "Check preview renders the groups that run" test_check_preview_renders_the_groups_that_run
  _hi_check "...and says when they show nothing" test_check_preview_says_when_nothing_shows
  _hi_check "Plugins grid wraps at the menu's width" test_plugins_page_wraps_at_the_menu_width
  _hi_check "...and says when nothing here rides" test_plugins_page_says_when_nothing_rides
  _hi_check "A plugin's number edits the list kept home" test_plugin_flip_edits_the_list_kept_home

  # Every pty case fans out together: each drives its own child under its own
  # $_HI_WORKDIR/<label> and the children re-source configure.sh themselves,
  # so nothing in this shell is shared - and thirty-odd of them at a second
  # apiece would be this suite's whole wall clock run one at a time.
  # The package-groups prompts belong to the section above; they sit here
  # because they are pty cases too.
  _hi_h2 "Testing: the interactive arms and the menu (pty)"
  _hi_par_begin "pty cases"
  _hi_par_check_capable pty "ask_value takes a typed number" test_ask_value_takes_a_typed_number
  _hi_par_check_capable pty "ask_value rejects junk and keeps current" test_ask_value_rejects_junk_and_keeps_current
  _hi_par_check_capable pty "ask_value: the typed default clears the override" test_ask_value_typed_default_clears_the_override
  _hi_par_check_capable pty "Truecolor words map both ways" test_truecolor_maps_its_words
  _hi_par_check_capable pty "Preset question: Enter keeps current" test_preset_question_enter_keeps_current
  _hi_par_check_capable pty "Preset question: a stranger is refused, run continues" test_preset_question_refuses_a_stranger_and_carries_on
  _hi_par_check_capable pty "Preset shorthand seeds the run" test_preset_shorthand_seeds_the_run
  _hi_par_check_capable pty "Menu: the main page sums up every section" test_menu_main_page_sums_up_every_section
  _hi_par_check_capable pty "Menu: a section's letter opens its page, b comes back" test_menu_section_letters_open_their_pages
  _hi_par_check_capable pty "Menu: This machine's page holds here too" test_menu_this_machine_page_holds_here_too
  _hi_par_check_capable pty "Menu: a number works from any page" test_menu_number_works_from_any_page
  _hi_par_check_capable pty "Menu: the Header grid holds 4 columns at 80" test_menu_header_grid_at_80
  _hi_par_check_capable pty "Menu: the Header grid folds to 2 at 40" test_menu_header_grid_at_40
  _hi_par_check_capable pty "Menu: every page fits 24 rows at 80 columns" test_menu_pages_fit_24_rows
  _hi_par_check_capable pty "Menu: fits 80 columns, pages in order" test_menu_layout_at_80
  _hi_par_check_capable pty "Menu: fits 40 columns, pages in order" test_menu_layout_at_40
  _hi_par_check_capable pty "Menu: a changed value names its default" test_menu_value_shows_its_default
  _hi_par_check_capable pty "Menu: a plugin group's number keeps it home" test_menu_keeps_a_plugin_group_home
  _hi_par_check_capable pty "Menu: ...and a plugin's its own" test_menu_keeps_a_plugin_home
  _hi_par_check_capable pty "Menu: ...and one sent again takes its group off the list" test_menu_sends_a_plugin_of_a_kept_group
  _hi_par_check_capable pty "Menu: an opt-in row writes its on-value" test_menu_opt_in_row_writes_its_on_value
  _hi_par_check_capable pty "Menu: the environment row toggles and previews" test_menu_env_segment_toggles_and_previews
  _hi_par_check_capable pty "Menu: the header row previews the whole header" test_menu_header_row_previews_the_header
  _hi_par_check_capable pty "Menu: item 1 turns the header off, in words" test_menu_header_off_previews_as_words
  _hi_par_check_capable pty "Menu: a header item toggle writes the order" test_menu_header_item_toggle_writes_the_order
  _hi_par_check_capable pty "Menu: back to the default order writes nothing" test_menu_default_order_writes_nothing
  _hi_par_check_capable pty "Menu: down N moves a header item" test_menu_moves_a_header_item
  _hi_par_check_capable pty "Menu: the banner toggles but never moves" test_menu_banner_never_moves
  _hi_par_check_capable pty "Menu: a move that cannot happen is refused in words" test_menu_refuses_a_move_that_cannot_happen
  _hi_par_check_capable pty "Menu: the last header item cannot be turned off" test_menu_keeps_the_last_header_item
  _hi_par_check_capable pty "Menu: items a stored order leaves out list unchecked" test_menu_lists_missing_header_items_off
  _hi_par_check_capable pty "Menu: h takes a header preset" test_menu_takes_a_header_preset
  _hi_par_check_capable pty "Menu: h takes a header preset by name" test_menu_takes_a_header_preset_by_name
  _hi_par_check_capable pty "Menu: h refuses a stranger" test_menu_header_preset_refuses_a_stranger
  _hi_par_check_capable pty "Menu: the width item takes a width" test_menu_takes_a_width
  _hi_par_check_capable pty "Menu: a package group's number flips it" test_menu_flips_a_package_group
  _hi_par_check_capable pty "Menu: hidden addresses" test_menu_takes_hidden_addresses
  _hi_par_check_capable pty "Menu: a prompt program is picked per shell" test_menu_picks_a_prompt_program_per_shell
  _hi_par_check_capable pty "Menu: auto for every shell clears the line" test_menu_prompt_program_back_to_auto
  _hi_par_check_capable pty "Menu: a prompt program off the list is asked again" test_menu_prompt_program_rejects_a_stranger
  _hi_par_check_capable pty "Menu: a separator typed and quoted" test_prompt_end_typed_interactively_is_quoted
  _hi_par_check_capable pty "Menu: a quoted separator is refused" test_menu_refuses_a_quoted_separator
  _hi_par_check_capable pty "Menu: the advanced rows" test_menu_advanced_rows
  _hi_par_check_capable pty "Full run: preset, then save" test_full_run_preset_then_save
  _hi_par_check_capable pty "Full run: preset, then quit writes nothing" test_full_run_quit_writes_nothing
  _hi_par_check_capable pty "Menu: EOF saves" test_menu_eof_saves
  _hi_par_check_capable pty "Menu: junk is bounded and quits" test_menu_junk_is_bounded_and_quits
  _hi_par_wait

  _hi_suite_end "configure.sh logic"
}

run_configure_tests
