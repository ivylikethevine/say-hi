#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Behavioral tests for common/bash.sh, zsh.zsh, and config.fish. Syntax-linting
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
  local -a trace=()
  # anything after the script is NAME=VALUE for the child - `env -i` is what
  # keeps local settings out, so extra variables have to be injected here
  # rather than exported around the call
  shift 3
  # ...and under a coverage tracer (xtrace on, into its own fd) the three
  # variables it traces a bash child through, which `env -i` would strip:
  # without them every bash.sh line these cases run read as untested
  if [ "$shell" = bash ] && [ -n "${BASH_XTRACEFD:-}" ] && [[ $- == *x* ]]; then
    trace=(SHELLOPTS=xtrace "PS4=$PS4" "BASH_XTRACEFD=$BASH_XTRACEFD")
  fi
  env -i HOME="$_HI_WORKDIR" TERM="$term" PATH="$PATH" _HI_PROMPT_TOOL="$_HI_PROMPT_TOOL" \
    _HI_HOME="$_HI_HOME" _HI_CONFIG_DIR="$_HI_WORKDIR/cfg" ${trace[@]+"${trace[@]}"} "$@" \
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

# readline counts every $PS1 byte it isn't told to ignore; an unmarked escape
# makes a typed line wrap back over the prompt. _hi_ps_mark wraps each
# \e[...m run in \001...\002 - only defined on the color branch, so xterm.
function test_bash_ps_mark_wraps_color_escapes() {
  local out want
  out="$(_hi_rc_shell xterm-256color bash \
    'source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null
     x="$(printf "\033[31mred\033[0m")"
     _hi_ps_mark x
     printf %s "$x"')"
  want=$'\001\e[31m\002red\001\e[0m\002'
  [ "$out" = "$want" ]
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
# actually reaching the alias chain in a real bash. Sampled from the file
# rather than spelled here, on alias_test.sh's precedent: those names change
# entry by entry, and one written into this suite goes stale the
# next time one is dropped. The unguarded `alias` lines are exactly that tail -
# everything above it is defined behind a `[ ... ] &&` test, not at column 0.
# An empty sample is not a failure - the file has no unguarded alias left - so
# it reports and passes, and this case can be deleted with the last alias in
# the file.
function test_bash_sources_the_convenience_aliases() {
  local sample
  sample="$(grep -oE '^alias +[A-Za-z_][A-Za-z0-9_]*=' "$_HI_ROOT/common/aliases.sh" |
    sed -E 's/^alias +//; s/=$//' | tr '\n' ' ')"
  [ -n "$sample" ] || {
    _hi_cecho " | common/aliases.sh defines no unguarded aliases left to sample" "$BLUE"
    return 0
  }
  _hi_rc_shell xterm-256color bash \
    "source \"\$_HI_HOME/say-hi/common/bash.sh\" 2>/dev/null
     for a in $sample; do
       alias \"\$a\" >/dev/null 2>&1 || { echo \"missing alias: \$a\" >&2; exit 1; }
     done"
}

# A plain child bash rather than _hi_rc_shell's `env -i`, for the cases below
# on bash.sh's prompt-time and completion machinery: they read nothing ambient
# beyond $HOME and $_HI_CONFIG_DIR, both redirected here, and a full
# environment keeps the child measurable by coverage tooling, which `env -i`
# silently is not - the same child-bash shape targets_test.sh's _hi_complete
# cases use. Later NAME=VALUE pairs win over the baseline, as in _hi_rc_shell.
function _hi_bash_child() {
  local script="$1"
  shift
  env HOME="$_HI_WORKDIR" TERM=xterm-256color _HI_CONFIG_DIR="$_HI_WORKDIR/cfg" "$@" \
    bash -c "$script" </dev/null
}

# __hi_ps1 runs per prompt: OSC 133;D must carry the *last* command's status and
# OSC 7 the cwd (the D/A pair kitty/WezTerm/ghostty jump and report by), and
# $PS1 itself must open with the A mark and close with B.
function test_bash_ps1_reports_status_and_cwd_marks() {
  local out
  # captured, so not a terminal: the gate is forced open here and has its own
  # case below
  out="$(_hi_bash_child '
    source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null
    _hi_marks_on() { :; }
    cd "$HOME" || exit 1
    (exit 7)
    __hi_ps1
    printf %s "$PS1"')"
  [[ "$out" == *$'\e]133;D;7\a'* ]] &&
    [[ "$out" == *$'\e]7;file://'*"$_HI_WORKDIR"$'\a'* ]] &&
    [[ "$out" == *$'\e]133;A'* && "$out" == *$'\e]133;B'* ]]
}

# zsh's prompt_subst stays the user's with the prompt disabled
function test_zsh_keeps_the_users_prompt_subst() {
  local out
  out="$(_hi_rc_shell xterm-256color zsh \
    '_HI_DISABLE_PROMPT=1 zsh -fc "source \$_HI_HOME/say-hi/common/zsh.zsh >/dev/null 2>&1; [[ -o prompt_subst ]] || printf off"')"
  [ "$out" = off ]
}

# <shell>: hi exports nothing for other tools (GCC_COLORS, CLICOLOR, LSCOLORS,
# LESSOPEN), and its palette is the shell's own - set, never exported
_HI_FOREIGN_ENV="GCC_COLORS CLICOLOR LSCOLORS LESSOPEN NC RED GREEN YELLOW BLUE PURPLE CYAN BRRED BRGREEN BRYELLOW BRBLUE BRPURPLE BRCYAN"

function test_rc_exports_nothing_for_other_tools() {
  local rc=bash.sh out
  [ "$1" = zsh ] && rc=zsh.zsh
  out="$(_hi_rc_shell xterm-256color "$1" 'source "$_HI_HOME/say-hi/common/'"$rc"'" >/dev/null 2>&1
    printf "%s|" "${NC+set}${RED+set}"
    for v in '"$_HI_FOREIGN_ENV"'; do
      env | grep -q "^$v=" && printf "%s " "$v"
    done')"
  [ "$out" = "setset|" ] || {
    _hi_cecho " | $1: [$out]" "$RED"
    return 1
  }
}

# <shell>: the styled tool aliases and the sudo alias are opt-ins - none in a
# stock session, every one with _HI_TOOL_ALIASES=1 and _HI_SUDO_ALIAS=1. ls
# is asked of bash and zsh only: fish ships an ls function of its own.
function test_rc_tool_and_sudo_aliases_are_opt_in() {
  local shell="$1" names="cat catn bat batn batcat eza exa sudo" script path off on
  [ "$shell" = fish ] || names="$names ls"
  case "$shell" in
  bash) script='source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; for a in '"$names"'; do alias "$a" >/dev/null 2>&1 && printf "%s " "$a"; done' ;;
  zsh) script='source "$_HI_HOME/say-hi/common/zsh.zsh" 2>/dev/null; for a in '"$names"'; do alias "$a" >/dev/null 2>&1 && printf "%s " "$a"; done' ;;
  fish) script='source $_HI_HOME/say-hi/common/config.fish 2>/dev/null; for a in '"$names"'; functions -q $a; and printf "%s " $a; end' ;;
  esac
  path="$(_hi_fake_path rc-opt_in-tools bat eza exa sudo):$PATH"
  off="$(_hi_rc_shell dumb "$shell" "$script" PATH="$path")"
  on="$(_hi_rc_shell dumb "$shell" "$script" PATH="$path" _HI_TOOL_ALIASES=1 _HI_SUDO_ALIAS=1)"
  [ -z "$off" ] && [ "$on" = "$names " ] || {
    _hi_cecho " | $shell: off [$off], on [$on]" "$RED"
    return 1
  }
}

