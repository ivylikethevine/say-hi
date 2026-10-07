#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Unit tests for scripts/convert_settings.sh, which rewrites overlay files an
# older hi wrote - name:N packages rows, type,name,color colors rows, the
# bare rows under [section] lines that followed both,
# _HI_PACKAGES_MIN_PRIORITY, and the _HI_DISABLE_TOOL_ALIASES and
# _HI_DISABLE_SUDO_ALIAS toggles - into the shapes this hi reads.
#
# The converters are filters (stdin to stdout) and run in-process
# through the script's source hatch; the entry point runs as a process
# against a scratch overlay directory per case.
#
# GLOSSARY: HI.34.
# shellcheck disable=SC2329,SC2317
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

_HI_CONVERT="$_HI_ROOT/scripts/convert_settings.sh"
# its own hatch stops it before the entry point; sourcing hands over the
# converters
# shellcheck source=../../scripts/convert_settings.sh
source "$_HI_CONVERT"
# full_check and _hi_colors_lookup, for the shipped-file cases
# shellcheck source=../../common/header.sh
source "$_HI_HEADER"
# core.sh, which both source, ends with `set +euo pipefail`
set -euo pipefail

# _hi_conv_is <converter> <input> <want> - <converter> turns <input> into
# exactly <want>, both %b; the mismatch printed when it does not
function _hi_conv_is() {
  local got want
  got="$(printf '%b' "$2" | "$1")"
  want="$(printf '%b' "$3")"
  [ "$got" = "$want" ] && return 0
  _hi_cecho " | got:  [$got]" "$RED"
  _hi_cecho " | want: [$want]" "$RED"
  return 1
}

# _hi_conv_dir <name> - a fresh overlay directory holding one old-shape file
# of each kind, printed
function _hi_conv_dir() {
  local dir="$_HI_WORKDIR/$1"
  mkdir -p "$dir"
  printf '# mine\nbat:3,batcat:3\n-sudo:2\n' >"$dir/packages"
  printf '# mine\nhostname,box,red\nusername,me,blue,3ba55d\n' >"$dir/colors"
  printf '#!/bin/sh\nexport _HI_PACKAGES_MIN_PRIORITY=3\nexport _HI_MAX_WIDTH=100\n' >"$dir/settings.sh"
  printf '%s' "$dir"
}

# _hi_conv_run <args...> - the entry point as a process
function _hi_conv_run() {
  bash "$_HI_CONVERT" "$@" 2>&1
}

# --- packages ----------------------------------------------------------------

# a row's group is the tier its highest N named: 3 core, 2 useful, 1 extras,
# 0 trivia, and the groups come out in that order whatever the file's order
function test_packages_map_each_tier_to_its_group() {
  _hi_conv_is _hi_convert_packages 'd:0\nc:1\nb:2\na:3\n' \
    '\n[core]\na\n\n[useful]\nb\n\n[extras]\nc\n\n[trivia]\nd'
}

# alternatives are sorted highest N first, file order within one N, and an N
# above 3 reads as 3
function test_packages_sort_alternatives_highest_first() {
  _hi_conv_is _hi_convert_packages 'x:1,y:3,z:1,w:3\nq:5,r:3\n' \
    '\n[core]\ny,w,x,z\nq,r'
}

# an old `-` row (heard only when missing) is a `+` row now, in the group of
# its tier - below 2, [base]
function test_packages_dash_rows_become_required() {
  _hi_conv_is _hi_convert_packages '-m:3\n-n:2,o:1\n-p:1\n-s:0,t:1\n' \
    '\n[core]\n+m\n\n[useful]\n+n,o\n\n[base]\n+p\n+t,s'
}

# an old `+` row (heard only when installed) has no counterpart, and lands as
# a plain row in [platform] whatever its N
function test_packages_plus_rows_become_platform() {
  _hi_conv_is _hi_convert_packages '+k:0,l:2\n+kitty:3\n' \
    '\n[platform]\nl,k\nkitty'
}

# comments above the first row stay on top; the rest travel with the row
# below them into its group, and those after the last row close the file.
# Blank lines go, and a row's own spaces with them.
function test_packages_comments_travel_with_their_row() {
  _hi_conv_is _hi_convert_packages '# top\n# more\n\nb:2\n# about a\n a : 3 \n\n# trailing\n' \
    '# top\n# more\n\n[core]\n# about a\na\n\n[useful]\nb\n\n# trailing'
}

# --- packages, sections to TOML ------------------------------------------------

# a group's rows gather by kind, plain then required then unwanted, in file
# order within one; a group of marked rows alone has no table of plain ones,
# and a name TOML would not read bare is quoted
function test_toml_packages_gather_a_group_by_kind() {
  _hi_conv_is _hi_toml_packages '[a]\nbat,batcat,cat\n+sudo,doas\njq\n-exa\n+g++\n[b]\n+awk\n[c]\n' \
    '[a]\nbat = ["batcat", "cat"]\njq = []\n\n[a.required]\nsudo = ["doas"]\n"g++" = []\n\n[a.unwanted]\nexa = []\n\n[b.required]\nawk = []\n\n[c]\n'
}

