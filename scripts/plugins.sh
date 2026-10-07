#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# `hi --plugins`: every plugin - the configs of a tool's hi carries to a
# target, a table of config/plugins or of your own plugins file - with what
# rides and what is off. `hi --plugin-off` and `--plugin-on` (a leading
# --off, --on) switch plugins through $_HI_PLUGINS_OFF in settings.sh; `hi
# --add-plugin` and `--remove-plugin` (--add, --remove) write a table of
# ~/.config/say-hi/plugins.
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
# shellcheck source=./table.sh
source "$_hi_d/scripts/table.sh"
# shellcheck source=./rc.sh
source "$_hi_d/scripts/rc.sh"
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
add) me="hi --add-plugin" usage="hi --add-plugin <group> <name> <file>... [<key>=<value>...] [--dry-run]" ;;
remove) me="hi --remove-plugin" usage="hi --remove-plugin <name> [--dry-run]" ;;
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

Lists every plugin: the configs of a tool's hi carries to a target and points
the tool at. A table a group and a row a member, as hi --doctor draws it:
where its file is found, and whether it rides or why not - its plugin is
switched off, or its tool is not installed here. Members found nowhere share
one last row.

  hi --plugin-off <name>...     switch plugins off: nothing of theirs rides
  hi --plugin-on <name>...      switch them back on
  hi --add-plugin <group> <name> <file>... [<key>=<value>...]
                                carry the configs of a tool hi does not know
  hi --remove-plugin <name>     stop carrying them

A <name> is a plugin or a member, as listed here, or one file of a member
that is a directory (extensions/10-kube).
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
  add)
    cat <<EOF
Usage: $usage

Writes the [<group>.<name>] table of ~/.config/say-hi/plugins, which adds a
plugin to the tree's config/plugins or replaces its plugin of that <name>.
<group> is the section it is listed under (editors, mux, prompt, cli, shell,
or one of your own), <name> the plugin's own word and its name in a report,
and each <file> the name a config rides under. The keys:

  tool=<commands>     what reads them; home's copy rides with any of them on
                      this machine. Left out, it is <name>; - asks nothing.
  wire=<wire>         how a target's tool finds a file: env:<variables>,
                      envdir:<variable>, 'flag:<command> <flag>',
                      'flagdir:<command> <flag>', or xdg:<command> for a file
                      it has no variable or flag for
  home=<paths>        where a file is here: paths a : apart, each starting at
                      /, ~/, or \$NAME; several a , apart are one place, the
                      first whose variable is set. Quote it, or the shell
                      expands it first.
  dialect=<dialect>   how its includes are found and its comments stripped
                      (sh, fish, vim, lua, elisp, nano, tmux, screen,
                      readline, kak, kdl, omp, omp-json, conf); left out, it
                      rides as written
  init=<command>      the tool's shell hook, a command printing a shell's
                      code with {shell} for the shell's name ('zoxide init
                      {shell}'): a target with the tool runs it after the
                      aliases and extensions. A plugin with one needs no file.
  prompt=yes          the init draws the prompt: the plugin joins
                      _HI_PROMPT_TOOL's programs, and hi's prompt stands down
  default=off         off until hi --plugin-on names it

A file whose wire, home, or dialect differs from the rest has a table of its
own under the plugin's, [<group>.<name>."<file>"], written by hand.

  -n, --dry-run    say what would be written, and write nothing

  hi --add-plugin cli task taskrc wire=env:TASKRC home='\$TASKRC : ~/.taskrc'
EOF
    ;;
  remove)
    cat <<EOF
Usage: $usage

