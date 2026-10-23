#!/usr/bin/env bash
# scripts/configure.sh's interactive arms and its menu, each driven through a
# pty; the menu's layout and header page are configure_menu_test.sh's.
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

_HI_CONFIGURE_PART=pty
# shellcheck source=./configure_test.sh
source "${BASH_SOURCE[0]%/*}/configure_test.sh"

function test_ask_value_takes_a_typed_number() {
  local got
  _hi_cfg_pty width_typed '120\n' '' config_max_width || _hi_why || return 1
  got="$(_hi_cfg_lines width_typed)"
  [ "$got" = "export _HI_MAX_WIDTH=120" ] || _hi_why got
}

# a rejected answer says why and keeps the current value rather than dropping
# it - the message names the value kept, so both halves are one substring
function test_ask_value_rejects_junk_and_keeps_current() {
  local got
  _hi_cfg_pty width_junk 'abc\n' 'export _HI_MAX_WIDTH=100' config_max_width || _hi_why || return 1
  _hi_cfg_has width_junk "a number, 40 or more, leaving it at 100" || _hi_why || return 1
  got="$(_hi_cfg_lines width_junk)"
  [ "$got" = "export _HI_MAX_WIDTH=100" ] || _hi_why got
}

# typing the shipped default is how an override is cleared interactively
function test_ask_value_typed_default_clears_the_override() {
  local got
  _hi_cfg_pty width_default '80\n' 'export _HI_MAX_WIDTH=100' config_max_width || _hi_why || return 1
  got="$(_hi_cfg_lines width_default | tr -d '[:space:]')"
  [ -z "$got" ] || _hi_why got
}

# a separator with a quote in it is refused rather than written into
# settings.sh
function test_menu_refuses_a_quoted_separator() {
  local got
  _hi_cfg_pty pe_quote "$(_hi_item 'end|bash')\n'\ns\n" '' config_hub || _hi_why || return 1
  _hi_cfg_has pe_quote "a single quote can't be written to settings.sh" || _hi_why || return 1
  got="$(_hi_cfg_lines pe_quote)"
  [[ "$got" != *"_HI_PROMPT_END_"* ]] || _hi_why got
}

# the truecolor question maps its words both ways: `off` is stored as 0, and
# nothing writes an $_HI_ASCII
function test_truecolor_maps_its_words() {
  _hi_cfg_pty adv_tc 'off\n' '' config_truecolor || _hi_why || return 1
  local lines
  lines="$(_hi_cfg_lines adv_tc)"
  [[ "$lines" == *"export _HI_TRUECOLOR=0"* && "$lines" != *"_HI_ASCII"* ]] || _hi_why lines
}

# a group of plugins has a key and no box: the Plugins page names it beside
# its plugins, and nothing numbers it
function test_menu_lists_a_plugin_group_without_a_box() {
  local got
  ! _hi_item 'plugin|editors' >/dev/null || _hi_because "the group has a number" || return 1
  _hi_cfg_pty plug_group 'g\ns\n' '' config_hub || return 1
  { _hi_cfg_has plug_group "g2  editors  vim nvim nano" && ! _hi_cfg_has plug_group "] editors"; } || _hi_why || return 1
  got="$(_hi_cfg_lines plug_group)"
  [[ "$got" != *"_HI_PLUGINS_OFF"* ]] || _hi_why got
}

# a plugin's number keeps it home, on its group's page: editors is g2, the
# second group by name
function test_menu_keeps_a_plugin_home() {
  local got
  _hi_cfg_pty plug_num "g2\n$(_hi_item 'plugin|nano')\ns\n" '' config_hub || _hi_why || return 1
  _hi_cfg_has plug_num ") [ ] nano" || _hi_why || return 1
  got="$(_hi_cfg_lines plug_num)"
  [[ "$got" == *"export _HI_PLUGINS_OFF='nano'"* ]] || _hi_why got
}

