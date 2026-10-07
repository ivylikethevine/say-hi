#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# The settings wizard's menu: its pages and rows, the hub that reads a key and
# acts on it, the header's item editor, and the package-group and plugin
# flips. Sourced by scripts/configure.sh, whose pending answers
# (setting_value, _hi_pending_set) every row reads and writes; not an entry
# point of its own.

# The menu numbers every setting the wizard asks once, across all its
# sections, and draws one section a page: the main page is a table, a row a
# section saying what it holds, each section page its rows. A number works
# from any page.
# _HI_MENU_ITEMS says what each number is, rebuilt as the list draws:
# row|<table>|<index> a yes/no row, word|<index> a header item, end|<shell> a
# prompt separator, tool|<shell> who draws a prompt, group|<name> a package
# group, plugin|<word> a plugin, or width, iphide,
# truecolor. _HI_MENU_WORD0 is the first header item's number, for up/down.
# _HI_MENU_PLUGINS is _hi_plugin_states' lines as the list last drew them,
# and _HI_MENU_GROUPS their groups in order: g<N> is the page of the Nth.
_HI_MENU_ITEMS=()
_HI_MENU_WORD0=0
_HI_MENU_PLUGINS=()
_HI_MENU_GROUPS=()
# how many checkboxes the grid being drawn holds so far
_HI_MENU_GRID_N=0
# The page drawn: empty for the main page, else a section's key, or g<N> for
# a group of plugins. The sections, in the order they number:
# "<key>|<title>|<its row of the main page's table>|<what that row leads with>",
# a row indented under the section it is a page of.
_HI_MENU_PAGE=""
_HI_MENU_SECTIONS=(
  "i|Header|Header|header, greeting, banner"
  "e|Header cells|  cells|"
  "c|Package check|  package check|"
  "r|Prompt|Prompt|prompt, git, env"
  "g|Plugins|Plugins|"
  "a|Aliases|Aliases|ls/cat and sudo aliases"
  "v|Advanced|Advanced|edges, mux, keep"
)
# While a section builds: whether its rows draw, and what its row of the main
# page's table says - its [x] count, its values.
_HI_MENU_DRAW=0
_HI_MENU_SUM_KEY="" _HI_MENU_SUM_ON=0 _HI_MENU_SUM_N=0 _HI_MENU_SUM_VALS=""
# The main page's table: a key, a name, and a text column, the last what is
# left of the menu's width
_HI_MENU_NW=16 _HI_MENU_TW=50

# What the last command said, printed under the next list rather than as it
# happened, so the redraw does not scroll it away: the colored line, and a
# preview function to box beneath it.
_HI_MENU_NOTE=""
_HI_MENU_NOTE_PREVIEW=""

# _hi_menu_note <message> <color> [preview-fn]
function _hi_menu_note() {
  _HI_MENU_NOTE="$(_hi_cecho "$1" "$2")"
  _HI_MENU_NOTE_PREVIEW="${3:-}"
}

# The width the menu draws to: the terminal's (lib.sh's _hi_term_cols), not
# capped by $_HI_MAX_WIDTH the way the header is, else 80. Read once per draw
# into $_HI_MENU_W.
_HI_MENU_W=80
# _hi_menu_cols <outvar>
function _hi_menu_cols() {
  local _hi_mc
  _hi_term_cols _hi_mc
  printf -v "$1" '%d' "${_hi_mc:-80}"
}

# _hi_menu_say <text> <color> - one line of prose, wrapped at word breaks to
# the menu's width or 80 columns, the narrower, every piece indented one space
function _hi_menu_say() {
  local line w=$((_HI_MENU_W < 80 ? _HI_MENU_W : 80))
  while IFS= read -r line; do
    _hi_cecho " $line" "$2"
  done < <(printf '%s\n' "$1" | fold -s -w $((w - 2)) | sed 's/ *$//')
}

# _hi_menu_num <outvar> - the last item's number as the list prints it,
# right-aligned in two columns and painted, ` 7)` or `12)`
function _hi_menu_num() {
  _hi_pad_to "$1" 2 "${#_HI_MENU_ITEMS[@]}" right
  _hi_paint "$1" "$BRYELLOW" "${!1})"
}