# No marks off a terminal, on TERM=dumb, or beside a terminal's own
# integration (kitty's, here), and OSC 7 carries the cwd percent-encoded
function test_bash_marks_only_where_they_belong() {
  local out
  mkdir -p "$_HI_WORKDIR/sp ace"
  out="$(_hi_bash_child '
    source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null
    __hi_ps1
    printf "%s|" "$PS1"
    _hi_marks_on() { [[ $TERM != dumb && -z ${_ksi_prompt+x} ]]; }
    TERM=dumb __hi_ps1
    printf "%s|" "$PS1"
    _ksi_prompt=y __hi_ps1
    printf "%s|" "$PS1"
    _hi_url_path u "$HOME/sp ace"
    printf "%s" "$u"')"
  [[ "$out" != *$'\e]133'* && "$out" != *$'\e]7;'* && "$out" == *"/sp%20ace" ]]
}

# Under a prompt program hi has no $PS1 to hold the marks: D, the cwd, and A
# go out ahead of its hook, the status handed on; oh-my-posh, which can send
# its own, gets none. The programs are stubs whose init prints nothing.
function test_bash_marks_ride_a_prompt_programs_draw() {
  local out p
  p="$(_hi_fake_path rc-mark-programs starship oh-my-posh):$PATH"
  out="$(_hi_bash_child '
    source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null
    _hi_marks_on() { :; }
    (exit 7)
    __hi_marks_pc
    printf "|st=%s|%s" "$?" "${PROMPT_COMMAND%%;*}"' PATH="$p" _HI_PROMPT_TOOL=starship)"
  [[ "$out" == *$'\e]133;D;7\a'*$'\e]133;A\a|st=7|__hi_marks_pc' ]] || _hi_because "starship: $out" || return 1
  out="$(_hi_bash_child '
    source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null
    declare -F __hi_marks_pc _hi_marks_exit' PATH="$p" _HI_PROMPT_TOOL=oh-my-posh)"
  [ -z "$out" ] || _hi_because "oh-my-posh: $out"
}

# the zsh half: the precmd sends A itself under a program, and leaves it to
# $PS1 under hi's own prompt
function test_zsh_marks_ride_a_prompt_programs_draw() {
  local out p
  p="$(_hi_fake_path rc-mark-programs starship oh-my-posh):$PATH"
  out="$(_hi_rc_shell xterm-256color zsh \
    'source "$_HI_HOME/say-hi/common/zsh.zsh" 2>/dev/null
     __hi_marks_on() { : }
     (exit 7); __hi_marks_precmd
     print -rn -- "|$precmd_functions[1]"' PATH="$p" _HI_PROMPT_TOOL=starship)"
  [[ "$out" == *$'\e]133;D;7\a'*$'\e]133;A\a|__hi_marks_precmd' ]] || _hi_because "starship: $out" || return 1
  out="$(_hi_rc_shell xterm-256color zsh \
    'source "$_HI_HOME/say-hi/common/zsh.zsh" 2>/dev/null
     __hi_marks_on() { : }
     __hi_marks_precmd' PATH="$p" _HI_PROMPT_TOOL=hi)"
  [[ "$out" == *$'\e]133;D;'* && "$out" != *$'\e]133;A'* ]] || _hi_because "hi: $out" || return 1
  out="$(_hi_rc_shell xterm-256color zsh \
    'source "$_HI_HOME/say-hi/common/zsh.zsh" 2>/dev/null
     print -rn -- "${+functions[__hi_marks_precmd]}"' PATH="$p" _HI_PROMPT_TOOL=oh-my-posh)"
  [ "$out" = 0 ] || _hi_because "oh-my-posh: $out"
}

# <shell>: a settings.sh line that fails or reads an unset variable never
# stops the shell starting, and an interactive shell's own set -u and
# pipefail survive hi's strict load
function test_rc_keeps_the_callers_shell_options() {
  local shell="$1" rc out cfg="$_HI_WORKDIR/strictcfg"
  mkdir -p "$cfg"
  printf 'false\n: "$HI_UNSET_BY_ANYONE"\n' >"$cfg/settings.sh"
  case "$shell" in
  bash) rc="$_HI_HOME/say-hi/common/bash.sh" ;;
  zsh) rc="$_HI_HOME/say-hi/common/zsh.zsh" ;;
  esac
  out="$(env -i HOME="$_HI_WORKDIR" USER=hi TERM=dumb PATH="$PATH" _HI_HOME="$_HI_HOME" \
    _HI_CONFIG_DIR="$cfg" _HI_DISABLE_HEADER=1 "$shell" -ic \
    'set -u; set -o pipefail; source "$1" >/dev/null 2>&1; [[ $- == *u* && -o pipefail ]] && echo kept' \
    "$shell" "$rc" 2>/dev/null </dev/null)"
  [ "$out" = kept ]
}

