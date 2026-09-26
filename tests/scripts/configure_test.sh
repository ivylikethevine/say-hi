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
# writes no line for it - the rule config_max_width and config_packages_groups
# use for their own defaults
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

# config_packages_groups: the only prompt that loops, so the parts worth
# pinning without a pty are the ones that do not need one - what it writes for
# the set it ends on. The loop itself needs a terminal and is skipped when
# there is none, which is what makes these callable here - provided stdin
# really is not one: run by hand from a terminal it would be, and the case
# would sit at the prompt, so it is fed /dev/null explicitly.
# _hi_settings_fixture swallows stdout (its other users assert against the
# file it wrote), so the collected lines go to a file inside the fixture
# instead - otherwise "no lines" and "lines nobody saw" look identical and the
# write-nothing cases would pass without asserting anything.
function _hi_groups_run() {
  mkdir -p "$_HI_CONFIG_DIR"
  printf '#!/bin/sh\n%s\n' "$1" >"$_HI_SETTINGS"
  _HI_SETTING_LINES=()
  _HI_SETTING_PENDING=()
  config_packages_groups </dev/null
  collect_setting_lines
  printf '%s\n' ${_HI_SETTING_LINES[@]+"${_HI_SETTING_LINES[@]}"} >"$_HI_CONFIG_DIR/lines.out"
}

function _hi_groups_lines() { cat "$_HI_WORKDIR/$1/overlay/lines.out" 2>/dev/null; }

function test_packages_groups_keeps_a_configured_value() {
  _hi_settings_fixture groups_keep _hi_groups_run "export _HI_PACKAGES_GROUPS='core extras'"
  [ "$(_hi_groups_lines groups_keep)" = "export _HI_PACKAGES_GROUPS='core extras'" ]
}

# a comma-separated value is read as a list and written back space-separated
function test_packages_groups_normalises_commas() {
  _hi_settings_fixture groups_comma _hi_groups_run "export _HI_PACKAGES_GROUPS='core,extras'"
  [ "$(_hi_groups_lines groups_comma)" = "export _HI_PACKAGES_GROUPS='core extras'" ]
}

# the shipped set is header.sh's own default, so writing it out would be a
# line that means nothing - in any order or spelling, the same rule
# config_max_width has for 80
function test_packages_groups_does_not_write_the_default() {
  _hi_settings_fixture groups_default _hi_groups_run "export _HI_PACKAGES_GROUPS='deprecated,useful core'"
  [ -f "$_HI_WORKDIR/groups_default/overlay/lines.out" ] || return 1
  [ -z "$(_hi_groups_lines groups_default | tr -d '[:space:]')" ] || return 1
  _hi_settings_fixture groups_unset _hi_groups_run ''
  [ -f "$_HI_WORKDIR/groups_unset/overlay/lines.out" ] || return 1
  [ -z "$(_hi_groups_lines groups_unset | tr -d '[:space:]')" ]
}

# ...and the other side of that rule: no group at all is an answer, spelled
# `none`, not an empty value that would read as the default
function test_packages_groups_writes_none() {
  _hi_settings_fixture groups_none _hi_groups_run "export _HI_PACKAGES_GROUPS='none'"
  [ "$(_hi_groups_lines groups_none)" = "export _HI_PACKAGES_GROUPS='none'" ]
}

# a fresh shell with only install.sh sourced, the way a caller other than
# run_configure reaches it: the default set is header.sh's, so the section
# loads it first - the shipped set in another order still writes nothing
function test_packages_groups_loads_its_own_default() {
  local dir="$_HI_WORKDIR/groups_fresh" out
  mkdir -p "$dir"
  printf '#!/bin/sh\n%s\n' "export _HI_PACKAGES_GROUPS='useful,core deprecated'" >"$dir/settings.sh"
  # shellcheck disable=SC2016 # expanded by the child
  out="$(_HI_SETTINGS="$dir/settings.sh" _HI_CONFIG_DIR="$dir" bash -c '
    set --
    source "$_HI_INSTALL"
    _HI_SETTINGS="$1/settings.sh" _HI_CONFIG_DIR="$1"
    _HI_SETTING_LINES=() _HI_SETTING_PENDING=()
    config_packages_groups </dev/null
    collect_setting_lines
    printf "LINES:%s\n" "${_HI_SETTING_LINES[*]:-}"' bash "$dir" 2>&1)" || return 1
  [[ "$out" == *"LINES:"* && "$out" != *_HI_PACKAGES_GROUPS* ]]
}

