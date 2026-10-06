#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# scripts/install.sh run as a program: its flags and modes, and the locator's
# walk through a symlink.
# A part of install_test.sh, a suite of its own so the Windows shards split them.
# The preamble's source line is install_test.sh's - it sources the harness, and
# holds the helpers the parts share (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

_HI_INSTALL_PART=run
# shellcheck source=./install_test.sh
source "${BASH_SOURCE[0]%/*}/install_test.sh"

# _hi_run_env <home-name> <cmd...> - <cmd> against $_HI_WORKDIR/<home-name>
# as $HOME, with only what a login shell has. stdin closed so no prompt can
# hang; $SHELL because install.sh reports ${SHELL##*/} under `set -u`.
function _hi_run_env() {
  local home="$_HI_WORKDIR/$1"
  shift
  mkdir -p "$home"
  _hi_login_env "$home" "$@" </dev/null
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
# --configure arms, the overlay seed, and the validation gate, which read
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

# a full install copies no default into the overlay: the tree's colors,
# packages, and editor rcs apply until the user puts a file there themselves,
# so settings.sh is the only thing the install leaves behind
function test_install_copies_no_default_into_the_overlay() {
  local ovl="$_HI_WORKDIR/ovl-mode/.config/say-hi" out rc=0 f
  out="$(_hi_run_install_here ovl-mode --link none --yes 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"Installed!"* ]] || return 1
  for f in colors packages vim nvim nano emacs; do
    [ ! -e "$ovl/$f" ] || {
      _hi_cecho " | $f was copied into the overlay" "$RED"
      return 1
    }
  done
  [ ! -d "$ovl/.git" ]
}

# --uninstall against a home that never installed: every half reports clean
# and the run still closes with its banner - the safe-to-re-run contract
function test_uninstall_mode_is_safe_on_a_fresh_home() {
  local out rc=0
  out="$(_hi_run_install un-fresh --uninstall 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"Uninstalled!"* && "$out" == *"no settings.sh to remove"* ]]
}

# --uninstall --purge takes the overlay directory with it; without the flag
# the overlay stays, and --dry-run names it and removes nothing
function test_uninstall_purge_removes_the_overlay() {
  local home="$_HI_WORKDIR/un-purge" out rc=0
  mkdir -p "$home/.config/say-hi"
  printf '[hostname]\nmine = "red"\n' >"$home/.config/say-hi/colors"
  out="$(_hi_run_install un-purge --uninstall 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [ -f "$home/.config/say-hi/colors" ] || return 1
  out="$(_hi_run_install un-purge --uninstall --purge --dry-run 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"would remove $home/.config/say-hi"* ]] &&
    [ -f "$home/.config/say-hi/colors" ] || return 1
  out="$(_hi_run_install un-purge --uninstall --purge 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"removed $home/.config/say-hi"* ]] &&
    [ ! -e "$home/.config/say-hi" ] || return 1
  # a second purge has nothing to do and says so
  out="$(_hi_run_install un-purge --uninstall --purge 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"no $home/.config/say-hi to remove"* ]]
}

# a purge that cannot delete everything says so, rather than "removed"
function test_uninstall_purge_says_when_it_cannot_remove() {
  local dir="$_HI_WORKDIR/purge-locked" out
  mkdir -p "$dir/say-hi/locked"
  printf 'x\n' >"$dir/say-hi/locked/colors"
  chmod 555 "$dir/say-hi/locked"
  out="$(_HI_CONFIG_DIR="$dir/say-hi" purge_overlay)"
  chmod 755 "$dir/say-hi/locked"
  [[ "$out" == *"couldn't remove all of it"* && "$out" != *"removed"* ]] && [ -d "$dir/say-hi" ]
}

# an rc hi cannot write is refused by name, with the lines to add by hand and
# no backup left beside it - never "updated"
function test_config_shell_refuses_a_read_only_rc() {
  local dir="$_HI_WORKDIR/rc-locked" out rc=0
  mkdir -p "$dir"
  printf 'echo mine\n' >"$dir/.bashrc"
  chmod 444 "$dir/.bashrc"
  out="$(config_shell bashrc "$dir/.bashrc" "source hi" 2>&1)" || rc=$?
  chmod 644 "$dir/.bashrc"
  [ "$rc" -eq 1 ] && [[ "$out" == *"can't write $dir/.bashrc"* && "$out" == *"source hi"* ]] &&
    [[ "$out" != *"updated"* ]] && [ ! -e "$dir/.bashrc.hi-orig" ] &&
    [ "$(cat "$dir/.bashrc")" = "echo mine" ]
}

# ...and an uninstall that meets one fails, having still done the rest
function test_run_uninstall_fails_on_a_read_only_rc() {
  local home="$_HI_WORKDIR/run-uninstall-locked" out rc=0
  mkdir -p "$home/.config/say-hi"
  printf 'echo before\nsource hi %s\n' "$_HI_MARKER" >"$home/.bashrc"
  chmod 444 "$home/.bashrc"
  printf '#!/bin/sh\nexport _HI_DISABLE_HEADER=1\n' >"$home/.config/say-hi/settings.sh"
  # shellcheck disable=SC2016 # single quotes on purpose: the child expands these
  out="$(env HOME="$home" XDG_CONFIG_HOME="$home/.config" _HI_CONFIG_DIR="$home/.config/say-hi" \
    _HI_SETTINGS="$home/.config/say-hi/settings.sh" _HI_HOME_BASHRC="$home/.bashrc" \
    _HI_HOME_ZSHRC="$home/.zshrc" _HI_HOME_FISH_CONFIG="$home/.config/fish/config.fish" \
    _HI_UNINSTALL_SCRIPT="$_HI_INSTALL" bash -c '
      set --
      source "$_HI_UNINSTALL_SCRIPT"
      function unlink_hi() { :; }
      run_uninstall 2>&1
    ')" || rc=$?
  chmod 644 "$home/.bashrc"
  [ "$rc" -eq 1 ] && [[ "$out" == *"can't write $home/.bashrc"* ]] &&
    [ ! -e "$home/.config/say-hi/settings.sh" ] && grep -qF "$_HI_MARKER" "$home/.bashrc"
}

# ...and --purge is --uninstall's alone
# ...and so does the whole run: its closing line says the rc is still wired,
# and the status is the one a script can act on
function test_uninstall_mode_fails_on_a_read_only_rc() {
  local home="$_HI_WORKDIR/un-locked" out rc=0
  mkdir -p "$home"
  printf 'echo before\nsource hi %s\n' "$_HI_MARKER" >"$home/.bashrc"
  chmod 444 "$home/.bashrc"
  out="$(_hi_run_install un-locked --uninstall 2>&1)" || rc=$?
  chmod 644 "$home/.bashrc"
  [ "$rc" -eq 1 ] && [[ "$out" == *"Uninstalled, but for the rc files named above"* ]] &&
    [[ "$out" != *"Uninstalled!"* ]] && grep -qF "$_HI_MARKER" "$home/.bashrc"
}

# an install that meets one writes the settings, leaves the rc as it was, and
# fails the same way
function test_install_mode_fails_on_a_read_only_rc() {
  local home="$_HI_WORKDIR/in-locked" out rc=0
  mkdir -p "$home"
  printf 'echo mine\n' >"$home/.bashrc"
  chmod 444 "$home/.bashrc"
  out="$(_hi_run_install_here in-locked --link none --yes --preset balanced 2>&1)" || rc=$?
  chmod 644 "$home/.bashrc"
  [ "$rc" -eq 1 ] && [[ "$out" == *"can't write $home/.bashrc"* ]] &&
    [[ "$out" == *"Installed, but for the rc files named above"* && "$out" != *"Installed!"* ]] &&
    [ "$(cat "$home/.bashrc")" = "echo mine" ] && [ -f "$home/.config/say-hi/settings.sh" ]
}

# --shell takes bash, zsh, fish, or all, comma- or space-separated: a name
# outside those is refused by name, and the flag alone asks for its list
function test_shell_flag_refuses_a_stranger() {
  local out rc=0
  out="$(bash "$_HI_ROOT/scripts/install.sh" --shell bash,tcsh 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--shell wants bash, zsh, fish, or all (got tcsh)"* ]] || return 1
  rc=0
  out="$(bash "$_HI_ROOT/scripts/install.sh" --shell 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--shell needs a list of bash, zsh, and fish, or all"* ]]
}

