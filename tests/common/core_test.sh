#!/usr/bin/env bash
# Copyright the say-hi contributors.
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
  )
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
  )
}

function test_use_ascii_override_beats_the_locale() {
  (
    unset LC_ALL LC_CTYPE LANG
    LANG=en_US.UTF-8 _HI_ASCII=1 _hi_use_ascii &&
      ! LANG=C _HI_ASCII=0 _hi_use_ascii
  )
}

# the chooser's two sets, via the marks the header suite also matches on
function test_choose_glyphs_picks_a_whole_set() {
  (
    _HI_ASCII=1
    _hi_choose_glyphs
    [ "$_HI_MARK_OK" = ok ] && [ "$_HI_MARK_NO" = x ] &&
      [ "$_HI_GLYPH_AHEAD" = "^" ] && [ "$_HI_MARK_OK_W" = 2 ]
  ) && (
    _HI_ASCII=0
    _hi_choose_glyphs
    [ "$_HI_MARK_OK" = "✓" ] && [ "$_HI_MARK_NO" = "✗" ] &&
      [ "$_HI_GLYPH_AHEAD" = "↑" ] && [ "$_HI_MARK_OK_W" = 1 ]
  )
}

function test_sanitize_leaves_plain_text_alone() {
  local out
  _hi_sanitize_var out "hello world"
  [ "$out" = "hello world" ]
}

function test_sanitize_strips_control_chars_and_backslashes() {
  local out
  _hi_sanitize_var out $'a\tb\\c'
  [ "$out" = "abc" ]
}

# https://no-color.org - the convention is "non-empty means off", so both the
# per-call gates and the source-time palette blanking are asserted, the second
# through a fresh bash: this shell sourced core.sh before the variable was set.
function test_no_color_blanks_the_escape() {
  [ -z "$(NO_COLOR=1 _hi_color_escape red)" ]
}

function test_no_color_beats_the_terminal() {
  ! NO_COLOR=1 TERM=xterm-256color _hi_has_color
}

function test_no_color_empty_means_on() {
  [ -n "$(NO_COLOR='' _hi_color_escape red)" ] &&
    NO_COLOR='' TERM=xterm-256color _hi_has_color
}

function test_no_color_blanks_the_palette_at_source_time() {
  local out
  out="$(env NO_COLOR=1 _HI_HOME="$_HI_HOME" bash -c \
    '. "$_HI_HOME/say-hi/common/core.sh"; printf "%s" "$NC$RED$BRCYAN"')"
  [ -z "$out" ]
}

# _HI_COLOR_SCHEME (GLOSSARY: HI.50): the twelve names render as a
# truecolor scheme only when the terminal says it can. Every case pins
# _HI_TRUECOLOR rather than reading the developer's own COLORTERM.
function test_has_truecolor_reads_colorterm() {
  _HI_TRUECOLOR="" COLORTERM=truecolor _hi_has_truecolor || return 1
  _HI_TRUECOLOR="" COLORTERM=24bit _hi_has_truecolor || return 1
  ! _HI_TRUECOLOR="" COLORTERM=xterm-256color _hi_has_truecolor || return 1
  ! _HI_TRUECOLOR="" COLORTERM="" _hi_has_truecolor || return 1
  [ "$(_HI_TRUECOLOR="" COLORTERM=truecolor _hi_truecolor_flag)" = 1 ] &&
    [ "$(_HI_TRUECOLOR="" COLORTERM="" _hi_truecolor_flag)" = 0 ]
}

function test_truecolor_override_wins_both_ways() {
  _HI_TRUECOLOR=1 COLORTERM="" _hi_has_truecolor || return 1
  ! _HI_TRUECOLOR=0 COLORTERM=truecolor _hi_has_truecolor
}

# one SGR: the 16-color pair first, the 24-bit triple after it, the bold bit
# kept for the bright six - so every reader of the leading escape still
# finds what it found before
function test_scheme_escape_keeps_the_16_color_prefix() {
  local red brred
  _HI_COLOR_SCHEME=catppuccin _HI_TRUECOLOR=1 _hi_color_escape_var red red
  _HI_COLOR_SCHEME=catppuccin _HI_TRUECOLOR=1 _hi_color_escape_var brred brred
  [ "$red" = '\e[0;31;38;2;243;139;168m' ] && [ "$brred" = '\e[1;31;38;2;243;119;153m' ] &&
    [ "$(_HI_COLOR_SCHEME=catppuccin _HI_TRUECOLOR=1 _hi_color_escape red)" = $'\e[0;31;38;2;243;139;168m' ]
}

function test_scheme_is_inert_without_truecolor() {
  local out
  _HI_COLOR_SCHEME=catppuccin _HI_TRUECOLOR=0 _hi_color_escape_var out red
  [ "$out" = '\e[0;31m' ] || return 1
  _HI_COLOR_SCHEME=catppuccin _HI_TRUECOLOR=0 _hi_color_hex out red
  [ -z "$out" ]
}

function test_scheme_is_inert_under_no_color() {
  [ -z "$(NO_COLOR=1 _HI_COLOR_SCHEME=monokai _HI_TRUECOLOR=1 _hi_color_escape red)" ]
}

function test_unknown_scheme_falls_back_to_16_color() {
  local out
  _HI_COLOR_SCHEME=solarized _HI_TRUECOLOR=1 _hi_color_escape_var out brcyan
  [ "$out" = '\e[1;36m' ]
}

function test_scheme_hex_is_six_hex_digits_for_every_slot() {
  local scheme i hex
  for scheme in catppuccin monokai onedark vscode; do
    i=0
    while [ "$i" -lt "${#_HI_COLOR_NAMES[@]}" ]; do
      _HI_COLOR_SCHEME="$scheme" _HI_TRUECOLOR=1 _hi_scheme_hex hex "$i"
      [ "${#hex}" -eq 6 ] || return 1
      case "$hex" in *[!0-9a-f]*) return 1 ;; esac
      i=$((i + 1))
    done
  done
}

# the exported palette and the by-name escape share one primitive, so a
# fresh shell under a scheme assigns $RED exactly what _hi_color_escape red
# prints - packages_preview.sh's reverse map depends on that
function test_palette_vars_agree_with_color_escape_under_a_scheme() {
  local out
  out="$(env _HI_COLOR_SCHEME=onedark _HI_TRUECOLOR=1 _HI_HOME="$_HI_HOME" bash -c '
    . "$_HI_HOME/say-hi/common/core.sh"
    for n in RED GREEN YELLOW BLUE PURPLE CYAN BRRED BRGREEN BRYELLOW BRBLUE BRPURPLE BRCYAN; do
      eval "v=\$$n"; printf "%b" "$v"
    done | od -An -c | tr -d " \n"
    printf "|"
    for n in "${_HI_COLOR_NAMES[@]}"; do _hi_color_escape "$n"; done | od -An -c | tr -d " \n"')"
  [ -n "${out%%|*}" ] && [ "${out%%|*}" = "${out#*|}" ] && [[ "${out%%|*}" == *"38;2;"* ]]
}