# a group named twice is one table, and rows above the first group keep
# their place on top, the marked ones under a table that names no group
function test_toml_packages_merge_a_group_named_twice() {
  _hi_conv_is _hi_toml_packages 'top\n-gone\n[a]\nx\n[b]\ny\n[a]\nz\n' \
    'top = []\n\n[unwanted]\ngone = []\n\n[a]\nx = []\nz = []\n\n[b]\ny = []\n'
}

# the leading block stays on top, a comment above a group above its first
# table, the rest with the row below; a line holding a #, which nothing read,
# is a comment
function test_toml_packages_comments_travel() {
  _hi_conv_is _hi_toml_packages '# top\n# more\n\n# about a\n[a]\n+x\n# about y\ny\nz # inert\n\n# trailing\n' \
    '# top\n# more\n\n# about a\n[a]\n# about y\ny = []\n\n[a.required]\nx = []\n\n# z # inert\n# trailing\n'
}

# --- colors, sections to TOML --------------------------------------------------

# a row is its name and a string of its color and hex; a name TOML would not
# read bare is quoted, a type named twice is one table, and what followed the
# color and was no hex is a comment behind the row
function test_toml_colors_rows_become_strings() {
  local f="$_HI_WORKDIR/colors.toml"
  printf '# top\n\n[hostname]\nweb-* red\nbox brred #ff5f5f the office\nodd blue note\n[username]\nme green 3ba55d\n[hostname]\nlate cyan\n' |
    _hi_toml_colors >"$f"
  [ "$(sed 's/  */ /g' "$f")" = "$(printf '# top\n\n[hostname]\n"web-*" = "red"\nbox = "brred #ff5f5f" # the office\nodd = "blue" # note\nlate = "cyan"\n\n[username]\nme = "green 3ba55d"')" ] ||
    _hi_because "$(cat "$f")" || return 1
  [ "$(_HI_COLORS="$f" _hi_colors_pattern hostname web-2)" = red ] &&
    [ "$(_HI_COLORS="$f" _hi_colors_lookup hostname box)" = 'brred#ff5f5f' ] &&
    [ "$(_HI_COLORS="$f" _hi_colors_lookup username me)" = 'green#3ba55d' ]
}

# --- colors ------------------------------------------------------------------

# types come out in the order they first appear, rows in file order within
# one - so a pattern keeps its place ahead of an exact row after it - and the
# result reads back through core.sh as the old rows did
function test_colors_group_rows_by_type_in_order() {
  local f="$_HI_WORKDIR/colors.converted"
  printf 'hostname,web-*,red\nusername,me,blue\nhostname,web-1,green,#ff0000\nhosttag,prod,brred,ff5f5f\n' |
    _hi_convert_colors | _hi_toml_colors >"$f"
  [ "$(grep '^\[' "$f" | tr '\n' ' ')" = "[hostname] [username] [hosttag] " ] || return 1
  _hi_before "$(cat "$f")" '^"web-\*"' '^web-1 ' || return 1
  [ "$(_HI_COLORS="$f" _hi_colors_pattern hostname web-2)" = red ] &&
    [ "$(_HI_COLORS="$f" _hi_colors_lookup hostname web-1)" = 'green#ff0000' ] &&
    [ "$(_HI_COLORS="$f" _hi_colors_lookup username me)" = blue ] &&
    [ "$(_HI_COLORS="$f" _hi_colors_lookup hosttag prod)" = 'brred#ff5f5f' ]
}

# the same comment rule as packages: the leading block on top, the rest with
# the row below
function test_colors_comments_travel_with_their_row() {
  local got
  got="$(printf '# top\nhostname,a,red\n# about b\nusername,b,blue\n' | _hi_convert_colors)"
  [ "$(printf '%s\n' "$got" | grep -v '^$' | sed 's/  */ /g')" = "$(printf '# top\n[hostname]\na red\n[username]\n# about b\nb blue')" ]
}

# --- plugins -----------------------------------------------------------------

# a carry file's lines become rows of one [carry] table, a name TOML would
# not read bare in quotes; comments stay, and a line of the wrong shape
# becomes one
# shellcheck disable=SC2016 # the home column holds its $ unexpanded
function test_carry_lines_become_rows() {
  _hi_conv_is _hi_convert_plugins '# member | tool | wire | home\n\n  taskrc | task | env:TASKRC | $TASKRC : ~/.taskrc  \nmy.rc|-|-|~/.myrc\n# about b\nb | x\n' \
    '# member | tool | wire | home\n[carry]\ntaskrc = "task | env:TASKRC | $TASKRC : ~/.taskrc"\n"my.rc" = "- | - | ~/.myrc"\n# about b\n# b | x\n'
}

# rows become a table a tool, named as the rows named their plugin: the
# tool's first word, a (name)'s name, else the member's first name. Rows of
# one tool share a table, one whose wire, home, or dialect differs getting a
# table of its own under it; a name a second group uses takes that group
# behind it; comments travel, and a line that is no row becomes one.
# shellcheck disable=SC2016,SC2088 # the home column holds its $ and ~ unexpanded
function test_plugins_rows_become_tables() {
  _hi_conv_is _hi_toml_plugins '# mine\n[cli]\n  taskrc = "task | env:TASKRC | $TASKRC : ~/.taskrc"\n# about b\n"b.rc" = "- | flag:btool -C | ~/b | sh"\nbad line\n\n[mine]\n"x/a" = "x y | flagdir:x -d | ~/.x/"\n"x/b.lua" = "x y | flagdir:x -d | ~/.x/ | lua"\n"x/c" = "x y | - | ~/.x/"\ninputrc = "(readline) | env:INPUTRC | ~/.inputrc"\ntask2 = "task | - | -"\n# last\n' \
    '# mine\n[cli.task]\nwire = "env:TASKRC"\nhome = "$TASKRC : ~/.taskrc"\nfiles = "taskrc"\n\n# about b\n[cli.b-rc]\ntool = "-"\nwire = "flag:btool -C"\nhome = "~/b"\ndialect = "sh"\nfiles = "b.rc"\n\n# bad line\n[mine.x]\ntool = "x y"\nwire = "flagdir:x -d"\nhome = "~/.x/"\nfiles = "x/a x/b.lua x/c"\n\n[mine.x."x/b.lua"]\ndialect = "lua"\n\n[mine.x."x/c"]\nwire = "-"\n\n[mine.readline]\ntool = "-"\nwire = "env:INPUTRC"\nhome = "~/.inputrc"\nfiles = "inputrc"\n\n[mine.task-mine]\ntool = "task"\nfiles = "task2"\n\n# last\n'
}

# ...and what comes out is what hi reads: every row's member, with the tool,
# the wire, the home, and the dialect its row had
# shellcheck disable=SC2016,SC2088 # the home column holds its $ and ~ unexpanded
function test_converted_plugins_read_as_their_rows_did() {
  local dir="$_HI_WORKDIR/conv-read" out
  mkdir -p "$dir"
  printf '[mine]\n"x/a" = "xtool | flagdir:xtool -d | ~/.x/"\n"x/b.lua" = "xtool | - | ~/.y/ | lua"\ninputrc2 = "(readline) | env:INPUTRC2 | ~/.inputrc2"\n' | _hi_toml_plugins >"$dir/plugins"
  out="$(env -u _hi_core_loaded _HI_CONFIG_DIR="$dir" bash -c 'set -- && source "$_HI_LAUNCHER" && _hi_plugins_load &&
    printf "%s\n" "${#_HI_PLUGIN_BAD[@]}" && for m in x/a x/b.lua inputrc2; do _hi_overlay_row "$m"; echo; done')"
  [ "$out" = '0
x/a|-|-|xtool|mine|xtool|flagdir:xtool -d|-|-|~/.x/
x/b.lua|-|-|xtool|mine|xtool|-|-|lua|~/.y/
inputrc2|-|-|-|mine|readline|env:INPUTRC2|-|-|~/.inputrc2' ] || _hi_because "read back: $out"
}

# the entry point writes the carry as plugins, in tables, and keeps it as
# carry.old, unless a plugins file is there already; a plugins file of rows
# is converted where it is, and one of tables is left alone
function test_entry_converts_the_carry() {
  local dir="$_HI_WORKDIR/conv-carry" out
  mkdir -p "$dir"
  printf 'taskrc | - | env:TASKRC | ~/.taskrc\n' >"$dir/carry"
  out="$(_hi_conv_run --dry-run "$dir")" || return 1
  [[ "$out" == *"would convert $dir/carry to $dir/plugins"* ]] && [ ! -e "$dir/plugins" ] || _hi_because "dry: $out" || return 1
  out="$(_hi_conv_run "$dir")" || return 1
  [[ "$out" == *"converted $dir/carry to $dir/plugins"* ]] && [ ! -e "$dir/carry" ] &&
    [ "$(cat "$dir/carry.old")" = 'taskrc | - | env:TASKRC | ~/.taskrc' ] &&
    [ "$(cat "$dir/plugins")" = "$(printf '[carry.taskrc]\ntool = "-"\nwire = "env:TASKRC"\nhome = "~/.taskrc"\nfiles = "taskrc"')" ] || _hi_because "$out: $(cat "$dir/plugins")" || return 1
  printf 'b | - | - | ~/b\n' >"$dir/carry"
  out="$(_hi_conv_run "$dir")" || return 1
  [ -z "$out" ] && [ -f "$dir/carry" ] || _hi_because "a second carry: $out" || return 1
  printf '[mine]\ntaskrc = "task | env:TASKRC | ~/.taskrc"\n' >"$dir/plugins"
  out="$(_hi_conv_run "$dir")" || return 1
  [[ "$out" == *"converted $dir/plugins to the current format"* ]] &&
    [ "$(cat "$dir/plugins.old")" = "$(printf '[mine]\ntaskrc = "task | env:TASKRC | ~/.taskrc"')" ] &&
    [ "$(cat "$dir/plugins")" = "$(printf '[mine.task]\nwire = "env:TASKRC"\nhome = "~/.taskrc"\nfiles = "taskrc"')" ] || _hi_because "$out: $(cat "$dir/plugins")" || return 1
  out="$(_hi_conv_run "$dir")" || return 1
  [ -z "$out" ] || _hi_because "a second run: $out"
}

# --- settings.sh -------------------------------------------------------------

# the old floor becomes the groups that show the same tiers; 2 was the
# default and goes, and every other line stays as it was
function test_settings_map_the_floor_to_groups() {
  _hi_conv_is _hi_convert_settings '#!/bin/sh\nexport _HI_PACKAGES_MIN_PRIORITY=0\nexport X=1\n' \
    "#!/bin/sh\nexport _HI_PACKAGES_GROUPS='core useful deprecated extras trivia base platform'\nexport X=1" || return 1
  _hi_conv_is _hi_convert_settings "export _HI_PACKAGES_MIN_PRIORITY='1'\n" \
    "export _HI_PACKAGES_GROUPS='core useful deprecated extras base'" || return 1
  _hi_conv_is _hi_convert_settings 'export X=1\nexport _HI_PACKAGES_MIN_PRIORITY=2\n' 'export X=1' || return 1
  _hi_conv_is _hi_convert_settings '_HI_PACKAGES_MIN_PRIORITY="3"\n' \
    "export _HI_PACKAGES_GROUPS='core deprecated'" || return 1
  _hi_conv_is _hi_convert_settings 'export _HI_PACKAGES_MIN_PRIORITY=4\n' \
    "export _HI_PACKAGES_GROUPS='none'"
}

# a trailing comment rides onto the replacement - the marker install writes
# on its own lines included, so the line stays install's to rewrite
function test_settings_keep_the_trailing_comment() {
  local line
  printf -v line '%-45s %s' 'export _HI_PACKAGES_MIN_PRIORITY=3' "$_HI_MARKER"
  [ "$(printf '%s\n' "$line" | _hi_convert_settings)" = "export _HI_PACKAGES_GROUPS='core deprecated' ${line##*=3 }" ] || return 1
  _hi_conv_is _hi_convert_settings 'export _HI_PACKAGES_MIN_PRIORITY=1 # mine\n' \
    "export _HI_PACKAGES_GROUPS='core useful deprecated extras base' # mine"
}

# a _HI_PACKAGES_GROUPS line already says what to show, before or after the
# old one: the old line just goes
function test_settings_drop_the_floor_beside_groups() {
  _hi_conv_is _hi_convert_settings "export _HI_PACKAGES_MIN_PRIORITY=0\nexport _HI_PACKAGES_GROUPS='core'\n" \
    "export _HI_PACKAGES_GROUPS='core'"
}

# the two alias toggles have nothing left to turn off (the aliases are
# opt-ins under new names): their lines go, whatever the quoting, and a
# comment naming one, or a new name, stays
function test_settings_drop_the_old_alias_toggles() {
  _hi_conv_is _hi_convert_settings "#!/bin/sh\nexport _HI_DISABLE_TOOL_ALIASES=1\n  _HI_DISABLE_SUDO_ALIAS='0'\n# _HI_DISABLE_TOOL_ALIASES=1 was mine\nexport _HI_SUDO_ALIAS=1\n" \
    "#!/bin/sh\n# _HI_DISABLE_TOOL_ALIASES=1 was mine\nexport _HI_SUDO_ALIAS=1"
}

# an editor's or a multiplexer's toggle at 1 is its word in the list, vim's
# both of its plugins, and one at 0 just goes; the list's own line takes the
# words where it stands, each once, and with none a line is written last
function test_settings_move_the_tool_toggles_to_the_list() {
  _hi_conv_is _hi_convert_settings "#!/bin/sh\nexport _HI_DISABLE_VIM=1\nexport _HI_DISABLE_NANO='0'\nexport _HI_MAX_WIDTH=100\n  _HI_DISABLE_TMUX=\"1\"\n" \
    "#!/bin/sh\nexport _HI_MAX_WIDTH=100\nexport _HI_PLUGINS_OFF='vim nvim tmux'" || return 1
  _hi_conv_is _hi_convert_settings "export _HI_PLUGINS_OFF='lazygit, vim'\nexport _HI_DISABLE_EDITORS=1\nexport _HI_DISABLE_VIM=1\nexport _HI_MUX=1\n" \
    "export _HI_PLUGINS_OFF='lazygit vim nvim nano emacs hx kak micro'\nexport _HI_MUX=1" || return 1
  _hi_conv_is _hi_convert_settings "export _HI_DISABLE_EMACS=0\n" ""
}

# a group's word in either list is its plugins' words, each once, where the
# line stands; a plugin's word stays
function test_settings_spell_a_group_as_its_plugins() {
  _hi_conv_is _hi_convert_settings "export _HI_PLUGINS_ON=\"hooks\"\nexport _HI_PLUGINS_OFF='lazygit, mux tmux'\nexport _HI_MUX=1\n" \
    "export _HI_PLUGINS_ON='zoxide atuin direnv mise'\nexport _HI_PLUGINS_OFF='lazygit tmux screen zellij'\nexport _HI_MUX=1" || return 1
  _HI_GROUP_MAP="mine:task note;" _hi_conv_is _hi_convert_settings "export _HI_PLUGINS_OFF='mine bat'\n" \
    "export _HI_PLUGINS_OFF='task note bat'"
}

# ...under the marker the toggle's line carried, padded as the wizard pads
# its own, so its block takes the line for one of its own
function test_settings_list_line_keeps_the_marker() {
  local line want
  printf -v line '%-45s %s' 'export _HI_DISABLE_HELIX=1' "$_HI_MARKER"
  printf -v want '%-45s %s' "export _HI_PLUGINS_OFF='hx'" "$_HI_MARKER"
  [ "$(printf '%s\n' "$line" | _hi_convert_settings)" = "$want" ]
}

# --- the entry point ---------------------------------------------------------

# each file in the old shape is converted in place, the original kept as
# <file>.old
function test_entry_converts_each_old_file() {
  local dir out f
  dir="$(_hi_conv_dir conv-all)"
  cp "$dir/packages" "$dir/packages.orig"
  cp "$dir/colors" "$dir/colors.orig"
  cp "$dir/settings.sh" "$dir/settings.sh.orig"
  out="$(_hi_conv_run "$dir")" || return 1
  for f in packages colors settings.sh; do
    if [[ "$out" != *"converted $dir/$f to the current format"* ]] || ! cmp -s "$dir/$f.old" "$dir/$f.orig"; then
      _hi_cecho " | $f: $out" "$RED"
      return 1
    fi
  done
  grep -qx '\[core\]' "$dir/packages" && grep -qx 'bat = \["batcat"\]' "$dir/packages" &&
    grep -qx '\[useful.required\]' "$dir/packages" && grep -qx 'sudo = \[\]' "$dir/packages" &&
    grep -qx '\[hostname\]' "$dir/colors" && grep -q '^me  *= "blue 3ba55d"$' "$dir/colors" &&
    grep -qx "export _HI_PACKAGES_GROUPS='core deprecated'" "$dir/settings.sh" &&
    ! grep -q MIN_PRIORITY "$dir/settings.sh" && grep -qx 'export _HI_MAX_WIDTH=100' "$dir/settings.sh"
}

# a settings.sh holding only an old alias toggle is old-format too
function test_entry_converts_the_old_alias_toggles() {
  local dir="$_HI_WORKDIR/conv-toggles" out
  mkdir -p "$dir"
  printf 'export _HI_DISABLE_SUDO_ALIAS=1\nexport _HI_MAX_WIDTH=100\n' >"$dir/settings.sh"
  out="$(_hi_conv_run "$dir")" || return 1
  [[ "$out" == *"converted $dir/settings.sh to the current format"* ]] &&
    grep -q _HI_DISABLE_SUDO_ALIAS "$dir/settings.sh.old" &&
    [ "$(cat "$dir/settings.sh")" = 'export _HI_MAX_WIDTH=100' ] || {
    _hi_cecho " | said: $out" "$RED"
    return 1
  }
}

# ...and so does a toggle the list replaced
function test_entry_converts_a_tool_toggle() {
  local dir="$_HI_WORKDIR/conv-tool-toggle" out
  mkdir -p "$dir"
  printf 'export _HI_DISABLE_KAKOUNE=1\n' >"$dir/settings.sh"
  out="$(_hi_conv_run "$dir")" || return 1
  [[ "$out" == *"converted $dir/settings.sh to the current format"* ]] &&
    [ "$(cat "$dir/settings.sh")" = "export _HI_PLUGINS_OFF='kak'" ] || {
    _hi_cecho " | said: $out" "$RED"
    return 1
  }
}

# ...and a group's word in a list, a group of the overlay's plugins file
# among them, though not one a plugin shares its name with; a second run
# finds nothing to do
function test_entry_converts_a_group_word() {
  local dir="$_HI_WORKDIR/conv-group-word" out
  mkdir -p "$dir"
  printf '[mine.task]\nfiles = "taskrc"\n[own.own]\nfiles = "ownrc"\n' >"$dir/plugins"
  printf "export _HI_PLUGINS_OFF='mine own mux'\n" >"$dir/settings.sh"
  out="$(_hi_conv_run "$dir")" || return 1
  [[ "$out" == *"converted $dir/settings.sh to the current format"* ]] &&
    [ "$(cat "$dir/settings.sh")" = "export _HI_PLUGINS_OFF='task own tmux screen zellij'" ] || {
    _hi_cecho " | said: $out, wrote: $(cat "$dir/settings.sh")" "$RED"
    return 1
  }
  out="$(_hi_conv_run "$dir")" || return 1
  [[ "$out" != *converted* ]] || _hi_because "a second run said: $out"
}

# --dry-run names each conversion and writes nothing
function test_entry_dry_run_writes_nothing() {
  local dir out f
  dir="$(_hi_conv_dir conv-dry)"
  cp "$dir/packages" "$dir/packages.orig"
  out="$(_hi_conv_run --dry-run "$dir")" || return 1
  for f in packages colors settings.sh; do
    [[ "$out" == *"would convert $dir/$f"* ]] && [ ! -e "$dir/$f.old" ] || return 1
  done
  cmp -s "$dir/packages" "$dir/packages.orig"
}

# a second run finds nothing in the old shape: it says nothing, changes
# nothing, and the .old files stay the originals
function test_entry_is_idempotent() {
  local dir out f
  dir="$(_hi_conv_dir conv-twice)"
  cp "$dir/colors" "$dir/colors.orig"
  _hi_conv_run "$dir" >/dev/null || return 1
  for f in packages colors settings.sh; do cp "$dir/$f" "$dir/$f.first"; done
  out="$(_hi_conv_run "$dir")" || return 1
  [ -z "$out" ] || return 1
  for f in packages colors settings.sh; do
    cmp -s "$dir/$f" "$dir/$f.first" || return 1
  done
  cmp -s "$dir/colors.old" "$dir/colors.orig"
}

# the rows under [section] lines, the shape between the first and this one,
# are converted the same way
function test_entry_converts_the_sections() {
  local dir="$_HI_WORKDIR/conv-sections" out
  mkdir -p "$dir"
  printf '# mine\n[core]\nbat,batcat\n+sudo\n' >"$dir/packages"
  printf '[hostname]\n10.0.* red\n' >"$dir/colors"
  out="$(_hi_conv_run "$dir")" || return 1
  [[ "$out" == *"converted $dir/packages to the current format"* && "$out" == *"converted $dir/colors to"* ]] &&
    grep -qx 'bat,batcat' "$dir/packages.old" && grep -qx '10.0.\* red' "$dir/colors.old" || return 1
  [ "$(cat "$dir/packages")" = "$(printf '# mine\n[core]\nbat = ["batcat"]\n\n[core.required]\nsudo = []')" ] ||
    _hi_because "$(cat "$dir/packages")" || return 1
  grep -q '^"10.0.\*"  *= "red"$' "$dir/colors"
}

# files already in the current shape, or absent, are left alone, whatever
# old row a comment of theirs still holds
function test_entry_leaves_current_files_alone() {
  local dir="$_HI_WORKDIR/conv-current" out
  mkdir -p "$dir"
  printf '# bat:3\n[core]\nbat = ["batcat"] # was bat,batcat\n\n[core.required]\n  "g++" = []\n' >"$dir/packages"
  printf '# hostname,box,red\n[hostname]\nbox = "red"\n' >"$dir/colors"
  out="$(_hi_conv_run "$dir")" || return 1
  [ -z "$out" ] && [ ! -e "$dir/packages.old" ] && [ ! -e "$dir/colors.old" ] &&
    [ ! -e "$dir/settings.sh" ]
}

# a file of TOML rows holding a line hi reads nothing of (a dotted key, a
# stray word) is still the current shape: converting it would take every row
# for a name
function test_entry_leaves_a_toml_file_with_an_unread_line_alone() {
  local dir="$_HI_WORKDIR/conv-unread" out
  mkdir -p "$dir"
  printf '[core]\nbat = ["batcat"]\nlesspipe.sh = []\nstray\n' >"$dir/packages"
  printf '[hostname]\nbox = "red"\nweb.* = "blue"\n' >"$dir/colors"
  cp "$dir/packages" "$dir/packages.orig"
  cp "$dir/colors" "$dir/colors.orig"
  out="$(_hi_conv_run "$dir")" || return 1
  [ -z "$out" ] || _hi_because "said: $out" || return 1
  [ ! -e "$dir/packages.old" ] && [ ! -e "$dir/colors.old" ] &&
    cmp -s "$dir/packages" "$dir/packages.orig" && cmp -s "$dir/colors" "$dir/colors.orig"
}

# with no directory, $_HI_CONFIG_DIR is the one converted
function test_entry_defaults_to_the_overlay() {
  local dir out
  dir="$(_hi_conv_dir conv-default)"
  out="$(_HI_CONFIG_DIR="$dir" _hi_conv_run)" || return 1
  [[ "$out" == *"converted $dir/packages"* ]] && [ -f "$dir/packages.old" ]
}

function test_entry_help_and_unknown_option() {
  local out rc=0
  out="$(_hi_conv_run --help)" || return 1
  [[ "$out" == "Usage: convert_settings.sh [--dry-run] [<dir>]"* ]] || return 1
  out="$(_hi_conv_run --bogus)" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"unknown option --bogus"* ]]
}

