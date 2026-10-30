#!/usr/bin/env bash
# scripts/configure.sh's menu driven through a pty: its layout at 80 and 40
# columns, and the header page.
# A part of configure_test.sh, a suite of its own so the Windows and coverage
# shards split them.
# The preamble's source line is configure_test.sh's - it sources the harness, and
# holds the helpers the parts share (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# SC2015: `A && B || _hi_why` is one assertion, its reporter run when either
# half is false.
# shellcheck disable=SC2329,SC2015
set -euo pipefail

_HI_CONFIGURE_PART=menu
# shellcheck source=./configure_test.sh
source "${BASH_SOURCE[0]%/*}/configure_test.sh"

# The layout, pinned at 80 columns and at 40 the way the header's width is
# ($_HI_TERM_COLS), through every page: no line of the run is wider than the
# terminal, a narrow one cutting help text and summaries rather than wrapping
# them, and the pages draw in the order their letters were typed
function _hi_menu_layout_at() {
  local w="$1" label="layout_$1" line len over=0 titles want
  _HI_TERM_COLS="$w" _hi_cfg_pty "$label" "$_HI_MENU_EVERY_PAGE" '' run_configure "" || return 1
  while IFS= read -r line; do
    case "$line" in *CFGRC=*) continue ;; esac
    # the pty echoes no input, so what follows the ` > ` prompt lands on its
    # line - where a terminal's Enter would have ended it
    line="${line#' > '}"
    _hi_visible_len len "$line"
    ((len > w)) || continue
    _hi_cecho " | $len columns at $w: $line" "$RED"
    over=1
  done < <(_hi_strip_ansi "$(<"$_HI_WORKDIR/$label.cfg.out")" | tr -d '\r')
  titles="$(_hi_cfg_titles "$label")"
  want="$_HI_MENU_EVERY_TITLE"
  # under 60 columns a page's title is its name alone
  ((w >= 60)) || want="${want//hi --configure: /}"
  [ "$titles" = "$want" ] || _hi_because "the pages at $w columns: [$titles]" || return 1
  [ "$over" = 0 ]
}

# The Header cells page's grid: the header items, numbered up to the package
# groups, 4 cells to a line at 80 columns, folding to 2 at 40, every one drawn
function _hi_menu_grid_at() {
  local w="$1" want="$2" label="grid_$1" cells page first
  cells=$(($(_hi_item 'group|core') - $(_hi_item 'word|0')))
  _HI_TERM_COLS="$w" _hi_cfg_pty "$label" 'e\ns\n' '' run_configure "" || return 1
  page="$(_hi_cfg_screen "$label" 1)"
  first="$(printf '%s\n' "$page" | grep -F " $(_hi_item 'word|0')) [x] utc" | grep -o ') \[[x ]\] ' | wc -l)"
  page="$(printf '%s\n' "$page" | grep -o ') \[[x ]\] ' | wc -l)"
  ((first == want)) || _hi_because "the grid's first line at $w holds $first cells" || return 1
  ((page == cells)) || _hi_because "the grid at $w holds $page cells, not $cells"
}

# The menu: the real header boxed above the cells' page, and every command
# re-renders. Toggling the first header item off (utc) writes the default
# order minus that word, quoted - read off header.sh's own
# $_HI_HEADER_ORDER_DEFAULT rather than a second copy of it, so a reorder
# there cannot leave this expectation stale.
function test_menu_header_item_toggle_writes_the_order() {
  _hi_cfg_pty hdr_toggle "e\n$(_hi_item 'word|0')\ns\n" '' config_hub || _hi_why || return 1
  local lines want
  want="$(bash -c 'source "$_HI_HEADER"; printf %s "$_HI_HEADER_ORDER_DEFAULT"')"
  want="${want/utc /}"
  lines="$(_hi_cfg_lines hdr_toggle)"
  _hi_cfg_has hdr_toggle "preview" &&
    [[ "$lines" == *"export _HI_HEADER_ORDER='$want'"* ]] || _hi_why lines want
}

# toggled off and back on, the order is the shipped one again and writes
# nothing - the same rule the typed default follows everywhere else
function test_menu_default_order_writes_nothing() {
  local w got
  w="$(_hi_item 'word|0')"
  _hi_cfg_pty hdr_default "$w\n$w\ns\n" '' config_hub || _hi_why w || return 1
  got="$(_hi_cfg_lines hdr_default | tr -d '[:space:]')"
  [ -z "$got" ] || _hi_why got
}

# `down N` swaps utc with its neighbor
function test_menu_moves_a_header_item() {
  local got
  _hi_cfg_pty hdr_move "down $(_hi_item 'word|0')\ns\n" '' config_hub || _hi_why || return 1
  got="$(_hi_cfg_lines hdr_move)"
  [[ "$got" == *"export _HI_HEADER_ORDER='version utc localtime"* ]] || _hi_why got
}

