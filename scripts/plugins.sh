#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# `hi --plugins`: every plugin - a config hi carries to a target, a row of
# config/plugins or of your own plugins file - with what rides and what is
# off. `hi --plugin-off` and `--plugin-on` (a leading --off, --on) switch
# plugins through $_HI_PLUGINS_OFF in settings.sh; `hi --add-plugin` and
# `--remove-plugin` (--add, --remove) write a row of ~/.config/say-hi/plugins.
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
# the table, the plugins files' reader, and what is off: hi.sh's own, so this lists
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
add) me="hi --add-plugin" usage="hi --add-plugin <group> <member> <tool> <wire> <home> [<dialect>] [--dry-run]" ;;
remove) me="hi --remove-plugin" usage="hi --remove-plugin <member> [--dry-run]" ;;
esac
me="${_HI_ARGV0:-$me}"
_HI_ME="$me"
_HI_DRY_RUN="" args=()
plugins="$_HI_CONFIG_DIR/plugins"

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
  hi --add-plugin <group> <member> <tool> <wire> <home> [<dialect>]
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

Adds a row to the [<group>] table of ~/.config/say-hi/plugins, which adds
to the tree's config/plugins or replaces its row of the same <member>.
<group> is the word that switches the row with its kind (editors, mux,
prompt, cli, shell, or one of your own), <member> the name the file rides
under, <tool> the command that reads it (or -), <wire> how a target's tool
finds it (env:<variables>, envdir:<variable>, 'flag:<command> <flag>',
'flagdir:<command> <flag>', xdg:<command> for a file it has no variable or
flag for, or -), and <home> where the file is here: paths
a : apart, each starting at /, ~/, or \$NAME; several a , apart are one
place, the first whose variable is set. Quote <home>, or the shell expands
it first. <dialect> is how its includes are found and its comments stripped
(sh, fish, vim, lua, elisp, nano, tmux, screen, readline, kak, kdl, omp,
omp-json, conf); left out, it rides as written.

  -n, --dry-run    say what would be written, and write nothing

  hi --add-plugin cli taskrc task env:TASKRC '\$TASKRC : ~/.taskrc'
EOF
    ;;
  remove)
    cat <<EOF
Usage: $usage

