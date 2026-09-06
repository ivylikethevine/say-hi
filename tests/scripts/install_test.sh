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
# `sudo ln`, which has no business firing from a suite. --no-link returns before
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

# the flag has to be a real flag, not just a variable an internal caller sets
function test_no_link_flag_is_parsed_and_documented() {
  grep -qF -- '--no-link) _HI_NO_LINK=1' "$_HI_INSTALL" &&
    grep -qF -- '--no-link' <("$_HI_INSTALL" --help)
}

function test_unlink_hi_skips_when_link_missing() {
  local link="$_HI_WORKDIR/no-such-link"
  (
    _HI_LINK="$link"
    unlink_hi
  ) | grep -q "leaving it alone"
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
# nor an `env -i` child - these are the argument parser, the --check-configs,
# --features-only arms, the overlay seed and the validation gate, which read
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
# the four modes are one choice: `hi --configure` injects --features-only,
# so `hi --configure --uninstall` reached run_uninstall
function test_two_modes_are_refused() {
  local out rc=0
  out="$(bash "$_HI_ROOT/scripts/install.sh" --features-only --uninstall 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"pick one of --features-only --uninstall"* ]]
}

function test_usage_names_what_was_typed() {
  [[ "$(_HI_ARGV0="hi --install" bash "$_HI_ROOT/scripts/install.sh" --help | head -1)" == "Usage: hi --install "* ]] &&
    [[ "$(bash "$_HI_ROOT/scripts/install.sh" --help | head -1)" == "Usage: install.sh "* ]]
}

function test_prefix_flag_requires_a_path() {
  local out rc=0
  out="$(bash "$_HI_ROOT/scripts/install.sh" --prefix 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--prefix requires a path"* ]]
}

function test_preset_flag_requires_a_name() {
  local out rc=0
  out="$(bash "$_HI_ROOT/scripts/install.sh" --preset 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--preset requires a name"* ]]
}

function test_an_unknown_argument_gets_the_usage() {
  local out rc=0
  out="$(bash "$_HI_ROOT/scripts/install.sh" --bogus 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"unrecognized argument: --bogus"* && "$out" == *"Usage: install.sh"* ]]
}

# --check-configs is the pre-install validation alone: a clean home is a zero
# exit, and a .bashrc that does not parse turns into a non-zero one - the
# contract anything scripting `hi --check-configs` reads
function test_check_configs_mode_passes_a_clean_home() {
  local out rc=0
  out="$(_hi_run_install_here cc-clean --check-configs 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"Checking existing shell configs!"* ]]
}

function test_check_configs_mode_fails_on_a_broken_bashrc() {
  local home="$_HI_WORKDIR/cc-broken" rc=0
  mkdir -p "$home"
  printf 'if [ 1 = 1 ]; then\n' >"$home/.bashrc" # unterminated if
  _hi_run_install_here cc-broken --check-configs >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 1 ]
}

# a full install seeds the overlay - the four shipped defaults, and no repo:
# versioning is the user's own; --configure (features-only) leaves it alone
function test_install_seeds_the_overlay() {
  local ovl="$_HI_WORKDIR/ovl-mode/.config/say-hi" out rc=0
  out="$(_hi_run_install_here ovl-mode --no-link --yes 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"seeded the shipped defaults"* && "$out" == *"Installed!"* ]] &&
    [ -f "$ovl/colors" ] && [ -f "$ovl/nano.rc" ] && [ ! -d "$ovl/.git" ] || return 1
  rc=0
  out="$(_hi_run_install_here ovl-feat --features-only --preset=minimal 2>&1)" || rc=$?
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

# --features-only (the `hi --configure` shape) writes the overlay's settings
# and nothing else: no rc file appears, and the run says which mode it was.
# --preset=<name> is the one-token spelling of the flag.
function test_features_only_writes_settings_and_no_rc() {
  local home="$_HI_WORKDIR/feat" out rc=0
  out="$(_hi_run_install_here feat --features-only --preset=minimal 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"Features updated!"* ]] &&
    grep -qF "export _HI_DISABLE_HEADER=1" "$home/.config/say-hi/settings.sh" &&
    [ ! -e "$home/.bashrc" ]
}

# a preset name is checked before a question is asked or a byte written: the
# typo costs an exit 1 that names the real ones, and no settings.sh appears
function test_a_stranger_preset_is_refused_before_anything_is_written() {
  local home="$_HI_WORKDIR/preset-typo" out rc=0
  out="$(_hi_run_install_here preset-typo --features-only --preset=minimalist 2>&1)" || rc=$?
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
  out="$(_hi_run_install_here gate-abort --no-link 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"re-run with --yes"* ]] &&
    ! grep -qF "$_HI_MARKER" "$home/.bashrc"
}

function test_install_with_yes_continues_over_broken_configs() {
  local home="$_HI_WORKDIR/gate-yes" out rc=0
  mkdir -p "$home"
  printf 'if [ 1 = 1 ]; then\n' >"$home/.bashrc"
  out="$(_hi_run_install_here gate-yes --no-link --yes 2>&1)" || rc=$?
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
  _hi_run_install_pty gate-no 'n\n' --no-link || return 1
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
  _hi_run_install_pty gate-y 'y\n' --no-link --preset everything || return 1
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
  out="$(_hi_run_install p10k --no-link --yes 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"found powerlevel10k"* ]] &&
    grep -qF "export _HI_DISABLE_LOCAL_PROMPT=1" "$home/.config/say-hi/settings.sh"
}

function test_install_writes_no_prompt_answer_without_a_framework() {
  local home="$_HI_WORKDIR/noframework" out rc=0
  out="$(_hi_run_install noframework --no-link --yes 2>&1)" || rc=$?
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
  out="$(_hi_run_install decided --no-link --yes 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" != *"found starship"* ]] &&
    ! grep -qF "_HI_DISABLE_LOCAL_PROMPT" "$home/.config/say-hi/settings.sh"
}