# The list's colors, so a row scans without reading it: the number you type
# $BRYELLOW, a green [x] on and a red [ ] off, a current value $BRPURPLE, the
# help after a label's " - " $BLUE like the intro's, a missing command's note
# and a changed row's "(default ...)" $YELLOW.
# _hi_menu_add <kind> <text> [no_newline] - number the next item and draw it
function _hi_menu_add() {
  local num
  _HI_MENU_ITEMS+=("$1")
  [ "$_HI_MENU_DRAW" = 1 ] || return 0
  _hi_menu_num num
  printf '  %s %s' "$num" "$2"
  [ $# -ge 3 ] || printf '\n'
}

# _hi_menu_check <outvar> <1|0> - a row's checkbox, counted toward its
# section's summary
function _hi_menu_check() {
  _HI_MENU_SUM_N=$((_HI_MENU_SUM_N + 1))
  [ "$2" != 1 ] || _HI_MENU_SUM_ON=$((_HI_MENU_SUM_ON + 1))
  if [ "$2" = 1 ]; then _hi_paint "$1" "$BRGREEN" "[x]"; else _hi_paint "$1" "$RED" "[ ]"; fi
}

# _hi_menu_trow <key> <name> <text> - a row of the main page's table, each
# cell padded by what it prints as; the caller fits the text
function _hi_menu_trow() {
  local k n t
  _hi_pad_to k 3 "$1"
  _hi_pad_to n "$_HI_MENU_NW" "$2"
  _hi_pad_to t "$_HI_MENU_TW" "$3"
  printf ' %s %s %s %s %s %s %s\n' "$_HI_BOX_V" "$k" "$_HI_BOX_V" "$n" "$_HI_BOX_V" "$t" "$_HI_BOX_V"
}

# _hi_menu_section [key] - close the section being built (its row of the
# main page's table) and open the one named <key>; no key closes the last
function _hi_menu_section() {
  local row name lead sum key
  if [ -n "$_HI_MENU_SUM_KEY" ] && [ -z "$_HI_MENU_PAGE" ]; then
    for row in "${_HI_MENU_SECTIONS[@]}"; do
      [ "${row%%|*}" = "$_HI_MENU_SUM_KEY" ] || continue
      lead="${row##*|}" name="${row%|*}"
      name="${name##*|}"
    done
    sum=""
    ((_HI_MENU_SUM_N == 0)) || sum="$_HI_MENU_SUM_ON of $_HI_MENU_SUM_N on"
    [ -z "$_HI_MENU_SUM_VALS" ] || sum="$sum${sum:+, }$_HI_MENU_SUM_VALS"
    _hi_fit sum "${lead:+$lead: }$sum" "$_HI_MENU_TW"
    _hi_paint key "$BRYELLOW" "[$_HI_MENU_SUM_KEY]"
    _hi_menu_trow "$key" "$name" "$sum"
  fi
  _HI_MENU_SUM_KEY="${1:-}" _HI_MENU_SUM_ON=0 _HI_MENU_SUM_N=0 _HI_MENU_SUM_VALS=""
  _HI_MENU_DRAW=0
  [ -n "${1:-}" ] && [ "$1" = "$_HI_MENU_PAGE" ] && _HI_MENU_DRAW=1
  return 0
}

# _hi_feature_index <var> <outvar> - where <var>'s row sits in
# $_HI_FEATURE_PROMPTS; 1 for none
function _hi_feature_index() {
  local _hi_fi
  for _hi_fi in "${!_HI_FEATURE_PROMPTS[@]}"; do
    [ "${_HI_FEATURE_PROMPTS[$_hi_fi]%%|*}" = "$1" ] || continue
    printf -v "$2" '%s' "$_hi_fi"
    return 0
  done
  return 1
}

# _hi_menu_where <key> <var> - one of the two switches for where hi styles a
# shell at all, this machine and the targets: <var>'s row of
# $_HI_FEATURE_PROMPTS, numbered like any other and drawn on the main page
# alone, where <key> flips it too
function _hi_menu_where() {
  local i var off on label state key text
  _hi_feature_index "$2" i || return 0
  IFS='|' read -r var off on _ _ label <<<"${_HI_FEATURE_PROMPTS[$i]}"
  _HI_MENU_ITEMS+=("row|_HI_FEATURE_PROMPTS|$i")
  [ -z "$_HI_MENU_PAGE" ] || return 0
  setting_on "$var" "$_HI_SETTINGS" "$off" "$on" && state=1 || state=0
  if [ "$state" = 1 ]; then _hi_paint state "$BRGREEN" "[x]"; else _hi_paint state "$RED" "[ ]"; fi
  _hi_paint key "$BRYELLOW" "[$1]"
  _hi_fit text "${label#* - }" "$_HI_MENU_TW"
  _hi_menu_trow "$key" "$state ${label%% - *}" "$text"
}

# _hi_menu_sub <key> <name> <text> - a page under the one drawn: its key, its
# name, and what it holds
function _hi_menu_sub() {
  local k n t
  [ "$_HI_MENU_DRAW" = 1 ] || return 0
  _hi_paint k "$BRYELLOW" "[$1]"
  _hi_pad_to n 14 "$2"
  _hi_fit t "$3" $((_HI_MENU_W > 32 ? _HI_MENU_W - 24 : 8))
  _hi_paint t "$BLUE" "$t"
  printf '  %s %s %s\n' "$k" "$n" "$t"
}

# _hi_menu_heading <text> - a line over the rows that follow, on the page
# that draws them
function _hi_menu_heading() {
  [ "$_HI_MENU_DRAW" != 1 ] || _hi_menu_say "$1" "$BLUE"
}

# _hi_menu_sum <text> - a phrase for the section's line on the main page
function _hi_menu_sum() {
  _HI_MENU_SUM_VALS="$_HI_MENU_SUM_VALS${_HI_MENU_SUM_VALS:+, }$1"
}

# _hi_menu_value <kind> <label> <value> <default> [quiet] - an item that asks
# for a value, indented past the [x] the yes/no rows carry, the default beside
# it when the value is not; label and value close up under 60 columns. It is
# part of its section's summary unless <quiet>.
function _hi_menu_value() {
  local _hi_mv_text _hi_mv_def="" _hi_mv_word pad=22 lead="    "
  [ -n "${5:-}" ] || _hi_menu_sum "$2 $3"
  ((_HI_MENU_W < 60)) && pad=$((${#2} + 1)) lead=" "
  [ "$3" = "$4" ] || _hi_paint _hi_mv_def "$YELLOW" " (default $4)"
  _hi_pad_to _hi_mv_word "$pad" "$2"
  printf -v _hi_mv_text '%s%s%b%s%b%s' "$lead" "$_hi_mv_word" "$BRPURPLE" "$3" "$NC" "$_hi_mv_def"
  _hi_menu_add "$1" "$_hi_mv_text"
}

# _hi_menu_row <table> <index> - one yes/no row, checked when on. A row whose
# <needs> command is absent here says so but still toggles - the setting
# applies wherever the command exists. The help after " - " is what gives way
# to a narrow terminal; the name, the note, and "(default ...)" stay.
function _hi_menu_row() {
  local var off on needs alt label state def name help="" note="" dnote="" room
  local -a rows=()
  _hi_prompt_rows "$1" rows
  IFS='|' read -r var off on _ needs label <<<"${rows[$2]}"
  setting_on "$var" "$_HI_SETTINGS" "$off" "$on" && state=1 || state=0
  # a default-on toggle has no on-value; an opt-in has one
  [ -z "$on" ] && def=1 || def=0
  name="${label%% - *}"
  # <needs> may name alternatives, `hx/helix`: any one of them is enough
  if [ -n "$needs" ]; then
    note=" (no ${needs%%/*} here)"
    for alt in ${needs//\// }; do
      ! command -v "$alt" >/dev/null 2>&1 || note=""
    done
  fi
  [ "$state" = "$def" ] || { [ "$def" = 1 ] && dnote=" (default on)" || dnote=" (default off)"; }
  # "  NN) [x] " is ten columns
  room=$((_HI_MENU_W - 11 - ${#name} - ${#note} - ${#dnote}))
  case "$label" in *' - '*)
    if ((room > 8)); then
      _hi_fit help "${label#* - }" $((room - 3))
      _hi_paint help "$BLUE" " - $help"
    fi
    ;;
  esac
  [ -z "$note" ] || _hi_paint note "$YELLOW" "$note"
  [ -z "$dnote" ] || _hi_paint dnote "$YELLOW" "$dnote"
  _hi_menu_check state "$state"
  _hi_menu_add "row|$1|$2" "$state $name$help$note$dnote"
}

# _hi_menu_rows <table> [index...] - those rows of a table, or every row
function _hi_menu_rows() {
  local t="$1" i
  local -a rows=()
  shift
  if [ $# = 0 ]; then
    _hi_prompt_rows "$t" rows
    set -- ${rows[@]+"${!rows[@]}"}
  fi
  for i; do _hi_menu_row "$t" "$i"; done
}

# The list, grouped by what a setting changes, a heading over each part of a
# page. First the two switches for where hi styles a shell at all, rows of
# the main page alone. Header: the switch for the whole of it, the greeting
# and the banner, its width and hidden addresses, and the two pages under it
# - its cells in the order they print, a grid of as many to a line as the
# width holds, four at most, and the package check's groups, a row each.
# Prompt: its switches, then who draws each shell's and what it ends with.
# Plugins: a row a group, and a page a group with a row a plugin. The aliases
# and Advanced follow. Every section numbers whichever page is drawn; only
# the page's own rows print, and the main page draws a row of its table a
# section. The rows keep their tables (and so their item kinds): this is only
# the order they draw in.
function _hi_menu_list() {
  local i state word width groups iphide tc row name shell end def cols var off on tool all g note w same
  local -a rows=() notes=()
  _HI_MENU_ITEMS=()
  _HI_MENU_SUM_KEY=""
  # no wider than the prose over it; the indent, the key, and the table's
  # edges and padding are 14 columns
  _HI_MENU_TW=$(((_HI_MENU_W < 80 ? _HI_MENU_W : 80) - _HI_MENU_NW - 14))
  ((_HI_MENU_TW >= 4)) || _HI_MENU_TW=4
  # " NN) [x] containers " is twenty columns, the last on a line nineteen
  cols=$(((_HI_MENU_W + 1) / 20))
  ((cols > 4)) && cols=4
  ((cols < 1)) && cols=1
  if [ -z "$_HI_MENU_PAGE" ]; then
    printf ' '
    _hi_hbar top 3 "$_HI_MENU_NW" "$_HI_MENU_TW"
  fi
  _hi_menu_where l _HI_DISABLE_LOCAL
  _hi_menu_where t _HI_PLAIN
  _hi_menu_section i
  for row in _HI_FEATURE_PROMPTS:0:header _HI_FEATURE_PROMPTS:1:greeting _HI_HEADER_PROMPTS:0:banner; do
    IFS=: read -r name i word <<<"$row"
    _hi_prompt_rows "$name" rows
    IFS='|' read -r var off on _ <<<"${rows[$i]}"
    setting_on "$var" "$_HI_SETTINGS" "$off" "$on" && state=1 || state=0
    _hi_menu_grid_item "row|$name|$i" "$state" "$word" "$cols"
  done
  _hi_menu_grid_end "$cols"
  setting_value _HI_MAX_WIDTH "$_HI_SETTINGS" width
  setting_value _HI_PACKAGES_GROUPS "$_HI_SETTINGS" groups
  setting_value _HI_IP_HIDE "$_HI_SETTINGS" iphide
  _hi_menu_value width "width" "${width:-80}" 80
  _hi_menu_value iphide "hidden addresses" "${iphide:-172.*}" '172.*' quiet
  _hi_menu_sub e "cells" "which items the header prints, and in what order"
  _hi_menu_sub c "package check" "the groups its check item runs"
  _hi_menu_section e
  _hi_menu_heading "In the order they print - up N or down N moves one"
  _HI_MENU_WORD0=$((${#_HI_MENU_ITEMS[@]} + 1))
  note=""
  for i in "${!_HI_HDR_WORDS[@]}"; do
    _hi_menu_grid_item "word|$i" "${_HI_HDR_ON[$i]}" "${_HI_HDR_WORDS[$i]}" "$cols"
    [ "${_HI_HDR_ON[$i]}" != 1 ] || note="$note${note:+ }${_HI_HDR_WORDS[$i]}"
  done
  _hi_menu_grid_end "$cols"
  _hi_menu_sum "$note"
  # the package check's groups, each a row: its name and what its comment in
  # the packages file says of it
  _hi_menu_section c
  _hi_menu_heading "The groups the header's check item runs - [x] runs"
  groups="${groups:-$_HI_PACKAGES_GROUPS_DEFAULT}"
  [ "$groups" = none ] || _hi_menu_sum "${groups//,/ }"
  _hi_package_groups all
  w=0
  for g in $all; do ((${#g} > w)) && w=${#g}; done
  _hi_read_lines notes < <(_hi_package_group_notes)
  for g in $all; do
    note=""
    for row in ${notes[@]+"${notes[@]}"}; do
      [ "${row%%|*}" != "$g" ] || note="${row#*|}"
    done
    case " ${groups//,/ } " in *" $g "*) state=1 ;; *) state=0 ;; esac
    _hi_menu_check state "$state"
    _hi_pad_to name "$w" "$g"
    _hi_fit note "$note" $((_HI_MENU_W - w - 14 > 8 ? _HI_MENU_W - w - 14 : 8))
    _hi_paint note "$BLUE" "$note"
    _hi_menu_add "group|$g" "$state $name  $note"
  done
  _hi_menu_section r
  _hi_menu_rows _HI_PROMPT_PROMPTS 0
  _hi_menu_rows _HI_FEATURE_PROMPTS 2 3
  setting_value _HI_PROMPT_TOOL "$_HI_SETTINGS" tool
  _hi_menu_heading "Who draws each shell's prompt - auto is the first program a target has, else hi"
  same="" note=""
  for row in "${_HI_SHELL_TABLE[@]}"; do
    name="${row%%|*}"
    _hi_prompt_choice "$name" "$tool" end
    _hi_menu_value "tool|$name" "$name prompt drawn by" "$end" auto quiet
    note="$note${note:+, }$name $end"
    case "$same" in '') same="$end" ;; "$end") ;; *) same=- ;; esac
  done
  [ "$same" = - ] || note="drawn by $same"
  _hi_menu_sum "$note"
  # one separator per shell hi styles (core.sh's _HI_SHELL_TABLE), wired up
  # here or not - a target's login shell may be one this machine lacks; the
  # shipped defaults are a different character per shell
  _hi_menu_heading "What hi's own prompt ends with"
  for row in "${_HI_SHELL_TABLE[@]}"; do
    name="${row%%|*}"
    _hi_shell_var shell "$name"
    _hi_prompt_end_shown "$shell" end
    def="$(_hi_prompt_end_default "$shell")"
    _hi_menu_value "end|$name" "$name prompt ends with" "$end" "${def#\\}" quiet
  done
  # the Plugins rows of the main page's table are _hi_menu_plugins' own
  _hi_menu_section g
  _hi_menu_plugins
  _HI_MENU_SUM_KEY=""
  _hi_menu_section a
  _hi_menu_rows _HI_FEATURE_PROMPTS 4 5
  _hi_menu_section v
  _hi_menu_rows _HI_ADVANCED_PROMPTS
  setting_value _HI_TRUECOLOR "$_HI_SETTINGS" tc
  case "$tc" in 1) tc=on ;; 0) tc=off ;; *) tc=auto ;; esac
  _hi_menu_value truecolor "24-bit color" "$tc" auto
  _hi_menu_section
  if [ -z "$_HI_MENU_PAGE" ]; then
    printf ' '
    _hi_hbar bottom 3 "$_HI_MENU_NW" "$_HI_MENU_TW"
  fi
}

# _hi_plugin_state <outvar> <on> <here> <config> - a plugin's state off its
# _hi_plugin_states flags: off when switched off, absent with its program or
# its config missing here, else rides
function _hi_plugin_state() {
  if [ "$2" != 1 ]; then
    printf -v "$1" off
  elif [ "$3" = 0 ] || [ "$4" = 0 ]; then
    printf -v "$1" absent
  else
    printf -v "$1" rides
  fi
}

# _hi_menu_group_names <outvar> <group> <room> - the group's plugins, a space
# apart, each in its state's color (lib.sh's _hi_plugin_color), as many as
# <room> columns hold and "..." for the rest
function _hi_menu_group_names() {
  local _hi_gn_e _hi_gn_g _hi_gn_n _hi_gn_s _hi_gn_h _hi_gn_c _hi_gn_out="" _hi_gn_used=0 _hi_gn_p
  for _hi_gn_e in "${_HI_MENU_PLUGINS[@]}"; do
    IFS='|' read -r _hi_gn_g _hi_gn_n _hi_gn_s _ _ _hi_gn_h _hi_gn_c _ <<<"$_hi_gn_e"
    [ "$_hi_gn_g" = "$2" ] && [ -n "$_hi_gn_n" ] || continue
    # room kept for the "..." a later name may need
    if ((_hi_gn_used + ${#_hi_gn_n} + 5 > $3)); then
      _hi_gn_out="$_hi_gn_out${_hi_gn_out:+ }..."
      break
    fi
    _hi_plugin_state _hi_gn_p "$_hi_gn_s" "$_hi_gn_h" "$_hi_gn_c"
    _hi_plugin_color _hi_gn_p "$_hi_gn_p"
    _hi_paint _hi_gn_p "$_hi_gn_p" "$_hi_gn_n"
    _hi_gn_out="$_hi_gn_out${_hi_gn_out:+ }$_hi_gn_p"
    _hi_gn_used=$((_hi_gn_used + ${#_hi_gn_n} + 1))
  done
  printf -v "$1" '%s' "$_hi_gn_out"
}

# _hi_menu_mark <outvar> <1|0|-> - found here, not found, or nothing to find
function _hi_menu_mark() {
  case "$2" in
  1) _hi_paint "$1" "$BRGREEN" "$_HI_MARK_OK" ;;
  0) _hi_paint "$1" "$RED" "$_HI_MARK_NO" ;;
  *) printf -v "$1" '%s' "-" ;;
  esac
}

# The plugins, every one of the plugins files. The main page's table has a
# row for the section and one under it a group, the group's plugins named in
# their state's color; the Plugins page the same rows. A group's page, g<N>,
# is a row a plugin: its checkbox - [x] rides to a target, [ ] stays home - its name in
# its state's color, whether its program and a config of its are found on
# this machine, and what a target gets of it. Under 60 columns a plugin's row
# is its checkbox, its name, and the two marks.
function _hi_menu_plugins() {
  local kept="" on="" entry group name s d prog here cfg about gi=0 rides=0 total=0
  local text key state num box cell m1 m2 wn=6 wp=5 wg=0 room
  setting_value _HI_PLUGINS_OFF "$_HI_SETTINGS" kept
  setting_value _HI_PLUGINS_ON "$_HI_SETTINGS" on
  _HI_MENU_PLUGINS=() _HI_MENU_GROUPS=()
  _hi_read_lines _HI_MENU_PLUGINS < <(_hi_plugin_states "$kept" "$on")
  for entry in ${_HI_MENU_PLUGINS[@]+"${_HI_MENU_PLUGINS[@]}"}; do
    IFS='|' read -r group name s d prog here cfg about <<<"$entry"
    if [ -z "$name" ]; then
      _HI_MENU_GROUPS+=("$group")
      ((${#group} > wg)) && wg=${#group}
      continue
    fi
    total=$((total + 1))
    _hi_plugin_state state "$s" "$here" "$cfg"
    [ "$state" != rides ] || rides=$((rides + 1))
  done
  if [ -z "$_HI_MENU_PAGE" ]; then
    _hi_paint key "$BRYELLOW" "[g]"
    _hi_fit text "$rides of $total ride" "$_HI_MENU_TW"
    if ((_HI_MENU_TW >= 46)); then
      _hi_plugin_color m1 rides
      _hi_paint m1 "$m1" "rides"
      _hi_plugin_color m2 off
      _hi_paint m2 "$m2" "stays home"
      _hi_plugin_color cell absent
      _hi_paint cell "$cell" "nothing here"
      text="$text: $m1, $m2, $cell"
    fi
    _hi_menu_trow "$key" "Plugins" "$text"
  fi
  _hi_menu_heading "A group's key opens its plugins"
  for entry in ${_HI_MENU_PLUGINS[@]+"${_HI_MENU_PLUGINS[@]}"}; do
    IFS='|' read -r group name s d prog here cfg about <<<"$entry"
    if [ -z "$name" ]; then
      gi=$((gi + 1))
      _HI_MENU_DRAW=0
      [ "$_HI_MENU_PAGE" != "g$gi" ] || _HI_MENU_DRAW=1
      _hi_paint key "$BRYELLOW" "g$gi"
      if [ -z "$_HI_MENU_PAGE" ]; then
        _hi_menu_group_names text "$group" "$_HI_MENU_TW"
        _hi_fit cell "  $group" "$_HI_MENU_NW"
        _hi_menu_trow "$key" "$cell" "$text"
      elif [ "$_HI_MENU_PAGE" = g ]; then
        _hi_pad_to key 3 "$key"
        _hi_pad_to cell "$wg" "$group"
        _hi_menu_group_names text "$group" $((_HI_MENU_W - wg - 9))
        printf '  %s %s  %s\n' "$key" "$cell" "$text"
      elif [ "$_HI_MENU_DRAW" = 1 ]; then
        # the columns' widths: the plugins' names, and the programs that go
        # by another name than their plugin
        wn=6
        for cell in "${_HI_MENU_PLUGINS[@]}"; do
          IFS='|' read -r m1 m2 _ _ text _ <<<"$cell"
          [ "$m1" = "$group" ] && [ -n "$m2" ] || continue
          ((${#m2} > wn)) && wn=${#m2}
          [ "$text" = "$m2" ] || [ "$text" = - ] || ((${#text} <= wp)) || wp=${#text}
        done
        room=$((_HI_MENU_W - wn - wp - 26))
        _hi_menu_heading "[x] rides to a target, [ ] stays home - program, config: found here or not"
        if ((_HI_MENU_W >= 60)); then
          _hi_pad_to cell "$wn" "plugin"
          _hi_pad_to m1 $((wp + 2)) "program"
          _hi_cecho "          $cell  $m1  config  on a target" "$BLUE"
        fi
      fi
      continue
    fi
    _HI_MENU_ITEMS+=("plugin|$name")
    [ "$_HI_MENU_DRAW" = 1 ] || continue
    _hi_menu_num num
    if [ "$s" = 1 ]; then _hi_paint box "$BRGREEN" "[x]"; else _hi_paint box "$RED" "[ ]"; fi
    _hi_plugin_state state "$s" "$here" "$cfg"
    _hi_plugin_color state "$state"
    _hi_pad_to cell "$wn" "$name"
    _hi_paint cell "$state" "$cell"
    _hi_menu_mark m1 "$here"
    _hi_menu_mark m2 "$cfg"
    if ((_HI_MENU_W < 60)); then
      printf '  %s %s %s %s%s\n' "$num" "$box" "$cell" "$m1" "$m2"
      continue
    fi
    [ "$prog" != "$name" ] && [ "$prog" != - ] || prog=""
    _hi_pad_to prog "$wp" "$prog"
    text=""
    ((room < 8)) || _hi_fit text "$about" "$room"
    _hi_paint text "$BLUE" "$text"
    printf '  %s %s %s  %s %s  %s       %s\n' "$num" "$box" "$cell" "$m1" "$prog" "$m2" "$text"
  done
}

# _hi_menu_grid_item <kind> <1|0> <name> <cols> - one checkbox in a grid of
# the Header page, <cols> to a line; _hi_menu_grid_end closes the grid
function _hi_menu_grid_item() {
  local _hi_gi_state _hi_gi_word _hi_gi_num
  _hi_menu_check _hi_gi_state "$2"
  _HI_MENU_ITEMS+=("$1")
  _HI_MENU_GRID_N=$((_HI_MENU_GRID_N + 1))
  [ "$_HI_MENU_DRAW" = 1 ] || return 0
  _hi_pad_to _hi_gi_word 10 "$3"
  (($4 > 1)) || _hi_gi_word="$3"
  _hi_menu_num _hi_gi_num
  printf ' %s %s %s' "$_hi_gi_num" "$_hi_gi_state" "$_hi_gi_word"
  if [ $((_HI_MENU_GRID_N % $4)) = 0 ]; then printf '\n'; else printf ' '; fi
}

# _hi_menu_grid_end <cols> - end a grid's last line where it stopped short
function _hi_menu_grid_end() {
  [ "$_HI_MENU_DRAW" != 1 ] || [ $((_HI_MENU_GRID_N % $1)) = 0 ] || printf '\n'
  _HI_MENU_GRID_N=0
}

# _hi_menu_pick <item> - act on an item of $_HI_MENU_ITEMS: flip a yes/no
# row, a header item, a package group, or a plugin, or ask for a value
function _hi_menu_pick() {
  local kind a b var off on preview label state
  local -a rows=()
  IFS='|' read -r kind a b <<<"$1"
  case "$kind" in
  row)
    _hi_prompt_rows "$a" rows
    IFS='|' read -r var off on preview _ label <<<"${rows[$b]}"
    _hi_setting_flip "$var" "$off" "$on" state
    # not boxed again where the page's own preview already shows it, and
    # never under the main page's table
    case "$_HI_MENU_PAGE:$preview" in
    a:_hi_tool_alias_preview | [rv]:_hi_prompt_preview | [rv]:_hi_git_status_preview | :*) preview="" ;;
    esac
    _hi_menu_note " ${label%% - *}: now $state" "$GREEN" "$preview"
    ;;
  word)
    # an empty $_HI_HEADER_ORDER means the default order at runtime, not
    # none, so the last item stays on
    if [ "${_HI_HDR_ON[$a]}" = 1 ] && [ "$(_hi_header_edit_count_on)" -le 1 ]; then
      _hi_menu_note " keep at least one header item - the Header page's header switch turns it all off" "$YELLOW"
    else
      [ "${_HI_HDR_ON[$a]}" = 1 ] && _HI_HDR_ON[a]=0 || _HI_HDR_ON[a]=1
      _hi_header_edit_commit
    fi
    ;;
  width) config_max_width ;;
  group) _hi_group_flip "$a" ;;
  plugin) _hi_plugin_flip "$a" ;;
  iphide) config_ip_hide ;;
  end) config_prompt_end "$a" ;;
  tool) config_prompt_tool "$a" ;;
  truecolor) config_truecolor ;;
  esac
}

# The menu: the page's preview, where it has one, the list, save, or quit. A
# command redraws both with whatever it changed; a reply that is not one only says so, under the list
# it was typed against. EOF saves - the same "no answer keeps what you have
# and the run completes" that every question here has always meant. The
# third junk answer in a row ends the run too, but as a quit: three words
# that are not menu items are not an instruction to write the file. Enter
# alone redraws.
_HI_CONFIGURE_QUIT=""
function config_hub() {
  local reply cmd arg idx last rejects=0 max_rejects=3 draw=1 p h s q b="" back title row
  _hi_probe_once
  _hi_header_edit_load
  _HI_MENU_PAGE=""
  while :; do
    if [ -n "$draw" ]; then
      _hi_menu_cols _HI_MENU_W
      title="hi --configure"
      for row in "${_HI_MENU_SECTIONS[@]}"; do
        [ "${row%%|*}" = "$_HI_MENU_PAGE" ] || continue
        title="${row#*|}"
        title="${title%%|*}"
      done
      case "$_HI_MENU_PAGE" in g?*) title="Plugins: ${_HI_MENU_GROUPS[${_HI_MENU_PAGE#g} - 1]}" ;; esac
      # under 60 columns a page's title is its name alone
      [ -z "$_HI_MENU_PAGE" ] || ((_HI_MENU_W < 60)) || title="hi --configure: $title"
      _hi_h2 "$title"
      # the keys first, so they are read before the list; short under 60.
      # Each works from any page: a page names the ones that are its own
      _hi_hotkey preset p p
      if ((_HI_MENU_W < 60)); then
        _hi_hotkey header h h
        _hi_hotkey save s s
        _hi_hotkey quit q q
        back=b
      else
        _hi_hotkey "header preset" h h
        _hi_hotkey "save and exit" s s
        _hi_hotkey "quit without writing" q q
        back=back
      fi
      b=""
      case "$_HI_MENU_PAGE" in
      '') ;;
      e) p="" ;;
      *) p="" h="" ;;
      esac
      [ -z "$_HI_MENU_PAGE" ] || _hi_hotkey "$back" b b
      printf ' %s%s%s%s%s%s%s  %s\n' "$b" "${b:+  }" "$p" "${p:+  }" "$h" "${h:+  }" "$s" "$q"
      # the picture is of what the page's settings change, or there is none
      case "$_HI_MENU_PAGE" in
      i | e) show_preview _hi_header_preview ;;
      c) show_preview _hi_check_preview ;;
      r) show_preview _hi_prompt_sample_preview ;;
      a) show_preview _hi_aliases_preview ;;
      esac
      _hi_menu_list
      if [ -n "$_HI_MENU_NOTE" ]; then
        printf '%s\n' "$_HI_MENU_NOTE"
        [ -z "$_HI_MENU_NOTE_PREVIEW" ] || show_preview "$_HI_MENU_NOTE_PREVIEW"
      fi
      _HI_MENU_NOTE="" _HI_MENU_NOTE_PREVIEW=""
    fi
    draw=1
    menu_read " > " reply || return 0
    cmd="${reply%% *}" arg=""
    [ "$cmd" != "$reply" ] && arg="${reply#* }"
    last=$((_HI_MENU_WORD0 + ${#_HI_HDR_WORDS[@]} - 1))
    case "$cmd" in
    '') ;;
    p | preset) config_preset ;;
    h | header) config_header_preset ;;
    up | u | down | d)
      if _hi_is_number "$arg" && [ "$arg" -ge "$_HI_MENU_WORD0" ] && [ "$arg" -le "$last" ]; then
        idx=$((arg - _HI_MENU_WORD0))
        case "$cmd" in u*) _hi_header_edit_move "$idx" -1 ;; *) _hi_header_edit_move "$idx" 1 ;; esac
      else
        _hi_menu_note " up/down take a header item, $_HI_MENU_WORD0 to $last - the banner always leads" "$YELLOW"
      fi
      ;;
    s | save) return 0 ;;
    q | quit)
      _HI_CONFIGURE_QUIT=1
      return 0
      ;;
    b | back) _HI_MENU_PAGE="" ;;
    i | e | c | r | g | a | v) _HI_MENU_PAGE="$cmd" ;;
    l | t)
      row=_HI_DISABLE_LOCAL
      [ "$cmd" = l ] || row=_HI_PLAIN
      ! _hi_feature_index "$row" idx || _hi_menu_pick "row|_HI_FEATURE_PROMPTS|$idx"
      ;;
    *)
      if _hi_is_number "$cmd" && [ "$cmd" -ge 1 ] && [ "$cmd" -le "${#_HI_MENU_ITEMS[@]}" ]; then
        _hi_menu_pick "${_HI_MENU_ITEMS[cmd - 1]}"
      elif [[ "$cmd" =~ ^g[1-9][0-9]?$ ]] && [ "${cmd#g}" -le "${#_HI_MENU_GROUPS[@]}" ]; then
        _HI_MENU_PAGE="$cmd"
      else
        draw=""
        _hi_menu_reject rejects "$max_rejects" \
          "type an item number (1-${#_HI_MENU_ITEMS[@]}), a page's key, up N / down N, or [p] [h] [s] [q]" && continue
        _hi_cecho " not a menu item three times - leaving $_HI_SETTINGS as it was" "$YELLOW"
        _HI_CONFIGURE_QUIT=1
        return 0
      fi
      ;;
    esac
    # shellcheck disable=SC2034 # read by _hi_menu_reject's ${!1}, not by name
    rejects=0
  done
}

