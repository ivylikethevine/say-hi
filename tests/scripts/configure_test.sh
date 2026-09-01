#!/usr/bin/env bash
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

# Three questions, one per shell, all of which have to survive being written to
# a file four shells source. Every case runs non-interactive (`</dev/null`, no
# tty), which is the path that keeps whatever is already configured.

# _hi_prompt_ends_lines [existing-settings-line ...] - what config_prompt_ends
# would write, as one string
function _hi_prompt_ends_lines() {
  local dir="$_HI_WORKDIR/promptends"
  local _HI_SETTINGS="$dir/settings.sh"
  local -a _HI_SETTING_LINES=()
  mkdir -p "$dir"
  [ "$#" -eq 0 ] && : >"$_HI_SETTINGS" || printf '%s\n' "$@" >"$_HI_SETTINGS"
  # >/dev/null: the section heading is stdout, the lines are the array
  config_prompt_ends </dev/null >/dev/null
  printf '%s' "${_HI_SETTING_LINES[*]}"
}

# the shipped defaults are core.sh's own, so writing them out would be noise
# that then has to be kept in sync - the same rule config_max_width has for 80
function test_prompt_ends_writes_nothing_for_the_defaults() {
  [ -z "$(_hi_prompt_ends_lines | tr -d ' ')" ]
}

function test_prompt_ends_keeps_an_existing_override() {
  local out
  out="$(_hi_prompt_ends_lines "export _HI_PROMPT_END_ZSH='::'")"
  [[ "$out" == *"export _HI_PROMPT_END_ZSH='::'"* ]]
}

# quoted on the way out: a separator is as likely to be $ or > as a letter, and
# the file is sourced by sh, bash, zsh and fish alike
function test_prompt_ends_quotes_what_it_writes() {
  local out
  out="$(_hi_prompt_ends_lines "export _HI_PROMPT_END_BASH='>'")"
  [[ "$out" == *"_HI_PROMPT_END_BASH='>'"* ]]
}