# A shell left from its prompt (Ctrl-D) never reaches PS0, so the EXIT trap
# closes the last A/B pair: chained ahead of a trap already set, which still
# sees the shell's status, installed once however often bash.sh is sourced,
# and silent when stdout is not a terminal.
function test_bash_exit_trap_closes_the_prompt_mark() {
  local out want
  out="$(_hi_bash_child '
    trap "echo prev:\$?" EXIT
    source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null
    source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null
    trap -p EXIT
    exit 5')"
  want="$(printf "trap -- '_hi_marks_exit \$?; echo prev:\$?' EXIT\nprev:5")"
  [ "$out" = "$want" ]
}

# the zsh half: a zshexit hook, which a terminal-less exit leaves silent
function test_zsh_exit_hook_closes_the_prompt_mark() {
  local out
  out="$(_hi_rc_shell xterm-256color zsh \
    'source "$_HI_HOME/say-hi/common/zsh.zsh" 2>/dev/null; print -r -- "$zshexit_functions"; exit 5')"
  [ "$out" = __hi_marks_zshexit ]
}

# the fish half: `exit` is a command whose own C and D went out, so the
# fish_exit handler closes the pair only when no command ran since the prompt
function test_fish_exit_closes_the_prompt_mark_only_from_the_prompt() {
  local out
  out="$(_hi_rc_shell xterm-256color fish \
    'source $_HI_HOME/say-hi/common/config.fish 2>/dev/null
     function __hi_marks_on; end # captured, so not a terminal: gate forced open
     emit fish_prompt >/dev/null; set -q __hi_marks_open; and echo -n open
     emit fish_preexec >/dev/null; set -q __hi_marks_open; or echo -n ,ran
     functions -q __hi_marks_exit; and echo -n ,hooked')"
  # fish 3 prints its handlers' C past `emit`'s redirect, and a bracketed-paste
  # reset on its way out, between and after the words
  [[ "$out" == *open*,ran*,hooked* ]]
}

# __hi_ps1 runs first in PROMPT_COMMAND, so it hands on the status it found:
# every hook after it reads the last command's, not its own
function test_bash_ps1_hands_on_the_status() {
  local out
  out="$(_hi_bash_child '
    source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null
    (exit 7)
    __hi_ps1 >/dev/null
    echo "st=$?"')"
  [[ "$out" == *st=7 ]]
}

# The pw3nage guard (the comment in __hi_ps1 says why): with promptvars on, the
# git segment reaches $PS1 as a literal ${__powerline_git_info} reference for
# bash to expand at display time - never its value spliced in.
function test_bash_ps1_references_git_info_under_promptvars() {
  local out
  out="$(_hi_bash_child '
    source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null
    cd "$HOME" || exit 1
    shopt -s promptvars
    __hi_ps1
    printf %s "$PS1"')"
  [[ "$out" == *'${__powerline_git_info}'* ]]
}

# ...and with promptvars off no expansion would ever happen, so the value
# goes in as text: the branch name lands in $PS1 itself, its color escapes
# already wrapped in \001...\002 by _hi_ps_mark (readline's ignore markers -
# the raw \[ \] pair only works in the static half bash decodes).
function test_bash_ps1_inlines_git_info_without_promptvars() {
  local out
  out="$(_hi_bash_child '
    source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null
    cd "$HI_TEST_REPO" || exit 1
    shopt -u promptvars
    __hi_ps1
    printf %s "$PS1"' HI_TEST_REPO="$(_hi_git_fixture)")"
  [[ "$out" != *'${__powerline_git_info}'* ]] ||
    _hi_because "PS1 kept the placeholder rather than inlining it: [$out]" || return 1
  [[ "$out" == *main* ]] ||
    _hi_because "PS1 names no branch; the fixture may not be a repo here: [$out]" || return 1
  [[ "$out" == *$'\001'* ]] ||
    _hi_because "PS1 has no \\001 mark around the git segment: [$out]"
}

# bash's dash-word branch, the same promise the zsh and fish cases below pin:
# `hi --<TAB>` answers from targets.sh's flags roster and never touches the
# target cache ($_HI_TARGET_ROWS_AT still -1, "never filled"), because a
# flag list must not wait on a docker daemon.
function test_bash_flag_completion_offers_hi_options_without_a_sweep() {
  local out
  out="$(_hi_bash_child '
    source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null
    COMP_WORDS=(hi --pla)
    COMP_CWORD=1
    COMPREPLY=()
    _hi_complete
    printf "%s|%s" "${COMPREPLY[*]}" "$_HI_TARGET_ROWS_AT"' _HI_DISABLE_PROMPT=1)"
  [ "$out" = "--plain|-1" ]
}

# ...and the target TAB's names are held in the shell for $_HI_TARGETS_TTL
# seconds: a second TAB inside the window forks nothing, and only TTL=0 turns
# the hold off. A stub $_HI_TARGETS tallies its runs - one x per sweep.
function test_bash_target_names_are_held_for_the_ttl() {
  local out stub count="$_HI_WORKDIR/targets.count"
  rm -f "$count"
  stub="$(_hi_stub_bin targets 'printf x >>"$HI_TEST_COUNT"; printf "stub\tdocker\n"')/targets"
  out="$(_hi_bash_child '
    source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null
    _HI_TARGETS="$HI_TEST_STUB" _HI_TARGETS_TTL=60
    _hi_target_rows
    _hi_target_rows
    printf "%s|%s|" "${_HI_TARGET_ROWS[0]%%[[:space:]]*}" "$(cat "$HI_TEST_COUNT")"
    _HI_TARGETS_TTL=0 _hi_target_rows
    cat "$HI_TEST_COUNT"' _HI_DISABLE_PROMPT=1 HI_TEST_STUB="$stub" HI_TEST_COUNT="$count")"
  [ "$out" = "stub|x|xx" ]
}

