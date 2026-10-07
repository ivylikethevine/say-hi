#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# common/core.sh's host tags, the color a name resolves to, the settings
# overlay, and the same answers in zsh.
# A part of core_test.sh, a suite of its own so the Windows shards split them.
# The preamble's source line is core_test.sh's - it sources the harness, and
# holds the helpers the parts share (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329,SC2016
set -euo pipefail

_HI_CORE_PART=identity
# shellcheck source=./core_test.sh
source "${BASH_SOURCE[0]%/*}/core_test.sh"

# _hi_fixture_tag <host> - _hi_ssh_host_tag against the fixture above
function _hi_fixture_tag() { _HI_SSH_CONFIG="$_HI_SSH_TAG_FIXTURE" _hi_ssh_host_tag "$@"; }

function test_ssh_host_tag_leftmost_of_multiple() {
  [ "$(_hi_fixture_tag myhost)" = "prod" ]
}

# A relayed hop: the middle box's config knows the host and carries no tag,
# so the client's tag map (the overlay's ssh_tags) answers - on a target only,
# and the rc of a host neither file tags is still the local walk's.
function test_ssh_host_tag_falls_back_to_the_clients_map_on_a_relay() {
  local dir="$_HI_WORKDIR/relaytags"
  mkdir -p "$dir"
  unset _HI_TAG_NAME # the one-deep memo is keyed on the name, not on these
  printf '# Tags: fromclient\nHost untaggedhost far-*\n' >"$dir/ssh_tags"
  [ "$(_HI_REMOTE_SESSION=1 _HI_CONFIG_DIR="$dir" _hi_fixture_tag untaggedhost)" = fromclient ] || return 1
  [ "$(_HI_REMOTE_SESSION=1 _HI_CONFIG_DIR="$dir" _hi_fixture_tag far-1)" = fromclient ] || return 1
  [ "$(_HI_REMOTE_SESSION=1 _HI_CONFIG_DIR="$dir" _hi_fixture_tag myhost)" = prod ] || return 1
  [ -z "$(_HI_CONFIG_DIR="$dir" _hi_fixture_tag untaggedhost)" ] || return 1
  local rc=0
  _HI_REMOTE_SESSION=1 _HI_CONFIG_DIR="$dir" _hi_fixture_tag nope >/dev/null || rc=$?
  [ "$rc" = 1 ]
}

# a tag set in an Included file colors its host, and an Include between a tag
# and a Host ends the tag there, as any other line does
function test_ssh_host_tag_follows_include() {
  local h="$_HI_WORKDIR/inc-tags"
  mkdir -p "$h/.ssh/config.d"
  printf 'Include config.d/*\n# Tags: orphan\nInclude none/*\nHost after\n' >"$h/.ssh/config"
  printf '# Tags: inc\nHost included\n' >"$h/.ssh/config.d/01"
  unset _HI_TAG_NAME
  [ "$(HOME="$h" _HI_SSH_CONFIG="$h/.ssh/config" _hi_ssh_host_tag included)" = inc ] || return 1
  unset _HI_TAG_NAME
  [ -z "$(HOME="$h" _HI_SSH_CONFIG="$h/.ssh/config" _hi_ssh_host_tag after)" ]
}

# a matching untagged block earlier in the file does not end the walk: a
# leading `Host *` of defaults marks every name known (rc 2) and the walk
# goes on to the tagged block below it, as ssh reads on past a first match
function test_ssh_host_tag_survives_a_leading_untagged_wildcard() {
  local cfg="$_HI_WORKDIR/ssh_config.leadingstar" rc=0
  printf 'Host *\n  AddKeysToAgent yes\n\n# Tags: prod\nHost behind\n' >"$cfg"
  unset _HI_TAG_NAME
  [ "$(_HI_SSH_CONFIG="$cfg" _hi_ssh_host_tag behind)" = prod ] || return 1
  unset _HI_TAG_NAME
  _HI_SSH_CONFIG="$cfg" _hi_ssh_host_tag elsewhere >/dev/null || rc=$?
  [ "$rc" -eq 2 ]
}

