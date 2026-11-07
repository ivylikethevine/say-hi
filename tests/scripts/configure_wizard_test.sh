#!/usr/bin/env bash
# scripts/configure.sh's presets, the run with no tty, and the hi link's
# skip path.
# A part of configure_test.sh, a suite of its own so the Windows shards split them.
# The preamble's source line is configure_test.sh's - it sources the harness, and
# holds the helpers the parts share (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

_HI_CONFIGURE_PART=wizard
# shellcheck source=./configure_test.sh
source "${BASH_SOURCE[0]%/*}/configure_test.sh"

# the shipped defaults are core.sh's own, so a file at them sets nothing
function test_defaults_set_nothing() {
  _hi_prints "" _hi_set_lines defaults "export _HI_DISABLE_LEAD_SPACE=0" "export _HI_TRUECOLOR="
}

function test_hi_prompt_kept_when_chosen() {
  local out
  out="$(_hi_set_lines hiprompt "export _HI_PROMPT_TOOL=hi")"
  [[ "$out" == *"export _HI_PROMPT_TOOL=hi"* ]] || _hi_why out || return 1
  out="$(_hi_set_lines hiprompt2 "export _HI_PROMPT_TOOL='bash:starship hi'")"
  [[ "$out" == *"export _HI_PROMPT_TOOL='bash:starship hi'"* ]] || _hi_why out
}

# a setting no preset answers keeps what the file holds
function test_unanswered_settings_keep_their_values() {
  local out
  out="$(_hi_set_lines adv_keep "export _HI_DISABLE_LEAD_SPACE=1" "export _HI_TRUECOLOR=0")"
  [[ "$out" == *"export _HI_DISABLE_LEAD_SPACE=1"* &&
    "$out" == *"export _HI_TRUECOLOR=0"* ]] || _hi_why out
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
  mkdir -p "$dir"
  shift
  [ "$#" -eq 0 ] || printf '#!/bin/sh\n%s\n' "$*" >"$_HI_SETTINGS"
  run_configure "" </dev/null >/dev/null || return 1
  [ -f "$_HI_SETTINGS" ] && cat "$_HI_SETTINGS"
  return 0
}

# a line written by hand, its value holding a space, is adopted into the
# block rather than written again beside itself
function test_configure_adopts_a_hand_written_line() {
  local out got got2 hide='10.0.* 192.168.*'
  out="$(_hi_run_in adopt "export _HI_IP_HIDE='$hide'")" || _hi_why || return 1
  got="$(printf '%s\n' "$out" | grep -c _HI_IP_HIDE)"
  got2="$(printf '%s\n' "$out" | grep _HI_IP_HIDE)"
  [ "$got" -eq 1 ] && [[ "$got2" == *"$hide"*"$_HI_MARKER" ]] || _hi_why got got2 out _HI_MARKER
}

# ...and with 256 KB after it: an early-exiting reader in the match pipe gets
# its writer a SIGPIPE, which pipefail reads as no match, every time at this size
function test_configure_adopts_a_hand_line_in_a_large_file() {
  local out got got2 pad="" i=0 hide='10.0.* 192.168.*'
  while ((i < 4096)); do
    pad="$pad# padding padding padding padding padding padding padding pad"$'\n'
    i=$((i + 1))
  done
  out="$(_hi_run_in adopt_large "export _HI_IP_HIDE='$hide'"$'\n'"$pad")" || _hi_why || return 1
  got="$(printf '%s\n' "$out" | grep -c _HI_IP_HIDE)"
  got2="$(printf '%s\n' "$out" | grep _HI_IP_HIDE)"
  [ "$got" -eq 1 ] && [[ "$got2" == *"$hide"*"$_HI_MARKER" ]] || _hi_why got got2 _HI_MARKER
}

# ...and a hand line for a name this run does not write is left as it is
function test_configure_leaves_a_hand_line_it_does_not_write() {
  local out got got2
  out="$(_hi_run_in keephand "export _HI_MY_OWN_LINE='>'")" || _hi_why || return 1
  got="$(printf '%s\n' "$out" | grep -c _HI_MY_OWN_LINE)"
  got2="$(printf '%s\n' "$out" | grep _HI_MY_OWN_LINE)"
  [ "$got" -eq 1 ] && [[ "$got2" != *"$_HI_MARKER"* ]] || _hi_why got got2 out _HI_MARKER
}

