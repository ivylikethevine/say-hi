#!/usr/bin/env bash
# Unit tests for common/paths.sh's local-only gate: the toggle flip at the
# bottom of the file, which is what _HI_DISABLE_LOCAL means. It turns every
# toggle off on the machine say-hi is *installed* on while leaving them on when
# that machine says `hi` elsewhere, told apart by _HI_REMOTE_SESSION (load.sh
# exports it; a local rc never does). Backwards, it would either strip hi from
# every target or leave it running where the user asked it not to.
#
# Each case sources paths.sh in its own child shell so exports can't leak, and
# reads the variables back out - which also proves settings.sh is picked up
# ahead of the gate rather than after it.
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

_HI_GATED_VARS=(_HI_DISABLE_HEADER _HI_DISABLE_PROMPT
  _HI_DISABLE_GIT_STATUS _HI_DISABLE_EDITORS
  _HI_DISABLE_OSC52 _HI_DISABLE_NOTIFY _HI_DISABLE_MARKS
  _HI_DISABLE_BAT_ALIAS _HI_DISABLE_EZA_CONFIG _HI_DISABLE_LS_ALIASES)

# Source paths.sh in a child shell with $1/$2 as the two gate inputs, then
# print "<var>=<value>" for every toggle the gate governs. core.sh does the
# defaulting paths.sh relies on ( _HI_DISABLE_LOCAL / _HI_REMOTE_SESSION both
# have to exist), so the child goes through it exactly like a real shell.
function _hi_gate() {
  _HI_DISABLE_LOCAL="$1" _HI_REMOTE_SESSION="$2" bash -c '
    source "$_HI_HOME/say-hi/common/core.sh"
    for v in "$@"; do printf "%s=%s\n" "$v" "${!v:-}"; done
  ' _ "${_HI_GATED_VARS[@]}"
}

function _hi_all_gated() {
  local out="$1" want="$2" v
  for v in "${_HI_GATED_VARS[@]}"; do
    printf '%s\n' "$out" | grep -qxF "$v=$want" || {
      _hi_cecho " | $v is not $want: $(printf '%s\n' "$out" | grep "^$v=")" "$RED"
      return 1
    }
  done
}

# _HI_DISABLE_LOCAL=1 on the install machine itself: hi stays out of the way
function test_local_only_disables_every_toggle_locally() {
  _hi_all_gated "$(_hi_gate 1 0)" 1
}

# The same gate over core.sh's other roster, where "off" is 0 rather than 1:
# _HI_OPT_INS ships off, so the gate has to leave it off (or put it back) on
# the local machine rather than setting it to 1 the way it does a disable.
# Without this the two polarities drift silently - a 1 here would mean
# "_HI_DISABLE_LOCAL=1 turned the scratch history on", the exact inversion
# _HI_DISABLE_OSC52 once suffered in the other direction.
function test_local_only_leaves_opt_ins_off_locally() {
  local out
  out="$(_HI_DISABLE_LOCAL=1 _HI_REMOTE_SESSION=0 _HI_SCRATCH_HISTORY=1 bash -c '
    source "$_HI_HOME/say-hi/common/core.sh"
    printf "%s" "${_HI_SCRATCH_HISTORY:-}"
  ')"
  [ "$out" = 0 ] || {
    _hi_cecho " | _HI_SCRATCH_HISTORY is $out under the local-only gate, wanted 0" "$RED"
    return 1
  }
}

# ...but the same setting must not follow the user onto a target, which is the
# entire reason the gate looks at _HI_REMOTE_SESSION at all.
#
# "Not disabled" is an explicit 0 rather than an empty value: the entry points
# default every toggle so that aliases.sh and config.fish, which read them
# bare, can't blow up under `set -u`. Asserting 0 here is what keeps that true.
function test_local_only_leaves_a_remote_session_alone() {
  _hi_all_gated "$(_hi_gate 1 1)" 0
}

function test_toggles_stay_on_without_local_only() {
  _hi_all_gated "$(_hi_gate 0 0)" 0
}

