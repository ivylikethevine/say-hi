#!/bin/bash
# Behavioral tests for shells/bash.sh, zsh.zsh and config.fish. Syntax-linting
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
    'source "$_HI_HOME/say-hi/shells/bash.sh" 2>/dev/null; printf %s "$HI_PS1"')"
  [[ "$out" == *'\u'* && "$out" == *@* && "$out" == *'\h'* && "$out" == *'\w'* ]]
}

# no color -> the exact plain form (shells/bash.sh's else branch)
function test_bash_hi_ps1_plain_without_color() {
  local out
  out="$(_hi_rc_shell dumb bash \
    'source "$_HI_HOME/say-hi/shells/bash.sh" 2>/dev/null; printf %s "$HI_PS1"')"
  [[ "$out" == *'\u@\h:\w' ]]
}

function test_bash_prompt_disabled_leaves_ps1_alone() {
  local out
  out="$(_HI_DISABLE_PROMPT=1 _hi_rc_shell xterm-256color bash \
    'export _HI_DISABLE_PROMPT=1; source "$_HI_HOME/say-hi/shells/bash.sh" 2>/dev/null; printf %s "${HI_PS1:-}"')"
  [ -z "$out" ]
}

function test_bash_registers_hi_completion() {
  _hi_rc_shell xterm-256color bash \
    'source "$_HI_HOME/say-hi/shells/bash.sh" 2>/dev/null; complete -p hi' |
    grep -qF '_hi_complete'
}

function test_bash_defines_key_aliases() {
  _hi_rc_shell xterm-256color bash \
    'source "$_HI_HOME/say-hi/shells/bash.sh" 2>/dev/null; alias grep && alias mindiff' >/dev/null
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
    script='source "$_HI_HOME/say-hi/shells/bash.sh" 2>/dev/null; printf "%s|%s" "$PS1" "${HI_PS1:-unset}"'
    want="STARSHIP-STUB|unset"
    ;;
  zsh)
    script='source "$_HI_HOME/say-hi/shells/zsh.zsh" 2>/dev/null; printf %s "$PS1"'
    want="STARSHIP-STUB"
    ;;
  fish)
    script='source $_HI_HOME/say-hi/shells/config.fish 2>/dev/null; fish_prompt'
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
    'source "$_HI_HOME/say-hi/shells/bash.sh" 2>/dev/null; printf %s "$HI_PS1"' \
    PATH="$(_hi_starship_stub_dir):$PATH")"
  [[ "$out" == *'\u'* ]]
}

# asked for, not installed: hi's prompt, and nothing on stderr
function test_bash_falls_back_when_starship_is_absent() {
  local out
  out="$(_hi_rc_shell xterm-256color bash \
    'source "$_HI_HOME/say-hi/shells/bash.sh" 2>/dev/null; printf %s "$HI_PS1"' \
    _HI_PROMPT=starship 2>&1)"
  [[ "$out" == *'\u'* ]]
}

function test_zsh_prompt_is_built() {
  local out
  out="$(_hi_rc_shell xterm-256color zsh \
    'source "$_HI_HOME/say-hi/shells/zsh.zsh" 2>/dev/null; print -r -- "$PS1"')"
  [[ "$out" == *%n* && "$out" == *@* && "$out" == *%m* ]]
}

function test_fish_registers_hi_completion() {
  # fish echoes the registration back without the -c flag, so match on the
  # target-list wiring instead
  _hi_rc_shell xterm-256color fish \
    'source $_HI_HOME/say-hi/shells/config.fish 2>/dev/null; complete -c hi' |
    grep -qF '$_HI_TARGETS'
}

# bash and zsh answer a `-*` word from targets.sh's flags roster and never
# touch the target cache, because a flag list must not wait on a docker daemon.
# fish keeps that promise only if the target completion carries the negated
# condition: an unconditional one fires the whole backend sweep alongside the
# flags on every `hi --<TAB>`.
# The two cases below actually *run* a completion rather than reading the
# registration back. Both shells reach the same roster bash.sh does, and both
# had only structural coverage until now - fish's guard was grepped for as a
# string, zsh's dash branch was not covered at all.
#
# zsh's `compadd` needs a real completion context, so it is stubbed: `-a` is
# handed the array's *name*, which is what ${(P)} dereferences. zsh's locals
# are dynamically scoped, so _hi's `flags` is visible from inside the stub.
function test_zsh_flag_completion_offers_hi_options() {
  local out
  out="$(_hi_rc_shell xterm-256color zsh '
    source $_HI_HOME/say-hi/shells/zsh.zsh 2>/dev/null
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
    source $_HI_HOME/say-hi/shells/config.fish 2>/dev/null
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
    'source $_HI_HOME/say-hi/shells/config.fish 2>/dev/null; complete -c hi')"
  # the bare-target line is guarded, and the flags line still is too
  printf '%s\n' "$out" | grep -qF 'not string match -q -- "-*"' &&
    printf '%s\n' "$out" | grep -qF '$_HI_TARGETS flags'
}

