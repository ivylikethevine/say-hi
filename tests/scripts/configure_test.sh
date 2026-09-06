#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Unit tests for hi --configure's settings wizard - scripts/configure.sh - and
# the rc.sh/table.sh helpers it and install.sh's own rc handling share
# (config_shell, tmpdir_line, check_one_config, check_overlay_configs,
# _hi_visible_len). Split out of tests/scripts/install_test.sh, which had grown
# to cover two scripts at once: this half is everything a plain install's
# second stage, or a later `hi --configure`, touches - every question, its
# validation, and the one write to $_HI_SETTINGS. install_test.sh keeps the
# other half: install_tree's packaging-mode DESTDIR layout and the
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

function test_config_shell_fresh_insert() {
  local target="$_HI_WORKDIR/fresh"
  : >"$target"
  config_shell "fresh block" "$target" "line one" "line two"
  grep -qF "line one" "$target" && grep -qF "line two" "$target" && grep -qF "$_HI_MARKER" "$target"
}

function test_config_shell_idempotent() {
  local target="$_HI_WORKDIR/idempotent" before after
  : >"$target"
  config_shell idempotent "$target" "line one"
  before="$(cat "$target")"
  config_shell idempotent "$target" "line one"
  after="$(cat "$target")"
  [ "$before" = "$after" ]
}

function test_config_shell_repairs_stale_line() {
  local target="$_HI_WORKDIR/repair"
  : >"$target"
  config_shell repair "$target" "old line"
  config_shell repair "$target" "new line"
  grep -qF "new line" "$target" && ! grep -qF "old line" "$target"
}

function test_config_shell_preserves_unrelated_content() {
  local target="$_HI_WORKDIR/preserve"
  printf '%s\n' "# a user comment" "alias ll='ls -la'" >"$target"
  config_shell preserve "$target" "hi line"
  grep -qF "# a user comment" "$target" && grep -qF "alias ll='ls -la'" "$target" && grep -qF "hi line" "$target"
}

function test_config_shell_skips_empty_args() {
  local target="$_HI_WORKDIR/emptyargs"
  : >"$target"
  config_shell emptyargs "$target" "" "real line" ""
  [ "$(grep -cF "$_HI_MARKER" "$target")" -eq 1 ]
}

# the block goes at the end, after whatever the file already had
function test_config_shell_appends_at_the_end() {
  local target="$_HI_WORKDIR/appends"
  printf '%s\n' "first line" >"$target"
  config_shell appends "$target" "hi line"
  [[ "$(tail -1 "$target")" == *"hi line"* ]]
}

# mode read via ls's first field - stat's flags differ GNU/BSD
# shellcheck disable=SC2012 # the paths are fixtures this suite just wrote
function test_config_shell_preserves_target_mode() {
  local target="$_HI_WORKDIR/mode" before
  printf 'content\n' >"$target"
  chmod 640 "$target"
  before="$(ls -l "$target" | awk '{ print $1 }')"
  config_shell mode "$target" "hi line"
  [ "$(ls -l "$target" | awk '{ print $1 }')" = "$before" ]
}

# a dotfile manager's hardlinked ~/.bashrc must not be severed by a mv
function test_config_shell_preserves_hardlinks() {
  local target="$_HI_WORKDIR/hardlink" twin="$_HI_WORKDIR/hardlink.twin"
  printf 'content\n' >"$target"
  ln "$target" "$twin"
  config_shell hardlink "$target" "hi line"
  grep -qF "hi line" "$twin"
}

function test_config_shell_backs_up_on_first_insert() {
  local target="$_HI_WORKDIR/backup"
  printf 'original content\n' >"$target"
  config_shell backup "$target" "hi line"
  [ -f "$target.hi-orig" ] && [ "$(cat "$target.hi-orig")" = "original content" ]
}

# the backup stays the pre-hi original - a rerun must not overwrite it
function test_config_shell_backup_survives_reruns() {
  local target="$_HI_WORKDIR/backup2"
  printf 'original\n' >"$target"
  config_shell backup2 "$target" "hi line"
  config_shell backup2 "$target" "another line"
  [ "$(cat "$target.hi-orig")" = "original" ]
}

# nothing to preserve, nothing to back up
function test_config_shell_no_backup_for_empty_target() {
  local target="$_HI_WORKDIR/backup3"
  : >"$target"
  config_shell backup3 "$target" "hi line"
  [ ! -e "$target.hi-orig" ]
}

# Nothing is spliced into common/paths.sh any more - the settings live in
# $_HI_SETTINGS, which every entry point sources *ahead* of paths.sh so that
# paths.sh's local-only gate can read them. That ordering is the load-bearing
# property now, and it's spread across three files (no single include line is
# valid in sh, bash, zsh and fish alike), so assert it in each.
# Comment lines are filtered out first: both files explain themselves in prose
# that names the very files being looked for, and a comment mentioning paths.sh
# above the code that sources settings.sh would read as the wrong order.
# _hi_before is the harness's ordering assertion; the only thing this check
# adds is dropping comment lines first, so a mention in a comment above the
# real source line cannot answer for it.
function _hi_sources_settings_before_paths() {
  _hi_before "$(grep -v '^[[:space:]]*#' "$1")" 'settings\.sh' 'paths\.sh'
}

function test_core_sources_settings_first() {
  _hi_sources_settings_before_paths "$_HI_ROOT/common/core.sh"
}