# ...and sends it again, the list's other plugins left on it
function test_menu_sends_a_plugin_kept_home() {
  local got
  _hi_cfg_pty plug_back "$(_hi_item 'plugin|nano')\ns\n" "export _HI_PLUGINS_OFF='nano vim'" config_hub || _hi_why || return 1
  _hi_cfg_has plug_back "nano: is sent" || _hi_why || return 1
  got="$(_hi_cfg_lines plug_back)"
  [[ "$got" == *"export _HI_PLUGINS_OFF='vim'"* ]] || _hi_why got
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
  local got
  _hi_cfg_pty feat_opt_in "$(_hi_item 'row|_HI_FEATURE_PROMPTS|4')\ns\n" '' config_hub || _hi_why || return 1
  _hi_cfg_has feat_opt_in "styled tool aliases: now on" || _hi_why || return 1
  got="$(_hi_cfg_lines feat_opt_in)"
  [[ "$got" == *"export _HI_TOOL_ALIASES=1"* ]] || _hi_why got
}

# The environment segment sits after git status. Its preview, boxed under
# the Prompt page, falls back to the shape when nothing is active here, which
# is what a run on a bare CI box sees - so the case asserts the toggle and the
# paren shape, not a name only this machine would have.
function test_menu_env_segment_toggles_and_previews() {
  local got
  _hi_cfg_pty feat_env "r\n$(_hi_item 'row|_HI_FEATURE_PROMPTS|3')\ns\n" '' config_hub || _hi_why || return 1
  { _hi_cfg_has feat_env "environment segment: now off" && _hi_cfg_has feat_env "myproj"; } || _hi_why || return 1
  got="$(_hi_cfg_lines feat_env)"
  [[ "$got" == *"export _HI_DISABLE_ENV_STATUS=1"* ]] || _hi_why got
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
  local got
  _hi_cfg_pty pe_star "$(_hi_item 'tool|bash')\nstarship\n$(_hi_item 'tool|zsh')\n2\n$(_hi_item 'tool|fish')\n2\ns\n" '' config_hub || _hi_why || return 1
  _hi_cfg_has pe_star "bash prompt: starship" || _hi_why || return 1
  got="$(_hi_cfg_lines pe_star)"
  [[ "$got" == *"export _HI_PROMPT_TOOL='bash:starship hi'"* ]] || _hi_why got
}

# ...and auto for every shell clears the line rather than writing one
function test_menu_prompt_program_back_to_auto() {
  local got
  _hi_cfg_pty pe_star_off "$(_hi_item 'tool|bash')\nauto\ns\n" "export _HI_PROMPT_TOOL='bash:starship'" config_hub || _hi_why || return 1
  { _hi_cfg_has pe_star_off "bash prompt: auto" && _hi_cfg_has pe_star_off "CFGLINES="; } || _hi_why || return 1
  got="$(_hi_cfg_lines pe_star_off)"
  [[ "$got" != *"_HI_PROMPT_TOOL"* ]] || _hi_why got
}

# a name off the list is said and asked again, and the third in a row leaves
# the shell's entry as it was
function test_menu_prompt_program_rejects_a_stranger() {
  local got
  _hi_cfg_pty pe_stranger "$(_hi_item 'tool|bash')\nnope\nstarship\ns\n" '' config_hub || _hi_why || return 1
  _hi_cfg_has pe_stranger "no choice nope - type a number or a name from the list" || _hi_why || return 1
  got="$(_hi_cfg_lines pe_stranger)"
  [[ "$got" == *"export _HI_PROMPT_TOOL=bash:starship"* ]] || _hi_why got || return 1
  _hi_cfg_pty pe_strangers "$(_hi_item 'tool|bash')\nnope\n99\nnah\ns\n" "export _HI_PROMPT_TOOL='bash:starship'" config_hub || _hi_why || return 1
  { _hi_cfg_has pe_strangers "no choice 99" && ! _hi_cfg_has pe_strangers "no choice nah"; } || _hi_why || return 1
  got="$(_hi_cfg_lines pe_strangers)"
  [[ "$got" == *"export _HI_PROMPT_TOOL=bash:starship"* ]] || _hi_why got
}

