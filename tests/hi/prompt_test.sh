#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Unit tests for hi.sh: the prompt the bash-less tiers get.
# common/config.fish renders a git segment without common/git_prompt.sh, so it
# carries its own copy of core.sh's palette and glyphs. Much of this file is the
# drift guard on that copy.
#
# Sourcing hi.sh goes through the same `[[ BASH_SOURCE == $0 ]]` hatch install.sh
# uses, which defines every function without connecting to anything - so the pure
# half is reachable here, where a mis-parse is an assertion rather than a
# confusing connection failure. _say_hi stays e2e-only by nature.
#
# GLOSSARY: HI.30 + HI.34. The linter follows `source "$_HI_LAUNCHER"` into hi.sh's
# trailing `_hi "$@"`, decides it never returns, and marks this file unreachable
# (SC2317) - it does not model the BASH_SOURCE guard. The single-quoted strings
# below are the target's to expand, not ours (SC2016).
# shellcheck disable=SC2329,SC2317,SC2016
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"
# shellcheck source=../../hi.sh
source "$_HI_LAUNCHER"

# core.sh's answer for a set of names, from a subshell so the suite's own glyph
# choice is untouched. <prefix> is the core-side variable family.
function _hi_core_values() {
  local prefix="$1" ascii="$2" name
  shift 2
  (
    _HI_ASCII="$ascii"
    _hi_choose_glyphs
    for name in "$@"; do
      eval "printf '%s=%s\n' \"$name\" \"\${$prefix$name}\""
    done
  )
}

# fish renders its git segment with its own __fish_git_prompt, so config.fish
# carries a second copy of the glyphs and palette - one say-hi never guarded. The
# cases below read the file rather than running fish: the copy is a set of
# literals, so parsing them is the whole check, and it holds on a runner with
# no fish installed (which is where the drift would land unnoticed).

# <role>=<value> per line, for the char_/color_ family named by $1
function _hi_fish_settings() {
  sed -n "s/^ *set -g __fish_git_prompt_$1_\([a-z_]*\) '\{0,1\}\([^']*\)'\{0,1\}\$/\1=\2/p" \
    "$_HI_ROOT/common/config.fish"
}

function _hi_fish_agrees() {
  local label="$1" a="$2" b="$3"
  [ -n "$a" ] && [ "$a" = "$b" ] && return 0
  _hi_cecho " | $label: config.fish and core.sh disagree -" "$RED"
  printf 'config.fish:\n%s\ncore.sh:\n%s\n' "$a" "$b" | sed 's/^/      /'
  return 1
}

# config.fish only overrides the glyphs on the ASCII side - the UTF-8 ones are
# fish's own - so the ASCII set is the copy, and this is the guard on it. Role
# names are fish's; the values have to be core.sh's _HI_ASCII=1 answers.
_HI_FISH_GLYPH_ROLES=("upstream_ahead:AHEAD" "upstream_behind:BEHIND"
  "stagedstate:STAGED" "dirtystate:DIRTY" "invalidstate:INVALID"
  "untrackedfiles:UNTRACKED" "stashstate:STASH" "cleanstate:CLEAN")
function test_fish_ascii_glyphs_match_core() {
  local pair role name want=""
  for pair in "${_HI_FISH_GLYPH_ROLES[@]}"; do
    role="${pair%%:*}"
    name="${pair#*:}"
    want="$want$role=$(_hi_core_values _HI_GLYPH_ 1 "$name" | sed 's/^[A-Z_]*=//')"$'\n'
  done
  _hi_fish_agrees "ascii glyphs" "$(_hi_fish_settings char)" "$(printf '%s' "$want")"
}

# the palette copy: fish names colors, core.sh spells escapes, and
# _hi_color_escape is the bridge - so a renamed color that stops resolving to
# the escape the bash tier uses for the same role fails here
_HI_FISH_COLOR_ROLES=("branch:BRPURPLE" "stagedstate:YELLOW"
  "invalidstate:RED" "cleanstate:BRGREEN")