Removes <member>'s row from ~/.config/say-hi/plugins. A plugin of hi's own
has no row there to remove: \`hi --plugin-off\` switches it off.

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

function _hi_plugins_list() {
  local name group member state color
  printf ' %-14s %-8s %-22s %s\n' plugin group member state
  while IFS='|' read -r name group member; do
    color="$GREEN"
    _hi_plugin_state "$member" state || color="$YELLOW"
    case "$state" in rides:* | *"switched off"*) ;; *) color="" ;; esac
    _hi_cecho "$(printf ' %-14s %-8s %-22s %s' "$name" "$group" "$member" "$state")" "$color"
  done < <(_hi_plugin_rows)
  for state in ${_HI_PLUGIN_BAD[@]+"${_HI_PLUGIN_BAD[@]}"}; do
    _hi_plugins_bad_where name "${state%%|*}"
    _hi_cecho " $name is ignored: ${state#*|}" "$YELLOW"
  done
}

# _hi_plugins_bad_where <outvar> <file:line> - a $_HI_PLUGIN_BAD entry's
# place as a path and a line
function _hi_plugins_bad_where() {
  case "$2" in
  config/*) printf -v "$1" '%s line %s' "$_HI_ROOT/${2%%:*}" "${2#*:}" ;;
  *) printf -v "$1" '%s line %s' "$_HI_CONFIG_DIR/${2%%:*}" "${2#*:}" ;;
  esac
}

# _hi_plugins_off_now <outvar> - the list settings.sh holds, read off its
# last _HI_PLUGINS_OFF line without running it, a space between its words
function _hi_plugins_off_now() {
  local value=""
  _hi_rc_value _HI_PLUGINS_OFF value "$_HI_SETTINGS" || true
  printf -v "$1" '%s' "${value//,/ }"
}

# _hi_plugins_write_off <list> - settings.sh with that list as its one
# _HI_PLUGINS_OFF line, among the lines hi --configure writes, or with none
# when the list is empty
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
  # the wizard's own spelling of the line (rc_tagged), so its block holds it
  [ -z "$1" ] || printf '%-45s %s\n' "export _HI_PLUGINS_OFF='$1'" "$_HI_MARKER" >>"$tmpfile"
  _hi_write_back "$tmpfile" "$_HI_SETTINGS"
  _hi_cecho "$_HI_SETTINGS updated" "$GREEN"
}

function _hi_plugins_switch() {
  local word known now="" next="" w changed=""
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
    on:*) _hi_cecho " $word is not in the list - nothing to switch" "$GREEN" ;;
    esac
  done
  [ -n "$changed" ] || exit 0
  # one space between words, none at the ends
  now=""
  for w in $next; do now="$now${now:+ }$w"; done
  _hi_plugins_write_off "$now"
}

# _hi_plugins_index <outvar> <member> - the index in `_hi_rows` of the
# overlay file's row of that member, or -1
function _hi_plugins_index() {
  local _hi_pi_i _hi_pi_k _hi_pi_v
  for ((_hi_pi_i = 0; _hi_pi_i < ${#_hi_rows[@]}; _hi_pi_i++)); do
    _hi_toml_row "${_hi_rows[_hi_pi_i]}" _hi_pi_k _hi_pi_v || continue
    [ "$_hi_pi_k" != "$2" ] || {
      printf -v "$1" '%s' "$_hi_pi_i"
      return 0
    }
  done
  printf -v "$1" '%s' -1
}

# _hi_plugins_write - `_hi_rows` as the overlay's plugins file
function _hi_plugins_write() {
  local tmpfile
  mkdir -p "$_HI_CONFIG_DIR"
  tmpfile="$(mktemp -t hi.plugins.XXXXXX)"
  printf '%s\n' "${_hi_rows[@]}" >"$tmpfile"
  _hi_write_back "$tmpfile" "$plugins"
  _hi_cecho "$plugins updated" "$GREEN"
}

function _hi_plugins_add() {
  local group member key row tmpdir at=-1 table="" why="" line said=""
  local -a existing_lines=()
  [ "${#args[@]}" -eq 5 ] || [ "${#args[@]}" -eq 6 ] ||
    _hi_die "needs a group, a member, a tool, a wire, and a home, then a dialect or nothing ($me --help)"
  group="${args[0]}" member="${args[1]}"
  _hi_words_ok "$group" 'A-Za-z0-9_' 'A-Za-z0-9_-' && [ "${group% *}" = "$group" ] ||
    _hi_die "not a group name: $group (letters, digits, _ -)"
  case "${args[2]}${args[3]}${args[4]}${args[5]:-}" in *['"'\\]*) _hi_die "a column cannot hold a quote or a backslash ($me --help)" ;; esac
  _hi_toml_key key "$member"
  row="$key = \"${args[2]} | ${args[3]} | ${args[4]}${args[5]:+ | ${args[5]}}\""
  [ -f "$plugins" ] && _hi_read_lines existing_lines <"$plugins"
  _hi_rows=(${existing_lines[@]+"${existing_lines[@]}"})
  _hi_plugins_index at "$member"
  if [ "$at" -ge 0 ]; then
    _hi_section_of table "$at"
    if [ "${_hi_rows[at]}" = "$row" ] && [ "$table" = "$group" ]; then
      _hi_cecho "$plugins: that row is there already - nothing to write" "$GREEN"
      exit 0
    fi
    said=" ~ $row (replacing the row for $member in [${table:-no group}])|$YELLOW"
    if [ "$table" = "$group" ]; then
      _hi_rows[at]="$row"
    else
      _hi_rows=("${_hi_rows[@]:0:at}" "${_hi_rows[@]:at+1}")
      _hi_section_add "$group" "$row"
    fi
  else
    said=" + $row in [$group]|$GREEN"
    [ "${#_hi_rows[@]}" -gt 0 ] || _hi_rows=('# a row a config of yours rides by: "<member>" = "<tool> | <wire> | <home> | <dialect>"')
    _hi_section_add "$group" "$row"
  fi
  # through the reader a connect uses, over the file as it would be: good
  # when that reader turns the row down for nothing
  tmpdir="$(mktemp -d -t hi.plugins.XXXXXX)"
  printf '%s\n' "${_hi_rows[@]}" >"$tmpdir/plugins"
  _hi_plugins_index at "$member"
  at=$((at + 1))
  why="$(
    _HI_CONFIG_DIR="$tmpdir" _hi_plugins_load
    for line in ${_HI_PLUGIN_BAD[@]+"${_HI_PLUGIN_BAD[@]}"}; do
      [ "${line%%|*}" != "plugins:$at" ] || printf '%s' "${line#*|}"
    done
  )"
  command rm -f "$tmpdir/plugins"
  rmdir "$tmpdir"
  [ -z "$why" ] || _hi_die "$why ($me --help)"
  _hi_cecho "${said%|*}" "${said##*|}"
  dry_run_say "write $plugins" && exit 0
  _hi_plugins_write
}

function _hi_plugins_remove() {
  local at=-1 table=""
  local -a existing_lines=()
  [ "${#args[@]}" -eq 1 ] || _hi_die "needs one member ($me --help)"
  [ -f "$plugins" ] && _hi_read_lines existing_lines <"$plugins"
  _hi_rows=(${existing_lines[@]+"${existing_lines[@]}"})
  _hi_plugins_index at "${args[0]}"
  if [ "$at" -lt 0 ]; then
    _hi_overlay_row "${args[0]}" >/dev/null &&
      _hi_die "${args[0]} is hi's own, with no row of yours to remove: hi --plugin-off ${args[0]} switches it off"
    _hi_cecho "$plugins has no row for ${args[0]} - nothing to write" "$GREEN"
    exit 0
  fi
  _hi_section_of table "$at"
  _hi_cecho " - ${_hi_rows[at]} (from [${table:-no group}])" "$YELLOW"
  _hi_rows=("${_hi_rows[@]:0:at}" "${_hi_rows[@]:at+1}")
  dry_run_say "write $plugins without it" && exit 0
  _hi_plugins_write
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