# The character each prompt ends with is a setting now (core.sh's
# _hi_prompt_end, mirrored in config.fish), with three different shipped
# defaults. Each case renders the real prompt in the real shell rather than
# grepping the rc, since the whole risk here is a value that reaches $PS1 in a
# form the shell then mangles.

# the last non-blank characters of the prompt the shell actually built
function _hi_prompt_tail() {
  local shell="$1" script
  shift
  case "$shell" in
  bash) script='source "$_HI_HOME/say-hi/shells/bash.sh" 2>/dev/null; ps1; printf %s "$PS1"' ;;
  zsh) script='source "$_HI_HOME/say-hi/shells/zsh.zsh" 2>/dev/null; print -rn -- "$PS1"' ;;
  fish) script='source $_HI_HOME/say-hi/shells/config.fish 2>/dev/null; fish_prompt' ;;
  esac
  _hi_strip_ansi "$(_hi_rc_shell xterm-256color "$shell" "$script" "$@")"
}

# the shipped defaults, one per shell: bash's `\$` (which bash itself renders as
# $ for a user and # for root), zsh's `>`, fish's `|`
function test_prompt_end_default() {
  local shell="$1" want="$2" out
  out="$(_hi_prompt_tail "$shell")"
  case "${out% }" in
  *"$want") return 0 ;;
  esac
  return 1
}

function test_prompt_end_shell_specific() {
  local shell="$1" var="$2" out
  out="$(_hi_prompt_tail "$shell" "$var=@@")"
  case "${out% }" in
  *@@) return 0 ;;
  esac
  return 1
}

# the one setting that covers all three, for people who want the same character
# everywhere - the shell-specific one still wins over it
function test_prompt_end_global_fallback() {
  local shell="$1" out
  out="$(_hi_prompt_tail "$shell" _HI_PROMPT_END=%%)"
  case "${out% }" in
  *%%) return 0 ;;
  esac
  return 1
}

function test_prompt_end_specific_beats_global() {
  local shell="$1" var="$2" out
  out="$(_hi_prompt_tail "$shell" _HI_PROMPT_END=%% "$var=@@")"
  case "${out% }" in
  *@@) return 0 ;;
  esac
  return 1
}

# an empty value is "unset", not "no separator": a prompt ending in a bare space
# is never what someone meant, and ' ' still expresses it
function test_prompt_end_empty_falls_back() {
  local shell="$1" var="$2" want="$3" out
  out="$(_hi_prompt_tail "$shell" "$var=")"
  case "${out% }" in
  *"$want") return 0 ;;
  esac
  return 1
}

# --- config.fish's $_HI_CONFIG_DIR ladder ------------------------------------
#
# fish cannot call a bash helper, so shells/config.fish carries its own copy of
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
    fish -c 'source $_HI_HOME/say-hi/shells/config.fish 2>/dev/null; printf %s $_HI_CONFIG_DIR' </dev/null)"
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
    fish -c 'source $_HI_HOME/say-hi/shells/config.fish 2>/dev/null; printf %s $_HI_CONFIG_DIR' </dev/null)"
  [ "$out" = "$base/shipped" ]
}