function test_fish_colors_match_core() {
  local pair role var fish_name got want mismatch=""
  for pair in "${_HI_FISH_COLOR_ROLES[@]}"; do
    role="${pair%%:*}"
    var="${pair#*:}"
    fish_name="$(_hi_fish_settings color | sed -n "s/^$role=//p")"
    [ -n "$fish_name" ] || {
      _hi_cecho " | config.fish sets no color for $role" "$RED"
      return 1
    }
    got="$(_hi_color_escape "$fish_name")"
    eval "want=\"\${$var}\""
    want="$(_hi_rendered "$want")"
    [ "$got" = "$want" ] || mismatch="$mismatch $role($fish_name vs $var)"
  done
  [ -z "$mismatch" ] || {
    _hi_cecho " | color roles disagree:$mismatch" "$RED"
    return 1
  }
}

# fish's default is `|`, bash's `\$`, zsh's `>` - three answers, and config.fish
# cannot call _hi_prompt_end_default to get its own. This is that pin.
function test_fish_prompt_end_default_matches_core() {
  local fish_default core_default
  fish_default="$(sed -n "s/^set -g _hi_prompt_end '\(.*\)'\$/\1/p" \
    "$_HI_ROOT/common/config.fish")"
  core_default="$(_hi_prompt_end_default FISH)"
  [ -n "$fish_default" ] && [ "$fish_default" = "$core_default" ] || {
    _hi_cecho " | config.fish: '$fish_default'  core.sh: '$core_default'" "$RED"
    return 1
  }
}

# the branch is shortened at the same width in both implementations, or the
# same repo renders a different branch name per shell
function test_branch_shorten_length_agrees() {
  local missing=""
  grep -q 'shorten_branch_len 32' "$_HI_ROOT/common/config.fish" ||
    missing="$missing config.fish"
  grep -q '#ref} > 32' "$_HI_ROOT/common/git_prompt.sh" ||
    missing="$missing git_prompt.sh"
  [ -z "$missing" ] || {
    _hi_cecho " | not shortening at 32:$missing" "$RED"
    return 1
  }
}

# sh/ash/dash sessions get hi's prompt, not the host's own (on busybox a
# bare "$"). The line hi writes has to survive shells with no readline and no
# command substitution in PS1, so it bakes everything in on the client and
# leaves exactly one escape for the target to expand.

# one line, so one case reads all of it: the username resolved once by the rc
# rather than per prompt, the host without its user@ part, a color from hi's own
# palette, the separator left for the shell (\$ - $ for a user, # for root), and
# no `$( )` inside PS1, which busybox ash would not expand anyway
function test_fallback_prompt_carries_user_host_and_color() {
  local out ps1
  out="$(DOMAIN=hitest@myhost _hi_fallback_prompt)"
  ps1="$(printf '%s\n' "$out" | sed -n 's/^PS1=//p')"
  [[ "$out" == *'_hi_u=$(id -un'* ]] || return 1
  [[ "$ps1" == *myhost* && "$ps1" == *$'\e['* ]] || return 1
  [[ "$ps1" == *'\$ "'* && "$ps1" != *'$('* ]]
}

# the separator is a setting everywhere else, so it is one here too
function test_fallback_prompt_honors_the_separator_setting() {
  [[ "$(_HI_PROMPT_END_BASH='>>' DOMAIN=hitest@myhost _hi_fallback_prompt)" == *'>> "'* ]]
}

# ...and the bash-less prompt takes bash's own separator, not one of its own:
# the two look alike on purpose, and one row fewer to freeze
function test_fallback_prompt_takes_the_bash_separator() {
  [[ "$(_HI_PROMPT_END_BASH='%%' DOMAIN=hitest@myhost _hi_fallback_prompt)" == *'%% "'* ]]
}

function test_fallback_prompt_respects_the_toggle() {
  [ -z "$(_HI_DISABLE_PROMPT=1 DOMAIN=hitest@myhost _hi_fallback_prompt)" ]
}

# the whole point: a real POSIX shell renders it without complaint
function test_fallback_prompt_renders_in_dash() {
  local out
  out="$(DOMAIN=hitest@myhost _hi_fallback_prompt |
    dash -s -c '. /dev/stdin; printf %s "$PS1"' 2>&1)" || return 1
  [[ "$out" == *myhost* && "$out" != *'id -un'* ]]
}

# The shared rc must NOT carry it: that file is also fed to fish, which has no
# PS1 and stops dead on the line, and to zsh, where `\$` is not this escape.
# The POSIX arm appends it instead - which is what the suffix below shows.
function test_fallback_rc_stays_shell_agnostic() {
  local out
  out="$(DOMAIN=hitest@myhost CMDARG="" _hi_fallback_rc)"
  [[ "$out" != *PS1=* ]]
}