# the block opens on its shape line, `# say-hi settings N`, which the
# converter and doctor read in place of guessing from the rows; a second
# run writes it once, and the diff report never counts it as a setting
function test_configure_opens_the_block_on_its_shape_line() {
  local out got first n shape
  n="$(sed -n 's/^_HI_SETTINGS_SHAPE=//p' "$_HI_ROOT/scripts/lib.sh")"
  [ -n "$n" ] || _hi_why n || return 1
  out="$(_hi_run_in shape "export _HI_MAX_WIDTH=100")" || _hi_why || return 1
  first="$(printf '%s\n' "$out" | grep -F "$_HI_MARKER" | sed -n 1p)"
  [[ "$first" == "# say-hi settings $n "*"$_HI_MARKER" ]] || _hi_why first out || return 1
  out="$(_hi_run_in shape)" || _hi_why || return 1
  got="$(printf '%s\n' "$out" | grep -c '^# say-hi settings ')"
  shape="$(_hi_settings_shape_of "$_HI_WORKDIR/run_shape/settings.sh")"
  [ "$got" -eq 1 ] && [ "$n" = "$shape" ] || _hi_why got shape out
}

# _hi_settings_shape_of <file> - lib.sh's reader, as the suite sees it
function _hi_settings_shape_of() {
  local shape
  _hi_settings_shape shape "$1"
  printf '%s' "$shape"
}

# no tty, no preset, and no file: a first install, which starts where a
# terminal's Enter would, from $_HI_PRESET_DEFAULT
function test_no_tty_first_run_writes_the_default_preset() {
  local got
  got="$(_hi_run_in notty)"
  [[ "$got" == *"export _HI_DISABLE_LOCAL=1"* && "$got" == *"_HI_PACKAGES_GROUPS='core,deprecated'"* ]] || _hi_why got
}

# a preset is a decision, so that run creates the file
function test_preset_run_still_creates_the_file() {
  local dir="$_HI_WORKDIR/run_preset"
  local _HI_SETTINGS="$dir/settings.sh"
  local _HI_HOME_BASHRC="$dir/none" _HI_HOME_ZSHRC="$dir/none" _HI_HOME_FISH_CONFIG="$dir/none"
  local -a _HI_SETTING_LINES=()
  _HI_SETTING_PENDING=()
  mkdir -p "$dir"
  run_configure balanced </dev/null >/dev/null || _hi_why || return 1
  grep -qF "_HI_PACKAGES_GROUPS='core,deprecated'" "$_HI_SETTINGS" || _hi_why _HI_SETTINGS
}

# _hi_diff_run <line...> - the closing report: what a run of the caller's
# $_HI_SETTING_LINES wrote against a block of <line...>, as +/- lines, read
# through config_shell's own marker padding
function _hi_diff_run() {
  config_shell settings "$_HI_SETTINGS" "$@"
  settings_diff_before
  settings_diff_report >"$_HI_CONFIG_DIR/diff.out"
}

function test_settings_diff_reports_added_and_removed() {
  local out
  local -a _HI_SETTING_LINES=("export _HI_DISABLE_PROMPT=1" "export _HI_MAX_WIDTH=120")
  _hi_settings_fixture diff _hi_diff_run "export _HI_DISABLE_PROMPT=1" "export _HI_DISABLE_GIT_STATUS=1"
  out="$(cat "$_HI_WORKDIR/diff/overlay/diff.out")"
  [[ "$out" == *"+ export _HI_MAX_WIDTH=120"* && "$out" == *"- export _HI_DISABLE_GIT_STATUS=1"* &&
    "$out" != *"_HI_DISABLE_PROMPT"* ]] || _hi_why out
}