# a blank line between the Tags comment and its Host does not drop the tag -
# only another Host or Match line does
function test_ssh_host_tag_survives_a_blank_line_before_its_host() {
  local cfg="$_HI_WORKDIR/ssh_config.blankline"
  printf '# Tags: spaced\n\nHost gap\n' >"$cfg"
  unset _HI_TAG_NAME
  [ "$(_HI_SSH_CONFIG="$cfg" _hi_ssh_host_tag gap)" = spaced ]
}

function test_ssh_host_tag_untagged_host_fails() {
  ! _hi_fixture_tag untaggedhost
}

function test_ssh_host_tag_equals_syntax_and_multialias() {
  [ "$(_hi_fixture_tag devhost)" = "dev" ] || return 1
  [ "$(_hi_fixture_tag otheralias)" = "dev" ]
}

function test_ssh_host_tag_unknown_host_fails() {
  ! _hi_fixture_tag no-such-host
}

# ssh reads its keywords case-insensitively, and targets.sh's awk agrees - a
# lowercase `host` entry once completed and dispatched as ssh while its tag
# was silently never found
function test_ssh_host_tag_matches_lowercase_host_keyword() {
  [ "$(_hi_fixture_tag lowerhost)" = "lower" ]
}

# the walker's rc is a three-way contract: 0 tagged, 2 known-but-untagged,
# 1 unknown - rc 2 is what hi.sh's _hi_is_ssh_host dispatches on
function test_ssh_host_tag_return_codes() {
  local rc
  _hi_fixture_tag untaggedhost >/dev/null
  rc=$?
  [ "$rc" -eq 2 ] || return 1
  _hi_fixture_tag no-such-host >/dev/null
  rc=$?
  [ "$rc" -eq 1 ]
}

function test_ssh_host_tag_wildcard_host_block() {
  [ "$(_hi_fixture_tag prod-web1)" = "prod" ]
}

# "prod" alone is not "prod-anything" - a bare miss must not fall through to
# the wildcard block that happens to share its prefix
function test_ssh_host_tag_wildcard_requires_the_dash() {
  ! _hi_fixture_tag prod
}

function test_ssh_host_tag_match_host_comma_patterns() {
  [ "$(_hi_fixture_tag staging-db1)" = "staging" ] || return 1
  [ "$(_hi_fixture_tag staging2-x)" = "staging" ]
}

function test_ssh_host_tag_wildcard_untagged_block_is_rc_2() {
  local rc
  _hi_fixture_tag wilduntagged-abc >/dev/null
  rc=$?
  [ "$rc" -eq 2 ]
}

# documented tradeoff (GLOSSARY: HI.37): a "!" token is inert, not honored as
# ssh's own negation, so web-99 still inherits the block's tag despite being
# explicitly excluded there. Pinned so a future change to this is deliberate.
function test_ssh_host_tag_negation_token_is_inert_not_exclusionary() {
  [ "$(_hi_fixture_tag web-99)" = "excluded" ]
}

# `Match host` takes further criteria after its patterns (user, exec,
# canonical, ...); those words are not host patterns, so a host that happens
# to be called "deploy" must not inherit the block's tag - only bastion-* does
function test_ssh_host_tag_match_criteria_are_not_patterns() {
  [ "$(_hi_fixture_tag bastion-2)" = "bastion" ] || return 1
  local rc=0
  _hi_fixture_tag deploy >/dev/null || rc=$?
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
  [ "$(_hi_fixture_tag canary-1)" = "canary" ] || return 1
  local rc=0
  _hi_fixture_tag build >/dev/null || rc=$?
  [ "$rc" -eq 1 ] || return 1

  [ "$(_hi_fixture_tag robot-1)" = "robot" ] || return 1

  [ "$(_hi_fixture_tag lastcall-1)" = "lastword" ]
}

# a Match on anything but host opens a block of its own, so the tag comment
# above it belongs to that block and never carries onto the next Host line
function test_ssh_host_tag_non_host_match_ends_its_tag() {
  local rc=0
  _hi_fixture_tag afternobody >/dev/null || rc=$?
  [ "$rc" -eq 2 ]
}

function test_resolve_color_override_wins() {
  local colors="$_HI_WORKDIR/colors.resolve1"
  printf '[username]\nbob = "red"\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _hi_resolve_color username bob)" = "red" ]
}