function test_remote_suffix_appends_the_prompt_for_posix_shells() {
  local out
  out="$(DOMAIN=hitest@myhost _hi_remote_suffix)"
  # the append lands after the fish arm - on the POSIX arm, which is the
  # first one past fish - and every arm that appends also exports ENV
  _hi_before "$out" 'fish -C' '>> "\$_hi_rc_dir/.hi_fallback_rc"' &&
    _hi_before "$out" '>> "\$_hi_rc_dir/.hi_fallback_rc"' 'ENV='
}

# --- the environment segment's fish copy (GLOSSARY: HI.54) -------------------
#
# config.fish cannot call common/env_prompt.sh and a `bash -c` per prompt draw
# is the fork this prompt refuses, so fish carries its own copy of the source
# list. These are the pins on it: a tool added to one file and not the other
# means the same shell session names a different set of environments depending
# on which shell you are in.

# the words $_HI_ENV_ORDER_DEFAULT is built from, one per line
function _hi_env_sources_core() {
  sed -n 's/^_HI_ENV_ORDER_DEFAULT="\(.*\)"$/\1/p' "$_HI_ROOT/common/env_prompt.sh" |
    tr ' ' '\n'
}

# the same list as config.fish's `set -l order ...` spells it
function _hi_env_sources_fish() {
  sed -n 's/^ *set -l order \(.*\)$/\1/p' "$_HI_ROOT/common/config.fish" |
    tr ' ' '\n'
}

function test_fish_env_order_default_matches_env_prompt() {
  _hi_fish_agrees "environment sources" \
    "$(_hi_env_sources_fish)" "$(_hi_env_sources_core)"
}

# the default list is also the roster both files branch on: a word in the
# default with no arm behind it would silently name nothing
function test_fish_env_sources_all_have_an_arm() {
  local word missing=""
  for word in $(_hi_env_sources_core); do
    grep -q "^ *$word)" "$_HI_ROOT/common/env_prompt.sh" ||
      missing="$missing env_prompt.sh:$word"
    grep -q "^ *case $word\$" "$_HI_ROOT/common/config.fish" ||
      missing="$missing config.fish:$word"
  done
  [ -z "$missing" ] || {
    _hi_cecho " | source words with no branch:$missing" "$RED"
    return 1
  }
}

# every tool variable one file reads, the other has to read too
_HI_ENV_VARS_READ=(MISE_SHELL ASDF_DIR PYENV_VERSION RBENV_VERSION
  NODENV_VERSION IN_NIX_SHELL GUIX_ENVIRONMENT DEVBOX_SHELL_ENABLED
  DEVENV_ROOT DIRENV_DIR CONDA_DEFAULT_ENV CONDA_PROMPT_MODIFIER
  VIRTUAL_ENV VIRTUAL_ENV_PROMPT)
function test_fish_env_reads_the_same_variables() {
  local var missing=""
  # -F with both spellings: env_prompt.sh writes "${VAR:-}" under `set -u`,
  # config.fish a bare "$VAR"
  for var in "${_HI_ENV_VARS_READ[@]}"; do
    grep -qF -e "\${$var" -e "\$$var" "$_HI_ROOT/common/env_prompt.sh" ||
      missing="$missing env_prompt.sh:$var"
    grep -qF -e "\${$var" -e "\$$var" "$_HI_ROOT/common/config.fish" ||
      missing="$missing config.fish:$var"
  done
  [ -z "$missing" ] || {
    _hi_cecho " | tool variables read by only one copy:$missing" "$RED"
    return 1
  }
}

# the config filenames the mise walk stats, one per line, sorted: the bash copy
# spells them `-f "$_hi_dir/<name>"`, the fish copy `test -f "$dir/<name>"`
function _hi_mise_configs() {
  grep -o -- '-f "\$[_a-z]*dir/[^"]*"' "$1" | sed 's|.*dir/||; s|"$||' | sort
}

function test_fish_mise_walks_the_same_config_names() {
  _hi_fish_agrees "mise config names" \
    "$(_hi_mise_configs "$_HI_ROOT/common/config.fish")" \
    "$(_hi_mise_configs "$_HI_ROOT/common/env_prompt.sh")"
}