# <name>|<one-line description>|<words>: a starting point for the header
# items. Empty words mean the shipped order - the same spelling
# $_HI_HEADER_ORDER itself uses for "the default" - rather than a second copy
# of header.sh's word list.
_HI_HEADER_PRESETS=(
  "full|every item, in the shipped order|"
  "compact|the clocks, the version, your git identity, the backend counts, and the package check|utc version localtime gitid containers jobs pods check"
  "quiet|just the clocks and your git identity|utc localtime gitid"
)

# The menu's working copy of $_HI_HEADER_ORDER: every word of the
# vocabulary exactly once, in display order, with a parallel on/off flag.
# _hi_header_edit_load seeds it from this run's value - the words it names
# first, in its order, then every word it leaves out, off, in the shipped
# order and then header/'s - and _hi_header_edit_commit writes the on words back to pending
# (empty when they are the shipped order, so nothing is written for it).
_HI_HDR_WORDS=()
_HI_HDR_ON=()

function _hi_header_edit_load() {
  local current word vocab seen=" "
  _hi_load_preview_sources
  _hi_header_vocab vocab
  setting_value _HI_HEADER_ORDER "$_HI_SETTINGS" current
  [ -n "$current" ] || current="$_HI_HEADER_ORDER_DEFAULT"
  _HI_HDR_WORDS=()
  _HI_HDR_ON=()
  # shellcheck disable=SC2086 # the split is the point: one word per feature
  for word in $current; do
    _hi_is_header_word "$word" || continue
    case "$seen" in *" $word "*) continue ;; esac
    seen="$seen$word "
    _HI_HDR_WORDS+=("$word")
    _HI_HDR_ON+=(1)
  done
  # shellcheck disable=SC2086 # the split is the point: one word per feature
  for word in $vocab; do
    case "$seen" in *" $word "*) continue ;; esac
    seen="$seen$word "
    _HI_HDR_WORDS+=("$word")
    _HI_HDR_ON+=(0)
  done
}