Removes the plugin <name>, its table and its files' tables, from
~/.config/say-hi/plugins. A plugin of hi's own has no table there to remove:
\`hi --plugin-off\` switches it off.

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
  -*) _hi_die "unknown option $1 ($usage)" ;;
  *) args+=("$1") ;;
  esac
  shift
done

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
    case "$groups" in *" $group "*) ;; *) groups="$groups$group " ;; esac
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
  [ "${#_HI_PLUGIN_BAD[@]}" -gt 0 ] || return 0
  _hi_section "ignored"
  for line in "${_HI_PLUGIN_BAD[@]}"; do
    # a file:line of the tree's config/ or of the overlay
    name="$_HI_CONFIG_DIR"
    case "$line" in config/*) name="$_HI_ROOT" ;; esac
    row="${line%%|*}"
    _hi_row "$name/${row%%:*} line ${row#*:}" "${line#*|}" warn
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
    printf '#!/bin/sh\n' >"$tmpfile"
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

# _hi_plugin_span <name> - <name>'s table in `_hi_rows` and the tables of its
# files, as the caller's $from and $to (the line after its last): 1 when the
# file has none. The comments and blank lines ahead of the next table are
# that table's.
function _hi_plugin_span() {
  local i t
  from=-1 to="${#_hi_rows[@]}"
  for ((i = 0; i < ${#_hi_rows[@]}; i++)); do
    _hi_toml_table t "${_hi_rows[i]}" || continue
    t="${t//[[:space:]]/}"
    case "${t#*.}" in
    "$1") [ "$t" = "${t#*.}" ] || from="$i" ;;
    "$1".*) ;;
    *)
      [ "$from" -lt 0 ] || {
        to="$i"
        break
      }
      ;;
    esac
  done
  [ "$from" -ge 0 ] || return 1
  while [ "$to" -gt $((from + 1)) ]; do
    case "${_hi_rows[to - 1]}" in '' | '#'*) to=$((to - 1)) ;; *) break ;; esac
  done
}

function _hi_plugins_add() {
  local group name word key files="" tmpdir why="" line said="" from to n
  local -a table=() keys=()
  [ "${#args[@]}" -ge 3 ] || _hi_die "needs a group, a name, and a file or an init=, then any of tool=, wire=, home=, dialect=, prompt=, default= ($me --help)"
  group="${args[0]}" name="${args[1]}"
  for word in "$group" "$name"; do
    _hi_words_ok "$word" 'A-Za-z0-9_' 'A-Za-z0-9_-' && [ "${word% *}" = "$word" ] ||
      _hi_die "not a group or a plugin's name: $word (letters, digits, _ -)"
  done
  for word in "${args[@]:2}"; do
    case "$word" in *['"'\\]*) _hi_die "a value cannot hold a quote or a backslash ($me --help)" ;; esac
    case "$word" in
    tool=* | wire=* | home=* | dialect=* | init=* | prompt=* | default=*) keys+=("$word") ;;
    *) files="$files${files:+ }$word" ;;
    esac
  done
  [ -n "$files" ] || [[ " ${keys[*]-} " == *" init="* ]] || _hi_die "needs a file for $name to carry, or an init= ($me --help)"
  # the tree's own order of keys, whatever order they were typed in
  table=("[$group.$name]")
  for key in init prompt default tool wire home dialect; do
    for word in ${keys[@]+"${keys[@]}"}; do
      [ "${word%%=*}" != "$key" ] || table+=("$key = \"${word#*=}\"")
    done
  done
  [ -z "$files" ] || table+=("files = \"$files\"")
  _hi_rows_read "$plugins"
  if _hi_plugin_span "$name"; then
    if [ "$(printf '%s\n' "${_hi_rows[@]:from:to-from}")" = "$(printf '%s\n' "${table[@]}")" ]; then
      _hi_cecho "$plugins: that plugin is there already - nothing to write" "$GREEN"
      exit 0
    fi
    _hi_toml_table line "${_hi_rows[from]}"
    said=" ~ [$group.$name] (replacing [$line])|$YELLOW"
    _hi_rows=("${_hi_rows[@]:0:from}" "${table[@]}" "${_hi_rows[@]:to}")
  else
    said=" + [$group.$name]|$GREEN"
    from="${#_hi_rows[@]}"
    if [ "$from" -eq 0 ]; then
      _hi_rows=('# a plugin of yours: a [<group>.<name>] table, its files and any of tool, wire, home, dialect' '')
    elif [ -n "${_hi_rows[from - 1]}" ]; then
      _hi_rows+=('')
    fi
    from="${#_hi_rows[@]}"
    _hi_rows+=("${table[@]}")
  fi
  # through the reader a connect uses, over the file as it would be: good
  # when that reader turns nothing of the table down
  tmpdir="$(mktemp -d -t hi.plugins.XXXXXX)"
  printf '%s\n' "${_hi_rows[@]}" >"$tmpdir/plugins"
  why="$(
    _HI_CONFIG_DIR="$tmpdir" _hi_plugins_load
    for line in ${_HI_PLUGIN_BAD[@]+"${_HI_PLUGIN_BAD[@]}"}; do
      n="${line%%|*}"
      [ "${n%%:*}" = plugins ] && [ "${n#*:}" -gt "$from" ] && [ "${n#*:}" -le $((from + ${#table[@]})) ] || continue
      printf '%s' "${line#*|}"
      break
    done
  )"
  command rm -f "$tmpdir/plugins"
  rmdir "$tmpdir"
  [ -z "$why" ] || _hi_die "$why ($me --help)"
  _hi_cecho "${said%|*}" "${said##*|}"
  for line in "${table[@]:1}"; do _hi_cecho "     $line" "${said##*|}"; done
  _hi_rows_write "$plugins"
}

function _hi_plugins_remove() {
  local from to line
  [ "${#args[@]}" -eq 1 ] || _hi_die "needs one plugin's name ($me --help)"
  _hi_rows_read "$plugins"
  if ! _hi_plugin_span "${args[0]}"; then
    while IFS='|' read -r line _; do
      [ "$line" != "${args[0]}" ] ||
        _hi_die "${args[0]} is hi's own, with no table of yours to remove: hi --plugin-off ${args[0]} switches it off"
    done < <(_hi_plugin_rows)
    _hi_cecho "$plugins has no plugin ${args[0]} - nothing to write" "$GREEN"
    exit 0
  fi
  _hi_toml_table line "${_hi_rows[from]}"
  _hi_cecho " - [$line]" "$YELLOW"
  # the comment lines right above it are about it, and go with it; so does
  # the blank line above those where one below, or nothing, follows
  while [ "$from" -gt 0 ]; do
    case "${_hi_rows[from - 1]}" in '#'*) from=$((from - 1)) ;; *) break ;; esac
  done
  if [ "$from" -gt 0 ] && [ -z "${_hi_rows[from - 1]}" ] && { [ "$to" -ge "${#_hi_rows[@]}" ] || [ -z "${_hi_rows[to]}" ]; }; then
    from=$((from - 1))
  fi
  _hi_rows=("${_hi_rows[@]:0:from}" "${_hi_rows[@]:to}")
  dry_run_say "write $plugins without it" && exit 0
  _hi_rows_write "$plugins"
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