# --- the shipped files of an older hi ----------------------------------------

# config/packages and config/colors as the last release in each old shape
# shipped them, kept verbatim beside this suite so the cases never depend on
# how much history a checkout carries: the first shape's under their own
# names, the sections' as <name>.sections
_HI_CONV_OLD="$_HI_ROOT/tests/scripts/convert_settings"

# the old shipped config/packages converts into a file full_check reads
# without an error and with no name:N row left, every group on
function test_shipped_old_packages_convert_and_parse() {
  local old="$_HI_WORKDIR/shipped.packages.old" new="$_HI_WORKDIR/shipped.packages"
  local err="$_HI_WORKDIR/shipped.packages.err" out shape=""
  cp "$_HI_CONV_OLD/packages" "$old"
  grep -q '^[^#]*:[0-9]' "$old" || return 1
  _hi_convert_packages <"$old" | _hi_toml_packages >"$new"
  ! grep -q '^[^#]*:[0-9]' "$new" || return 1
  _hi_data_shape shape "$new" "$_HI_FLAT_PACKAGES"
  [ "$shape" = toml ] || return 1
  out="$(_HI_PACKAGES="$new" _HI_PACKAGES_GROUPS="core useful extras trivia base platform" full_check 2>"$err")"
  [ ! -s "$err" ] && [ -n "$out" ]
}