function _hi_header_edit_commit() {
  local i on=""
  for i in "${!_HI_HDR_WORDS[@]}"; do
    [ "${_HI_HDR_ON[$i]}" = 1 ] && on="$on${_HI_HDR_WORDS[$i]} "
  done
  on="${on% }"
  [ "$on" = "$_HI_HEADER_ORDER_DEFAULT" ] && on=""
  _hi_pending_set _HI_HEADER_ORDER "$on"
}

# how many words are on - the menu refuses to turn the last one off, since
# an empty $_HI_HEADER_ORDER means the default order at runtime, not none
function _hi_header_edit_count_on() {
  local i n=0
  for i in "${!_HI_HDR_ON[@]}"; do [ "${_HI_HDR_ON[$i]}" = 1 ] && n=$((n + 1)); done
  printf '%d' "$n"
}

# _hi_header_edit_preset <name> - the header items from a header preset:
# its words first and on, in its order, everything else off after
function _hi_header_edit_preset() {
  local row
  row="$(preset_row "$1" _HI_HEADER_PRESETS)" || return 1
  _hi_pending_set _HI_HEADER_ORDER "${row##*|}"
  _hi_header_edit_load
  _hi_header_edit_commit
  _hi_menu_note " header: the '$1' preset" "$GREEN"
}