# --- the personal blocks, now their own overridable files --------------------
#
# Each shell's taste (history sizing, keybindings, completion and color styling)
# moved out of the shipped rc into shells/<shell>_personal.*, on
# misc/personal.sh's precedent. Three things have to stay true per shell, and
# the third is the one the split exists for: hi's defaults load, the toggle
# turns *those* off, and the user's own copy in $_HI_CONFIG_DIR is sourced after
# and wins - including when the toggle is on, because the toggle is about hi's
# taste, not the user's.
#
# <shell>|<user file>|<probe script>|<shipped value>|<user line>|<user value>
_HI_PERSONAL_ROWS=(
  'bash|bash_personal.sh|source "$_HI_HOME/say-hi/shells/bash.sh" 2>/dev/null; printf %s "${PROMPT_DIRTRIM:-}"|2|PROMPT_DIRTRIM=9|9'
  'zsh|zsh_personal.zsh|source "$_HI_HOME/say-hi/shells/zsh.zsh" 2>/dev/null; printf %s "${HISTFILE:-}"|.zsh_history|HISTFILE=/tmp/hi.sentinel|/tmp/hi.sentinel'
  'fish|fish_personal.fish|source $_HI_HOME/say-hi/shells/config.fish 2>/dev/null; printf %s "$fish_color_command"|blue|set -gx fish_color_command magenta|magenta'
)

# the probe for one row, with the user's file present only when $2 says so
function _hi_personal_probe() {
  local row="$1" want_user="$2" toggle="$3"
  local shell file script shipped line value
  IFS='|' read -r shell file script shipped line value <<<"$row"
  rm -f "$_HI_WORKDIR/cfg/$file"
  [ "$want_user" = yes ] && printf '%s\n' "$line" >"$_HI_WORKDIR/cfg/$file"
  _hi_rc_shell xterm-256color "$shell" "$script" _HI_DISABLE_PERSONAL="$toggle"
}

function test_personal_defaults_load() {
  local row="$1" shell file script shipped
  IFS='|' read -r shell file script shipped _ _ <<<"$row"
  case "$(_hi_personal_probe "$row" no 0)" in *"$shipped"*) return 0 ;; esac
  return 1
}

function test_personal_toggle_turns_them_off() {
  [ -z "$(_hi_personal_probe "$1" no 1)" ]
}

function test_personal_user_file_wins() {
  local row="$1" shell file script shipped line value
  IFS='|' read -r shell file script shipped line value <<<"$row"
  [ "$(_hi_personal_probe "$row" yes 0)" = "$value" ]
}

# The toggle is hi's taste, not yours - so a user file still applies with it on.
# This is the half that would silently regress if the guard were folded into the
# same condition as the shipped source.
function test_personal_user_file_survives_the_toggle() {
  local row="$1" shell file script shipped line value
  IFS='|' read -r shell file script shipped line value <<<"$row"
  [ "$(_hi_personal_probe "$row" yes 1)" = "$value" ]
}

function run_rc_tests() {
  _hi_workdir rctest
  mkdir -p "$_HI_WORKDIR/cfg"

  _hi_suite_begin

  _hi_h1 "Testing shells/bash.sh, zsh.zsh and config.fish behavior"

  _hi_h2 "Testing: bash"
  _hi_check "HI_PS1 carries user, host and cwd" test_bash_hi_ps1_contains_user_host_cwd
  _hi_check "Plain HI_PS1 without color" test_bash_hi_ps1_plain_without_color
  _hi_check "_HI_DISABLE_PROMPT leaves it unset" test_bash_prompt_disabled_leaves_ps1_alone
  _hi_check "hi completion is registered" test_bash_registers_hi_completion
  _hi_check "Key aliases are defined" test_bash_defines_key_aliases

  _hi_h2 "Testing: zsh and fish"
  _hi_check_requires zsh "zsh builds its prompt" test_zsh_prompt_is_built
  _hi_check_requires zsh "zsh flag TAB completes hi's options" test_zsh_flag_completion_offers_hi_options

  _hi_h2 "Testing: the personal blocks as overridable files"
  local _hi_row _hi_sh
  for _hi_row in "${_HI_PERSONAL_ROWS[@]}"; do
    _hi_sh="${_hi_row%%|*}"
    _hi_check_requires "$_hi_sh" "[$_hi_sh] hi's defaults load" \
      test_personal_defaults_load "$_hi_row"
    _hi_check_requires "$_hi_sh" "[$_hi_sh] _HI_DISABLE_PERSONAL turns them off" \
      test_personal_toggle_turns_them_off "$_hi_row"
    _hi_check_requires "$_hi_sh" "[$_hi_sh] the user's own file wins" \
      test_personal_user_file_wins "$_hi_row"
    _hi_check_requires "$_hi_sh" "[$_hi_sh] the user's file survives the toggle" \
      test_personal_user_file_survives_the_toggle "$_hi_row"
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

  _hi_suite_end "rc"
}

run_rc_tests