# the segment is truncated at the same width, with core.sh's own ellipsis in
# both glyph sets - config.fish's copy is two literals
function test_fish_env_truncation_matches_core() {
  local utf8 ascii want_utf8 want_ascii missing=""
  grep -q 'string sub -l 31' "$_HI_ROOT/common/config.fish" ||
    missing="$missing config.fish:width"
  grep -q '#_hi_out} > 32' "$_HI_ROOT/common/env_prompt.sh" ||
    missing="$missing env_prompt.sh:width"
  utf8="$(sed -n 's/^set -g _hi_env_ellipsis \(.*\)$/\1/p' "$_HI_ROOT/common/config.fish")"
  ascii="$(sed -n "s/^ *set -g _hi_env_ellipsis '\(.*\)'\$/\1/p" "$_HI_ROOT/common/config.fish")"
  want_utf8="$(_hi_core_values _HI_GLYPH_ 0 ELLIPSIS | sed 's/^[A-Z_]*=//')"
  want_ascii="$(_hi_core_values _HI_GLYPH_ 1 ELLIPSIS | sed 's/^[A-Z_]*=//')"
  [ "$utf8" = "$want_utf8" ] || missing="$missing ellipsis($utf8 vs $want_utf8)"
  [ "$ascii" = "$want_ascii" ] || missing="$missing ascii-ellipsis($ascii vs $want_ascii)"
  [ -z "$missing" ] || {
    _hi_cecho " | truncation disagrees:$missing" "$RED"
    return 1
  }
}

# one color for the segment, named the same way in each shell's own vocabulary:
# bash embeds the palette variable, zsh the %F{} name (which has no bright
# variants - see the note above zsh.zsh's USER_COLOR block), fish the color name
function test_fish_env_color_matches_the_other_shells() {
  local missing=""
  grep -q '\\\[\$BRCYAN\\\]' "$_HI_ROOT/common/bash.sh" || missing="$missing bash.sh"
  grep -q '%F{cyan}\${__hi_env_info}' "$_HI_ROOT/common/zsh.zsh" || missing="$missing zsh.zsh"
  grep -q 'set_color brcyan' "$_HI_ROOT/common/config.fish" || missing="$missing config.fish"
  [ -z "$missing" ] || {
    _hi_cecho " | the environment segment is uncolored in:$missing" "$RED"
    return 1
  }
}

function run_hi_prompt_tests() {
  _hi_workdir hiprompttest

  _hi_suite_begin

  _hi_h1 "Testing hi.sh: the bash-less prompt"

  _hi_h2 "Testing: the bash-less prompt"
  _hi_check "Carries user, host, color, and separator" test_fallback_prompt_carries_user_host_and_color
  _hi_check "_HI_PROMPT_END_BASH applies here too" test_fallback_prompt_honors_the_separator_setting
  _hi_check "_HI_PROMPT_END_BASH is the sh prompt's too" test_fallback_prompt_takes_the_bash_separator
  _hi_check "_HI_DISABLE_PROMPT skips it" test_fallback_prompt_respects_the_toggle
  _hi_check_requires dash "Renders in a real dash" test_fallback_prompt_renders_in_dash
  _hi_check "The shared rc stays shell-agnostic" test_fallback_rc_stays_shell_agnostic
  _hi_check "The POSIX arm appends it" test_remote_suffix_appends_the_prompt_for_posix_shells

  _hi_h2 "Testing: the fish git segment's copies"
  _hi_check "config.fish's ascii glyphs match core.sh" test_fish_ascii_glyphs_match_core
  _hi_check "config.fish's colors match core.sh" test_fish_colors_match_core
  _hi_check "config.fish's prompt end matches core.sh" test_fish_prompt_end_default_matches_core
  _hi_check "Both segments shorten at 32" test_branch_shorten_length_agrees

  _hi_h2 "Testing: the fish environment segment's copy"
  _hi_check "config.fish's source list matches env_prompt.sh" test_fish_env_order_default_matches_env_prompt
  _hi_check "Every source word has a branch in both" test_fish_env_sources_all_have_an_arm
  _hi_check "Both copies read the same tool variables" test_fish_env_reads_the_same_variables
  _hi_check "Both mise walks look for the same files" test_fish_mise_walks_the_same_config_names
  _hi_check "Both truncate at 32 with core.sh's ellipsis" test_fish_env_truncation_matches_core
  _hi_check "All three shells color the segment" test_fish_env_color_matches_the_other_shells
  _hi_suite_end "hi.sh (the bash-less prompt)"
}

run_hi_prompt_tests