# the hash is untouched by a scheme: a name, never a hex
function test_hash_color_ignores_the_scheme() {
  [ "$(_HI_COLOR_SCHEME=vscode _HI_TRUECOLOR=1 _hi_hash_color prod-db)" = "$(_hi_hash_color prod-db)" ]
}

# _hi_cecho's %b is for the palette; the text goes through %s. What it prints
# is a target's or ssh's words as often as hi's - _hi_report_failure feeds a
# connect errlog through it - so a backslash a target wrote has to come out a
# backslash, and a literal `\e]0;` in a banner has to stay text rather than
# retitle the client's terminal. The colors, still '\e' strings, still expand.
function test_cecho_prints_the_text_verbatim() {
  local in='C:\Users\new \e]0;x\a %s' out
  out="$(_hi_cecho "$in" "" 1)"
  [ "$out" = "$in$(printf '%b' "$NC")" ]
}

function test_cecho_still_expands_the_palette() {
  local out
  out="$(_hi_cecho x "$RED" 1)"
  [ "$out" = "$(printf '%b' "$RED")x$(printf '%b' "$NC")" ]
}

#
# hi is meant to reach a scratch or distroless container: bash and no
# coreutils at all, so `hostname`, `uname`, `whoami` and `id` are none of them
# there. The identity helpers are read for the banner and the prompt on every
# connect, so what they do without their binaries is user-visible: unhandled,
# that is "uname: command not found" at the top of the session, and a colour
# hashed off an empty string.
#
# A child shell per case: the answers are memoized for the life of a shell, so
# this one's PATH has to be in place before the first call. 2>&1 into the
# assertion on purpose - a rung that leaked to stderr is the whole bug.
#
# $_HI_CONFIG_DIR is aimed at a directory that is never created, and
# $XDG_CONFIG_HOME with it: `env -i` leaves neither set, and core.sh then
# resolves the overlay to the *real* ~/.config/say-hi and sources whatever the
# person running the suite has configured into the middle of the probe.
function _hi_barebones() {
  local nocfg="$_HI_WORKDIR/barebones-nocfg"
  env -i PATH="$(_hi_real_path barebones bash)" HOME="$HOME" NO_COLOR=1 \
    XDG_CONFIG_HOME="$nocfg" _HI_CONFIG_DIR="$nocfg/say-hi" \
    _HI_HOME="$_HI_HOME" "$@" bash -c \
    'source "$_HI_HOME/say-hi/common/core.sh"; printf "%s" "$(eval "$_HI_CASE_PROBE")"' 2>&1
}

function test_hostname_falls_back_to_the_shells_own() {
  [ "$(_hi_barebones _HI_CASE_PROBE=_hi_hostname HOSTNAME=probe-host)" = probe-host ]
}

function test_hostname_names_itself_unknown_with_nothing_to_ask() {
  [ "$(_hi_barebones _HI_CASE_PROBE=_hi_hostname HOSTNAME=)" = unknown ]
}

function test_whoami_falls_back_to_the_environment() {
  [ "$(_hi_barebones _HI_CASE_PROBE=_hi_whoami USER=probe-user)" = probe-user ] &&
    [ "$(_hi_barebones _HI_CASE_PROBE=_hi_whoami LOGNAME=probe-logname)" = probe-logname ]
}

function test_whoami_names_itself_unknown_with_nothing_to_ask() {
  [ "$(_hi_barebones _HI_CASE_PROBE=_hi_whoami)" = unknown ]
}

# $EPOCHREALTIME unset is bash 3.2 (macOS) as much as it is a stripped box:
# unsetting it drops the special attribute, so the date(1) rung is reachable
# from a bash 5 that would otherwise never fork.
function test_now_answers_without_date() {
  local out
  out="$(_hi_barebones _HI_CASE_PROBE='unset EPOCHREALTIME; _hi_now')"
  case "$out" in '' | *[!0-9.]*) return 1 ;; esac
}

function test_hash_color_matches_hand_computed_bucket() {
  # ord('a')=97, 97 % 12 == 1 -> _HI_COLOR_NAMES[1] == green
  [ "$(_hi_hash_color a)" = "green" ] || return 1
  # ord('a')+ord('b')=97+98=195, 195 % 12 == 3 -> _HI_COLOR_NAMES[3] == blue
  [ "$(_hi_hash_color ab)" = "blue" ]
}

function test_override_color_exact_match() {
  local colors="$_HI_WORKDIR/colors.exact"
  printf 'username,alice,red\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _hi_override_color username alice)" = "red" ]
}

function test_override_color_no_match_fails() {
  local colors="$_HI_WORKDIR/colors.nomatch"
  printf 'username,alice,red\n' >"$colors"
  ! _HI_COLORS="$colors" _hi_override_color username bob
}

function test_override_color_localuser_special_case() {
  local colors="$_HI_WORKDIR/colors.localuser"
  printf 'username,LOCALUSER,cyan\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _HI_LOCAL_USER=testuser _hi_override_color username testuser)" = "cyan" ]
}