# the sections' shipped config/packages converts into the rows it held: as
# many, every first name a key, and each marked row under its kind's table
function test_shipped_sections_packages_convert_whole() {
  local old="$_HI_CONV_OLD/packages.sections" new="$_HI_WORKDIR/shipped.packages.toml"
  local line group="" mark="" name="" alts="" got want shape=""
  _hi_data_shape shape "$old" "$_HI_FLAT_PACKAGES"
  [ "$shape" = sections ] || return 1
  _hi_toml_packages <"$old" >"$new"
  _hi_data_shape shape "$new" "$_HI_FLAT_PACKAGES"
  [ "$shape" = toml ] || return 1
  # both as "<group> <marker><name>,<alternatives>" lines, sorted
  want="$(awk '/#/ || /^$/ { next } /^\[/ { g = substr($0, 2, length($0) - 2); next } { print g, $0 }' "$old" | sort)"
  got="$(
    while IFS= read -r line; do
      _hi_package_table "$line" group mark && continue
      _hi_toml_row "$line" name alts || continue
      printf '%s %s\n' "$group" "$mark$name${alts:+,$alts}"
    done <"$new" | sort
  )"
  [ -n "$want" ] && [ "$got" = "$want" ] || _hi_because "$(diff <(printf '%s\n' "$want") <(printf '%s\n' "$got"))"
}