# _hi_header_edit_move <index> <-1|+1> - swap a word with its neighbor
function _hi_header_edit_move() {
  local i="$1" j=$(($1 + $2)) w o
  if ((j < 0 || j >= ${#_HI_HDR_WORDS[@]})); then
    _hi_menu_note " ${_HI_HDR_WORDS[$i]} is already at that end" "$YELLOW"
    return 0
  fi
  w="${_HI_HDR_WORDS[$i]}" o="${_HI_HDR_ON[$i]}"
  _HI_HDR_WORDS[i]="${_HI_HDR_WORDS[j]}" _HI_HDR_ON[i]="${_HI_HDR_ON[j]}"
  _HI_HDR_WORDS[j]="$w" _HI_HDR_ON[j]="$o"
  _hi_header_edit_commit
}

# the menu's [h]eader preset pick: one shot, like config_preset
function config_header_preset() {
  local reply="" short=""
  _hi_preset_list _HI_HEADER_PRESETS 10
  menu_read " Header preset? (the bracketed letter or the name; Enter keeps the list as it is) [] " reply || return 0
  [ -n "$reply" ] || return 0
  # an exact name first, then an unambiguous first letter - config_preset's
  # own rule, through the same two helpers rather than a third copy of it
  if preset_row "$reply" _HI_HEADER_PRESETS >/dev/null; then
    short="$reply"
  else
    short="$(preset_shorthand "$reply" _HI_HEADER_PRESETS)" || short=""
  fi
  [ -n "$short" ] && _hi_header_edit_preset "$short" && return 0
  _hi_menu_note " no such header preset: $reply" "$YELLOW"
  return 0
}

# _hi_group_flip <group> - one package group of the check, on or off, in this
# run's $_HI_PACKAGES_GROUPS. The shipped set, in any order, clears the
# override rather than restating it - config_max_width does the same with
# 80 - and no group at all is `none`.
function _hi_group_flip() {
  local cur="" on w next="" said="on"
  # the default below is header.sh's
  _hi_load_preview_sources
  setting_value _HI_PACKAGES_GROUPS "$_HI_SETTINGS" cur
  on=" ${cur:-$_HI_PACKAGES_GROUPS_DEFAULT} " on="${on//,/ }"
  [ "$on" != " none " ] || on=" "
  case "$on" in
  *" $1 "*) on="${on/" $1 "/ }" said="off" ;;
  *) on="$on$1 " ;;
  esac
  # shellcheck disable=SC2086 # a space-separated word list
  for w in $on; do next="$next${next:+ }$w"; done
  # shellcheck disable=SC2086 # both are space-separated word lists
  if [ "$(printf '%s\n' $next | LC_ALL=C sort)" = "$(printf '%s\n' $_HI_PACKAGES_GROUPS_DEFAULT | LC_ALL=C sort)" ]; then
    next=""
  elif [ -z "$next" ]; then
    next=none
  fi
  _hi_pending_set _HI_PACKAGES_GROUPS "$next"
  _hi_menu_note " package group $1: now $said" "$GREEN"
}

# _hi_plugin_notes - "<plugin>|<note>" for each plugin of the plugins files
# with a comment right above its table: that comment's first sentence
function _hi_plugin_notes() {
  local f
  for f in "$_HI_ROOT/config/plugins" "${_HI_CONFIG_DIR:-}/plugins"; do
    [ ! -f "$f" ] || awk '
      /^[ \t]*#/ { c = $0; sub(/^[ \t]*#[ \t]*/, "", c); com = com == "" ? c : com " " c; next }
      /^[ \t]*\[[^].]+\.[^].]+\]/ && com != "" {
        t = $0; sub(/^[ \t]*\[[^].]+\./, "", t); sub(/\].*/, "", t); gsub(/[ \t]/, "", t)
        sub(/\. .*/, "", com); sub(/\.$/, "", com); gsub(/\|/, "/", com)
        print t "|" com
      }
      { com = "" }
    ' "$f"
  done
}