function test_override_color_localhostname_special_case() {
  local colors="$_HI_WORKDIR/colors.localhost"
  printf 'hostname,LOCALHOSTNAME,magenta\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _HI_LOCAL_HOSTNAME=testhost _hi_override_color hostname testhost)" = "magenta" ]
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

function test_ssh_host_tag_leftmost_of_multiple() {
  [ "$(_HI_SSH_CONFIG="$_HI_SSH_TAG_FIXTURE" _hi_ssh_host_tag myhost)" = "prod" ]
}

function test_ssh_host_tag_untagged_host_fails() {
  ! _HI_SSH_CONFIG="$_HI_SSH_TAG_FIXTURE" _hi_ssh_host_tag untaggedhost
}

function test_ssh_host_tag_equals_syntax_and_multialias() {
  [ "$(_HI_SSH_CONFIG="$_HI_SSH_TAG_FIXTURE" _hi_ssh_host_tag devhost)" = "dev" ] || return 1
  [ "$(_HI_SSH_CONFIG="$_HI_SSH_TAG_FIXTURE" _hi_ssh_host_tag otheralias)" = "dev" ]
}

function test_ssh_host_tag_unknown_host_fails() {
  ! _HI_SSH_CONFIG="$_HI_SSH_TAG_FIXTURE" _hi_ssh_host_tag no-such-host
}

# ssh reads its keywords case-insensitively, and targets.sh's awk agrees - a
# lowercase `host` entry once completed and dispatched as ssh while its tag
# was silently never found
function test_ssh_host_tag_matches_lowercase_host_keyword() {
  [ "$(_HI_SSH_CONFIG="$_HI_SSH_TAG_FIXTURE" _hi_ssh_host_tag lowerhost)" = "lower" ]
}

# the walker's rc is a three-way contract: 0 tagged, 2 known-but-untagged,
# 1 unknown - rc 2 is what hi.sh's _hi_is_ssh_host dispatches on
function test_ssh_host_tag_return_codes() {
  local rc
  _HI_SSH_CONFIG="$_HI_SSH_TAG_FIXTURE" _hi_ssh_host_tag untaggedhost >/dev/null
  rc=$?
  [ "$rc" -eq 2 ] || return 1
  _HI_SSH_CONFIG="$_HI_SSH_TAG_FIXTURE" _hi_ssh_host_tag no-such-host >/dev/null
  rc=$?
  [ "$rc" -eq 1 ]
}

function test_ssh_host_tag_wildcard_host_block() {
  [ "$(_HI_SSH_CONFIG="$_HI_SSH_TAG_FIXTURE" _hi_ssh_host_tag prod-web1)" = "prod" ]
}

# "prod" alone is not "prod-anything" - a bare miss must not fall through to
# the wildcard block that happens to share its prefix
function test_ssh_host_tag_wildcard_requires_the_dash() {
  ! _HI_SSH_CONFIG="$_HI_SSH_TAG_FIXTURE" _hi_ssh_host_tag prod
}

function test_ssh_host_tag_match_host_comma_patterns() {
  [ "$(_HI_SSH_CONFIG="$_HI_SSH_TAG_FIXTURE" _hi_ssh_host_tag staging-db1)" = "staging" ] || return 1
  [ "$(_HI_SSH_CONFIG="$_HI_SSH_TAG_FIXTURE" _hi_ssh_host_tag staging2-x)" = "staging" ]
}

function test_ssh_host_tag_wildcard_untagged_block_is_rc_2() {
  local rc
  _HI_SSH_CONFIG="$_HI_SSH_TAG_FIXTURE" _hi_ssh_host_tag wilduntagged-abc >/dev/null
  rc=$?
  [ "$rc" -eq 2 ]
}

# documented tradeoff (GLOSSARY: HI.37): a "!" token is inert, not honored as
# ssh's own negation, so web-99 still inherits the block's tag despite being
# explicitly excluded there. Pinned so a future change to this is deliberate.
function test_ssh_host_tag_negation_token_is_inert_not_exclusionary() {
  [ "$(_HI_SSH_CONFIG="$_HI_SSH_TAG_FIXTURE" _hi_ssh_host_tag web-99)" = "excluded" ]
}

# `Match host` takes further criteria after its patterns (user, exec,
# canonical, ...); those words are not host patterns, so a host that happens
# to be called "deploy" must not inherit the block's tag - only bastion-* does
function test_ssh_host_tag_match_criteria_are_not_patterns() {
  [ "$(_HI_SSH_CONFIG="$_HI_SSH_TAG_FIXTURE" _hi_ssh_host_tag bastion-2)" = "bastion" ] || return 1
  local rc=0
  _HI_SSH_CONFIG="$_HI_SSH_TAG_FIXTURE" _hi_ssh_host_tag deploy >/dev/null || rc=$?
  [ "$rc" -eq 1 ]
}

# The rest of ssh_config's Match criteria roster - the walker strips one of
# `user`, `localuser`, `exec`, `canonical`, `final` off the end of a `Match
# host` pattern list, in that order - only `user` had a case above.
# `canonical` and `final` are bare keywords with no value of their own, so
# "lastcall-* canonical final" exercises both the mid-string and
# end-of-string truncations in one fixture line - named to not itself start
# with the word "final", which the last truncation would otherwise also
# strip as if it were the keyword.
function test_ssh_host_tag_match_criteria_localuser_exec_canonical_final() {
  [ "$(_HI_SSH_CONFIG="$_HI_SSH_TAG_FIXTURE" _hi_ssh_host_tag canary-1)" = "canary" ] || return 1
  local rc=0
  _HI_SSH_CONFIG="$_HI_SSH_TAG_FIXTURE" _hi_ssh_host_tag build >/dev/null || rc=$?
  [ "$rc" -eq 1 ] || return 1

  [ "$(_HI_SSH_CONFIG="$_HI_SSH_TAG_FIXTURE" _hi_ssh_host_tag robot-1)" = "robot" ] || return 1

  [ "$(_HI_SSH_CONFIG="$_HI_SSH_TAG_FIXTURE" _hi_ssh_host_tag lastcall-1)" = "lastword" ]
}

# a Match on anything but host opens a block of its own, so the tag comment
# above it belongs to that block and never carries onto the next Host line
function test_ssh_host_tag_non_host_match_ends_its_tag() {
  local rc=0
  _HI_SSH_CONFIG="$_HI_SSH_TAG_FIXTURE" _hi_ssh_host_tag afternobody >/dev/null || rc=$?
  [ "$rc" -eq 2 ]
}

function test_resolve_color_override_wins() {
  local colors="$_HI_WORKDIR/colors.resolve1"
  printf 'username,bob,red\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _hi_resolve_color username bob)" = "red" ]
}

function test_resolve_color_hosttag_via_ssh_config() {
  local colors="$_HI_WORKDIR/colors.resolve2"
  printf 'hosttag,prod,blue\n' >"$colors"
  [ "$(_HI_SSH_CONFIG="$_HI_SSH_TAG_FIXTURE" _HI_COLORS="$colors" _hi_resolve_color hostname myhost)" = "blue" ]
}

function test_resolve_color_usertag_when_no_exact_override() {
  local colors="$_HI_WORKDIR/colors.resolve3"
  printf 'usertag,prodtag,green\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _hi_resolve_color username someuser prodtag)" = "green" ]
}

function test_resolve_color_falls_back_to_hash() {
  local colors="$_HI_WORKDIR/colors.missing" # never created - no override file
  [ "$(_HI_COLORS="$colors" _hi_resolve_color username unknownxyz)" = "$(_hi_hash_color unknownxyz)" ]
}

# Subnet-style pins: a hostname row whose name field holds * or ? matches the
# target through _hi_ssh_pattern_hit. Structural precedence: exact pin >
# hosttag > pattern > hash.
function test_pattern_pin_colors_a_subnet() {
  local colors="$_HI_WORKDIR/colors.pattern"
  printf 'hostname,10.0.1.*,red\nhostname,*.prod.example,blue\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _hi_resolve_color hostname 10.0.1.7)" = red ] || return 1
  [ "$(_HI_COLORS="$colors" _hi_resolve_color hostname db.prod.example)" = blue ] || return 1
  ! _HI_COLORS="$colors" _hi_colors_pattern hostname 10.0.2.7
}

function test_pattern_first_row_wins() {
  local colors="$_HI_WORKDIR/colors.patorder"
  printf 'hostname,10.0.*,green\nhostname,10.0.1.*,red\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _hi_resolve_color hostname 10.0.1.7)" = green ]
}

function test_exact_pin_beats_pattern() {
  local colors="$_HI_WORKDIR/colors.patexact"
  printf 'hostname,10.0.1.*,red\nhostname,10.0.1.7,cyan\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _hi_resolve_color hostname 10.0.1.7)" = cyan ]
}

function test_hosttag_beats_pattern() {
  local colors="$_HI_WORKDIR/colors.pattag"
  printf 'hostname,myhost*,red\nhosttag,prod,blue\n' >"$colors"
  [ "$(_HI_SSH_CONFIG="$_HI_SSH_TAG_FIXTURE" _HI_COLORS="$colors" _hi_resolve_color hostname myhost)" = blue ]
}

function test_pattern_beats_hash() {
  local colors="$_HI_WORKDIR/colors.pathash"
  printf 'hostname,unhashed-*,brred\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _hi_resolve_color hostname unhashed-9)" = brred ] || return 1
  [ "$(_HI_COLORS="$colors" _hi_resolve_color hostname other-9)" = "$(_hi_hash_color other-9)" ]
}

# A Host token that is not a hostname pattern - a `)` or `;;` in it - is
# skipped, never eval'd: the zsh arm re-parses its pattern as case syntax
# otherwise, and ~/.ssh/config is a file the user edits by hand.
function test_pattern_hit_skips_a_token_that_is_not_a_hostname() {
  _hi_ssh_pattern_hit myhost 'x) hit=0 ;; case y in y' && return 1
  _hi_ssh_pattern_hit myhost 'my*' || return 1
  _hi_ssh_pattern_hit fe80::1 'fe80:*' || return 1
  ! _hi_ssh_pattern_hit myhost 'other?'
}

function test_zsh_pattern_hit_skips_the_same_tokens() {
  _hi_shell_agrees '_hi_ssh_pattern_hit myhost "x) hit=0 ;; case y in y"; printf "bad:%s " "$?"; _hi_ssh_pattern_hit myhost "my*"; printf "glob:%s" "$?"'
}

# the pattern walk rides _hi_ssh_pattern_hit, whose zsh divergences are HI.37's
function test_zsh_pattern_pins_agree_with_bash() {
  local colors="$_HI_WORKDIR/colors.zshpat" a b script
  printf 'hostname,10.0.1.*,red\n' >"$colors"
  script='printf "%s|%s" "$(_hi_resolve_color hostname 10.0.1.7)" "$(_hi_resolve_color hostname 10.0.2.7)"'
  a="$(env _HI_HOME="$_HI_HOME" _HI_COLORS="$colors" bash -c "source \"\$_HI_HOME/say-hi/common/core.sh\"; $script" 2>&1)"
  b="$(env _HI_HOME="$_HI_HOME" _HI_COLORS="$colors" zsh -c "source \"\$_HI_HOME/say-hi/common/core.sh\"; $script" 2>&1)"
  [ -n "$a" ] && [ "$a" = "$b" ]
}

