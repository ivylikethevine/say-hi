#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# scripts/configure.sh's interactive arms and its menu, each driven through a
# pty.
# A part of configure_test.sh, a suite of its own so the Windows shards split them.
# The preamble's source line is configure_test.sh's - it sources the harness, and
# holds the helpers the parts share (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# SC2015: `A && B || _hi_why` is one assertion, its reporter run when either
# half is false.
# shellcheck disable=SC2329,SC2015
set -euo pipefail

_HI_CONFIGURE_PART=pty
# shellcheck source=./configure_test.sh
source "${BASH_SOURCE[0]%/*}/configure_test.sh"

# _hi_pty_run <child-script> <suffix> <label> <input> <line> [args...] - the
# pty rig _hi_cfg_pty runs: a scratch settings.sh, the
# input typed at a forced pty, the transcript captured to
# $_HI_WORKDIR/<label>.<suffix>.out, killed once it has written nothing for
# the deadline rather than hung forever.
function _hi_pty_run() {
  local child="$1" suffix="$2" label="$3" input="$4" line="${5:-}"
  local dir="$_HI_WORKDIR/$label" out="$_HI_WORKDIR/$label.$suffix.out"
  shift 5
  mkdir -p "$dir/common" "$dir/config" "$dir/overlay"
  printf '#!/bin/sh\n%s\n' "$line" >"$dir/overlay/settings.sh"
  : >"$out"
  rm -f "$dir/verdict"
  printf '%b' "$input" |
    "${_HI_PTY_FORCED[@]}" bash -c "$child" bash "$dir" "$@" >"$out" 2>&1 &
  _hi_wait_quiet "$!" "${_HI_CASE_TIMEOUT:-60}" "$out" "$label"
  [ "$_HI_WAIT_EXIT" != 124 ]
}

# _hi_pty_field <label> <suffix> <tag> [capture] - the field after <tag> on
# a pty transcript's tail line, CR-normalised first (a pty writes CR-LF) -
# everything to the end of the line by default, or just what <capture>
# matches (a sed bracket expression body) when the tag's value can have
# trailing text of its own. The one shape behind _hi_cfg_rc and
# _hi_cfg_lines. The child also writes that line to
# <label>/verdict, which is read first: a BSD pty can drop the last output of
# a child that exits at once, and the transcript is only the fallback.
function _hi_pty_field() {
  local src="$_HI_WORKDIR/$1/verdict"
  [ -s "$src" ] || src="$_HI_WORKDIR/$1.$2.out"
  tr '\r' '\n' <"$src" | sed -n "s/.*$3\\(${4:-.*}\\).*/\\1/p" | head -1
}

# _hi_cfg_pty <label> <input> <settings-line> <fn> [arg...] - one configure
# function under a pty with <input> (printf %b) on its stdin. Transcript
# lands in $_HI_WORKDIR/<label>.cfg.out; non-zero when the child had to be
# killed at the deadline.
function _hi_cfg_pty() {
  local label="$1" input="$2" line="$3"
  shift 3
  _hi_pty_run "$_HI_CFG_CHILD" cfg "$label" "$input" "$line" "$@"
}

# the readers: the transcript's visible text for substrings (fixed strings
# only - a pty writes CR-LF, so nothing here anchors a line; the menu paints
# inside a row, so its escapes come out first), the tail line's fields
# through the same CR normalisation the groups loop's readers use
function _hi_cfg_has() { _hi_strip_ansi "$(<"$_HI_WORKDIR/$1.cfg.out")" | grep -qF "$2"; }

function _hi_cfg_rc() { _hi_pty_field "$1" cfg 'CFGRC=' '[0-9]*'; }

function _hi_cfg_lines() { _hi_pty_field "$1" cfg 'CFGLINES='; }

# _hi_cfg_screen <label> <n> - the menu's <n>th draw, 0 the first: the pty
# echoes no input, so each ` > ` prompt shares its line with the next draw's
# title, and a draw runs from one prompt line to the line before the next
function _hi_cfg_screen() {
  _hi_strip_ansi "$(<"$_HI_WORKDIR/$1.cfg.out")" | tr -d '\r' |
    awk -v n="$2" 'index($0, " > ") == 1 { s++ } s == n'
}

function _hi_cfg_screen_has() {
  _hi_cfg_screen "$1" "$2" | grep -qF -- "$3" || _hi_because "draw $2 of $1 has no \"$3\""
}

