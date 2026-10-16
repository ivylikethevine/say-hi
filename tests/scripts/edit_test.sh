#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Unit tests for scripts/edit.sh - `hi --edit [<file>]`, which opens the
# overlay, or one file of it, in the editor, making a file of hi's own
# first where it is not there yet.
#
# Driven through `hi.sh --edit` over a scratch tree, so the common/flags row
# and _hi_dispatch_subcommand are covered with it. The editor is a recorder
# script that writes its arguments to a file and opens nothing, so a case
# reads what would have been opened.
#
# GLOSSARY: HI.34.
# shellcheck disable=SC2329,SC2317
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

_HI_EDIT_TREE=""
_HI_EDIT_BIN=""

# _hi_edit_run <config> <args...> - `hi --edit <args>` over that overlay,
# $VISUAL and $EDITOR cleared unless the case sets them, the recorder's
# directory first on PATH; what it said on stdout, the recorder's log in
# <config>.opened
function _hi_edit_run() {
  local cfg="$1" rc=0
  shift
  mkdir -p "$cfg.home"
  env -u _HI_EDITOR VISUAL="${VISUAL:-}" EDITOR="${EDITOR:-}" _HI_EDIT_LOG="$cfg.opened" \
    HOME="$cfg.home" XDG_CONFIG_HOME="$cfg.home/.config" _HI_CONFIG_DIR="$cfg" \
    _HI_HOME="$_HI_EDIT_TREE" PATH="$_HI_EDIT_BIN:$PATH" NO_COLOR=1 \
    "$_HI_EDIT_TREE/say-hi/hi.sh" --edit "$@" 2>&1 || rc=$?
  return "$rc"
}

# _hi_edit_cfg <name> - a fresh overlay directory's path; nothing is made
function _hi_edit_cfg() {
  local n=1
  while [ -e "$_HI_WORKDIR/$1-cfg.$n" ] || [ -e "$_HI_WORKDIR/$1-cfg.$n.opened" ]; do n=$((n + 1)); done
  printf '%s' "$_HI_WORKDIR/$1-cfg.$n"
}

# _hi_edit_opened <config> - what the recorder was handed, one argument a line
function _hi_edit_opened() { cat "$1.opened" 2>/dev/null; }

# _hi_edit_recorder <name> - an editor of that name in the recorder's
# directory: writes its arguments to $_HI_EDIT_LOG, preceded by its own name
function _hi_edit_recorder() {
  # shellcheck disable=SC2016 # the recorder's own script, expanded when it runs
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s" "$@" >"$_HI_EDIT_LOG"\n' "$1" >"$_HI_EDIT_BIN/$1"
  chmod +x "$_HI_EDIT_BIN/$1"
}

