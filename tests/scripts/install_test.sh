#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Unit tests for scripts/install.sh's own two halves: install_tree, the whole
# of what a packaging recipe's package() step calls, and --uninstall's
# marker-based rc rewriting (strip_marker/strip_settings/unlink_hi), plus an
# install+uninstall round trip. The settings-wizard half of what this file used
# to cover - config_shell, ensure_settings_shebang, overlay_seed,
# presets, and everything else `hi --configure` touches - moved to
# tests/scripts/configure_test.sh once the file covering both scripts at once
# outgrew being one suite; see that file's header for the split.
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

set -- # install.sh reads "$@" for its own args; make sure it sees none
# shellcheck source=../../scripts/install.sh
source "$_HI_INSTALL"

# install_tree is the whole of what a PKGBUILD's package() (or a deb/rpm recipe)
# calls. It must lay the tree down under $DESTDIR and touch nothing else - no rc
# file, no sudo, no prompt - since none of those belong to the packager.

# the scratch source tree alone, for cases that need setup between it and the
# install_tree run (or several runs)
#
# hi.sh gets a real shebang, not the bare "x" every other placeholder file
# gets: install_tree's chmod +x on the staged copy has nothing to grab onto on
# a real Windows runner otherwise - MSYS's executable bit is content-derived
# (a shebang or a PE header), not purely the chmod call, so a shebang-less
# stand-in can chmod +x clean and still read as non-executable afterward.
function _hi_package_src() {
  local dir="$_HI_WORKDIR/$1" item
  mkdir -p "$dir/src/say-hi/common" "$dir/src/say-hi/settings" "$dir/src/say-hi/scripts"
  printf '#!/bin/sh\nx\n' >"$dir/src/say-hi/hi.sh"
  for item in load.sh LICENSE.md README.md; do printf 'x\n' >"$dir/src/say-hi/$item"; done
}

# Stand a scratch tree up and run install_tree against it.
function _hi_package_fixture() {
  local dir="$_HI_WORKDIR/$1"
  local _HI_ROOT="$dir/src/say-hi" _HI_PREFIX="/usr/share" DESTDIR="$dir/dest"
  _hi_package_src "$1"
  install_tree >/dev/null
}

function test_install_tree_copies_the_tree_under_destdir() {
  _hi_package_fixture copies
  local dest="$_HI_WORKDIR/copies/dest/usr/share/say-hi"
  [ -d "$dest/common" ] && [ -d "$dest/settings" ] &&
    [ -f "$dest/load.sh" ] && [ -x "$dest/hi.sh" ]
}

# scripts/ is the one place this list differs from hi.sh's $_HI_PAYLOAD: a
# payload doesn't need it, but a packaged install does, or `hi --install` (which
# every user of that package has to run once) would not be there to run.
function test_install_tree_ships_scripts() {
  _hi_package_fixture scripts
  [ -d "$_HI_WORKDIR/scripts/dest/usr/share/say-hi/scripts" ]
}

# the man page: gzipped outside the tree when the source has one (a checkout
# or tarball does; docs/ is not in $_HI_PACKAGE_CONTENTS, so an installed
# tree doesn't, and install_tree must simply skip it then)
function test_install_tree_stages_the_man_page() {
  local dir="$_HI_WORKDIR/man"
  local _HI_ROOT="$dir/src/say-hi" _HI_PREFIX="/usr/share" DESTDIR="$dir/dest"
  _hi_package_src man
  mkdir -p "$_HI_ROOT/docs"
  printf '.TH HI 1\n' >"$_HI_ROOT/docs/hi.1"
  install_tree >/dev/null
  [ -f "$dir/dest/usr/share/man/man1/hi.1.gz" ]
}

function test_install_tree_skips_the_man_page_without_a_source() {
  _hi_package_fixture noman
  [ ! -e "$_HI_WORKDIR/noman/dest/usr/share/man" ]
}

# the link has to point where hi.sh will be on the installed system, not into
# the staging root, which won't exist by then
function test_install_tree_links_hi_without_destdir_in_the_target() {
  _hi_package_fixture link
  [ "$(readlink "$_HI_WORKDIR/link/dest/usr/bin/hi")" = "/usr/share/say-hi/hi.sh" ]
}

# a package can't rewrite anyone's rc file, so profile.d is the only place it
# can put the _HI_HOME every shell needs before it sources anything
function test_install_tree_writes_the_profile_snippet() {
  _hi_package_fixture profile
  grep -qF 'export _HI_HOME="/usr/share"' "$_HI_WORKDIR/profile/dest/etc/profile.d/say-hi.sh"
}

function test_install_tree_touches_no_rc_file() {
  _hi_package_fixture norc
  local dest="$_HI_WORKDIR/norc/dest"
  [ ! -e "$dest/root" ] && [ ! -e "$dest$HOME" ] && [ ! -e "$dest/etc/bash.bashrc" ]
}

# cp -R merges, so a re-stage must clear the dest or removed files keep shipping
function test_install_tree_clears_a_stale_destination() {
  local dir="$_HI_WORKDIR/staledest"
  _hi_package_fixture staledest
  printf 'stale\n' >"$dir/dest/usr/share/say-hi/leftover"
  local _HI_ROOT="$dir/src/say-hi" _HI_PREFIX="/usr/share" DESTDIR="$dir/dest"
  install_tree >/dev/null
  [ ! -e "$dir/dest/usr/share/say-hi/leftover" ] && [ -f "$dir/dest/usr/share/say-hi/load.sh" ]
}

# clearing the dest removes a pre-existing symlink itself, never its target
function test_install_tree_replaces_a_symlinked_dest_without_following() {
  local dir="$_HI_WORKDIR/symdest"
  _hi_package_src symdest
  mkdir -p "$dir/dest/usr/share" "$dir/elsewhere"
  printf 'keep\n' >"$dir/elsewhere/precious"
  ln -s "$dir/elsewhere" "$dir/dest/usr/share/say-hi"
  local _HI_ROOT="$dir/src/say-hi" _HI_PREFIX="/usr/share" DESTDIR="$dir/dest"
  install_tree >/dev/null
  [ -f "$dir/elsewhere/precious" ] && [ ! -L "$dir/dest/usr/share/say-hi" ] &&
    [ -f "$dir/dest/usr/share/say-hi/load.sh" ]
}

function _hi_strip_written_settings() {
  ensure_settings_shebang
  strip_settings
}

