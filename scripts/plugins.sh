#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# `hi --plugins`: every plugin - a config hi carries to a target, its own
# table's or a line of your carry file - with what rides and what is off.
# `hi --plugin-off` and `--plugin-on` (a leading --off, --on) switch plugins
# through $_HI_PLUGINS_OFF in settings.sh; `hi --add-plugin` and
# `--remove-plugin` (--add, --remove) write a line of ~/.config/say-hi/carry.
# set_color.sh's shape: HI.33 the standalone entry, HI.09 the commit step.
# GLOSSARY: HI.63, HI.64
#
# SC2317/SC2329: shellcheck follows the `source` of hi.sh below into its
# trailing `_hi "$@"`, decides that call never returns, and marks everything
# after the source line unreachable (scripts/doctor.sh has the same story).
# shellcheck disable=SC2317,SC2329

# GLOSSARY: HI.33 - the standalone-entry form, and why $_HI_HOME wins in it
_hi_d="${BASH_SOURCE[0]}"
case "$_hi_d" in */*) _hi_d="${_hi_d%/*}/.." ;; *) _hi_d=".." ;; esac
[ -z "${_HI_HOME:-}" ] || _hi_d="$_HI_HOME/say-hi"
# shellcheck source=../common/core.sh
source "$_hi_d/common/core.sh"
# the table, the carry's reader, and what is off: hi.sh's own, so this lists
# exactly what a connect would pack. Ahead of lib.sh, whose _hi_die names the
# command where hi.sh's says hi.
# shellcheck source=../hi.sh
source "$_hi_d/hi.sh"
# shellcheck source=./lib.sh
source "$_hi_d/scripts/lib.sh"
unset _hi_d

# after core.sh, which ends with `set +euo pipefail`. GLOSSARY: HI.15
set -euo pipefail

mode="list"
case "${1:-}" in
--off | --on | --add | --remove)
  mode="${1#--}"
  shift
  ;;
esac
case "$mode" in
list) me="hi --plugins" usage="hi --plugins" ;;
off | on) me="hi --plugin-$mode" usage="hi --plugin-$mode <name>... [--dry-run]" ;;
add) me="hi --add-plugin" usage="hi --add-plugin <member> <tool> <wire> <home> [--dry-run]" ;;
remove) me="hi --remove-plugin" usage="hi --remove-plugin <member> [--dry-run]" ;;
esac
me="${_HI_ARGV0:-$me}"
_HI_ME="$me"
_HI_DRY_RUN="" args=()
carry="$_HI_CONFIG_DIR/carry"

function _hi_plugins_help() {
  case "$mode" in
  list)
    cat <<EOF
Usage: $usage

Lists every plugin: a config hi carries to a target and points its tool at.
One row a member, with the file that rides, or why none does: its plugin is
switched off, its tool is not installed here, or there is nothing to carry.

  hi --plugin-off <name>...     switch plugins off: nothing of theirs rides
  hi --plugin-on <name>...      switch them back on
  hi --add-plugin <member> <tool> <wire> <home>
                                carry a config of a tool hi does not know
  hi --remove-plugin <member>   stop carrying it

A <name> is a plugin, a group, or a member, as listed here.
EOF
    ;;
  off | on)
    cat <<EOF
Usage: $usage

Switches plugins $mode for every target: a plugin that is off sends no file
and sets nothing there, so the tool keeps the target's own config. <name> is
a plugin, a group, or a member, as \`hi --plugins\` lists them. The list is
_HI_PLUGINS_OFF in ~/.config/say-hi/settings.sh.

  -n, --dry-run    say what would be written, and write nothing
EOF
    ;;
  add)
    cat <<EOF
Usage: $usage

Adds a line to ~/.config/say-hi/carry: <member> is the name the file rides
under, <tool> the command that reads it (or -), <wire> how a target's tool
finds it (env:<variables>, envdir:<variable>, 'flag:<command> <flag>',
'flagdir:<command> <flag>', or -), and <home> where the file is here: paths
a : apart, each starting at /, ~/, or \$NAME; several a , apart are one
place, the first whose variable is set. Quote <home>, or the shell expands
it first.

  -n, --dry-run    say what would be written, and write nothing

  hi --add-plugin taskrc task env:TASKRC '\$TASKRC : ~/.taskrc'
EOF
    ;;
  remove)
    cat <<EOF
Usage: $usage

Removes <member>'s line from ~/.config/say-hi/carry. A plugin of hi's own
has no line to remove: \`hi --plugin-off\` switches it off.

  -n, --dry-run    say what would be written, and write nothing
EOF
    ;;
  esac
}

while [ $# -gt 0 ]; do
  case "$1" in
  -h | --help)
    _hi_plugins_help
    exit 0
    ;;
  -n | --dry-run) _HI_DRY_RUN=1 ;;
  # a wire or a home of - is a word, and so is a flag: wire's own
  - | flag*) args+=("$1") ;;
  -*) _hi_die "unknown option $1 ($usage)" ;;
  *) args+=("$1") ;;
  esac
  shift
done

# _hi_plugins_state <member> <outvar> - what a connect does with <member>,
# in a phrase; 1 when it is off
function _hi_plugins_state() {
  local src="" why="" tilde='~'
  case "$1" in
  */ | *.d)
    src="$(_hi_overlay_files "$1" | grep -c .)" || true
    if [ "$src" = 0 ]; then src=""; else src="$src file(s)"; fi
    ;;
  *) ! _hi_overlay_src "$1" src || src="${src/#"$HOME"/$tilde}" ;;
  esac
  if [ -n "$src" ]; then
    printf -v "$2" '%s' "rides: $src"
  elif _hi_unsent_why "$1" why; then
    printf -v "$2" '%s' "stays home: $why"
  else
    printf -v "$2" '%s' "nothing to carry"
  fi
  [ "${why#switched off}" = "$why" ]
}

