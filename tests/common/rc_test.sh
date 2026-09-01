#!/usr/bin/env bash
# Behavioral tests for common/bash.sh, zsh.zsh and config.fish. Syntax-linting
# alone lets a prompt or completion silently stop being defined and still pass
# CI, so these run them. Each case runs a fresh shell under `env -i` with HOME
# and _HI_CONFIG_DIR pointed into the workdir, so local settings can't leak in.
#
# GLOSSARY: HI.30 + HI.34. The single-quoted scripts are expanded by the *child*
# shell, which is the whole point (SC2016).
# shellcheck disable=SC2329,SC2016
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# run <shell> -c <script> in the controlled environment; TERM comes first so
# cases can pick the color branch (xterm-256color) or the plain one (dumb)
function _hi_rc_shell() {
  local term="$1" shell="$2" script="$3"
  # anything after the script is NAME=VALUE for the child - `env -i` is what
  # keeps local settings out, so extra variables have to be injected here
  # rather than exported around the call
  shift 3
  env -i HOME="$_HI_WORKDIR" TERM="$term" PATH="$PATH" \
    _HI_HOME="$_HI_HOME" _HI_CONFIG_DIR="$_HI_WORKDIR/cfg" "$@" \
    "$shell" -c "$script" </dev/null
}

function test_bash_hi_ps1_contains_user_host_cwd() {
  local out
  out="$(_hi_rc_shell xterm-256color bash \
    'source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; printf %s "$HI_PS1"')"
  [[ "$out" == *'\u'* && "$out" == *@* && "$out" == *'\h'* && "$out" == *'\w'* ]]
}

# no color -> the exact plain form (common/bash.sh's else branch)
function test_bash_hi_ps1_plain_without_color() {
  local out
  out="$(_hi_rc_shell dumb bash \
    'source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; printf %s "$HI_PS1"')"
  [[ "$out" == *'\u@\h:\w' ]]
}

function test_bash_prompt_disabled_leaves_ps1_alone() {
  local out
  out="$(_HI_DISABLE_PROMPT=1 _hi_rc_shell xterm-256color bash \
    'export _HI_DISABLE_PROMPT=1; source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; printf %s "${HI_PS1:-}"')"
  [ -z "$out" ]
}

# Even with hi's own prompt off, the color hashing it would have used is
# still primed into plain variables - $_HI_HOST_ESC/$_HI_USER_ESC (the raw
# ANSI escape, bash's form) and $_HI_HOST_COLOR/$_HI_USER_COLOR (the color
# name, zsh's %F{} form) - so a custom PS1 in the user's own bash.sh/zsh.zsh
# can still use it, per docs/SETTINGS.md.
function test_bash_prompt_disabled_still_primes_color_variables() {
  local out host_esc user_esc host_color user_color
  out="$(_HI_DISABLE_PROMPT=1 _hi_rc_shell xterm-256color bash \
    'export _HI_DISABLE_PROMPT=1; source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null
     printf "%s\t%s\t%s\t%s" "$_HI_HOST_ESC" "$_HI_USER_ESC" "$_HI_HOST_COLOR" "$_HI_USER_COLOR"')"
  IFS=$'\t' read -r host_esc user_esc host_color user_color <<<"$out"
  [ -n "$host_esc" ] && [ -n "$user_esc" ] && [ -n "$host_color" ] && [ -n "$user_color" ]
}

function test_zsh_prompt_disabled_still_primes_color_variables() {
  local out host_color user_color
  out="$(_HI_DISABLE_PROMPT=1 _hi_rc_shell xterm-256color zsh \
    'export _HI_DISABLE_PROMPT=1; source "$_HI_HOME/say-hi/common/zsh.zsh" 2>/dev/null
     printf "%s\t%s" "$_HI_HOST_COLOR" "$_HI_USER_COLOR"')"
  IFS=$'\t' read -r host_color user_color <<<"$out"
  [ -n "$host_color" ] && [ -n "$user_color" ]
}

function test_bash_registers_hi_completion() {
  _hi_rc_shell xterm-256color bash \
    'source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; complete -p hi' |
    grep -qF '_hi_complete'
}