function test_strip_settings_removes_what_install_wrote() {
  _hi_settings_fixture strip _hi_strip_written_settings
  [ ! -e "$(_hi_fixture_settings strip)" ]
}

# colors and packages are the user's own writing, not something install.sh
# produced - uninstall leaves them for the same reason it leaves the checkout
function _hi_strip_beside_colors() {
  printf 'hostname,foo,brred\n' >"$_HI_CONFIG_DIR/colors"
  ensure_settings_shebang
  strip_settings
}

function test_strip_settings_leaves_the_rest_of_the_overlay() {
  _hi_settings_fixture keep _hi_strip_beside_colors
  [ -f "$_HI_WORKDIR/keep/config/colors" ] && [ ! -e "$(_hi_fixture_settings keep)" ]
}

# The only path through config_hi a test may take: every other one ends in
# `sudo ln`, which has no business firing from a suite. --link none returns before
# that, which is the whole point of it - a Homebrew/distro/Git Bash install has
# nothing to link and no way to link it.

function test_config_hi_no_link_skips_the_symlink() {
  local link="$_HI_WORKDIR/no-link-link"
  (
    _HI_LINK="$link"
    _HI_NO_LINK=1
    config_hi
  ) | grep -q "leaving $link alone"
  [ ! -e "$link" ]
}

# the flag has to be a real flag, not just a variable an internal caller
# sets: --link none / user / system, joined too, and nothing else
function test_link_flag_is_parsed_and_documented() {
  local out rc
  grep -qF -- '--link <where>' <("$_HI_INSTALL" --help) || return 1
  rc=0
  out="$(bash "$_HI_INSTALL" --link 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--link needs one of none, user or system"* ]] || return 1
  rc=0
  out="$(bash "$_HI_INSTALL" --link=sideways 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--link wants one of none, user or system (got sideways)"* ]]
}

function test_unlink_hi_skips_when_link_missing() {
  local link="$_HI_WORKDIR/no-such-link"
  (
    _HI_LINK="$link"
    unlink_hi
  ) | grep -q "no $link to remove"
}

# --link system on an uninstall names /usr/bin/hi once, not never: the
# dedupe against the default link once skipped the only link there was
function test_unlink_hi_with_the_system_link_checks_it_once() {
  local out
  out="$(
    _HI_LINK=/usr/bin/hi
    _HI_DRY_RUN=1
    unlink_hi
  )" || return 1
  [ "$(printf '%s\n' "$out" | grep -c '/usr/bin/hi')" -eq 1 ]
}

function test_unlink_hi_skips_when_link_points_elsewhere() {
  local link="$_HI_WORKDIR/elsewhere-link"
  ln -sfn /bin/true "$link"
  (
    _HI_LINK="$link"
    unlink_hi
  ) | grep -q "leaving it alone"
}

# The real-run half: the flag errors, the mode banners and the locator walk
# can only be seen by executing install.sh as a program, the way a user does.
# Every run gets the scratch tree run_install_tests stands up (never this
# checkout: the rc writers and unlink_hi must have nothing of the
# developer's within reach) and a fabricated $HOME under env -i -
# install_location_test.sh's isolation in miniature, minus the fresh-shell
# read-back that suite exists for.
_HI_RUN_TREE=""

# _hi_run_env <home-name> <cmd...> - <cmd> against $_HI_WORKDIR/<home-name>
# as $HOME, with only what a login shell has. stdin closed so no prompt can
# hang; $SHELL because install.sh reports ${SHELL##*/} under `set -u`.
function _hi_run_env() {
  local home="$_HI_WORKDIR/$1"
  shift
  mkdir -p "$home"
  env -i HOME="$home" PATH="$PATH" TERM="${TERM:-xterm-256color}" \
    SHELL=/bin/bash XDG_CONFIG_HOME="$home/.config" "$@" </dev/null
}

# _hi_run_install <home-name> <flag...> - the scratch tree's install.sh, for
# the modes that reach outside $HOME: --uninstall walks unlink_hi past
# /usr/bin/hi, which on a box with say-hi installed points at the real one.
function _hi_run_install() {
  local home="$1"
  shift
  _hi_run_env "$home" bash "$_HI_RUN_TREE/scripts/install.sh" "$@"
}

# _hi_run_install_here <home-name> <flag...> - this checkout's own install.sh
# against a fabricated $HOME, for every mode confined to $HOME and
# $XDG_CONFIG_HOME. The real file rather than the scratch copy, and a plain
# `env` rather than `env -i`, because the coverage sweep sees neither a copy
# nor an `env -i` child - these are the argument parser, the rc check,
# --configure arms, the overlay seed and the validation gate, which read
# as never run when they only ever ran out of $_HI_RUN_TREE. The locator still
# derives the tree from the script's own path (GLOSSARY: HI.33), so what runs
# is exactly what the copy ran, in place.
function _hi_run_install_here() {
  local home="$_HI_WORKDIR/$1"
  shift
  mkdir -p "$home"
  env HOME="$home" TERM="${TERM:-xterm-256color}" SHELL=/bin/bash \
    XDG_CONFIG_HOME="$home/.config" _HI_CONFIG_DIR="$home/.config/say-hi" \
    bash "$_HI_ROOT/scripts/install.sh" "$@" </dev/null
}

# the three argument errors: each has to stop before anything is sourced,
# written or asked, with the message naming what was missing
# the four modes are one choice: `hi --configure` injects --configure,
# so `hi --configure --uninstall` reached run_uninstall
function test_two_modes_are_refused() {
  local out rc=0
  out="$(bash "$_HI_ROOT/scripts/install.sh" --configure --uninstall 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"pick one of --configure --uninstall"* ]]
}

function test_usage_names_what_was_typed() {
  [[ "$(_HI_ARGV0="hi --install" bash "$_HI_ROOT/scripts/install.sh" --help | head -1)" == "Usage: hi --install "* ]] &&
    [[ "$(bash "$_HI_ROOT/scripts/install.sh" --help | head -1)" == "Usage: install.sh "* ]]
}

function test_prefix_flag_requires_a_path() {
  local out rc=0
  out="$(bash "$_HI_ROOT/scripts/install.sh" --prefix 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--prefix needs a path"* ]]
}