function _hi_plugins_list() {
  local name group member state color
  printf ' %-14s %-8s %-22s %s\n' plugin group member state
  while IFS='|' read -r name group member; do
    color="$GREEN"
    _hi_plugins_state "$member" state || color="$YELLOW"
    case "$state" in rides:* | *"switched off"*) ;; *) color="" ;; esac
    _hi_cecho "$(printf ' %-14s %-8s %-22s %s' "$name" "$group" "$member" "$state")" "$color"
  done < <(_hi_plugin_rows)
  for state in ${_HI_CARRY_BAD[@]+"${_HI_CARRY_BAD[@]}"}; do
    _hi_cecho " $carry line ${state%%|*} is ignored: ${state#*|}" "$YELLOW"
  done
}

# _hi_plugins_off_now <outvar> - the list settings.sh holds, read off its
# last _HI_PLUGINS_OFF line without running it, a space between its words
function _hi_plugins_off_now() {
  local value=""
  _hi_rc_value _HI_PLUGINS_OFF value "$_HI_SETTINGS" || true
  printf -v "$1" '%s' "${value//,/ }"
}

# _hi_plugins_write_off <list> - settings.sh with that list as its one
# _HI_PLUGINS_OFF line, or with none when the list is empty
function _hi_plugins_write_off() {
  local tmpfile line
  dry_run_say "write _HI_PLUGINS_OFF='$1' to $_HI_SETTINGS" && return 0
  mkdir -p "$_HI_CONFIG_DIR"
  tmpfile="$(mktemp -t hi.plugins.XXXXXX)"
  if [ -f "$_HI_SETTINGS" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?_HI_PLUGINS_OFF= ]] || printf '%s\n' "$line"
    done <"$_HI_SETTINGS" >"$tmpfile"
  else
    printf '#!/bin/sh\n' >"$tmpfile"
  fi
  [ -z "$1" ] || printf "export _HI_PLUGINS_OFF='%s'\n" "$1" >>"$tmpfile"
  _hi_write_back "$tmpfile" "$_HI_SETTINGS"
  _hi_cecho "$_HI_SETTINGS updated" "$GREEN"
}

# _hi_plugins_toggled <word> <outvar> - is a member <word> names (as its
# plugin, its group, or itself) off by a toggle, the list aside?
function _hi_plugins_toggled() {
  local name group member
  while IFS='|' read -r name group member; do
    case "$1" in "$name" | "$group" | "$member") ;; *) continue ;; esac
    ! _HI_PLUGINS_OFF="" _hi_plugin_off "$member" "$2" || return 0
  done < <(_hi_plugin_rows)
  return 1
}