# What this case is really for: common/bash.sh's `source "$_HI_ALIASES"` line
# actually reaching the alias chain in a real bash. It asserts the four aliases
# hi installs on its own account - hi_copy and hi_notify are hi's, vim and nano
# the editor-rc wrappers - rather than any of the convenience aliases below them
# in the file, because these four are named by a toggle apiece and so are
# stable by contract - unlike `grep`/`mindiff`, named here before 8c5570a
# retired both while removing personal aliases for the first release and
# turned the case red with nothing in the chain actually wrong. Nothing here
# depends on a binary being installed - all four are defined by the file, not
# resolved from PATH.
function test_bash_defines_key_aliases() {
  _hi_rc_shell xterm-256color bash \
    'source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null
     for a in vim nano hi_copy hi_notify; do
       alias "$a" >/dev/null 2>&1 || { echo "missing alias: $a" >&2; exit 1; }
     done'
}

# ...and that the chain carries on past those four into the convenience set -
# sudo, the cat/bat and ls/eza families - now the tail of settings/aliases.sh,
# a settings/personal.sh of their own before. Sampled from the file
# rather than spelled here, on alias_test.sh's precedent: those names are still
# being retired entry by entry, and one written into this suite goes stale the
# next time one is dropped. The unguarded `alias` lines are exactly that tail -
# everything above it is defined behind a `[ ... ] &&` test, not at column 0.
# An empty sample is not a failure - it is what finishing that removal looks
# like - so it reports and passes, and this case can be deleted with the last
# alias in the file.
function test_bash_sources_the_convenience_aliases() {
  local sample
  sample="$(grep -oE '^alias +[A-Za-z_][A-Za-z0-9_]*=' "$_HI_ROOT/settings/aliases.sh" |
    sed -E 's/^alias +//; s/=$//' | tr '\n' ' ')"
  [ -n "$sample" ] || {
    _hi_cecho " | settings/aliases.sh defines no unguarded aliases left to sample" "$BLUE"
    return 0
  }
  _hi_rc_shell xterm-256color bash \
    "source \"\$_HI_HOME/say-hi/common/bash.sh\" 2>/dev/null
     for a in $sample; do
       alias \"\$a\" >/dev/null 2>&1 || { echo \"missing alias: \$a\" >&2; exit 1; }
     done"
}

# zsh/fish presence is handled by _hi_check_requires at the registration, so a
# machine without one still runs (and honestly reports) the rest.

# _HI_PROMPT=starship hands the prompt over when starship exists; a stub on a
# prepended PATH stands in for it, answering `init <shell>` with a line whose
# effect the case can see. Three assertions per family: deferred when asked
# and present, hi's prompt kept when not asked, and hi's prompt kept - with
# no error - when asked but starship is absent.
function _hi_starship_stub_dir() {
  local dir="$_HI_WORKDIR/starship-bin"
  [ -x "$dir/starship" ] || {
    mkdir -p "$dir"
    printf '#!/bin/sh\ncase "$2" in\nbash | zsh) echo "PS1=STARSHIP-STUB" ;;\nfish) echo "function fish_prompt; echo -n STARSHIP-STUB; end" ;;\nesac\n' >"$dir/starship"
    chmod +x "$dir/starship"
  }
  printf '%s' "$dir"
}

# One case for all three shells: the per-shell rc, prompt-print incantation
# and expected shape live in the case's own table. Extra NAME=VALUE arguments
# ride _hi_rc_shell (env applies the last assignment, so the prepended-PATH
# override wins over the baseline), so there is one `env -i` block here rather
# than one per case.
function test_defers_to_starship_when_asked() {
  local shell="$1" script want out
  case "$shell" in
  bash)
    script='source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; printf "%s|%s" "$PS1" "${HI_PS1:-unset}"'
    want="STARSHIP-STUB|unset"
    ;;
  zsh)
    script='source "$_HI_HOME/say-hi/common/zsh.zsh" 2>/dev/null; printf %s "$PS1"'
    want="STARSHIP-STUB"
    ;;
  fish)
    script='source $_HI_HOME/say-hi/common/config.fish 2>/dev/null; fish_prompt'
    want="*STARSHIP-STUB*"
    ;;
  esac
  out="$(_hi_rc_shell xterm-256color "$shell" "$script" \
    PATH="$(_hi_starship_stub_dir):$PATH" _HI_PROMPT=starship)"
  # shellcheck disable=SC2053 # $want is a pattern (fish's is a glob)
  [[ "$out" == $want ]]
}