# --prefix is the packager's flag: reached through `hi --install` it would
# rm -rf a live prefix, and a relative one lands in /etc/profile.d as typed
function test_prefix_is_refused_through_hi_install() {
  local out rc=0
  out="$(_HI_ARGV0="hi --install" bash "$_HI_ROOT/scripts/install.sh" --prefix /opt 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--prefix is packaging mode"* ]]
}

function test_prefix_must_be_absolute() {
  local out rc=0
  out="$(bash "$_HI_ROOT/scripts/install.sh" --prefix opt 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--prefix needs an absolute path (got opt)"* ]]
}

function test_preset_flag_requires_a_name() {
  local out rc=0
  out="$(bash "$_HI_ROOT/scripts/install.sh" --preset 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--preset needs a name"* ]]
}

# one red line naming --help, no usage dump: the shape every command's
# refusal has
function test_an_unknown_argument_gets_the_usage() {
  local out rc=0
  out="$(bash "$_HI_ROOT/scripts/install.sh" --bogus 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"unknown option --bogus (install.sh --help lists them)"* ]] &&
    [[ "$out" != *"Usage:"* ]] && [ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ]
}
# --configure is the script-side spelling too, and names itself in its usage
function test_configure_is_features_only() {
  local out
  out="$(bash "$_HI_ROOT/scripts/install.sh" --configure --help)" || return 1
  [[ "$out" == "Usage: install.sh --configure ["* ]]
}

# a full install seeds the overlay - the four shipped defaults, and no repo:
# versioning is the user's own; --configure (features-only) leaves it alone
function test_install_seeds_the_overlay() {
  local ovl="$_HI_WORKDIR/ovl-mode/.config/say-hi" out rc=0
  out="$(_hi_run_install_here ovl-mode --link none --yes 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"seeded the shipped defaults"* && "$out" == *"Installed!"* ]] &&
    [ -f "$ovl/colors" ] && [ -f "$ovl/nano.rc" ] && [ ! -d "$ovl/.git" ] || return 1
  rc=0
  out="$(_hi_run_install_here ovl-feat --configure --preset=minimal 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [ ! -e "$_HI_WORKDIR/ovl-feat/.config/say-hi/colors" ] &&
    [ ! -d "$_HI_WORKDIR/ovl-feat/.config/say-hi/.git" ]
}

# --uninstall against a home that never installed: every half reports clean
# and the run still closes with its banner - the safe-to-re-run contract
function test_uninstall_mode_is_safe_on_a_fresh_home() {
  local out rc=0
  out="$(_hi_run_install un-fresh --uninstall 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"Uninstalled!"* && "$out" == *"no settings.sh to remove"* ]]
}

# --configure (the `hi --configure` shape) writes the overlay's settings
# and nothing else: no rc file appears, and the run says which mode it was.
# --preset=<name> is the one-token spelling of the flag.
function test_features_only_writes_settings_and_no_rc() {
  local home="$_HI_WORKDIR/feat" out rc=0
  out="$(_hi_run_install_here feat --configure --preset=minimal 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"Features updated!"* ]] &&
    grep -qF "export _HI_DISABLE_HEADER=1" "$home/.config/say-hi/settings.sh" &&
    [ ! -e "$home/.bashrc" ]
}

# a preset name is checked before a question is asked or a byte written: the
# typo costs an exit 1 that names the real ones, and no settings.sh appears
# the refusal is the first and only line: no section banner ahead of it
function test_a_stranger_preset_is_refused_before_the_banner() {
  local out rc=0
  out="$(_hi_run_install_here preset-banner --configure --preset=minimalist 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$(_hi_strip_ansi "$out")" == *"no such preset: minimalist"* ]] &&
    [[ "$out" != *"Configuring"* ]] && [ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ]
}

function test_a_stranger_preset_is_refused_before_anything_is_written() {
  local home="$_HI_WORKDIR/preset-typo" out rc=0
  out="$(_hi_run_install_here preset-typo --configure --preset=minimalist 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"no such preset: minimalist"* && "$out" == *"minimal"* ]] &&
    [ ! -e "$home/.config/say-hi/settings.sh" ]
}

# run_uninstall in order: the rc lines go, then the settings file, then the
# link. A child bash with $HOME swapped, so core.sh derives the rc roster
# from the fabricated home (this shell's roster is already bound to the real
# one); plain `env`, not `env -i`, so the coverage sweep sees it. unlink_hi is
# shadowed: the real one walks /usr/bin/hi, and a box with say-hi installed
# has one that is not ours.
function test_run_uninstall_strips_rc_then_settings_then_the_link() {
  local home="$_HI_WORKDIR/run-uninstall" out
  mkdir -p "$home/.config/say-hi"
  printf 'echo before\n%s\nsource hi\necho after\n' "$_HI_MARKER" >"$home/.bashrc"
  printf '#!/bin/sh\nexport _HI_DISABLE_HEADER=1\n' >"$home/.config/say-hi/settings.sh"
  # the rc roster is exported by this shell already bound to the real $HOME,
  # so the three paths are handed over explicitly; install.sh parses its
  # argv when sourced, hence the `set --` and the path riding in the env
  # shellcheck disable=SC2016 # single quotes on purpose: the child expands these
  out="$(env HOME="$home" XDG_CONFIG_HOME="$home/.config" _HI_CONFIG_DIR="$home/.config/say-hi" \
    _HI_SETTINGS="$home/.config/say-hi/settings.sh" _HI_HOME_BASHRC="$home/.bashrc" \
    _HI_HOME_ZSHRC="$home/.zshrc" _HI_HOME_FISH_CONFIG="$home/.config/fish/config.fish" \
    _HI_UNINSTALL_SCRIPT="$_HI_INSTALL" bash -c '
      set --
      source "$_HI_UNINSTALL_SCRIPT"
      function unlink_hi() { echo UNLINK_CALLED; }
      run_uninstall 2>&1
    ')" || return 1
  [[ "$out" == *UNLINK_CALLED* ]] &&
    [ ! -e "$home/.config/say-hi/settings.sh" ] &&
    ! grep -qF "$_HI_MARKER" "$home/.bashrc" &&
    grep -qx 'echo before' "$home/.bashrc" && grep -qx 'echo after' "$home/.bashrc"
}

# the validation gate, both ways: a broken .bashrc stops a non-interactive
# install cold with nothing written, and --yes overrides it into a full
# install that still wires that same .bashrc
function test_install_aborts_on_broken_configs_without_yes() {
  local home="$_HI_WORKDIR/gate-abort" out rc=0
  mkdir -p "$home"
  printf 'if [ 1 = 1 ]; then\n' >"$home/.bashrc"
  out="$(_hi_run_install_here gate-abort --link none 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"re-run with --yes"* ]] &&
    ! grep -qF "$_HI_MARKER" "$home/.bashrc"
}

