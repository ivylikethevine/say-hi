#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Unit tests for common/core.sh
# GLOSSARY: HI.30 + HI.34. The single-quoted probe scripts are expanded by the
# *child* shell, which is the whole point (SC2016).
# shellcheck disable=SC2329,SC2016
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

function test_use_ascii_in_a_c_locale() {
  (
    unset LC_ALL LC_CTYPE LANG _HI_ASCII
    LANG=C _hi_use_ascii
  ) || _hi_why
}

function test_use_ascii_not_under_utf8() {
  (
    unset LC_ALL LC_CTYPE LANG _HI_ASCII
    # The brace group is what silences bash's `warning: setlocale` on a host
    # without the locale (FreeBSD has C.UTF-8 and not C.utf8): the assignment
    # is made ahead of a simple command's own redirection, so 2>/dev/null has
    # to wrap the command instead. The case is about the *spelling* reaching
    # _hi_use_ascii's glob, never about the locale existing.
    ! LANG=en_US.UTF-8 _hi_use_ascii &&
      ! { LC_ALL=C.utf8 _hi_use_ascii; } 2>/dev/null # LC_ALL outranks, both spellings count
  ) || _hi_why -6
}

function test_use_ascii_override_beats_the_locale() {
  (
    unset LC_ALL LC_CTYPE LANG
    LANG=en_US.UTF-8 _HI_ASCII=1 _hi_use_ascii &&
      ! LANG=C _HI_ASCII=0 _hi_use_ascii
  ) || _hi_why
}

# the chooser's two sets, via the marks the header suite also matches on
function test_choose_glyphs_picks_a_whole_set() {
  { (
    _HI_ASCII=1
    _hi_choose_glyphs
    [ "$_HI_MARK_OK" = "+" ] && [ "$_HI_MARK_NO" = x ] &&
      [ "$_HI_GLYPH_AHEAD" = "^" ]
  ) && (
    _HI_ASCII=0
    _hi_choose_glyphs
    [ "$_HI_MARK_OK" = "✓" ] && [ "$_HI_MARK_NO" = "✗" ] &&
      [ "$_HI_GLYPH_AHEAD" = "↑" ]
  ); } || _hi_why _HI_MARK_OK _HI_MARK_NO _HI_GLYPH_AHEAD
}

function test_sanitize_leaves_plain_text_alone() {
  local out
  _hi_sanitize_var out "hello world"
  [ "$out" = "hello world" ] || _hi_why out
}

function test_sanitize_strips_control_chars_and_backslashes() {
  local out
  _hi_sanitize_var out $'a\tb\\c'
  [ "$out" = "abc" ] || _hi_why out
}

# https://no-color.org - the convention is "non-empty means off", so both the
# per-call gates and the source-time palette blanking are asserted, the second
# through a fresh bash: this shell sourced core.sh before the variable was set.
function test_no_color_blanks_the_escape() {
  [ -z "$(NO_COLOR=1 _hi_color_escape red)" ] || _hi_why
}

function test_no_color_beats_the_terminal() {
  ! NO_COLOR=1 TERM=xterm-256color _hi_has_color || _hi_why
}

function test_no_color_empty_means_on() {
  { [ -n "$(NO_COLOR='' _hi_color_escape red)" ] &&
    NO_COLOR='' TERM=xterm-256color _hi_has_color; } || _hi_why
}

function test_no_color_blanks_the_palette_at_source_time() {
  local out
  out="$(env NO_COLOR=1 _HI_HOME="$_HI_HOME" bash -c \
    '. "$_HI_HOME/say-hi/common/core.sh"; printf "%s" "$NC$RED$BRCYAN"')"
  [ -z "$out" ] || _hi_why out
}

# _HI_COLOR_SCHEME (GLOSSARY: HI.50): the twelve names render as a
# truecolor scheme only when the terminal says it can. Every case pins
# _HI_TRUECOLOR rather than reading the developer's own COLORTERM.
function test_has_truecolor_reads_colorterm() {
  _HI_TRUECOLOR="" COLORTERM=truecolor _hi_has_truecolor || _hi_why || return 1
  _HI_TRUECOLOR="" COLORTERM=24bit _hi_has_truecolor || _hi_why || return 1
  ! _HI_TRUECOLOR="" COLORTERM=xterm-256color _hi_has_truecolor || _hi_why || return 1
  ! _HI_TRUECOLOR="" COLORTERM="" _hi_has_truecolor || _hi_why || return 1
  [ "$(_HI_TRUECOLOR="" COLORTERM=truecolor _hi_truecolor_flag)" = 1 ] &&
    [ "$(_HI_TRUECOLOR="" COLORTERM="" _hi_truecolor_flag)" = 0 ] || _hi_why
}

function test_truecolor_override_wins_both_ways() {
  _HI_TRUECOLOR=1 COLORTERM="" _hi_has_truecolor || _hi_why || return 1
  ! _HI_TRUECOLOR=0 COLORTERM=truecolor _hi_has_truecolor || _hi_why
}

# one SGR: the 16-color pair first, the 24-bit triple after it, the bold bit
# kept for the bright six - so every reader of the leading escape still
# finds what it found before
function test_scheme_escape_keeps_the_16_color_prefix() {
  local red brred
  _HI_COLOR_SCHEME="$_HI_TEST_L24" _HI_TRUECOLOR=1 _hi_color_escape_var red red
  _HI_COLOR_SCHEME="$_HI_TEST_L24" _HI_TRUECOLOR=1 _hi_color_escape_var brred brred
  [ "$red" = '\e[0;31;38;2;243;139;168m' ] && [ "$brred" = '\e[1;31;38;2;243;119;153m' ] &&
    [ "$(_HI_COLOR_SCHEME="$_HI_TEST_L24" _HI_TRUECOLOR=1 _hi_color_escape red)" = $'\e[0;31;38;2;243;139;168m' ] || _hi_why red brred
}