function test_bash_keeps_hi_prompt_without_the_setting() {
  local out
  out="$(_hi_rc_shell xterm-256color bash \
    'source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; printf %s "$HI_PS1"' \
    PATH="$(_hi_starship_stub_dir):$PATH")"
  [[ "$out" == *'\u'* ]]
}

# Asked for, not installed: hi's prompt, and nothing on stderr. "Not
# installed" has to be manufactured - this machine may well carry starship
# (an Arch box does), so the case swaps $PATH for a toolbox of the real tools
# bash.sh needs, minus starship, rather than trusting the box to lack it.
function test_bash_falls_back_when_starship_is_absent() {
  local out
  out="$(_hi_rc_shell xterm-256color bash \
    'source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; printf %s "$HI_PS1"' \
    PATH="$(_hi_real_path starshipless bash sh sed awk grep tr cut hostname uname cksum git)" \
    _HI_PROMPT=starship 2>&1)"
  [[ "$out" == *'\u'* ]]
}

function test_zsh_prompt_is_built() {
  local out
  out="$(_hi_rc_shell xterm-256color zsh \
    'source "$_HI_HOME/say-hi/common/zsh.zsh" 2>/dev/null; print -r -- "$PS1"')"
  [[ "$out" == *%n* && "$out" == *@* && "$out" == *%m* ]]
}

function test_fish_registers_hi_completion() {
  # fish echoes the registration back without the -c flag, so match on the
  # target-list wiring instead
  _hi_rc_shell xterm-256color fish \
    'source $_HI_HOME/say-hi/common/config.fish 2>/dev/null; complete -c hi' |
    grep -qF '$_HI_TARGETS'
}

# bash and zsh answer a `-*` word from targets.sh's flags roster and never
# touch the target cache, because a flag list must not wait on a docker daemon.
# fish keeps that promise only if the target completion carries the negated
# condition: an unconditional one fires the whole backend sweep alongside the
# flags on every `hi --<TAB>`.
# The two cases below actually *run* a completion rather than reading the
# registration back. Both shells reach the same roster bash.sh does, and
# reading the registration back is only structural coverage - fish's guard
# grepped for as a string, zsh's dash branch not exercised at all.
#
# zsh's `compadd` needs a real completion context, so it is stubbed: `-a` is
# handed the array's *name*, which is what ${(P)} dereferences. zsh's locals
# are dynamically scoped, so _hi's `flags` is visible from inside the stub.
function test_zsh_flag_completion_offers_hi_options() {
  local out
  out="$(_hi_rc_shell xterm-256color zsh '
    source $_HI_HOME/say-hi/common/zsh.zsh 2>/dev/null
    compadd() { local -a a; [[ $1 == -a ]] && a=(${(P)2}); print -l -- $a }
    words=(hi --c); CURRENT=2
    _hi
  ')"
  printf '%s\n' "$out" | grep -qx -- --doctor &&
    printf '%s\n' "$out" | grep -qx -- --color-preview
}

# fish does its own prefix matching, so `--col` narrows to the one flag. A tab
# in the output would be a target row ("<name>\t<kind>"), which is the sweep
# the -n guard exists to keep out of a dash word.
function test_fish_flag_completion_offers_hi_options() {
  local out
  out="$(_hi_rc_shell xterm-256color fish '
    source $_HI_HOME/say-hi/common/config.fish 2>/dev/null
    complete -C "hi --col"
  ')"
  printf '%s\n' "$out" | grep -qx -- --color-preview || return 1
  if printf '%s\n' "$out" | grep -q "$(printf '\t')"; then
    _hi_cecho "   a dash word also swept the targets" "$RED"
    return 1
  fi
  return 0
}