# the main page's closing rows: an opt-in toggle and a value typed for real, including
# the words-to-flag mapping _HI_TRUECOLOR's question hides behind ("on" is
# stored as 1)
function test_menu_advanced_rows() {
  _hi_cfg_pty adv_typed "$(_hi_item 'row|_HI_ADVANCED_PROMPTS|0')\n$(_hi_item truecolor)\non\ns\n" '' config_hub || _hi_why || return 1
  local lines
  lines="$(_hi_cfg_lines adv_typed)"
  _hi_cfg_has adv_typed "drop the leading space: now on" &&
    [[ "$lines" == *"export _HI_DISABLE_LEAD_SPACE=1"* && "$lines" == *"export _HI_TRUECOLOR=1"* ]] || _hi_why lines
}

# the hub's y key opens the same truecolor question its row does
function test_menu_y_key_asks_truecolor() {
  _hi_cfg_pty y_key 'y\noff\ns\n' '' config_hub || _hi_why || return 1
  local lines
  lines="$(_hi_cfg_lines y_key)"
  [[ "$lines" == *"export _HI_TRUECOLOR=0"* ]] || _hi_why lines
}

# Enter at the preset question keeps the current settings: nothing seeded,
# and the run carries on rather than failing
function test_preset_question_enter_keeps_current() {
  local got
  _hi_cfg_pty pre_enter '\n' '' config_preset || _hi_why || return 1
  got="$(_hi_cfg_rc pre_enter)"
  { [ "$got" = 0 ] && _hi_cfg_has pre_enter "Start from a preset?" && ! _hi_cfg_has pre_enter "starting from the"; } || _hi_why got
}

# a typo gets the full name list back and the run carries on unseeded - the
# question is an offer, not a gate
function test_preset_question_refuses_a_stranger_and_carries_on() {
  local got
  _hi_cfg_pty pre_unknown 'zzz\n' '' config_preset || _hi_why || return 1
  got="$(_hi_cfg_rc pre_unknown)"
  { [ "$got" = 0 ] && _hi_cfg_has pre_unknown "no such preset: zzz"; } || _hi_why got
}