function test_resolve_color_hosttag_via_ssh_config() {
  local colors="$_HI_WORKDIR/colors.resolve2"
  printf '[hosttag]\nprod = "blue"\n' >"$colors"
  [ "$(_HI_SSH_CONFIG="$_HI_SSH_TAG_FIXTURE" _HI_COLORS="$colors" _hi_resolve_color hostname myhost)" = "blue" ]
}

function test_resolve_color_usertag_when_no_exact_override() {
  local colors="$_HI_WORKDIR/colors.resolve3"
  printf '[usertag]\nprodtag = "green"\n' >"$colors"
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
  printf '[hostname]\n"10.0.1.*" = "red"\n"*.prod.example" = "blue"\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _hi_resolve_color hostname 10.0.1.7)" = red ] || return 1
  [ "$(_HI_COLORS="$colors" _hi_resolve_color hostname db.prod.example)" = blue ] || return 1
  ! _HI_COLORS="$colors" _hi_colors_pattern hostname 10.0.2.7
}

function test_pattern_first_row_wins() {
  local colors="$_HI_WORKDIR/colors.patorder"
  printf '[hostname]\n"10.0.*" = "green"\n"10.0.1.*" = "red"\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _hi_resolve_color hostname 10.0.1.7)" = green ]
}

function test_exact_pin_beats_pattern() {
  local colors="$_HI_WORKDIR/colors.patexact"
  printf '[hostname]\n"10.0.1.*" = "red"\n"10.0.1.7" = "cyan"\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _hi_resolve_color hostname 10.0.1.7)" = cyan ]
}

function test_hosttag_beats_pattern() {
  local colors="$_HI_WORKDIR/colors.pattag"
  printf '[hostname]\n"myhost*" = "red"\n[hosttag]\nprod = "blue"\n' >"$colors"
  [ "$(_HI_SSH_CONFIG="$_HI_SSH_TAG_FIXTURE" _HI_COLORS="$colors" _hi_resolve_color hostname myhost)" = blue ]
}