# the banner always leads: it toggles but never moves
function test_menu_banner_never_moves() {
  local b
  b="$(_hi_item 'row|_HI_HEADER_PROMPTS|0')"
  _hi_cfg_pty hdr_banner "up $b\n$b\ns\n" '' config_hub || _hi_why b || return 1
  local lines
  lines="$(_hi_cfg_lines hdr_banner)"
  _hi_cfg_has hdr_banner "the banner always leads" &&
    [[ "$lines" == *"export _HI_DISABLE_BANNER=1"* && "$lines" != *"_HI_HEADER_ORDER"* ]] || _hi_why lines
}

# up/down off the header items, and at the end the item is already at - two
# refusals, each in words, and the run goes on
function test_menu_refuses_a_move_that_cannot_happen() {
  _hi_cfg_pty hdr_updown "up 99\nup $(_hi_item 'word|0')\ns\n" '' config_hub || _hi_why || return 1
  _hi_cfg_has hdr_updown "up/down take a header item" &&
    _hi_cfg_has hdr_updown "is already at that end" || _hi_why
}

# h, then a name off the roster: said, nothing written, the menu goes on
function test_menu_header_preset_refuses_a_stranger() {
  local got
  _hi_cfg_pty hdr_pstranger 'h\nnope\ns\n' '' config_hub || _hi_why || return 1
  _hi_cfg_has hdr_pstranger "no such header preset: nope" || _hi_why || return 1
  got="$(_hi_cfg_lines hdr_pstranger | tr -d '[:space:]')"
  [ -z "$got" ] || _hi_why got
}

function test_menu_takes_a_width() {
  local got
  _hi_cfg_pty hdr_width "$(_hi_item width)\n120\ns\n" '' config_hub || _hi_why || return 1
  _hi_cfg_has hdr_width "Terminal width for the header/banner (40 or more)?" || _hi_why || return 1
  got="$(_hi_cfg_lines hdr_width)"
  [[ "$got" == *"export _HI_MAX_WIDTH=120"* ]] || _hi_why got
}

function test_menu_takes_hidden_addresses() {
  local got
  _hi_cfg_pty hdr_iphide "$(_hi_item iphide)\nnone\ns\n" "export _HI_HEADER_ORDER='ip utc'" config_hub || _hi_why || return 1
  _hi_cfg_has hdr_iphide "Hide which addresses from the ip cell" || _hi_why || return 1
  got="$(_hi_cfg_lines hdr_iphide)"
  [[ "$got" == *"export _HI_IP_HIDE='none'"* ]] || _hi_why got
}

function test_menu_takes_a_header_preset() {
  local got
  _hi_cfg_pty hdr_preset 'h\nq\ns\n' '' config_hub || _hi_why || return 1
  got="$(_hi_cfg_lines hdr_preset)"
  [[ "$got" == *"export _HI_HEADER_ORDER='utc localtime gitid'"* ]] || _hi_why got
}

# ...by its full name too, which the one-letter shorthand would refuse
function test_menu_takes_a_header_preset_by_name() {
  local got
  _hi_cfg_pty hdr_preset_name 'h\nquiet\ns\n' '' config_hub || _hi_why || return 1
  got="$(_hi_cfg_lines hdr_preset_name)"
  [[ "$got" == *"export _HI_HEADER_ORDER='utc localtime gitid'"* ]] || _hi_why got
}

# the header feature row turns the whole header off, and its page's preview
# says so in words rather than showing an empty box
function test_menu_header_off_previews_as_words() {
  local got
  _hi_cfg_pty hdr_off "i\n$(_hi_item 'row|_HI_FEATURE_PROMPTS|0')\ns\n" '' config_hub || _hi_why || return 1
  _hi_cfg_has hdr_off "header off - nothing prints" || _hi_why || return 1
  got="$(_hi_cfg_lines hdr_off)"
  [[ "$got" == *"export _HI_DISABLE_HEADER=1"* ]] || _hi_why got
}

# an empty $_HI_HEADER_ORDER means the default at runtime, so the last item
# cannot be turned off - the menu says how to get an empty header instead
function test_menu_keeps_the_last_header_item() {
  local got
  _hi_cfg_pty hdr_last "$(_hi_item 'word|0')\ns\n" "export _HI_HEADER_ORDER='gitid'" config_hub || _hi_why || return 1
  _hi_cfg_has hdr_last "keep at least one header item" || _hi_why || return 1
  got="$(_hi_cfg_lines hdr_last)"
  [[ "$got" == *"export _HI_HEADER_ORDER='gitid'"* ]] || _hi_why got
}

# a stored order lists its words first, in its order, then every word it
# leaves out, unchecked
function test_menu_lists_missing_header_items_off() {
  local w
  w="$(_hi_item 'word|0')"
  _hi_cfg_pty hdr_list 'e\ns\n' "export _HI_HEADER_ORDER='check gitid'" config_hub || _hi_why || return 1
  _hi_cfg_has hdr_list "$w) [x] check" &&
    _hi_cfg_has hdr_list "$((w + 1))) [x] gitid" &&
    _hi_cfg_has hdr_list "$((w + 2))) [ ] utc" || _hi_why w
}