# ...and its config/colors into one every pin reads back from
function test_shipped_sections_colors_convert_whole() {
  local old="$_HI_CONV_OLD/colors.sections" new="$_HI_WORKDIR/shipped.colors.toml"
  local type="" name color hex got n=0
  _hi_toml_colors <"$old" >"$new"
  while read -r name color hex; do
    case "$name" in
    '' | '#'*) continue ;;
    '['*']')
      type="${name:1:${#name}-2}"
      continue
      ;;
    esac
    got="$(_HI_COLORS="$new" _hi_colors_lookup "$type" "$name")" || got=""
    [ "$got" = "$color" ] || _hi_because "$type $name: got [$got], want [$color]" || return 1
    n=$((n + 1))
  done <"$old"
  [ "$n" -gt 0 ]
}

# ...and the old shipped config/colors into one core.sh resolves the same
# pins from: every old row's name reads back its old color
function test_shipped_old_colors_convert_and_resolve() {
  local old="$_HI_WORKDIR/shipped.colors.old" new="$_HI_WORKDIR/shipped.colors" type name color hex want got n=0
  cp "$_HI_CONV_OLD/colors" "$old"
  grep -Eq '^[a-z]+,[^,#]+,' "$old" || return 1
  _hi_convert_colors <"$old" | _hi_toml_colors >"$new"
  while IFS=, read -r type name color hex; do
    case "$type" in '' | '#'*) continue ;; esac
    case "$name" in *[\*\?]*) continue ;; esac
    want="$color"
    hex="${hex#\#}"
    [ -z "$hex" ] || want="$color#$hex"
    got="$(_HI_COLORS="$new" _hi_colors_lookup "$type" "$name")" || got=""
    [ "$got" = "$want" ] || {
      _hi_cecho " | $type $name: got [$got], want [$want]" "$RED"
      return 1
    }
    n=$((n + 1))
  done <"$old"
  [ "$n" -gt 0 ]
}