# the check is off, so which groups it runs is moot - the stored value is kept
# for when 'check' comes back
function test_packages_groups_kept_when_the_check_is_off() {
  local out
  out="$(_hi_collected_lines groups_off "export _HI_HEADER_ORDER='gitid'" "export _HI_PACKAGES_GROUPS='core'")"
  [[ "$out" == *"export _HI_HEADER_ORDER='gitid'"* && "$out" == *"export _HI_PACKAGES_GROUPS='core'"* ]]
}

# The loop itself, which none of the cases above can reach: `[ -t 0 ]`
# guards it, so exercising it at all needs a pty. An unbounded retry is the
# failure to fear: an answer that never names a group re-asking forever, with
# no way out but ^C and a full re-render of the package check on every pass.
# What these pin is that it *stops*, by counting
# the prompts rather than trusting a wall clock: a bound that regressed would
# show up as more prompts, not as a slower suite - and that each reply toggles
# the groups it names.
#
# The child reads a fixture packages file with five groups, one of them
# capitalised, so the offered names do not follow the shipped roster.
#
# $_HI_PTY_FORCED is empty when there is no usable pty - no python3 at all, or
# a python3 without the Unix-only `pty` module - which is why these register
# through `_hi_check_capable pty` and skip yellow rather than fail: the
# backend suites' doctrine, for the same reason.
# shellcheck disable=SC2016 # single quotes on purpose: every expansion in here
# is the child shell's to make, after the pty has put it on the other side
_HI_GROUPS_CHILD='
  _hi_dir="$1"
  source "$_HI_TEST_LIB"
  set --
  source "$_HI_INSTALL"
  _HI_ROOT="$_hi_dir"
  # the editor rcs an overlay carries, the only ones common/aliases.sh flags
  mkdir -p "$_hi_dir/overlay"
  : >"$_hi_dir/overlay/nanorc"
  _HI_NANORC="$_hi_dir/overlay/nanorc"
  _HI_CONFIG_DIR="$_hi_dir/overlay"
  _HI_SETTINGS="$_hi_dir/overlay/settings.sh"
  printf "%s\n" "[core]" sh "[useful]" sh "[deprecated]" "-zz-hi-absent" "[extras]" sh "[Work]" sh \
    >"$_hi_dir/overlay/packages"
  _HI_PACKAGES="$_hi_dir/overlay/packages"
  _HI_SETTING_LINES=()
  _HI_SETTING_PENDING=()
  config_packages_groups
  collect_setting_lines
  printf "GROUPLINES:%s\n" "${_HI_SETTING_LINES[*]:-}" | tee "$_hi_dir/verdict"
'

# _hi_groups_pty <label> <input> [settings-line] - run config_packages_groups
# under a pty with <input> (printf %b, so \n and \004 work) on its stdin.
# Transcript lands in $_HI_WORKDIR/<label>.groups.out. Non-zero when the child
# had to be killed, which is the regression this is here to catch.
# _hi_pty_run <child-script> <suffix> <label> <input> <line> [args...] - the
# pty rig _hi_groups_pty and _hi_cfg_pty both run: a scratch settings.sh, the
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

function _hi_groups_pty() { _hi_pty_run "$_HI_GROUPS_CHILD" groups "$1" "$2" "${3:-}"; }