# ble.sh's as-you-type completion (`auto` in its comp_type) never sweeps:
# nothing held offers nothing, a real TAB sweeps once, and auto then offers
# what that TAB left
function test_bash_ble_auto_complete_runs_no_sweep() {
  local out stub count="$_HI_WORKDIR/ble.count"
  rm -f "$count"
  stub="$(_hi_stub_bin bletargets 'printf x >>"$HI_TEST_COUNT"; printf "web\tssh\n"')/bletargets"
  out="$(_hi_bash_child '
    source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null
    _HI_TARGETS="$HI_TEST_STUB" BLE_VERSION=0.4 COMP_WORDS=(hi w) COMP_CWORD=1
    auto() { local comp_type=auto; _hi_complete; printf "[%s]" "${COMPREPLY[*]}"; }
    auto
    _hi_complete
    auto
    printf "%s" "$(cat "$HI_TEST_COUNT")"' _HI_DISABLE_PROMPT=1 HI_TEST_STUB="$stub" HI_TEST_COUNT="$count")"
  [ "$out" = "[][web]x" ]
}

# The deferred exa completion, registered only where hi's tool aliases made
# exa an alias: the first TAB clones eza's registered spec onto exa and
# answers 124, bash-completion's "retry with the new spec". The loader
# function is dropped first so a host bash-completion cannot fetch a
# different eza spec over the case's own.
function test_bash_exa_completion_clones_ezas_spec() {
  local out
  out="$(_hi_bash_child '
    source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null
    unset -f _completion_loader 2>/dev/null
    complete -W "--grid --tree" eza
    _hi_load_exa_completion
    printf "%s|" "$?"
    complete -p exa' _HI_DISABLE_PROMPT=1 _HI_TOOL_ALIASES=1 PATH="$(_hi_fake_path rc-exa exa):$PATH")"
  [[ "$out" == '124|'*'-W'*'--grid --tree'*' exa' ]]
}

# ...a word of the spec that holds a quote, which `complete -p` writes as
# '...'\''...', is cloned as that one word
function test_bash_exa_completion_clones_a_quoted_word() {
  local out
  out="$(_hi_bash_child '
    source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null
    unset -f _completion_loader 2>/dev/null
    complete -o nospace -W "it'\''s --grid" eza
    _hi_load_exa_completion
    eza="$(complete -p eza)" exa="$(complete -p exa)"
    printf "%s" "${exa% exa}"
    [ "${exa% exa}" = "${eza% eza}" ] && printf "|same"' _HI_DISABLE_PROMPT=1 _HI_TOOL_ALIASES=1 PATH="$(_hi_fake_path rc-exa exa):$PATH")"
  [[ "$out" == *"it'\''s --grid"*'|same' ]] || _hi_because "exa's spec: $out"
}

# ...and with no eza spec to clone (and no loader to fetch one) it reports
# failure and leaves its own registration armed for the next TAB.
function test_bash_exa_completion_fails_without_an_eza_spec() {
  local out
  out="$(_hi_bash_child '
    source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null
    unset -f _completion_loader 2>/dev/null
    complete -r eza 2>/dev/null
    _hi_load_exa_completion
    printf "%s|" "$?"
    complete -p exa' _HI_DISABLE_PROMPT=1 _HI_TOOL_ALIASES=1 PATH="$(_hi_fake_path rc-exa exa):$PATH")"
  [[ "$out" == '1|'*'_hi_load_exa_completion exa' ]]
}

# <shell>: exa completes as eza only where hi's tool aliases made exa an
# alias - not with the opt-in off, nor with the user's aliases.sh taking the
# alias back. zsh's compdef is stubbed over a seeded eza entry, so the host's
# own completions cannot answer for it.
function test_exa_completes_as_eza_only_with_the_alias() {
  local shell="$1" script path cfg="$_HI_WORKDIR/exa-unaliased-$1" mark on off back
  mkdir -p "$cfg"
  case "$shell" in
  bash)
    mark=_hi_load_exa_completion
    printf 'unalias exa\n' >"$cfg/aliases.sh"
    script='source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; complete -p exa 2>/dev/null'
    ;;
  zsh)
    mark=exa=eza
    printf 'unalias exa\n' >"$cfg/aliases.sh"
    # zsh's associative array, spelled so drift's bash-4 check reads past it
    script='typeset "-A" _comps; _comps[eza]=_eza; compdef() { print -rn -- "[$*]"; }
      source "$_HI_HOME/say-hi/common/zsh.zsh" 2>/dev/null'
    ;;
  fish)
    mark=eza
    printf 'functions -e exa\n' >"$cfg/aliases.sh"
    script='source $_HI_HOME/say-hi/common/config.fish 2>/dev/null; complete -c exa'
    ;;
  esac
  path="$(_hi_fake_path rc-exa exa):$PATH"
  on="$(_hi_rc_shell dumb "$shell" "$script" PATH="$path" _HI_TOOL_ALIASES=1)"
  off="$(_hi_rc_shell dumb "$shell" "$script" PATH="$path")"
  back="$(_hi_rc_shell dumb "$shell" "$script" PATH="$path" _HI_TOOL_ALIASES=1 _HI_CONFIG_DIR="$cfg")"
  [[ "$on" == *"$mark"* && "$off" != *"$mark"* && "$back" != *"$mark"* ]] || {
    _hi_cecho " | $shell: on [$on], off [$off], taken back [$back]" "$RED"
    return 1
  }
}

# When starship owns the prompt, hi's per-prompt hook must stay out of its
# way: no __hi_ps1 function defined, nothing prepended to PROMPT_COMMAND - a
# leftover __hi_ps1 there would overwrite starship's $PS1 on every prompt.
function test_bash_starship_handoff_installs_no_ps1_hook() {
  local out
  out="$(_hi_bash_child '
    source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null
    printf "%s|%s" "${PROMPT_COMMAND-}" "$(type -t __hi_ps1 || true)"' \
    "PATH=$(_hi_prompt_stub_dir starship):$PATH" _HI_PROMPT_TOOL=starship)"
  [[ "$out" != *__hi_ps1* ]]
}

# zsh/fish presence is handled by _hi_check_requires at the registration, so a
# machine without one still runs (and honestly reports) the rest.