function test_toggles_stay_on_remotely_without_local_only() {
  _hi_all_gated "$(_hi_gate 0 1)" 0
}

# The gate's list has to be core.sh's _HI_TOGGLES minus the gate's own two
# inputs - paths.sh can't loop the roster (its four-shell dialect has no
# loops), so it spells the list out, and a toggle added to core.sh that never
# reaches it is exactly how _HI_DISABLE_OSC52 once went
# missing from "all of the above". The behavioral cases above walk
# _HI_GATED_VARS, so pinning that list to the roster pins the gate.
function test_gate_list_matches_the_toggle_roster() {
  local t
  local -a want=()
  for t in "${_HI_TOGGLES[@]}"; do
    case "$t" in _HI_DISABLE_LOCAL | _HI_REMOTE_SESSION) continue ;; esac
    want+=("$t")
  done
  [ "${want[*]}" = "${_HI_GATED_VARS[*]}" ] || {
    _hi_cecho " | roster (minus gate inputs): ${want[*]}" "$RED"
    _hi_cecho " | gated:                      ${_HI_GATED_VARS[*]}" "$RED"
    return 1
  }
}

# config.fish can't read the roster either (fish parses no bash), so it
# carries a hand-written mirror in its toggle-defaulting loop - this is the
# whole-list drift guard that mirror never had
function test_fish_toggle_list_matches_core() {
  local fish_list core_list
  fish_list="$(awk '/^for _hi_toggle in /{p=1} p{print; if ($0 !~ /\\$/) exit}' \
    "$_HI_ROOT/common/config.fish" | grep -oE '_HI_[A-Z0-9_]+')"
  core_list="$(printf '%s\n' "${_HI_TOGGLES[@]}")"
  [ "$fish_list" = "$core_list" ] || {
    _hi_cecho " | config.fish: $(printf '%s' "$fish_list" | tr '\n' ' ')" "$RED"
    _hi_cecho " | core.sh:     ${_HI_TOGGLES[*]}" "$RED"
    return 1
  }
}

# the gate is the last thing paths.sh does and it ends in `|| true`, so a
# no-flip run must still leave the file sourceable under set -e
function test_paths_sources_cleanly_under_strict_mode() {
  _HI_DISABLE_LOCAL=0 _HI_REMOTE_SESSION=0 bash -c '
    set -euo pipefail
    source "$_HI_HOME/say-hi/common/core.sh"
    [ -n "$_HI_ROOT" ]
  '
}

# settings/aliases.sh and common/config.fish read the toggles bare, and neither
# can use ${X:-0} because fish sources both and has no such expansion. So the
# entry points guarantee the variables exist instead. Getting this wrong is
# invisible until something runs under `set -u`, where an unset toggle is fatal
# rather than empty - which is exactly how `hi <target> <command>` broke.

function _hi_defaults_via() {
  bash -c "$1"' ; for v in '"${_HI_GATED_VARS[*]}"' _HI_DISABLE_LOCAL _HI_REMOTE_SESSION; do
    printf "%s=%s\n" "$v" "${!v-UNSET}"; done'
}

function _hi_none_unset() {
  local out="$1" v
  for v in "${_HI_GATED_VARS[@]}" _HI_DISABLE_LOCAL _HI_REMOTE_SESSION; do
    printf '%s\n' "$out" | grep -qxF "$v=UNSET" && {
      _hi_cecho " | $v is still unset" "$RED"
      return 1
    }
  done
  return 0
}

# core.sh is the one entry point for bash and zsh, and what config.fish's
# `bash -c` reaches directly
function test_core_defines_every_toggle() {
  # shellcheck disable=SC2016 # this is source for a child bash, not for us
  _hi_none_unset "$(_hi_defaults_via 'source "$_HI_HOME/say-hi/common/core.sh"')"
}

# the whole point: sourcing aliases.sh under `set -u` must not be fatal
function test_aliases_source_cleanly_under_nounset() {
  bash -c 'set -euo pipefail
    source "$_HI_HOME/say-hi/common/core.sh"
    source "$_HI_ALIASES"' 2>/dev/null
}