# GLOSSARY: HI.33's bash arm - the every-entry-point-derives-its-own-tree
# fallback that makes $_HI_HOME optional. Every other case in this suite sets
# $_HI_HOME before sourcing core.sh (test_lib.sh's own doing, HI.33's *test*
# side), so this branch never otherwise runs: a fresh bash with $_HI_HOME
# genuinely unset (not just empty - `-u`, not a blank value) sourcing core.sh
# by its real path is the only way to reach it. Asserts against the real
# checkout's own $_HI_HOME rather than a scratch tree, since the point is
# that the derivation is correct, not merely that it runs.
function test_hi_home_self_derives_when_unset() {
  local real="$_HI_HOME/say-hi/common/core.sh"
  [ "$(env -u _HI_HOME -u _hi_core_loaded bash -c \
    "source '$real'; printf '%s' \"\$_HI_HOME\"")" = "$_HI_HOME" ]
}

# The other half of HI.33's case: BASH_SOURCE[0] carries no slash at all when
# core.sh is sourced by a bare relative name from its own directory (`source
# core.sh`, not `source ./core.sh` or an absolute path) - bash's `.`/`source`
# still finds it in the current directory, but the case that strips a
# directory component off $_hi_self has nothing to strip, and takes the
# `*) _hi_self="."` arm instead.
function test_hi_home_self_derives_from_a_bare_relative_source() {
  [ "$(cd "$_HI_HOME/say-hi/common" && env -u _HI_HOME -u _hi_core_loaded bash -c \
    'source core.sh; printf "%s" "$_HI_HOME"')" = "$_HI_HOME" ]
}

# core.sh's preamble runs once per shell and is guarded by $_hi_core_loaded,
# so there is no function to call: the case is a fresh bash sourcing core.sh
# against a scratch $_HI_CONFIG_DIR whose settings.sh claims $_HI_PROBE.
# shellcheck disable=SC2016 # the probe expands in the child bash, not here
function test_settings_sh_is_sourced() {
  local dir="$_HI_WORKDIR/overlay"
  mkdir -p "$dir"
  printf 'export _HI_PROBE=global\n' >"$dir/settings.sh"
  [ "$(env -u _hi_core_loaded -u _HI_PROBE _HI_HOME="$_HI_HOME" _HI_CONFIG_DIR="$dir" \
    bash -c 'source "$_HI_HOME/say-hi/common/core.sh"; printf "%s" "${_HI_PROBE:-unset}"')" = global ]
}