function _hi_plugins_switch() {
  local word known now="" next="" w why="" changed=""
  [ "${#args[@]}" -gt 0 ] || _hi_die "needs a plugin, a group, or a member ($me --help)"
  known=" $(_hi_plugin_words | tr '\n' ' ')"
  _hi_plugins_off_now now
  next=" $now "
  for word in "${args[@]}"; do
    case "$known" in *" $word "*) ;; *) _hi_die "not a plugin, a group, or a member: $word (hi --plugins lists them)" ;; esac
    case "$mode:$next" in
    off:*" $word "*) _hi_cecho " $word is off already" "$GREEN" ;;
    off:*)
      next="$next$word "
      changed=1
      _hi_cecho " - $word" "$YELLOW"
      ;;
    on:*" $word "*)
      next="${next// $word / }"
      changed=1
      _hi_cecho " + $word" "$GREEN"
      ;;
    on:*)
      # off by a toggle: that is hi --configure's to change
      if _hi_plugins_toggled "$word" why; then
        _hi_cecho " $word is off by $why, which hi --configure sets" "$YELLOW"
      else
        _hi_cecho " $word is not in the list - nothing to switch" "$GREEN"
      fi
      ;;
    esac
  done
  [ -n "$changed" ] || exit 0
  # one space between words, none at the ends
  now=""
  for w in $next; do now="$now${now:+ }$w"; done
  _hi_plugins_write_off "$now"
}

# _hi_plugins_column <outvar> <line> - the first column of a carry line,
# without the spaces around it
function _hi_plugins_column() {
  local _hi_pc="${2%%|*}"
  _hi_trim _hi_pc
  printf -v "$1" '%s' "$_hi_pc"
}

# _hi_plugins_lines <file> - its lines, the last one ended whether or not
# the file ends it, so a line added after it starts its own
function _hi_plugins_lines() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do printf '%s\n' "$line"; done <"$1"
}

function _hi_plugins_add() {
  local row tmpdir tmpfile why=""
  [ "${#args[@]}" -eq 4 ] || _hi_die "needs a member, a tool, a wire, and a home ($me --help)"
  row="${args[0]} | ${args[1]} | ${args[2]} | ${args[3]}"
  # through the reader a connect uses, over a copy with the line as its
  # last: good when that reader turns the last line down for nothing
  tmpdir="$(mktemp -d -t hi.plugins.XXXXXX)"
  [ ! -f "$carry" ] || _hi_plugins_lines "$carry" >"$tmpdir/carry"
  printf '%s\n' "$row" >>"$tmpdir/carry"
  why="$(
    _HI_CONFIG_DIR="$tmpdir" _hi_carry_load
    last=0
    _hi_count_lines last <"$tmpdir/carry"
    for each in ${_HI_CARRY_BAD[@]+"${_HI_CARRY_BAD[@]}"}; do
      [ "${each%%|*}" != "$last" ] || printf '%s' "${each#*|}"
    done
  )"
  command rm -f "$tmpdir/carry"
  rmdir "$tmpdir"
  [ -z "$why" ] || _hi_die "$why ($me --help)"
  _hi_cecho " + $row" "$GREEN"
  dry_run_say "add that line to $carry" && exit 0
  mkdir -p "$_HI_CONFIG_DIR"
  tmpfile="$(mktemp -t hi.plugins.XXXXXX)"
  if [ -f "$carry" ]; then
    _hi_plugins_lines "$carry" >"$tmpfile"
  else
    printf '# member | tool | wire | home, best first\n' >"$tmpfile"
  fi
  printf '%s\n' "$row" >>"$tmpfile"
  _hi_write_back "$tmpfile" "$carry"
  _hi_cecho "$carry updated" "$GREEN"
}

function _hi_plugins_remove() {
  local line first tmpfile found=""
  local -a kept=()
  [ "${#args[@]}" -eq 1 ] || _hi_die "needs one member ($me --help)"
  [ ! -f "$carry" ] || while IFS= read -r line || [ -n "$line" ]; do
    _hi_plugins_column first "$line"
    case "$first" in
    '#'*) kept+=("$line") ;;
    "${args[0]}")
      found=1
      _hi_cecho " - $line" "$YELLOW"
      ;;
    *) kept+=("$line") ;;
    esac
  done <"$carry"
  if [ -z "$found" ]; then
    _hi_overlay_row "${args[0]}" >/dev/null &&
      _hi_die "${args[0]} is hi's own, with no line to remove: hi --plugin-off ${args[0]} switches it off"
    _hi_cecho "$carry has no line for ${args[0]} - nothing to write" "$GREEN"
    exit 0
  fi
  dry_run_say "write $carry without it" && exit 0
  tmpfile="$(mktemp -t hi.plugins.XXXXXX)"
  printf '%s\n' ${kept[@]+"${kept[@]}"} >"$tmpfile"
  _hi_write_back "$tmpfile" "$carry"
  _hi_cecho "$carry updated" "$GREEN"
}

case "$mode" in
list)
  [ "${#args[@]}" -eq 0 ] || _hi_die "takes no argument ($me --help)"
  _hi_plugins_list
  ;;
off | on) _hi_plugins_switch ;;
add) _hi_plugins_add ;;
remove) _hi_plugins_remove ;;
esac