function test_settings_diff_says_no_changes() {
  local -a _HI_SETTING_LINES=("export _HI_DISABLE_PROMPT=1")
  _hi_settings_fixture diff_same _hi_diff_run "export _HI_DISABLE_PROMPT=1"
  grep -q 'no changes' "$_HI_WORKDIR/diff_same/overlay/diff.out" || _hi_why
}

#
# A preset is an absolute answer over the `preset` rows of scripts/settings:
# what it names is set, every other preset row goes back to the default, and
# nothing outside them (width, separators, the timeouts) is touched.

# _hi_preset_rows - the names of scripts/settings' `preset` rows, a line each
function _hi_preset_rows() {
  awk -F' [|] ' '!/^#/ && $1 == "preset" { print $2 }' "$_HI_ROOT/scripts/settings"
}

function test_apply_preset_seeds_every_answer() {
  local target="$_HI_WORKDIR/preset_seed"
  printf 'export _HI_DISABLE_PROMPT=1\nexport _HI_MAX_WIDTH=120\n' >"$target"
  _HI_SETTING_PENDING=()
  apply_preset minimal >/dev/null || _hi_why || return 1
  # named by the preset: set; not named: back to the default, even though the
  # file sets it; outside the preset rows: still the file's
  _hi_prints 1 setting_value _HI_DISABLE_HEADER "$target" || return 1
  _hi_prints "" setting_value _HI_DISABLE_PROMPT "$target" || return 1
  _hi_prints 120 setting_value _HI_MAX_WIDTH "$target"
}

function test_apply_preset_rejects_a_stranger() {
  _HI_SETTING_PENDING=()
  ! apply_preset no-such-preset 2>/dev/null || _hi_why
}

# preset_shorthand is what the typed reply goes through before apply_preset,
# tested directly: config_pick_preset is `[ -t 0 ]`-gated, and the
# resolution it does has nothing to do with a tty
function test_preset_shorthand_resolves_each_first_letter() {
  local got got2 got3
  got="$(preset_shorthand e)"
  got2="$(preset_shorthand b)"
  got3="$(preset_shorthand m)"
  [ "$got" = "everything" ] && [ "$got2" = "balanced" ] && [ "$got3" = "minimal" ] || _hi_why got got2 got3
}

# two presets sharing a letter refuse it rather than guess, and an exact
# name still resolves
function test_preset_shorthand_refuses_ambiguity() {
  local got
  local -a _HI_PRESETS=("alpha|first|a b" "apex|second|c d" "zulu|third|e f")
  got="$(preset_shorthand z)"
  [ "$got" = zulu ] || _hi_why got || return 1
  got="$(preset_row apex)"
  [ "$got" = "apex|second|c d" ] || _hi_why got || return 1
  ! preset_shorthand a 2>/dev/null || _hi_why
}

function test_preset_shorthand_rejects_unknown_letter() {
  ! preset_shorthand z 2>/dev/null || _hi_why
}

function test_preset_shorthand_rejects_multiple_characters() {
  ! preset_shorthand ev 2>/dev/null || _hi_why
}

# ...or a setting outside them, as lean names _HI_PROMPT_TOOL and
# _HI_BACKENDS_OFF: a row of scripts/settings, never an invented name
function test_every_preset_names_only_settings() {
  local row values pair settings
  settings="$(sed -n 's/^[a-z]* | \(_HI_[A-Z0-9_]*\) |.*/\1/p' "$_HI_ROOT/scripts/settings")"
  # shellcheck disable=SC2153 # _HI_PRESETS is configure.sh's table, not a typo of --preset's var
  for row in "${_HI_PRESETS[@]}"; do
    values="${row##*|}"
    for pair in $values; do
      case $'\n'"$settings"$'\n' in *$'\n'"${pair%%=*}"$'\n'*) ;; *) _hi_why settings pair || return 1 ;; esac
    done
  done
}

# the header order, the hidden addresses and the prompt program stay out of
# the preset rows on purpose: a preset resets every row it does not name, so
# one of them there would make every preset silently reset it
function test_preset_rows_exclude_the_order() {
  local vocab
  vocab="$(_hi_preset_rows)"
  [ -n "$vocab" ] || _hi_why vocab || return 1
  { ! grep -qx _HI_HEADER_ORDER <<<"$vocab" &&
    ! grep -qx _HI_IP_HIDE <<<"$vocab" &&
    ! grep -qx _HI_MAX_WIDTH <<<"$vocab" &&
    ! grep -qx _HI_PROMPT_TOOL <<<"$vocab"; } || _hi_why vocab
}

