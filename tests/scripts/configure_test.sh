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
  # the packer, with the files it sources, and the shipped plugins rows,
  # which hi.sh reads under $_HI_ROOT
  mkdir -p "$_hi_dir/config" "$_hi_dir/scripts"
  for _hi_part in "${_HI_LAUNCHER%/*}"/scripts/pack*.sh "${_HI_LAUNCHER%/*}/scripts/zshrc.sh"; do
    ln -sfn "$_hi_part" "$_hi_dir/scripts/${_hi_part##*/}"
  done
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

_HI_MENU_EVERY_TITLE="hi --configure,hi --configure: Header,hi --configure: Header cells"

_HI_MENU_EVERY_TITLE="$_HI_MENU_EVERY_TITLE,hi --configure: Package check,hi --configure: Prompt"

_HI_MENU_EVERY_TITLE="$_HI_MENU_EVERY_TITLE,hi --configure: Plugins,hi --configure: Plugins: cli"

_HI_MENU_EVERY_TITLE="$_HI_MENU_EVERY_TITLE,hi --configure: Aliases,hi --configure: Advanced,hi --configure"

# _hi_item <kind> - the number the menu gives an item ("word|0" the first
# header item, "end|bash", "width", ...), read off the list itself rather
# than counted by hand, so a row added above it cannot leave a case typing
# the wrong number. The list is the same for every case, so it is built once,
# ahead of the batches: a build is some thirty forks, and the case that
# walks every row paid them per row.
_HI_ITEM_LIST=()

function _hi_items_load() {
  # the plugins number by what has a file, so under the overlay the pty
  # child ($_HI_CFG_CHILD) makes: nano's rc alone
  _hi_read_lines _HI_ITEM_LIST < <(
    _HI_SETTINGS=/dev/null
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

# _hi_configure_begin - what every part of this suite starts from, and the tally
function _hi_configure_begin() {
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
  _hi_suite_begin
}

function run_configure_tests() {
  _hi_configure_begin

  _hi_h1 "Testing scripts/configure.sh's reusable logic"

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

  _hi_suite_end "configure.sh logic"
}

# a part (configure_*_test.sh) sources this file for what is above and runs its own
[ -n "${_HI_CONFIGURE_PART:-}" ] || run_configure_tests