function test_fish_flag_completion_does_not_also_sweep_targets() {
  local out
  out="$(_hi_rc_shell xterm-256color fish \
    'source $_HI_HOME/say-hi/common/config.fish 2>/dev/null; complete -c hi')"
  # the bare-target line is guarded, and the flags line still is too
  printf '%s\n' "$out" | grep -qF 'not string match -q -- "-*"' &&
    printf '%s\n' "$out" | grep -qF '$_HI_TARGETS flags'
}

# The character each prompt ends with is a setting now (core.sh's
# _hi_prompt_end, mirrored in config.fish), with three different shipped
# defaults. Each case renders the real prompt in the real shell rather than
# grepping the rc, since the whole risk here is a value that reaches $PS1 in a
# form the shell then mangles.

# the last non-blank characters of the prompt the shell actually built.
# $_HI_AS_ROOT=yes/no shadows fish's root test either way: fish is the only one
# of the three whose prompt is *run* here (bash and zsh are read as raw $PS1),
# so without the shadow which branch a case takes depends on who invoked CI -
# and the FreeBSD VM, like most container images, is root.
function _hi_prompt_tail() {
  local shell="$1" script root=""
  shift
  case "${_HI_AS_ROOT:-}" in
  yes) root='function fish_is_root_user; return 0; end; ' ;;
  no) root='function fish_is_root_user; return 1; end; ' ;;
  esac
  case "$shell" in
  bash) script='source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; ps1; printf %s "$PS1"' ;;
  zsh) script='source "$_HI_HOME/say-hi/common/zsh.zsh" 2>/dev/null; print -rn -- "$PS1"' ;;
  fish) script="source \$_HI_HOME/say-hi/common/config.fish 2>/dev/null; $root fish_prompt" ;;
  esac
  # the OSC 133 mark that closes every prompt (and bash's \[ \] around it)
  # is not part of the separator, so it comes off before the tail is read
  _hi_strip_ansi "$(_hi_rc_shell xterm-256color "$shell" "$script" "$@")" |
    sed -e $'s/\x1b\\][^\x07]*\x07//g' -e 's/\\\[//g' -e 's/\\\]//g' -e 's/%{%}//g'
}

# the shipped defaults, one per shell: bash's `\$` (which bash itself renders as
# $ for a user and # for root), zsh's `>`, fish's `|`
function test_prompt_end_default() {
  local shell="$1" want="$2" out
  out="$(_HI_AS_ROOT=no _hi_prompt_tail "$shell")"
  case "${out% }" in
  *"$want") return 0 ;;
  esac
  return 1
}

function test_prompt_end_shell_specific() {
  local shell="$1" var="$2" out
  out="$(_HI_AS_ROOT=no _hi_prompt_tail "$shell" "$var=@@")"
  case "${out% }" in
  *@@) return 0 ;;
  esac
  return 1
}

# the one setting that covers all three, for people who want the same character
# everywhere - the shell-specific one still wins over it
function test_prompt_end_global_fallback() {
  local shell="$1" out
  out="$(_HI_AS_ROOT=no _hi_prompt_tail "$shell" _HI_PROMPT_END=%%)"
  case "${out% }" in
  *%%) return 0 ;;
  esac
  return 1
}

function test_prompt_end_specific_beats_global() {
  local shell="$1" var="$2" out
  out="$(_HI_AS_ROOT=no _hi_prompt_tail "$shell" _HI_PROMPT_END=%% "$var=@@")"
  case "${out% }" in
  *@@) return 0 ;;
  esac
  return 1
}

# an empty value is "unset", not "no separator": a prompt ending in a bare space
# is never what someone meant, and ' ' still expresses it
function test_prompt_end_empty_falls_back() {
  local shell="$1" var="$2" want="$3" out
  out="$(_HI_AS_ROOT=no _hi_prompt_tail "$shell" "$var=")"
  case "${out% }" in
  *"$want") return 0 ;;
  esac
  return 1
}