# the whole run with --preset, no tty: exactly the preset's lines land in the
# block, a value outside the preset rows survives, and one inside them that
# the preset does not name is commented. The fixture is written through config_shell,
# so the before-state is the marked block a real run would find.
function _hi_preset_run() {
  config_shell settings "$_HI_SETTINGS" "export _HI_PLUGINS_OFF='nano'" "export _HI_MAX_WIDTH=120"
  _HI_SETTING_LINES=()
  _HI_SETTING_PENDING=()
  run_configure balanced </dev/null
}

function test_preset_run_writes_the_preset() {
  local block
  _hi_settings_fixture preset_run _hi_preset_run
  block="$(grep -F "$_HI_MARKER" "$(_hi_fixture_settings preset_run)" | grep "^export ")"
  [[ "$block" == *"export _HI_PACKAGES_GROUPS='core,deprecated'"* &&
    "$block" == *"export _HI_MAX_WIDTH=120"* && "$block" != *"_HI_PLUGINS_OFF"* ]] || _hi_why block
}

# lean names two variables outside the preset rows: they are written with the
# rest, and a later preset that does not name them leaves them be. Its list
# kept home is every plugin of config/plugins but the hooks, in its order.
function _hi_preset_lean_run() {
  _HI_SETTING_LINES=()
  _HI_SETTING_PENDING=()
  run_configure lean </dev/null || return 1
  _HI_SETTING_LINES=()
  _HI_SETTING_PENDING=()
  cp "$_HI_SETTINGS" "$_HI_SETTINGS.lean"
  run_configure everything </dev/null
}

function test_preset_lean_sets_what_no_other_resets() {
  local f lean block all
  _hi_settings_fixture preset_lean _hi_preset_lean_run
  f="$(_hi_fixture_settings preset_lean)"
  lean="$(grep -F "$_HI_MARKER" "$f.lean" | grep "^export ")"
  block="$(grep -F "$_HI_MARKER" "$f" | grep "^export ")"
  all="$(sed -n 's/^\[\([^].]*\)\.\([^].]*\)\]$/\1 \2/p' "$_HI_ROOT/config/plugins" | grep -v '^hooks ' | cut -d' ' -f2 | tr '\n' ',')"
  [[ "$lean" == *"export _HI_PLUGINS_OFF='${all%,}'"* &&
    "$lean" == *"export _HI_PROMPT_TOOL=hi"* && "$lean" == *"export _HI_BACKENDS_OFF='all'"* ]] &&
    [[ "$block" != *"_HI_PLUGINS_OFF"* && "$block" == *"export _HI_PROMPT_TOOL=hi"* &&
      "$block" == *"export _HI_BACKENDS_OFF='all'"* ]] || _hi_why lean all block
}

function test_install_rejects_an_unknown_preset() {
  ! bash "$_HI_INSTALL" --configure --preset nope </dev/null >/dev/null 2>&1 || _hi_why _HI_INSTALL
}

function test_config_hi_skips_when_already_linked() {
  local link="$_HI_WORKDIR/already-linked"
  ln -sfn "$_HI_LAUNCHER" "$link"
  (
    _HI_LINK="$link"
    config_hi
  ) | grep -q "already points at" || _hi_why link
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
  ) | grep -q "couldn't make" || _hi_why dir link
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
  [[ "$out" == *"already points at"* && "$out" != *"CHMOD RAN"* ]] || _hi_why out
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
      _hi_why -3 || return 1
    }
    _HI_LAUNCHER="$dir/hi.sh"
    _HI_LINK="$dir/bin/hi"
    config_hi
  ) >/dev/null
  _hi_prints "$dir/hi.sh" readlink "$dir/bin/hi"
}