function test_install_with_yes_continues_over_broken_configs() {
  local home="$_HI_WORKDIR/gate-yes" out rc=0
  mkdir -p "$home"
  printf 'if [ 1 = 1 ]; then\n' >"$home/.bashrc"
  out="$(_hi_run_install_here gate-yes --link none --yes 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"continuing anyway"* && "$out" == *"Installed!"* ]] &&
    grep -qF "$_HI_MARKER" "$home/.bashrc"
}

# _hi_run_install_pty <home-name> <input> <flag...> - _hi_run_install under a
# pty with <input> (printf %b) on its stdin, for the one question install.sh
# asks a terminal and nothing else: rc.sh's config_validate_shells. The
# transcript is $_HI_WORKDIR/<home-name>.pty.out, and the cases assert on it
# rather than on the status - pty.spawn exits with the raw wait status,
# which comes back through the shell truncated to 0.
function _hi_run_install_pty() {
  local name="$1" input="$2" home="$_HI_WORKDIR/$1" out="$_HI_WORKDIR/$1.pty.out"
  shift 2
  mkdir -p "$home"
  : >"$out"
  printf '%b' "$input" |
    env -i HOME="$home" PATH="$PATH" TERM="${TERM:-xterm-256color}" \
      SHELL=/bin/bash XDG_CONFIG_HOME="$home/.config" \
      "${_HI_PTY_FORCED[@]}" bash "$_HI_RUN_TREE/scripts/install.sh" "$@" >"$out" 2>&1 &
  _hi_wait_pid "$!" "${_HI_CASE_TIMEOUT:-30}" _hi_timed_out "$name" "${_HI_CASE_TIMEOUT:-30}"
  [ "$_HI_WAIT_EXIT" != 124 ]
}

# the same gate at a terminal, where it asks instead of deciding: "n" stops
# the install with nothing written...
function test_install_gate_declined_at_a_terminal_aborts() {
  local home="$_HI_WORKDIR/gate-no"
  mkdir -p "$home"
  printf 'if [ 1 = 1 ]; then\n' >"$home/.bashrc"
  _hi_run_install_pty gate-no 'n\n' --link none || return 1
  grep -qF 'Continue installing anyway?' "$_HI_WORKDIR/gate-no.pty.out" &&
    grep -qF 'aborting install' "$_HI_WORKDIR/gate-no.pty.out" &&
    ! grep -qF 'Installed!' "$_HI_WORKDIR/gate-no.pty.out" &&
    ! grep -qF "$_HI_MARKER" "$home/.bashrc"
}

# ...and "y" goes on to a full install that wires that same .bashrc. A preset
# so the settings wizard, which would also ask a terminal, has nothing to ask.
function test_install_gate_accepted_at_a_terminal_continues() {
  local home="$_HI_WORKDIR/gate-y"
  mkdir -p "$home"
  printf 'if [ 1 = 1 ]; then\n' >"$home/.bashrc"
  _hi_run_install_pty gate-y 'y\n' --link none --preset everything || return 1
  grep -qF 'Installed!' "$_HI_WORKDIR/gate-y.pty.out" &&
    grep -qF "$_HI_MARKER" "$home/.bashrc"
}

# A prompt framework in the user's own rc answers _HI_DISABLE_LOCAL_PROMPT on
# the first install: hi's prompt stays off on this machine and on on every
# target, and the run says which framework it found.
function test_install_keeps_a_detected_prompt_framework() {
  local home="$_HI_WORKDIR/p10k" out rc=0
  mkdir -p "$home"
  printf 'source ~/powerlevel10k/powerlevel10k.zsh-theme\n' >"$home/.zshrc"
  out="$(_hi_run_install p10k --link none --yes 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"found powerlevel10k"* ]] &&
    grep -qF "export _HI_DISABLE_LOCAL_PROMPT=1" "$home/.config/say-hi/settings.sh"
}

function test_install_writes_no_prompt_answer_without_a_framework() {
  local home="$_HI_WORKDIR/noframework" out rc=0
  out="$(_hi_run_install noframework --link none --yes 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" != *"in your shell config"* ]] &&
    ! grep -qF "_HI_DISABLE_LOCAL_PROMPT" "$home/.config/say-hi/settings.sh"
}

# a settings.sh already there is a decision already taken, whatever it holds:
# detection never overrides it, the Features menu is where it changes
function test_install_detection_defers_to_an_existing_settings_file() {
  local home="$_HI_WORKDIR/decided" out rc=0
  mkdir -p "$home/.config/say-hi"
  printf 'starship init bash | source\n' >"$home/.bashrc"
  printf '#!/bin/sh\n' >"$home/.config/say-hi/settings.sh"
  out="$(_hi_run_install decided --link none --yes 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" != *"found starship"* ]] &&
    ! grep -qF "_HI_DISABLE_LOCAL_PROMPT" "$home/.config/say-hi/settings.sh"
}

# hi's own rc lines never read as a framework: a fresh configure over an
# already-wired .zshrc (uninstall leaves the rc lines' backup, and a user may
# keep hi's lines) finds nothing
function test_install_ignores_its_own_rc_lines() {
  local home="$_HI_WORKDIR/rerun" out rc=0
  _hi_run_install rerun --link none --yes >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || return 1
  rm -f "$home/.config/say-hi/settings.sh"
  out="$(_hi_run_install rerun --link none --yes 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" != *"in your shell config"* ]]
}

# --prefix=<dir> (the one-token spelling) enters packaging mode: the tree
# lands under $DESTDIR<dir>, and the profile.d snippet names the prefix -
# not the staging root, which is gone at runtime, and not the build tree
function test_prefix_equals_spelling_stages_under_destdir() {
  local stage="$_HI_WORKDIR/stage" out rc=0
  out="$(_hi_run_env pack env DESTDIR="$stage" \
    bash "$_HI_RUN_TREE/scripts/install.sh" --prefix=/opt 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"Packaged!"* ]] &&
    [ -f "$stage/opt/say-hi/hi.sh" ] &&
    grep -qF 'export _HI_HOME="/opt"' "$stage/etc/profile.d/say-hi.sh"
}