# a pty writes CR-LF, so all three readers normalise before matching. The
# marker is deliberately not anchored to the start of a line: `read -p` leaves
# the cursor on its prompt, so when the loop exits on EOF the marker is
# printed onto the tail of that same prompt line.
function _hi_groups_prompts() {
  tr '\r' '\n' <"$_HI_WORKDIR/$1.groups.out" | grep -c 'Toggle which groups' || true
}
function _hi_groups_finished() {
  [ -s "$_HI_WORKDIR/$1/verdict" ] || tr '\r' '\n' <"$_HI_WORKDIR/$1.groups.out" | grep -q 'GROUPLINES:'
}
# _hi_pty_field <label> <suffix> <tag> [capture] - the field after <tag> on
# a pty transcript's tail line, CR-normalised first (a pty writes CR-LF) -
# everything to the end of the line by default, or just what <capture>
# matches (a sed bracket expression body) when the tag's value can have
# trailing text of its own. The one shape behind _hi_groups_pty_lines,
# _hi_cfg_rc, and _hi_cfg_lines. The child also writes that line to
# <label>/verdict, which is read first: a BSD pty can drop the last output of
# a child that exits at once, and the transcript is only the fallback.
function _hi_pty_field() {
  local src="$_HI_WORKDIR/$1/verdict"
  [ -s "$src" ] || src="$_HI_WORKDIR/$1.$2.out"
  tr '\r' '\n' <"$src" | sed -n "s/.*$3\\(${4:-.*}\\).*/\\1/p" | head -1
}
function _hi_groups_pty_lines() { _hi_pty_field "$1" groups 'GROUPLINES:'; }

# eight junk answers, three prompts: the bound, not the patience - and the
# set it gives up on is the one it started with, the default, so nothing is
# written
function test_packages_groups_stops_asking_for_a_name() {
  _hi_groups_pty groups_junk 'zz\nyy\nxx\nww\nvv\nuu\ntt\nss\n' || return 1
  _hi_groups_finished groups_junk || return 1
  [ "$(_hi_groups_prompts groups_junk)" -le 3 ] &&
    tr '\r' '\n' <"$_HI_WORKDIR/groups_junk.groups.out" | grep -q 'no group zz' &&
    [ -z "$(_hi_groups_pty_lines groups_junk)" ]
}

# EOF is not an answer: one prompt, then out.
function test_packages_groups_ends_on_eof() {
  _hi_groups_pty groups_eof '\004' || return 1
  _hi_groups_finished groups_eof || return 1
  [ "$(_hi_groups_prompts groups_eof)" -le 1 ]
}

# the prompt offers the file's groups, in file order
function test_packages_groups_offers_the_files_groups() {
  _hi_groups_pty groups_offer '\n' || return 1
  tr '\r' '\n' <"$_HI_WORKDIR/groups_offer.groups.out" |
    grep -q 'Toggle which groups (core useful deprecated extras Work)?'
}

# a reply flips each group it names: extras on, useful off, in one answer
function test_packages_groups_toggles_each_named_group() {
  _hi_groups_pty groups_flip 'extras useful\n\n' || return 1
  [ "$(_hi_groups_pty_lines groups_flip)" = "export _HI_PACKAGES_GROUPS='core deprecated extras'" ]
}

# a comma-separated reply is a list too
function test_packages_groups_splits_a_comma_reply() {
  _hi_groups_pty groups_comma_reply 'extras,useful\n\n' || return 1
  [ "$(_hi_groups_pty_lines groups_comma_reply)" = "export _HI_PACKAGES_GROUPS='core deprecated extras'" ]
}

# a reply is matched whatever its case, and the group is toggled under the
# file's own spelling
function test_packages_groups_matches_any_case() {
  _hi_groups_pty groups_case 'WORK\n\n' || return 1
  [ "$(_hi_groups_pty_lines groups_case)" = "export _HI_PACKAGES_GROUPS='core useful deprecated Work'" ]
}

# every group toggled off is `none`, written out
function test_packages_groups_all_off_is_none() {
  _hi_groups_pty groups_alloff 'core useful deprecated\n\n' || return 1
  [ "$(_hi_groups_pty_lines groups_alloff)" = "export _HI_PACKAGES_GROUPS='none'" ]
}

# ...and toggling back to the shipped set writes nothing
function test_packages_groups_back_to_the_default_writes_nothing() {
  _hi_groups_pty groups_back 'core\n\n' "export _HI_PACKAGES_GROUPS='useful deprecated'" || return 1
  _hi_groups_finished groups_back || return 1
  [ -z "$(_hi_groups_pty_lines groups_back)" ]
}