# a package group's number flips it: useful, on
function test_menu_flips_a_package_group() {
  local got
  _hi_cfg_pty hdr_groups "$(_hi_item 'group|useful')\ns\n" '' config_hub || _hi_why || return 1
  _hi_cfg_has hdr_groups "package group useful: now on" || _hi_why || return 1
  got="$(_hi_cfg_lines hdr_groups)"
  [[ "$got" == *"export _HI_PACKAGES_GROUPS='core deprecated useful'"* ]] || _hi_why got
}

# ...and the header row, off and back on, previews the whole header both ways
function test_menu_header_row_previews_the_header() {
  local got
  _hi_cfg_pty feat_header "i\n$(_hi_item 'row|_HI_FEATURE_PROMPTS|0')\n$(_hi_item 'row|_HI_FEATURE_PROMPTS|0')\ns\n" '' config_hub || _hi_why || return 1
  { _hi_cfg_has feat_header "header off - nothing prints" && _hi_cfg_has feat_header "Connected"; } || _hi_why || return 1
  got="$(_hi_cfg_lines feat_header | tr -d '[:space:]')"
  [ -z "$got" ] || _hi_why got
}

function test_menu_header_grid_at_80() { _hi_menu_grid_at 80 4; }

function test_menu_header_grid_at_40() { _hi_menu_grid_at 40 2; }

# At 80 columns every page, the main one included, fits a 24-row terminal:
# a draw's lines, then the prompt's own row
function test_menu_pages_fit_24_rows() {
  local k rows
  _HI_TERM_COLS=80 _hi_cfg_pty hub_rows "$_HI_MENU_EVERY_PAGE" '' run_configure "" || _hi_why || return 1
  for k in 1 2 3 4 5 6 7; do
    rows=$(($(_hi_cfg_screen hub_rows "$k" | wc -l) + 1))
    ((rows <= 24)) || _hi_because "draw $k is $rows rows" || return 1
  done
}

function test_menu_layout_at_80() { _hi_menu_layout_at 80; }

function test_menu_layout_at_40() { _hi_menu_layout_at 40; }

# a value away from its default says the default beside it; one at it does not
function test_menu_value_shows_its_default() {
  _HI_TERM_COLS=80 _hi_cfg_pty hub_def 'i\ns\n' "export _HI_MAX_WIDTH=100" run_configure "" || _hi_why || return 1
  _hi_cfg_has hub_def "width                 100 (default 80)" &&
    ! _hi_cfg_has hub_def "(default bridges)" || _hi_why
}

function run_configure_menu_tests() {
  _hi_configure_begin

  _hi_h1 "Testing scripts/configure.sh's menu (pty): its layout and the header page"

  # every case drives its own child, as configure_pty_test.sh's do
  _hi_h2 "Testing: the menu's layout and header page (pty)"
  _hi_par_begin "pty cases"
  _hi_par_check_capable pty "Menu: the cells' grid holds 4 columns at 80" test_menu_header_grid_at_80
  _hi_par_check_capable pty "Menu: the cells' grid folds to 2 at 40" test_menu_header_grid_at_40
  _hi_par_check_capable pty "Menu: every page fits 24 rows at 80 columns" test_menu_pages_fit_24_rows
  _hi_par_check_capable pty "Menu: fits 80 columns, pages in order" test_menu_layout_at_80
  _hi_par_check_capable pty "Menu: fits 40 columns, pages in order" test_menu_layout_at_40
  _hi_par_check_capable pty "Menu: a changed value names its default" test_menu_value_shows_its_default
  _hi_par_check_capable pty "Menu: the header row previews the whole header" test_menu_header_row_previews_the_header
  _hi_par_check_capable pty "Menu: the header switch turns the header off, in words" test_menu_header_off_previews_as_words
  _hi_par_check_capable pty "Menu: a header item toggle writes the order" test_menu_header_item_toggle_writes_the_order
  _hi_par_check_capable pty "Menu: back to the default order writes nothing" test_menu_default_order_writes_nothing
  _hi_par_check_capable pty "Menu: down N moves a header item" test_menu_moves_a_header_item
  _hi_par_check_capable pty "Menu: the banner toggles but never moves" test_menu_banner_never_moves
  _hi_par_check_capable pty "Menu: a move that cannot happen is refused in words" test_menu_refuses_a_move_that_cannot_happen
  _hi_par_check_capable pty "Menu: the last header item cannot be turned off" test_menu_keeps_the_last_header_item
  _hi_par_check_capable pty "Menu: items a stored order leaves out list unchecked" test_menu_lists_missing_header_items_off
  _hi_par_check_capable pty "Menu: h takes a header preset" test_menu_takes_a_header_preset
  _hi_par_check_capable pty "Menu: h takes a header preset by name" test_menu_takes_a_header_preset_by_name
  _hi_par_check_capable pty "Menu: h refuses a stranger" test_menu_header_preset_refuses_a_stranger
  _hi_par_check_capable pty "Menu: the width item takes a width" test_menu_takes_a_width
  _hi_par_check_capable pty "Menu: a package group's number flips it" test_menu_flips_a_package_group
  _hi_par_check_capable pty "Menu: hidden addresses" test_menu_takes_hidden_addresses
  _hi_par_wait

  _hi_suite_end "configure.sh menu (pty)"
}

run_configure_menu_tests
