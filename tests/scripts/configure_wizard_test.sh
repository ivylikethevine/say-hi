#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# scripts/configure.sh's opt-ins, presets, the skip path, and the previews its
# questions draw.
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

function run_configure_wizard_tests() {
  _hi_configure_begin

  _hi_h1 "Testing scripts/configure.sh's reusable logic (the wizard's pages)"

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

  _hi_suite_end "configure.sh logic (the wizard's pages)"
}

run_configure_wizard_tests