function test_pattern_beats_hash() {
  local colors="$_HI_WORKDIR/colors.pathash"
  printf '[hostname]\n"unhashed-*" = "brred"\n' >"$colors"
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

# The patterns are a string to peel, never a list to expand: `for pat in $2`
# pathname-expands as well as word-splits, so a bare `*` - the commonest Host
# line there is - would become whatever files the cwd holds and match nothing.
# Run from a directory with files in it, which is the only place it shows.
function test_pattern_hit_does_not_glob_against_the_cwd() {
  local dir="$_HI_WORKDIR/pattern.cwd"
  mkdir -p "$dir"
  : >"$dir/aaa"
  : >"$dir/bbb"
  (
    cd "$dir" || return 1
    _hi_ssh_pattern_hit liona '*' || return 1
    _hi_ssh_pattern_hit prod-db 'prod-*' || return 1
    ! _hi_ssh_pattern_hit other 'prod-*'
  )
}

function test_zsh_pattern_hit_skips_the_same_tokens() {
  _hi_shell_agrees '_hi_ssh_pattern_hit myhost "x) hit=0 ;; case y in y"; printf "bad:%s " "$?"; _hi_ssh_pattern_hit myhost "my*"; printf "glob:%s" "$?"'
}

# the pattern walk rides _hi_ssh_pattern_hit, whose zsh divergences are HI.37's
function test_zsh_pattern_pins_agree_with_bash() {
  local colors="$_HI_WORKDIR/colors.zshpat" a b script
  printf '[hostname]\n"10.0.1.*" = "red"\n' >"$colors"
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

# hi.sh derives the same tree through its own symlink walk (the /usr/bin/hi
# or ~/.local/bin/hi link install makes points at it): an absolute link, a
# relative one reached through a directory (the `*/*` arm), and a relative
# one sourced by its bare name (the `*)` arm, no directory to prepend).
# Behind the symlink capability: Git Bash's `ln -s` copies the file unless
# native symlinks are on, and a copy outside the tree derives the wrong one.
function test_hi_sh_walks_its_symlinks_to_the_tree() {
  local d="$_HI_WORKDIR/hi-links" got
  mkdir -p "$d/bin"
  ln -sf "$_HI_HOME/say-hi/hi.sh" "$d/abs"
  ln -sf ../abs "$d/bin/rel"
  for got in \
    "$(env -u _HI_HOME -u _hi_core_loaded bash -c "set --; source '$d/abs'; printf '%s' \"\$_HI_HOME\"")" \
    "$(env -u _HI_HOME -u _hi_core_loaded bash -c "set --; source '$d/bin/rel'; printf '%s' \"\$_HI_HOME\"")" \
    "$(cd "$d/bin" && env -u _HI_HOME -u _hi_core_loaded bash -c 'set --; source rel; printf "%s" "$_HI_HOME"')"; do
    [ "$got" = "$_HI_HOME" ] || _hi_because "derived $got, not $_HI_HOME" || return 1
  done
}

# hi.sh stamps the connect clock before core.sh exists, with its own copy of
# _hi_now: a date(1) with no %N (old BSD) prints the N back, and the stamp is
# the whole seconds instead
function test_hi_sh_connect_clock_takes_whole_seconds_without_nanoseconds() {
  local dir="$_HI_WORKDIR/hi-bsd-date" got
  mkdir -p "$dir"
  printf '%s\n' '#!/bin/sh' 'case "$1" in +%s.%N) echo 1700000000.N ;; *) echo 1700000000 ;; esac' >"$dir/date"
  chmod +x "$dir/date"
  got="$(env -u _hi_core_loaded PATH="$dir:$PATH" bash -c \
    'unset EPOCHREALTIME; set --; source "$_HI_HOME/say-hi/hi.sh"; printf "%s" "$_HI_CONNECT_T0"')"
  [ "$got" = 1700000000 ] || _hi_because "_HI_CONNECT_T0: $got"
}

# That the user's settings.sh is sourced at all is paths_test.sh's
# test_settings_beat_the_defaults; the cases here are the layers around it.
#
#
# $_HI_CONFIG_DIR is derived from the XDG base, and an explicit value wins.
# core.sh's preamble runs once per shell and is guarded by $_hi_core_loaded,
# so there is no function to call: each case is a fresh bash sourcing core.sh.
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

# GLOSSARY: HI.60. $_HI_EXTENSIONS empty - a shell that loaded a tree from
# before it, re-sourcing its rc - makes "$_HI_EXTENSIONS"/* the glob /*,
# and _hi_load_extensions sources what it is handed: every file at the root
# of the disk that parses.
function test_extension_files_never_glob_the_root() {
  (
    _HI_EXTENSIONS=""
    _hi_members=(x) _hi_strays=(y)
    _hi_dir_members "$_HI_EXTENSIONS"
    [ "${#_hi_members[@]}" -eq 0 ] && [ "${#_hi_strays[@]}" -eq 0 ]
  )
}

# one listing for every directory of code (GLOSSARY: HI.58): the plain files
# in name order are its members, and what else is there is named apart, for
# hi --doctor - a backup, a directory, a name with a space
function test_dir_members_lists_members_and_strays() {
  local dir="$_HI_WORKDIR/dir-members"
  local -a _hi_members=() _hi_strays=()
  mkdir -p "$dir/sub"
  : >"$dir/20-b"
  : >"$dir/10-a.sh"
  : >"$dir/30-c.bak"
  : >"$dir/a b"
  _hi_dir_members "$dir"
  [ "${_hi_members[*]}" = "$dir/10-a.sh $dir/20-b" ] || _hi_because "members: ${_hi_members[*]}" || return 1
  [ "${#_hi_strays[@]}" = 3 ] || _hi_because "strays: ${_hi_strays[*]}" || return 1
  _hi_dir_members "$dir/none"
  [ "${#_hi_members[@]}" -eq 0 ] && [ "${#_hi_strays[@]}" -eq 0 ]
}

function test_zsh_hash_color_agrees_with_bash() {
  _hi_shell_agrees 'printf "%s,%s,%s" "$(_hi_hash_color alice)" "$(_hi_hash_color prod-db)" "$(_hi_hash_color x)"'
}

function test_zsh_scheme_escape_agrees_with_bash() {
  _hi_shell_agrees "export _HI_COLOR_SCHEME='$_HI_TEST_L24' _HI_TRUECOLOR=1; _hi_assign_palette; _hi_color_hex h brcyan; printf '%s|%s|%s' \"\$RED\" \"\$BRCYAN\" \"\$h\""
}

# the list form walks the setting by offset, which is where zsh and bash
# most easily part ways; both banks and the word count have to agree
function test_zsh_scheme_list_agrees_with_bash() {
  _hi_shell_agrees "export _HI_COLOR_SCHEME='$_HI_TEST_L48' _HI_TRUECOLOR=1; _hi_scheme_words n; _hi_assign_palette; _hi_color_hex h brcyan; _hi_color_escape_at e 17; printf '%s|%s|%s|%s|%s' \"\$n\" \"\$RED\" \"\$BRCYAN\" \"\$h\" \"\$e\""
}

# extended_glob (grml's and prezto's default, and common in a .zshrc) makes a
# bare # a pattern operator: a pin's hex and a Host line's trailing comment
# still split off the same as in bash
function test_zsh_extended_glob_agrees_with_bash() {
  local cfg="$_HI_WORKDIR/ssh_config.extglob" want='orange|3ba55d|red||eg' got
  printf '# Tags: eg\nHost eghost # a note\n' >"$cfg"
  got="$(_hi_in_shell zsh "setopt extended_glob; export _HI_SSH_CONFIG='$cfg'
    _hi_color_split b h \"orange#3ba55d\"; _hi_color_split b2 h2 red
    printf '%s|%s|%s|%s|%s' \"\$b\" \"\$h\" \"\$b2\" \"\$h2\" \"\$(_hi_ssh_host_tag eghost)\"")"
  [ "$got" = "$want" ] || _hi_because "zsh: [$got]" || return 1
  got="$(_hi_in_shell bash "export _HI_SSH_CONFIG='$cfg'
    _hi_color_split b h \"orange#3ba55d\"; _hi_color_split b2 h2 red
    printf '%s|%s|%s|%s|%s' \"\$b\" \"\$h\" \"\$b2\" \"\$h2\" \"\$(_hi_ssh_host_tag eghost)\"")"
  [ "$got" = "$want" ] || _hi_because "bash: [$got]"
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