function test_scheme_is_inert_without_truecolor() {
  local out
  _HI_COLOR_SCHEME="$_HI_TEST_L24" _HI_TRUECOLOR=0 _hi_color_escape_var out red
  [ "$out" = '\e[0;31m' ] || _hi_why out || return 1
  _HI_COLOR_SCHEME="$_HI_TEST_L24" _HI_TRUECOLOR=0 _hi_color_hex out red
  [ -z "$out" ] || _hi_why out
}

function test_scheme_is_inert_under_no_color() {
  [ -z "$(NO_COLOR=1 _HI_COLOR_SCHEME="$_HI_TEST_L24" _HI_TRUECOLOR=1 _hi_color_escape red)" ] || _hi_why
}

function test_unknown_scheme_falls_back_to_16_color() {
  local out
  _HI_COLOR_SCHEME=solarized _HI_TRUECOLOR=1 _hi_color_escape_var out brcyan
  [ "$out" = '\e[1;36m' ] || _hi_why out
}

function test_scheme_hex_is_six_hex_digits_for_every_slot() {
  local scheme i hex
  for scheme in "$_HI_TEST_L24" "$_HI_TEST_L48"; do
    i=0
    while [ "$i" -lt "${#_HI_COLOR_NAMES[@]}" ]; do
      _HI_COLOR_SCHEME="$scheme" _HI_TRUECOLOR=1 _hi_scheme_hex hex "$i"
      [ "${#hex}" -eq 6 ] || _hi_why hex || return 1
      case "$hex" in *[!0-9a-f]*) _hi_why hex || return 1 ;; esac
      i=$((i + 1))
    done
  done
}

# the exported palette and the by-name escape share one primitive, so a
# fresh shell under a scheme assigns $RED exactly what _hi_color_escape red
# prints - preview.sh's reverse map depends on that
function test_palette_vars_agree_with_color_escape_under_a_scheme() {
  local out
  out="$(env _HI_COLOR_SCHEME="$_HI_TEST_L24" _HI_TRUECOLOR=1 _HI_HOME="$_HI_HOME" bash -c '
    . "$_HI_HOME/say-hi/common/core.sh"
    . "$_HI_HOME/say-hi/scripts/lib.sh"
    for n in RED GREEN YELLOW BLUE PURPLE CYAN BRRED BRGREEN BRYELLOW BRBLUE BRPURPLE BRCYAN; do
      eval "v=\$$n"; printf "%b" "$v"
    done | od -An -c | tr -d " \n"
    printf "|"
    for n in "${_HI_COLOR_NAMES[@]:0:12}"; do _hi_color_escape "$n"; done | od -An -c | tr -d " \n"')"
  [ -n "${out%%|*}" ] && [ "${out%%|*}" = "${out#*|}" ] && [[ "${out%%|*}" == *"38;2;"* ]] || _hi_why out
}

# the hash is untouched by a scheme: a name, never a hex
function test_hash_color_ignores_the_scheme() {
  [ "$(_HI_COLOR_SCHEME="$_HI_TEST_L24" _HI_TRUECOLOR=1 _hi_hash_color prod-db)" = "$(_hi_hash_color prod-db)" ] || _hi_why
}

# _HI_TEST_L24/_HI_TEST_L48: tests/lib/fixtures.sh, shared with header_test.sh

function test_scheme_words_counts_a_list() {
  local n
  _HI_COLOR_SCHEME="$_HI_TEST_L24" _hi_scheme_words n
  [ "$n" -eq 24 ] || _hi_why n || return 1
  _HI_COLOR_SCHEME="$_HI_TEST_L48" _hi_scheme_words n
  [ "$n" -eq 48 ] || _hi_why n || return 1
  _HI_COLOR_SCHEME="F38BA8 ${_HI_TEST_L24#* }" _hi_scheme_words n
  [ "$n" -eq 24 ] || _hi_why n || return 1
  # twelve words: not a scheme
  _HI_COLOR_SCHEME="${_HI_TEST_L24% * * * * * * * * * * * *}" _hi_scheme_words n
  [ "$n" -eq 0 ] || _hi_why n || return 1
  _HI_COLOR_SCHEME=solarized _hi_scheme_words n
  [ "$n" -eq 0 ] || _hi_why n || return 1
  _HI_COLOR_SCHEME="" _hi_scheme_words n
  [ "$n" -eq 0 ] || _hi_why n || return 1
  _HI_COLOR_SCHEME="$_HI_TEST_L24 cd3131" _hi_scheme_words n
  [ "$n" -eq 0 ] || _hi_why n || return 1
  _HI_COLOR_SCHEME="zzzzzz ${_HI_TEST_L24#* }" _hi_scheme_words n
  [ "$n" -eq 0 ] || _hi_why n || return 1
  _HI_COLOR_SCHEME="$(printf '%s' "$_HI_TEST_L24" | tr ' ' ',')" _hi_scheme_words n
  [ "$n" -eq 0 ] || _hi_why n
}

# the first word paints red, with the 16-color half in front as ever
function test_scheme_list_of_twenty_four_renders() {
  local out
  _HI_COLOR_SCHEME="$_HI_TEST_L24" _HI_TRUECOLOR=1 _hi_color_escape_var out red
  [ "$out" = '\e[0;31;38;2;243;139;168m' ] || _hi_why out || return 1
  _HI_COLOR_SCHEME="F38BA8 ${_HI_TEST_L24#* }" _HI_TRUECOLOR=1 _hi_color_escape_var out red
  [ "$out" = '\e[0;31;38;2;243;139;168m' ] || _hi_why out
}

