#!/usr/bin/env bash
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
EOF
  printf '%s' "$f"
}

function test_ssh_host_tag_leftmost_of_multiple() {
  local f
  f="$(_hi_ssh_tag_fixture)"
  [ "$(_HI_SSH_CONFIG="$f" _hi_ssh_host_tag myhost)" = "prod" ]
}

function test_ssh_host_tag_untagged_host_fails() {
  local f
  f="$(_hi_ssh_tag_fixture)"
  ! _HI_SSH_CONFIG="$f" _hi_ssh_host_tag untaggedhost
}

function test_ssh_host_tag_equals_syntax_and_multialias() {
  local f
  f="$(_hi_ssh_tag_fixture)"
  [ "$(_HI_SSH_CONFIG="$f" _hi_ssh_host_tag devhost)" = "dev" ] || return 1
  [ "$(_HI_SSH_CONFIG="$f" _hi_ssh_host_tag otheralias)" = "dev" ]
}

function test_ssh_host_tag_unknown_host_fails() {
  local f
  f="$(_hi_ssh_tag_fixture)"
  ! _HI_SSH_CONFIG="$f" _hi_ssh_host_tag no-such-host
}

# ssh reads its keywords case-insensitively, and targets.sh's awk agrees - a
# lowercase `host` entry once completed and dispatched as ssh while its tag
# was silently never found
function test_ssh_host_tag_matches_lowercase_host_keyword() {
  local f
  f="$(_hi_ssh_tag_fixture)"
  [ "$(_HI_SSH_CONFIG="$f" _hi_ssh_host_tag lowerhost)" = "lower" ]
}

# the walker's rc is a three-way contract: 0 tagged, 2 known-but-untagged,
# 1 unknown - rc 2 is what hi.sh's _hi_is_ssh_host dispatches on
function test_ssh_host_tag_return_codes() {
  local f rc
  f="$(_hi_ssh_tag_fixture)"
  _HI_SSH_CONFIG="$f" _hi_ssh_host_tag untaggedhost >/dev/null
  rc=$?
  [ "$rc" -eq 2 ] || return 1
  _HI_SSH_CONFIG="$f" _hi_ssh_host_tag no-such-host >/dev/null
  rc=$?
  [ "$rc" -eq 1 ]
}

function test_ssh_host_tag_wildcard_host_block() {
  local f
  f="$(_hi_ssh_tag_fixture)"
  [ "$(_HI_SSH_CONFIG="$f" _hi_ssh_host_tag prod-web1)" = "prod" ]
}

# "prod" alone is not "prod-anything" - a bare miss must not fall through to
# the wildcard block that happens to share its prefix
function test_ssh_host_tag_wildcard_requires_the_dash() {
  local f
  f="$(_hi_ssh_tag_fixture)"
  ! _HI_SSH_CONFIG="$f" _hi_ssh_host_tag prod
}

function test_ssh_host_tag_match_host_comma_patterns() {
  local f
  f="$(_hi_ssh_tag_fixture)"
  [ "$(_HI_SSH_CONFIG="$f" _hi_ssh_host_tag staging-db1)" = "staging" ] || return 1
  [ "$(_HI_SSH_CONFIG="$f" _hi_ssh_host_tag staging2-x)" = "staging" ]
}

function test_ssh_host_tag_wildcard_untagged_block_is_rc_2() {
  local f rc
  f="$(_hi_ssh_tag_fixture)"
  _HI_SSH_CONFIG="$f" _hi_ssh_host_tag wilduntagged-abc >/dev/null
  rc=$?
  [ "$rc" -eq 2 ]
}

# documented tradeoff (GLOSSARY: HI.37): a "!" token is inert, not honored as
# ssh's own negation, so web-99 still inherits the block's tag despite being
# explicitly excluded there. Pinned so a future change to this is deliberate.
function test_ssh_host_tag_negation_token_is_inert_not_exclusionary() {
  local f
  f="$(_hi_ssh_tag_fixture)"
  [ "$(_HI_SSH_CONFIG="$f" _hi_ssh_host_tag web-99)" = "excluded" ]
}

function test_resolve_color_override_wins() {
  local colors="$_HI_WORKDIR/colors.resolve1"
  printf 'username,bob,red\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _hi_resolve_color username bob)" = "red" ]
}

function test_resolve_color_hosttag_via_ssh_config() {
  local f colors
  f="$(_hi_ssh_tag_fixture)"
  colors="$_HI_WORKDIR/colors.resolve2"
  printf 'hosttag,prod,blue\n' >"$colors"
  [ "$(_HI_SSH_CONFIG="$f" _HI_COLORS="$colors" _hi_resolve_color hostname myhost)" = "blue" ]
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
  _hi_ssh_tag_fixture >/dev/null
  _hi_shell_agrees 'printf "%s,%s,%s" "$(_hi_hash_color alice)" "$(_hi_hash_color prod-db)" "$(_hi_hash_color x)"'
}

function test_zsh_host_tag_agrees_with_bash() {
  _hi_shell_agrees 'printf "%s|%s" "$(_hi_ssh_host_tag myhost)" "$(_hi_ssh_host_tag devhost)"'
}

# GLOSSARY: HI.37 - the two zsh divergences _hi_ssh_pattern_hit works around
# (word-splitting, then GLOB_SUBST) are each invisible to a bash-only suite
function test_zsh_host_tag_wildcard_agrees_with_bash() {
  _hi_ssh_tag_fixture >/dev/null
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

function run_core_tests() {
  _hi_workdir sharedtest

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

  _hi_h2 "Testing: _hi_resolve_color precedence"
  _hi_check "Exact override wins" test_resolve_color_override_wins
  _hi_check "Hosttag via ssh config" test_resolve_color_hosttag_via_ssh_config
  _hi_check "Usertag when no exact override" test_resolve_color_usertag_when_no_exact_override
  _hi_check "Falls back to the hash" test_resolve_color_falls_back_to_hash

  _hi_h2 "Testing: the settings overlay"
  _hi_check "settings.sh is sourced" test_settings_sh_is_sourced
  _hi_check_eq "Defaults to ~/.config/say-hi" say-hi _hi_cfg_answer neither
  _hi_check_eq "Uses say-hi when it exists" say-hi _hi_cfg_answer new
  _hi_check "An explicit \$_HI_CONFIG_DIR wins" test_config_dir_explicit_value_wins

  _hi_h2 "Testing: the same answers in zsh"
  _hi_check_requires zsh "_hi_hash_color agrees with bash" test_zsh_hash_color_agrees_with_bash
  _hi_check_requires zsh "_hi_ssh_host_tag agrees with bash" test_zsh_host_tag_agrees_with_bash
  _hi_check_requires zsh "...and rejects the same hosts" test_zsh_host_tag_rejects_the_same_hosts
  _hi_check_requires zsh "...and agrees on wildcard blocks" test_zsh_host_tag_wildcard_agrees_with_bash
  _hi_check_requires zsh "_hi_resolve_color agrees with bash" test_zsh_resolve_color_agrees_with_bash
  _hi_check_requires zsh "zsh.zsh leaves KSH_ARRAYS off" test_zsh_rc_leaves_ksharrays_alone
  _hi_check_requires zsh "zsh.zsh survives KSH_ARRAYS being on" test_zsh_rc_survives_ksharrays_being_on

  _hi_suite_end "core.sh"
}

run_core_tests