# The system-wide layer: sourced before the user's settings.sh (so the user
# wins), and only on the machine say-hi is installed on. $_HI_SYSTEM_SETTINGS
# stands in for /etc/say-hi/settings.sh so the cases need no root.
function test_system_settings_apply_locally() {
  local sys="$_HI_WORKDIR/sys.settings.sh"
  printf 'export _HI_PROBE=system\n' >"$sys"
  [ "$(env -u _hi_core_loaded -u _HI_PROBE -u _HI_REMOTE_SESSION _HI_HOME="$_HI_HOME" \
    _HI_SYSTEM_SETTINGS="$sys" \
    bash -c 'source "$_HI_HOME/say-hi/common/core.sh"; printf "%s" "${_HI_PROBE:-unset}"')" = system ]
}

function test_user_settings_beat_system() {
  local sys="$_HI_WORKDIR/sys2.settings.sh" dir="$_HI_WORKDIR/sys-user-overlay"
  mkdir -p "$dir"
  printf 'export _HI_PROBE=system\n' >"$sys"
  printf 'export _HI_PROBE=user\n' >"$dir/settings.sh"
  [ "$(env -u _hi_core_loaded -u _HI_PROBE -u _HI_REMOTE_SESSION _HI_HOME="$_HI_HOME" \
    _HI_SYSTEM_SETTINGS="$sys" _HI_CONFIG_DIR="$dir" \
    bash -c 'source "$_HI_HOME/say-hi/common/core.sh"; printf "%s" "${_HI_PROBE:-unset}"')" = user ]
}

function test_system_settings_skipped_remotely() {
  local sys="$_HI_WORKDIR/sys3.settings.sh"
  printf 'export _HI_PROBE=system\n' >"$sys"
  [ "$(env -u _hi_core_loaded -u _HI_PROBE _HI_REMOTE_SESSION=1 _HI_HOME="$_HI_HOME" \
    _HI_SYSTEM_SETTINGS="$sys" \
    bash -c 'source "$_HI_HOME/say-hi/common/core.sh"; printf "%s" "${_HI_PROBE:-unset}"')" = unset ]
}

#
# $_HI_CONFIG_DIR is derived from the XDG base, and an explicit value wins.
# Same preamble-in-a-fresh-bash shape as test_settings_sh_is_sourced above, for
# the same reason.
#
# common/config.fish carries the same resolution in fish's dialect and is
# pinned against these answers by tests/common/rc_test.sh.

# _hi_cfg_answer <case> - what core.sh resolves $_HI_CONFIG_DIR to when the XDG
# base holds <case>: `new` or `neither`. Printed relative to the base, so a
# case reads as the name rather than a workdir path.
function _hi_cfg_answer() {
  local base="$_HI_WORKDIR/xdg.$1" out
  rm -rf "$base"
  mkdir -p "$base"
  case "$1" in
  new) mkdir -p "$base/say-hi" ;;
  esac
  out="$(env -u _hi_core_loaded -u _HI_CONFIG_DIR _HI_HOME="$_HI_HOME" XDG_CONFIG_HOME="$base" \
    bash -c 'source "$_HI_HOME/say-hi/common/core.sh"; printf "%s" "$_HI_CONFIG_DIR"')"
  printf '%s' "${out#"$base/"}"
}

# hi.sh points a target at the overlay it shipped, so an explicit value has to
# beat the derived one
function test_config_dir_explicit_value_wins() {
  local base="$_HI_WORKDIR/xdg.explicit"
  rm -rf "$base"
  mkdir -p "$base/say-hi"
  [ "$(env -u _hi_core_loaded _HI_HOME="$_HI_HOME" XDG_CONFIG_HOME="$base" \
    _HI_CONFIG_DIR="$base/shipped" \
    bash -c 'source "$_HI_HOME/say-hi/common/core.sh"; printf "%s" "$_HI_CONFIG_DIR"')" = "$base/shipped" ]
}

# common/zsh.zsh sources core.sh directly, so its functions run in zsh too - and
# three zsh differences had each silently broken something: `${name:i:1}` is a
# history modifier there, $BASH_REMATCH is never populated, and an unquoted
# `$var` is not word-split. All three were invisible to a bash-only suite, so
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

function test_zsh_hash_color_agrees_with_bash() {
  _hi_shell_agrees 'printf "%s,%s,%s" "$(_hi_hash_color alice)" "$(_hi_hash_color prod-db)" "$(_hi_hash_color x)"'
}

function test_zsh_scheme_escape_agrees_with_bash() {
  _hi_shell_agrees 'export _HI_COLOR_SCHEME=vscode _HI_TRUECOLOR=1; _hi_assign_palette; _hi_color_hex h brcyan; printf "%s|%s|%s" "$RED" "$BRCYAN" "$h"'
}

function test_zsh_host_tag_agrees_with_bash() {
  _hi_shell_agrees 'printf "%s|%s" "$(_hi_ssh_host_tag myhost)" "$(_hi_ssh_host_tag devhost)"'
}

# GLOSSARY: HI.37 - the two zsh divergences _hi_ssh_pattern_hit works around
# (word-splitting, then GLOB_SUBST) are each invisible to a bash-only suite
function test_zsh_host_tag_wildcard_agrees_with_bash() {
  _hi_shell_agrees 'printf "%s|%s" "$(_hi_ssh_host_tag prod-web1)" "$(_hi_ssh_host_tag staging2-x)"'
}

function test_zsh_host_tag_rejects_the_same_hosts() {
  _hi_shell_agrees '_hi_ssh_host_tag untaggedhost >/dev/null; printf "untagged:%s " "$?"; _hi_ssh_host_tag nope >/dev/null; printf "unknown:%s" "$?"'
}

function test_zsh_resolve_color_agrees_with_bash() {
  _hi_shell_agrees 'printf "%s" "$(_hi_resolve_color hostname myhost)"'
}

# the regression that matters for oh-my-zsh: hi must not leave KSH_ARRAYS on in
# the user's shell, because omz and its plugins index arrays from 1
function test_zsh_rc_leaves_ksharrays_alone() {
  local out
  out="$(env _HI_HOME="$_HI_HOME" TERM=xterm-256color zsh -c \
    'source "$_HI_HOME/say-hi/common/zsh.zsh"; setopt | grep -c ksharrays' 2>/dev/null)"
  [ "$out" = 0 ]
}

# ...and it still has to work when the user (or their framework) turned it on
function test_zsh_rc_survives_ksharrays_being_on() {
  local out
  out="$(env _HI_HOME="$_HI_HOME" TERM=xterm-256color zsh -c \
    'setopt KSH_ARRAYS; source "$_HI_HOME/say-hi/common/zsh.zsh"; print -n "$USER_COLOR"' 2>/dev/null)"
  [ -n "$out" ]
}