function run_convert_settings_tests() {
  _hi_workdir convertsettings
  _hi_suite_begin

  _hi_h2 "Testing: _hi_convert_packages"
  _hi_check "Each tier maps to its group, in group order" test_packages_map_each_tier_to_its_group
  _hi_check "Alternatives sort highest N first, stably" test_packages_sort_alternatives_highest_first
  _hi_check "A - row becomes a + row, low tiers in [base]" test_packages_dash_rows_become_required
  _hi_check "A + row becomes a plain [platform] row" test_packages_plus_rows_become_platform
  _hi_check "Comments travel with the row below" test_packages_comments_travel_with_their_row

  _hi_h2 "Testing: _hi_toml_packages and _hi_toml_colors"
  _hi_check "A group's rows gather by kind" test_toml_packages_gather_a_group_by_kind
  _hi_check "A group named twice is one table" test_toml_packages_merge_a_group_named_twice
  _hi_check "Comments travel with the row or the group below" test_toml_packages_comments_travel
  _hi_check "A colors row is its name and a string" test_toml_colors_rows_become_strings

  _hi_h2 "Testing: _hi_convert_colors"
  _hi_check "Types in first-appearance order, rows in file order" test_colors_group_rows_by_type_in_order
  _hi_check "Comments travel with the row below" test_colors_comments_travel_with_their_row

  _hi_h2 "Testing: the plugins"
  _hi_check "A carry's lines become rows of a [carry] table" test_carry_lines_become_rows
  _hi_check "Rows become a table a tool" test_plugins_rows_become_tables
  _hi_check "...which hi reads as it read the rows" test_converted_plugins_read_as_their_rows_did
  _hi_check "The entry point converts a carry and a plugins file of rows" test_entry_converts_the_carry

  _hi_h2 "Testing: _hi_convert_settings"
  _hi_check "The floor maps to groups; 2 goes" test_settings_map_the_floor_to_groups
  _hi_check "Beside a groups line the floor just goes" test_settings_drop_the_floor_beside_groups
  _hi_check "A trailing comment, install's marker too, is kept" test_settings_keep_the_trailing_comment
  _hi_check "The old alias toggles go, a comment naming one stays" test_settings_drop_the_old_alias_toggles
  _hi_check "An editor's toggle becomes its word in the list" test_settings_move_the_tool_toggles_to_the_list
  _hi_check "A group's word becomes its plugins'" test_settings_spell_a_group_as_its_plugins
  _hi_check "...on a line the wizard's block takes as its own" test_settings_list_line_keeps_the_marker

  _hi_h2 "Testing: convert_settings.sh"
  _hi_check "Converts each old file, keeping <file>.old" test_entry_converts_each_old_file
  _hi_check "An old alias toggle alone makes settings.sh old-format" test_entry_converts_the_old_alias_toggles
  _hi_check "...and so does an editor's" test_entry_converts_a_tool_toggle
  _hi_check "...and a group's word in a list" test_entry_converts_a_group_word
  _hi_check "--dry-run writes nothing" test_entry_dry_run_writes_nothing
  _hi_check "A second run is a no-op" test_entry_is_idempotent
  _hi_check "The rows under [section] lines are converted too" test_entry_converts_the_sections
  _hi_check "Current or absent files are left alone" test_entry_leaves_current_files_alone
  _hi_check "...and so is a TOML file with a line hi does not read" test_entry_leaves_a_toml_file_with_an_unread_line_alone
  _hi_check "No directory means the overlay" test_entry_defaults_to_the_overlay
  _hi_check "--help, and an unknown option refused" test_entry_help_and_unknown_option

  _hi_h2 "Testing: an older hi's shipped files"
  _hi_check "config/packages converts and parses" test_shipped_old_packages_convert_and_parse
  _hi_check "config/colors converts and resolves the same" test_shipped_old_colors_convert_and_resolve
  _hi_check "The sections' config/packages converts whole" test_shipped_sections_packages_convert_whole
  _hi_check "...and their config/colors" test_shipped_sections_colors_convert_whole

  _hi_suite_end "scripts/convert_settings.sh"
}

run_convert_settings_tests