# The overlay's aliases.sh is additive - settings/aliases.sh's last line sources
# $_HI_CONFIG_DIR/aliases.sh so the user's definitions win. Point
# $_HI_CONFIG_DIR at the tree's own settings/ and that line becomes the file
# sourcing itself, forever: exactly what a target does when the overlay is
# unpacked over settings/ instead of into its own config/, and what hung every ssh
# session until the overlay got a directory of its own. Backgrounded and
# waited on because a hang, not a failure, is the symptom - a bare call here
# would take the whole suite down with it.
function test_aliases_do_not_source_themselves() {
  _HI_CONFIG_DIR="$_HI_ROOT/settings" bash -c 'set -eu
    . "$_HI_HOME/say-hi/common/paths.sh"
    . "$_HI_ALIASES"' >/dev/null 2>&1 &
  _hi_wait_pid "$!" 10
  [ "$_HI_WAIT_EXIT" != 124 ]
}

function test_settings_beat_the_defaults() {
  local dir
  dir="$(_hi_overlay_dir)"
  printf 'export _HI_DISABLE_PROMPT=1\n' >"$dir/settings.sh"
  [ "$(_HI_CONFIG_DIR="$dir" bash -c \
    'source "$_HI_HOME/say-hi/common/core.sh"; printf "%s" "$_HI_DISABLE_PROMPT"')" = 1 ]
}

# an explicit export from the caller's environment outranks the default too,
# which is what makes `_HI_DISABLE_PROMPT=1 bash` work as a one-off
function test_environment_beats_the_defaults() {
  [ "$(_HI_DISABLE_EDITORS=1 bash -c \
    'source "$_HI_HOME/say-hi/common/core.sh"; printf "%s" "$_HI_DISABLE_EDITORS"')" = 1 ]
}

# colors and packages each resolve to $_HI_CONFIG_DIR's copy when the user has
# made one and to the tree's otherwise, per file rather than all-or-nothing;
# settings.sh only ever resolves to the overlay, since that is the only place
# install.sh writes it. That is what keeps configuring say-hi from dirtying the
# checkout - and what lets the tree be root-owned, which is the whole reason a
# distro package can work.
#
# test_lib.sh points $_HI_CONFIG_DIR at a scratch path that doesn't exist, so
# the un-overridden direction is the default here and a real ~/.config/say-hi
# can't decide the result.

# Print $1's value from a child shell that went through core.sh, with
# $_HI_CONFIG_DIR pointed at $2.
function _hi_resolved() {
  _HI_CONFIG_DIR="$2" bash -c \
    'source "$_HI_HOME/say-hi/common/core.sh"; printf "%s" "${!1}"' _ "$1"
}

function _hi_overlay_dir() {
  local dir="$_HI_WORKDIR/overlay"
  mkdir -p "$dir"
  printf '%s' "$dir"
}

function test_settings_resolve_to_the_overlay() {
  local dir
  dir="$(_hi_overlay_dir)"
  printf '#!/bin/sh\n' >"$dir/settings.sh"
  [ "$(_hi_resolved _HI_SETTINGS "$dir")" = "$dir/settings.sh" ]
}

function test_overlay_colors_win() {
  local dir
  dir="$(_hi_overlay_dir)"
  printf 'hostname,foo,brred\n' >"$dir/colors"
  [ "$(_hi_resolved _HI_COLORS "$dir")" = "$dir/colors" ]
}

# per file, not all-or-nothing: an overlay holding only colors must leave
# packages tracking the tree, or `hi --update` would stop delivering new defaults
# for everything the user never overrode
function test_overlay_falls_back_per_file() {
  local dir
  dir="$(_hi_overlay_dir)"
  printf 'hostname,foo,brred\n' >"$dir/colors"
  rm -f "$dir/packages"
  [ "$(_hi_resolved _HI_PACKAGES "$dir")" = "$_HI_ROOT/settings/packages" ]
}