# _HI_PROMPT_TOOL=<tool> hands the prompt over when the tool exists; a stub on a
# prepended PATH stands in for it, answering `init <shell>` with a line whose
# effect the case can see - the same stub body for starship and oh-my-posh,
# since both take `init <shell>`. Three assertions per family: deferred when
# asked and present, hi's prompt kept when not asked, and hi's prompt kept -
# with no error - when asked but the tool is absent.
# _hi_stub_bin <name> <script-body> - a directory holding one executable
# <name> whose body is <script-body> (after the #!/bin/sh line), built once;
# prints the directory for a PATH prepend
function _hi_stub_bin() {
  local dir="$_HI_WORKDIR/$1-bin"
  [ -x "$dir/$1" ] || {
    mkdir -p "$dir"
    printf '#!/bin/sh\n%s\n' "$2" >"$dir/$1"
    chmod +x "$dir/$1"
  }
  printf '%s' "$dir"
}

function _hi_prompt_stub_dir() {
  _hi_stub_bin "$1" 'case "$2" in
bash | zsh) echo "PS1=PROMPT-STUB" ;;
fish) echo "function fish_prompt; echo -n PROMPT-STUB; end" ;;
esac'
}

#
# The environment segment (GLOSSARY: HI.54). Three implementations - the shared
# common/env_prompt.sh for bash and zsh, config.fish's own copy for fish - and
# three different answers to "is another tool's prefix already on screen", so
# each shell is run for real rather than read.
#

# _hi_env_segment <shell> [pre] [NAME=VALUE ...] - what that shell's prompt
# puts in front of user@host. <pre> is shell code run after hi's rc and before
# the segment, for the cases that have to fake a venv activation.
function _hi_env_segment() {
  local shell="$1" pre="${2:-}" script
  shift 2
  case "$shell" in
  # __hi_ps1 prints the OSC 133/7 marks as a side effect; they are not the segment
  bash) script='source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; '"$pre"' __hi_ps1 >/dev/null; printf %s "$__hi_env_info"' ;;
  zsh) script='source "$_HI_HOME/say-hi/common/zsh.zsh" 2>/dev/null; '"$pre"' __hi_env_precmd; print -rn -- "$__hi_env_info"' ;;
  fish) script='source $_HI_HOME/say-hi/common/config.fish 2>/dev/null; '"$pre"' __hi_env_prompt' ;;
  esac
  _hi_rc_shell xterm-256color "$shell" "$script" "$@"
}

# _hi_env_names <shell> <want> [pre] [NAME=VALUE ...]
function _hi_env_names() {
  local shell="$1" want="$2"
  shift 2
  [ "$(_hi_env_segment "$shell" "$@")" = "$want" ]
}

# The venv activate scripts leave a marker behind saying they ran in *this*
# shell: $_OLD_VIRTUAL_PS1 for bash and zsh, an _old_fish_prompt function for
# fish. This is that marker, per shell.
function _hi_venv_activated() {
  case "$1" in
  bash | zsh) printf '%s' '_OLD_VIRTUAL_PS1="$ ";' ;;
  fish) printf '%s' 'function _old_fish_prompt; end;' ;;
  esac
}