# Root gets '#' - but as the *default* giving way, never as an override, which
# is the rule bash's shipped `\$` follows (it renders as # for root, and an
# explicit _HI_PROMPT_END_BASH still wins). fish is the only shell where that
# decision is made in hi's own code rather than by the shell, so it is the only
# one with a case. Run through the shadow, so it covers the branch on a
# non-root box too.
function test_prompt_end_root_takes_the_default() {
  local out
  out="$(_HI_AS_ROOT=yes _hi_prompt_tail fish)"
  case "${out% }" in *'#') return 0 ;; esac
  return 1
}

function test_prompt_end_root_keeps_an_explicit_one() {
  local out
  out="$(_HI_AS_ROOT=yes _hi_prompt_tail fish _HI_PROMPT_END_FISH=@@)"
  case "${out% }" in *@@) return 0 ;; esac
  return 1
}

#
# fish cannot call a bash helper, so common/config.fish carries its own copy of
# common/core.sh's overlay-directory resolution. Two copies of one decision is
# exactly the shape that drifts, so these cases run fish's and compare with the
# answers tests/common/core_test.sh pins bash's against.
#
# _HI_CONFIG_DIR has to come out of the environment here (the helper above sets
# it for every other case), which is why this runs fish directly.
function _hi_fish_cfg_answer() {
  local base="$_HI_WORKDIR/fishxdg.$1" out
  rm -rf "$base"
  mkdir -p "$base"
  case "$1" in
  new) mkdir -p "$base/say-hi" ;;
  esac
  out="$(env -i HOME="$_HI_WORKDIR" TERM=dumb PATH="$PATH" \
    _HI_HOME="$_HI_HOME" XDG_CONFIG_HOME="$base" \
    fish -c 'source $_HI_HOME/say-hi/common/config.fish 2>/dev/null; printf %s $_HI_CONFIG_DIR' </dev/null)"
  printf '%s' "${out#"$base/"}"
}

function test_fish_config_dir_matches_bash() {
  [ "$(_hi_fish_cfg_answer neither)" = say-hi ] &&
    [ "$(_hi_fish_cfg_answer new)" = say-hi ]
}

# hi.sh points a target at its shipped overlay; fish must honour that too
function test_fish_config_dir_explicit_value_wins() {
  local base="$_HI_WORKDIR/fishxdg.explicit" out
  rm -rf "$base"
  mkdir -p "$base/say-hi"
  out="$(env -i HOME="$_HI_WORKDIR" TERM=dumb PATH="$PATH" \
    _HI_HOME="$_HI_HOME" XDG_CONFIG_HOME="$base" _HI_CONFIG_DIR="$base/shipped" \
    fish -c 'source $_HI_HOME/say-hi/common/config.fish 2>/dev/null; printf %s $_HI_CONFIG_DIR' </dev/null)"
  [ "$out" = "$base/shipped" ]
}

#
# core.sh's system-settings layer, hand-mirrored in config.fish - the same
# fish-vs-bash drift risk as the overlay-directory resolution above. bash's
# half is pinned in core_test.sh; these pin fish's.
function test_fish_system_settings_apply_locally() {
  local sys="$_HI_WORKDIR/fish.sys.settings.sh"
  printf 'export _HI_PROBE=system\n' >"$sys"
  [ "$(env -i HOME="$_HI_WORKDIR" TERM=dumb PATH="$PATH" \
    _HI_HOME="$_HI_HOME" XDG_CONFIG_HOME="$_HI_WORKDIR/fishsys.a" \
    _HI_SYSTEM_SETTINGS="$sys" \
    fish -c 'source $_HI_HOME/say-hi/common/config.fish 2>/dev/null; printf %s $_HI_PROBE' </dev/null)" = system ]
}

function test_fish_system_settings_skipped_remotely() {
  local sys="$_HI_WORKDIR/fish.sys.settings.sh"
  printf 'export _HI_PROBE=system\n' >"$sys"
  [ -z "$(env -i HOME="$_HI_WORKDIR" TERM=dumb PATH="$PATH" \
    _HI_HOME="$_HI_HOME" XDG_CONFIG_HOME="$_HI_WORKDIR/fishsys.b" \
    _HI_SYSTEM_SETTINGS="$sys" _HI_REMOTE_SESSION=1 \
    fish -c 'source $_HI_HOME/say-hi/common/config.fish 2>/dev/null; printf %s $_HI_PROBE' </dev/null)" ]
}