# The locator walk (GLOSSARY: HI.33), driven for real through each symlink
# shape readlink can hand back: an absolute target, a relative one with a
# slash, and a bare name (which resolves in the link's own directory, so it
# is invoked from there the way argv0 would arrive). In all three the run's
# own banner has to name the scratch tree as hi_home - resolving the link
# rather than the link's directory is the whole point.
function _hi_run_named_the_tree() {
  [[ "$1" == *"hi_home: ${_HI_RUN_TREE%/say-hi}"* ]]
}

function test_locator_walks_an_absolute_symlink() {
  local out
  mkdir -p "$_HI_WORKDIR/loc-bin"
  ln -sfn "$_HI_RUN_TREE/scripts/install.sh" "$_HI_WORKDIR/loc-bin/hi-install"
  out="$(_hi_run_env loc-abs bash "$_HI_WORKDIR/loc-bin/hi-install" --uninstall --dry-run 2>&1)" || true
  _hi_run_named_the_tree "$out"
}

function test_locator_walks_a_relative_symlink() {
  local parent="${_HI_RUN_TREE%/say-hi}" out
  mkdir -p "$parent/bin"
  ln -sfn ../say-hi/scripts/install.sh "$parent/bin/hi-install"
  out="$(_hi_run_env loc-rel bash "$parent/bin/hi-install" --uninstall --dry-run 2>&1)" || true
  _hi_run_named_the_tree "$out"
}

function test_locator_walks_a_bare_name_symlink() {
  local out
  ln -sfn install.sh "$_HI_RUN_TREE/scripts/reinstall.sh"
  out="$(cd "$_HI_RUN_TREE/scripts" &&
    _hi_run_env loc-bare bash reinstall.sh --uninstall --dry-run 2>&1)" || true
  _hi_run_named_the_tree "$out"
}

# unlink_hi's removal ladder, staged like configure_test.sh's config_hi
# cases: a writable bindir needs nothing, and both sudo failures (refused,
# absent) end in instructions rather than a `set -e` death - with the link
# still in place for the instructions to be about
function test_unlink_hi_removes_its_own_link() {
  local dir="$_HI_WORKDIR/unlink-mine"
  mkdir -p "$dir"
  ln -sfn "$_HI_LAUNCHER" "$dir/hi"
  (
    _HI_LINK="$dir/hi"
    unlink_hi
  ) | grep -q "removed $dir/hi" &&
    [ ! -e "$dir/hi" ]
}

function test_unlink_hi_instructs_when_sudo_is_refused() {
  local dir="$_HI_WORKDIR/unlink-refused" out rc=0
  mkdir -p "$dir/bin"
  ln -sfn "$_HI_LAUNCHER" "$dir/bin/hi"
  chmod 555 "$dir/bin"
  out="$(
    function sudo() { return 1; }
    _HI_LINK="$dir/bin/hi"
    unlink_hi
  )" || rc=$?
  chmod 755 "$dir/bin"
  [ "$rc" -eq 0 ] && [[ "$out" == *"couldn't remove it"* ]] && [ -L "$dir/bin/hi" ]
}

# readlink and dirname ride along as real binaries: swapping PATH to lose
# sudo takes the whole toolbox with it
function test_unlink_hi_instructs_with_no_sudo_at_all() {
  local dir="$_HI_WORKDIR/unlink-none" farm out rc=0
  farm="$(_hi_real_path unlink_tools readlink dirname)"
  mkdir -p "$dir/bin"
  ln -sfn "$_HI_LAUNCHER" "$dir/bin/hi"
  chmod 555 "$dir/bin"
  out="$(
    hash -r
    # shellcheck disable=SC2030,SC2031 # subshell-local is the intent
    PATH="$farm"
    _HI_LINK="$dir/bin/hi"
    unlink_hi
  )" || rc=$?
  chmod 755 "$dir/bin"
  [ "$rc" -eq 0 ] && [[ "$out" == *"no sudo here"* ]] && [ -L "$dir/bin/hi" ]
}

# The first command a fresh clone runs has to answer a checkout that is not
# called say-hi by name - hi.sh has that guard, and install.sh reached it
# first with a raw "No such file" from bash
function test_a_misnamed_clone_is_refused_by_name() {
  local dir="$_HI_WORKDIR/misnamed" out rc=0
  mkdir -p "$dir"
  cp -R "$_HI_RUN_TREE" "$dir/sayhi"
  out="$(_hi_run_env misnamed-home bash "$dir/sayhi/scripts/install.sh" --uninstall --dry-run 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"has to be a directory named say-hi"* ]]
}

# reached as `hi --uninstall`, every message says so - the usage line, the
# argument error, and a --help that describes uninstalling rather than the
# install it undoes
function test_errors_name_what_was_typed() {
  local out rc=0
  out="$(_HI_ARGV0="hi --uninstall" bash "$_HI_ROOT/scripts/install.sh" --uninstall --bogus 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"hi --uninstall: unknown option --bogus (hi --uninstall --help lists them)"* && "$out" != *"Usage:"* ]]
}

# every mode is a word, --install included, so a second one is refused
# rather than silently taking over: `hi --install --uninstall` once uninstalled
function test_install_plus_another_mode_is_refused() {
  local out rc=0
  out="$(_HI_ARGV0="hi --install" bash "$_HI_ROOT/scripts/install.sh" --install --uninstall --dry-run 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"pick one of --install --uninstall"* && "$out" != *"Uninstalling"* ]]
}

# a switch that is not the mode's own is refused by name: `--uninstall --yes`
# must not read as a confirmation that meant something
function test_a_switch_outside_its_mode_is_refused() {
  local out rc=0
  out="$(_HI_ARGV0="hi --uninstall" bash "$_HI_ROOT/scripts/install.sh" --uninstall --yes 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--yes does not apply here"* ]] || return 1
  rc=0
  out="$(_HI_ARGV0="hi --configure" bash "$_HI_ROOT/scripts/install.sh" --configure --link none 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--link does not apply here"* ]]
}

function test_uninstall_help_is_its_own() {
  local out
  out="$(_HI_ARGV0="hi --uninstall" bash "$_HI_ROOT/scripts/install.sh" --uninstall --help)" || return 1
  [[ "$out" == "Usage: hi --uninstall [--dry-run]"* && "$out" == *"inverse of the install"* && "$out" != *"Wires up"* ]]
}