# _hi_unexport <shell> - the _HI_* names a child of <shell> sees, sorted,
# after core.sh, every roster name exported, two strays beside them, and
# _hi_unexport: exactly the roster, from the one call that un-exports the rest
function _hi_unexported_env() {
  env _HI_HOME="$_HI_HOME" _HI_PROBE_UX1=a _HI_PROBE_UX2=b "$1" -c '
    source "$_HI_HOME/say-hi/common/core.sh"
    for n in "${_HI_CHILD_ENV[@]}"; do eval "export $n=\"\${$n-set}\""; done
    _hi_unexport
    env | grep -o "^_HI_[A-Za-z0-9_]*" | sort | tr "\n" " "' 2>/dev/null
}

function test_unexport_leaves_exactly_the_roster() {
  local want out
  want="$(printf '%s\n' "${_HI_CHILD_ENV[@]}" | sort | tr '\n' ' ')"
  out="$(_hi_unexported_env "$1")"
  [ "$out" = "$want" ] || {
    _hi_cecho " | $1 exports: $out" "$RED"
    _hi_cecho " | roster:     $want" "$RED"
    return 1
  }
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

function run_core_identity_tests() {
  _hi_core_begin

  _hi_h1 "Testing common/core.sh (tags, colors, and settings)"

  _hi_h2 "Testing: _hi_ssh_host_tag"
  _hi_check "Leftmost tag of a multi-tag comment" test_ssh_host_tag_leftmost_of_multiple
  _hi_check "A tag in an Included file colors its host" test_ssh_host_tag_follows_include
  _hi_check "A leading untagged Host * does not end the walk" test_ssh_host_tag_survives_a_leading_untagged_wildcard
  _hi_check "A blank line before its Host keeps the tag" test_ssh_host_tag_survives_a_blank_line_before_its_host
  _hi_check "Untagged host fails" test_ssh_host_tag_untagged_host_fails
  _hi_check "A relayed hop reads the client's tag map" test_ssh_host_tag_falls_back_to_the_clients_map_on_a_relay
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
  _hi_check "...localuser, exec, canonical, and final too" test_ssh_host_tag_match_criteria_localuser_exec_canonical_final
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
  _hi_check "Patterns are not globbed against the cwd" test_pattern_hit_does_not_glob_against_the_cwd
  _hi_check_requires zsh "zsh skips the same tokens" test_zsh_pattern_hit_skips_the_same_tokens
  _hi_check_requires zsh "Pattern pins agree in zsh" test_zsh_pattern_pins_agree_with_bash

  _hi_h2 "Testing: _hi_on_exit / _hi_setting_get / _hi_unexport"
  _hi_check "_hi_on_exit installs a trap that fires in bash" test_on_exit_installs_a_trap_that_fires_in_bash
  _hi_check "_hi_setting_get: rc 1 for a missing file and an unset name" test_setting_get_fails_for_a_missing_file_and_an_unset_name
  _hi_check "_hi_unexport keeps the value, drops the export bit" test_unexport_keeps_values_and_drops_the_export_bit
  _hi_check "...leaving exactly \$_HI_CHILD_ENV exported" test_unexport_leaves_exactly_the_roster bash
  _hi_check_requires zsh "...in zsh too" test_unexport_leaves_exactly_the_roster zsh

  _hi_h2 "Testing: HI.33's bash arm - \$_HI_HOME self-derivation"
  _hi_check "sourced by its real path with \$_HI_HOME unset" test_hi_home_self_derives_when_unset
  _hi_check "...and by a bare relative name from its own directory" test_hi_home_self_derives_from_a_bare_relative_source
  _hi_check_capable symlink "hi.sh walks its symlinks to the same tree" test_hi_sh_walks_its_symlinks_to_the_tree
  _hi_check "hi.sh's connect clock takes whole seconds from a date(1) with no %N" \
    test_hi_sh_connect_clock_takes_whole_seconds_without_nanoseconds

  _hi_h2 "Testing: the settings overlay"
  _hi_check_eq "Defaults to ~/.config/say-hi" say-hi _hi_cfg_answer neither
  _hi_check_eq "Uses say-hi when it exists" say-hi _hi_cfg_answer new
  _hi_check "An explicit \$_HI_CONFIG_DIR wins" test_config_dir_explicit_value_wins
  _hi_check "An empty extensions/ globs nothing, never /" test_extension_files_never_glob_the_root
  _hi_check "A directory of code lists its members, and its strays apart" test_dir_members_lists_members_and_strays

  _hi_h2 "Testing: the same answers in zsh"
  _hi_check_requires zsh "_hi_hash_color agrees with bash" test_zsh_hash_color_agrees_with_bash
  _hi_check_requires zsh "A scheme escape agrees with bash" test_zsh_scheme_escape_agrees_with_bash
  _hi_check_requires zsh "A scheme list agrees with bash" test_zsh_scheme_list_agrees_with_bash
  _hi_check_requires zsh "_hi_ssh_host_tag agrees with bash" test_zsh_host_tag_agrees_with_bash
  _hi_check_requires zsh "...and under extended_glob, a # still splits a pin and a comment" test_zsh_extended_glob_agrees_with_bash
  _hi_check_requires zsh "...and rejects the same hosts" test_zsh_host_tag_rejects_the_same_hosts
  _hi_check_requires zsh "...and agrees on wildcard blocks" test_zsh_host_tag_wildcard_agrees_with_bash
  _hi_check_requires zsh "_hi_resolve_color agrees with bash" test_zsh_resolve_color_agrees_with_bash
  _hi_check_requires zsh "zsh.zsh leaves KSH_ARRAYS off" test_zsh_rc_leaves_ksharrays_alone
  _hi_check_requires zsh "zsh.zsh survives KSH_ARRAYS being on" test_zsh_rc_survives_ksharrays_being_on

  _hi_suite_end "core.sh (tags, colors, and settings)"
}

run_core_identity_tests