#
# hi ships nobody's taste per shell - no history sizing, keybindings,
# completion or color styling of its own. What it ships is the hook for yours:
# the user's own file in $_HI_CONFIG_DIR, named for the *shell file* it
# extends (bash.sh, zsh.zsh, config.fish).
#
# Two things have to stay true per shell, and the second is why the first is
# worth asserting: hi ships no default of its own for these settings,
# and the user's file is sourced and applies. The no-file case is the regression
# guard on the removal - a preference creeping back into a shipped rc shows up
# here as a probe that stopped agreeing with a bare shell's.
#
# <shell>|<user file, and the rc it extends>|<probe read>|<user line>|<user value>
#
# That naming is why the second field doubles as the rc to source -
# `source "$_HI_HOME/say-hi/common/$file"` parses in bash and fish both - and
# the third is the read on its own. Keeping the two apart is what lets the probe
# run the read *without* hi's rc, for the baseline the no-file case measures
# against.
#
# zsh's row here was HISTFILE once, proving hi shipped no history preference
# at all; hi touches no shell's history now, so the row is gone.
_HI_SHELL_OVERRIDE_ROWS=(
  'bash|bash.sh|printf %s "${PROMPT_DIRTRIM:-}"|PROMPT_DIRTRIM=9|9'
  'fish|config.fish|printf %s "$fish_color_command"|set -gx fish_color_command magenta|magenta'
)

# _hi_shell_override_probe <row> <none|user|bare> - the row's read, run with
# hi's rc and no user file (none), with both (user), or with neither (bare).
function _hi_shell_override_probe() {
  local row="$1" mode="$2"
  local shell file script line value src=""
  IFS='|' read -r shell file script line value <<<"$row"
  rm -f "$_HI_WORKDIR/cfg/$file"
  [ "$mode" = user ] && printf '%s\n' "$line" >"$_HI_WORKDIR/cfg/$file"
  [ "$mode" = bare ] || src='source "$_HI_HOME/say-hi/common/'"$file"'" 2>/dev/null; '
  _hi_rc_shell xterm-256color "$shell" "$src$script"
}

# The shipped rc sets none of these - measured against the same shell *without*
# it rather than against the empty string, because a bare shell does not always
# answer empty: fish 4.0 through 4.6 set every fish_color_* in a `fish -c` too,
# which 4.7 stopped and fish 3 never did. Reading "hi changed nothing" off an
# absolute value made this case a report on the local fish build; as a
# difference it still fails the day a preference lands back in a shipped rc.
function test_shell_ships_no_preference_default() {
  [ "$(_hi_shell_override_probe "$1" none)" = "$(_hi_shell_override_probe "$1" bare)" ]
}

function test_shell_user_file_applies() {
  local row="$1" shell file script line value
  IFS='|' read -r shell file script line value <<<"$row"
  [ "$(_hi_shell_override_probe "$row" user)" = "$value" ]
}