# a shorthand letter resolves and seeds the run
function test_preset_shorthand_seeds_the_run() {
  local got
  _hi_cfg_pty pre_walk 'b\n' '' config_preset || _hi_why || return 1
  _hi_cfg_has pre_walk "starting from the 'balanced' preset" || _hi_why || return 1
  got="$(_hi_cfg_lines pre_walk)"
  [[ "$got" == *"export _HI_PACKAGES_GROUPS='core,deprecated'"* ]] || _hi_why got
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
# three words that are not menu items are not an instruction to write. No
# word here is a key of the menu's, and nothing after the third is typed, so
# the quit is the count's
function test_menu_junk_is_bounded_and_quits() {
  _hi_cfg_pty hub_junk 'xx\nzz\nww\n' '' run_configure "" || _hi_why || return 1
  _hi_cfg_has hub_junk "type an item number" &&
    _hi_cfg_has hub_junk "not a menu item three times - leaving" &&
    _hi_cfg_has hub_junk "CFGQUIT=1" || _hi_why
}

# the main page is a table and no preview: the two switches for where hi
# styles a shell, then a row a page, in order - its key, its name, and what
# it holds - a group of plugins under Plugins with its plugins named, the
# switches with no page and the 24-bit color, and none of the pages' own rows
function test_menu_main_page_is_a_table_of_its_pages() {
  local main keys
  _HI_TERM_COLS=80 _hi_cfg_pty hub_all 's\n' '' run_configure "" || _hi_why || return 1
  main="$(_hi_cfg_screen hub_all 0)"
  keys="$(printf '%s\n' "$main" | sed -n 's/^ [^ ]* \[\([a-z]\)\] .*/\1/p' | paste -sd, -)"
  [ "$keys" = "l,t,i,e,c,r,g,a,o,m,k,y" ] || _hi_because "the main page's rows: [$keys]" || return 1
  [[ "$main" != *"preview"* && "$main" == *"[l] "*"[x] this machine "*"[t] "*"[x] targets "* ]] &&
    [[ "$main" == *"[i] "*" Header "*"3 of 3 on, width 80"*"[e] "*" cells "*" utc version "* ]] &&
    [[ "$main" == *"[c] "*" package check "*" core useful deprecated"* && "$main" == *"[g] "*" Plugins "*" ride"* ]] &&
    [[ "$main" == *" g1 "*" cli "*" bat "*" g2 "*" editors "*" nano "* ]] &&
    [[ "$main" == *"[a] "*"[ ] tool aliases "*"[k] "*"[ ] ssh --keep "*"[y] "*" 24-bit color "*" auto"* ]] &&
    [[ "$main" != *") ["* && "$main" != *"hi --configure:"* && "$main" != *"[b]ack"* ]] &&
    _hi_cfg_has hub_all "CFGQUIT=none" || _hi_why main
}

# a row's key opens its page - titled, [b]ack leading the keys, only its own
# rows, and a preview of what they change or none - and b comes back to the
# main page
function test_menu_keys_open_their_pages() {
  local titles end core hdr utc bat
  end="$(_hi_item 'end|bash')" && core="$(_hi_item 'group|core')" &&
    hdr="$(_hi_item 'row|_HI_FEATURE_PROMPTS|0')" &&
    utc="$(_hi_item 'word|0')" && bat="$(_hi_item 'plugin|bat')" || _hi_why end core hdr || return 1
  _HI_TERM_COLS=80 _hi_cfg_pty hub_pages "$_HI_MENU_EVERY_PAGE" '' run_configure "" || _hi_why || return 1
  titles="$(_hi_cfg_titles hub_pages)"
  [ "$titles" = "$_HI_MENU_EVERY_TITLE" ] || _hi_because "titles: [$titles]" || return 1
  _hi_cfg_screen_has hub_pages 1 " [b]ack  [s]ave" &&
    _hi_cfg_screen_has hub_pages 1 " $hdr) [x] header" &&
    _hi_cfg_screen_has hub_pages 1 "Connected" &&
    _hi_cfg_screen_has hub_pages 1 "[e] cells" &&
    _hi_cfg_screen_has hub_pages 1 ") [ ] drop the header's right edge" &&
    _hi_cfg_screen_has hub_pages 2 " [b]ack  [h]eader preset" &&
    _hi_cfg_screen_has hub_pages 2 " $utc) [x] utc" &&
    _hi_cfg_screen_has hub_pages 3 "$core) [x] core" &&
    _hi_cfg_screen_has hub_pages 4 "$end)     bash prompt ends with" &&
    _hi_cfg_screen_has hub_pages 5 "g2  editors  vim nvim nano" &&
    _hi_cfg_screen_has hub_pages 6 "$bat) [x] bat" &&
    _hi_cfg_screen_has hub_pages 6 "program  config  on a target" &&
    _hi_cfg_screen_has hub_pages 7 "[x] this machine" &&
    ! _hi_cfg_screen_has hub_pages 4 " $hdr) [x] header" 2>/dev/null &&
    ! _hi_cfg_screen_has hub_pages 4 "Connected" 2>/dev/null &&
    ! _hi_cfg_screen_has hub_pages 5 "preview" 2>/dev/null &&
    ! _hi_cfg_screen_has hub_pages 6 "preview" 2>/dev/null &&
    ! _hi_cfg_screen_has hub_pages 7 "preview" 2>/dev/null &&
    ! _hi_cfg_screen_has hub_pages 7 "[b]ack" 2>/dev/null || _hi_why hdr utc core end
}

# the main page's switches flip by their keys: this machine's writes
# _HI_DISABLE_LOCAL, the targets' _HI_PLAIN, and the ones with no page their
# own setting
function test_menu_main_page_switches_where_hi_styles() {
  local lines
  _HI_TERM_COLS=80 _hi_cfg_pty hub_where 'l\nt\na\nk\ns\n' '' run_configure "" || _hi_why || return 1
  lines="$(_hi_cfg_lines hub_where)"
  _hi_cfg_screen_has hub_where 1 "this machine: now off" &&
    _hi_cfg_screen_has hub_where 1 "[ ] this machine" &&
    _hi_cfg_screen_has hub_where 2 "targets: now off" &&
    _hi_cfg_screen_has hub_where 2 "[ ] targets" &&
    _hi_cfg_screen_has hub_where 3 "[x] tool aliases" &&
    _hi_cfg_screen_has hub_where 4 "[x] ssh --keep" &&
    [[ "$lines" == *"export _HI_DISABLE_LOCAL=1"* && "$lines" == *"export _HI_PLAIN=1"* ]] &&
    [[ "$lines" == *"export _HI_TOOL_ALIASES=1"* && "$lines" == *"export _HI_KEEP=1"* ]] || _hi_why lines
}

# a number works from any page: the main page's flips a Prompt row and stays
# on the main page, the Plugins page's flips a main-page switch and stays there
function test_menu_number_works_from_any_page() {
  local p t
  p="$(_hi_item 'row|_HI_PROMPT_PROMPTS|0')" && t="$(_hi_item 'row|_HI_FEATURE_PROMPTS|4')" || _hi_why p t || return 1
  _HI_TERM_COLS=80 _hi_cfg_pty hub_num "$p\ng\n$t\ns\n" '' run_configure "" || _hi_why p t || return 1
  local lines
  lines="$(_hi_cfg_lines hub_num)"
  _hi_cfg_screen_has hub_num 1 "colored user@host prompt: now off" &&
    _hi_cfg_screen_has hub_num 1 "[x] this machine" &&
    _hi_cfg_screen_has hub_num 3 "styled tool aliases: now on" &&
    _hi_cfg_screen_has hub_num 3 "hi --configure: Plugins" &&
    [[ "$lines" == *"export _HI_DISABLE_PROMPT=1"* && "$lines" == *"export _HI_TOOL_ALIASES=1"* ]] || _hi_why lines
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
  _hi_par_check_capable pty "Menu: the main page's switches flip by their keys" test_menu_main_page_switches_where_hi_styles
  _hi_par_check_capable pty "Menu: a number works from any page" test_menu_number_works_from_any_page
  _hi_par_check_capable pty "Menu: a plugin group has a key and no box" test_menu_lists_a_plugin_group_without_a_box
  _hi_par_check_capable pty "Menu: a plugin's number keeps it home" test_menu_keeps_a_plugin_home
  _hi_par_check_capable pty "Menu: ...and sends it again" test_menu_sends_a_plugin_kept_home
  _hi_par_check_capable pty "Menu: ...and one off by default is switched on" test_menu_switches_a_default_off_plugin_on
  _hi_par_check_capable pty "Menu: an opt-in row writes its on-value" test_menu_opt_in_row_writes_its_on_value
  _hi_par_check_capable pty "Menu: the environment row toggles and previews" test_menu_env_segment_toggles_and_previews
  _hi_par_check_capable pty "Menu: a prompt program is picked per shell" test_menu_picks_a_prompt_program_per_shell
  _hi_par_check_capable pty "Menu: auto for every shell clears the line" test_menu_prompt_program_back_to_auto
  _hi_par_check_capable pty "Menu: a prompt program off the list is asked again" test_menu_prompt_program_rejects_a_stranger
  _hi_par_check_capable pty "Menu: a separator typed and quoted" test_prompt_end_typed_interactively_is_quoted
  _hi_par_check_capable pty "Menu: a quoted separator is refused" test_menu_refuses_a_quoted_separator
  _hi_par_check_capable pty "Menu: the advanced rows" test_menu_advanced_rows
  _hi_par_check_capable pty "Menu: the y key asks the truecolor question" test_menu_y_key_asks_truecolor
  _hi_par_check_capable pty "Full run: preset, then save" test_full_run_preset_then_save
  _hi_par_check_capable pty "Full run: preset, then quit writes nothing" test_full_run_quit_writes_nothing
  _hi_par_check_capable pty "Menu: EOF saves" test_menu_eof_saves
  _hi_par_check_capable pty "Menu: junk is bounded and quits" test_menu_junk_is_bounded_and_quits
  _hi_par_wait

  _hi_suite_end "configure.sh logic (pty)"
}

run_configure_pty_tests