# a reply naming one unknown group toggles none of it, and a rejected answer
# must not poison the ones after it: extras is flipped once, by the second
# reply, not twice
function test_packages_groups_takes_a_name_after_a_rejection() {
  _hi_groups_pty groups_recover 'extras zz\nextras\n\n' || return 1
  tr '\r' '\n' <"$_HI_WORKDIR/groups_recover.groups.out" | grep -q 'no group zz' || return 1
  [ "$(_hi_groups_pty_lines groups_recover)" = "export _HI_PACKAGES_GROUPS='core useful deprecated extras'" ]
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
# (_HI_DISABLE_LEAD_SPACE=1, _HI_PROMPT_TOOL=hi) is on only when its
# on-value is. setting_on is the one reader of both, and _hi_setting_flip
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
  [[ "$out" == *"export _HI_PROMPT_TOOL=hi"* ]]
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

function test_every_preset_names_only_vocabulary() {
  local row values pair vocab
  vocab="$(_hi_preset_vocab)"
  # shellcheck disable=SC2153 # _HI_PRESETS is configure.sh's table, not a typo of --preset's var
  for row in "${_HI_PRESETS[@]}"; do
    values="${row##*|}"
    for pair in $values; do
      case "$vocab" in *"${pair%%=*}"*) ;; *) return 1 ;; esac
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
  config_shell settings "$_HI_SETTINGS" "export _HI_DISABLE_EDITORS=1" "export _HI_MAX_WIDTH=120"
  _HI_SETTING_LINES=()
  _HI_SETTING_PENDING=()
  run_configure balanced </dev/null
}

function test_preset_run_writes_the_preset() {
  local block
  _hi_settings_fixture preset_run _hi_preset_run
  block="$(grep -F "$_HI_MARKER" "$(_hi_fixture_settings preset_run)")"
  [[ "$block" == *"export _HI_PACKAGES_GROUPS='core,deprecated'"* &&
    "$block" == *"export _HI_MAX_WIDTH=120"* && "$block" != *"_HI_DISABLE_EDITORS"* ]]
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

# every editor is presence-gated in common/aliases.sh itself (a box without
# the tool leaves its alias undefined), which _hi_editors_preview reads rather
# than restates - so each line only needs to be there when the tool is.
function test_editors_preview_names_every_override() {
  local out
  out="$(_hi_editors_preview)"
  if command -v nano >/dev/null 2>&1; then
    [[ "$out" == *"nano --rcfile $_HI_NANORC"* ]] || return 1
  fi
  if command -v emacs >/dev/null 2>&1; then
    [[ "$out" == *"emacs -nw -q -l $_HI_EMACSRC"* ]] || return 1
  fi
  if command -v micro >/dev/null 2>&1; then
    [[ "$out" == *"micro -> micro -backup false"* ]] || return 1
  fi
  # each name carries the rc of the binary behind it: nvim answers to both
  # `vim` and `nvim` and reads init.lua, vim reads vimrc
  if command -v nvim >/dev/null 2>&1; then
    [[ "$out" == *"nvim  -> "* && "$out" == *"-u $_HI_NVIMRC"* ]] || return 1
  elif command -v vim >/dev/null 2>&1; then
    [[ "$out" == *"-u $_HI_VIMRC"* ]] || return 1
  fi
  if command -v hx >/dev/null 2>&1; then
    [[ "$out" == *"hx    -> "* && "$out" == *"-c $_HI_HELIXRC"* ]] || return 1
  fi
}

# vim has no second spelling left to drift out of step:
# _hi_editors_preview sources common/aliases.sh itself and reads the alias
# back (same trick as load.sh's _hi_session_editor), so what pins them is
# behaviour, not text - the preview's line for <tool> must be exactly what
# sourcing the alias produces. tests/config/alias_fallthrough_test.sh keeps
# the textual pin for bat, whose preview is not built this way.
function test_editor_preview_matches_its_alias() {
  local tool="$1" from_alias from_preview
  from_alias="$(
    _HI_DISABLE_EDITORS=0
    # shellcheck disable=SC2031 # lives and dies in this $( )
    # shellcheck source=/dev/null # common/aliases.sh, or the copy in the overlay
    # (no apostrophe in a comment inside a $( ): bash 3.2 reads it as a quote)
    source "$_HI_ALIASES" >/dev/null 2>&1
    alias "$tool" 2>/dev/null
  )"
  [ -n "$from_alias" ] || {
    _hi_cecho " | no $tool alias to compare" "$RED"
    return 1
  }
  eval "from_alias=${from_alias#*=}"
  from_preview="$(_hi_editors_preview | sed -n "s/^$tool *-> //p")"
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
    PATH="$dir:$(_hi_real_path preview_tools bash sh dirname cat tr sed awk grep uname hostname)" _hi_prompt_tool_preview)"
  [[ "$out" == *"the first of starship a target has"* ]]
}