# config_hi's own lockout degradation (both the refused-sudo and the
# no-sudo-at-all shape of it) is tests/scripts/install_test.sh's to assert -
# link_hi_by_hand is the one function behind both, and that suite's
# "Instructs when sudo is refused"/"Instructs with no sudo at all" check that
# output, down to the fixture.
#

# the whole run with neither a preset nor a tty: nothing is asked, and the
# rewrite reproduces the block it found rather than dropping it
function _hi_no_preset_run() {
  config_shell settings "$_HI_SETTINGS" "export _HI_DISABLE_GIT_STATUS=1"
  _HI_SETTING_LINES=()
  _HI_SETTING_PENDING=()
  run_configure "" </dev/null
}

function test_run_configure_without_a_preset_keeps_the_block() {
  local block
  _hi_settings_fixture nopreset _hi_no_preset_run
  block="$(grep -F "$_HI_MARKER" "$(_hi_fixture_settings nopreset)")"
  [[ "$block" == *"export _HI_DISABLE_GIT_STATUS=1"* ]] || _hi_why block
}

function run_configure_wizard_tests() {
  _hi_configure_begin

  _hi_h1 "Testing scripts/configure.sh's reusable logic (presets and the run)"

  _hi_h2 "Testing: the run, and the closing report"
  _hi_check "Settings at their defaults set nothing" test_defaults_set_nothing
  _hi_check "hi's prompt is kept when chosen" test_hi_prompt_kept_when_chosen
  _hi_check "A setting no preset answers keeps its value" test_unanswered_settings_keep_their_values
  _hi_check "A hand-written line is adopted, not duplicated" test_configure_adopts_a_hand_written_line
  _hi_check "...in a settings.sh of 256 KB too" test_configure_adopts_a_hand_line_in_a_large_file
  _hi_check "A hand line this run does not write is left alone" test_configure_leaves_a_hand_line_it_does_not_write
  _hi_check "The block opens on its shape line, written once" test_configure_opens_the_block_on_its_shape_line
  _hi_check "No tty and no file: the default preset is written" test_no_tty_first_run_writes_the_default_preset
  _hi_check "A preset run creates the file" test_preset_run_still_creates_the_file
  _hi_check "Diff reports added and removed lines" test_settings_diff_reports_added_and_removed
  _hi_check "Diff says no changes" test_settings_diff_says_no_changes

  _hi_h2 "Testing: presets"
  _hi_check "A preset seeds every answer of its rows" test_apply_preset_seeds_every_answer
  _hi_check "lean sets what no other preset resets" test_preset_lean_sets_what_no_other_resets
  _hi_check "An unknown preset is refused" test_apply_preset_rejects_a_stranger
  _hi_check "Shorthand resolves each preset's first letter" test_preset_shorthand_resolves_each_first_letter
  _hi_check "Shorthand refuses ambiguity" test_preset_shorthand_refuses_ambiguity
  _hi_check "Shorthand rejects an unknown letter" test_preset_shorthand_rejects_unknown_letter
  _hi_check "Shorthand rejects more than one character" test_preset_shorthand_rejects_multiple_characters
  _hi_check "Every preset names only settings" test_every_preset_names_only_settings
  _hi_check "The preset rows exclude the order" test_preset_rows_exclude_the_order
  _hi_check "--preset writes exactly the preset" test_preset_run_writes_the_preset
  _hi_check "install.sh refuses an unknown --preset" test_install_rejects_an_unknown_preset
  _hi_check "No preset and no tty keeps the block" test_run_configure_without_a_preset_keeps_the_block

  _hi_h2 "Testing: config_hi (skip path only)"
  _hi_check_capable symlink "Skips when already linked" test_config_hi_skips_when_already_linked
  _hi_check_capable symlink "Survives an unwritable launcher" test_config_hi_survives_an_unwritable_launcher
  _hi_check_capable symlink "Skips chmod when already executable" test_config_hi_skips_chmod_when_already_executable
  _hi_check_capable symlink "Links plainly into a writable bindir" test_config_hi_links_plainly_when_bindir_is_writable

  _hi_suite_end "configure.sh logic (presets and the run)"
}

run_configure_wizard_tests