function test_no_overlay_uses_the_tree() {
  local dir="$_HI_WORKDIR/no-such-overlay"
  [ "$(_hi_resolved _HI_COLORS "$dir")" = "$_HI_ROOT/settings/colors" ] &&
    [ "$(_hi_resolved _HI_PACKAGES "$dir")" = "$_HI_ROOT/settings/packages" ]
}

# ...but settings.sh still points into the overlay on a machine that has no
# overlay yet, unguarded, because that is where install.sh has to write it
function test_settings_point_at_the_overlay_before_it_exists() {
  local dir="$_HI_WORKDIR/no-such-overlay"
  [ "$(_hi_resolved _HI_SETTINGS "$dir")" = "$dir/settings.sh" ]
}

# ...and an explicit value outranks both. The four overlay files with a path
# variable of their own carry the same "only when unset" guard $_HI_HOME and
# $_HI_CONFIG_DIR use, so `export _HI_COLORS=/anywhere` in settings.sh or in
# the environment moves that one file and leaves the other three tracking the
# overlay. Without the guard paths.sh re-exported over the top of it, and the
# symptom was a setting that simply did nothing.
_HI_OVERLAY_PATH_VARS=(_HI_COLORS _HI_PACKAGES _HI_VIMRC _HI_NANORC)

# the overlay basename each of the four resolves to, in the same order
_HI_OVERLAY_PATH_FILES=(colors packages vim.rc nano.rc)

# an overlay directory holding a copy of all four, so every case below is
# choosing between two real files rather than between a file and a miss
function _hi_full_overlay_dir() {
  local dir f
  dir="$_HI_WORKDIR/full-overlay"
  mkdir -p "$dir"
  for f in "${_HI_OVERLAY_PATH_FILES[@]}"; do printf '#\n' >"$dir/$f"; done
  printf '%s' "$dir"
}

# $1 exported to $2, with $_HI_CONFIG_DIR pointed at a full overlay: the
# override has to win over the overlay's same-named file, not merely over the
# tree default
function test_env_override_beats_the_overlay_file() {
  local dir i var
  dir="$(_hi_full_overlay_dir)"
  for i in "${!_HI_OVERLAY_PATH_VARS[@]}"; do
    var="${_HI_OVERLAY_PATH_VARS[i]}"
    # shellcheck disable=SC2016 # ${!1} is the child bash's to expand, not ours
    [ "$(_HI_CONFIG_DIR="$dir" env "$var=/anywhere/hi-$i" bash -c \
      'source "$_HI_HOME/say-hi/common/core.sh"; printf "%s" "${!1}"' _ "$var")" = "/anywhere/hi-$i" ] || {
      _hi_cecho " | $var: the overlay's copy won over an explicit export" "$RED"
      return 1
    }
  done
}

# the same through settings.sh, which is where a user actually writes it -
# core.sh sources that file before paths.sh for exactly this reason
function test_settings_override_beats_the_overlay_file() {
  local dir
  dir="$(_hi_full_overlay_dir)"
  printf 'export _HI_VIMRC=/dotfiles/hi-vim.rc\n' >"$dir/settings.sh"
  [ "$(_hi_resolved _HI_VIMRC "$dir")" = /dotfiles/hi-vim.rc ]
}

# ...and it moves that one file only: the other three still resolve to the
# overlay, which is the difference between this and pointing $_HI_CONFIG_DIR
# somewhere else
function test_override_moves_one_file_only() {
  local dir i var
  dir="$(_hi_full_overlay_dir)"
  rm -f "$dir/settings.sh"
  for i in 1 2 3; do
    var="${_HI_OVERLAY_PATH_VARS[i]}"
    # shellcheck disable=SC2016 # ${!1} is the child bash's to expand, not ours
    [ "$(_HI_CONFIG_DIR="$dir" env _HI_COLORS=/anywhere/hi-colors bash -c \
      'source "$_HI_HOME/say-hi/common/core.sh"; printf "%s" "${!1}"' _ "$var")" = "$dir/${_HI_OVERLAY_PATH_FILES[i]}" ] || {
      _hi_cecho " | $var followed _HI_COLORS out of the overlay" "$RED"
      return 1
    }
  done
}