# slot 24 is red again: the second bank under a 48-word list, the first bank
# under everything else - and always red's 16-color half
function test_scheme_second_bank_folds_without_48_words() {
  local a b c
  _HI_COLOR_SCHEME="$_HI_TEST_L48" _HI_TRUECOLOR=1 _hi_color_escape_at a 24
  _HI_COLOR_SCHEME="$_HI_TEST_L24" _HI_TRUECOLOR=1 _hi_color_escape_at b 24
  _HI_COLOR_SCHEME=solarized _HI_TRUECOLOR=1 _hi_color_escape_at c 24
  [ "$a" = '\e[0;31;38;2;205;49;49m' ] && [ "$b" = '\e[0;31;38;2;243;139;168m' ] && [ "$c" = '\e[0;31m' ] || _hi_why a b c
}

# a list that is not one is an unknown scheme: 16 colors for the sixteen's
# names, no complaint here
function test_scheme_bad_list_falls_back_to_16_color() {
  local out
  _HI_COLOR_SCHEME="$_HI_TEST_L24 cd3131" _HI_TRUECOLOR=1 _hi_color_escape_var out red
  [ "$out" = '\e[0;31m' ] || _hi_why out || return 1
  _HI_COLOR_SCHEME="zzzzzz ${_HI_TEST_L24#* }" _HI_TRUECOLOR=1 _hi_color_escape_var out brcyan
  [ "$out" = '\e[1;36m' ] || _hi_why out
}

# scripts/lib.sh's three readers of the setting, tested beside the primitive
# they wrap (test_lib.sh sources lib.sh)
function test_scheme_ok_takes_names_and_lists() {
  _hi_scheme_ok "$_HI_TEST_L24" && _hi_scheme_ok "$_HI_TEST_L48" || _hi_why || return 1
  # hi ships no named schemes, so a name is just a word
  ! _hi_scheme_ok catppuccin || _hi_why || return 1
  ! _hi_scheme_ok solarized || _hi_why || return 1
  ! _hi_scheme_ok custom || _hi_why || return 1
  ! _hi_scheme_ok "$_HI_TEST_L24 cd3131" || _hi_why || return 1
  ! _hi_scheme_ok "" || _hi_why
}

# _hi_ramp_ok is the one judge of $_HI_PACKAGES_PALETTE - header.sh falls
# back on it per render, doctor.sh and the previews report off it - so the
# grammar is pinned here, beside the vocabulary it checks against.
function test_ramp_ok_takes_eight_color_names() {
  _hi_ramp_ok "$_HI_TEST_RAMP" || _hi_why || return 1
  _hi_ramp_ok "cyan green brcyan brgreen blue magenta bryellow brred" || _hi_why || return 1
  # the twelve extras are names too
  _hi_ramp_ok "orange pink teal lime violet salmon gold sky" || _hi_why || return 1
  ! _hi_ramp_ok "" || _hi_why || return 1
  ! _hi_ramp_ok cool || _hi_why || return 1
  ! _hi_ramp_ok "cyan green brcyan brgreen" || _hi_why || return 1
  ! _hi_ramp_ok "$_HI_TEST_RAMP brred" || _hi_why || return 1
  ! _hi_ramp_ok "cyan green brcyan brgreen blue magenta bryellow nosuch" || _hi_why || return 1
  # a doubled space leaves an empty word, which no name matches
  ! _hi_ramp_ok "cyan  green brcyan brgreen blue magenta bryellow brred" || _hi_why || return 1
  # every byte a name cannot hold is refused before the walk, so nothing here
  # can glob against the working directory or reach a `case` as a pattern
  ! _hi_ramp_ok "* * * * * * * *" || _hi_why || return 1
  ! _hi_ramp_ok "cyan green brcyan brgreen blue magenta bryellow BRRED" || _hi_why || return 1
  ! _hi_ramp_ok "cyan;green brcyan brgreen blue magenta bryellow brred" || _hi_why
}

# a .d directory's allow list (HI.58): plain names ride, and a dotfile, a
# backup, an editor's leftovers, or a name no shell word could be never do
function test_dir_member_ok_takes_plain_names_only() {
  local n
  for n in 10-lang lang box_2 init.fish A1; do
    _hi_dir_member_ok "$n" || _hi_why n || return 1
  done
  for n in '' .10-lang.swp 10-lang~ 10-lang.bak x.orig x.rej x.tmp -x '10 lang' 'a*'; do
    ! _hi_dir_member_ok "$n" || _hi_why n || return 1
  done
}

# _hi_flag_word's three answers, one home now for hi.sh and scripts/ alike:
# a joined word (0), the next argument (2, the caller shifts again), and a
# bare flag with nothing after it (1, the variable untouched)
function test_flag_word_takes_joined_next_or_nothing() {
  local w="" rc=0
  _hi_flag_word w --use=docker extra && [ "$w" = docker ] || _hi_why w || return 1
  _hi_flag_word w --use podman || rc=$?
  [ "$rc" -eq 2 ] && [ "$w" = podman ] || _hi_why rc w || return 1
  rc=0
  _hi_flag_word w --use || rc=$?
  [ "$rc" -eq 1 ] && [ "$w" = podman ] || _hi_why rc w
}