# hi's own rc lines never read as a framework: a fresh configure over an
# already-wired .zshrc (uninstall leaves the rc lines' backup, and a user may
# keep hi's lines) finds nothing
function test_install_ignores_its_own_rc_lines() {
  local home="$_HI_WORKDIR/rerun" out rc=0
  _hi_run_install rerun --no-link --yes >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || return 1
  rm -f "$home/.config/say-hi/settings.sh"
  out="$(_hi_run_install rerun --no-link --yes 2>&1)" || rc=$?
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
  out="$(_hi_run_env loc-abs bash "$_HI_WORKDIR/loc-bin/hi-install" --check-configs 2>&1)" || true
  _hi_run_named_the_tree "$out"
}

function test_locator_walks_a_relative_symlink() {
  local parent="${_HI_RUN_TREE%/say-hi}" out
  mkdir -p "$parent/bin"
  ln -sfn ../say-hi/scripts/install.sh "$parent/bin/hi-install"
  out="$(_hi_run_env loc-rel bash "$parent/bin/hi-install" --check-configs 2>&1)" || true
  _hi_run_named_the_tree "$out"
}

function test_locator_walks_a_bare_name_symlink() {
  local out
  ln -sfn install.sh "$_HI_RUN_TREE/scripts/reinstall.sh"
  out="$(cd "$_HI_RUN_TREE/scripts" &&
    _hi_run_env loc-bare bash reinstall.sh --check-configs 2>&1)" || true
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
    PATH="$farm"
    _HI_LINK="$dir/bin/hi"
    unlink_hi
  )" || rc=$?
  chmod 755 "$dir/bin"
  [ "$rc" -eq 0 ] && [[ "$out" == *"no sudo here"* ]] && [ -L "$dir/bin/hi" ]
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

  _hi_h2 "Testing: config_hi (--no-link only)"
  _hi_check "Skips the symlink entirely" test_config_hi_no_link_skips_the_symlink
  _hi_check "Flag is parsed and documented" test_no_link_flag_is_parsed_and_documented

  _hi_h2 "Testing: unlink_hi (skip paths only)"
  _hi_check "Skips a missing link" test_unlink_hi_skips_when_link_missing
  _hi_check_capable symlink "Skips a foreign link" test_unlink_hi_skips_when_link_points_elsewhere

  _hi_h2 "Testing: unlink_hi (the removal ladder)"
  _hi_check_capable symlink "Removes its own link from a writable bindir" test_unlink_hi_removes_its_own_link
  _hi_check_capable lockout "Instructs when sudo is refused" test_unlink_hi_instructs_when_sudo_is_refused
  _hi_check_capable lockout "Instructs with no sudo at all" test_unlink_hi_instructs_with_no_sudo_at_all

  # the scratch tree every real run below executes out of
  _HI_RUN_TREE="$(_hi_scratch_tree realrun common settings scripts hi.sh load.sh)/say-hi"
  chmod +x "$_HI_RUN_TREE/hi.sh"

  _hi_h2 "Testing: install.sh run for real (flags and modes)"
  _hi_check "--prefix requires a path" test_prefix_flag_requires_a_path
  _hi_check "--preset requires a name" test_preset_flag_requires_a_name
  _hi_check "An unknown argument gets the usage" test_an_unknown_argument_gets_the_usage
  _hi_check "Two modes at once are refused" test_two_modes_are_refused
  _hi_check "The usage line names what was typed" test_usage_names_what_was_typed
  _hi_check "--check-configs passes a clean home" test_check_configs_mode_passes_a_clean_home
  _hi_check "--check-configs fails on a broken .bashrc" test_check_configs_mode_fails_on_a_broken_bashrc
  _hi_check "A full install seeds the overlay" test_install_seeds_the_overlay
  _hi_check "--uninstall is safe on a fresh home" test_uninstall_mode_is_safe_on_a_fresh_home
  _hi_check "--features-only writes settings and no rc" test_features_only_writes_settings_and_no_rc
  _hi_check "--preset=<stranger> is refused before anything is written" test_a_stranger_preset_is_refused_before_anything_is_written
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