function test_configure_help_is_its_own() {
  local out
  out="$(_HI_ARGV0="hi --configure" bash "$_HI_ROOT/scripts/install.sh" --configure --help)" || return 1
  [[ "$out" == "Usage: hi --configure [--preset <name>]"* && "$out" == *"Revisit the settings"* && "$out" != *"Wires up"* ]]
}

# the last --link on the line wins, the way --mux/--no-mux do
function test_last_link_flag_wins() {
  local out
  out="$(_hi_run_install_here lastlink --dry-run --link system --link none --preset balanced 2>&1)" || return 1
  [[ "$out" == *"--link none given"* && "$out" != *"/usr/bin/hi"* ]]
}

# config_hi's user-local default: the bindir is made when it is missing, and
# a bindir off $PATH is said so, once
function test_config_hi_creates_the_user_bindir() {
  local dir="$_HI_WORKDIR/userbin" out
  mkdir -p "$dir"
  printf '#!/bin/bash\n' >"$dir/hi.sh"
  chmod 755 "$dir/hi.sh"
  out="$(
    _HI_LAUNCHER="$dir/hi.sh"
    _HI_LINK="$dir/.local/bin/hi"
    config_hi
  )" || return 1
  [ "$(readlink "$dir/.local/bin/hi")" = "$dir/hi.sh" ] && [[ "$out" == *"not on your PATH"* ]]
}

function test_config_hi_is_quiet_when_the_bindir_is_on_path() {
  local dir="$_HI_WORKDIR/onpathbin" out
  mkdir -p "$dir/bin"
  printf '#!/bin/bash\n' >"$dir/hi.sh"
  chmod 755 "$dir/hi.sh"
  out="$(
    # shellcheck disable=SC2030,SC2031 # subshell-local is the intent
    PATH="$dir/bin:$PATH"
    _HI_LAUNCHER="$dir/hi.sh"
    _HI_LINK="$dir/bin/hi"
    config_hi
  )" || return 1
  [ "$(readlink "$dir/bin/hi")" = "$dir/hi.sh" ] && [[ "$out" != *"not on your PATH"* ]]
}

# something on PATH already runs this tree - Homebrew's wrapper, a package's
# /usr/bin/hi - so no link is added beside it
function test_config_hi_skips_when_hi_on_path_runs_this_tree() {
  local dir="$_HI_WORKDIR/haswrapper" out
  mkdir -p "$dir/wrap" "$dir/bin"
  printf '#!/bin/bash\n' >"$dir/hi.sh"
  chmod 755 "$dir/hi.sh"
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$dir/hi.sh" >"$dir/wrap/hi"
  chmod 755 "$dir/wrap/hi"
  out="$(
    # shellcheck disable=SC2030,SC2031 # subshell-local is the intent
    PATH="$dir/wrap:$PATH"
    _HI_LAUNCHER="$dir/hi.sh"
    _HI_LINK="$dir/bin/hi"
    config_hi
  )" || return 1
  [[ "$out" == *"already on your PATH at $dir/wrap/hi"* ]] && [ ! -e "$dir/bin/hi" ]
}

# _hi_pkg_shim - a dpkg that says every path belongs to say-hi, first on
# PATH; pacman (this box's, when it is one) answers "not owned" for a scratch
# path and link_owner moves on to it
function _hi_pkg_shim() {
  local bin="$_HI_WORKDIR/pkgbin"
  [ -x "$bin/dpkg" ] || {
    mkdir -p "$bin"
    # shellcheck disable=SC2016 # the shim's own $1/$2
    printf '#!/bin/sh\n[ "$1" = -S ] || exit 1\nprintf "say-hi: %%s\\n" "$2"\n' >"$bin/dpkg"
    chmod +x "$bin/dpkg"
  }
  printf '%s' "$bin"
}

function test_config_hi_refuses_a_package_owned_link() {
  local dir="$_HI_WORKDIR/pkgowned" out
  mkdir -p "$dir/bin"
  printf '#!/bin/bash\n' >"$dir/hi.sh"
  ln -sfn /bin/true "$dir/bin/hi"
  out="$(
    # shellcheck disable=SC2030,SC2031 # subshell-local is the intent
    PATH="$(_hi_pkg_shim):$PATH"
    _HI_LAUNCHER="$dir/hi.sh"
    _HI_LINK="$dir/bin/hi"
    config_hi
  )" || return 1
  [[ "$out" == *"belongs to the say-hi package"* ]] && [ "$(readlink "$dir/bin/hi")" = /bin/true ]
}

function test_config_hi_refuses_a_foreign_link() {
  local dir="$_HI_WORKDIR/foreign" out
  mkdir -p "$dir/bin"
  printf '#!/bin/bash\n' >"$dir/hi.sh"
  ln -sfn /bin/true "$dir/bin/hi"
  out="$(
    _HI_LAUNCHER="$dir/hi.sh"
    _HI_LINK="$dir/bin/hi"
    config_hi
  )" || return 1
  [[ "$out" == *"is not hi's"* ]] && [ "$(readlink "$dir/bin/hi")" = /bin/true ]
}

function test_unlink_hi_names_the_owning_package() {
  local dir="$_HI_WORKDIR/pkgunlink" out
  mkdir -p "$dir/bin"
  ln -sfn /bin/true "$dir/bin/hi"
  out="$(
    # shellcheck disable=SC2030,SC2031 # subshell-local is the intent
    PATH="$(_hi_pkg_shim):$PATH"
    _HI_LINK="$dir/bin/hi"
    unlink_hi
  )" || return 1
  [[ "$out" == *"(owned by the say-hi package), leaving it alone"* ]] && [ -L "$dir/bin/hi" ]
}

# an earlier hi on PATH that runs some other tree: the link is still made,
# and the shadowing is said, since scripts will reach the other one
function test_config_hi_warns_when_another_hi_shadows_the_link() {
  local dir="$_HI_WORKDIR/shadowed" out
  mkdir -p "$dir/other" "$dir/bin"
  printf '#!/bin/bash\n' >"$dir/hi.sh"
  chmod 755 "$dir/hi.sh"
  printf '#!/bin/sh\nexit 0\n' >"$dir/other/hi"
  chmod 755 "$dir/other/hi"
  out="$(
    # shellcheck disable=SC2030,SC2031 # subshell-local is the intent
    PATH="$dir/other:$dir/bin:$PATH"
    _HI_LAUNCHER="$dir/hi.sh"
    _HI_LINK="$dir/bin/hi"
    config_hi
  )" || return 1
  [ "$(readlink "$dir/bin/hi")" = "$dir/hi.sh" ] &&
    [[ "$out" == *"$dir/other/hi comes first on your PATH"* ]]
}