# the guard must not cost the default: with nothing exported, the overlay's
# copy still wins over the tree's, which is the behaviour every install has
function test_unset_still_prefers_the_overlay() {
  local dir i var
  dir="$(_hi_full_overlay_dir)"
  rm -f "$dir/settings.sh"
  for i in "${!_HI_OVERLAY_PATH_VARS[@]}"; do
    var="${_HI_OVERLAY_PATH_VARS[i]}"
    [ "$(_hi_resolved "$var" "$dir")" = "$dir/${_HI_OVERLAY_PATH_FILES[i]}" ] || {
      _hi_cecho " | $var did not resolve to the overlay" "$RED"
      return 1
    }
  done
}

# The guard must not make this file's own answer sticky. A child shell inherits
# every one of the four, so a guard that took an inherited value at face value
# would pin the result to the parent's $_HI_CONFIG_DIR - and `_HI_CONFIG_DIR=elsewhere bash`
# would go on reading the overlay it was told to leave. Modelled the way it
# happens: resolve once against one overlay, carry the whole result into a
# child pointed at another.
function test_a_derived_value_does_not_survive_a_new_config_dir() {
  local first second out
  first="$(_hi_full_overlay_dir)"
  rm -f "$first/settings.sh"
  second="$_HI_WORKDIR/second-overlay"
  mkdir -p "$second"
  printf '#\n' >"$second/colors"
  out="$(_HI_CONFIG_DIR="$first" bash -c '
    source "$_HI_HOME/say-hi/common/core.sh"
    _HI_CONFIG_DIR="$1" bash -c '"'"'
      source "$_HI_HOME/say-hi/common/core.sh"
      printf "%s\n%s" "$_HI_COLORS" "$_HI_PACKAGES"'"'"'' _ "$second")"
  [ "$out" = "$second/colors"$'\n'"$_HI_ROOT/settings/packages" ] || {
    _hi_cecho " | re-resolved to [$out], not the second overlay" "$RED"
    return 1
  }
}

# core.sh owes paths.sh a defined value for each of the four, the way it owes
# the toggles one: paths.sh reads them bare, and under `set -u` an unset name
# is fatal rather than empty
function test_core_defines_every_overlay_path_var() {
  local var out
  for var in "${_HI_OVERLAY_PATH_VARS[@]}"; do
    out="$(bash -c 'source "$_HI_HOME/say-hi/common/core.sh"; printf "%s" "${!1-UNSET}"' _ "$var")"
    [ "$out" != UNSET ] || {
      _hi_cecho " | $var is unset after core.sh" "$RED"
      return 1
    }
  done
}

# every one of the four is guarded, so a fifth path variable added beside them
# cannot quietly skip the override
function test_every_overlay_path_var_is_guarded() {
  local var
  for var in "${_HI_OVERLAY_PATH_VARS[@]}"; do
    grep -qF "[ -z \"\$$var\" ] && export $var=" "$_HI_ROOT/common/paths.sh" || {
      _hi_cecho " | $var has no \"only when unset\" guard in paths.sh" "$RED"
      return 1
    }
  done
}

# Every overlay file hi ships (hi.sh's _HI_OVERLAY_FILES) needs a local
# override guard in paths.sh - except settings.sh (unguarded by design: the
# overlay is its only home) and the four additive ones, which each shell or
# settings/aliases.sh sources by name from $_HI_CONFIG_DIR rather than reaching
# through a path var: aliases.sh and the three per-shell files
# (bash.sh, zsh.zsh, config.fish). A missed
# guard fails asymmetrically: the file works on targets but local sessions
# ignore the override - the same silent drift the toggle-gate pin above
# catches.
function test_overlay_guards_match_the_roster() {
  local f roster
  roster="$(bash -c 'set -- && source "$_HI_LAUNCHER" && printf "%s\n" "${_HI_OVERLAY_FILES[@]}"')"
  [ -n "$roster" ] || return 1
  while IFS= read -r f; do
    case "$f" in
    settings.sh | aliases.sh) continue ;;
    bash.sh | zsh.zsh | config.fish) continue ;;
    esac
    grep -qF "[ -f \"\$_HI_CONFIG_DIR/$f\" ] && export" "$_HI_ROOT/common/paths.sh" || {
      _hi_cecho " | overlay file $f has no local-override guard in paths.sh" "$RED"
      return 1
    }
  done <<<"$roster"
}