# Every row has all six fields, both rc paths are absolute, and the flags
# column names only mechanisms that exist. A row short a field silently
# hands install.sh an empty rc path, which is a `touch ""` at install time.
function test_shell_table_rows_are_wellformed() {
  local row shell label tree home check flags dialect rest
  for row in "${_HI_SHELL_TABLE[@]}"; do
    IFS='|' read -r shell label tree home check flags dialect rest <<<"$row"
    [ -n "$shell" ] && [ -n "$label" ] && [ -n "$check" ] || {
      _hi_cecho " | thin row: $row" "$RED"
      return 1
    }
    case "$dialect" in
    sh | fish) ;;
    *)
      _hi_cecho " | unknown rc dialect '$dialect': $row" "$RED"
      return 1
      ;;
    esac
    [ -z "$rest" ] || {
      _hi_cecho " | too many fields: $row" "$RED"
      return 1
    }
    case "$tree$home" in
    /*/*) ;;
    *)
      _hi_cecho " | rc paths must be absolute: $row" "$RED"
      return 1
      ;;
    esac
    case ",$flags," in
    *,local,*) ;;
    *)
      _hi_cecho " | no known mechanism in flags: $row" "$RED"
      return 1
      ;;
    esac
  done
}

# The roster is the table; paths.sh is the data. A shell given path vars there
# and no row here reaches neither install.sh's local half nor hi.sh's remote
# probe - it just quietly does nothing, which is how the two lists drifted
# before.
function test_shell_table_covers_every_rc_path_var() {
  local var value missing=""
  for var in _HI_BASHRC _HI_ZSHRC _HI_FISH_CONFIG \
    _HI_HOME_BASHRC _HI_HOME_ZSHRC _HI_HOME_FISH_CONFIG; do
    eval "value=\"\${$var:-}\""
    [ -n "$value" ] || {
      _hi_cecho " | paths.sh exports no $var" "$RED"
      return 1
    }
    case "$(printf '%s\n' "${_HI_SHELL_TABLE[@]}")" in
    *"|$value|"* | *"|$value") ;;
    *) missing="$missing $var" ;;
    esac
  done
  [ -z "$missing" ] || {
    _hi_cecho " | in paths.sh but in no _HI_SHELL_TABLE row:$missing" "$RED"
    return 1
  }
}

function test_repeat_makes_count_copies() {
  local out
  _hi_repeat out 4 '='
  [ "$out" = "====" ] || return 1
  _hi_repeat out 0 '='
  [ -z "$out" ]
}

function test_human_duration_formats() {
  [ "$(_hi_human_duration 59)" = "0:59" ] &&
    [ "$(_hi_human_duration 61.9)" = "1:01" ] &&
    [ "$(_hi_human_duration 3661)" = "1:01:01" ]
}

function test_du_size_answers_for_a_real_path() {
  local dir="$_HI_WORKDIR/du.probe" out
  mkdir -p "$dir"
  printf '%2048s' '' >"$dir/two-k"
  out="$(_hi_du_size "$dir")"
  [ -n "$out" ] || return 1
  case "$out" in [0-9]*) ;; *) return 1 ;; esac
}

# the shipped verdicts win; the local binaries are only the fallback
function test_local_identity_prefers_the_shipped_verdict() {
  [ "$(_HI_LOCAL_USER=shipped-user _hi_local_username)" = shipped-user ] || return 1
  [ "$(_HI_LOCAL_HOSTNAME=shipped-host _hi_local_hostname)" = shipped-host ] || return 1
  (
    unset _HI_LOCAL_USER _HI_LOCAL_HOSTNAME
    [ "$(_hi_local_username)" = "$(_hi_whoami)" ] &&
      [ "$(_hi_local_hostname)" = "$(_hi_hostname)" ]
  )
}

function test_ascii_flag_ships_the_verdict() {
  (
    _HI_ASCII=1
    [ "$(_hi_ascii_flag)" = 1 ]
  ) && (
    _HI_ASCII=0
    [ "$(_hi_ascii_flag)" = 0 ]
  )
}

# never auto-detected: the setting and the binary both have to say yes
function test_wants_starship_needs_both_halves() {
  (
    unset _HI_PROMPT
    ! _hi_wants_starship
  ) || return 1
  ! _HI_PROMPT=starship PATH="$_HI_WORKDIR/empty.path" _hi_wants_starship || return 1
  mkdir -p "$_HI_WORKDIR/empty.path"
  _HI_PROMPT=starship PATH="$(_hi_fake_path star starship):$PATH" _hi_wants_starship
}

function test_colors_lookup_verdicts() {
  local colors="$_HI_WORKDIR/colors.lookup"
  printf 'username,alice,red\nhostname,box,blue\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _hi_colors_lookup hostname box)" = blue ] || return 1
  ! _HI_COLORS="$colors" _hi_colors_lookup hostname nobox || return 1
  ! _HI_COLORS="$_HI_WORKDIR/colors.absent" _hi_colors_lookup hostname box
}

# the memo pair: a shipped _HI_TARGET_COLOR wins outright, and the escape is
# the escape of whatever the color half answered
function test_host_color_memo_and_escape_agree() {
  (
    unset _HI_HOST_COLOR _HI_HOST_ESC
    _HI_TARGET_COLOR=blue
    [ "$(_hi_host_color)" = blue ] || exit 1
    [ "$(_hi_host_escape)" = "$(_hi_color_escape blue)" ]
  )
}

function test_user_color_resolves_like_resolve_color() {
  (
    unset _HI_USER_COLOR _HI_TARGET_TAG
    [ "$(_hi_user_color)" = "$(_hi_resolve_color username "$(_hi_whoami)")" ]
  )
}

# the out-var forms exist so a prompt builder keeps the memo out of a $( )
# subshell; the answer must match the stdout form's
function test_escape_var_forms_fill_the_caller() {
  (
    unset _HI_HOST_ESC _HI_USER_ESC
    local h u
    _hi_host_escape h
    _hi_user_escape u
    [ "$h" = "$(_hi_host_escape)" ] && [ "$u" = "$(_hi_user_escape)" ]
  )
}

# _hi_shell_rows with no argument is the whole roster; with one, only the rows
# carrying that flag.
function test_shell_rows_filters_by_flag() {
  local all local_rows
  all="$(_hi_shell_rows | wc -l)"
  local_rows="$(_hi_shell_rows local | wc -l)"
  [ "$all" -eq "${#_HI_SHELL_TABLE[@]}" ] || return 1
  [ "$local_rows" -gt 0 ] && [ "$local_rows" -le "$all" ] || return 1
  [ -z "$(_hi_shell_rows nosuchflag)" ]
}

# the version, unpresented: a packager's stamp wins outright, else git
# describe against $_HI_ROOT, else empty. header.sh's version cell and hi.sh's
# --version both go through this.
function test_release_or_describe_prefers_the_stamp() {
  (
    _HI_RELEASE=1.2.3
    [ "$(_hi_release_or_describe)" = 1.2.3 ]
  )
}

function test_release_or_describe_falls_back_to_git() {
  (
    unset _HI_RELEASE
    [ -d "$_HI_ROOT/.git" ] || return 0 # nothing to fall back to in a tarball checkout
    [ -n "$(_hi_release_or_describe)" ]
  )
}

function test_release_or_describe_empty_without_either() {
  local dir
  dir="$(mktemp -d "$_HI_WORKDIR/norelease.XXXXXX")"
  (
    unset _HI_RELEASE
    _HI_ROOT="$dir"
    [ -z "$(_hi_release_or_describe)" ]
  )
}

# lesspipe/debian_chroot both read hardcoded absolute paths
# (/usr/bin/lesspipe, /etc/debian_chroot) rather than anything on $PATH, so
# there is no fixture-able way to force either arm on a box that lacks them
# (this one does) short of writing outside the checkout - only the
# already-exported skip is portable.
function test_interactive_extras_skips_lesspipe_when_already_set() {
  (
    LESSOPEN=already-set
    _hi_interactive_extras
    [ "$LESSOPEN" = already-set ]
  )
}

# the memos land in the *calling* shell - the entire point (a prompt's $( )
# would lose them, same as _hi_git_prompt's out-var form) - so this has to run
# without a subshell around the call itself.
function test_prime_identity_fills_every_memo_in_the_caller() {
  unset _HI_HOSTNAME_CACHE _HI_WHOAMI_CACHE _HI_HOST_COLOR _HI_USER_COLOR
  _hi_prime_identity
  [ -n "${_HI_HOSTNAME_CACHE:-}" ] &&
    [ -n "${_HI_WHOAMI_CACHE:-}" ] &&
    [ "${_HI_HOST_COLOR+x}" = x ] &&
    [ "${_HI_USER_COLOR+x}" = x ]
}

# the bash arm of _hi_on_exit is a plain EXIT trap: the command runs after
# the body, once (the zsh arm is pinned with the other zsh answers below)
function test_on_exit_installs_a_trap_that_fires_in_bash() {
  local out
  out="$(env _HI_HOME="$_HI_HOME" bash -c '
    source "$_HI_HOME/say-hi/common/core.sh"
    _hi_on_exit "echo fired"
    echo body' 2>&1)"
  [ "$out" = $'body\nfired' ]
}

# the two ways a value is not there: no file at all, and a file that never
# sets the name - both rc 1, and neither says anything
function test_setting_get_fails_for_a_missing_file_and_an_unset_name() {
  local f="$_HI_WORKDIR/sg.sh" out
  printf 'export _HI_PROBE_SG=yes\n' >"$f"
  ! _hi_setting_get "$_HI_WORKDIR/absent.sh" _HI_PROBE_SG >/dev/null || return 1
  out="$(_hi_setting_get "$f" _HI_NEVER_SET_SG)" && return 1
  [ -z "$out" ] && [ "$(_hi_setting_get "$f" _HI_PROBE_SG)" = yes ]
}

# an _HI_* name outside _HI_CHILD_ENV stays set in the shell but stops
# reaching children; one on the roster keeps its export
function test_unexport_keeps_values_and_drops_the_export_bit() {
  local out
  out="$(env _HI_HOME="$_HI_HOME" _HI_PROBE_UX=kept bash -c '
    source "$_HI_HOME/say-hi/common/core.sh"
    _hi_unexport
    printf "%s|" "${_HI_PROBE_UX:-lost}"
    bash -c "printf %s \"\${_HI_PROBE_UX:-gone}\""')"
  [ "$out" = "kept|gone" ]
}

function run_core_tests() {
  _hi_workdir sharedtest
  _HI_SSH_TAG_FIXTURE="$(_hi_ssh_tag_fixture)"

  _hi_h1 "Testing common/core.sh"

  _hi_suite_begin

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
  _hi_check "Every slot of every scheme is six hex digits" test_scheme_hex_is_six_hex_digits_for_every_slot
  _hi_check "The palette agrees with _hi_color_escape under a scheme" test_palette_vars_agree_with_color_escape_under_a_scheme
  _hi_check "The hash ignores the scheme" test_hash_color_ignores_the_scheme

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

  _hi_h2 "Testing: a target with nothing but a shell"
  _hi_check "Hostname falls back to the shell's own" test_hostname_falls_back_to_the_shells_own
  _hi_check "...and to \"unknown\" with nothing to ask" test_hostname_names_itself_unknown_with_nothing_to_ask
  _hi_check "Whoami falls back to the environment" test_whoami_falls_back_to_the_environment
  _hi_check "...and to \"unknown\" with nothing to ask" test_whoami_names_itself_unknown_with_nothing_to_ask
  _hi_check "_hi_now answers without date(1)" test_now_answers_without_date

  _hi_h2 "Testing: _HI_SHELL_TABLE"
  _hi_check "Every row is six well-formed fields" test_shell_table_rows_are_wellformed
  _hi_check "Every paths.sh rc var has a row" test_shell_table_covers_every_rc_path_var
  _hi_check "_hi_shell_rows filters by flag" test_shell_rows_filters_by_flag

  _hi_h2 "Testing: the small formatters"
  _hi_check "_hi_repeat makes count copies" test_repeat_makes_count_copies
  _hi_check "_hi_human_duration's three shapes" test_human_duration_formats
  _hi_check "_hi_du_size answers for a real path" test_du_size_answers_for_a_real_path

  _hi_h2 "Testing: the shipped verdicts"
  _hi_check "Local identity prefers the shipped verdict" test_local_identity_prefers_the_shipped_verdict
  _hi_check "_hi_ascii_flag ships the client's verdict" test_ascii_flag_ships_the_verdict
  _hi_check "_hi_wants_starship needs setting and binary" test_wants_starship_needs_both_halves

  _hi_h2 "Testing: the colors file readers"
  _hi_check "_hi_colors_lookup's three verdicts" test_colors_lookup_verdicts

  _hi_h2 "Testing: the identity memos"
  _hi_check "Host memo honors \$_HI_TARGET_COLOR; escape agrees" test_host_color_memo_and_escape_agree
  _hi_check "User color resolves like _hi_resolve_color" test_user_color_resolves_like_resolve_color
  _hi_check "The out-var escape forms fill the caller" test_escape_var_forms_fill_the_caller
  _hi_check "_hi_prime_identity fills every memo in the caller" test_prime_identity_fills_every_memo_in_the_caller

  _hi_h2 "Testing: _hi_release_or_describe"
  _hi_check "A shipped \$_HI_RELEASE wins outright" test_release_or_describe_prefers_the_stamp
  _hi_check "Falls back to git describe against \$_HI_ROOT" test_release_or_describe_falls_back_to_git
  _hi_check "Empty with neither a stamp nor a .git" test_release_or_describe_empty_without_either

  _hi_h2 "Testing: _hi_interactive_extras"
  _hi_check "Skips the lesspipe fork when LESSOPEN is already set" test_interactive_extras_skips_lesspipe_when_already_set

  _hi_h2 "Testing: _hi_ssh_host_tag"
  _hi_check "Leftmost tag of a multi-tag comment" test_ssh_host_tag_leftmost_of_multiple
  _hi_check "Untagged host fails" test_ssh_host_tag_untagged_host_fails
  _hi_check "'Tags=' syntax and multi-alias Host lines" test_ssh_host_tag_equals_syntax_and_multialias
  _hi_check "Unknown host fails" test_ssh_host_tag_unknown_host_fails
  _hi_check "Lowercase 'host' keyword matches" test_ssh_host_tag_matches_lowercase_host_keyword
  _hi_check "rc contract: 0 tagged / 2 untagged / 1 unknown" test_ssh_host_tag_return_codes
  _hi_check "Wildcard Host block tags every match" test_ssh_host_tag_wildcard_host_block
  _hi_check "Wildcard requires the literal dash" test_ssh_host_tag_wildcard_requires_the_dash
  _hi_check "Match host, comma-separated patterns" test_ssh_host_tag_match_host_comma_patterns
  _hi_check "Untagged wildcard block is rc 2" test_ssh_host_tag_wildcard_untagged_block_is_rc_2
  _hi_check "A '!' token is inert, not exclusionary" test_ssh_host_tag_negation_token_is_inert_not_exclusionary
  _hi_check "Match criteria after the patterns are not patterns" test_ssh_host_tag_match_criteria_are_not_patterns
  _hi_check "...localuser, exec, canonical and final too" test_ssh_host_tag_match_criteria_localuser_exec_canonical_final
  _hi_check "A non-host Match ends its tag" test_ssh_host_tag_non_host_match_ends_its_tag

  _hi_h2 "Testing: _hi_resolve_color precedence"
  _hi_check "Exact override wins" test_resolve_color_override_wins
  _hi_check "Hosttag via ssh config" test_resolve_color_hosttag_via_ssh_config
  _hi_check "Usertag when no exact override" test_resolve_color_usertag_when_no_exact_override
  _hi_check "Falls back to the hash" test_resolve_color_falls_back_to_hash
  _hi_check "A pattern pin colors a subnet" test_pattern_pin_colors_a_subnet
  _hi_check "First matching pattern wins" test_pattern_first_row_wins
  _hi_check "An exact pin beats a pattern" test_exact_pin_beats_pattern
  _hi_check "A hosttag beats a pattern" test_hosttag_beats_pattern
  _hi_check "A pattern beats the hash" test_pattern_beats_hash
  _hi_check "A token that is not a hostname is skipped, not eval'd" test_pattern_hit_skips_a_token_that_is_not_a_hostname
  _hi_check_requires zsh "zsh skips the same tokens" test_zsh_pattern_hit_skips_the_same_tokens
  _hi_check_requires zsh "Pattern pins agree in zsh" test_zsh_pattern_pins_agree_with_bash

  _hi_h2 "Testing: _hi_on_exit / _hi_setting_get / _hi_unexport"
  _hi_check "_hi_on_exit installs a trap that fires in bash" test_on_exit_installs_a_trap_that_fires_in_bash
  _hi_check "_hi_setting_get: rc 1 for a missing file and an unset name" test_setting_get_fails_for_a_missing_file_and_an_unset_name
  _hi_check "_hi_unexport keeps the value, drops the export bit" test_unexport_keeps_values_and_drops_the_export_bit

  _hi_h2 "Testing: HI.33's bash arm - \$_HI_HOME self-derivation"
  _hi_check "sourced by its real path with \$_HI_HOME unset" test_hi_home_self_derives_when_unset
  _hi_check "...and by a bare relative name from its own directory" test_hi_home_self_derives_from_a_bare_relative_source

  _hi_h2 "Testing: the settings overlay"
  _hi_check "settings.sh is sourced" test_settings_sh_is_sourced
  _hi_check "The system layer applies locally" test_system_settings_apply_locally
  _hi_check "...the user's settings.sh beats it" test_user_settings_beat_system
  _hi_check "...and a remote session skips it" test_system_settings_skipped_remotely
  _hi_check_eq "Defaults to ~/.config/say-hi" say-hi _hi_cfg_answer neither
  _hi_check_eq "Uses say-hi when it exists" say-hi _hi_cfg_answer new
  _hi_check "An explicit \$_HI_CONFIG_DIR wins" test_config_dir_explicit_value_wins

  _hi_h2 "Testing: the same answers in zsh"
  _hi_check_requires zsh "_hi_hash_color agrees with bash" test_zsh_hash_color_agrees_with_bash
  _hi_check_requires zsh "A scheme escape agrees with bash" test_zsh_scheme_escape_agrees_with_bash
  _hi_check_requires zsh "_hi_ssh_host_tag agrees with bash" test_zsh_host_tag_agrees_with_bash
  _hi_check_requires zsh "...and rejects the same hosts" test_zsh_host_tag_rejects_the_same_hosts
  _hi_check_requires zsh "...and agrees on wildcard blocks" test_zsh_host_tag_wildcard_agrees_with_bash
  _hi_check_requires zsh "_hi_resolve_color agrees with bash" test_zsh_resolve_color_agrees_with_bash
  _hi_check_requires zsh "zsh.zsh leaves KSH_ARRAYS off" test_zsh_rc_leaves_ksharrays_alone
  _hi_check_requires zsh "zsh.zsh survives KSH_ARRAYS being on" test_zsh_rc_survives_ksharrays_being_on

  _hi_suite_end "core.sh"
}

run_core_tests