# ...and the label the previews and hi --doctor print for it, the three
# shapes _hi_scheme_label prints for a scheme
function test_ramp_label_names_every_shape() {
  local l
  _HI_PACKAGES_PALETTE="" _hi_ramp_label l
  [ "$l" = default ] || _hi_why l || return 1
  _HI_PACKAGES_PALETTE="$_HI_TEST_RAMP" _hi_ramp_label l
  [ "$l" = custom ] || _hi_why l || return 1
  _HI_PACKAGES_PALETTE=mono _hi_ramp_label l
  [ "$l" = "mono (ignored - not eight color names)" ] || _hi_why l
}

function test_scheme_label_names_every_shape() {
  local l
  _HI_COLOR_SCHEME="" _hi_scheme_label l
  [ "$l" = default ] || _hi_why l || return 1
  _HI_COLOR_SCHEME="$_HI_TEST_L24" _hi_scheme_label l
  [ "$l" = "custom (24)" ] || _hi_why l || return 1
  _HI_COLOR_SCHEME="$_HI_TEST_L48" _hi_scheme_label l
  [ "$l" = "custom (48)" ] || _hi_why l || return 1
  _HI_COLOR_SCHEME=solarized _hi_scheme_label l
  [ "$l" = "solarized (ignored - not a scheme)" ] || _hi_why l
}

# _hi_cecho's %b is for the palette; the text goes through %s. What it prints
# is a target's or ssh's words as often as hi's - _hi_report_failure feeds a
# connect errlog through it - so a backslash a target wrote has to come out a
# backslash, and a literal `\e]0;` in a banner has to stay text rather than
# retitle the client's terminal. The colors, still '\e' strings, still expand.
function test_cecho_prints_the_text_verbatim() {
  local in='C:\Users\new \e]0;x\a %s' out
  out="$(_hi_cecho "$in" "" 1)"
  [ "$out" = "$in$(_hi_rendered "$NC")" ] || _hi_why out in
}

function test_cecho_still_expands_the_palette() {
  local out
  out="$(_hi_cecho x "$RED" 1)"
  [ "$out" = "$(_hi_rendered "${RED}x$NC")" ] || _hi_why out
}

function test_hash_color_matches_hand_computed_bucket() {
  # ord('a')=97, 97 % 24 == 1 -> _HI_COLOR_NAMES[1] == green
  [ "$(_hi_hash_color a)" = "green" ] || _hi_why || return 1
  # ord('a')+ord('b')=97+98=195, 195 % 24 == 3 -> _HI_COLOR_NAMES[3] == blue
  [ "$(_hi_hash_color ab)" = "blue" ] || _hi_why || return 1
  # ord('m')=109, 109 % 24 == 13 -> the extras are in the hash's range
  [ "$(_hi_hash_color m)" = "pink" ] || _hi_why
}

# The twelve extras: a 16-color pair of their own (orange is bright yellow
# there), a built-in hex under no scheme on a truecolor terminal, the
# scheme's word under a scheme, and the base name for %F{}/set_color.
function test_extra_names_render_by_fallback_and_hex() {
  local out
  _HI_COLOR_SCHEME="" _HI_TRUECOLOR=0 _hi_color_escape_var out orange
  [ "$out" = '\e[1;33m' ] || _hi_why out || return 1
  _HI_COLOR_SCHEME="" _HI_TRUECOLOR=1 _hi_color_escape_var out orange
  [ "$out" = '\e[1;33;38;2;255;140;0m' ] || _hi_why out || return 1
  _HI_COLOR_SCHEME="" _HI_TRUECOLOR=1 _hi_color_escape_var out red
  [ "$out" = '\e[0;31m' ] || _hi_why out || return 1
  _HI_COLOR_SCHEME=solarized _HI_TRUECOLOR=1 _hi_color_escape_var out teal
  [ "$out" = '\e[0;36;38;2;32;178;170m' ] || _hi_why out || return 1
  # a list whose thirteenth word is not the built-in orange, so the assertion
  # tells "the list's word for an extra" from "the built-in one"
  _HI_COLOR_SCHEME="$_HI_TEST_L12 fd971f${_HI_TEST_L24#"$_HI_TEST_L12 ff8c00"}" _HI_TRUECOLOR=1 _hi_color_escape_var out orange
  [ "$out" = '\e[1;33;38;2;253;151;31m' ] || _hi_why out || return 1
  _HI_COLOR_SCHEME="$_HI_TEST_L48" _HI_TRUECOLOR=1 _hi_color_escape_at out 36
  [ "$out" = '\e[1;33;38;2;224;123;57m' ] || _hi_why out
}

function test_color_base_names_the_16_color_half() {
  local b
  _hi_color_base b orange
  [ "$b" = bryellow ] || _hi_why b || return 1
  _hi_color_base b teal
  [ "$b" = cyan ] || _hi_why b || return 1
  _hi_color_base b lavender
  [ "$b" = brmagenta ] || _hi_why b || return 1
  _hi_color_base b brred
  [ "$b" = brred ] || _hi_why b || return 1
  _hi_color_base b nosuch
  [ "$b" = nosuch ] || _hi_why b
}