# _hi_cfg_titles <label> - every draw's title, in order, comma-joined
function _hi_cfg_titles() {
  _hi_strip_ansi "$(<"$_HI_WORKDIR/$1.cfg.out")" | tr -d '\r' |
    sed -E -n 's/.*-  (hi --configure(: [A-Za-z: ]+)?|Header( cells)?|Package check|Prompt|Plugins(: [a-z]+)?|Aliases|Advanced)  -.*/\1/p' |
    paste -sd, -
}

# every page's key in order, g1 the first group of plugins (cli) standing
# for the groups', then b: the eight pages and the main page again, each
# drawn once
_HI_MENU_EVERY_PAGE='i\ne\nc\nr\ng\ng1\na\nv\nb\ns\n'

function test_ask_value_takes_a_typed_number() {
  _hi_cfg_pty width_typed '120\n' '' config_max_width || _hi_why || return 1
  [ "$(_hi_cfg_lines width_typed)" = "export _HI_MAX_WIDTH=120" ] || _hi_why
}

# a rejected answer says why and keeps the current value rather than dropping
# it - the message names the value kept, so both halves are one substring
function test_ask_value_rejects_junk_and_keeps_current() {
  _hi_cfg_pty width_junk 'abc\n' 'export _HI_MAX_WIDTH=100' config_max_width || _hi_why || return 1
  _hi_cfg_has width_junk "a number, 40 or more, leaving it at 100" &&
    [ "$(_hi_cfg_lines width_junk)" = "export _HI_MAX_WIDTH=100" ] || _hi_why
}

# typing the shipped default is how an override is cleared interactively
function test_ask_value_typed_default_clears_the_override() {
  _hi_cfg_pty width_default '80\n' 'export _HI_MAX_WIDTH=100' config_max_width || _hi_why || return 1
  [ -z "$(_hi_cfg_lines width_default | tr -d '[:space:]')" ] || _hi_why
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
  local w
  w="$(_hi_item 'word|0')"
  _hi_cfg_pty hdr_default "$w\n$w\ns\n" '' config_hub || _hi_why w || return 1
  [ -z "$(_hi_cfg_lines hdr_default | tr -d '[:space:]')" ] || _hi_why
}

# `down N` swaps utc with its neighbor
function test_menu_moves_a_header_item() {
  _hi_cfg_pty hdr_move "down $(_hi_item 'word|0')\ns\n" '' config_hub || _hi_why || return 1
  [[ "$(_hi_cfg_lines hdr_move)" == *"export _HI_HEADER_ORDER='version utc localtime"* ]] || _hi_why
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
  _hi_cfg_pty hdr_pstranger 'h\nnope\ns\n' '' config_hub || _hi_why || return 1
  _hi_cfg_has hdr_pstranger "no such header preset: nope" &&
    [ -z "$(_hi_cfg_lines hdr_pstranger | tr -d '[:space:]')" ] || _hi_why
}

function test_menu_takes_a_width() {
  _hi_cfg_pty hdr_width "$(_hi_item width)\n120\ns\n" '' config_hub || _hi_why || return 1
  _hi_cfg_has hdr_width "Terminal width for the header/banner (40 or more)?" &&
    [[ "$(_hi_cfg_lines hdr_width)" == *"export _HI_MAX_WIDTH=120"* ]] || _hi_why
}

function test_menu_takes_hidden_addresses() {
  _hi_cfg_pty hdr_iphide "$(_hi_item iphide)\nnone\ns\n" "export _HI_HEADER_ORDER='ip utc'" config_hub || _hi_why || return 1
  _hi_cfg_has hdr_iphide "Hide which addresses from the ip cell" &&
    [[ "$(_hi_cfg_lines hdr_iphide)" == *"export _HI_IP_HIDE='none'"* ]] || _hi_why
}

# a separator with a quote in it is refused rather than written into
# settings.sh
function test_menu_refuses_a_quoted_separator() {
  _hi_cfg_pty pe_quote "$(_hi_item 'end|bash')\n'\ns\n" '' config_hub || _hi_why || return 1
  _hi_cfg_has pe_quote "a single quote can't be written to settings.sh" &&
    [[ "$(_hi_cfg_lines pe_quote)" != *"_HI_PROMPT_END_"* ]] || _hi_why
}

# the truecolor question maps its words both ways: `off` is stored as 0, and
# nothing writes an $_HI_ASCII
function test_truecolor_maps_its_words() {
  _hi_cfg_pty adv_tc 'off\n' '' config_truecolor || _hi_why || return 1
  local lines
  lines="$(_hi_cfg_lines adv_tc)"
  [[ "$lines" == *"export _HI_TRUECOLOR=0"* && "$lines" != *"_HI_ASCII"* ]] || _hi_why lines
}