# the gate reads what install.sh wrote, and after this change that file is the
# overlay's - so the ordering test above has to hold from there too
function test_overlay_settings_are_visible_to_the_gate() {
  local dir home
  dir="$(_hi_overlay_dir)"
  home="$(_hi_scratch_tree overlaygate common settings)"
  printf 'export _HI_DISABLE_LOCAL=1\n' >"$dir/settings.sh"
  _hi_all_gated "$(_HI_HOME="$home" _HI_CONFIG_DIR="$dir" _hi_gate 0 0)" 1
}

function run_paths_tests() {
  _hi_workdir pathstest

  _hi_h1 "Testing common/paths.sh's local-only gate"

  _hi_suite_begin

  _hi_h2 "Testing: _HI_DISABLE_LOCAL / _HI_REMOTE_SESSION"
  _hi_check "Local-only disables every toggle locally" test_local_only_disables_every_toggle_locally
  _hi_check "Local-only leaves a remote session alone" test_local_only_leaves_a_remote_session_alone
  _hi_check "Toggles stay on without local-only" test_toggles_stay_on_without_local_only
  _hi_check "Toggles stay on remotely without local-only" test_toggles_stay_on_remotely_without_local_only
  _hi_check "The gate covers the whole toggle roster" test_gate_list_matches_the_toggle_roster
  _hi_check "config.fish's toggle mirror matches core.sh" test_fish_toggle_list_matches_core
  _hi_check "Sources cleanly under strict mode" test_paths_sources_cleanly_under_strict_mode

  _hi_h2 "Testing: the toggles are always defined"
  _hi_check "core.sh defines every toggle" test_core_defines_every_toggle
  _hi_check "aliases.sh sources cleanly under set -u" test_aliases_source_cleanly_under_nounset
  _hi_check "aliases.sh does not source itself" test_aliases_do_not_source_themselves
  _hi_check "Settings beat the defaults" test_settings_beat_the_defaults
  _hi_check "The environment beats the defaults" test_environment_beats_the_defaults

  _hi_h2 "Testing: the \$_HI_CONFIG_DIR overlay"
  _hi_check "Settings resolve to the overlay" test_settings_resolve_to_the_overlay
  _hi_check "Overlay colors win" test_overlay_colors_win
  _hi_check "Falls back per file" test_overlay_falls_back_per_file
  _hi_check "No overlay uses the tree" test_no_overlay_uses_the_tree
  _hi_check "Settings point at the overlay before it exists" test_settings_point_at_the_overlay_before_it_exists
  _hi_check "Overlay settings reach the gate" test_overlay_settings_are_visible_to_the_gate
  _hi_check "Every overlay file has its paths.sh guard" test_overlay_guards_match_the_roster

  _hi_h2 "Testing: per-file overlay location overrides"
  _hi_check "core.sh defines every path variable" test_core_defines_every_overlay_path_var
  _hi_check "Every path variable is guarded" test_every_overlay_path_var_is_guarded
  _hi_check "Unset still prefers the overlay" test_unset_still_prefers_the_overlay
  _hi_check "The environment beats the overlay file" test_env_override_beats_the_overlay_file
  _hi_check "settings.sh beats the overlay file" test_settings_override_beats_the_overlay_file
  _hi_check "An override moves one file only" test_override_moves_one_file_only
  _hi_check "A derived value does not outlive its config dir" test_a_derived_value_does_not_survive_a_new_config_dir

  _hi_suite_end "paths.sh"
}

run_paths_tests