# config_hi's own sudo ladder, the mirror of unlink_hi's below: a bindir
# that refuses the write ends in instructions, not a `set -e` death
function test_config_hi_instructs_when_sudo_is_refused() {
  local dir="$_HI_WORKDIR/link-refused" out rc=0
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
  [ "$rc" -eq 0 ] && [[ "$out" == *"finish it as root with: ln -sfn '$dir/hi.sh' '$dir/bin/hi'"* ]] &&
    [ ! -e "$dir/bin/hi" ]
}

function test_config_hi_instructs_with_no_sudo_at_all() {
  local dir="$_HI_WORKDIR/link-none" farm out rc=0
  farm="$(_hi_real_path link_tools readlink dirname)"
  mkdir -p "$dir/bin"
  printf '#!/bin/bash\n' >"$dir/hi.sh"
  chmod 755 "$dir/hi.sh"
  chmod 555 "$dir/bin"
  out="$(
    hash -r
    # shellcheck disable=SC2030,SC2031 # subshell-local is the intent
    PATH="$farm"
    _HI_LAUNCHER="$dir/hi.sh"
    _HI_LINK="$dir/bin/hi"
    config_hi
  )" || rc=$?
  chmod 755 "$dir/bin"
  [ "$rc" -eq 0 ] && [[ "$out" == *"couldn't link $dir/bin/hi"* ]] && [ ! -e "$dir/bin/hi" ]
}

function test_config_hi_dry_run_makes_no_link() {
  local dir="$_HI_WORKDIR/drylink" out
  mkdir -p "$dir/bin"
  printf '#!/bin/bash\n' >"$dir/hi.sh"
  out="$(
    _HI_DRY_RUN=1
    _HI_LAUNCHER="$dir/hi.sh"
    _HI_LINK="$dir/bin/hi"
    config_hi
  )" || return 1
  [[ "$out" == *"would link $dir/bin/hi"* ]] && [ ! -e "$dir/bin/hi" ]
}

# --dry-run through the whole install: every write is named, none is made -
# no rc line, no seed, no settings.sh, no link
function test_dry_run_install_writes_nothing() {
  local home="$_HI_WORKDIR/dry" out rc=0
  out="$(_hi_run_install_here dry --dry-run --preset balanced 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] || return 1
  [[ "$out" == *"dry run: would rewrite hi's lines in $home/.bashrc"* ]] &&
    [[ "$out" == *"would seed $home/.config/say-hi/colors"* ]] &&
    [[ "$out" == *"would link $home/.local/bin/hi"* ]] &&
    [ ! -e "$home/.bashrc" ] && [ ! -e "$home/.config/say-hi/colors" ] &&
    [ ! -e "$home/.config/say-hi/settings.sh" ] && [ ! -e "$home/.local/bin/hi" ]
}

# -n is --dry-run's short form on every mode
function test_dry_run_short_form_is_the_same() {
  local home="$_HI_WORKDIR/dryn" long short
  _hi_run_install_here dryn --link none --yes --preset balanced >/dev/null 2>&1 || return 1
  long="$(_hi_run_install_here dryn --uninstall --dry-run 2>&1)" || return 1
  short="$(_hi_run_install_here dryn --uninstall -n 2>&1)" || return 1
  [ "$long" = "$short" ] && [[ "$short" == *"would remove $home/.config/say-hi/settings.sh"* ]] &&
    [ -f "$home/.config/say-hi/settings.sh" ]
}

function test_dry_run_uninstall_removes_nothing() {
  local home="$_HI_WORKDIR/dryun" out rc=0
  _hi_run_install_here dryun --link none --yes --preset balanced >/dev/null 2>&1 || return 1
  out="$(_hi_run_install_here dryun --uninstall --dry-run 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"would rewrite hi's lines in $home/.bashrc"* ]] &&
    [[ "$out" == *"would remove $home/.config/say-hi/settings.sh"* ]] &&
    grep -qF "$_HI_MARKER" "$home/.bashrc" && [ -f "$home/.config/say-hi/settings.sh" ]
}

# --link system is the one link that reaches for /usr/bin; under --dry-run
# the hi.sh step names that path and never the user's
function test_system_link_flag_targets_usr_bin() {
  local home="$_HI_WORKDIR/syslink" out
  out="$(_hi_run_install_here syslink --dry-run --link system --preset balanced 2>&1)" || return 1
  [[ "$out" == *"/usr/bin/hi"* && "$out" != *"$home/.local/bin/hi"* ]]
}

function test_install_reports_the_version() {
  local out
  out="$(_HI_RELEASE=v9.9.9 _hi_run_install_here ver --dry-run --preset balanced 2>&1)" || return 1
  [[ "$out" == *"version: v9.9.9"* ]]
}