# with the prompt off there is nothing for the setting to choose between,
# and the preview says so rather than listing programs
function test_prompt_tool_preview_is_moot_with_the_prompt_off() {
  local _HI_SETTINGS="$_HI_WORKDIR/prompt-tool-off.settings.sh" out
  printf 'export _HI_DISABLE_PROMPT=1\n' >"$_HI_SETTINGS"
  out="$(_hi_prompt_tool_preview)"
  [[ "$out" == "moot while the prompt is off"* ]] || _hi_because "preview: $out"
}

function test_prompt_tool_preview_reports_none() {
  local out
  mkdir -p "$_HI_WORKDIR/preview_none" "$_HI_WORKDIR/preview_home"
  out="$(HOME="$_HI_WORKDIR/preview_home" XDG_CONFIG_HOME="$_HI_WORKDIR/preview_home" \
    PATH="$(_hi_real_path preview_tools bash sh dirname cat tr sed awk grep uname hostname):$_HI_WORKDIR/preview_none" _hi_prompt_tool_preview)"
  [[ "$out" == *"no prompt program is installed here"* ]]
}

# the preview renders the groups it is handed, not the ones configured: a
# group that is off in the file's setting shows when named
function test_groups_preview_renders_the_candidate() {
  _hi_load_preview_sources
  local out
  printf '[mine]\nsh\n' >"$_HI_WORKDIR/groups_fixture"
  out="$(_HI_PACKAGES="$_HI_WORKDIR/groups_fixture" _hi_packages_groups_preview mine)"
  [[ "$(_hi_strip_ansi "$out")" == *" sh "* ]]
}