# zsh and fish keep the prompt the activate script edited, so hi leaves the
# venv to it and names only what has no prefix of its own. bash's __hi_ps1() rebuilds
# $PS1 every draw, so there is nothing there to defer to and hi draws both.
# zsh counts what %{ %} holds as zero columns: only the git segment's escapes
# go inside, so its text stays counted, and a % in a branch name prints as one
function test_zsh_git_segment_counts_its_text() {
  local out
  out="$(_hi_rc_shell xterm-256color zsh 'source "$_HI_HOME/say-hi/common/zsh.zsh" 2>/dev/null
    _hi_git_prompt() { typeset -g "$1"=$'"'"' (\e[1;35m50%\e[0m)'"'"'; }
    __hi_git_precmd
    setopt extended_glob
    v=${(S)__hi_git_info//\%\{*\%\}/}
    print -rn -- "[$v][${${(%)__hi_git_info}//$'"'"'\e'"'"'\[[0-9;]#m/}]"')"
  [[ "$out" == *"[ (50%%)][ (50%)]" && "$out" != *$'\e'* ]]
}

# An activate script's "(name) " ahead of hi's prompt brings its own space,
# so the lead space goes while it is there and comes back once it is not:
# zsh sees the prefix on $PS1, fish the wrapped fish_prompt
function test_zsh_lead_yields_to_an_activate_prefix() {
  local out
  out="$(_hi_rc_shell xterm-256color zsh 'source "$_HI_HOME/say-hi/common/zsh.zsh" 2>/dev/null
    __hi_env_precmd; a="[$__hi_lead]"
    PS1="(proj) $PS1"; __hi_env_precmd
    print -rn -- "${a}[${__hi_lead}]"')"
  [[ "$out" == *"[ ][]" ]]
}

function test_fish_lead_yields_to_an_activate_prefix() {
  local out
  out="$(_hi_rc_shell xterm-256color fish 'source $_HI_HOME/say-hi/common/config.fish 2>/dev/null
    set -l a (prompt_login | string replace -ra "\e\[[0-9;]*m|\e\(B" "")
    function _old_fish_prompt; end
    set -l b (prompt_login | string replace -ra "\e\[[0-9;]*m|\e\(B" "")
    echo -n "[$a][$b]"')"
  [[ "$out" == *"[ "[!\ ]*"]["[!\ ]* ]]
}

function test_env_defers_to_an_activate_that_ran_here() {
  local shell="$1" want="$2"
  _hi_env_names "$shell" "$want" "$(_hi_venv_activated "$shell")" \
    DIRENV_DIR=-/home/x/proj VIRTUAL_ENV_PROMPT=myproj
}

# fish is the one shell whose prompt is actually run here, so it is the one
# that can show the segment in place: leading, before user@host.
function test_fish_prompt_leads_with_the_environment() {
  local out
  out="$(_HI_AS_ROOT=no _hi_prompt_tail fish VIRTUAL_ENV=/x/proj/.venv)"
  [[ "$out" == " (proj) "* ]]
}

# ...and with no environment active at all - every prompt outside a venv - the
# leading space is still there. fish drops a whole concatenated word when a
# command substitution inside it produces nothing, so the lead written as
# "$lead"(__hi_env_prompt) vanished on exactly the prompts that had no segment,
# which is most of them.
function test_fish_prompt_keeps_the_lead_without_an_environment() {
  local out
  out="$(_HI_AS_ROOT=no _hi_prompt_tail fish)"
  [[ "$out" == " "* ]] || {
    _hi_cecho " | fish prompt did not start with the lead: [${out:0:24}]" "$RED"
    return 1
  }
}

# ...and _HI_DISABLE_LEAD_SPACE=1 is what takes it away, in the same place
function test_fish_prompt_drops_the_lead_when_asked() {
  local out
  out="$(_HI_AS_ROOT=no _hi_prompt_tail fish _HI_DISABLE_LEAD_SPACE=1)"
  [[ "$out" != " "* ]]
}

# bash and zsh reach $PS1 through a reference filled by the hook, so what their
# templates can be asked is the placement: the segment ahead of user@host.
function test_bash_ps1_leads_with_the_environment_reference() {
  local out
  out="$(_hi_rc_shell xterm-256color bash \
    'source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; __hi_ps1; printf %s "$PS1"')"
  [[ "$out" == *'${__hi_env_info}'*'\u'* ]]
}

function test_zsh_ps1_leads_with_the_environment_reference() {
  local out
  out="$(_hi_rc_shell xterm-256color zsh \
    'source "$_HI_HOME/say-hi/common/zsh.zsh" 2>/dev/null; print -rn -- "$PS1"')"
  [[ "$out" == *'${__hi_env_info}'*%n* ]]
}

function test_zsh_prompt_is_built() {
  local out
  out="$(_hi_rc_shell xterm-256color zsh \
    'source "$_HI_HOME/say-hi/common/zsh.zsh" 2>/dev/null; print -r -- "$PS1"')"
  [[ "$out" == *%n* && "$out" == *@* && "$out" == *%m* ]]
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
# _hi is autoloaded off the $fpath zsh.zsh extended, as compinit would.
function test_zsh_flag_completion_offers_hi_options() {
  local out
  out="$(_hi_rc_shell xterm-256color zsh '
    source $_HI_HOME/say-hi/common/zsh.zsh 2>/dev/null
    autoload -Uz _hi
    compadd() { local -a a; while (( $# )); do [[ $1 == -a ]] && a=(${(P)2}); shift; done; print -l -- $a }
    words=(hi --c); CURRENT=2
    _hi
  ')"
  printf '%s\n' "$out" | grep -qx -- --doctor &&
    printf '%s\n' "$out" | grep -qx -- --preview
}

# An rc that runs no compinit gets none from hi: no compinit, promptinit, or
# compdef defined, no completion table, and no dump written
function test_zsh_runs_no_compinit_of_its_own() {
  local h="$_HI_WORKDIR/nodump" out f
  mkdir -p "$h"
  # ZDOTDIR set: Alpine's /etc/zsh/zshenv moves it to ~/.config/zsh otherwise
  out="$(_hi_rc_shell dumb zsh 'source "$_HI_HOME/say-hi/common/zsh.zsh" >/dev/null 2>&1
    print -rn -- "${+functions[compinit]}${+functions[promptinit]}${+functions[compdef]}${+_comps}"' \
    HOME="$h" ZDOTDIR="$h")"
  [ "$out" = 0000 ] || {
    _hi_cecho " | compinit promptinit compdef _comps: $out" "$RED"
    return 1
  }
  for f in "$h"/.zcompdump*; do
    [ -e "$f" ] && return 1
  done
  return 0
}

# common/ joins $fpath once and last, however often the rc is sourced: after
# the user's own directories, so a completion of theirs named _hi still wins
function test_zsh_fpath_holds_common_once() {
  local out
  out="$(_hi_rc_shell dumb zsh 'fpath=(/mine $fpath)
    source "$_HI_HOME/say-hi/common/zsh.zsh" >/dev/null 2>&1
    source "$_HI_HOME/say-hi/common/zsh.zsh" >/dev/null 2>&1
    hits=(${(M)fpath:#$_HI_ROOT/common})
    print -rn -- "$#hits|$fpath[1]|$fpath[-1]"')"
  [[ "$out" == "1|/mine|"*/say-hi/common ]] || {
    _hi_cecho " | count|first|last: $out" "$RED"
    return 1
  }
}

# ...and the word after --preview comes from the words roster, described,
# through the same stub: the flag is in words[CURRENT-1]
function test_zsh_completes_the_word_after_preview() {
  local out
  out="$(_hi_rc_shell xterm-256color zsh '
    source $_HI_HOME/say-hi/common/zsh.zsh 2>/dev/null
    autoload -Uz _hi
    compadd() { local -a a; while (( $# )); do [[ $1 == -a ]] && a=(${(P)2}); shift; done; print -l -- $a }
    words=(hi --preview ""); CURRENT=3
    _hi
  ')"
  printf '%s\n' "$out" | grep -qx header &&
    printf '%s\n' "$out" | grep -qx packages
}

# _hi_rc_reentry <shell> <rc> <probe> - <shell> sources hi's <rc> with an
# overlay copy of the same name that sources <rc> again, as an overlay sourcing
# ~/.bashrc would; prints <probe>'s output, nothing if still recursing at the
# deadline. exec'd, so a timeout kills the shell itself. GLOSSARY: HI.55
# _hi_rc_of_member <overlay member> - hi's own rc for that shell, which the
# overlay's per-shell file is named after the shell's rc rather than
function _hi_rc_of_member() {
  case "$1" in bashrc) printf bash.sh ;; zshrc) printf zsh.zsh ;; *) printf '%s' "$1" ;; esac
}

# The character each prompt ends with is a setting (core.sh's
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
  bash) script='source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; __hi_ps1; printf %s "$PS1"' ;;
  zsh) script='source "$_HI_HOME/say-hi/common/zsh.zsh" 2>/dev/null; print -rn -- "$PS1"' ;;
  fish) script="source \$_HI_HOME/say-hi/common/config.fish 2>/dev/null; $root fish_prompt" ;;
  esac
  # _hi_strip_ansi takes the OSC 133 mark that closes every prompt; bash's
  # \[ \] and zsh's %{ %} around it come off here, before the tail is read, as
  # do zsh's ${__hi_ma}/${__hi_mb}, the references its raw $PS1 draws them by
  # shellcheck disable=SC2016 # the ${...} are literal text to strip
  _hi_strip_ansi "$(_hi_rc_shell xterm-256color "$shell" "$script" "$@")" |
    sed -e 's/\\\[//g' -e 's/\\\]//g' -e 's/%{%}//g' -e 's/\${__hi_m[ab]}//g'
}

#
# hi ships nobody's taste per shell - no history sizing, keybindings,
# completion, or color styling of its own. What it ships is the hook for yours:
# the user's own file in $_HI_CONFIG_DIR, named for the *shell file* it
# extends (bash.sh, zsh.zsh, config.fish).
#
# Two things have to stay true per shell, and the second is why the first is
# worth asserting: hi ships no default of its own for these settings,
# and the user's file is sourced and applies. The no-file case guards the
# shipped rcs: a preference in one shows up here as a probe that disagrees
# with a bare shell's.
#
# <shell>|<user file, and the rc it extends>|<probe read>|<user line>|<user value>
#
# That naming is why the second field doubles as the rc to source -
# `source "$_HI_HOME/say-hi/common/$file"` parses in bash and fish both - and
# the third is the read on its own. Keeping the two apart is what lets the probe
# run the read *without* hi's rc, for the baseline the no-file case measures
# against.
_HI_SHELL_OVERRIDE_ROWS=(
  'bash|bashrc|printf %s "${PROMPT_DIRTRIM:-}"|PROMPT_DIRTRIM=9|9'
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
  [ "$mode" = bare ] || src='source "$_HI_HOME/say-hi/common/'"$(_hi_rc_of_member "$file")"'" 2>/dev/null; '
  _hi_rc_shell xterm-256color "$shell" "$src$script"
}

# The shipped rc sets none of these - measured against the same shell *without*
# it rather than against the empty string, because a bare shell does not always
# answer empty: fish 4.0 through 4.6 set every fish_color_* in a `fish -c` too,
# where 4.7 and fish 3 do not. Reading "hi changed nothing" off an absolute
# value would make this case a report on the local fish build; as a
# difference it still fails the day a preference lands in a shipped rc.
function test_shell_ships_no_preference_default() {
  [ "$(_hi_shell_override_probe "$1" none)" = "$(_hi_shell_override_probe "$1" bare)" ]
}

function test_shell_user_file_applies() {
  local row="$1" shell file script line value
  IFS='|' read -r shell file script line value <<<"$row"
  [ "$(_hi_shell_override_probe "$row" user)" = "$value" ]
}

# _hi_rc_begin - what every part of this suite starts from, and the tally
function _hi_rc_begin() {
  _hi_workdir rctest
  mkdir -p "$_HI_WORKDIR/cfg"
  _hi_suite_begin
}

function run_rc_tests() {
  _hi_rc_begin

  _hi_h1 "Testing common/bash.sh, zsh.zsh, and config.fish behavior"

  _hi_h2 "Testing: bash"
  _hi_check "HI_PS1 carries user, host, and cwd" test_bash_hi_ps1_contains_user_host_cwd
  _hi_check "Plain HI_PS1 without color" test_bash_hi_ps1_plain_without_color
  _hi_check "_hi_ps_mark wraps color escapes for readline" test_bash_ps_mark_wraps_color_escapes
  _hi_check "_HI_DISABLE_PROMPT leaves it unset" test_bash_prompt_disabled_leaves_ps1_alone
  _hi_check "...but still primes the color variables (bash)" test_bash_prompt_disabled_still_primes_color_variables
  _hi_check_requires zsh "...and in zsh too" test_zsh_prompt_disabled_still_primes_color_variables
  _hi_check "hi completion is registered" test_bash_registers_hi_completion
  _hi_check "The convenience aliases land too" test_bash_sources_the_convenience_aliases
  _hi_check "__hi_ps1 marks the prompt, status, and cwd (OSC 133/7)" test_bash_ps1_reports_status_and_cwd_marks
  _hi_check "...and hands the status on to the hooks after it" test_bash_ps1_hands_on_the_status
  _hi_check "...but no marks off a terminal, on TERM=dumb, or beside kitty's" test_bash_marks_only_where_they_belong
  _hi_check "...and under a prompt program's draw, oh-my-posh's apart" test_bash_marks_ride_a_prompt_programs_draw
  _hi_check_requires zsh "...in zsh too" test_zsh_marks_ride_a_prompt_programs_draw
  _hi_check_requires zsh "zsh's prompt_subst stays the user's with the prompt off" test_zsh_keeps_the_users_prompt_subst
  _hi_check "[bash] no other tool's variables, no exported palette" test_rc_exports_nothing_for_other_tools bash
  _hi_check_requires zsh "[zsh] no other tool's variables, no exported palette" test_rc_exports_nothing_for_other_tools zsh
  _hi_check "[bash] the tool and sudo aliases are opt-in" test_rc_tool_and_sudo_aliases_are_opt_in bash
  _hi_check_requires zsh "[zsh] the tool and sudo aliases are opt-in" test_rc_tool_and_sudo_aliases_are_opt_in zsh
  _hi_check_requires fish "[fish] the tool and sudo aliases are opt-in" test_rc_tool_and_sudo_aliases_are_opt_in fish
  _hi_check "A failing settings.sh line, and the caller's set -u, survive" test_rc_keeps_the_callers_shell_options bash
  _hi_check_requires zsh "...in zsh too" test_rc_keeps_the_callers_shell_options zsh
  _hi_check "An EXIT trap closes the last prompt mark" test_bash_exit_trap_closes_the_prompt_mark
  _hi_check_requires zsh "...and a zshexit hook in zsh" test_zsh_exit_hook_closes_the_prompt_mark
  _hi_check_requires fish "...and fish_exit in fish, from the prompt only" test_fish_exit_closes_the_prompt_mark_only_from_the_prompt
  _hi_check "PS1 references the git segment (promptvars)" test_bash_ps1_references_git_info_under_promptvars
  _hi_check "...and inlines it marked as text without" test_bash_ps1_inlines_git_info_without_promptvars
  _hi_check "bash flag TAB completes hi's options, no sweep" test_bash_flag_completion_offers_hi_options_without_a_sweep
  _hi_check "bash target TAB reuses its names within the TTL" test_bash_target_names_are_held_for_the_ttl
  _hi_check "ble.sh's as-you-type completion runs no sweep" test_bash_ble_auto_complete_runs_no_sweep
  _hi_check "the first exa TAB clones eza's spec (124)" test_bash_exa_completion_clones_ezas_spec
  _hi_check "...a word holding a quote included" test_bash_exa_completion_clones_a_quoted_word
  _hi_check "...and fails armed without an eza spec" test_bash_exa_completion_fails_without_an_eza_spec
  _hi_check "[bash] exa completes as eza only with hi's exa alias" test_exa_completes_as_eza_only_with_the_alias bash
  _hi_check_requires zsh "[zsh] exa completes as eza only with hi's exa alias" test_exa_completes_as_eza_only_with_the_alias zsh
  _hi_check_requires fish "[fish] exa completes as eza only with hi's exa alias" test_exa_completes_as_eza_only_with_the_alias fish
  _hi_check "starship handoff installs no __hi_ps1 hook" test_bash_starship_handoff_installs_no_ps1_hook

  _hi_h2 "Testing: zsh and fish"
  _hi_check_requires zsh "zsh builds its prompt" test_zsh_prompt_is_built
  _hi_check_requires zsh "zsh flag TAB completes hi's options" test_zsh_flag_completion_offers_hi_options
  _hi_check_requires zsh "zsh completes the word after --preview" test_zsh_completes_the_word_after_preview
  _hi_check_requires zsh "zsh runs no compinit, and writes no dump, of its own" test_zsh_runs_no_compinit_of_its_own
  _hi_check_requires zsh "zsh's \$fpath holds common/ once, last, after a re-source" test_zsh_fpath_holds_common_once

  _hi_h2 "Testing: the environment segment (venv, conda, direnv, nix, ...)"
  # every child's $HOME is $_HI_WORKDIR, so this is the case the mise row was
  # built for: a global ~/.tool-versions, a directory under ~ that only
  # inherits it, and a project with a config of its own
  : >"$_HI_WORKDIR/.tool-versions"
  mkdir -p "$_HI_WORKDIR/mise/proj"
  : >"$_HI_WORKDIR/mise/proj/.tool-versions"
  local _hi_esh
  for _hi_esh in bash zsh fish; do
    _hi_check_requires "$_hi_esh" "[$_hi_esh] nothing active -> no segment" \
      _hi_env_names "$_hi_esh" "" ""
    _hi_check_requires "$_hi_esh" "[$_hi_esh] a .venv is named for its project" \
      _hi_env_names "$_hi_esh" "(proj) " "" VIRTUAL_ENV=/x/proj/.venv
    _hi_check_requires "$_hi_esh" "[$_hi_esh] direnv outside a venv, outermost first" \
      _hi_env_names "$_hi_esh" "(direnv:proj|myproj) " "" \
      DIRENV_DIR=-/home/x/proj VIRTUAL_ENV_PROMPT=myproj
    _hi_check_requires "$_hi_esh" "[$_hi_esh] _HI_DISABLE_ENV_STATUS silences it" \
      _hi_env_names "$_hi_esh" "" "" VIRTUAL_ENV_PROMPT=myproj _HI_DISABLE_ENV_STATUS=1
    _hi_check_requires "$_hi_esh" "[$_hi_esh] mise under a project config is named" \
      _hi_env_names "$_hi_esh" "(mise) " "cd '$_HI_WORKDIR/mise/proj';" MISE_SHELL=x
    _hi_check_requires "$_hi_esh" "[$_hi_esh] mise on ~'s config alone is not" \
      _hi_env_names "$_hi_esh" "" "cd '$_HI_WORKDIR/mise';" MISE_SHELL=x
  done
  _hi_check "[bash] draws the venv its PROMPT_COMMAND would have eaten" \
    test_env_defers_to_an_activate_that_ran_here bash "(direnv:proj|myproj) "
  _hi_check_requires zsh "[zsh] leaves an activate that ran here its own prefix" \
    test_env_defers_to_an_activate_that_ran_here zsh "(direnv:proj) "
  _hi_check_requires fish "[fish] leaves an activate that ran here its own prefix" \
    test_env_defers_to_an_activate_that_ran_here fish "(direnv:proj) "
  _hi_check "[bash] PS1 puts the segment ahead of user@host" test_bash_ps1_leads_with_the_environment_reference
  _hi_check_requires zsh "[zsh] PS1 puts the segment ahead of user@host" test_zsh_ps1_leads_with_the_environment_reference
  _hi_check_requires fish "[fish] the drawn prompt leads with it" test_fish_prompt_leads_with_the_environment
  _hi_check_requires fish "...and keeps the lead with no environment" test_fish_prompt_keeps_the_lead_without_an_environment
  _hi_check_requires fish "..._HI_DISABLE_LEAD_SPACE=1 takes the lead away" test_fish_prompt_drops_the_lead_when_asked
  _hi_check_requires zsh "[zsh] an activate's prefix takes the lead space's place" test_zsh_lead_yields_to_an_activate_prefix
  _hi_check_requires zsh "[zsh] the git segment's text counts toward the width" test_zsh_git_segment_counts_its_text
  _hi_check_requires fish "[fish] an activate's prefix takes the lead space's place" test_fish_lead_yields_to_an_activate_prefix

  _hi_h2 "Testing: the per-shell override files"
  local _hi_row _hi_sh
  for _hi_row in "${_HI_SHELL_OVERRIDE_ROWS[@]}"; do
    _hi_sh="${_hi_row%%|*}"
    _hi_check_requires "$_hi_sh" "[$_hi_sh] hi ships no preference of its own" \
      test_shell_ships_no_preference_default "$_hi_row"
    _hi_check_requires "$_hi_sh" "[$_hi_sh] the user's own file applies" \
      test_shell_user_file_applies "$_hi_row"
  done

  _hi_suite_end "rc"
}

# a part (rc_*_test.sh) sources this file for what is above and runs its own
[ -n "${_HI_RC_PART:-}" ] || run_rc_tests