# the overlay directory itself with no file named, made where there is none
function test_edit_opens_the_overlay_directory() {
  local cfg out got
  cfg="$(_hi_edit_cfg dir)"
  out="$(EDITOR=rec _hi_edit_run "$cfg")" || _hi_why cfg out || return 1
  got="$(_hi_edit_opened "$cfg")"
  [ "$got" = "rec
$cfg" ] && [ -d "$cfg" ] || _hi_why got cfg out
}

# a plugins file that is not there yet starts from the tree's key reference,
# the comment config/plugins opens on, and an example table; one that is
# there is opened as it is
function test_edit_makes_a_plugins_file_from_the_key_reference() {
  local cfg out got want
  cfg="$(_hi_edit_cfg plugins)"
  out="$(EDITOR=rec _hi_edit_run "$cfg" plugins)" || _hi_why cfg out || return 1
  [[ "$out" == *"made $cfg/plugins"* ]] || _hi_because "said: $out" || return 1
  got="$(_hi_edit_opened "$cfg")"
  [ "$got" = "rec
$cfg/plugins" ] || _hi_why got || return 1
  want="$(awk '/^#/ { print; next } { exit }' "$_HI_ROOT/config/plugins")"
  [ "$(sed '/^$/,$d' "$cfg/plugins")" = "$want" ] && grep -qx '# \[cli.task\]' "$cfg/plugins" || _hi_why cfg want || return 1
  printf '[mine.x]\nfiles = "x"\n' >"$cfg/plugins"
  out="$(EDITOR=rec _hi_edit_run "$cfg" plugins)" || _hi_why cfg out || return 1
  [[ "$out" != *made* ]] && [ "$(cat "$cfg/plugins")" = '[mine.x]
files = "x"' ] || _hi_why out cfg
}

# colors and packages start as copies of the tree's, as --add-color and
# --add-package make them; settings.sh as --configure starts one
function test_edit_makes_hi_s_other_files_as_their_commands_do() {
  local cfg out n
  cfg="$(_hi_edit_cfg own)"
  n="$(sed -n 's/^_HI_SETTINGS_SHAPE=//p' "$_HI_ROOT/scripts/lib.sh")"
  out="$(EDITOR=rec _hi_edit_run "$cfg" colors)" || _hi_why cfg out || return 1
  cmp -s "$cfg/colors" "$_HI_ROOT/config/colors" || _hi_why cfg out || return 1
  out="$(EDITOR=rec _hi_edit_run "$cfg" packages)" || _hi_why cfg out || return 1
  cmp -s "$cfg/packages" "$_HI_ROOT/config/packages" || _hi_why cfg out || return 1
  out="$(EDITOR=rec _hi_edit_run "$cfg" settings.sh)" || _hi_why cfg out || return 1
  [ "$(sed -n 1p "$cfg/settings.sh")" = '#!/bin/sh' ] && [[ "$(sed -n 2p "$cfg/settings.sh")" == "# say-hi settings $n "*"$_HI_MARKER" ]] &&
    [ "$(wc -l <"$cfg/settings.sh" | tr -d ' ')" = 2 ] || _hi_why cfg out
}

# any other file gets its directory and nothing else: one the editor is
# left without saving must not ride empty in place of home's
function test_edit_makes_a_members_directory_and_not_the_file() {
  local cfg out got
  cfg="$(_hi_edit_cfg member)"
  out="$(EDITOR=rec _hi_edit_run "$cfg" vim/vimrc)" || _hi_why cfg out || return 1
  got="$(_hi_edit_opened "$cfg")"
  [ "$got" = "rec
$cfg/vim/vimrc" ] && [ -d "$cfg/vim" ] && [ ! -e "$cfg/vim/vimrc" ] && [[ "$out" != *made* ]] || _hi_why got cfg out
}

# $VISUAL first, then $EDITOR, then _HI_EDITOR from the settings, then the
# first of hi's editors on PATH; a value's flags ride with it, and one that
# names nothing installed is passed over
function test_edit_picks_the_editor_in_order() {
  local cfg out got
  cfg="$(_hi_edit_cfg editor)"
  out="$(VISUAL="vis --wait" EDITOR=rec _hi_edit_run "$cfg")" || _hi_why cfg out || return 1
  got="$(_hi_edit_opened "$cfg")"
  [ "$got" = "vis
--wait
$cfg" ] || _hi_because "VISUAL with a flag: $got" || return 1
  out="$(VISUAL=no-such-editor-here EDITOR=rec _hi_edit_run "$cfg")" || _hi_why cfg out || return 1
  [ "$(_hi_edit_opened "$cfg")" = "rec
$cfg" ] || _hi_because "an absent VISUAL: $(_hi_edit_opened "$cfg")" || return 1
  mkdir -p "$cfg"
  printf '#!/bin/sh\nexport _HI_EDITOR=nano\n' >"$cfg/settings.sh"
  out="$(_hi_edit_run "$cfg")" || _hi_why cfg out || return 1
  [ "$(_hi_edit_opened "$cfg")" = "nano
$cfg" ] || _hi_because "_HI_EDITOR: $(_hi_edit_opened "$cfg")" || return 1
  rm -f "$cfg/settings.sh"
  out="$(_hi_edit_run "$cfg")" || _hi_why cfg out || return 1
  [ "$(_hi_edit_opened "$cfg")" = "nvim
$cfg" ] || _hi_because "the list's first: $(_hi_edit_opened "$cfg")"
}

# a path that leaves the overlay, more than one file, an unknown option, and
# a name ending in a slash are refused, with nothing made
function test_edit_refuses_what_it_cannot_open() {
  local cfg out word rc
  cfg="$(_hi_edit_cfg refuse)"
  for word in ../x /etc/x './x' 'a/../x' 'x/'; do
    rc=0
    out="$(EDITOR=rec _hi_edit_run "$cfg" "$word")" || rc=$?
    [ "$rc" -ne 0 ] && [[ "$out" == *"not a file of $cfg"* ]] && [ ! -e "$cfg" ] ||
      _hi_because "[$word] gave rc $rc: $out" || return 1
  done
  rc=0
  out="$(EDITOR=rec _hi_edit_run "$cfg" plugins colors)" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"takes one file at most"* ]] || _hi_because "two files: $out" || return 1
  rc=0
  out="$(EDITOR=rec _hi_edit_run "$cfg" --force)" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"unknown option --force"* ]] || _hi_because "--force: $out" || return 1
  out="$(EDITOR=rec _hi_edit_run "$cfg" --help)" || _hi_why out || return 1
  [[ "$out" == "Usage: hi --edit [<file>]"* ]] && [ ! -e "$cfg" ] || _hi_why out cfg
}

function run_edit_tests() {
  _hi_workdir edit
  _hi_suite_begin
  _HI_EDIT_TREE="$(_hi_scratch_tree edit-tree common config load.sh hi.sh link:scripts)"
  _HI_EDIT_BIN="$_HI_WORKDIR/bin"
  mkdir -p "$_HI_EDIT_BIN"
  _hi_edit_recorder rec
  _hi_edit_recorder vis
  _hi_edit_recorder nano
  _hi_edit_recorder nvim

  _hi_h2 "Testing: scripts/edit.sh"
  _hi_check "No file opens the overlay directory" test_edit_opens_the_overlay_directory
  _hi_check "A new plugins file starts from the key reference" test_edit_makes_a_plugins_file_from_the_key_reference
  _hi_check "colors, packages and settings.sh start as their commands make them" test_edit_makes_hi_s_other_files_as_their_commands_do
  _hi_check "Any other file gets its directory, not the file" test_edit_makes_a_members_directory_and_not_the_file
  _hi_check "The editor is picked in order" test_edit_picks_the_editor_in_order
  _hi_check "What it cannot open is refused" test_edit_refuses_what_it_cannot_open

  _hi_suite_end "scripts/edit.sh"
}

run_edit_tests