function test_purge_is_refused_outside_uninstall() {
  local out rc=0
  out="$(_hi_run_install un-purge-mode --install --purge 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"--purge does not apply here"* ]]
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

# an overlay an older hi wrote is converted before any setting is read: the
# old-shape packages and colors files come out as TOML, each original kept
# beside it as <file>.old
function test_configure_converts_an_old_overlay() {
  local home="$_HI_WORKDIR/convert-old" cfg out
  cfg="$home/.config/say-hi"
  mkdir -p "$cfg"
  printf 'bat:3,batcat:3\n' >"$cfg/packages"
  printf 'hostname,box,red\n' >"$cfg/colors"
  out="$(_hi_run_install_here convert-old --configure --preset=balanced 2>&1)" || return 1
  [[ "$out" == *"converted $cfg/packages"* && "$out" == *"converted $cfg/colors"* ]] &&
    grep -qx 'bat = \["batcat"\]' "$cfg/packages" && grep -qx 'bat:3,batcat:3' "$cfg/packages.old" &&
    grep -q '^box  *= "red"$' "$cfg/colors" && grep -qx 'hostname,box,red' "$cfg/colors.old"
}

# ...and under --dry-run it only says it would
function test_configure_dry_run_converts_nothing() {
  local home="$_HI_WORKDIR/convert-dry" cfg out
  cfg="$home/.config/say-hi"
  mkdir -p "$cfg"
  printf 'bat:3,batcat:3\n' >"$cfg/packages"
  out="$(_hi_run_install_here convert-dry --configure --preset=balanced --dry-run 2>&1)" || return 1
  [[ "$out" == *"would convert $cfg/packages"* ]] && [ ! -e "$cfg/packages.old" ] &&
    [ "$(cat "$cfg/packages")" = 'bat:3,batcat:3' ]
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
  if [ "$rc" -eq 1 ] && [[ "$out" == *"re-run with --yes"* ]] &&
    ! grep -qF "$_HI_MARKER" "$home/.bashrc"; then
    return 0
  fi
  # the transcript, since a gate that asked instead of deciding (a stdin this
  # platform calls a terminal) reads identically from the status alone
  _hi_cecho " | rc=$rc, and the non-interactive gate line is missing:" "$RED"
  printf '%s\n' "$out" | sed 's/^/   | /' >&2
  return 1
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
    _hi_login_env "$home" "${_HI_PTY_FORCED[@]}" bash "$_HI_RUN_TREE/scripts/install.sh" "$@" >"$out" 2>&1 &
  _hi_wait_quiet "$!" "${_HI_CASE_TIMEOUT:-60}" "$out" "$name"
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

# a first install asks a terminal one thing, and "n" keeps hi off this
# machine; the menu is hi --configure's
function test_first_install_asks_only_about_this_machine() {
  local home="$_HI_WORKDIR/first-q" out="$_HI_WORKDIR/first-q.pty.out"
  _hi_run_install_pty first-q 'n\n' --link none || return 1
  grep -qF "Style this machine's own shells too" "$out" && grep -qF 'Installed!' "$out" &&
    ! grep -qF 'Nothing is written until you save' "$out" &&
    grep -qF 'export _HI_DISABLE_LOCAL=1' "$home/.config/say-hi/settings.sh"
}

# ...and nothing at all once there is a settings.sh
function test_a_later_install_asks_nothing() {
  local home="$_HI_WORKDIR/later-q" out="$_HI_WORKDIR/later-q.pty.out"
  mkdir -p "$home/.config/say-hi"
  printf '#!/bin/sh\n' >"$home/.config/say-hi/settings.sh"
  _hi_run_install_pty later-q '' --link none || return 1
  ! grep -qF 'Style this machine' "$out" && grep -qF 'Installed!' "$out"
}

# hi --configure quit at its menu writes nothing and says so
function test_features_only_quit_leaves_the_settings() {
  local home="$_HI_WORKDIR/feat-quit"
  _hi_run_install_pty feat-quit 'q\n' --configure || return 1
  grep -qF 'Settings left as they were' "$_HI_WORKDIR/feat-quit.pty.out" &&
    ! grep -qF 'Features updated!' "$_HI_WORKDIR/feat-quit.pty.out" &&
    [ ! -e "$home/.config/say-hi/settings.sh" ] ||
    _hi_because "the run said: $(tail -5 "$_HI_WORKDIR/feat-quit.pty.out")"
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

# _hi_mode_help_is_its_own <mode> <usage-prefix> <body-phrase> - the mode's own
# --help: its usage line first, its own paragraph, and nothing of the install's.
# The exit code and the text are both reported on failure: a bare `return 1`
# here said only "FAILED" on a windows-11-arm runner, which cannot tell a help
# text that came out wrong from a `bash` that never ran (the emulated Git Bash
# there also loses `ln -s` and `mkdir -m`, so a dead child is a real candidate).
function _hi_mode_help_is_its_own() {
  local mode="$1" usage="$2" phrase="$3" out rc=0
  out="$(_HI_ARGV0="hi --$mode" bash "$_HI_ROOT/scripts/install.sh" "--$mode" --help)" || rc=$?
  [ "$rc" -eq 0 ] || {
    _hi_cecho " | hi --$mode --help exited $rc" "$RED"
    return 1
  }
  [[ "$out" == "$usage"* && "$out" == *"$phrase"* && "$out" != *"Wires up"* ]] || {
    _hi_cecho " | hi --$mode --help was:" "$RED"
    printf '%s\n' "$out" | sed 's/^/      /'
    return 1
  }
}

function test_uninstall_help_is_its_own() {
  _hi_mode_help_is_its_own uninstall "Usage: hi --uninstall [--purge] [--dry-run]" "inverse of the install"
}

function test_configure_help_is_its_own() {
  _hi_mode_help_is_its_own configure "Usage: hi --configure [--preset <name>]" "Revisit the settings"
}

# no terminal and no --preset: --configure has nothing to do and says so,
# exit 1; an --install still completes and only mentions it
function test_configure_without_a_terminal_says_so() {
  local out rc=0
  out="$(_hi_run_install_here nomenu --configure 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"no terminal for the menu - --preset <name>"* && "$out" == *"everything balanced minimal lean"* ]] || return 1
  rc=0
  out="$(_hi_run_install_here nomenu-install --dry-run --link none 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"no terminal for the settings menu"* ]]
}

# the last --link on the line wins, the way --mux/--no-mux do
function test_last_link_flag_wins() {
  local out
  out="$(_hi_run_install_here lastlink --dry-run --link system --link none --preset balanced 2>&1)" || return 1
  [[ "$out" == *"--link none given"* && "$out" != *"/usr/bin/hi"* ]]
}

# ...and `user` is a word of its own, not only the default: after a none it
# puts the link back in $HOME
function test_link_user_undoes_an_earlier_none() {
  local home="$_HI_WORKDIR/lastuser" out
  out="$(_hi_run_install_here lastuser --dry-run --link none --link user --preset balanced 2>&1)" || return 1
  [[ "$out" == *"would link $home/.local/bin/hi"* && "$out" != *"--link none given"* ]]
}

# --dry-run through the whole install: every write is named, none is made -
# no rc line, no seed, no settings.sh, no link
function test_dry_run_install_writes_nothing() {
  local home="$_HI_WORKDIR/dry" out rc=0
  out="$(_hi_run_install_here dry --dry-run --preset balanced 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] || return 1
  [[ "$out" == *"dry run: would rewrite hi's lines in $home/.bashrc"* ]] &&
    [[ "$out" == *"would rewrite hi's lines in $home/.config/say-hi/settings.sh"* ]] &&
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

function run_install_run_tests() {
  _hi_install_begin

  _hi_h1 "Testing scripts/install.sh's reusable logic (run for real)"

  # the scratch tree every real run below executes out of
  _HI_RUN_TREE="$(_hi_scratch_tree realrun common config scripts hi.sh load.sh)/say-hi"
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
  _hi_check "--link user undoes an earlier none" test_link_user_undoes_an_earlier_none
  _hi_check "--configure with no terminal says so" test_configure_without_a_terminal_says_so
  _hi_check "A clone not named say-hi is refused by name" test_a_misnamed_clone_is_refused_by_name
  _hi_check "--dry-run installs nothing, and says what it would" test_dry_run_install_writes_nothing
  _hi_check "--uninstall --dry-run removes nothing" test_dry_run_uninstall_removes_nothing
  _hi_check "--link system reaches for /usr/bin/hi" test_system_link_flag_targets_usr_bin
  _hi_check "The banner names the version" test_install_reports_the_version
  _hi_check "A full install copies no default in" test_install_copies_no_default_into_the_overlay
  _hi_check "--uninstall is safe on a fresh home" test_uninstall_mode_is_safe_on_a_fresh_home
  _hi_check "--uninstall --purge removes the overlay, dry-run keeps it" test_uninstall_purge_removes_the_overlay
  _hi_check_capable lockout "...and says when it cannot" test_uninstall_purge_says_when_it_cannot_remove
  _hi_check_capable lockout "config_shell refuses a read-only rc" test_config_shell_refuses_a_read_only_rc
  _hi_check_capable lockout "run_uninstall fails on a read-only rc" test_run_uninstall_fails_on_a_read_only_rc
  _hi_check_capable lockout "...and so does the whole --uninstall run" test_uninstall_mode_fails_on_a_read_only_rc
  _hi_check_capable lockout "An install fails on one too, settings written" test_install_mode_fails_on_a_read_only_rc
  _hi_check "--shell refuses a name that is no shell of hi's" test_shell_flag_refuses_a_stranger
  _hi_check "--purge is refused outside --uninstall" test_purge_is_refused_outside_uninstall
  _hi_check "--configure writes settings and no rc" test_features_only_writes_settings_and_no_rc
  _hi_check_capable pty "...and quit at its menu, leaves them as they were" test_features_only_quit_leaves_the_settings
  _hi_check "--configure converts an old overlay first" test_configure_converts_an_old_overlay
  _hi_check "...and under --dry-run only says it would" test_configure_dry_run_converts_nothing
  _hi_check "--preset=<stranger> is refused before anything is written" test_a_stranger_preset_is_refused_before_anything_is_written
  _hi_check "...and before the banner" test_a_stranger_preset_is_refused_before_the_banner
  _hi_check "-n is --dry-run" test_dry_run_short_form_is_the_same
  _hi_check "run_uninstall strips rc, then settings, then the link" test_run_uninstall_strips_rc_then_settings_then_the_link
  _hi_check "No --yes over broken configs aborts" test_install_aborts_on_broken_configs_without_yes
  _hi_check "--yes continues over broken configs" test_install_with_yes_continues_over_broken_configs
  _hi_check_capable pty "Declined at a terminal, the gate aborts" test_install_gate_declined_at_a_terminal_aborts
  _hi_check_capable pty "Accepted at a terminal, the install goes on" test_install_gate_accepted_at_a_terminal_continues
  _hi_check_capable pty "A first install asks only about this machine" test_first_install_asks_only_about_this_machine
  _hi_check_capable pty "A later install asks nothing" test_a_later_install_asks_nothing
  # install_tree links usr/bin/hi, so a host without symlinks cannot stage
  _hi_check_capable symlink "--prefix=<dir> stages under DESTDIR" test_prefix_equals_spelling_stages_under_destdir
  _hi_check "hi's own rc lines never read as a framework" test_install_ignores_its_own_rc_lines

  _hi_h2 "Testing: the locator walk through a symlink"
  _hi_check_capable symlink "An absolute link target" test_locator_walks_an_absolute_symlink
  _hi_check_capable symlink "A relative one with a slash" test_locator_walks_a_relative_symlink
  _hi_check_capable symlink "A bare name in the link's own directory" test_locator_walks_a_bare_name_symlink

  _hi_suite_end "install.sh logic (run for real)"
}

run_install_run_tests