function test_fish_config_sources_settings_first() {
  _hi_sources_settings_before_paths "$_HI_ROOT/common/config.fish"
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
# the file is sourced by sh, bash, zsh and fish alike
function test_prompt_ends_quotes_what_it_writes() {
  local out
  out="$(_hi_collected_lines prompt_quote "export _HI_PROMPT_END_BASH='>'")"
  [[ "$out" == *"_HI_PROMPT_END_BASH='>'"* ]]
}

# the prompt is off, so what it ends with is moot right now - and kept, so
# turning the prompt back on finds the separator where it was left. The old
# wizard dropped a moot value with the section it skipped; the collector
# has no sections to skip.
function test_prompt_ends_kept_when_the_prompt_is_off() {
  local out
  out="$(_hi_collected_lines prompt_off "export _HI_DISABLE_PROMPT=1" "export _HI_PROMPT_END_ZSH='::'")"
  [[ "$out" == *"export _HI_DISABLE_PROMPT=1"* && "$out" == *"export _HI_PROMPT_END_ZSH='::'"* ]]
}

function test_packages_palette_keeps_an_existing_override() {
  local out
  out="$(_hi_section_lines palette_keep config_packages_palette "export _HI_PACKAGES_PALETTE=warm")"
  [[ "$out" == *"export _HI_PACKAGES_PALETTE=warm"* ]]
}

# cool is header.sh's own default, so writing it out would be a line that
# means nothing - the same rule config_max_width and config_packages_floor use
function test_packages_palette_does_not_write_the_default() {
  local out
  out="$(_hi_section_lines palette_default config_packages_palette)"
  [ -z "$(printf '%s' "$out" | tr -d ' ')" ]
}

function test_color_scheme_keeps_an_existing_override() {
  local out
  out="$(_hi_section_lines scheme_keep config_color_scheme "export _HI_COLOR_SCHEME=onedark")"
  [[ "$out" == *"export _HI_COLOR_SCHEME=onedark"* ]]
}

# no scheme is the default, so nothing is ever written for it
function test_color_scheme_does_not_write_the_default() {
  local out
  out="$(_hi_section_lines scheme_default config_color_scheme)"
  [ -z "$(printf '%s' "$out" | tr -d ' ')" ]
}

# five rows, one per scheme, every one but default painted with the 24-bit
# tail (forced, so the swatches show what a capable terminal would)
function test_color_scheme_preview_lists_every_scheme() {
  local out scheme
  out="$(_hi_color_scheme_preview)"
  for scheme in default catppuccin monokai onedark vscode; do
    [[ "$out" == *"$scheme"* ]] || return 1
  done
  [[ "$out" == *";38;2;"* && "$out" == *"brcyan"* ]] || return 1
  [ "$(printf '%s\n' "$out" | grep -c ';38;2;')" -eq 4 ]
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

# the check itself is off, so which colors it would use is moot - the header
# editor does not offer the palette then, and the stored value is kept for
# when 'check' comes back
function test_packages_palette_kept_when_the_check_is_off() {
  local out
  out="$(_hi_collected_lines palette_off \
    "export _HI_HEADER_ORDER='gitid'" "export _HI_PACKAGES_PALETTE=warm")"
  [[ "$out" == *"export _HI_HEADER_ORDER='gitid'"* && "$out" == *"export _HI_PACKAGES_PALETTE=warm"* ]]
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
  local row words
  _hi_load_preview_sources
  for row in "${_HI_HEADER_PRESETS[@]}"; do
    words="${row##*|}"
    [ -z "$words" ] && continue
    _hi_is_header_order "$words" || return 1
  done
  [ "$(preset_names)" != "" ]
}

# The versioning contract: init makes a repo with one (possibly empty) first
# commit and is idempotent; overlay_commit turns settings writes into history
# only where a repo already exists, and never creates one. Each case gets a
# fresh scratch $_HI_CONFIG_DIR; the identity fallback keeps the commits
# working on a machine that never ran `git config`.
function _hi_overlay_commits() {
  git -C "$1" rev-list --count HEAD 2>/dev/null || echo 0
}

function test_overlay_init_creates_a_repo_with_a_first_commit() {
  local dir="$_HI_WORKDIR/ovl-init"
  mkdir -p "$dir"
  printf 'export X=1\n' >"$dir/settings.sh"
  (_HI_CONFIG_DIR="$dir" overlay_init >/dev/null) &&
    [ -d "$dir/.git" ] && [ "$(_hi_overlay_commits "$dir")" = 1 ] &&
    git -C "$dir" ls-files | grep -qx settings.sh
}

function test_overlay_init_is_idempotent() {
  local dir="$_HI_WORKDIR/ovl-idem"
  mkdir -p "$dir"
  (_HI_CONFIG_DIR="$dir" overlay_init >/dev/null) &&
    (_HI_CONFIG_DIR="$dir" overlay_init >/dev/null) &&
    [ "$(_hi_overlay_commits "$dir")" = 1 ]
}

# The input validators guarding what ask_value will write into settings.sh -
# the single-quote one is what keeps a typed value from ending the sh word the
# written `export NAME='value'` line wraps it in.
function test_validators_hold_their_grammars() {
  _hi_is_number 42 || return 1
  ! _hi_is_number 4.2 || return 1
  ! _hi_is_number '' || return 1
  ! _hi_is_number 4x || return 1
  _hi_is_seconds 2 || return 1
  _hi_is_seconds 0.25 || return 1
  ! _hi_is_seconds .5 || return 1
  ! _hi_is_seconds 2s || return 1
  _hi_has_no_single_quote "plain value" || return 1
  ! _hi_has_no_single_quote "don't" || return 1
  _hi_is_shell_list "login fish bash" || return 1
  _hi_is_shell_list zsh || return 1
  ! _hi_is_shell_list "" || return 1
  ! _hi_is_shell_list "fish csh" || return 1
  _hi_is_packages_palette cool || return 1
  _hi_is_packages_palette warm || return 1
  _hi_is_packages_palette mono || return 1
  ! _hi_is_packages_palette bogus || return 1
  _hi_is_ip_hide none || return 1
  _hi_is_color_scheme default || return 1
  _hi_is_color_scheme catppuccin || return 1
  _hi_is_color_scheme monokai || return 1
  _hi_is_color_scheme onedark || return 1
  _hi_is_color_scheme vscode || return 1
  ! _hi_is_color_scheme solarized || return 1
  ! _hi_is_color_scheme "" || return 1
  _hi_is_ip_hide '172.*' || return 1
  _hi_is_ip_hide '10.* 192.168.?.*' || return 1
  ! _hi_is_ip_hide "" || return 1
  ! _hi_is_ip_hide "172.*;rm" || return 1
  ! _hi_is_ip_hide "all" || return 1
  _hi_is_header_order "utc version localtime arch os cores cpu ram gitid containers jobs pods auth pub uptime check" || return 1
  _hi_is_header_order "check gitid" || return 1
  _hi_is_header_order utc || return 1
  ! _hi_is_header_order "" || return 1
  ! _hi_is_header_order "utc bogus"
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

# the seed half: a fresh init copies the four shipped defaults in for the
# files the user has none of, byte for byte and tracked from the first commit
function test_overlay_init_seeds_the_shipped_defaults() {
  local dir="$_HI_WORKDIR/ovl-seed" f
  mkdir -p "$dir"
  (_HI_CONFIG_DIR="$dir" overlay_init >/dev/null) || return 1
  for f in colors packages vim.rc nano.rc; do
    cmp -s "$_HI_ROOT/settings/$f" "$dir/$f" || {
      _hi_cecho " | $f was not seeded from the tree" "$RED"
      return 1
    }
    git -C "$dir" ls-files | grep -qx "$f" || {
      _hi_cecho " | $f is not in the first commit" "$RED"
      return 1
    }
  done
}

function test_overlay_init_never_overwrites_a_present_file() {
  local dir="$_HI_WORKDIR/ovl-noclobber"
  mkdir -p "$dir"
  printf 'hostname,mine,red\n' >"$dir/colors"
  (_HI_CONFIG_DIR="$dir" overlay_init >/dev/null) || return 1
  [ "$(cat "$dir/colors")" = "hostname,mine,red" ] || return 1
  # the gaps still fill in around it
  cmp -s "$_HI_ROOT/settings/packages" "$dir/packages"
}

function test_overlay_commit_records_a_change_when_tracked() {
  local dir="$_HI_WORKDIR/ovl-commit"
  mkdir -p "$dir"
  (_HI_CONFIG_DIR="$dir" overlay_init >/dev/null) || return 1
  printf 'export Y=2\n' >"$dir/settings.sh"
  (_HI_CONFIG_DIR="$dir" overlay_commit) &&
    [ "$(_hi_overlay_commits "$dir")" = 2 ]
}

function test_overlay_commit_is_a_noop_with_nothing_new() {
  local dir="$_HI_WORKDIR/ovl-noop"
  mkdir -p "$dir"
  (_HI_CONFIG_DIR="$dir" overlay_init >/dev/null) || return 1
  (_HI_CONFIG_DIR="$dir" overlay_commit) &&
    [ "$(_hi_overlay_commits "$dir")" = 1 ]
}

function test_overlay_commit_never_creates_a_repo() {
  local dir="$_HI_WORKDIR/ovl-untracked"
  mkdir -p "$dir"
  printf 'export X=1\n' >"$dir/settings.sh"
  (_HI_CONFIG_DIR="$dir" overlay_commit) &&
    [ ! -d "$dir/.git" ]
}

# settings.sh is sourced by sh, bash, zsh and fish, so line 1 has to be the
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

# config_packages_floor: the only prompt that loops, so the parts worth pinning
# without a pty are the three that do not need one - it keeps an existing floor
# rather than dropping it, it does not restate the shipped default, and a
# zero survives. The loop itself needs a terminal and is skipped when there is
# none, which is what makes these callable here - provided stdin really is
# not one: run by hand from a terminal it would be, and the case would sit at
# the prompt, so it is fed /dev/null explicitly. _hi_settings_fixture
# swallows stdout (its other users assert against the file it wrote), so the
# collected lines go to a file inside the fixture instead - otherwise "no
# lines" and "lines nobody saw" look identical and two of these three would
# pass without asserting anything.
function _hi_floor_run() {
  mkdir -p "$_HI_CONFIG_DIR"
  printf '#!/bin/sh\n%s\n' "$1" >"$_HI_SETTINGS"
  _HI_SETTING_LINES=()
  _HI_SETTING_PENDING=()
  config_packages_floor </dev/null
  collect_setting_lines
  printf '%s\n' ${_HI_SETTING_LINES[@]+"${_HI_SETTING_LINES[@]}"} >"$_HI_CONFIG_DIR/lines.out"
}

function _hi_floor_lines() { cat "$_HI_WORKDIR/$1/config/lines.out" 2>/dev/null; }

function test_packages_floor_keeps_a_configured_value() {
  _hi_settings_fixture floor_keep _hi_floor_run 'export _HI_PACKAGES_MIN_PRIORITY=3'
  [ "$(_hi_floor_lines floor_keep)" = "export _HI_PACKAGES_MIN_PRIORITY=3" ]
}

# 2 is header.sh's own default via ${_HI_PACKAGES_MIN_PRIORITY:-2}, so writing
# it out would be a line that means nothing - the same rule config_max_width
# has for 80.
function test_packages_floor_does_not_write_the_default() {
  _hi_settings_fixture floor_default _hi_floor_run 'export _HI_PACKAGES_MIN_PRIORITY=2'
  [ -f "$_HI_WORKDIR/floor_default/config/lines.out" ] || return 1
  [ -z "$(_hi_floor_lines floor_default | tr -d '[:space:]')" ]
}

# ...and the other side of that rule: 0 is an answer like any other - "put the
# trivia tier back" - so it has to survive as a line rather than being elided as the default.
function test_packages_floor_writes_a_zero() {
  _hi_settings_fixture floor_zero _hi_floor_run 'export _HI_PACKAGES_MIN_PRIORITY=0'
  [ "$(_hi_floor_lines floor_zero)" = "export _HI_PACKAGES_MIN_PRIORITY=0" ]
}

# the check is off, so its depth is moot - the header editor does not offer
# the dial then, and the stored floor is kept for when 'check' comes back
function test_packages_floor_kept_when_the_check_is_off() {
  local out
  out="$(_hi_collected_lines floor_off "export _HI_HEADER_ORDER='gitid'" "export _HI_PACKAGES_MIN_PRIORITY=3")"
  [[ "$out" == *"export _HI_HEADER_ORDER='gitid'"* && "$out" == *"export _HI_PACKAGES_MIN_PRIORITY=3"* ]]
}

# The loop itself, which none of the four cases above can reach: `[ -t 0 ]`
# guards it, so exercising it at all needs a pty - which is how it went
# untested long enough to grow an unbounded retry. An answer that was never a
# number re-asked forever, with no way out but ^C and a full re-render of the
# package check on every pass. What these pin is that it *stops*, by counting
# the prompts rather than trusting a wall clock: a bound that regressed would
# show up as more prompts, not as a slower suite.
#
# $_HI_PTY_FORCED is empty when there is no usable pty - no python3 at all, or
# a python3 without the Unix-only `pty` module - which is why these register
# through `_hi_check_capable pty` and skip yellow rather than fail: the
# backend suites' doctrine, for the same reason.
# shellcheck disable=SC2016 # single quotes on purpose: every expansion in here
# is the child shell's to make, after the pty has put it on the other side
_HI_FLOOR_CHILD='
  _hi_dir="$1"
  source "$_HI_TEST_LIB"
  set --
  source "$_HI_INSTALL"
  _HI_ROOT="$_hi_dir"
  _HI_CONFIG_DIR="$_hi_dir/config"
  _HI_SETTINGS="$_hi_dir/config/settings.sh"
  _HI_SETTING_LINES=()
  _HI_SETTING_PENDING=()
  config_packages_floor
  collect_setting_lines
  printf "FLOORLINES:%s\n" "${_HI_SETTING_LINES[*]:-}"
'

# _hi_floor_pty <label> <input> [settings-line] - run config_packages_floor
# under a pty with <input> (printf %b, so \n and \004 work) on its stdin.
# Transcript lands in $_HI_WORKDIR/<label>.floor.out. Non-zero when the child
# had to be killed, which is the regression this is here to catch.
function _hi_floor_pty() {
  local label="$1" input="$2" line="${3:-}"
  local dir="$_HI_WORKDIR/$label" out="$_HI_WORKDIR/$label.floor.out"
  mkdir -p "$dir/common" "$dir/settings" "$dir/config"
  printf '#!/bin/sh\n%s\n' "$line" >"$dir/config/settings.sh"
  : >"$out"
  printf '%b' "$input" |
    "${_HI_PTY_FORCED[@]}" bash -c "$_HI_FLOOR_CHILD" bash "$dir" >"$out" 2>&1 &
  _hi_wait_pid "$!" "${_HI_CASE_TIMEOUT:-30}" _hi_timed_out "$label" "${_HI_CASE_TIMEOUT:-30}"
  [ "$_HI_WAIT_EXIT" != 124 ]
}

# a pty writes CR-LF, so all three readers normalise before matching. The
# marker is deliberately not anchored to the start of a line: `read -p` leaves
# the cursor on its prompt, so when the loop exits by repeating the value on
# screen the marker is printed onto the tail of that same prompt line.
function _hi_floor_prompts() {
  tr '\r' '\n' <"$_HI_WORKDIR/$1.floor.out" | grep -c 'Lowest package priority' || true
}
function _hi_floor_finished() {
  tr '\r' '\n' <"$_HI_WORKDIR/$1.floor.out" | grep -q 'FLOORLINES:'
}
function _hi_floor_pty_lines() {
  tr '\r' '\n' <"$_HI_WORKDIR/$1.floor.out" | sed -n 's/.*FLOORLINES://p' | head -1
}

# eight junk answers, three prompts: the bound, not the patience.
function test_packages_floor_stops_asking_for_a_number() {
  _hi_floor_pty floor_junk 'zz\nyy\nxx\nww\nvv\nuu\ntt\nss\n' || return 1
  _hi_floor_finished floor_junk || return 1
  [ "$(_hi_floor_prompts floor_junk)" -le 3 ]
}

# EOF is not an answer: one prompt, then out.
function test_packages_floor_ends_on_eof() {
  _hi_floor_pty floor_eof '\004' || return 1
  _hi_floor_finished floor_eof || return 1
  [ "$(_hi_floor_prompts floor_eof)" -le 1 ]
}

# a rejected answer must not poison the ones after it - the reject count
# resets, so this still lands on 3 rather than giving up first. 3, not the
# default: the default is cleared rather than written, which would leave this
# case nothing to see.
function test_packages_floor_takes_a_number_after_a_rejection() {
  _hi_floor_pty floor_recover 'zz\n3\n3\n' || return 1
  [ "$(_hi_floor_pty_lines floor_recover)" = "export _HI_PACKAGES_MIN_PRIORITY=3" ]
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
  # shellcheck disable=SC2012 # fixture paths, mode via ls as elsewhere here
  ls -l "$_HI_SETTINGS" | awk '{ print $1 }' >"$_HI_WORKDIR/shebang_mode.before"
  ensure_settings_shebang
}

# shellcheck disable=SC2012 # fixture paths, mode via ls as above
function test_settings_shebang_preserves_mode() {
  _hi_settings_fixture shebang_mode _hi_shebang_mode
  local before after
  before="$(cat "$_HI_WORKDIR/shebang_mode.before")"
  after="$(ls -l "$(_hi_fixture_settings shebang_mode)" | awk '{ print $1 }')"
  [ "$after" = "$before" ]
}

# the three config_* groups accumulate rather than each calling config_shell,
# because one config_shell call per group against one file would have each
# wipe the other two's lines
function _hi_settings_one_write() {
  local -a _HI_SETTING_LINES=("export _HI_DISABLE_PROMPT=1" "" "export _HI_HEADER_BANNER=0")
  mkdir -p "$_HI_CONFIG_DIR"
  config_shell settings "$_HI_SETTINGS" "${_HI_SETTING_LINES[@]}"
}

function test_config_settings_writes_every_group_at_once() {
  _hi_settings_fixture onewrite _hi_settings_one_write
  local f
  f="$(_hi_fixture_settings onewrite)"
  grep -qF "export _HI_DISABLE_PROMPT=1" "$f" && grep -qF "export _HI_HEADER_BANNER=0" "$f"
}

# the whole point of the overlay: a fresh install leaves the tree untouched, so
# `hi --update`'s git pull still applies and a root-owned tree still works
function test_settings_are_written_outside_the_tree() {
  _hi_settings_fixture outside _hi_shebang_fresh
  [ -f "$(_hi_fixture_settings outside)" ] && [ ! -e "$_HI_WORKDIR/outside/settings/settings.sh" ]
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
  printf 'export _HI_HEADER_BANNER=0\n' >"$target"
  setting_off _HI_HEADER_BANNER "$target" 0
}

# the line as config_shell really writes it: marker-padded, unquoted - the
# exact spelling hi.sh's payload trim has to read correctly
function test_setting_off_reads_marker_padded_line() {
  local target="$_HI_WORKDIR/padded"
  printf '%-45s %s\n' 'export _HI_DISABLE_FOO=1' "$_HI_MARKER" >"$target"
  setting_off _HI_DISABLE_FOO "$target" &&
    [ "$(_hi_setting_get "$target" _HI_DISABLE_FOO)" = 1 ]
}

# _hi_setting_get sources the file for real now rather than hand-scanning
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

# Written even for a tree at the default location: nothing defaults to $HOME
# any more, and a new process with no tree to derive from reads this line or
# nothing at all (GLOSSARY: HI.33)
function test_tmpdir_line_states_the_tree_even_at_home() {
  local out
  out="$(_HI_HOME="$HOME" tmpdir_line sh)"
  [ "$out" = "export _HI_HOME=\"$HOME\"" ]
}

function test_tmpdir_line_posix_variant() {
  local out
  out="$(_HI_HOME=/opt/elsewhere tmpdir_line sh)"
  [ "$out" = 'export _HI_HOME="/opt/elsewhere"' ]
}

function test_tmpdir_line_fish_variant() {
  local out
  out="$(_HI_HOME=/opt/elsewhere tmpdir_line fish)"
  [ "$out" = 'set -gx _HI_HOME "/opt/elsewhere"' ]
}

function test_ask_setting_default_keeps_enabled() {
  local target="$_HI_WORKDIR/ask_enabled"
  : >"$target"
  ask_setting _HI_DISABLE_FOO "" "$target" 1 "" </dev/null
}

function test_ask_setting_default_keeps_disabled() {
  local target="$_HI_WORKDIR/ask_disabled"
  printf 'export _HI_DISABLE_FOO=1\n' >"$target"
  ! ask_setting _HI_DISABLE_FOO "" "$target" 1 "" </dev/null
}

#
# A default-on toggle is on unless its off-value is written; an opt-in
# (_HI_NO_LEAD_SPACE=1, _HI_PROMPT=starship) is on only when its
# on-value is. setting_on is the one reader of both, and ask_prompt_group
# writes both.

function test_setting_on_opt_in_absent_is_off() {
  local target="$_HI_WORKDIR/opt_in_absent"
  : >"$target"
  _HI_SETTING_PENDING=()
  ! setting_on _HI_NO_LEAD_SPACE "$target" 0 1
}

function test_setting_on_opt_in_present_is_on() {
  local target="$_HI_WORKDIR/opt_in_present"
  printf 'export _HI_NO_LEAD_SPACE=1\n' >"$target"
  _HI_SETTING_PENDING=()
  setting_on _HI_NO_LEAD_SPACE "$target" 0 1
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

function test_starship_kept_when_chosen() {
  local out
  out="$(_hi_collected_lines starship "export _HI_PROMPT=starship")"
  [[ "$out" == *"export _HI_PROMPT=starship"* ]]
}

# the section opened with nobody to answer keeps every advanced value,
# quoting included - every question keeps what the file holds
function test_advanced_declined_keeps_every_value() {
  local out
  out="$(_hi_section_lines adv_keep config_advanced \
    "export _HI_TERM_FALLBACK=0" "export _HI_RECENT=0" \
    "export _HI_SHELL_PREFERENCE='zsh login'" "export _HI_ASCII=1" \
    "export _HI_TARGETS_TTL=9" "export _HI_PROBE_TIMEOUT=0.5")"
  [[ "$out" == *"export _HI_TERM_FALLBACK=0"* && "$out" == *"export _HI_RECENT=0"* &&
    "$out" == *"export _HI_SHELL_PREFERENCE='zsh login'"* && "$out" == *"export _HI_ASCII=1"* &&
    "$out" == *"export _HI_TARGETS_TTL=9"* && "$out" == *"export _HI_PROBE_TIMEOUT=0.5"* ]]
}

# and with nothing set, writes nothing - the defaults live in the code
function test_advanced_defaults_write_nothing() {
  [ -z "$(_hi_section_lines adv_default config_advanced | tr -d ' ')" ]
}

# a row whose <needs> command is absent is not asked, and the collector
# carries what the file holds for it rather than dropping it
function test_prompt_group_carries_a_row_it_cannot_ask() {
  local out dir="$_HI_WORKDIR/needs"
  local _HI_SETTINGS="$dir/settings.sh"
  local -a _HI_SETTING_LINES=() _HI_NEEDS_PROMPTS=("_HI_NO_LEAD_SPACE|0|1|| moot?|no-such-command-$$|")
  _HI_SETTING_PENDING=()
  mkdir -p "$dir"
  printf 'export _HI_NO_LEAD_SPACE=1\n' >"$_HI_SETTINGS"
  ask_prompt_group _HI_NEEDS_PROMPTS </dev/null
  [ "${#_HI_SETTING_PENDING[@]}" = 0 ] || return 1
  _hi_collect_group _HI_NEEDS_PROMPTS
  out="${_HI_SETTING_LINES[*]:-}"
  [[ "$out" == *"export _HI_NO_LEAD_SPACE=1"* ]]
}

function test_validators_for_the_advanced_values() {
  _hi_is_shell_list "login zsh bash" && ! _hi_is_shell_list "login sh" && ! _hi_is_shell_list "" &&
    _hi_is_seconds 0.5 && _hi_is_seconds 3 && ! _hi_is_seconds abc &&
    _hi_is_glyph_choice ascii && ! _hi_is_glyph_choice yes
}

# the closing report: what this run wrote against what the block held, as
# +/- lines, read through config_shell's own marker padding
function _hi_diff_run() {
  local -a _HI_SETTING_LINES=("export _HI_DISABLE_PROMPT=1" "export _HI_MAX_WIDTH=120")
  mkdir -p "$_HI_CONFIG_DIR"
  config_shell settings "$_HI_SETTINGS" "export _HI_DISABLE_PROMPT=1" "export _HI_HEADER_BANNER=0"
  settings_diff_before
  settings_diff_report >"$_HI_CONFIG_DIR/diff.out"
}

function test_settings_diff_reports_added_and_removed() {
  local out
  _hi_settings_fixture diff _hi_diff_run
  out="$(cat "$_HI_WORKDIR/diff/config/diff.out")"
  [[ "$out" == *"+ export _HI_MAX_WIDTH=120"* && "$out" == *"- export _HI_HEADER_BANNER=0"* &&
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
  grep -q 'no changes' "$_HI_WORKDIR/diff_same/config/diff.out"
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
    ! grep -qx _HI_IP_HIDE <<<"$vocab"
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
  [[ "$block" == *"export _HI_PACKAGES_MIN_PRIORITY=3"* && "$block" == *"export _HI_DISABLE_NOTIFY=1"* &&
    "$block" == *"export _HI_MAX_WIDTH=120"* && "$block" != *"_HI_DISABLE_EDITORS"* ]]
}

function test_install_rejects_an_unknown_preset() {
  ! bash "$_HI_INSTALL" --features-only --preset nope </dev/null >/dev/null 2>&1
}

function test_visible_len_plain_text() {
  local len
  _hi_visible_len len "hello"
  [ "$len" -eq 5 ]
}

function test_visible_len_strips_color_codes() {
  local colored len
  colored="$(_hi_rendered "${GREEN}hi${NC}")"
  _hi_visible_len len "$colored"
  [ "$len" -eq 2 ]
}

function test_check_one_config_valid_bash() {
  local target="$_HI_WORKDIR/valid.bashrc"
  printf 'echo hi\n' >"$target"
  check_one_config bash "$target" bash -n
}

function test_check_one_config_invalid_bash() {
  local target="$_HI_WORKDIR/invalid.bashrc"
  printf 'if [ 1 = 1 ]; then\n' >"$target" # unterminated if
  ! check_one_config bash "$target" bash -n
}

function test_check_one_config_skips_missing_shell() {
  local target="$_HI_WORKDIR/whatever"
  printf 'irrelevant\n' >"$target"
  check_one_config nope "$target" definitely-not-a-real-shell-xyz
}

# check_overlay_configs: the roster over a scratch overlay. What the fish row
# pins is the reason the function exists - an `if` block in aliases.sh is
# valid sh and invalid fish, and the sh row alone would wave it through.
function _hi_overlay_check_run() { check_overlay_configs; }
# shellcheck disable=SC2016 # $_HI_CONFIG_DIR is the fixture child's to expand
function test_check_overlay_configs_passes_a_clean_overlay() {
  _hi_settings_fixture ov_clean bash -c 'printf "alias ll=\"ls -l\"\n" >"$_HI_CONFIG_DIR/aliases.sh"'
  _hi_settings_fixture ov_clean _hi_overlay_check_run
}
# shellcheck disable=SC2016 # same: expands in the child
function test_check_overlay_configs_catches_sh_only_aliases() {
  _hi_settings_fixture ov_if bash -c 'printf "if true; then alias ll=ls; fi\n" >"$_HI_CONFIG_DIR/aliases.sh"'
  ! _hi_settings_fixture ov_if _hi_overlay_check_run
}
function test_check_overlay_configs_passes_with_no_overlay() {
  _hi_settings_fixture ov_none _hi_overlay_check_run
}

function test_check_one_config_skips_empty_file() {
  local target="$_HI_WORKDIR/empty.bashrc"
  : >"$target"
  check_one_config bash "$target" bash -n
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

# refused/absent sudo on an unwritable bindir must end in instructions, not a
# `set -e` death at the last step of a completed install.
#
# The bindir's mode is what stages the failure, so this needs a run that a mode
# can actually refuse - hence `_hi_check_capable lockout` at the registration
# below. As root the chmod is inert: config_hi's `[ -w ]` answers yes, the link
# is made, and the case fails on a step that worked.
function test_config_hi_degrades_when_sudo_cannot_link() {
  local dir="$_HI_WORKDIR/nosudo" out rc=0
  mkdir -p "$dir/bin"
  printf '#!/bin/bash\n' >"$dir/hi.sh"
  chmod 755 "$dir/hi.sh"
  chmod 555 "$dir/bin"
  out="$(
    function sudo() { return 1; }
    _HI_LAUNCHER="$dir/hi.sh"
    _HI_LINK="$dir/bin/hi"
    config_hi
  )" || rc=$?
  chmod 755 "$dir/bin"
  [ "$rc" -eq 0 ] && [[ "$out" == *"--no-link"* ]] && [ ! -e "$dir/bin/hi" ]
}

# ...and the sudo-less box: the same staging as the refused-sudo case, but
# with a PATH that has no sudo on it at all - the other way into
# link_hi_by_hand. readlink and dirname ride along as real binaries, since
# swapping PATH for the probe takes the whole toolbox with it.
function test_config_hi_degrades_with_no_sudo_at_all() {
  local dir="$_HI_WORKDIR/nosudoatall" farm out rc=0
  farm="$(_hi_real_path nosudo_tools readlink dirname)"
  mkdir -p "$dir/bin"
  printf '#!/bin/bash\n' >"$dir/hi.sh"
  chmod 755 "$dir/hi.sh"
  chmod 555 "$dir/bin"
  out="$(
    hash -r
    # shellcheck disable=SC2030 # subshell-local is exactly the intent
    PATH="$farm"
    _HI_LAUNCHER="$dir/hi.sh"
    _HI_LINK="$dir/bin/hi"
    config_hi
  )" || rc=$?
  chmod 755 "$dir/bin"
  [ "$rc" -eq 0 ] && [[ "$out" == *"--no-link"* ]] && [ ! -e "$dir/bin/hi" ]
}

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

function test_editors_preview_names_both_overrides() {
  local out
  out="$(_hi_editors_preview)"
  [[ "$out" == *"nano --rcfile $_HI_NANORC"* && "$out" == *"-u $_HI_VIMRC"* ]]
}

function test_osc52_preview_names_the_escape_and_the_helper() {
  local out
  out="$(_hi_osc52_preview)"
  [[ "$out" == *']52;c;'* && "$out" == *"$_HI_OSC52"* ]]
}

function test_bat_preview_names_the_bat_it_found() {
  local dir out
  dir="$(_hi_fake_path preview_bat bat)"
  # shellcheck disable=SC2031 # the swaps here live and die in their own $( )
  out="$(PATH="$dir:$PATH" _hi_bat_alias_preview)"
  [[ "$out" == "cat -> $dir/bat "* ]]
}

# an empty PATH directory, so `command -v bat` fails even where bat is real
function test_bat_preview_without_bat_says_targets_only() {
  local out
  mkdir -p "$_HI_WORKDIR/preview_none"
  out="$(hash -r && PATH="$_HI_WORKDIR/preview_none" _hi_bat_alias_preview)"
  [[ "$out" == *"bat is not installed here"* ]]
}

function test_starship_preview_reports_an_installed_one() {
  local dir out
  dir="$(_hi_fake_path preview_star starship)"
  # shellcheck disable=SC2031 # the swap lives and dies in its own $( )
  out="$(PATH="$dir:$PATH" _hi_starship_preview)"
  [[ "$out" == *"starship is installed here"* ]]
}

function test_starship_preview_reports_an_absent_one() {
  local out
  mkdir -p "$_HI_WORKDIR/preview_none"
  out="$(hash -r && PATH="$_HI_WORKDIR/preview_none" _hi_starship_preview)"
  [[ "$out" == *"starship is not installed on this machine"* ]]
}

# an empty render is a real answer at a high enough floor, and the preview
# says so rather than handing show_preview a blank to drop on the floor
function test_floor_preview_says_off_at_the_top_floor() {
  _hi_load_preview_sources
  local out
  out="$(_hi_strip_ansi "$(_hi_floor_candidate=4 _hi_packages_floor_preview)")"
  [[ "$out" == *"nothing - the check is off at this floor"* ]]
}

# the palette's preview is the real check (every shipped row renders a mark,
# installed or not, so floor 0 is never empty) - and the same off-message
# shape as the floor's when the floor has hidden everything. Asserted on the
# raw render: the names land unpainted between escapes anyway.
function test_palette_preview_renders_the_real_check() {
  _hi_load_preview_sources
  local dir out
  dir="$(_hi_fake_path preview_palette bat)"
  # shellcheck disable=SC2031 # the swap lives and dies in its own $( )
  out="$(PATH="$dir:$PATH" _HI_PACKAGES_MIN_PRIORITY=0 _hi_packages_palette_preview)"
  [[ "$out" == *" bat "* && "$out" != *"nothing -"* ]]
}

function test_palette_preview_says_off_above_every_priority() {
  _hi_load_preview_sources
  local out
  out="$(_hi_strip_ansi "$(_HI_PACKAGES_MIN_PRIORITY=9 _hi_packages_palette_preview)")"
  [[ "$out" == *"nothing - the package check is off"* ]]
}

# no git, no init - said in red, and no half-made overlay left behind
function test_overlay_init_without_git_says_so() {
  local dir="$_HI_WORKDIR/ovl-nogit" out rc=0
  mkdir -p "$dir" "$_HI_WORKDIR/no-tools"
  out="$(
    hash -r
    # shellcheck disable=SC2123,SC2030 # losing the search path is the case
    PATH="$_HI_WORKDIR/no-tools"
    _HI_CONFIG_DIR="$dir" overlay_init 2>&1
  )" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"git is not installed"* ]] && [ ! -d "$dir/.git" ]
}

# a machine that never ran `git config` still gets a committed overlay: init
# falls back to a repo-local identity rather than failing its first commit
function test_overlay_init_supplies_an_identity_when_git_has_none() {
  local dir="$_HI_WORKDIR/ovl-noident"
  mkdir -p "$dir" "$_HI_WORKDIR/ovl-noident-home"
  (
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
    export HOME="$_HI_WORKDIR/ovl-noident-home"
    _HI_CONFIG_DIR="$dir" overlay_init >/dev/null
  ) || return 1
  [ "$(git -C "$dir" config user.name)" = "say-hi" ] &&
    [ "$(_hi_overlay_commits "$dir")" = 1 ]
}

# the whole run with neither a preset nor a tty: config_preset stands down,
# every question keeps what the file holds, and the rewrite reproduces the
# block it found rather than dropping it
function _hi_no_preset_run() {
  mkdir -p "$_HI_CONFIG_DIR"
  config_shell settings "$_HI_SETTINGS" "export _HI_DISABLE_NOTIFY=1"
  _HI_SETTING_LINES=()
  _HI_SETTING_PENDING=()
  run_configure "" </dev/null
}

function test_run_configure_without_a_preset_keeps_the_block() {
  local block
  _hi_settings_fixture nopreset _hi_no_preset_run
  block="$(grep -F "$_HI_MARKER" "$(_hi_fixture_settings nopreset)")"
  [[ "$block" == *"export _HI_DISABLE_NOTIFY=1"* ]]
}

# The interactive arms proper: ask_setting's tty prompt, ask_value's typed
# answers, config_preset and the intro are all `[ -t 0 ]`-gated the same way
# the floor loop is, and the same pty harness reaches them. The child is
# _HI_FLOOR_CHILD's shape generalised - point the settings at a scratch dir,
# run the one configure function named on its argv with the pty as stdin, and
# report the exit code, the preset-final flag and the collected lines on one
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
  _HI_CONFIG_DIR="$_hi_dir/config"
  _HI_SETTINGS="$_hi_dir/config/settings.sh"
  _HI_SETTING_LINES=()
  _HI_SETTING_PENDING=()
  _hi_cfg_rc=0
  "${_hi_cfg_argv[@]}" || _hi_cfg_rc=$?
  collect_setting_lines
  printf "CFGRC=%s CFGQUIT=%s CFGLINES=%s\n" "$_hi_cfg_rc" "${_HI_CONFIGURE_QUIT:-none}" "${_HI_SETTING_LINES[*]:-}"
'

# _hi_cfg_pty <label> <input> <settings-line> <fn> [arg...] - one configure
# function under a pty with <input> (printf %b) on its stdin. Transcript
# lands in $_HI_WORKDIR/<label>.cfg.out; non-zero when the child had to be
# killed at the deadline.
function _hi_cfg_pty() {
  local label="$1" input="$2" line="$3"
  local dir="$_HI_WORKDIR/$label" out="$_HI_WORKDIR/$label.cfg.out"
  shift 3
  mkdir -p "$dir/common" "$dir/settings" "$dir/config"
  printf '#!/bin/sh\n%s\n' "$line" >"$dir/config/settings.sh"
  : >"$out"
  printf '%b' "$input" |
    "${_HI_PTY_FORCED[@]}" bash -c "$_HI_CFG_CHILD" bash "$dir" "$@" >"$out" 2>&1 &
  _hi_wait_pid "$!" "${_HI_CASE_TIMEOUT:-30}" _hi_timed_out "$label" "${_HI_CASE_TIMEOUT:-30}"
  [ "$_HI_WAIT_EXIT" != 124 ]
}

# the readers: the raw transcript for substrings (fixed strings only - a pty
# writes CR-LF, so nothing here anchors a line), the tail line's fields
# through the same CR normalisation the floor's readers use
function _hi_cfg_has() { grep -qF "$2" "$_HI_WORKDIR/$1.cfg.out"; }
function _hi_cfg_rc() {
  tr '\r' '\n' <"$_HI_WORKDIR/$1.cfg.out" | sed -n 's/.*CFGRC=\([0-9]*\).*/\1/p' | head -1
}
function _hi_cfg_lines() {
  tr '\r' '\n' <"$_HI_WORKDIR/$1.cfg.out" | sed -n 's/.*CFGLINES=//p' | head -1
}

# answering n turns a default-on toggle off, and the prompt said what the
# setting was in words before asking
function test_ask_setting_takes_a_no() {
  _hi_cfg_pty ask_no 'n\n' '' \
    ask_setting _HI_DISABLE_FOO " Enable foo?" "$_HI_WORKDIR/ask_no/config/settings.sh" 1 || return 1
  [ "$(_hi_cfg_rc ask_no)" = 1 ] && _hi_cfg_has ask_no "(currently on) [Y/n]"
}

# ...and y turns a written-off one back on, with the hint's capital flipped -
# plus the preview box, boxed between the question and the read
function test_ask_setting_takes_a_yes_over_an_off_state() {
  _hi_cfg_pty ask_yes 'y\n' 'export _HI_DISABLE_FOO=1' \
    ask_setting _HI_DISABLE_FOO " Enable foo?" "$_HI_WORKDIR/ask_yes/config/settings.sh" 1 \
    _hi_osc52_preview || return 1
  [ "$(_hi_cfg_rc ask_yes)" = 0 ] &&
    _hi_cfg_has ask_yes "(currently off) [y/N]" &&
    _hi_cfg_has ask_yes "hi_copy"
}

function test_ask_setting_enter_keeps_the_off_state() {
  _hi_cfg_pty ask_enter '\n' 'export _HI_DISABLE_FOO=1' \
    ask_setting _HI_DISABLE_FOO " Enable foo?" "$_HI_WORKDIR/ask_enter/config/settings.sh" 1 || return 1
  [ "$(_hi_cfg_rc ask_enter)" = 1 ]
}

function test_ask_value_takes_a_typed_number() {
  _hi_cfg_pty width_typed '120\n' '' config_max_width || return 1
  [ "$(_hi_cfg_lines width_typed)" = "export _HI_MAX_WIDTH=120" ]
}

# a rejected answer says why and keeps the current value rather than dropping
# it - the message names the value kept, so both halves are one substring
function test_ask_value_rejects_junk_and_keeps_current() {
  _hi_cfg_pty width_junk 'abc\n' 'export _HI_MAX_WIDTH=100' config_max_width || return 1
  _hi_cfg_has width_junk "not a number, leaving it at 100" &&
    [ "$(_hi_cfg_lines width_junk)" = "export _HI_MAX_WIDTH=100" ]
}

# typing the shipped default is how an override is cleared interactively
function test_ask_value_typed_default_clears_the_override() {
  _hi_cfg_pty width_default '80\n' 'export _HI_MAX_WIDTH=100' config_max_width || return 1
  [ -z "$(_hi_cfg_lines width_default | tr -d '[:space:]')" ]
}

# the palette question previews the real check once, then takes a word
function test_color_scheme_asked_interactively_takes_a_word() {
  _hi_cfg_pty scheme_typed 'monokai\n' '' config_color_scheme || return 1
  _hi_cfg_has scheme_typed "catppuccin" &&
    [ "$(_hi_cfg_lines scheme_typed)" = "export _HI_COLOR_SCHEME=monokai" ]
}

# typing the default clears an override rather than restating it
function test_color_scheme_default_answer_clears_it() {
  _hi_cfg_pty scheme_clear 'default\n' "export _HI_COLOR_SCHEME=vscode" config_color_scheme || return 1
  [[ "$(_hi_cfg_lines scheme_clear)" != *"_HI_COLOR_SCHEME"* ]]
}

function test_hub_opens_colors() {
  _hi_cfg_pty hub_colors '6\nonedark\ns\n' '' run_configure "" || return 1
  _hi_cfg_has hub_colors "Color scheme:" &&
    [[ "$(_hi_cfg_lines hub_colors)" == *"export _HI_COLOR_SCHEME=onedark"* ]]
}

function test_palette_asked_interactively_takes_a_word() {
  _hi_cfg_pty pal_typed 'warm\n' '' config_packages_palette || return 1
  _hi_cfg_has pal_typed "preview" &&
    [ "$(_hi_cfg_lines pal_typed)" = "export _HI_PACKAGES_PALETTE=warm" ]
}

# The header editor: the real header boxed above the list, and every
# command re-renders. Toggling one word off (2 is utc, the first item after
# the banner) writes the default order minus that word, quoted - read off
# header.sh's own $_HI_HEADER_ORDER_DEFAULT rather than a second copy of it,
# so a reorder there cannot leave this expectation stale.
function test_header_editor_toggle_writes_the_order() {
  _hi_cfg_pty hdr_toggle '2\n\n' '' config_header || return 1
  local lines want
  want="$(bash -c 'source "$_HI_HEADER"; printf %s "$_HI_HEADER_ORDER_DEFAULT"')"
  want="${want/utc /}"
  lines="$(_hi_cfg_lines hdr_toggle)"
  _hi_cfg_has hdr_toggle "preview" &&
    [[ "$lines" == *"export _HI_HEADER_ORDER='$want'"* ]]
}

# toggled off and back on, the order is the shipped one again and writes
# nothing - the same rule the typed default follows everywhere else
function test_header_editor_default_order_writes_nothing() {
  _hi_cfg_pty hdr_default '2\n2\n\n' '' config_header || return 1
  [ -z "$(_hi_cfg_lines hdr_default | tr -d '[:space:]')" ]
}

# `down 2` swaps utc with its neighbor
function test_header_editor_moves_a_word() {
  _hi_cfg_pty hdr_move 'down 2\n\n' '' config_header || return 1
  [[ "$(_hi_cfg_lines hdr_move)" == *"export _HI_HEADER_ORDER='version utc localtime"* ]]
}

# the banner always leads: item 1 toggles but never moves
function test_header_editor_banner_never_moves() {
  _hi_cfg_pty hdr_banner 'up 1\n1\n\n' '' config_header || return 1
  local lines
  lines="$(_hi_cfg_lines hdr_banner)"
  _hi_cfg_has hdr_banner "the banner always leads" &&
    [[ "$lines" == *"export _HI_HEADER_BANNER=0"* && "$lines" != *"_HI_HEADER_ORDER"* ]]
}

# a header preset loads its words, on and in its order, everything else off
# _hi_detect_in <home> [zdotdir] - detect_prompt_framework with the roster
# pointed at <home>'s rc files, in a subshell so the suite's own stay bound
function _hi_detect_in() {
  (
    _HI_HOME_BASHRC="$1/.bashrc" _HI_HOME_ZSHRC="$1/.zshrc" _HI_HOME_FISH_CONFIG="$1/.config/fish/config.fish"
    export ZDOTDIR="${2:-}"
    detect_prompt_framework
  )
}

# every rc on the roster is read, a $ZDOTDIR .zshrc with them, hi's own
# marker-tagged lines never count, and a fish_prompt.fish of the user's own
# is the fallback when no framework names itself
# shellcheck disable=SC2016 # the rc lines are fixtures; nothing expands
function test_detect_prompt_framework_reads_every_rc_and_skips_hi_lines() {
  local home="$_HI_WORKDIR/detect"
  mkdir -p "$home/zdot" "$home/.config/fish/functions"
  ! _hi_detect_in "$home" >/dev/null || return 1
  printf 'eval "$(starship init bash)"\n' >"$home/.bashrc"
  [ "$(_hi_detect_in "$home")" = starship ] || return 1
  rm -f "$home/.bashrc"
  printf 'source ~/powerlevel10k/p10k.zsh\n' >"$home/zdot/.zshrc"
  [ "$(_hi_detect_in "$home" "$home/zdot")" = powerlevel10k ] || return 1
  ! _hi_detect_in "$home" >/dev/null || return 1
  rm -f "$home/zdot/.zshrc"
  printf 'eval "$(starship init bash)" %s\n' "$_HI_MARKER" >"$home/.bashrc"
  ! _hi_detect_in "$home" >/dev/null || return 1
  : >"$home/.config/fish/functions/fish_prompt.fish"
  [ "$(_hi_detect_in "$home")" = "your own fish_prompt" ]
}

# the "keep theirs" default is a first-configure courtesy: with no settings.sh
# a found framework pends _HI_DISABLE_LOCAL_PROMPT=1; with one, the stored
# answer stands and nothing is pended
# shellcheck disable=SC2016 # the rc line is a fixture; nothing expands
function test_prompt_framework_default_keeps_theirs_only_on_a_first_configure() {
  local home="$_HI_WORKDIR/pfd" out
  mkdir -p "$home"
  printf 'eval "$(starship init bash)"\n' >"$home/.bashrc"
  out="$(
    _HI_HOME_BASHRC="$home/.bashrc" _HI_HOME_ZSHRC="$home/.zshrc" _HI_HOME_FISH_CONFIG="$home/none"
    _HI_SETTINGS="$home/absent.sh"
    _HI_SETTING_PENDING=()
    prompt_framework_default >/dev/null
    printf '%s' "${_HI_SETTING_PENDING[*]:-}"
  )"
  [ "$out" = "_HI_DISABLE_LOCAL_PROMPT=1" ] || return 1
  : >"$home/settings.sh"
  out="$(
    _HI_HOME_BASHRC="$home/.bashrc" _HI_HOME_ZSHRC="$home/.zshrc" _HI_HOME_FISH_CONFIG="$home/none"
    _HI_SETTINGS="$home/settings.sh"
    _HI_SETTING_PENDING=()
    prompt_framework_default >/dev/null
    printf '%s' "${_HI_SETTING_PENDING[*]:-}"
  )"
  [ -z "$out" ]
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

# up/down out of range, on the banner, and at the end the word is already at
# - three refusals, each in words, and the run goes on
function test_header_editor_refuses_a_move_that_cannot_happen() {
  _hi_cfg_pty hdr_updown 'up 99\nup 1\nup 2\n\n' '' config_header || return 1
  _hi_cfg_has hdr_updown "up/down take an item number from 2 to" &&
    _hi_cfg_has hdr_updown "the banner always leads" &&
    _hi_cfg_has hdr_updown "is already at that end"
}

# three answers the editor cannot read in a row end it, like the hub
function test_header_editor_junk_is_bounded() {
  _hi_cfg_pty hdr_junk 'x\ny\nz\n' '' config_header || return 1
  [ "$(_hi_cfg_rc hdr_junk)" = 0 ] &&
    _hi_cfg_has hdr_junk "type an item number, up N, down N, p, w, c, k, 0, or Enter" &&
    [ -z "$(_hi_cfg_lines hdr_junk | tr -d '[:space:]')" ]
}

# p, then a name off the roster: said, nothing written, the editor goes on
function test_header_editor_preset_refuses_a_stranger() {
  _hi_cfg_pty hdr_pstranger 'p\nnope\n\n' '' config_header || return 1
  _hi_cfg_has hdr_pstranger "no such header preset: nope" &&
    [ -z "$(_hi_cfg_lines hdr_pstranger | tr -d '[:space:]')" ]
}

# w asks for the width and writes a typed one
function test_header_editor_w_takes_a_width() {
  _hi_cfg_pty hdr_width 'w\n120\n\n' '' config_header || return 1
  _hi_cfg_has hdr_width "Terminal width for the header/banner?" &&
    [[ "$(_hi_cfg_lines hdr_width)" == *"export _HI_MAX_WIDTH=120"* ]]
}

# k asks for the check's palette once check is on, and writes the word
function test_header_editor_k_takes_a_palette() {
  _hi_cfg_pty hdr_palette 'k\nwarm\n\n' "export _HI_HEADER_ORDER='check utc'" config_header || return 1
  _hi_cfg_has hdr_palette "Package check palette: cool, warm, or mono?" &&
    [[ "$(_hi_cfg_lines hdr_palette)" == *"export _HI_PACKAGES_PALETTE=warm"* ]]
}

function test_header_editor_i_takes_hidden_addresses() {
  _hi_cfg_pty hdr_iphide 'i\nnone\n\n' "export _HI_HEADER_ORDER='ip utc'" config_header || return 1
  _hi_cfg_has hdr_iphide "Hide which addresses from the ip cell" &&
    [[ "$(_hi_cfg_lines hdr_iphide)" == *"export _HI_IP_HIDE='none'"* ]]
}

# the Prompt menu is bounded the same way, and a separator with a quote in it
# is refused rather than written into settings.sh
function test_prompt_menu_junk_is_bounded_and_a_quote_is_refused() {
  _hi_cfg_pty pe_junk 'x\ny\nz\n' '' config_prompt || return 1
  _hi_cfg_has pe_junk "type a number from 1 to" || return 1
  _hi_cfg_pty pe_quote '2\n'"'"'\n\n' '' config_prompt || return 1
  _hi_cfg_has pe_quote "a single quote can't be written to settings.sh" &&
    [[ "$(_hi_cfg_lines pe_quote)" != *"_HI_PROMPT_END_"* ]]
}

# the glyph question maps words both ways, and a shell list with a stranger
# in it is refused - said in words, the current value kept, nothing written
function test_advanced_values_map_glyph_words_and_refuse_a_bad_shell_list() {
  _hi_cfg_pty adv_glyphs 'bash zsh\nglyphs\n\n\n\n\n' '' config_advanced_values || return 1
  local lines
  lines="$(_hi_cfg_lines adv_glyphs)"
  [[ "$lines" == *"export _HI_SHELL_PREFERENCE='bash zsh'"* && "$lines" == *"export _HI_ASCII=0"* ]] || return 1
  _hi_cfg_pty adv_badshell 'tcsh\n\n\n\n\n\n' '' config_advanced_values || return 1
  _hi_cfg_has adv_badshell "only login, bash, zsh and fish are understood" &&
    [[ "$(_hi_cfg_lines adv_badshell)" != *"_HI_SHELL_PREFERENCE"* ]]
}

function test_header_editor_takes_a_preset() {
  _hi_cfg_pty hdr_preset 'p\nq\n\n' '' config_header || return 1
  [[ "$(_hi_cfg_lines hdr_preset)" == *"export _HI_HEADER_ORDER='utc localtime gitid'"* ]]
}

# 0 turns the whole header off, and the preview says so in words rather
# than showing an empty box
function test_header_editor_header_off_previews_as_words() {
  _hi_cfg_pty hdr_off '0\n\n' '' config_header || return 1
  _hi_cfg_has hdr_off "header off - nothing prints" &&
    [[ "$(_hi_cfg_lines hdr_off)" == *"export _HI_DISABLE_HEADER=1"* ]]
}

# an empty $_HI_HEADER_ORDER means the default at runtime, so the last word
# cannot be turned off - the editor says how to get an empty header instead
function test_header_editor_keeps_the_last_word() {
  _hi_cfg_pty hdr_last '2\n\n' "export _HI_HEADER_ORDER='gitid'" config_header || return 1
  _hi_cfg_has hdr_last "keep at least one item" &&
    [[ "$(_hi_cfg_lines hdr_last)" == *"export _HI_HEADER_ORDER='gitid'"* ]]
}

# a stored order lists its words first, in its order, then every word it
# leaves out, unchecked
function test_header_editor_lists_missing_words_off() {
  _hi_cfg_pty hdr_list '\n' "export _HI_HEADER_ORDER='check gitid'" config_header || return 1
  _hi_cfg_has hdr_list "2) [x] check" &&
    _hi_cfg_has hdr_list "3) [x] gitid" &&
    _hi_cfg_has hdr_list "4) [ ] utc"
}

# the check's depth and palette are only offered while 'check' is on
function test_header_editor_refuses_check_dials_when_check_is_off() {
  _hi_cfg_pty hdr_nocheck 'c\nk\n\n' "export _HI_HEADER_ORDER='gitid'" config_header || return 1
  _hi_cfg_has hdr_nocheck "turn 'check' on first" &&
    ! _hi_cfg_has hdr_nocheck "Lowest package priority" &&
    ! _hi_cfg_has hdr_nocheck "Package check palette"
}

# ...and reachable from the editor when it is: c opens the floor's loop
function test_header_editor_opens_the_check_depth() {
  _hi_cfg_pty hdr_depth 'c\n3\n3\n\n' '' config_header || return 1
  [[ "$(_hi_cfg_lines hdr_depth)" == *"export _HI_PACKAGES_MIN_PRIORITY=3"* ]]
}

# The Features menu: a number flips the row and shows its preview
function test_features_menu_toggles_and_previews() {
  _hi_cfg_pty feat_toggle '4\n\n' '' config_features || return 1
  _hi_cfg_has feat_toggle "vim/nano config overrides: now off" &&
    _hi_cfg_has feat_toggle "nano --rcfile" &&
    [[ "$(_hi_cfg_lines feat_toggle)" == *"export _HI_DISABLE_EDITORS=1"* ]]
}

# ...and the header row previews the whole header, not just its banner
function test_features_menu_header_row_previews_the_header() {
  _hi_cfg_pty feat_header '1\n1\n\n' '' config_features || return 1
  _hi_cfg_has feat_header "header off - nothing prints" &&
    _hi_cfg_has feat_header "Connected" &&
    [ -z "$(_hi_cfg_lines feat_header | tr -d '[:space:]')" ]
}

# three junk answers in a row and a submenu goes back on its own
function test_features_menu_junk_is_bounded() {
  _hi_cfg_pty feat_junk 'x\ny\nz\n' '' config_features || return 1
  [ "$(_hi_cfg_rc feat_junk)" = 0 ]
}

# The Prompt menu: item 2 is bash's separator, typed and single-quoted;
# zsh's is never asked and never written
function test_prompt_end_typed_interactively_is_quoted() {
  _hi_cfg_pty pe_typed '2\n>>\n\n' '' config_prompt || return 1
  local lines
  lines="$(_hi_cfg_lines pe_typed)"
  [[ "$lines" == *"export _HI_PROMPT_END_BASH='>>'"* && "$lines" != *"_HI_PROMPT_END_ZSH"* ]]
}

# item 1 is the starship opt-in
function test_prompt_menu_toggles_starship() {
  _hi_cfg_pty pe_star '1\n\n' '' config_prompt || return 1
  _hi_cfg_has pe_star "starship: now on" &&
    [[ "$(_hi_cfg_lines pe_star)" == *"export _HI_PROMPT=starship"* ]]
}

# the advanced section is a question walk with no gate of its own now (the
# hub's item is the gate) - and Enter through all of it still writes
# nothing, since the defaults live in the code
function test_advanced_walks_the_questions() {
  _hi_cfg_pty adv_walk '\n\n\n\n\n\n\n\n\n\n' '' config_advanced || return 1
  _hi_cfg_has adv_walk "Swap a TERM" &&
    _hi_cfg_has adv_walk "Shell a session runs in" &&
    [ -z "$(_hi_cfg_lines adv_walk | tr -d '[:space:]')" ]
}

# every advanced value typed for real, including the words-to-flag mapping
# _HI_ASCII's question hides behind ("ascii" is stored as 1)
function test_advanced_values_typed_interactively() {
  _hi_cfg_pty adv_typed 'zsh login\nascii\n9\n0.5\npodman docker\n120\n' '' config_advanced_values || return 1
  local lines
  lines="$(_hi_cfg_lines adv_typed)"
  [[ "$lines" == *"export _HI_SHELL_PREFERENCE='zsh login'"* && "$lines" == *"export _HI_ASCII=1"* &&
    "$lines" == *"export _HI_TARGETS_TTL=9"* && "$lines" == *"export _HI_PROBE_TIMEOUT=0.5"* &&
    "$lines" == *"export _HI_CONTAINER_CLIS='podman docker'"* &&
    "$lines" == *"export _HI_CTL_PERSIST=120"* ]]
}

# a CLI name hi.sh could not turn into a function name is refused in words
# and the value left alone, like every other ask_value answer
function test_advanced_container_clis_rejects_a_bad_name() {
  _hi_cfg_pty adv_clis '\n\n\n\nno-dashes here\n\n' '' config_advanced_values || return 1
  _hi_cfg_has adv_clis "plain names" &&
    [[ "$(_hi_cfg_lines adv_clis)" != *"_HI_CONTAINER_CLIS"* ]]
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
    [[ "$(_hi_cfg_lines pre_walk)" == *"export _HI_PACKAGES_MIN_PRIORITY=3"* ]]
}

# The hub proper. The shortest whole run: the intro orients, 1 opens the
# presets, m picks minimal, s saves - and the one write at the end is exactly
# the preset's block.
function test_full_run_preset_then_save() {
  _hi_cfg_pty full_walk '1\nm\ns\n' '' run_configure "" || return 1
  local block
  block="$(grep -F "$_HI_MARKER" "$_HI_WORKDIR/full_walk/config/settings.sh")"
  _hi_cfg_has full_walk "Nothing is written until you save" &&
    _hi_cfg_has full_walk "starting from the 'minimal' preset" &&
    _hi_cfg_has full_walk "CFGQUIT=none" &&
    [[ "$block" == *"export _HI_DISABLE_HEADER=1"* && "$block" == *"export _HI_DISABLE_LOCAL=1"* ]]
}

# q after the same preset writes nothing at all - no block, not even the
# shebang - and leaves the flag install.sh's closing line reads
function test_full_run_quit_writes_nothing() {
  _hi_cfg_pty full_quit '1\nm\nq\n' '' run_configure "" || return 1
  _hi_cfg_has full_quit "starting from the 'minimal' preset" &&
    _hi_cfg_has full_quit "nothing written" &&
    _hi_cfg_has full_quit "CFGQUIT=1" &&
    ! grep -qF "$_HI_MARKER" "$_HI_WORKDIR/full_quit/config/settings.sh"
}

# EOF at the hub saves what there is - no answer has always meant "keep what
# you have and finish" here - so a driver that stops typing still ends in
# the write
function test_hub_eof_saves() {
  _hi_cfg_pty hub_eof '\004' 'export _HI_DISABLE_NOTIFY=1' run_configure "" || return 1
  _hi_cfg_has hub_eof "CFGQUIT=none" &&
    grep -qF "export _HI_DISABLE_NOTIFY=1" "$_HI_WORKDIR/hub_eof/config/settings.sh"
}

# ...and so does the third junk answer in a row: the bound, not the patience
function test_hub_junk_is_bounded_and_saves() {
  _hi_cfg_pty hub_junk 'x\ny\nz\nq\n' '' run_configure "" || return 1
  _hi_cfg_has hub_junk "saving what you have" &&
    _hi_cfg_has hub_junk "CFGQUIT=none"
}

# every digit opens its section and comes back to the hub; the preview box
# is drawn before the menu. The advanced walk takes up to ten Enters (one
# fewer without fish here); a spare Enter at the hub only redraws it.
function test_hub_opens_every_section() {
  _hi_cfg_pty hub_all '2\n\n3\n\n4\n\n5\n\n\n\n\n\n\n\n\n\n\n\ns\n' '' run_configure "" || return 1
  _hi_cfg_has hub_all "preview" &&
    _hi_cfg_has hub_all "Header" &&
    _hi_cfg_has hub_all "Features" &&
    _hi_cfg_has hub_all "Prompt" &&
    _hi_cfg_has hub_all "Advanced settings" &&
    _hi_cfg_has hub_all "Swap a TERM" &&
    _hi_cfg_has hub_all "CFGQUIT=none"
}

function run_configure_tests() {
  _hi_workdir configuretest

  _hi_h1 "Testing scripts/configure.sh's reusable logic"

  _hi_suite_begin

  _hi_h2 "Testing: config_shell"
  _hi_check "Fresh insert" test_config_shell_fresh_insert
  _hi_check "Idempotent re-run" test_config_shell_idempotent
  _hi_check "Repairs a stale line" test_config_shell_repairs_stale_line
  _hi_check "Preserves unrelated content" test_config_shell_preserves_unrelated_content
  _hi_check "Skips empty args" test_config_shell_skips_empty_args
  _hi_check "Appends at the end" test_config_shell_appends_at_the_end
  _hi_check "Preserves the target's mode" test_config_shell_preserves_target_mode
  _hi_check "Preserves hardlinks" test_config_shell_preserves_hardlinks
  _hi_check "Backs up on the first insert" test_config_shell_backs_up_on_first_insert
  _hi_check "Backup survives reruns" test_config_shell_backup_survives_reruns
  _hi_check "No backup for an empty target" test_config_shell_no_backup_for_empty_target

  _hi_h2 "Testing: settings are sourced ahead of paths.sh"
  _hi_check "common/core.sh" test_core_sources_settings_first
  _hi_check "common/config.fish" test_fish_config_sources_settings_first

  _hi_h2 "Testing: the collector - prompt separators"
  _hi_check "An existing override is kept" test_prompt_ends_keeps_an_existing_override
  _hi_check "Written values are quoted" test_prompt_ends_quotes_what_it_writes
  _hi_check "Kept when the prompt is off" test_prompt_ends_kept_when_the_prompt_is_off

  _hi_h2 "Testing: the collector - palette and header order"
  _hi_check "Palette: an existing override is kept" test_packages_palette_keeps_an_existing_override
  _hi_check "Palette: the default writes nothing" test_packages_palette_does_not_write_the_default
  _hi_check "Palette: kept when the check is off" test_packages_palette_kept_when_the_check_is_off
  _hi_check "Hidden addresses: an existing override is kept" test_ip_hide_keeps_an_existing_override
  _hi_check "Scheme: an existing override is kept" test_color_scheme_keeps_an_existing_override
  _hi_check "Scheme: the default writes nothing" test_color_scheme_does_not_write_the_default
  _hi_check "Scheme preview lists every scheme" test_color_scheme_preview_lists_every_scheme
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

  _hi_h2 "Testing: overlay_init / overlay_commit"
  _hi_check_requires git "Init makes a repo with a first commit" test_overlay_init_creates_a_repo_with_a_first_commit
  _hi_check_requires git "Init is idempotent" test_overlay_init_is_idempotent
  _hi_check_requires git "Init seeds the shipped defaults" test_overlay_init_seeds_the_shipped_defaults
  _hi_check_requires git "...and never overwrites a present file" test_overlay_init_never_overwrites_a_present_file
  _hi_check_requires git "A tracked overlay commits settings writes" test_overlay_commit_records_a_change_when_tracked
  _hi_check_requires git "Nothing new, no commit" test_overlay_commit_is_a_noop_with_nothing_new
  _hi_check_requires git "An untracked overlay never hears about git" test_overlay_commit_never_creates_a_repo
  _hi_check "No git, no init - and it says so" test_overlay_init_without_git_says_so
  _hi_check_requires git "Init supplies an identity where git has none" test_overlay_init_supplies_an_identity_when_git_has_none

  _hi_h2 "Testing: ensure_settings_shebang"
  _hi_check "Written to a new settings.sh" test_shebang_is_written_to_a_new_settings_file
  _hi_check "Stays first under the settings block" test_shebang_stays_first_under_the_settings_block
  _hi_check "Not duplicated on reruns" test_shebang_is_not_duplicated_on_reruns
  _hi_check "Packages floor: an existing value survives" test_packages_floor_keeps_a_configured_value
  _hi_check "Packages floor: the default is not written" test_packages_floor_does_not_write_the_default
  _hi_check "Packages floor: a zero is written out" test_packages_floor_writes_a_zero
  _hi_check "Packages floor: kept when the check is off" test_packages_floor_kept_when_the_check_is_off
  _hi_check "Replaces a different shebang" test_shebang_replaces_a_different_one_and_keeps_content
  _hi_check "detect_prompt_framework reads every rc and skips hi's lines" test_detect_prompt_framework_reads_every_rc_and_skips_hi_lines
  _hi_check "prompt_framework_default: keep theirs, first configure only" test_prompt_framework_default_keeps_theirs_only_on_a_first_configure
  _hi_check "_hi_header_edit_preset refuses a stranger" test_header_edit_preset_refuses_a_stranger
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

  _hi_h2 "Testing: tmpdir_line"
  _hi_check "States the tree even at \$HOME" test_tmpdir_line_states_the_tree_even_at_home
  _hi_check "Posix export line" test_tmpdir_line_posix_variant
  _hi_check "Fish set -gx line" test_tmpdir_line_fish_variant

  _hi_h2 "Testing: ask_setting (non-interactive)"
  _hi_check "Keeps enabled default" test_ask_setting_default_keeps_enabled
  _hi_check "Keeps disabled default" test_ask_setting_default_keeps_disabled

  _hi_h2 "Testing: opt-ins, the advanced section and the closing report"
  _hi_check "An absent opt-in is off" test_setting_on_opt_in_absent_is_off
  _hi_check "A written opt-in is on" test_setting_on_opt_in_present_is_on
  _hi_check "An absent toggle is on" test_setting_on_toggle_absent_is_on
  _hi_check "An opt-in that is off writes nothing" test_opt_in_off_writes_nothing
  _hi_check "starship is kept when chosen" test_starship_kept_when_chosen
  _hi_check "Advanced: unanswered keeps every value" test_advanced_declined_keeps_every_value
  _hi_check "Advanced: defaults write nothing" test_advanced_defaults_write_nothing
  _hi_check "A row that cannot be asked is carried" test_prompt_group_carries_a_row_it_cannot_ask
  _hi_check "Validators for the advanced values" test_validators_for_the_advanced_values
  _hi_check "Diff reports added and removed lines" test_settings_diff_reports_added_and_removed
  _hi_check "Diff says no changes" test_settings_diff_says_no_changes

  _hi_h2 "Testing: presets"
  _hi_check "A preset seeds every answer in its vocabulary" test_apply_preset_seeds_every_answer
  _hi_check "An unknown preset is refused" test_apply_preset_rejects_a_stranger
  _hi_check "Shorthand resolves each preset's first letter" test_preset_shorthand_resolves_each_first_letter
  _hi_check "Shorthand rejects an unknown letter" test_preset_shorthand_rejects_unknown_letter
  _hi_check "Shorthand rejects more than one character" test_preset_shorthand_rejects_multiple_characters
  _hi_check "Every preset stays inside the vocabulary" test_every_preset_names_only_vocabulary
  _hi_check "The vocabulary excludes the palette and the order" test_preset_vocab_excludes_palette_and_order
  _hi_check "--preset writes exactly the preset" test_preset_run_writes_the_preset
  _hi_check "install.sh refuses an unknown --preset" test_install_rejects_an_unknown_preset
  _hi_check "No preset and no tty keeps the block" test_run_configure_without_a_preset_keeps_the_block

  _hi_h2 "Testing: _hi_visible_len"
  _hi_check "Plain text" test_visible_len_plain_text
  _hi_check "Strips color codes" test_visible_len_strips_color_codes

  _hi_h2 "Testing: check_one_config"
  _hi_check_requires bash "Valid bash syntax" test_check_one_config_valid_bash
  _hi_check_requires bash "Invalid bash syntax" test_check_one_config_invalid_bash
  _hi_check "Skips a missing shell" test_check_one_config_skips_missing_shell
  _hi_check_requires bash "Skips an empty file" test_check_one_config_skips_empty_file

  _hi_h2 "Testing: check_overlay_configs"
  _hi_check_requires fish "A clean overlay passes" test_check_overlay_configs_passes_a_clean_overlay
  _hi_check_requires fish "An sh-only aliases.sh is caught by the fish row" test_check_overlay_configs_catches_sh_only_aliases
  _hi_check "No overlay, nothing to say" test_check_overlay_configs_passes_with_no_overlay

  _hi_h2 "Testing: config_hi (skip path only)"
  _hi_check_capable symlink "Skips when already linked" test_config_hi_skips_when_already_linked
  _hi_check_capable symlink "Survives an unwritable launcher" test_config_hi_survives_an_unwritable_launcher
  _hi_check_capable symlink "Skips chmod when already executable" test_config_hi_skips_chmod_when_already_executable
  _hi_check_capable symlink "Links plainly into a writable bindir" test_config_hi_links_plainly_when_bindir_is_writable
  _hi_check_capable lockout "Degrades when sudo can't link" test_config_hi_degrades_when_sudo_cannot_link
  _hi_check_capable lockout "Degrades with no sudo at all" test_config_hi_degrades_with_no_sudo_at_all

  _hi_h2 "Testing: the question previews"
  _hi_check "Prompt preview shows this user@host" test_prompt_preview_shows_this_user_and_host
  _hi_check "Prompt sample says off when the prompt is disabled" test_prompt_sample_preview_says_off_when_disabled
  _hi_check "Editors preview names both overrides" test_editors_preview_names_both_overrides
  _hi_check "OSC 52 preview names the escape and the helper" test_osc52_preview_names_the_escape_and_the_helper
  _hi_check "bat preview names the bat it found" test_bat_preview_names_the_bat_it_found
  _hi_check "...and says so when there is none" test_bat_preview_without_bat_says_targets_only
  _hi_check "starship preview reports an installed one" test_starship_preview_reports_an_installed_one
  _hi_check "...and an absent one" test_starship_preview_reports_an_absent_one
  _hi_check "Floor preview says off at the top floor" test_floor_preview_says_off_at_the_top_floor
  _hi_check "Palette preview renders the real check" test_palette_preview_renders_the_real_check
  _hi_check "...and says off above every priority" test_palette_preview_says_off_above_every_priority

  # Every pty case fans out together: each drives its own child under its own
  # $_HI_WORKDIR/<label> and the children re-source configure.sh themselves,
  # so nothing in this shell is shared - and thirty-odd of them at a second
  # apiece were this suite's whole wall clock when they ran one at a time.
  # The three packages-floor prompts belong to the section above; they sit
  # here because they are pty cases too.
  _hi_h2 "Testing: the interactive arms, the header editor, the Features menu and the hub (pty)"
  _hi_par_begin "pty cases"
  _hi_par_check_capable pty "Packages floor: junk stops the loop" test_packages_floor_stops_asking_for_a_number
  _hi_par_check_capable pty "Packages floor: EOF ends the prompt" test_packages_floor_ends_on_eof
  _hi_par_check_capable pty "Packages floor: a number lands after a rejection" test_packages_floor_takes_a_number_after_a_rejection
  _hi_par_check_capable pty "ask_setting takes a no" test_ask_setting_takes_a_no
  _hi_par_check_capable pty "ask_setting takes a yes over an off state" test_ask_setting_takes_a_yes_over_an_off_state
  _hi_par_check_capable pty "ask_setting: Enter keeps the off state" test_ask_setting_enter_keeps_the_off_state
  _hi_par_check_capable pty "ask_value takes a typed number" test_ask_value_takes_a_typed_number
  _hi_par_check_capable pty "ask_value rejects junk and keeps current" test_ask_value_rejects_junk_and_keeps_current
  _hi_par_check_capable pty "ask_value: the typed default clears the override" test_ask_value_typed_default_clears_the_override
  _hi_par_check_capable pty "Palette: previewed once, then a typed word" test_palette_asked_interactively_takes_a_word
  _hi_par_check_capable pty "Scheme: previewed, then a typed word" test_color_scheme_asked_interactively_takes_a_word
  _hi_par_check_capable pty "Scheme: the default clears an override" test_color_scheme_default_answer_clears_it
  _hi_par_check_capable pty "Hub: 6 opens Colors" test_hub_opens_colors
  _hi_par_check_capable pty "Prompt menu: a separator typed and quoted" test_prompt_end_typed_interactively_is_quoted
  _hi_par_check_capable pty "Prompt menu: 1 toggles starship" test_prompt_menu_toggles_starship
  _hi_par_check_capable pty "Advanced: Enter through every question" test_advanced_walks_the_questions
  _hi_par_check_capable pty "Advanced values: typed for real" test_advanced_values_typed_interactively
  _hi_par_check_capable pty "Advanced values: a bad CLI name is refused" test_advanced_container_clis_rejects_a_bad_name
  _hi_par_check_capable pty "Preset question: Enter keeps current" test_preset_question_enter_keeps_current
  _hi_par_check_capable pty "Preset question: a stranger is refused, run continues" test_preset_question_refuses_a_stranger_and_carries_on
  _hi_par_check_capable pty "Preset shorthand seeds the run" test_preset_shorthand_seeds_the_run
  _hi_par_check_capable pty "A toggle writes the order, previewed" test_header_editor_toggle_writes_the_order
  _hi_par_check_capable pty "Back to the default order writes nothing" test_header_editor_default_order_writes_nothing
  _hi_par_check_capable pty "down N moves a word" test_header_editor_moves_a_word
  _hi_par_check_capable pty "The banner toggles but never moves" test_header_editor_banner_never_moves
  _hi_par_check_capable pty "p takes a header preset" test_header_editor_takes_a_preset
  _hi_par_check_capable pty "0 turns the header off, previewed in words" test_header_editor_header_off_previews_as_words
  _hi_par_check_capable pty "The last word cannot be turned off" test_header_editor_keeps_the_last_word
  _hi_par_check_capable pty "Words a stored order leaves out list unchecked" test_header_editor_lists_missing_words_off
  _hi_par_check_capable pty "c/k refused while 'check' is off" test_header_editor_refuses_check_dials_when_check_is_off
  _hi_par_check_capable pty "c opens the check depth" test_header_editor_opens_the_check_depth
  _hi_par_check_capable pty "A move that cannot happen is refused in words" test_header_editor_refuses_a_move_that_cannot_happen
  _hi_par_check_capable pty "Editor junk is bounded" test_header_editor_junk_is_bounded
  _hi_par_check_capable pty "p refuses a stranger" test_header_editor_preset_refuses_a_stranger
  _hi_par_check_capable pty "w takes a width" test_header_editor_w_takes_a_width
  _hi_par_check_capable pty "k takes a palette" test_header_editor_k_takes_a_palette
  _hi_par_check_capable pty "i takes the hidden addresses" test_header_editor_i_takes_hidden_addresses
  _hi_par_check_capable pty "Prompt menu: junk bounded, a quote refused" test_prompt_menu_junk_is_bounded_and_a_quote_is_refused
  _hi_par_check_capable pty "Advanced values: glyph words map, a bad shell list is refused" test_advanced_values_map_glyph_words_and_refuse_a_bad_shell_list
  _hi_par_check_capable pty "A number toggles and previews" test_features_menu_toggles_and_previews
  _hi_par_check_capable pty "The header row previews the whole header" test_features_menu_header_row_previews_the_header
  _hi_par_check_capable pty "Junk is bounded" test_features_menu_junk_is_bounded
  _hi_par_check_capable pty "Full run: preset, then save" test_full_run_preset_then_save
  _hi_par_check_capable pty "Full run: preset, then quit writes nothing" test_full_run_quit_writes_nothing
  _hi_par_check_capable pty "Hub: EOF saves" test_hub_eof_saves
  _hi_par_check_capable pty "Hub: junk is bounded and saves" test_hub_junk_is_bounded_and_saves
  _hi_par_check_capable pty "Hub: every section opens and returns" test_hub_opens_every_section
  _hi_par_wait

  _hi_suite_end "configure.sh logic"
}

run_configure_tests
