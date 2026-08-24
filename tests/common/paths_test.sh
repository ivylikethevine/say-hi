#!/bin/bash
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

_HI_GATED_VARS=(_HI_DISABLE_HEADER _HI_DISABLE_PROMPT _HI_DISABLE_PERSONAL
  _HI_DISABLE_GIT_STATUS _HI_DISABLE_EDITORS _HI_DISABLE_ALIASES
  _HI_DISABLE_OSC52 _HI_DISABLE_NOTIFY)

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
    "$_HI_ROOT/shells/config.fish" | grep -oE '_HI_[A-Z0-9_]+')"
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

# misc/aliases.sh and shells/config.fish read the toggles bare, and neither
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

# The overlay's aliases.sh is additive - misc/aliases.sh's last line sources
# $_HI_CONFIG_DIR/aliases.sh so the user's definitions win. Point
# $_HI_CONFIG_DIR at the tree's own misc/ and that line becomes the file
# sourcing itself, forever: exactly what a target does when the overlay is
# unpacked over misc/ instead of into its own config/, and what hung every ssh
# session until the overlay got a directory of its own. Backgrounded and
# waited on because a hang, not a failure, is the symptom - a bare call here
# would take the whole suite down with it.
function test_aliases_do_not_source_themselves() {
  _HI_CONFIG_DIR="$_HI_ROOT/misc" bash -c 'set -eu
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
  [ "$(_hi_resolved _HI_PACKAGES "$dir")" = "$_HI_ROOT/misc/packages" ]
}

function test_no_overlay_uses_the_tree() {
  local dir="$_HI_WORKDIR/no-such-overlay"
  [ "$(_hi_resolved _HI_COLORS "$dir")" = "$_HI_ROOT/misc/colors" ] &&
    [ "$(_hi_resolved _HI_PACKAGES "$dir")" = "$_HI_ROOT/misc/packages" ]
}

# ...but settings.sh still points into the overlay on a machine that has no
# overlay yet, unguarded, because that is where install.sh has to write it
function test_settings_point_at_the_overlay_before_it_exists() {
  local dir="$_HI_WORKDIR/no-such-overlay"
  [ "$(_hi_resolved _HI_SETTINGS "$dir")" = "$dir/settings.sh" ]
}

# Every overlay file hi ships (hi.sh's _HI_OVERLAY_FILES) needs a local
# override guard in paths.sh - except settings.sh (unguarded by design: the
# overlay is its only home) and aliases.sh (consumed additively by
# misc/aliases.sh's last line, not through a path var). A missed guard
# fails asymmetrically: the file works on targets but local sessions ignore
# the override - the same silent drift the toggle-gate pin above catches.
function test_overlay_guards_match_the_roster() {
  local f roster
  roster="$(bash -c 'set -- && source "$_HI_LAUNCHER" && printf "%s\n" "${_HI_OVERLAY_FILES[@]}"')"
  [ -n "$roster" ] || return 1
  while IFS= read -r f; do
    case "$f" in settings.sh | aliases.sh) continue ;; esac
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
  home="$(_hi_scratch_tree overlaygate common misc shells)"
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

  _hi_suite_end "paths.sh"
}

run_paths_tests