# _hi_plugin_states <kept home> <switched on> - every plugin of the plugins
# files under those two lists, a line for its group, `<group>|`, and under it
# one a plugin: `<group>|<plugin>|<on>|<off by default>|<program>|<here>|
# <config>|<about>`. <on> is 1 for one a target is sent; <off by default> is
# 1 for a plugin $_HI_PLUGINS_ON has to name. <program> is what reads the plugin's config, the first of its commands
# found here, or - with none to look for, and <here> whether this machine has
# it; <config> is whether a file of the plugin's is found here, - for a
# plugin of no files; <about> is _hi_plugin_notes' line, else what its hook
# or its wire does. hi.sh is sourced in the one place.
function _hi_plugin_states() {
  (
    # shellcheck source=/dev/null # hi.sh, whose functions alone are wanted
    source "$_HI_LAUNCHER" >/dev/null 2>&1
    local name group last="" seen=" " nl=$'\n' i r p m on d tool wire hook prog here cfg about prompts notes
    local -a members=() buf=() plugs=() _hi_paths=()
    _HI_PLUGINS_OFF="$1" _HI_PLUGINS_ON="${2:-}"
    _hi_plugins_load
    for r in ${_HI_PLUGIN_ROWS[@]+"${_HI_PLUGIN_ROWS[@]}"}; do
      _hi_row_col "$r" plugin p
      plugs+=("$p")
    done
    # the prompt programs this machine has, whatever is switched off
    prompts=" $(unset _HI_PROMPT_TOOL _HI_PROMPT_LIST_KEY && _HI_PLUGINS_OFF='' _hi_prompt_list) "
    notes="$nl$(_hi_plugin_notes)"
    # a group's line, then its plugins'
    function _hi_ps_flush() {
      [ -n "$last" ] || return 0
      printf '%s|\n' "$last"
      printf '%s\n' "${buf[@]}"
    }
    while IFS='|' read -r name group _; do
      case "$seen" in *" $group|$name "*) continue ;; esac
      seen="$seen$group|$name "
      if [ "$group" != "$last" ]; then
        _hi_ps_flush
        last="$group" buf=()
      fi
      members=() tool="" wire="" hook=""
      for i in ${plugs[@]+"${!plugs[@]}"}; do
        [ "${plugs[i]}" = "$name" ] || continue
        r="${_HI_PLUGIN_ROWS[i]}"
        members+=("${r%%|*}")
        [ -n "$tool" ] || {
          _hi_row_col "$r" tool tool
          _hi_row_col "$r" wire wire
        }
      done
      for r in ${_HI_PLUGIN_HOOKS[@]+"${_HI_PLUGIN_HOOKS[@]}"}; do
        _hi_hook_col "$r" name p
        [ "$p" != "$name" ] || hook="$r"
      done
      on=1 d=0
      ! _hi_plugin_switched_off "$name" || on=0
      case "$_HI_PLUGIN_DEFAULT_OFF" in *" $name "*) d=1 ;; esac
      # a hook's tool, where it has no command, is its init's
      if [ -n "$hook" ]; then
        _hi_hook_col "$hook" tool tool
        [ "$tool" != - ] || {
          _hi_hook_col "$hook" init tool
          tool="${tool%% *}"
        }
      fi
      prog=- here=-
      if [ -n "$tool" ] && [ "$tool" != - ]; then
        prog="${tool%% *}" here=0
        for p in $tool; do
          command -v "$p" >/dev/null 2>&1 || continue
          prog="$p" here=1
          break
        done
      elif _hi_prompt_row "$name" >/dev/null; then
        prog="$name" here=0
        case "$prompts" in *" $name "*) here=1 ;; esac
      fi
      cfg=-
      ((${#members[@]} == 0)) || cfg=0
      for m in ${members[@]+"${members[@]}"}; do
        _hi_overlay_row "$m" r || continue
        _hi_overlay_places "$m" "$r"
        for p in "$_HI_CONFIG_DIR/$m" ${_hi_paths[@]+"${_hi_paths[@]}"}; do
          [ -f "$p" ] || { [ -z "${m##*/}" ] && [ -d "$p" ]; } || continue
          cfg=1
          break 2
        done
      done
      about=""
      case "$notes" in
      *"$nl$name|"*)
        about="${notes##*"$nl$name|"}"
        about="${about%%"$nl"*}"
        ;;
      esac
      if [ -z "$about" ] && [ -n "$hook" ]; then
        _hi_hook_col "$hook" init about
        about="runs \`$about\` in a target's shell"
      elif [ -z "$about" ]; then
        case "$wire" in
        env:* | envdir:*)
          about="${wire#*:}"
          about="points \$${about%%[ ;]*} at your config"
          ;;
        flag:* | flagdir:* | xdg:*) about="aliases $name to read your config" ;;
        *) about="your ${members[0]:-$name} rides" ;;
        esac
      fi
      buf+=("$group|$name|$on|$d|$prog|$here|$cfg|$about")
    done < <(_hi_plugin_rows | sort -s -t'|' -k2,2)
    _hi_ps_flush
  )
}