function run_rc_tests() {
  _hi_workdir rctest
  mkdir -p "$_HI_WORKDIR/cfg"

  _hi_suite_begin

  _hi_h1 "Testing common/bash.sh, zsh.zsh and config.fish behavior"

  _hi_h2 "Testing: bash"
  _hi_check "HI_PS1 carries user, host and cwd" test_bash_hi_ps1_contains_user_host_cwd
  _hi_check "Plain HI_PS1 without color" test_bash_hi_ps1_plain_without_color
  _hi_check "_HI_DISABLE_PROMPT leaves it unset" test_bash_prompt_disabled_leaves_ps1_alone
  _hi_check "...but still primes the color variables (bash)" test_bash_prompt_disabled_still_primes_color_variables
  _hi_check_requires zsh "...and in zsh too" test_zsh_prompt_disabled_still_primes_color_variables
  _hi_check "hi completion is registered" test_bash_registers_hi_completion
  _hi_check "Key aliases are defined" test_bash_defines_key_aliases
  _hi_check "The convenience aliases land too" test_bash_sources_the_convenience_aliases

  _hi_h2 "Testing: zsh and fish"
  _hi_check_requires zsh "zsh builds its prompt" test_zsh_prompt_is_built
  _hi_check_requires zsh "zsh flag TAB completes hi's options" test_zsh_flag_completion_offers_hi_options

  _hi_h2 "Testing: the per-shell override files"
  local _hi_row _hi_sh
  for _hi_row in "${_HI_SHELL_OVERRIDE_ROWS[@]}"; do
    _hi_sh="${_hi_row%%|*}"
    _hi_check_requires "$_hi_sh" "[$_hi_sh] hi ships no preference of its own" \
      test_shell_ships_no_preference_default "$_hi_row"
    _hi_check_requires "$_hi_sh" "[$_hi_sh] the user's own file applies" \
      test_shell_user_file_applies "$_hi_row"
  done

  _hi_h2 "Testing: starship deference (_HI_PROMPT=starship)"
  _hi_check "[bash] defers when asked and present" test_defers_to_starship_when_asked bash
  _hi_check "[bash] keeps hi's prompt without the setting" test_bash_keeps_hi_prompt_without_the_setting
  _hi_check "[bash] falls back silently when absent" test_bash_falls_back_when_starship_is_absent
  _hi_check_requires zsh "[zsh] defers when asked and present" test_defers_to_starship_when_asked zsh
  _hi_check_requires fish "[fish] defers when asked and present" test_defers_to_starship_when_asked fish
  _hi_check_requires fish "fish registers hi completion" test_fish_registers_hi_completion
  _hi_check_requires fish "fish flag TAB does not sweep the backends" test_fish_flag_completion_does_not_also_sweep_targets
  _hi_check_requires fish "fish flag TAB completes hi's options" test_fish_flag_completion_offers_hi_options
  _hi_check_requires fish "fish resolves \$_HI_CONFIG_DIR as bash does" test_fish_config_dir_matches_bash
  _hi_check_requires fish "fish honours an explicit \$_HI_CONFIG_DIR" test_fish_config_dir_explicit_value_wins
  _hi_check_requires fish "fish sources the system layer locally" test_fish_system_settings_apply_locally
  _hi_check_requires fish "...and skips it in a remote session" test_fish_system_settings_skipped_remotely

  _hi_h2 "Testing: the prompt separator"
  # the shells install.sh wires up locally, and their shipped defaults, both
  # read off core.sh's rosters rather than spelled again here
  local shell upper var default
  for shell in $(_hi_shell_rows local | cut -d'|' -f1); do
    upper="$(printf '%s' "$shell" | tr '[:lower:]' '[:upper:]')"
    var="_HI_PROMPT_END_$upper"
    # bash's default ships as the two characters `\$`, which bash renders as $
    # for a user and # for root; these cases run as a user, so the leading
    # backslash comes off before comparing against a rendered prompt.
    default="$(_hi_prompt_end_default "$upper")"
    default="${default#\\}"
    _hi_check_requires "$shell" "[$shell] default is '$default'" test_prompt_end_default "$shell" "$default"
    _hi_check_requires "$shell" "[$shell] $var wins" test_prompt_end_shell_specific "$shell" "$var"
    _hi_check_requires "$shell" "[$shell] _HI_PROMPT_END covers it" test_prompt_end_global_fallback "$shell"
    _hi_check_requires "$shell" "[$shell] the specific one beats it" test_prompt_end_specific_beats_global "$shell" "$var"
    _hi_check_requires "$shell" "[$shell] empty falls back to '$default'" test_prompt_end_empty_falls_back "$shell" "$var" "$default"
  done
  _hi_check_requires fish "[fish] root takes '#' over the default" test_prompt_end_root_takes_the_default
  _hi_check_requires fish "[fish] root keeps an explicit one" test_prompt_end_root_keeps_an_explicit_one

  _hi_suite_end "rc"
}

run_rc_tests