function run_install_tests() {
  _hi_workdir installtest

  _hi_h1 "Testing scripts/install.sh's reusable logic"

  _hi_suite_begin

  _hi_h2 "Testing: install_tree (packaging mode)"
  _hi_check "Copies the tree under DESTDIR" test_install_tree_copies_the_tree_under_destdir
  _hi_check "Ships scripts/" test_install_tree_ships_scripts
  _hi_check "Stages the man page, gzipped" test_install_tree_stages_the_man_page
  _hi_check "Skips the man page without a source" test_install_tree_skips_the_man_page_without_a_source
  _hi_check_capable symlink "Links hi without DESTDIR in the target" test_install_tree_links_hi_without_destdir_in_the_target
  _hi_check "Writes the profile.d snippet" test_install_tree_writes_the_profile_snippet
  _hi_check "Touches no rc file" test_install_tree_touches_no_rc_file
  _hi_check "Clears a stale destination" test_install_tree_clears_a_stale_destination
  _hi_check_capable symlink "Replaces a symlinked dest without following" test_install_tree_replaces_a_symlinked_dest_without_following

  _hi_h2 "Testing: strip_settings"
  _hi_check "Removes what install wrote" test_strip_settings_removes_what_install_wrote
  _hi_check "Leaves the rest of the overlay" test_strip_settings_leaves_the_rest_of_the_overlay
  _hi_check "Quiet when there is nothing" _hi_settings_fixture nothing strip_settings

  _hi_h2 "Testing: config_hi (--link none only)"
  _hi_check "Skips the symlink entirely" test_config_hi_no_link_skips_the_symlink
  _hi_check "--link is parsed and documented" test_link_flag_is_parsed_and_documented
  _hi_check_capable symlink "Makes the user bindir, and says when it is off PATH" test_config_hi_creates_the_user_bindir
  _hi_check_capable symlink "Quiet when the bindir is on PATH" test_config_hi_is_quiet_when_the_bindir_is_on_path
  _hi_check "Skips when a hi on PATH already runs this tree" test_config_hi_skips_when_hi_on_path_runs_this_tree
  _hi_check_capable symlink "Leaves a package's link to the package manager" test_config_hi_refuses_a_package_owned_link
  _hi_check_capable symlink "Leaves a foreign link alone" test_config_hi_refuses_a_foreign_link
  _hi_check "--dry-run names the link and makes none" test_config_hi_dry_run_makes_no_link
  _hi_check_capable symlink "Says when an earlier hi on PATH shadows the link" test_config_hi_warns_when_another_hi_shadows_the_link
  _hi_check_capable lockout "Instructs when sudo is refused" test_config_hi_instructs_when_sudo_is_refused
  _hi_check_capable lockout "Instructs with no sudo at all" test_config_hi_instructs_with_no_sudo_at_all

  _hi_h2 "Testing: unlink_hi (skip paths only)"
  _hi_check "Skips a missing link" test_unlink_hi_skips_when_link_missing
  _hi_check "--link system is checked once, not skipped" test_unlink_hi_with_the_system_link_checks_it_once
  _hi_check_capable symlink "Skips a foreign link" test_unlink_hi_skips_when_link_points_elsewhere
  _hi_check_capable symlink "Names the package a foreign link belongs to" test_unlink_hi_names_the_owning_package

  _hi_h2 "Testing: unlink_hi (the removal ladder)"
  _hi_check_capable symlink "Removes its own link from a writable bindir" test_unlink_hi_removes_its_own_link
  _hi_check_capable lockout "Instructs when sudo is refused" test_unlink_hi_instructs_when_sudo_is_refused
  _hi_check_capable lockout "Instructs with no sudo at all" test_unlink_hi_instructs_with_no_sudo_at_all

  # the scratch tree every real run below executes out of
  _HI_RUN_TREE="$(_hi_scratch_tree realrun common settings scripts hi.sh load.sh)/say-hi"
  chmod +x "$_HI_RUN_TREE/hi.sh"

  _hi_h2 "Testing: install.sh run for real (flags and modes)"
  _hi_check "--prefix requires a path" test_prefix_flag_requires_a_path
  _hi_check "--prefix is refused through hi --install" test_prefix_is_refused_through_hi_install
  _hi_check "--prefix must be absolute" test_prefix_must_be_absolute
  _hi_check "--preset requires a name" test_preset_flag_requires_a_name
  _hi_check "An unknown argument gets the usage" test_an_unknown_argument_gets_the_usage
  _hi_check "--configure names itself" test_configure_is_features_only
  _hi_check "Two modes at once are refused" test_two_modes_are_refused
  _hi_check "The usage line names what was typed" test_usage_names_what_was_typed
  _hi_check "Every error names what was typed" test_errors_name_what_was_typed
  _hi_check "--install plus another mode is refused" test_install_plus_another_mode_is_refused
  _hi_check "A switch outside its mode is refused" test_a_switch_outside_its_mode_is_refused
  _hi_check "--uninstall --help describes uninstalling" test_uninstall_help_is_its_own
  _hi_check "--configure --help describes the settings" test_configure_help_is_its_own
  _hi_check "The last --link on the line wins" test_last_link_flag_wins
  _hi_check "A clone not named say-hi is refused by name" test_a_misnamed_clone_is_refused_by_name
  _hi_check "--dry-run installs nothing, and says what it would" test_dry_run_install_writes_nothing
  _hi_check "--uninstall --dry-run removes nothing" test_dry_run_uninstall_removes_nothing
  _hi_check "--link system reaches for /usr/bin/hi" test_system_link_flag_targets_usr_bin
  _hi_check "The banner names the version" test_install_reports_the_version
  _hi_check "A full install seeds the overlay" test_install_seeds_the_overlay
  _hi_check "--uninstall is safe on a fresh home" test_uninstall_mode_is_safe_on_a_fresh_home
  _hi_check "--configure writes settings and no rc" test_features_only_writes_settings_and_no_rc
  _hi_check "--preset=<stranger> is refused before anything is written" test_a_stranger_preset_is_refused_before_anything_is_written
  _hi_check "...and before the banner" test_a_stranger_preset_is_refused_before_the_banner
  _hi_check "-n is --dry-run" test_dry_run_short_form_is_the_same
  _hi_check "run_uninstall strips rc, then settings, then the link" test_run_uninstall_strips_rc_then_settings_then_the_link
  _hi_check "No --yes over broken configs aborts" test_install_aborts_on_broken_configs_without_yes
  _hi_check "--yes continues over broken configs" test_install_with_yes_continues_over_broken_configs
  _hi_check_capable pty "Declined at a terminal, the gate aborts" test_install_gate_declined_at_a_terminal_aborts
  _hi_check_capable pty "Accepted at a terminal, the install goes on" test_install_gate_accepted_at_a_terminal_continues
  _hi_check "--prefix=<dir> stages under DESTDIR" test_prefix_equals_spelling_stages_under_destdir
  _hi_check "A detected prompt framework is kept on this machine" test_install_keeps_a_detected_prompt_framework
  _hi_check "No framework, no prompt answer written" test_install_writes_no_prompt_answer_without_a_framework
  _hi_check "Detection defers to an existing settings.sh" test_install_detection_defers_to_an_existing_settings_file
  _hi_check "hi's own rc lines never read as a framework" test_install_ignores_its_own_rc_lines

  _hi_h2 "Testing: the locator walk through a symlink"
  _hi_check_capable symlink "An absolute link target" test_locator_walks_an_absolute_symlink
  _hi_check_capable symlink "A relative one with a slash" test_locator_walks_a_relative_symlink
  _hi_check_capable symlink "A bare name in the link's own directory" test_locator_walks_a_bare_name_symlink

  _hi_suite_end "install.sh logic"
}

run_install_tests