# _hi_plugin_flip <plugin> - a plugin of the Plugins pages, sent or kept home,
# in this run's $_HI_PLUGINS_OFF and $_HI_PLUGINS_ON: the lists `hi
# --plugin-off` and `--plugin-on` keep too (GLOSSARY: HI.64). One that is off
# by default moves through the second, as there.
function _hi_plugin_flip() {
  local kept="" on="" w entry n s d state=1 dflt="" said="stays home" next=""
  setting_value _HI_PLUGINS_OFF "$_HI_SETTINGS" kept
  setting_value _HI_PLUGINS_ON "$_HI_SETTINGS" on
  for entry in ${_HI_MENU_PLUGINS[@]+"${_HI_MENU_PLUGINS[@]}"}; do
    IFS='|' read -r _ n s d _ <<<"$entry"
    [ "$n" = "$1" ] || continue
    state="$s" dflt="$d"
    break
  done
  kept=" ${kept//,/ } " on=" ${on//,/ } "
  if [ "$state" != 1 ]; then
    said="is sent"
    kept="${kept/" $1 "/ }"
    [ "$dflt" != 1 ] || case "$on" in *" $1 "*) ;; *) on="$on$1 " ;; esac
  elif [ "$dflt" = 1 ]; then
    on="${on/" $1 "/ }"
  else
    kept="$kept$1 "
  fi
  for w in $kept; do next="$next${next:+ }$w"; done
  _hi_pending_set _HI_PLUGINS_OFF "$next"
  if [ "$dflt" = 1 ]; then
    next=""
    for w in $on; do next="$next${next:+ }$w"; done
    _hi_pending_set _HI_PLUGINS_ON "$next"
  fi
  _hi_menu_note " $1: $said" "$GREEN"
}