# the prompt is off, so what it ends with is moot - the same skip
# config_header_details makes when the header itself is off
function test_prompt_ends_skipped_when_the_prompt_is_off() {
  local out
  out="$(_hi_prompt_ends_lines "export _HI_DISABLE_PROMPT=1" "export _HI_PROMPT_END_ZSH='::'")"
  [ -z "$(printf '%s' "$out" | tr -d ' ')" ]
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
# rather than dropping it, it does not restate the shipped default, and it does
# not ask about a check that is switched off. The loop itself needs a terminal
# and is skipped when there is none, which is what makes these callable here -
# provided stdin really is not one: run by hand from a terminal it would be,
# and the case would sit at the prompt, so it is fed /dev/null explicitly.
# _hi_settings_fixture swallows stdout (its other users assert against the file
# it wrote), so the collected lines go to a file inside the fixture instead -
# otherwise "no lines" and "lines nobody saw" look identical and two of these
# three would pass without asserting anything.
function _hi_floor_run() {
  mkdir -p "$_HI_CONFIG_DIR"
  printf '#!/bin/sh\n%s\n' "$1" >"$_HI_SETTINGS"
  _HI_SETTING_LINES=()
  _HI_SETTING_PENDING=()
  config_packages_floor </dev/null
  printf '%s\n' ${_HI_SETTING_LINES[@]+"${_HI_SETTING_LINES[@]}"} >"$_HI_CONFIG_DIR/lines.out"
}

function _hi_floor_lines() { cat "$_HI_WORKDIR/$1/config/lines.out" 2>/dev/null; }

function test_packages_floor_keeps_a_configured_value() {
  _hi_settings_fixture floor_keep _hi_floor_run 'export _HI_PACKAGES_MIN_PRIORITY=3'
  [ "$(_hi_floor_lines floor_keep)" = "export _HI_PACKAGES_MIN_PRIORITY=3" ]
}

# 1 is header.sh's own default via ${_HI_PACKAGES_MIN_PRIORITY:-1}, so writing
# it out would be a line that means nothing - the same rule config_max_width
# has for 80.
function test_packages_floor_does_not_write_the_default() {
  _hi_settings_fixture floor_default _hi_floor_run 'export _HI_PACKAGES_MIN_PRIORITY=1'
  [ -f "$_HI_WORKDIR/floor_default/config/lines.out" ] || return 1
  [ -z "$(_hi_floor_lines floor_default | tr -d '[:space:]')" ]
}

# ...and the other side of that rule: 0 is an answer like any other - "put the
# trivia tier back" - so it has to survive as a line rather than being elided as the default.
function test_packages_floor_writes_a_zero() {
  _hi_settings_fixture floor_zero _hi_floor_run 'export _HI_PACKAGES_MIN_PRIORITY=0'
  [ "$(_hi_floor_lines floor_zero)" = "export _HI_PACKAGES_MIN_PRIORITY=0" ]
}

function test_packages_floor_is_skipped_when_the_check_is_off() {
  _hi_settings_fixture floor_off _hi_floor_run 'export _HI_HEADER_CHECK=0'
  # the file has to exist - a skip that never ran the function at all would
  # leave no file and pass the emptiness check for the wrong reason
  [ -f "$_HI_WORKDIR/floor_off/config/lines.out" ] || return 1
  [ -z "$(_hi_floor_lines floor_off | tr -d '[:space:]')" ]
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
# a python3 without the Unix-only `pty` module - which is what makes these skip
# yellow rather than fail: the backend suites' doctrine, for the same reason.
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
  _hi_wait_pid "$!" 30 _hi_timed_out "$label" 30
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
  [ "${#_HI_PTY_FORCED[@]}" -eq 0 ] && {
    _hi_skip "[floor_junk]" "no usable pty to drive an interactive case"
    return 0
  }
  _hi_floor_pty floor_junk 'zz\nyy\nxx\nww\nvv\nuu\ntt\nss\n' || return 1
  _hi_floor_finished floor_junk || return 1
  [ "$(_hi_floor_prompts floor_junk)" -le 3 ]
}

# EOF is not an answer: one prompt, then out.
function test_packages_floor_ends_on_eof() {
  [ "${#_HI_PTY_FORCED[@]}" -eq 0 ] && {
    _hi_skip "[floor_eof]" "no usable pty to drive an interactive case"
    return 0
  }
  _hi_floor_pty floor_eof '\004' || return 1
  _hi_floor_finished floor_eof || return 1
  [ "$(_hi_floor_prompts floor_eof)" -le 1 ]
}

# a rejected answer must not poison the ones after it - the reject count
# resets, so this still lands on 2 rather than giving up first.
function test_packages_floor_takes_a_number_after_a_rejection() {
  [ "${#_HI_PTY_FORCED[@]}" -eq 0 ] && {
    _hi_skip "[floor_recover]" "no usable pty to drive an interactive case"
    return 0
  }
  _hi_floor_pty floor_recover 'zz\n2\n2\n' || return 1
  [ "$(_hi_floor_pty_lines floor_recover)" = "export _HI_PACKAGES_MIN_PRIORITY=2" ]
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
  local -a _HI_SETTING_LINES=("export _HI_DISABLE_PROMPT=1" "" "export _HI_HEADER_CHECK=0")
  mkdir -p "$_HI_CONFIG_DIR"
  config_shell settings "$_HI_SETTINGS" "${_HI_SETTING_LINES[@]}"
}

function test_config_settings_writes_every_group_at_once() {
  _hi_settings_fixture onewrite _hi_settings_one_write
  local f
  f="$(_hi_fixture_settings onewrite)"
  grep -qF "export _HI_DISABLE_PROMPT=1" "$f" && grep -qF "export _HI_HEADER_CHECK=0" "$f"
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
  printf 'export _HI_HEADER_TIMESTAMP=0\n' >"$target"
  setting_off _HI_HEADER_TIMESTAMP "$target" 0
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
# (_HI_ENABLE_FISH_ALIAS_ABBR=1, _HI_PROMPT=starship) is on only when its
# on-value is. setting_on is the one reader of both, and ask_prompt_group
# writes both.

function test_setting_on_opt_in_absent_is_off() {
  local target="$_HI_WORKDIR/opt_in_absent"
  : >"$target"
  _HI_SETTING_PENDING=()
  ! setting_on _HI_ENABLE_FISH_ALIAS_ABBR "$target" 0 1
}

function test_setting_on_opt_in_present_is_on() {
  local target="$_HI_WORKDIR/opt_in_present"
  printf 'export _HI_ENABLE_FISH_ALIAS_ABBR=1\n' >"$target"
  _HI_SETTING_PENDING=()
  setting_on _HI_ENABLE_FISH_ALIAS_ABBR "$target" 0 1
}

function test_setting_on_toggle_absent_is_on() {
  local target="$_HI_WORKDIR/toggle_absent"
  : >"$target"
  _HI_SETTING_PENDING=()
  setting_on _HI_DISABLE_FOO "$target" 1
}

# _hi_section_lines <name> <fn> [settings-line ...] - what <fn> would write,
# non-interactively (stdin is /dev/null, so every question keeps what the
# file holds), as one string
function _hi_section_lines() {
  local dir="$_HI_WORKDIR/section_$1" fn="$2"
  local _HI_SETTINGS="$dir/settings.sh"
  local -a _HI_SETTING_LINES=()
  _HI_SETTING_PENDING=()
  mkdir -p "$dir"
  shift 2
  [ "$#" -eq 0 ] && : >"$_HI_SETTINGS" || printf '%s\n' "$@" >"$_HI_SETTINGS"
  "$fn" </dev/null >/dev/null
  printf '%s' "${_HI_SETTING_LINES[*]:-}"
}

# an opt-in that is off writes nothing - there is no "=0" spelling of it
function test_opt_in_off_writes_nothing() {
  [ -z "$(_hi_section_lines prompt_default config_prompt_ends | tr -d ' ')" ]
}

function test_starship_kept_when_chosen() {
  local out
  out="$(_hi_section_lines starship config_prompt_ends "export _HI_PROMPT=starship")"
  [[ "$out" == *"export _HI_PROMPT=starship"* ]]
}

# the gate declined (here: nobody to answer it) keeps every advanced value,
# quoting included - the section runs, it just is not asked
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

# a row whose <needs> command is absent is carried, not asked and not dropped
function test_prompt_group_carries_a_row_it_cannot_ask() {
  local out dir="$_HI_WORKDIR/needs"
  local _HI_SETTINGS="$dir/settings.sh"
  local -a _HI_SETTING_LINES=() _HI_NEEDS_PROMPTS=("_HI_ENABLE_FISH_ALIAS_ABBR|0|1|| moot?|no-such-command-$$")
  _HI_SETTING_PENDING=()
  mkdir -p "$dir"
  printf 'export _HI_ENABLE_FISH_ALIAS_ABBR=1\n' >"$_HI_SETTINGS"
  ask_prompt_group _HI_NEEDS_PROMPTS </dev/null
  out="${_HI_SETTING_LINES[*]:-}"
  [[ "$out" == *"export _HI_ENABLE_FISH_ALIAS_ABBR=1"* ]]
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
  config_shell settings "$_HI_SETTINGS" "export _HI_DISABLE_PROMPT=1" "export _HI_HEADER_CHECK=0"
  settings_diff_before
  settings_diff_report >"$_HI_CONFIG_DIR/diff.out"
}

function test_settings_diff_reports_added_and_removed() {
  local out
  _hi_settings_fixture diff _hi_diff_run
  out="$(cat "$_HI_WORKDIR/diff/config/diff.out")"
  [[ "$out" == *"+ export _HI_MAX_WIDTH=120"* && "$out" == *"- export _HI_HEADER_CHECK=0"* &&
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

# the whole run with --preset, no tty: exactly the preset's lines land in the
# block, a value outside the vocabulary survives, and one inside it that the
# preset does not name is gone. The fixture is written through config_shell,
# so the before-state is the marked block a real run would find.
function _hi_preset_run() {
  mkdir -p "$_HI_CONFIG_DIR"
  config_shell settings "$_HI_SETTINGS" "export _HI_DISABLE_EDITORS=1" "export _HI_MAX_WIDTH=120"
  _HI_SETTING_LINES=()
  _HI_SETTING_PENDING=()
  _HI_PRESET_FINAL=""
  run_configure balanced </dev/null
}

function test_preset_run_writes_the_preset() {
  local block
  _hi_settings_fixture preset_run _hi_preset_run
  block="$(grep -F "$_HI_MARKER" "$(_hi_fixture_settings preset_run)")"
  [[ "$block" == *"export _HI_HEADER_TIMESTAMP=0"* && "$block" == *"export _HI_HEADER_IDENTITY=0"* &&
    "$block" == *"export _HI_PACKAGES_MIN_PRIORITY=3"* && "$block" == *"export _HI_DISABLE_NOTIFY=1"* &&
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

  _hi_h2 "Testing: config_prompt_ends"
  _hi_check "Defaults write nothing" test_prompt_ends_writes_nothing_for_the_defaults
  _hi_check "An existing override is kept" test_prompt_ends_keeps_an_existing_override
  _hi_check "Written values are quoted" test_prompt_ends_quotes_what_it_writes
  _hi_check "Skipped when the prompt is off" test_prompt_ends_skipped_when_the_prompt_is_off

  _hi_h2 "Testing: overlay_init / overlay_commit"
  _hi_check_requires git "Init makes a repo with a first commit" test_overlay_init_creates_a_repo_with_a_first_commit
  _hi_check_requires git "Init is idempotent" test_overlay_init_is_idempotent
  _hi_check_requires git "Init seeds the shipped defaults" test_overlay_init_seeds_the_shipped_defaults
  _hi_check_requires git "...and never overwrites a present file" test_overlay_init_never_overwrites_a_present_file
  _hi_check_requires git "A tracked overlay commits settings writes" test_overlay_commit_records_a_change_when_tracked
  _hi_check_requires git "Nothing new, no commit" test_overlay_commit_is_a_noop_with_nothing_new
  _hi_check_requires git "An untracked overlay never hears about git" test_overlay_commit_never_creates_a_repo

  _hi_h2 "Testing: ensure_settings_shebang"
  _hi_check "Written to a new settings.sh" test_shebang_is_written_to_a_new_settings_file
  _hi_check "Stays first under the settings block" test_shebang_stays_first_under_the_settings_block
  _hi_check "Not duplicated on reruns" test_shebang_is_not_duplicated_on_reruns
  _hi_check "Packages floor: an existing value survives" test_packages_floor_keeps_a_configured_value
  _hi_check "Packages floor: the default is not written" test_packages_floor_does_not_write_the_default
  _hi_check "Packages floor: a zero is written out" test_packages_floor_writes_a_zero
  _hi_check "Packages floor: skipped when the check is off" test_packages_floor_is_skipped_when_the_check_is_off
  _hi_check "Packages floor: junk stops the loop" test_packages_floor_stops_asking_for_a_number
  _hi_check "Packages floor: EOF ends the prompt" test_packages_floor_ends_on_eof
  _hi_check "Packages floor: a number lands after a rejection" test_packages_floor_takes_a_number_after_a_rejection
  _hi_check "Replaces a different shebang" test_shebang_replaces_a_different_one_and_keeps_content
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
  _hi_check "Advanced: declined keeps every value" test_advanced_declined_keeps_every_value
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
  _hi_check "--preset writes exactly the preset" test_preset_run_writes_the_preset
  _hi_check "install.sh refuses an unknown --preset" test_install_rejects_an_unknown_preset

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

  _hi_suite_end "configure.sh logic"
}

run_configure_tests