function test_menu_takes_a_header_preset() {
  _hi_cfg_pty hdr_preset 'h\nq\ns\n' '' config_hub || _hi_why || return 1
  [[ "$(_hi_cfg_lines hdr_preset)" == *"export _HI_HEADER_ORDER='utc localtime gitid'"* ]] || _hi_why
}

# ...by its full name too, which the one-letter shorthand would refuse
function test_menu_takes_a_header_preset_by_name() {
  _hi_cfg_pty hdr_preset_name 'h\nquiet\ns\n' '' config_hub || _hi_why || return 1
  [[ "$(_hi_cfg_lines hdr_preset_name)" == *"export _HI_HEADER_ORDER='utc localtime gitid'"* ]] || _hi_why
}

# the header feature row turns the whole header off, and its page's preview
# says so in words rather than showing an empty box
function test_menu_header_off_previews_as_words() {
  _hi_cfg_pty hdr_off "i\n$(_hi_item 'row|_HI_FEATURE_PROMPTS|0')\ns\n" '' config_hub || _hi_why || return 1
  _hi_cfg_has hdr_off "header off - nothing prints" &&
    [[ "$(_hi_cfg_lines hdr_off)" == *"export _HI_DISABLE_HEADER=1"* ]] || _hi_why
}

# an empty $_HI_HEADER_ORDER means the default at runtime, so the last item
# cannot be turned off - the menu says how to get an empty header instead
function test_menu_keeps_the_last_header_item() {
  _hi_cfg_pty hdr_last "$(_hi_item 'word|0')\ns\n" "export _HI_HEADER_ORDER='gitid'" config_hub || _hi_why || return 1
  _hi_cfg_has hdr_last "keep at least one header item" &&
    [[ "$(_hi_cfg_lines hdr_last)" == *"export _HI_HEADER_ORDER='gitid'"* ]] || _hi_why
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

# a package group's number flips it: useful, off
function test_menu_flips_a_package_group() {
  _hi_cfg_pty hdr_groups "$(_hi_item 'group|useful')\ns\n" '' config_hub || _hi_why || return 1
  _hi_cfg_has hdr_groups "package group useful: now off" &&
    [[ "$(_hi_cfg_lines hdr_groups)" == *"export _HI_PACKAGES_GROUPS='core deprecated'"* ]] || _hi_why
}

# a group of plugins has a key and no box: the Plugins page names it beside
# its plugins, and nothing numbers it
function test_menu_lists_a_plugin_group_without_a_box() {
  ! _hi_item 'plugin|editors' >/dev/null || _hi_because "the group has a number" || return 1
  _hi_cfg_pty plug_group 'g\ns\n' '' config_hub || return 1
  _hi_cfg_has plug_group "g2  editors  vim nvim nano" && ! _hi_cfg_has plug_group "] editors" &&
    [[ "$(_hi_cfg_lines plug_group)" != *"_HI_PLUGINS_OFF"* ]] || _hi_why
}

# a plugin's number keeps it home, on its group's page: editors is g2, the
# second group by name
function test_menu_keeps_a_plugin_home() {
  _hi_cfg_pty plug_num "g2\n$(_hi_item 'plugin|nano')\ns\n" '' config_hub || _hi_why || return 1
  _hi_cfg_has plug_num ") [ ] nano" &&
    [[ "$(_hi_cfg_lines plug_num)" == *"export _HI_PLUGINS_OFF='nano'"* ]] || _hi_why
}

# ...and sends it again, the list's other plugins left on it
function test_menu_sends_a_plugin_kept_home() {
  _hi_cfg_pty plug_back "$(_hi_item 'plugin|nano')\ns\n" "export _HI_PLUGINS_OFF='nano vim'" config_hub || _hi_why || return 1
  _hi_cfg_has plug_back "nano: is sent" &&
    [[ "$(_hi_cfg_lines plug_back)" == *"export _HI_PLUGINS_OFF='vim'"* ]] || _hi_why
}

# a plugin that is off by default moves through the other list: zoxide's box
# writes it to $_HI_PLUGINS_ON, and nothing to the list kept home
function test_menu_switches_a_default_off_plugin_on() {
  local lines
  _hi_cfg_pty plug_on "$(_hi_item 'plugin|zoxide')\ns\n" '' config_hub || _hi_why || return 1
  lines="$(_hi_cfg_lines plug_on)"
  _hi_cfg_has plug_on "zoxide: is sent" &&
    [[ "$lines" == *"export _HI_PLUGINS_ON='zoxide'"* && "$lines" != *"_HI_PLUGINS_OFF"* ]] || _hi_why lines
}

# The indices here are positions in $_HI_FEATURE_PROMPTS, so inserting a row
# above the one a case means shifts it: the tool aliases are 4 and
# _HI_DISABLE_ENV_STATUS 3 because the greeting row sits at 1, under the
# header's.

# an opt-in row (the tool aliases, 4) flips on to its on-value
function test_menu_opt_in_row_writes_its_on_value() {
  _hi_cfg_pty feat_opt_in "$(_hi_item 'row|_HI_FEATURE_PROMPTS|4')\ns\n" '' config_hub || _hi_why || return 1
  _hi_cfg_has feat_opt_in "styled tool aliases: now on" &&
    [[ "$(_hi_cfg_lines feat_opt_in)" == *"export _HI_TOOL_ALIASES=1"* ]] || _hi_why
}

# The environment segment sits after git status. Its preview, boxed under
# the Prompt page, falls back to the shape when nothing is active here, which
# is what a run on a bare CI box sees - so the case asserts the toggle and the
# paren shape, not a name only this machine would have.
function test_menu_env_segment_toggles_and_previews() {
  _hi_cfg_pty feat_env "r\n$(_hi_item 'row|_HI_FEATURE_PROMPTS|3')\ns\n" '' config_hub || _hi_why || return 1
  _hi_cfg_has feat_env "environment segment: now off" &&
    _hi_cfg_has feat_env "myproj" &&
    [[ "$(_hi_cfg_lines feat_env)" == *"export _HI_DISABLE_ENV_STATUS=1"* ]] || _hi_why
}

# ...and the header row, off and back on, previews the whole header both ways
function test_menu_header_row_previews_the_header() {
  _hi_cfg_pty feat_header "i\n$(_hi_item 'row|_HI_FEATURE_PROMPTS|0')\n$(_hi_item 'row|_HI_FEATURE_PROMPTS|0')\ns\n" '' config_hub || _hi_why || return 1
  _hi_cfg_has feat_header "header off - nothing prints" &&
    _hi_cfg_has feat_header "Connected" &&
    [ -z "$(_hi_cfg_lines feat_header | tr -d '[:space:]')" ] || _hi_why
}

# a separator typed for bash is single-quoted; zsh's, asked but left alone,
# is never written
function test_prompt_end_typed_interactively_is_quoted() {
  _hi_cfg_pty pe_typed "$(_hi_item 'end|bash')\n>>\ns\n" '' config_hub || _hi_why || return 1
  local lines
  lines="$(_hi_cfg_lines pe_typed)"
  [[ "$lines" == *"export _HI_PROMPT_END_BASH='>>'"* && "$lines" != *"_HI_PROMPT_END_ZSH"* ]] || _hi_why lines
}

# who draws each shell's prompt is asked shell by shell: starship for bash,
# by name, hi for zsh and fish, by number, is one plain `hi` and bash's entry
function test_menu_picks_a_prompt_program_per_shell() {
  _hi_cfg_pty pe_star "$(_hi_item 'tool|bash')\nstarship\n$(_hi_item 'tool|zsh')\n2\n$(_hi_item 'tool|fish')\n2\ns\n" '' config_hub || _hi_why || return 1
  _hi_cfg_has pe_star "bash prompt: starship" &&
    [[ "$(_hi_cfg_lines pe_star)" == *"export _HI_PROMPT_TOOL='bash:starship hi'"* ]] || _hi_why
}

# ...and auto for every shell clears the line rather than writing one
function test_menu_prompt_program_back_to_auto() {
  _hi_cfg_pty pe_star_off "$(_hi_item 'tool|bash')\nauto\ns\n" "export _HI_PROMPT_TOOL='bash:starship'" config_hub || _hi_why || return 1
  _hi_cfg_has pe_star_off "bash prompt: auto" && _hi_cfg_has pe_star_off "CFGLINES=" &&
    [[ "$(_hi_cfg_lines pe_star_off)" != *"_HI_PROMPT_TOOL"* ]] || _hi_why
}

# a name off the list is said and asked again, and the third in a row leaves
# the shell's entry as it was
function test_menu_prompt_program_rejects_a_stranger() {
  _hi_cfg_pty pe_stranger "$(_hi_item 'tool|bash')\nnope\nstarship\ns\n" '' config_hub || _hi_why || return 1
  _hi_cfg_has pe_stranger "no choice nope - type a number or a name from the list" &&
    [[ "$(_hi_cfg_lines pe_stranger)" == *"export _HI_PROMPT_TOOL=bash:starship"* ]] || _hi_why || return 1
  _hi_cfg_pty pe_strangers "$(_hi_item 'tool|bash')\nnope\n99\nnah\ns\n" "export _HI_PROMPT_TOOL='bash:starship'" config_hub || _hi_why || return 1
  _hi_cfg_has pe_strangers "no choice 99" && ! _hi_cfg_has pe_strangers "no choice nah" &&
    [[ "$(_hi_cfg_lines pe_strangers)" == *"export _HI_PROMPT_TOOL=bash:starship"* ]] || _hi_why
}

# the Advanced rows: an opt-in toggle and a value typed for real, including
# the words-to-flag mapping _HI_TRUECOLOR's question hides behind ("on" is
# stored as 1)
function test_menu_advanced_rows() {
  _hi_cfg_pty adv_typed "$(_hi_item 'row|_HI_ADVANCED_PROMPTS|0')\n$(_hi_item truecolor)\non\ns\n" '' config_hub || _hi_why || return 1
  local lines
  lines="$(_hi_cfg_lines adv_typed)"
  _hi_cfg_has adv_typed "drop the leading space: now on" &&
    [[ "$lines" == *"export _HI_DISABLE_LEAD_SPACE=1"* && "$lines" == *"export _HI_TRUECOLOR=1"* ]] || _hi_why lines
}

# Enter at the preset question keeps the current settings: nothing seeded,
# and the run carries on rather than failing
function test_preset_question_enter_keeps_current() {
  _hi_cfg_pty pre_enter '\n' '' config_preset || _hi_why || return 1
  [ "$(_hi_cfg_rc pre_enter)" = 0 ] &&
    _hi_cfg_has pre_enter "Start from a preset?" &&
    ! _hi_cfg_has pre_enter "starting from the" || _hi_why
}

# a typo gets the full name list back and the run carries on unseeded - the
# question is an offer, not a gate
function test_preset_question_refuses_a_stranger_and_carries_on() {
  _hi_cfg_pty pre_unknown 'zzz\n' '' config_preset || _hi_why || return 1
  [ "$(_hi_cfg_rc pre_unknown)" = 0 ] && _hi_cfg_has pre_unknown "no such preset: zzz" || _hi_why
}

# a shorthand letter resolves and seeds the run
function test_preset_shorthand_seeds_the_run() {
  _hi_cfg_pty pre_walk 'b\n' '' config_preset || _hi_why || return 1
  _hi_cfg_has pre_walk "starting from the 'balanced' preset" &&
    [[ "$(_hi_cfg_lines pre_walk)" == *"export _HI_PACKAGES_GROUPS='core,deprecated'"* ]] || _hi_why
}

# The whole run. The shortest: the intro orients, p opens the presets, m
# picks minimal, s saves - and the one write at the end is exactly the
# preset's block.
function test_full_run_preset_then_save() {
  _hi_cfg_pty full_walk 'p\nm\ns\n' '' run_configure "" || _hi_why || return 1
  local block
  block="$(grep -F "$_HI_MARKER" "$_HI_WORKDIR/full_walk/overlay/settings.sh")"
  _hi_cfg_has full_walk "Nothing is written until you save" &&
    _hi_cfg_has full_walk "starting from the 'minimal' preset" &&
    _hi_cfg_has full_walk "CFGQUIT=none" &&
    [[ "$block" == *"export _HI_DISABLE_HEADER=1"* && "$block" == *"export _HI_DISABLE_LOCAL=1"* &&
      "$block" == *"export _HI_PLUGINS_OFF='vim,nvim,nano,emacs,hx,kak,micro'"* ]] || _hi_why block
}

# q after the same preset writes nothing at all - no block, not even the
# shebang - and leaves the flag install.sh's closing line reads
function test_full_run_quit_writes_nothing() {
  _hi_cfg_pty full_quit 'p\nm\nq\n' '' run_configure "" || _hi_why || return 1
  _hi_cfg_has full_quit "starting from the 'minimal' preset" &&
    _hi_cfg_has full_quit "nothing written" &&
    _hi_cfg_has full_quit "CFGQUIT=1" &&
    ! grep -qF "$_HI_MARKER" "$_HI_WORKDIR/full_quit/overlay/settings.sh" || _hi_why
}

# EOF at the menu saves what there is - no answer has always meant "keep
# what you have and finish" here - so a driver that stops typing still ends
# in the write
function test_menu_eof_saves() {
  _hi_cfg_pty hub_eof '\004' 'export _HI_DISABLE_GIT_STATUS=1' run_configure "" || _hi_why || return 1
  _hi_cfg_has hub_eof "CFGQUIT=none" &&
    grep -qF "export _HI_DISABLE_GIT_STATUS=1" "$_HI_WORKDIR/hub_eof/overlay/settings.sh" || _hi_why
}

# ...and the third junk answer in a row ends the run too, but as a quit:
# three words that are not menu items are not an instruction to write
function test_menu_junk_is_bounded_and_quits() {
  _hi_cfg_pty hub_junk 'x\ny\nz\nq\n' '' run_configure "" || _hi_why || return 1
  _hi_cfg_has hub_junk "type an item number" &&
    _hi_cfg_has hub_junk "leaving" &&
    _hi_cfg_has hub_junk "CFGQUIT=1" || _hi_why
}

# the main page is a table and no preview: the two switches for where hi
# styles a shell, then a row a page, in order - its key, its name, and what
# it holds - a group of plugins under Plugins with its plugins named, and
# none of the pages' own rows
function test_menu_main_page_is_a_table_of_its_pages() {
  local main keys
  _HI_TERM_COLS=80 _hi_cfg_pty hub_all 's\n' '' run_configure "" || _hi_why || return 1
  main="$(_hi_cfg_screen hub_all 0)"
  keys="$(printf '%s\n' "$main" | sed -n 's/^ [^ ]* \[\([a-z]\)\] .*/\1/p' | paste -sd, -)"
  [ "$keys" = "l,t,i,e,c,r,g,a,v" ] || _hi_because "the main page's rows: [$keys]" || return 1
  [[ "$main" != *"preview"* && "$main" == *"[l] "*"[x] this machine "*"[t] "*"[x] targets "* ]] &&
    [[ "$main" == *"[i] "*" Header "*"3 of 3 on, width 80"*"[e] "*" cells "*" utc version "* ]] &&
    [[ "$main" == *"[c] "*" package check "*" core useful deprecated"* && "$main" == *"[g] "*" Plugins "*" ride"* ]] &&
    [[ "$main" == *" g1 "*" cli "*" bat "*" g2 "*" editors "*" nano "* ]] &&
    [[ "$main" == *"[v] "*" Advanced "*", 24-bit color auto"* ]] &&
    [[ "$main" != *") ["* && "$main" != *"hi --configure:"* && "$main" != *"[b]ack"* ]] &&
    _hi_cfg_has hub_all "CFGQUIT=none" || _hi_why main
}

# a row's key opens its page - titled, [b]ack leading the keys, only its own
# rows, and a preview of what they change or none - and b comes back to the
# main page
function test_menu_keys_open_their_pages() {
  local titles end sudo core hdr utc bat
  end="$(_hi_item 'end|bash')" && core="$(_hi_item 'group|core')" &&
    sudo="$(_hi_item 'row|_HI_FEATURE_PROMPTS|5')" && hdr="$(_hi_item 'row|_HI_FEATURE_PROMPTS|0')" &&
    utc="$(_hi_item 'word|0')" && bat="$(_hi_item 'plugin|bat')" || _hi_why end core sudo hdr || return 1
  _HI_TERM_COLS=80 _hi_cfg_pty hub_pages "$_HI_MENU_EVERY_PAGE" '' run_configure "" || _hi_why || return 1
  titles="$(_hi_cfg_titles hub_pages)"
  [ "$titles" = "$_HI_MENU_EVERY_TITLE" ] || _hi_because "titles: [$titles]" || return 1
  _hi_cfg_screen_has hub_pages 1 " [b]ack  [s]ave" &&
    _hi_cfg_screen_has hub_pages 1 " $hdr) [x] header" &&
    _hi_cfg_screen_has hub_pages 1 "Connected" &&
    _hi_cfg_screen_has hub_pages 1 "[e] cells" &&
    _hi_cfg_screen_has hub_pages 2 " [b]ack  [h]eader preset" &&
    _hi_cfg_screen_has hub_pages 2 " $utc) [x] utc" &&
    _hi_cfg_screen_has hub_pages 3 "$core) [x] core" &&
    _hi_cfg_screen_has hub_pages 4 "$end)     bash prompt ends with" &&
    _hi_cfg_screen_has hub_pages 5 "g2  editors  vim nvim nano" &&
    _hi_cfg_screen_has hub_pages 6 "$bat) [x] bat" &&
    _hi_cfg_screen_has hub_pages 6 "program  config  on a target" &&
    _hi_cfg_screen_has hub_pages 7 "$sudo) [ ] sudo alias" &&
    _hi_cfg_screen_has hub_pages 8 "24-bit color" &&
    _hi_cfg_screen_has hub_pages 9 "[x] this machine" &&
    ! _hi_cfg_screen_has hub_pages 4 " $hdr) [x] header" 2>/dev/null &&
    ! _hi_cfg_screen_has hub_pages 4 "Connected" 2>/dev/null &&
    ! _hi_cfg_screen_has hub_pages 5 "preview" 2>/dev/null &&
    ! _hi_cfg_screen_has hub_pages 6 "preview" 2>/dev/null &&
    ! _hi_cfg_screen_has hub_pages 9 "preview" 2>/dev/null &&
    ! _hi_cfg_screen_has hub_pages 9 "[b]ack" 2>/dev/null || _hi_why hdr utc core end
}

# the main page's two switches flip by their keys: this machine's writes
# _HI_DISABLE_LOCAL, the targets' _HI_PLAIN
function test_menu_main_page_switches_where_hi_styles() {
  local lines
  _HI_TERM_COLS=80 _hi_cfg_pty hub_where 'l\nt\ns\n' '' run_configure "" || _hi_why || return 1
  lines="$(_hi_cfg_lines hub_where)"
  _hi_cfg_screen_has hub_where 1 "this machine: now off" &&
    _hi_cfg_screen_has hub_where 1 "[ ] this machine" &&
    _hi_cfg_screen_has hub_where 2 "targets: now off" &&
    _hi_cfg_screen_has hub_where 2 "[ ] targets" &&
    [[ "$lines" == *"export _HI_DISABLE_LOCAL=1"* && "$lines" == *"export _HI_PLAIN=1"* ]] || _hi_why lines
}

# a number works from any page: the main page's flips a Prompt row and stays
# on the main page, the Advanced page's flips an Aliases row and stays there
function test_menu_number_works_from_any_page() {
  local p t
  p="$(_hi_item 'row|_HI_PROMPT_PROMPTS|0')" && t="$(_hi_item 'row|_HI_FEATURE_PROMPTS|4')" || _hi_why p t || return 1
  _HI_TERM_COLS=80 _hi_cfg_pty hub_num "$p\nv\n$t\ns\n" '' run_configure "" || _hi_why p t || return 1
  local lines
  lines="$(_hi_cfg_lines hub_num)"
  _hi_cfg_screen_has hub_num 1 "colored user@host prompt: now off" &&
    _hi_cfg_screen_has hub_num 1 "[x] this machine" &&
    _hi_cfg_screen_has hub_num 3 "styled tool aliases: now on" &&
    _hi_cfg_screen_has hub_num 3 "hi --configure: Advanced" &&
    [[ "$lines" == *"export _HI_DISABLE_PROMPT=1"* && "$lines" == *"export _HI_TOOL_ALIASES=1"* ]] || _hi_why lines
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

function test_menu_header_grid_at_80() { _hi_menu_grid_at 80 4; }

function test_menu_header_grid_at_40() { _hi_menu_grid_at 40 2; }

# At 80 columns every page, the main one included, fits a 24-row terminal:
# a draw's lines, then the prompt's own row
function test_menu_pages_fit_24_rows() {
  local k rows
  _HI_TERM_COLS=80 _hi_cfg_pty hub_rows "$_HI_MENU_EVERY_PAGE" '' run_configure "" || _hi_why || return 1
  for k in 1 2 3 4 5 6 7 8 9; do
    rows=$(($(_hi_cfg_screen hub_rows "$k" | wc -l) + 1))
    ((rows <= 24)) || _hi_because "draw $k is $rows rows" || return 1
  done
}

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
  [ "$titles" = "$want" ] || {
    _hi_cecho " | the pages at $w columns: [$titles]" "$RED"
    return 1
  }
  [ "$over" = 0 ]
}

function test_menu_layout_at_80() { _hi_menu_layout_at 80; }

function test_menu_layout_at_40() { _hi_menu_layout_at 40; }

# a value away from its default says the default beside it; one at it does not
function test_menu_value_shows_its_default() {
  _HI_TERM_COLS=80 _hi_cfg_pty hub_def 'i\ns\n' "export _HI_MAX_WIDTH=100" run_configure "" || _hi_why || return 1
  _hi_cfg_has hub_def "width                 100 (default 80)" &&
    ! _hi_cfg_has hub_def "(default 172.*)" || _hi_why
}

function run_configure_pty_tests() {
  _hi_configure_begin

  _hi_h1 "Testing scripts/configure.sh's reusable logic (pty)"

  # Every pty case fans out together: each drives its own child under its own
  # $_HI_WORKDIR/<label> and the children re-source configure.sh themselves,
  # so nothing in this shell is shared - and thirty-odd of them at a second
  # apiece would be this suite's whole wall clock run one at a time.
  # The package-groups prompts belong to the section above; they sit here
  # because they are pty cases too.
  _hi_h2 "Testing: the interactive arms and the menu (pty)"
  _hi_par_begin "pty cases"
  _hi_par_check_capable pty "ask_value takes a typed number" test_ask_value_takes_a_typed_number
  _hi_par_check_capable pty "ask_value rejects junk and keeps current" test_ask_value_rejects_junk_and_keeps_current
  _hi_par_check_capable pty "ask_value: the typed default clears the override" test_ask_value_typed_default_clears_the_override
  _hi_par_check_capable pty "Truecolor words map both ways" test_truecolor_maps_its_words
  _hi_par_check_capable pty "Preset question: Enter keeps current" test_preset_question_enter_keeps_current
  _hi_par_check_capable pty "Preset question: a stranger is refused, run continues" test_preset_question_refuses_a_stranger_and_carries_on
  _hi_par_check_capable pty "Preset shorthand seeds the run" test_preset_shorthand_seeds_the_run
  _hi_par_check_capable pty "Menu: the main page is a table of its pages" test_menu_main_page_is_a_table_of_its_pages
  _hi_par_check_capable pty "Menu: a row's key opens its page, b comes back" test_menu_keys_open_their_pages
  _hi_par_check_capable pty "Menu: l and t switch where hi styles a shell" test_menu_main_page_switches_where_hi_styles
  _hi_par_check_capable pty "Menu: a number works from any page" test_menu_number_works_from_any_page
  _hi_par_check_capable pty "Menu: the cells' grid holds 4 columns at 80" test_menu_header_grid_at_80
  _hi_par_check_capable pty "Menu: the cells' grid folds to 2 at 40" test_menu_header_grid_at_40
  _hi_par_check_capable pty "Menu: every page fits 24 rows at 80 columns" test_menu_pages_fit_24_rows
  _hi_par_check_capable pty "Menu: fits 80 columns, pages in order" test_menu_layout_at_80
  _hi_par_check_capable pty "Menu: fits 40 columns, pages in order" test_menu_layout_at_40
  _hi_par_check_capable pty "Menu: a changed value names its default" test_menu_value_shows_its_default
  _hi_par_check_capable pty "Menu: a plugin group has a key and no box" test_menu_lists_a_plugin_group_without_a_box
  _hi_par_check_capable pty "Menu: a plugin's number keeps it home" test_menu_keeps_a_plugin_home
  _hi_par_check_capable pty "Menu: ...and sends it again" test_menu_sends_a_plugin_kept_home
  _hi_par_check_capable pty "Menu: ...and one off by default is switched on" test_menu_switches_a_default_off_plugin_on
  _hi_par_check_capable pty "Menu: an opt-in row writes its on-value" test_menu_opt_in_row_writes_its_on_value
  _hi_par_check_capable pty "Menu: the environment row toggles and previews" test_menu_env_segment_toggles_and_previews
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
  _hi_par_check_capable pty "Menu: a prompt program is picked per shell" test_menu_picks_a_prompt_program_per_shell
  _hi_par_check_capable pty "Menu: auto for every shell clears the line" test_menu_prompt_program_back_to_auto
  _hi_par_check_capable pty "Menu: a prompt program off the list is asked again" test_menu_prompt_program_rejects_a_stranger
  _hi_par_check_capable pty "Menu: a separator typed and quoted" test_prompt_end_typed_interactively_is_quoted
  _hi_par_check_capable pty "Menu: a quoted separator is refused" test_menu_refuses_a_quoted_separator
  _hi_par_check_capable pty "Menu: the advanced rows" test_menu_advanced_rows
  _hi_par_check_capable pty "Full run: preset, then save" test_full_run_preset_then_save
  _hi_par_check_capable pty "Full run: preset, then quit writes nothing" test_full_run_quit_writes_nothing
  _hi_par_check_capable pty "Menu: EOF saves" test_menu_eof_saves
  _hi_par_check_capable pty "Menu: junk is bounded and quits" test_menu_junk_is_bounded_and_quits
  _hi_par_wait

  _hi_suite_end "configure.sh logic (pty)"
}

run_configure_pty_tests
