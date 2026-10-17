#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# `hi --plugins`: every plugin - the configs of a tool's hi carries to a
# target, a table of config/plugins or of your own plugins file - with what
# rides and what is off. `hi --disable-plugin` and `--enable-plugin` (a leading
# --off, --on) switch plugins through $_HI_PLUGINS_OFF in settings.sh. A
# table of your own is written by hand: `hi --edit plugins`.
# set_color.sh's shape: HI.33 the standalone entry, HI.09 the commit step.
# GLOSSARY: HI.63, HI.64
#
# SC2317/SC2329: shellcheck follows the `source` of hi.sh below into its
# trailing `_hi "$@"`, decides that call never returns, and marks everything
# after the source line unreachable (scripts/doctor.sh has the same story).
# shellcheck disable=SC2317,SC2329

# --text, read ahead of core.sh: its palette is set as it is sourced, and
# $NO_COLOR is how it is asked for none
_HI_TEXT=0
case " $* " in *" --text "*) _HI_TEXT=1 && export NO_COLOR=1 ;; esac

# GLOSSARY: HI.33 - the standalone-entry form, and why $_HI_HOME wins in it
_hi_d="${BASH_SOURCE[0]}"
case "$_hi_d" in */*) _hi_d="${_hi_d%/*}/.." ;; *) _hi_d=".." ;; esac
[ -z "${_HI_HOME:-}" ] || _hi_d="$_HI_HOME/say-hi"
[ -z "${_HI_ROOT:-}" ] || [ "${_HI_ROOT%/*}" != "${_HI_HOME:-${_HI_ROOT%/*}}" ] || _hi_d="$_HI_ROOT"
# shellcheck source=../common/core.sh
source "$_hi_d/common/core.sh"
# the table, the plugins files' reader, and what is off: hi.sh's own, so this lists
# exactly what a connect would pack. Ahead of lib.sh, whose _hi_die names the
# command where hi.sh's says hi.
# shellcheck source=../hi.sh
source "$_hi_d/hi.sh"
# shellcheck source=./lib.sh
source "$_hi_d/scripts/lib.sh"
# shellcheck source=./table.sh
source "$_hi_d/scripts/table.sh"
# shellcheck source=./rc.sh
source "$_hi_d/scripts/rc.sh"
unset _hi_d

# after core.sh, which ends with `set +euo pipefail`. GLOSSARY: HI.15
set -euo pipefail

mode="list"
case "${1:-}" in
--off | --on)
  mode="${1#--}"
  shift
  ;;
esac
case "$mode" in
list) me="hi --plugins" usage="hi --plugins [--text]" ;;
off) me="hi --disable-plugin" usage="hi --disable-plugin <name>... [--dry-run]" ;;
on) me="hi --enable-plugin" usage="hi --enable-plugin <name>... [--dry-run]" ;;
esac
me="${_HI_ARGV0:-$me}"
_HI_ME="$me"
_HI_DRY_RUN="" args=()

function _hi_plugins_help() {
  case "$mode" in
  list)
    cat <<EOF
Usage: $usage

Lists every plugin: the configs of a tool's hi carries to a target and points
the tool at. A table a group and a row a member, as hi --doctor draws it:
where its file is found, and whether it rides or why not - its plugin is
switched off, or its tool is not installed here. Members found nowhere share
one last row.

  hi --disable-plugin <name>...     switch plugins off: nothing of theirs rides
  hi --enable-plugin <name>...      switch them back on
  hi --edit plugins                 open your plugins file, for a tool hi does not know

A <name> is a plugin or a member, as listed here, or one file of a member
that is a directory (extensions/10-kube).

  --text    no box and no color: one row a line, "group / member: text", a
            riding row saying (ok), for a screen reader or a grep
EOF
    ;;
  off | on)
    cat <<EOF
Usage: $usage

Switches plugins $mode for every target: a plugin that is off sends no file
and sets nothing there, so the tool keeps the target's own config. <name> is
a plugin or a member, as \`hi --plugins\` lists them, or one file of a member
that is a directory (extensions/10-kube). The list is _HI_PLUGINS_OFF in
~/.config/say-hi/settings.sh.

  -n, --dry-run    say what would be written, and write nothing
EOF
    ;;
  esac
}

# --text, read ahead of core.sh above, is the list's alone
_hi_argv=()
for _hi_a in "$@"; do
  [ "$_hi_a" != --text ] || continue
  _hi_argv+=("$_hi_a")
done
set -- ${_hi_argv[@]+"${_hi_argv[@]}"}
unset _hi_argv _hi_a
[ "$_HI_TEXT" != 1 ] || [ "$mode" = list ] || _hi_die "--text is hi --plugins' switch ($me --help)"
_hi_args _hi_plugins_help "$usage" "$@"

# _hi_plugin_row <label> <text> [severity] - a member's row, its label in the
# color of its plugin's state (lib.sh's _hi_plugin_color)
function _hi_plugin_row() {
  local c state=absent
  if [ "${3:-}" = ok ]; then state=rides; elif _hi_plugin_off "${1%% (*}"; then state=off; fi
  _hi_plugin_color c "$state"
  _hi_row "$1" "$2" "${3:-}" "$c"
}

# a section a group, in the order the rows name them, and a member's row as
# `hi --doctor` draws it (lib.sh's _hi_member_rows), its label colored; the
# rows hi could not read last, a warn each
function _hi_plugins_list() {
  local name group groups=" " row line _HI_ROW_FN=_hi_plugin_row
  local -a rows members
  _hi_plugins_load
  _hi_read_lines rows < <(_hi_plugin_rows)
  for row in ${rows[@]+"${rows[@]}"}; do
    group="${row#*|}" group="${group%|*}"
    _hi_list_has "$groups" "$group" || groups="$groups$group "
  done
  # shellcheck disable=SC2086 # group names, a space apart
  for group in $groups; do
    members=()
    for row in "${rows[@]}"; do
      case "$row" in *"|$group|"*) members+=("${row##*|}") ;; esac
    done
    _hi_section "$group"
    _hi_member_rows "${members[@]}"
    _hi_rows_flush
  done
  # the shell hooks, prompt programs among them (HI.67)
  if [ "${#_HI_PLUGIN_HOOKS[@]}" -gt 0 ]; then
    _hi_section "hooks"
    _hi_hook_rows
    _hi_rows_flush
  fi
  # the variables whose values ride (HI.62)
  if [ "${#_HI_PLUGIN_ENVS[@]}" -gt 0 ]; then
    _hi_section "variables"
    _hi_env_rows
    _hi_rows_flush
  fi
  # what a dialect keeps home as private, riding under a hi-allow (HI.57)
  _hi_read_lines rows < <(_hi_allowed_lines)
  if [ "${#rows[@]}" -gt 0 ]; then
    _hi_section "allowed"
    for row in "${rows[@]}"; do
      IFS='|' read -r name line _ group <<<"$row"
      _hi_row "$name:$line" "rides under its hi-allow: $group"
    done
    _hi_rows_flush
  fi
  [ "${#_HI_PLUGIN_BAD[@]}" -gt 0 ] || return 0
  _hi_section "ignored"
  for line in "${_HI_PLUGIN_BAD[@]}"; do
    # a file:line of the tree's config/, of the site's (a whole path), or
    # of the overlay
    name="$_HI_CONFIG_DIR/"
    case "$line" in config/*) name="$_HI_ROOT/" ;; /*) name="" ;; esac
    row="${line%%|*}"
    _hi_row "$name${row%%:*} line ${row#*:}" "${line#*|}" warn
  done
  _hi_rows_flush
}

# _hi_plugins_write_list <_HI_PLUGINS_OFF|_HI_PLUGINS_ON> <list> - settings.sh
# with that list as its one line of that name, among the lines hi --configure
# writes, or with none when the list is empty
function _hi_plugins_write_list() {
  local var="$1" tmpfile line
  shift
  dry_run_say "write $var='$1' to $_HI_SETTINGS" && return 0
  mkdir -p "$_HI_CONFIG_DIR"
  tmpfile="$(mktemp -t hi.plugins.XXXXXX)"
  if [ -f "$_HI_SETTINGS" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?$var= ]] || printf '%s\n' "$line"
    done <"$_HI_SETTINGS" >"$tmpfile"
  else
    # a new file opens as the wizard's block does, on its shape line
    printf '#!/bin/sh\n' >"$tmpfile"
    rc_tagged line "# say-hi settings $_HI_SETTINGS_SHAPE"
    printf '%s' "$line" >>"$tmpfile"
  fi
  # the wizard's own spelling of the line, so its block holds it
  local tagged
  [ -z "$1" ] || rc_tagged tagged "export $var='$1'"
  printf '%s' "${tagged:-}" >>"$tmpfile"
  _hi_write_back "$tmpfile" "$_HI_SETTINGS"
  _hi_cecho "$_HI_SETTINGS updated" "$GREEN"
}

function _hi_plugins_switch() {
  local word known now="" next="" w changed="" on="" nexton="" changedon=""
  [ "${#args[@]}" -gt 0 ] || _hi_die "needs a plugin or a member ($me --help)"
  _hi_plugins_load
  known=" $(_hi_plugin_words | tr '\n' ' ')"
  # settings.sh's last _HI_PLUGINS_OFF and _HI_PLUGINS_ON lines, read without
  # running them
  _hi_rc_value _HI_PLUGINS_OFF now "$_HI_SETTINGS" || true
  _hi_rc_value _HI_PLUGINS_ON on "$_HI_SETTINGS" || true
  now="${now//,/ }" on="${on//,/ }"
  next=" $now " nexton=" $on "
  for word in "${args[@]}"; do
    _hi_plugin_word_ok "$word" "$known" || _hi_die "not a plugin or a member: $word (hi --plugins lists them)"
    # a plugin off by default moves through the on list: on adds it there,
    # off takes it out (and never into the off list, which would say more
    # than it needs to)
    case "$_HI_PLUGIN_DEFAULT_OFF" in *" $word "*) ;; *) word="$word|" ;; esac
    if [ "${word%|}" = "$word" ]; then
      case "$mode:$nexton" in
      on:*" $word "*) _hi_cecho " $word is on already" "$GREEN" ;;
      on:*)
        nexton="$nexton$word "
        changedon=1
        _hi_cecho " + $word" "$GREEN"
        ;;
      off:*" $word "*)
        nexton="${nexton// $word / }"
        changedon=1
        _hi_cecho " - $word" "$YELLOW"
        ;;
      off:*) _hi_cecho " $word is off already (off by default)" "$GREEN" ;;
      esac
      continue
    fi
    word="${word%|}"
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
  [ -n "$changed" ] || [ -n "$changedon" ] || exit 0
  # one space between words, none at the ends
  now="" on=""
  for w in $next; do now="$now${now:+ }$w"; done
  for w in $nexton; do on="$on${on:+ }$w"; done
  [ -z "$changed" ] || _hi_plugins_write_list _HI_PLUGINS_OFF "$now"
  [ -z "$changedon" ] || _hi_plugins_write_list _HI_PLUGINS_ON "$on"
}

case "$mode" in
list)
  [ "${#args[@]}" -eq 0 ] || _hi_die "takes no argument ($me --help)"
  _hi_plugins_list
  ;;
off | on) _hi_plugins_switch ;;
esac