# an empty render is a real answer - every group off, or the named ones
# silent - and the preview says so rather than handing show_preview a blank
# to drop
function test_groups_preview_says_when_nothing_shows() {
  _hi_load_preview_sources
  local out
  printf '[mine]\nsh\n' >"$_HI_WORKDIR/groups_fixture"
  # the candidate is an argument, not a global the caller sets; the fixture
  # file is scoped to the render itself, not to the strip around it
  out="$(_HI_PACKAGES="$_HI_WORKDIR/groups_fixture" _hi_packages_groups_preview none)"
  [[ "$(_hi_strip_ansi "$out")" == *"these groups show nothing here"* ]] || return 1
  out="$(_HI_PACKAGES="$_HI_WORKDIR/groups_fixture" _hi_packages_groups_preview)"
  [[ "$(_hi_strip_ansi "$out")" == *"these groups show nothing here"* ]]
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
# config_preset, and the intro are all `[ -t 0 ]`-gated the same way
# the groups loop is, and the same pty harness reaches them. The child is
# _HI_GROUPS_CHILD's shape generalised - point the settings at a scratch dir,
# run the one configure function named on its argv with the pty as stdin, and
# report the exit code, the preset-final flag, and the collected lines on one
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
  # the editor rcs an overlay carries, the only ones common/aliases.sh flags
  mkdir -p "$_hi_dir/overlay"
  : >"$_hi_dir/overlay/nanorc"
  _HI_NANORC="$_hi_dir/overlay/nanorc"
  _HI_CONFIG_DIR="$_hi_dir/overlay"
  _HI_SETTINGS="$_hi_dir/overlay/settings.sh"
  _HI_SETTING_LINES=()
  _HI_SETTING_PENDING=()
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
# the wrong number
function _hi_item() {
  local i _HI_SETTINGS=/dev/null
  _HI_SETTING_PENDING=()
  _hi_header_edit_load
  _hi_menu_list >/dev/null
  for i in "${!_HI_MENU_ITEMS[@]}"; do
    [ "${_HI_MENU_ITEMS[$i]}" = "$1" ] || continue
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
  _hi_cfg_pty hdr_list 's\n' "export _HI_HEADER_ORDER='check gitid'" config_hub || return 1
  _hi_cfg_has hdr_list "$w) [x] check" &&
    _hi_cfg_has hdr_list "$((w + 1))) [x] gitid" &&
    _hi_cfg_has hdr_list "$((w + 2))) [ ] utc"
}

# the package groups item opens the groups loop; useful is toggled off
function test_menu_opens_the_package_groups() {
  _hi_cfg_pty hdr_groups "$(_hi_item groups)\nuseful\n\ns\n" '' config_hub || return 1
  [[ "$(_hi_cfg_lines hdr_groups)" == *"export _HI_PACKAGES_GROUPS='core deprecated'"* ]]
}

# a feature row flips and says so under the list, with its preview
# The indices here are positions in $_HI_FEATURE_PROMPTS, so inserting a row
# above the one a case means shifts it: _HI_DISABLE_EDITORS is 4 and
# _HI_DISABLE_ENV_STATUS 3 because the greeting row sits at 1, under the
# header's.
function test_menu_feature_toggles_and_previews() {
  _hi_cfg_pty feat_toggle "$(_hi_item 'row|_HI_FEATURE_PROMPTS|4')\ns\n" '' config_hub || return 1
  _hi_cfg_has feat_toggle "editor config overrides: now off" &&
    { ! command -v nano >/dev/null 2>&1 || _hi_cfg_has feat_toggle "nano --rcfile"; } &&
    [[ "$(_hi_cfg_lines feat_toggle)" == *"export _HI_DISABLE_EDITORS=1"* ]]
}

# The environment segment sits between git status and the editors. Its preview
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

function test_menu_toggles_hi_prompt() {
  _hi_cfg_pty pe_star "$(_hi_item 'row|_HI_PROMPT_PROMPTS|1')\ns\n" '' config_hub || return 1
  _hi_cfg_has pe_star "hi's own prompt: now on" &&
    [[ "$(_hi_cfg_lines pe_star)" == *"export _HI_PROMPT_TOOL=hi"* ]]
}

# ...and back off: an opt-in switched off clears its line rather than
# writing an off-value
function test_menu_toggles_hi_prompt_off() {
  _hi_cfg_pty pe_star_off "$(_hi_item 'row|_HI_PROMPT_PROMPTS|1')\ns\n" 'export _HI_PROMPT_TOOL=hi' config_hub || return 1
  _hi_cfg_has pe_star_off "hi's own prompt: now off" && _hi_cfg_has pe_star_off "CFGLINES=" &&
    [[ "$(_hi_cfg_lines pe_star_off)" != *"_HI_PROMPT_TOOL"* ]]
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
    [[ "$block" == *"export _HI_DISABLE_HEADER=1"* && "$block" == *"export _HI_DISABLE_LOCAL=1"* ]]
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

# one screen holds every group - no submenu to open - under the preview box
function test_menu_lists_every_group() {
  _hi_cfg_pty hub_all 's\n' '' run_configure "" || return 1
  _hi_cfg_has hub_all "preview" &&
    _hi_cfg_has hub_all "Editors" &&
    _hi_cfg_has hub_all "Header - the preview's rows" &&
    _hi_cfg_has hub_all "package groups" &&
    _hi_cfg_has hub_all "bash prompt ends with" &&
    _hi_cfg_has hub_all "Advanced" &&
    _hi_cfg_has hub_all "24-bit color" &&
    _hi_cfg_has hub_all "CFGQUIT=none"
}

# The layout, pinned at 80 columns and at 40 the way the header's width is
# ($_HI_TERM_COLS): no line of the run is wider than the terminal, a narrow
# one cutting help text rather than wrapping it, and the groups draw in their
# order - what a setting changes, the header's first, Advanced last, apart
function _hi_menu_layout_at() {
  local w="$1" label="layout_$1" line len over=0 heads
  _HI_TERM_COLS="$w" _hi_cfg_pty "$label" 's\n' '' run_configure "" || return 1
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
  heads="$(_hi_strip_ansi "$(<"$_HI_WORKDIR/$label.cfg.out")" | tr -d '\r' |
    sed -E -n 's/^ (Header|Prompt|Editors|Aliases|This machine)( - .*)?$/\1/p; s/^ [^ ]+ Advanced .*/Advanced/p' | paste -sd, -)"
  [ "$heads" = "Header,Prompt,Editors,Aliases,This machine,Advanced" ] || {
    _hi_cecho " | the groups at $w columns: [$heads]" "$RED"
    return 1
  }
  [ "$over" = 0 ]
}
function test_menu_layout_at_80() { _hi_menu_layout_at 80; }
function test_menu_layout_at_40() { _hi_menu_layout_at 40; }

# a value away from its default says the default beside it; one at it does not
function test_menu_value_shows_its_default() {
  _HI_TERM_COLS=80 _hi_cfg_pty hub_def 's\n' "export _HI_PACKAGES_GROUPS='core'" run_configure "" || return 1
  _hi_cfg_has hub_def "package groups        core (default core useful deprecated)" &&
    ! _hi_cfg_has hub_def "(default 80)"
}

function run_configure_tests() {
  _hi_workdir configuretest
  # the editor configs an overlay carries: without them no editor has an alias
  # for the previews to read back
  mkdir -p "$_HI_CONFIG_DIR"
  local _hi_f
  for _hi_f in vimrc init.lua config.toml nanorc init.el; do : >"$_HI_CONFIG_DIR/$_hi_f"; done
  export _HI_VIMRC="$_HI_CONFIG_DIR/vimrc" _HI_NVIMRC="$_HI_CONFIG_DIR/init.lua" _HI_HELIXRC="$_HI_CONFIG_DIR/config.toml" \
    _HI_NANORC="$_HI_CONFIG_DIR/nanorc" _HI_EMACSRC="$_HI_CONFIG_DIR/init.el"

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
  _hi_check "Package groups: an existing value survives" test_packages_groups_keeps_a_configured_value
  _hi_check "Package groups: commas are written as spaces" test_packages_groups_normalises_commas
  _hi_check "Package groups: the default set is not written" test_packages_groups_does_not_write_the_default
  _hi_check "Package groups: none is written out" test_packages_groups_writes_none
  _hi_check "Package groups: kept when the check is off" test_packages_groups_kept_when_the_check_is_off
  _hi_check "Package groups: loads its own default" test_packages_groups_loads_its_own_default
  _hi_check "Replaces a different shebang" test_shebang_replaces_a_different_one_and_keeps_content
  _hi_check "_hi_header_edit_preset refuses a stranger" test_header_edit_preset_refuses_a_stranger
  _hi_check "...and turns on a preset's words, in its order" test_header_edit_preset_turns_on_its_words_in_order
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
  _hi_check "Editors preview names every override" test_editors_preview_names_every_override
  if command -v nvim >/dev/null 2>&1 || command -v vim >/dev/null 2>&1; then
    _hi_check "The vim preview matches its alias" test_editor_preview_matches_its_alias vim
  else
    _hi_skip "The vim preview matches its alias" "no nvim or vim"
  fi
  if command -v nvim >/dev/null 2>&1; then
    _hi_check "...and the nvim preview matches its own" test_editor_preview_matches_its_alias nvim
  else
    _hi_skip "...and the nvim preview matches its own" "no nvim"
  fi
  if command -v hx >/dev/null 2>&1; then
    _hi_check "...and the hx preview matches its own" test_editor_preview_matches_its_alias hx
  else
    _hi_skip "...and the hx preview matches its own" "no hx"
  fi
  _hi_check "bat preview names the bat it found" test_bat_preview_names_the_bat_it_found
  _hi_check "...and says so when there is none" test_bat_preview_without_bat_says_targets_only
  _hi_check "the prompt preview names the programs installed here" test_prompt_tool_preview_names_what_is_installed
  _hi_check "...and says when there are none" test_prompt_tool_preview_reports_none
  _hi_check "...and that it is moot with the prompt off" test_prompt_tool_preview_is_moot_with_the_prompt_off
  _hi_check "eza/exa preview names the ls it aliases" test_eza_preview_names_the_ls_it_aliases
  _hi_check "Env segment preview draws the live segment" test_env_status_preview_draws_the_live_segment
  _hi_check "...and a sample with nothing active" test_env_status_preview_samples_with_nothing_active
  _hi_check "Groups preview renders the candidate groups" test_groups_preview_renders_the_candidate
  _hi_check "...and says when they show nothing" test_groups_preview_says_when_nothing_shows

  # Every pty case fans out together: each drives its own child under its own
  # $_HI_WORKDIR/<label> and the children re-source configure.sh themselves,
  # so nothing in this shell is shared - and thirty-odd of them at a second
  # apiece would be this suite's whole wall clock run one at a time.
  # The package-groups prompts belong to the section above; they sit here
  # because they are pty cases too.
  _hi_h2 "Testing: the interactive arms and the menu (pty)"
  _hi_par_begin "pty cases"
  _hi_par_check_capable pty "Package groups: junk stops the loop" test_packages_groups_stops_asking_for_a_name
  _hi_par_check_capable pty "Package groups: EOF ends the prompt" test_packages_groups_ends_on_eof
  _hi_par_check_capable pty "Package groups: offers the file's groups" test_packages_groups_offers_the_files_groups
  _hi_par_check_capable pty "Package groups: a reply toggles each name" test_packages_groups_toggles_each_named_group
  _hi_par_check_capable pty "Package groups: a comma reply is split" test_packages_groups_splits_a_comma_reply
  _hi_par_check_capable pty "Package groups: a reply matches any case" test_packages_groups_matches_any_case
  _hi_par_check_capable pty "Package groups: all off is none" test_packages_groups_all_off_is_none
  _hi_par_check_capable pty "Package groups: back to the default writes nothing" test_packages_groups_back_to_the_default_writes_nothing
  _hi_par_check_capable pty "Package groups: a name lands after a rejection" test_packages_groups_takes_a_name_after_a_rejection
  _hi_par_check_capable pty "ask_value takes a typed number" test_ask_value_takes_a_typed_number
  _hi_par_check_capable pty "ask_value rejects junk and keeps current" test_ask_value_rejects_junk_and_keeps_current
  _hi_par_check_capable pty "ask_value: the typed default clears the override" test_ask_value_typed_default_clears_the_override
  _hi_par_check_capable pty "Truecolor words map both ways" test_truecolor_maps_its_words
  _hi_par_check_capable pty "Preset question: Enter keeps current" test_preset_question_enter_keeps_current
  _hi_par_check_capable pty "Preset question: a stranger is refused, run continues" test_preset_question_refuses_a_stranger_and_carries_on
  _hi_par_check_capable pty "Preset shorthand seeds the run" test_preset_shorthand_seeds_the_run
  _hi_par_check_capable pty "Menu: every group on one screen" test_menu_lists_every_group
  _hi_par_check_capable pty "Menu: fits 80 columns, groups in order" test_menu_layout_at_80
  _hi_par_check_capable pty "Menu: fits 40 columns, groups in order" test_menu_layout_at_40
  _hi_par_check_capable pty "Menu: a changed value names its default" test_menu_value_shows_its_default
  _hi_par_check_capable pty "Menu: a feature toggles and previews" test_menu_feature_toggles_and_previews
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
  _hi_par_check_capable pty "Menu: package groups opens its loop" test_menu_opens_the_package_groups
  _hi_par_check_capable pty "Menu: hidden addresses" test_menu_takes_hidden_addresses
  _hi_par_check_capable pty "Menu: hi's prompt toggles" test_menu_toggles_hi_prompt
  _hi_par_check_capable pty "Menu: hi's prompt toggles back off" test_menu_toggles_hi_prompt_off
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
