#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Unit tests for scripts/install.sh's own two halves: install_tree, the whole
# of what a packaging recipe's package() step calls, and --uninstall's
# marker-based rc rewriting (strip_marker/strip_settings/unlink_hi), plus an
# install+uninstall round trip. The settings-wizard half of what this file used
# to cover - config_shell, ensure_settings_shebang,
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
  mkdir -p "$dir/src/say-hi/common" "$dir/src/say-hi/config" "$dir/src/say-hi/scripts"
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
  [ -d "$dest/common" ] && [ -d "$dest/config" ] &&
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

# a live root (no DESTDIR) whose hi.sh a package owns is refused before the
# rm -rf. Past the refusal, no DESTDIR means the real /usr/bin and /etc, so
# every command the staging runs is a tripwire that ends the subshell first.
function test_install_tree_leaves_a_package_owned_live_root_alone() {
  local dir="$_HI_WORKDIR/liveowned" out rc=0
  local _HI_ROOT="$dir/src/say-hi" _HI_PREFIX="$dir/prefix" DESTDIR="" _HI_DRY_RUN=""
  _hi_package_src liveowned
  mkdir -p "$dir/prefix/say-hi"
  printf 'x\n' >"$dir/prefix/say-hi/hi.sh"
  # shellcheck disable=SC2032 # tripwires, never meant to reach sudo
  out="$(
    # shellcheck disable=SC2030,SC2031 # subshell-local is the intent
    PATH="$(_hi_pkg_shim):$PATH"
    function rm() { exit 3; }
    function mkdir() { exit 3; }
    function cp() { exit 3; }
    function ln() { exit 3; }
    function chmod() { exit 3; }
    function gzip() { exit 3; }
    install_tree 2>&1
  )" || rc=$?
  [ "$rc" -eq 1 ] && [ -f "$dir/prefix/say-hi/hi.sh" ] &&
    [[ "$out" == *"$dir/prefix/say-hi belongs to the say-hi package - leave it to the package manager"* ]]
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
  printf '[hostname]\nfoo = "brred"\n' >"$_HI_CONFIG_DIR/colors"
  ensure_settings_shebang
  strip_settings
}

function test_strip_settings_leaves_the_rest_of_the_overlay() {
  _hi_settings_fixture keep _hi_strip_beside_colors
  [ -f "$_HI_WORKDIR/keep/overlay/colors" ] && [ ! -e "$(_hi_fixture_settings keep)" ]
}

# The only path through config_hi a test may take: every other one ends in
# `sudo ln`, which has no business firing from a suite. --link none returns before
# that, which is the whole point of it - a Homebrew/distro/Git Bash install has
# nothing to link and no way to link it.
function test_config_hi_no_link_skips_the_symlink() {
  local link="$_HI_WORKDIR/no-link-link"
  (
    _HI_LINK="$link"
    _HI_LINK_MODE=none
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
  [ "$rc" -eq 1 ] && [[ "$out" == *"--link needs one of none, user, or system"* ]] || return 1
  rc=0
  out="$(bash "$_HI_INSTALL" --link=sideways 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--link wants one of none, user, or system (got sideways)"* ]]
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

# The real-run half: the flag errors, the mode banners, and the locator walk
# can only be seen by executing install.sh as a program, the way a user does.
# Every run gets the scratch tree run_install_tests stands up (never this
# checkout: the rc writers and unlink_hi must have nothing of the
# developer's within reach) and a fabricated $HOME under env -i -
# install_location_test.sh's isolation in miniature, minus the fresh-shell
# read-back that suite exists for.
_HI_RUN_TREE=""

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

# _hi_install_begin - what every part of this suite starts from, and the tally
function _hi_install_begin() {
  _hi_workdir installtest
  _hi_suite_begin
}

function run_install_tests() {
  _hi_install_begin

  _hi_h1 "Testing scripts/install.sh's reusable logic"

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
  _hi_check "Leaves a package-owned live root to the package manager" test_install_tree_leaves_a_package_owned_live_root_alone

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
  _HI_RUN_TREE="$(_hi_scratch_tree realrun common config scripts hi.sh load.sh)/say-hi"
  chmod +x "$_HI_RUN_TREE/hi.sh"

  _hi_suite_end "install.sh logic"
}

# a part (install_*_test.sh) sources this file for what is above and runs its own
[ -n "${_HI_INSTALL_PART:-}" ] || run_install_tests
