#!/usr/bin/env bash
# Unit tests for scripts/install.sh's own two halves: install_tree, the whole
# of what a packaging recipe's package() step calls, and --uninstall's
# marker-based rc rewriting (strip_marker/strip_settings/unlink_hi), plus an
# install+uninstall round trip. The settings-wizard half of what this file used
# to cover - config_shell, ensure_settings_shebang, overlay_init/commit,
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

function test_strip_marker_removes_tagged_lines_only() {
  local target="$_HI_WORKDIR/tagged"
  printf '%s\n' "# a user comment" "alias ll='ls -la'" >"$target"
  config_shell fixture "$target" "hi line one" "hi line two"
  strip_marker test "$target"
  grep -qF "# a user comment" "$target" &&
    grep -qF "alias ll='ls -la'" "$target" &&
    ! grep -qF "$_HI_MARKER" "$target" &&
    ! grep -qF "hi line one" "$target"
}

function test_strip_marker_noop_when_marker_absent() {
  local target="$_HI_WORKDIR/untagged" before after
  printf '%s\n' "just a normal file" >"$target"
  before="$(cat "$target")"
  strip_marker test "$target"
  after="$(cat "$target")"
  [ "$before" = "$after" ]
}

function test_strip_marker_safe_on_missing_file() {
  strip_marker test "$_HI_WORKDIR/does-not-exist"
}

function test_install_uninstall_round_trip() {
  local target="$_HI_WORKDIR/roundtrip" before after
  printf '%s\n' "# pre-existing line" >"$target"
  before="$(cat "$target")"
  config_shell fixture "$target" "some hi config line"
  grep -qF "some hi config line" "$target" || return 1
  strip_marker fixture "$target"
  after="$(cat "$target")"
  [ "$before" = "$after" ]
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

function test_strip_settings_is_quiet_when_there_is_nothing() {
  _hi_settings_fixture nothing strip_settings
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

# the shim is the only reason `hi --uninstall` and the documented
# scripts/uninstall.sh path still work, so assert it points at the flag
function test_uninstall_shim_delegates_to_install() {
  grep -qF -- '--uninstall' "$_HI_UNINSTALL" && grep -qF 'install.sh' "$_HI_UNINSTALL"
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

  _hi_h2 "Testing: strip_marker (--uninstall)"
  _hi_check "Removes only tagged lines" test_strip_marker_removes_tagged_lines_only
  _hi_check "No-op when marker absent" test_strip_marker_noop_when_marker_absent
  _hi_check "Safe on a missing file" test_strip_marker_safe_on_missing_file
  _hi_check "Install+uninstall round-trips" test_install_uninstall_round_trip

  _hi_h2 "Testing: strip_settings"
  _hi_check "Removes what install wrote" test_strip_settings_removes_what_install_wrote
  _hi_check "Leaves the rest of the overlay" test_strip_settings_leaves_the_rest_of_the_overlay
  _hi_check "Quiet when there is nothing" test_strip_settings_is_quiet_when_there_is_nothing

  _hi_h2 "Testing: config_hi (--no-link only)"
  _hi_check "Skips the symlink entirely" test_config_hi_no_link_skips_the_symlink
  _hi_check "Flag is parsed and documented" test_no_link_flag_is_parsed_and_documented

  _hi_h2 "Testing: unlink_hi (skip paths only)"
  _hi_check "Skips a missing link" test_unlink_hi_skips_when_link_missing
  _hi_check_capable symlink "Skips a foreign link" test_unlink_hi_skips_when_link_points_elsewhere
  _hi_check "uninstall.sh shims onto --uninstall" test_uninstall_shim_delegates_to_install

  _hi_suite_end "install.sh logic"
}

run_install_tests