# every extra has a hex of its own in the default table and in a list of the
# user's own, none repeats one of the first twelve's within a table, and the
# fallback string covers every slot
function test_extra_names_have_a_hex_in_every_table() {
  local scheme i j hex other
  [ "${#_HI_COLOR_FALLBACK}" -eq $((${#_HI_COLOR_NAMES[@]} * 3 - 1)) ] || _hi_why _HI_COLOR_FALLBACK _HI_COLOR_NAMES || return 1
  for scheme in "" "$_HI_TEST_L24" "$_HI_TEST_L48"; do
    i=12
    while [ "$i" -lt 24 ]; do
      _HI_COLOR_SCHEME="$scheme" _HI_TRUECOLOR=1 _hi_scheme_hex hex "$i"
      [ "${#hex}" -eq 6 ] || _hi_why hex || return 1
      j=0
      while [ "$j" -lt 12 ]; do
        _HI_COLOR_SCHEME="$scheme" _HI_TRUECOLOR=1 _hi_scheme_hex other "$j"
        [ "$hex" != "$other" ] || _hi_why hex other || return 1
        j=$((j + 1))
      done
      i=$((i + 1))
    done
  done
}

# fish is handed the base name beside the hex: set_color knows no orange
function test_prompt_colors_hand_fish_the_base_name() {
  local out
  out="$(_HI_USER_COLOR=orange _HI_HOST_COLOR=red _HI_TRUECOLOR=1 _hi_prompt_colors)"
  [ "$out" = $'ff8c00 bryellow\nred' ] || _hi_why out
}

function test_override_color_exact_match() {
  local colors="$_HI_WORKDIR/colors.exact"
  printf '[username]\nalice = "red"\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _hi_override_color username alice)" = "red" ] || _hi_why colors
}

function test_override_color_no_match_fails() {
  local colors="$_HI_WORKDIR/colors.nomatch"
  printf '[username]\nalice = "red"\n' >"$colors"
  ! _HI_COLORS="$colors" _hi_override_color username bob || _hi_why colors
}

function test_override_color_localuser_special_case() {
  local colors="$_HI_WORKDIR/colors.localuser"
  printf '[username]\nLOCALUSER = "cyan"\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _HI_LOCAL_USER=testuser _hi_override_color username testuser)" = "cyan" ] || _hi_why colors
}

function test_override_color_localhostname_special_case() {
  local colors="$_HI_WORKDIR/colors.localhost"
  printf '[hostname]\nLOCALHOSTNAME = "magenta"\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _HI_LOCAL_HOSTNAME=testhost _hi_override_color hostname testhost)" = "magenta" ] || _hi_why colors
}

# A row's optional fourth column - that pin's own 24-bit color. It comes back
# joined to the name, "<color>#<rrggbb>", from every reader of the file: the
# exact pin, the pattern row, and the hosttag alike.
function test_pin_hex_joins_the_name() {
  local colors="$_HI_WORKDIR/colors.hex"
  printf '[username]\nalice = "red 3ba55d"\n[hostname]\n"10.0.1.*" = "blue 102030"\n[hosttag]\nprod = "brred ff5f5f"\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _hi_colors_lookup username alice)" = 'red#3ba55d' ] || _hi_why colors || return 1
  [ "$(_HI_COLORS="$colors" _hi_colors_pattern hostname 10.0.1.7)" = 'blue#102030' ] || _hi_why colors || return 1
  [ "$(_HI_COLORS="$colors" _hi_override_color hosttag prod)" = 'brred#ff5f5f' ] || _hi_why colors || return 1
  [ "$(_HI_COLORS="$colors" _hi_resolve_color username alice)" = 'red#3ba55d' ] || _hi_why colors
}

# a leading `#` is how a hex is usually written down, and the digits are
# read in either case
function test_pin_hex_accepts_a_leading_hash_and_either_case() {
  local colors="$_HI_WORKDIR/colors.hexhash"
  printf '[username]\nalice = "red #FF00AA"\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _hi_colors_lookup username alice)" = 'red#FF00AA' ] || _hi_why colors
}

# The pinned hex is the escape's 24-bit half and outranks the scheme, while
# the 16-color pair stays the third column's - which is all a terminal
# without truecolor is given.
function test_pin_hex_paints_the_escape_over_the_scheme() {
  local out
  _HI_COLOR_SCHEME="$_HI_TEST_L24" _HI_TRUECOLOR=1 _hi_color_escape_var out 'red#3ba55d'
  [ "$out" = '\e[0;31;38;2;59;165;93m' ] || _hi_why out || return 1
  _HI_COLOR_SCHEME="" _HI_TRUECOLOR=1 _hi_color_escape_var out 'brgreen#3ba55d'
  [ "$out" = '\e[1;32;38;2;59;165;93m' ] || _hi_why out || return 1
  _HI_COLOR_SCHEME="$_HI_TEST_L24" _HI_TRUECOLOR=0 _hi_color_escape_var out 'red#3ba55d'
  [ "$out" = '\e[0;31m' ] || _hi_why out || return 1
  [ -z "$(NO_COLOR=1 _HI_TRUECOLOR=1 _hi_color_escape 'red#3ba55d')" ] || _hi_why || return 1
  # the name half still has to be one of the twenty-four: it is the escape's
  # 16-color half, so an unknown name resets exactly as it does without a hex
  _HI_TRUECOLOR=1 _hi_color_escape_var out 'nosuch#3ba55d'
  [ "$out" = "$NC" ] || _hi_why out
}

# zsh's %F{#..} and fish's set_color take the hex; both take the base name,
# which is the third column's and never carries the pin
function test_pin_hex_reaches_the_hex_and_base_readers() {
  local out
  _HI_COLOR_SCHEME="$_HI_TEST_L24" _HI_TRUECOLOR=1 _hi_color_hex out 'red#3ba55d'
  [ "$out" = '3ba55d' ] || _hi_why out || return 1
  _HI_COLOR_SCHEME="$_HI_TEST_L24" _HI_TRUECOLOR=0 _hi_color_hex out 'red#3ba55d'
  [ -z "$out" ] || _hi_why out || return 1
  _hi_color_base out 'orange#3ba55d'
  [ "$out" = bryellow ] || _hi_why out || return 1
  out="$(_HI_USER_COLOR='orange#fd971f' _HI_HOST_COLOR=red _HI_TRUECOLOR=1 _hi_prompt_colors)"
  [ "$out" = $'fd971f bryellow\nred' ] || _hi_why out
}

# _hi_toml_rows_probe - _hi_toml_row over the lines a data file can hold, a
# line each as "<status>|<key>|<value>": bare and quoted keys, a string, an
# array, padding, a comment behind the value, a # inside a string, and what
# is no row at all
function _hi_toml_rows_probe() {
  local l k v
  while IFS= read -r l; do
    k="" v=""
    _hi_toml_row "$l" k v
    printf '%s|%s|%s\n' "$?" "$k" "$v"
  done <<'ROWS'
bat = ["batcat", "ccat"]
direnv = []
  "g++"   =   [ "c++","clang++" ]   # a note
prod-db = "brred ff5f5f"
"10.0.1.*" = "red" # a subnet
tagged = "red #ff0000"
# a comment
[table]
[table.required]
bare words
old,row,red
n = 1
t = true
s = "unclosed
= "no key"
ROWS
}

function test_toml_row_reads_the_subset() {
  local want
  want="0|bat|batcat,ccat
0|direnv|
0|g++|c++,clang++
0|prod-db|brred ff5f5f
0|10.0.1.*|red
0|tagged|red #ff0000
1||
1||
1||
1||
1||
1||
1||
1||
1||"
  [ "$(_hi_toml_rows_probe)" = "$want" ] || _hi_because "$(_hi_toml_rows_probe)"
}

function test_zsh_toml_row_agrees_with_bash() {
  local zsh_out
  zsh_out="$(zsh -c "source '$_HI_ROOT/common/core.sh'; $(declare -f _hi_toml_rows_probe); _hi_toml_rows_probe")"
  [ "$zsh_out" = "$(_hi_toml_rows_probe)" ] || _hi_because "$zsh_out"
}

# A colors file is hand-written: a typo in the hex field costs the row its
# hex, never its color.
function test_pin_hex_ignores_a_malformed_hex_field() {
  local colors="$_HI_WORKDIR/colors.hexbad"
  printf '[username]\na = "red zzz"\nb = "red 12345"\nc = "red 12345g"\ne = "red"\nf = "red #"\n' >"$colors"
  local name
  for name in a b c e f; do
    [ "$(_HI_COLORS="$colors" _hi_colors_lookup username "$name")" = red ] || _hi_why colors name || return 1
  done
}

# anything after the hex is a note, not part of it, in the string or behind it
function test_pin_hex_ignores_trailing_text() {
  local colors="$_HI_WORKDIR/colors.hextail"
  printf '[username]\nd = "red 3ba55d the office box"\ng = "red #3BA55D" # a note\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _hi_colors_lookup username d)" = 'red#3ba55d' ] &&
    [ "$(_HI_COLORS="$colors" _hi_colors_lookup username g)" = 'red#3BA55D' ] || _hi_why colors
}

# A [type] line scopes every row under it: one name pinned under two types
# answers each type with its own color, a type named twice, which TOML
# would refuse, is read both times, and a row above the first table belongs
# to no type at all
function test_colors_rows_are_scoped_to_their_section() {
  local colors="$_HI_WORKDIR/colors.sections"
  printf 'shared = "yellow"\n[hostname]\nshared = "red"\n[username] # a note\nshared = "blue"\n[hostname]\nlate = "green"\n' >"$colors"
  { [ "$(_HI_COLORS="$colors" _hi_colors_lookup hostname shared)" = red ] &&
    [ "$(_HI_COLORS="$colors" _hi_colors_lookup username shared)" = blue ] &&
    [ "$(_HI_COLORS="$colors" _hi_colors_lookup hostname late)" = green ] &&
    ! _HI_COLORS="$colors" _hi_colors_lookup hosttag shared; } || _hi_why colors
}

# comments and blank lines are skipped wherever they sit, indented and padded
# rows read the same, a name in quotes is the name, and the rows of the two
# formats before this one pin nothing
function test_colors_skips_comments_blanks_and_old_rows() {
  local colors="$_HI_WORKDIR/colors.skips"
  printf '# a note\n\n[hostname]\n  # an indented note\n\n  box   =   "cyan"\n"a.b"="red"\nhostname,old,red\nolder blue\n' >"$colors"
  { [ "$(_HI_COLORS="$colors" _hi_colors_lookup hostname box)" = cyan ] &&
    [ "$(_HI_COLORS="$colors" _hi_colors_lookup hostname a.b)" = red ] &&
    ! _HI_COLORS="$colors" _hi_colors_lookup hostname old &&
    ! _HI_COLORS="$colors" _hi_colors_lookup hostname older &&
    ! _HI_COLORS="$colors" _hi_colors_lookup hostname '#'; } || _hi_why colors
}

# a pattern row is a hostname glob: the pattern reader matches it, the exact
# reader does not, and an exact row is never a pattern
function test_colors_pattern_row_is_a_glob() {
  local colors="$_HI_WORKDIR/colors.pattern"
  printf '[hostname]\n"web-?" = "blue"\nweb-1 = "red"\n' >"$colors"
  { [ "$(_HI_COLORS="$colors" _hi_colors_pattern hostname web-2)" = blue ] &&
    [ "$(_HI_COLORS="$colors" _hi_colors_pattern hostname web-1)" = blue ] &&
    [ "$(_HI_COLORS="$colors" _hi_colors_lookup hostname web-1)" = red ] &&
    ! _HI_COLORS="$colors" _hi_colors_lookup hostname web-2 &&
    ! _HI_COLORS="$colors" _hi_colors_pattern hostname web-10; } || _hi_why colors
}

# _hi_colors_scan reuses the rows a caller's batch loaded once - a file
# changed after the load goes unseen - and without a batch reads the file
# itself, into rows of its own that leave the caller's alone
function _hi_colors_batch_probe() {
  local _HI_COLORS_BATCH=1 _HI_COLORS_ROWS="" batched unbatched
  _hi_colors_load
  printf '[username]\nalice = "blue"\n' >"$_HI_COLORS"
  _hi_colors_scan username alice '' batched
  _HI_COLORS_BATCH=0
  _hi_colors_scan username alice '' unbatched
  printf '%s|%s|%s' "$batched" "$unbatched" "${_HI_COLORS_ROWS//$'\x1f'/,}"
}

function test_colors_scan_reads_a_batch_once() {
  local colors="$_HI_WORKDIR/colors.batch" out
  printf '[username]\nalice = "red"\n' >"$colors"
  out="$(_HI_COLORS="$colors" _hi_colors_batch_probe)"
  [ "$out" = "red|blue|username,alice,red," ] || _hi_because "batched|unbatched|rows: $out"
}

function test_zsh_pin_hex_agrees_with_bash() {
  local colors="$_HI_WORKDIR/colors.hexzsh"
  printf '[username]\nalice = "orange 3ba55d"\n' >"$colors"
  _hi_shell_agrees "export _HI_COLORS='$colors' _HI_TRUECOLOR=1
    c=\"\$(_hi_colors_lookup username alice)\"
    _hi_color_escape_var e \"\$c\"; _hi_color_hex h \"\$c\"; _hi_color_base b \"\$c\"
    printf '%s|%s|%s|%s' \"\$c\" \"\$e\" \"\$h\" \"\$b\"" || _hi_why colors c e h
}

# The one ssh_config every tag case reads. Built once by run_core_tests, and
# $_HI_SSH_TAG_FIXTURE holds the path from then on - the zsh-agreement cases
# reach the same file through _hi_in_shell's constant _HI_SSH_CONFIG.
_HI_SSH_TAG_FIXTURE=""

function _hi_ssh_tag_fixture() {
  local f="$_HI_WORKDIR/ssh_config"
  cat >"$f" <<'EOF'
# Tags: prod, web
Host myhost
    HostName 1.2.3.4

Host untaggedhost
    HostName 5.6.7.8

# Tags= dev
Host devhost otheralias
    HostName 9.9.9.9

# Tags: lower
host lowerhost
    HostName 10.10.10.10

# Tags: prod
Host prod-*
    HostName 11.11.11.11

# Tags: staging
Match host staging-*, staging2-*
    HostName 12.12.12.12

Host wilduntagged-*
    HostName 13.13.13.13

# Tags: excluded
Host web-* !web-99
    HostName 14.14.14.14

# Tags: bastion
Match host bastion-* user deploy
    HostName 15.15.15.15

# Tags: nobody
Match user nobody
    HostName 16.16.16.16

Host afternobody
    HostName 17.17.17.17

# Tags: canary
Match host canary-* localuser build
    HostName 18.18.18.18

# Tags: robot
Match host robot-* exec "true"
    HostName 19.19.19.19

# Tags: lastword
Match host lastcall-* canonical final
    HostName 20.20.20.20
EOF
  printf '%s' "$f"
}

# common/zsh.zsh sources core.sh directly, so its functions run in zsh too - and
# three zsh differences each break something silently: `${name:i:1}` is a
# history modifier there, $BASH_REMATCH is never populated, and an unquoted
# `$var` is not word-split. All three are invisible to a bash-only suite, so
# these cases run the real functions in a real zsh and compare with bash's
# answer; the point is that the two agree.

function _hi_in_shell() {
  local shell="$1" script="$2"
  env _HI_HOME="$_HI_HOME" _HI_SSH_CONFIG="$_HI_WORKDIR/ssh_config" \
    "$shell" -c "source \"\$_HI_HOME/say-hi/common/core.sh\"; $script" 2>&1
}

function _hi_shell_agrees() {
  local script="$1" a b
  a="$(_hi_in_shell bash "$script")"
  b="$(_hi_in_shell zsh "$script")"
  [ -n "$a" ] && [ "$a" = "$b" ]
}

# _hi_core_begin - what every part of this suite starts from, and the tally
function _hi_core_begin() {
  _hi_workdir sharedtest
  _HI_SSH_TAG_FIXTURE="$(_hi_ssh_tag_fixture)"
  _hi_suite_begin
}

function run_core_tests() {
  _hi_core_begin

  _hi_h1 "Testing common/core.sh"

  _hi_h2 "Testing: _hi_use_ascii / _hi_choose_glyphs"
  _hi_check "C locale means ASCII" test_use_ascii_in_a_c_locale
  _hi_check "UTF-8 keeps the glyphs" test_use_ascii_not_under_utf8
  _hi_check "_HI_ASCII beats the locale" test_use_ascii_override_beats_the_locale
  _hi_check "The chooser swaps whole sets" test_choose_glyphs_picks_a_whole_set

  _hi_h2 "Testing: _hi_sanitize_var"
  _hi_check "Leaves plain text alone" test_sanitize_leaves_plain_text_alone
  _hi_check "Strips control chars and backslashes" test_sanitize_strips_control_chars_and_backslashes

  _hi_h2 "Testing: _hi_color_escape"
  _hi_check_eq "Red matches \$RED" "$(_hi_rendered "$RED")" _hi_color_escape red
  _hi_check_eq "Brcyan matches \$BRCYAN" "$(_hi_rendered "$BRCYAN")" _hi_color_escape brcyan
  _hi_check_eq "Unknown name resets" "$(_hi_rendered "$NC")" _hi_color_escape not-a-real-color

  _hi_h2 "Testing: NO_COLOR"
  _hi_check "Blanks the escape" test_no_color_blanks_the_escape
  _hi_check "Beats the terminal's yes" test_no_color_beats_the_terminal
  _hi_check "Empty means on (non-empty rule)" test_no_color_empty_means_on
  _hi_check "Blanks the palette at source time" test_no_color_blanks_the_palette_at_source_time

  _hi_h2 "Testing: _HI_COLOR_SCHEME (HI.50)"
  _hi_check "_hi_has_truecolor reads COLORTERM" test_has_truecolor_reads_colorterm
  _hi_check "_HI_TRUECOLOR overrides both ways" test_truecolor_override_wins_both_ways
  _hi_check "A scheme escape keeps the 16-color prefix" test_scheme_escape_keeps_the_16_color_prefix
  _hi_check "Inert without truecolor" test_scheme_is_inert_without_truecolor
  _hi_check "Inert under NO_COLOR" test_scheme_is_inert_under_no_color
  _hi_check "An unknown scheme falls back to 16 colors" test_unknown_scheme_falls_back_to_16_color
  _hi_check "Every slot of a list is six hex digits" test_scheme_hex_is_six_hex_digits_for_every_slot
  _hi_check "The palette agrees with _hi_color_escape under a scheme" test_palette_vars_agree_with_color_escape_under_a_scheme
  _hi_check "The hash ignores the scheme" test_hash_color_ignores_the_scheme
  _hi_check "_hi_scheme_words counts a 24/48-word list" test_scheme_words_counts_a_list
  _hi_check "The extras render by fallback pair and hex" test_extra_names_render_by_fallback_and_hex
  _hi_check "_hi_color_base names the 16-color half" test_color_base_names_the_16_color_half
  _hi_check "Every extra has its own hex in every table" test_extra_names_have_a_hex_in_every_table
  _hi_check "fish gets the base name beside the hex" test_prompt_colors_hand_fish_the_base_name
  _hi_check "A 24-word list renders" test_scheme_list_of_twenty_four_renders
  _hi_check "Slots 24-47 fold to the first bank without 48 words" test_scheme_second_bank_folds_without_48_words
  _hi_check "A malformed list falls back to 16 colors" test_scheme_bad_list_falls_back_to_16_color
  _hi_check "_hi_scheme_ok takes only lists" test_scheme_ok_takes_names_and_lists
  _hi_check "_hi_scheme_label names every shape" test_scheme_label_names_every_shape
  _hi_check "_hi_ramp_ok takes eight color names" test_ramp_ok_takes_eight_color_names
  _hi_check "_hi_dir_member_ok takes plain names only" test_dir_member_ok_takes_plain_names_only
  _hi_check "_hi_flag_word: joined, next, or nothing" test_flag_word_takes_joined_next_or_nothing
  _hi_check "_hi_ramp_label names every shape" test_ramp_label_names_every_shape

  _hi_h2 "Testing: _hi_cecho"
  _hi_check "Prints the text verbatim" test_cecho_prints_the_text_verbatim
  _hi_check "...and still expands the palette" test_cecho_still_expands_the_palette

  _hi_h2 "Testing: _hi_hash_color"
  _hi_check_eq "Deterministic across calls" "$(_hi_hash_color someuser)" _hi_hash_color someuser
  _hi_check "Matches hand-computed buckets" test_hash_color_matches_hand_computed_bucket

  _hi_h2 "Testing: _hi_override_color"
  _hi_check "Exact match" test_override_color_exact_match
  _hi_check "No match fails" test_override_color_no_match_fails
  _hi_check "LOCALUSER special case" test_override_color_localuser_special_case
  _hi_check "LOCALHOSTNAME special case" test_override_color_localhostname_special_case

  _hi_h2 "Testing: config/colors' rows, and a pin's own hex"
  _hi_check "_hi_toml_row reads a key and its string or array" test_toml_row_reads_the_subset
  _hi_check_requires zsh "...in zsh too" test_zsh_toml_row_agrees_with_bash
  _hi_check "The hex joins the name, from every reader" test_pin_hex_joins_the_name
  _hi_check "A leading # is allowed, either case" test_pin_hex_accepts_a_leading_hash_and_either_case
  _hi_check "The hex paints the escape, over any scheme" test_pin_hex_paints_the_escape_over_the_scheme
  _hi_check "zsh and fish get the hex and the base name" test_pin_hex_reaches_the_hex_and_base_readers
  _hi_check "A malformed hex field is ignored" test_pin_hex_ignores_a_malformed_hex_field
  _hi_check "Text after the hex is ignored" test_pin_hex_ignores_trailing_text
  _hi_check "Rows are scoped to their [type] table" test_colors_rows_are_scoped_to_their_section
  _hi_check "Comments, blanks and the old rows are skipped" test_colors_skips_comments_blanks_and_old_rows
  _hi_check "A pattern row is a glob, not an exact pin" test_colors_pattern_row_is_a_glob
  _hi_check "A batch reads the file once, a lone scan every time" test_colors_scan_reads_a_batch_once
  _hi_check_requires zsh "A pinned hex agrees in zsh" test_zsh_pin_hex_agrees_with_bash

  _hi_suite_end "core.sh"
}

# a part (core_*_test.sh) sources this file for what is above and runs its own
[ -n "${_HI_CORE_PART:-}" ] || run_core_tests
