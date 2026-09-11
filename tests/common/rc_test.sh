#!/usr/bin/env bash
# Copyright the say-hi contributors.
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

# ps1 runs per prompt: OSC 133;D must carry the *last* command's status and
# OSC 7 the cwd (the D/A pair kitty/WezTerm/ghostty jump and report by), and
# $PS1 itself must open with the A mark and close with B.
function test_bash_ps1_reports_status_and_cwd_marks() {
  local out
  out="$(_hi_bash_child '
    source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null
    cd "$HOME" || exit 1
    (exit 7)
    ps1
    printf %s "$PS1"')"
  [[ "$out" == *$'\e]133;D;7\a'* ]] &&
    [[ "$out" == *$'\e]7;file://'*"$_HI_WORKDIR"$'\a'* ]] &&
    [[ "$out" == *$'\e]133;A'* && "$out" == *$'\e]133;B'* ]]
}

# _HI_DISABLE_MARKS=1 silences the whole channel - no D at prompt time, no
# A/B in $PS1 - and TERM=dumb takes the color branch's else with it: the
# plain \u@\h:\w form, with no escapes anywhere.
function test_bash_disable_marks_emits_no_osc() {
  local out
  out="$(_hi_bash_child '
    source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null
    ps1
    printf %s "$PS1"' _HI_DISABLE_MARKS=1 TERM=dumb)"
  [[ "$out" != *$'\e]133'* ]] || return 1
  [[ "$out" == *'\u@\h:\w'* ]]
}

# The pw3nage guard (the comment in ps1 says why): with promptvars on, the
# git segment reaches $PS1 as a literal ${__powerline_git_info} reference for
# bash to expand at display time - never its value spliced in.
function test_bash_ps1_references_git_info_under_promptvars() {
  local out
  out="$(_hi_bash_child '
    source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null
    cd "$HOME" || exit 1
    shopt -s promptvars
    ps1
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
    ps1
    printf %s "$PS1"' HI_TEST_REPO="$(_hi_git_fixture)")"
  [[ "$out" != *'${__powerline_git_info}'* ]] &&
    [[ "$out" == *main* && "$out" == *$'\001'* ]]
}

# bash's dash-word branch, the same promise the zsh and fish cases below pin:
# `hi --<TAB>` answers from targets.sh's flags roster and never touches the
# target cache ($_HI_TARGET_NAMES_AT still -1, "never filled"), because a
# flag list must not wait on a docker daemon.
function test_bash_flag_completion_offers_hi_options_without_a_sweep() {
  local out
  out="$(_hi_bash_child '
    source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null
    COMP_WORDS=(hi --pl)
    COMP_CWORD=1
    COMPREPLY=()
    _hi_complete
    printf "%s|%s" "${COMPREPLY[*]}" "$_HI_TARGET_NAMES_AT"' _HI_DISABLE_PROMPT=1)"
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
    _hi_target_names
    _hi_target_names
    printf "%s|%s|" "$_HI_TARGET_NAMES" "$(cat "$HI_TEST_COUNT")"
    _HI_TARGETS_TTL=0 _hi_target_names
    cat "$HI_TEST_COUNT"' _HI_DISABLE_PROMPT=1 HI_TEST_STUB="$stub" HI_TEST_COUNT="$count")"
  [ "$out" = "stub|x|xx" ]
}

# The deferred exa completion: the first TAB clones eza's registered spec
# onto exa and answers 124, bash-completion's "retry with the new spec". The
# loader function is dropped first so a host bash-completion cannot fetch a
# different eza spec over the case's own.
function test_bash_exa_completion_clones_ezas_spec() {
  local out
  out="$(_hi_bash_child '
    source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null
    unset -f _completion_loader 2>/dev/null
    complete -W "--grid --tree" eza
    _hi_load_exa_completion
    printf "%s|" "$?"
    complete -p exa' _HI_DISABLE_PROMPT=1)"
  [[ "$out" == '124|'*'-W'*'--grid --tree'*' exa' ]]
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
    complete -p exa' _HI_DISABLE_PROMPT=1)"
  [[ "$out" == '1|'*'_hi_load_exa_completion exa' ]]
}

# When starship owns the prompt, hi's per-prompt hook must stay out of its
# way: no ps1 function defined, nothing prepended to PROMPT_COMMAND - a
# leftover ps1 there would overwrite starship's $PS1 on every prompt.
function test_bash_starship_handoff_installs_no_ps1_hook() {
  local out
  out="$(_hi_bash_child '
    source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null
    printf "%s|%s" "${PROMPT_COMMAND-}" "$(type -t ps1 || true)"' \
    "PATH=$(_hi_prompt_stub_dir starship):$PATH" _HI_PROMPT_TOOL=starship)"
  [[ "$out" != *ps1* ]]
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

# One case for all three shells and both tools: the per-shell rc, prompt-print
# incantation, and expected shape live in the case's own table. Extra
# NAME=VALUE arguments ride _hi_rc_shell (env applies the last assignment, so
# the prepended-PATH override wins over the baseline), so there is one `env -i`
# block here rather than one per case.
function test_defers_to_prompt_tool_when_asked() {
  local shell="$1" tool="$2" script want out
  case "$shell" in
  bash)
    script='source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; printf "%s|%s" "$PS1" "${HI_PS1:-unset}"'
    want="PROMPT-STUB|unset"
    ;;
  zsh)
    script='source "$_HI_HOME/say-hi/common/zsh.zsh" 2>/dev/null; printf %s "$PS1"'
    want="PROMPT-STUB"
    ;;
  fish)
    script='source $_HI_HOME/say-hi/common/config.fish 2>/dev/null; fish_prompt'
    want="*PROMPT-STUB*"
    ;;
  esac
  out="$(_hi_rc_shell xterm-256color "$shell" "$script" \
    PATH="$(_hi_prompt_stub_dir "$tool"):$PATH" _HI_PROMPT_TOOL="$tool")"
  # shellcheck disable=SC2053 # $want is a pattern (fish's is a glob)
  [[ "$out" == $want ]]
}

# on a target, a tool's config in the overlay becomes the tool's own variable
# (starship.toml -> $STARSHIP_CONFIG, theme.yml -> $EZA_CONFIG_DIR - the
# directory, since eza fixes the file name - bat.conf -> $BAT_CONFIG_PATH); at
# home the variable is left alone, whatever the overlay holds
# <shell> <overlay file> <variable> <expected on a target> [NAME=VALUE...]
function test_remote_session_exports_overlay_config() {
  local shell="$1" file="$2" var="$3" want="$4" script out home
  shift 4
  mkdir -p "$_HI_WORKDIR/cfg"
  printf '# a config\n' >"$_HI_WORKDIR/cfg/$file"
  case "$shell" in
  bash) script='source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; printf %s "${'"$var"':-}"' ;;
  fish) script='source $_HI_HOME/say-hi/common/config.fish 2>/dev/null; echo -n $'"$var" ;;
  esac
  out="$(_hi_rc_shell xterm-256color "$shell" "$script" "$@" _HI_REMOTE_SESSION=1)"
  home="$(_hi_rc_shell xterm-256color "$shell" "$script" "$@")"
  rm -f "$_HI_WORKDIR/cfg/$file"
  [ "$out" = "$want" ] && [ -z "$home" ]
}

# a stub zoxide/atuin whose `init <shell>` prints one line the session can be
# asked about: the tool is "installed", and what it prints is what got eval'd
function _hi_tool_stub_dir() {
  _hi_stub_bin "$1" 'case "$2" in
fish) echo "set -g HI_'"$1"'_INIT $2" ;;
*) echo "HI_'"$1"'_INIT=$2" ;;
esac'
}

# the session runs `<tool> init <shell>` when the tool is there...
function test_tool_init_wires_the_tool_in() {
  local shell="$1" tool="$2" script out
  case "$shell" in
  bash) script='source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; printf %s "${HI_'"$tool"'_INIT:-}"' ;;
  zsh) script='source "$_HI_HOME/say-hi/common/zsh.zsh" 2>/dev/null; printf %s "${HI_'"$tool"'_INIT:-}"' ;;
  fish) script='source $_HI_HOME/say-hi/common/config.fish 2>/dev/null; echo -n $HI_'"$tool"'_INIT' ;;
  esac
  out="$(_hi_rc_shell xterm-256color "$shell" "$script" PATH="$(_hi_tool_stub_dir "$tool"):$PATH")"
  [ "$out" = "$shell" ]
}

# ...not when the toggle is off, and not when something already did (the
# function the real init leaves behind is the mark)
function test_tool_init_stands_down() {
  local shell="$1" tool="$2" fn="$3" pre body wired toggled
  case "$shell" in
  bash) pre="$fn() { :; }; " body='source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; printf %s "${HI_'"$tool"'_INIT:-}"' ;;
  zsh) pre="$fn() { :; }; " body='source "$_HI_HOME/say-hi/common/zsh.zsh" 2>/dev/null; printf %s "${HI_'"$tool"'_INIT:-}"' ;;
  fish) pre="function $fn; end; " body='source $_HI_HOME/say-hi/common/config.fish 2>/dev/null; echo -n $HI_'"$tool"'_INIT' ;;
  esac
  wired="$(_hi_rc_shell xterm-256color "$shell" "$pre$body" PATH="$(_hi_tool_stub_dir "$tool"):$PATH")"
  toggled="$(_hi_rc_shell xterm-256color "$shell" "$body" PATH="$(_hi_tool_stub_dir "$tool"):$PATH" _HI_DISABLE_TOOL_INIT=1)"
  [ -z "$wired" ] && [ -z "$toggled" ]
}

# fish's sudo wrapper is a function behind _HI_DISABLE_SUDO_ALIAS, the same
# toggle as the POSIX alias; off, `sudo` is the command and nothing else
function test_fish_sudo_wrapper_follows_the_toggle() {
  local script='source $_HI_HOME/say-hi/common/config.fish 2>/dev/null; functions -q sudo; and echo wrapped; or echo bare' on off
  on="$(_hi_rc_shell xterm-256color fish "$script")"
  off="$(_hi_rc_shell xterm-256color fish "$script" _HI_DISABLE_SUDO_ALIAS=1)"
  [ "$on" = wrapped ] && [ "$off" = bare ]
}

function test_bash_keeps_hi_prompt_without_the_setting() {
  local out
  out="$(_hi_rc_shell xterm-256color bash \
    'source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; printf %s "$HI_PS1"' \
    PATH="$(_hi_prompt_stub_dir starship):$PATH")"
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
    _HI_PROMPT_TOOL=starship 2>&1)"
  [[ "$out" == *'\u'* ]]
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
  # ps1 prints the OSC 133/7 marks as a side effect; they are not the segment
  bash) script='source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; '"$pre"' ps1 >/dev/null; printf %s "$__hi_env_info"' ;;
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
# venv to it and names only what has no prefix of its own. bash's ps1() rebuilds
# $PS1 every draw, so there is nothing there to defer to and hi draws both.
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
    'source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; ps1; printf %s "$PS1"')"
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
    compadd() { local -a a; while (( $# )); do [[ $1 == -a ]] && a=(${(P)2}); shift; done; print -l -- $a }
    words=(hi --c); CURRENT=2
    _hi
  ')"
  printf '%s\n' "$out" | grep -qx -- --doctor &&
    printf '%s\n' "$out" | grep -qx -- --preview
}

# zsh colors the target list by backend through the hi-targets tag's
# list-colors, matched on each display line's leading kind; none under
# $NO_COLOR, and a zstyle of the user's own is left alone
function test_zsh_target_list_colors_per_backend() {
  local out
  out="$(_hi_rc_shell xterm-256color zsh '
    source $_HI_HOME/say-hi/common/zsh.zsh 2>/dev/null
    zstyle -g lc ":completion:*:hi-targets" list-colors; print -l -- $lc')"
  [[ "$out" == *"=* ssh - *=0;33"* && "$out" == *"docker|"*") - *=0;34"* &&
    "$out" == *"=* nomad - *=0;32"* && "$out" == *"=* kube - *=1;35"* ]] || {
    _hi_cecho " | list-colors: ${out//$'\n'/ }" "$RED"
    return 1
  }
  out="$(_hi_rc_shell xterm-256color zsh '
    source $_HI_HOME/say-hi/common/zsh.zsh 2>/dev/null
    zstyle -g lc ":completion:*:hi-targets" list-colors; print -r -- ${#lc}' NO_COLOR=1)"
  [ "$out" = 0 ] || return 1
  out="$(_hi_rc_shell xterm-256color zsh '
    zstyle ":completion:*:hi-targets" list-colors "=*=31"
    source $_HI_HOME/say-hi/common/zsh.zsh 2>/dev/null
    zstyle -g lc ":completion:*:hi-targets" list-colors; print -r -- "$lc"')"
  [ "$out" = "=*=31" ]
}

# zsh expands hi's own `hi` alias before completing, so the launcher's name
# is registered too, or `hi <TAB>` falls through to file completion
function test_zsh_completion_covers_the_alias_target() {
  local out
  out="$(_hi_rc_shell xterm-256color zsh '
    autoload -Uz compinit && compinit -u -D
    source $_HI_HOME/say-hi/common/zsh.zsh 2>/dev/null
    print -r -- "${_comps[hi]}:${_comps[hi.sh]}"')"
  [ "$out" = "_hi:_hi" ] || {
    _hi_cecho " | _comps[hi]:_comps[hi.sh] = $out" "$RED"
    return 1
  }
}

# ...and the target branch goes through _description with that tag, which is
# what applies the style: a seeded cache, the completion builtins stubbed
function test_zsh_target_completion_uses_the_colored_tag() {
  local out
  out="$(_hi_rc_shell xterm-256color zsh '
    source $_HI_HOME/say-hi/common/zsh.zsh 2>/dev/null
    _description() { print -r -- "desc $*"; expl=(-V -default-); }
    compadd() { print -r -- "compadd $*"; }
    _HI_TARGET_ROWS=(web) _HI_TARGET_DESCS=("docker - web") _HI_TARGET_ROWS_AT=$SECONDS
    words=(hi ""); CURRENT=2
    _hi')"
  [[ "$out" == *"desc -V hi-targets expl target"* &&
    "$out" == *"compadd -V -default- -d _HI_TARGET_DESCS -a _HI_TARGET_ROWS"* ]] || {
    _hi_cecho " | got: ${out//$'\n'/ | }" "$RED"
    return 1
  }
}

# _hi_bash_listing <COMP_TYPE> <word> [NAME=VALUE...] - _hi_complete's
# COMPREPLY for <word>, "|"-joined, over a seeded target cache
function _hi_bash_listing() {
  local type="$1" word="$2"
  shift 2
  _hi_rc_shell dumb bash "
    source \"\$_HI_HOME/say-hi/common/bash.sh\" 2>/dev/null
    _HI_TARGET_NAMES='web web2 jobx podx sshy dup dup' _HI_TARGET_NAMES_AT=\$SECONDS
    _HI_TARGET_KINDS='docker podman nomad kube ssh ssh docker'
    COMP_WORDS=(hi '$word') COMP_CWORD=1 COMP_TYPE=$type
    _hi_complete
    IFS='|'
    printf '%s' \"\${COMPREPLY[*]}\"" "$@"
}

# bash lists each target's backend symbol only while readline lists (63),
# never when it inserts (9); a name two backends share is listed once with
# both symbols; ASCII stand-ins off a UTF-8 locale; $_HI_SYMBOL_* wins.
# GLOSSARY: HI.56
function test_bash_target_symbols_only_when_listing() {
  local out
  out="$(_hi_bash_listing 63 '' LANG=C.UTF-8)"
  [ "$out" = "web ▣|web2 ▣|jobx ◆|podx ⎈|sshy »|dup »▣" ] || {
    _hi_cecho " | listing: $out" "$RED"
    return 1
  }
  out="$(_hi_bash_listing 9 w LANG=C.UTF-8)"
  [ "$out" = "web|web2" ] || {
    _hi_cecho " | inserting: $out" "$RED"
    return 1
  }
  out="$(_hi_bash_listing 63 d LANG=C.UTF-8)"
  [ "$out" = dup ] || {
    _hi_cecho " | one shared name: $out" "$RED"
    return 1
  }
  out="$(_hi_bash_listing 63 '')"
  [ "$out" = "web #|web2 #|jobx *|podx @|sshy >|dup >#" ] || {
    _hi_cecho " | ascii: $out" "$RED"
    return 1
  }
  out="$(_hi_bash_listing 63 '' LANG=C.UTF-8 _HI_SYMBOL_KUBE=k8s)"
  [[ "$out" == *"|podx k8s|"* ]]
}

# fish's target rows carry the backend's symbol ahead of the kind, the
# description fish shows beside each name; $_HI_SYMBOL_* wins
function test_fish_target_symbols() {
  local fixture="$_HI_WORKDIR/targets-fixture.sh" out
  printf '%s\n' "printf 'web\\tdocker\\njobx\\tnomad\\npodx\\tkube\\nsshy\\tssh\\n'" >"$fixture"
  out="$(_hi_rc_shell dumb fish "source \$_HI_HOME/say-hi/common/config.fish 2>/dev/null
    set _HI_TARGETS $fixture
    __hi_targets" LANG=C.UTF-8 _HI_SYMBOL_SSH=S)"
  [ "$out" = $'web\t▣ docker\njobx\t◆ nomad\npodx\t⎈ kube\nsshy\tS ssh' ] || {
    _hi_cecho " | __hi_targets: ${out//$'\n'/ | }" "$RED"
    return 1
  }
}

# _hi_greet <shell> <i|c|s> [NAME=VALUE...] - how many times <shell> prints
# the Online header sourcing hi's rc: typed in (i, from stdin), `-i -c` (c),
# or as a script (s); settings.sh trims the header to one cell, no probes
function _hi_greet() {
  local shell="$1" rc=bash.sh cfg="$_HI_WORKDIR/greet"
  local -a args=(--norc)
  [ "$shell" = zsh ] && rc=zsh.zsh args=(-f)
  local src="source \"\$_HI_HOME/say-hi/common/$rc\""
  case "$2" in i) args+=(-i) ;; c) args+=(-i -c "$src") ;; esac
  shift 2
  mkdir -p "$cfg" && printf 'export _HI_HEADER_ORDER=utc\n' >"$cfg/settings.sh"
  printf '%s\n' "$src" | env -i HOME="$_HI_WORKDIR" TERM=dumb PATH="$PATH" \
    _HI_HOME="$_HI_HOME" _HI_CONFIG_DIR="$cfg" "$@" "$shell" "${args[@]}" 2>/dev/null |
    grep -c Online || true
}

# a local interactive bash and zsh greet with hi's header, as fish does -
# once; never `-i -c` or a script (fish greets neither), a target session,
# or under the toggle
function test_local_shell_prints_the_header() {
  local shell=$1
  [ "$(_hi_greet "$shell" i)" = 1 ] && [ "$(_hi_greet "$shell" c)" = 0 ] &&
    [ "$(_hi_greet "$shell" s)" = 0 ] &&
    [ "$(_hi_greet "$shell" i _HI_REMOTE_SESSION=1)" = 0 ] &&
    [ "$(_hi_greet "$shell" i _HI_DISABLE_HEADER=1)" = 0 ]
}

# ...and the word after --preview comes from the words roster, described,
# through the same stub: the flag is in words[CURRENT-1]
function test_zsh_completes_the_word_after_preview() {
  local out
  out="$(_hi_rc_shell xterm-256color zsh '
    source $_HI_HOME/say-hi/common/zsh.zsh 2>/dev/null
    compadd() { local -a a; while (( $# )); do [[ $1 == -a ]] && a=(${(P)2}); shift; done; print -l -- $a }
    words=(hi --preview ""); CURRENT=3
    _hi
  ')"
  printf '%s\n' "$out" | grep -qx header &&
    printf '%s\n' "$out" | grep -qx packages
}

# fish does its own prefix matching, so `--preview-c` narrows to one flag, and
# prints it with the roster's help clause after a tab - the description fish
# shows beside the flag. A line that does not start with a dash would be a
# target row ("<name>\t<kind>"), which is the sweep the -n guard exists to
# keep out of a dash word.
function test_fish_flag_completion_offers_hi_options() {
  local out
  out="$(_hi_rc_shell xterm-256color fish '
    source $_HI_HOME/say-hi/common/config.fish 2>/dev/null
    complete -C "hi --pl"
  ')"
  printf '%s\n' "$out" | grep -q "^--plain$(printf '\t')a bare shell" || return 1
  if printf '%s\n' "$out" | grep -qv '^-'; then
    _hi_cecho "   a dash word also swept the targets" "$RED"
    return 1
  fi
  return 0
}

# the word after --preview: fish's own condition picks the words roster, and
# the target sweep (any line not in the roster) stays out
function test_fish_completes_the_word_after_preview() {
  local out
  out="$(_hi_rc_shell xterm-256color fish '
    source $_HI_HOME/say-hi/common/config.fish 2>/dev/null
    complete -C "hi --preview "
  ')"
  printf '%s\n' "$out" | grep -q "^header$(printf '\t')the connect header" || return 1
  printf '%s\n' "$out" | grep -q "^colors$(printf '\t')" || return 1
  [ "$(printf '%s\n' "$out" | grep -c .)" -eq 4 ]
}

# _hi_rc_reentry <shell> <rc> <probe> - <shell> sources hi's <rc> with an
# overlay copy of the same name that sources <rc> again, as an overlay sourcing
# ~/.bashrc would; prints <probe>'s output, nothing if still recursing at the
# deadline. exec'd, so a timeout kills the shell itself. GLOSSARY: HI.55
function _hi_rc_reentry() {
  local shell="$1" rc="$2" probe="$3" cfg="$_HI_WORKDIR/reentry-$1"
  mkdir -p "$cfg"
  printf 'source "%s"\n' "$_HI_HOME/say-hi/common/$rc" >"$cfg/$rc"
  (exec env -i HOME="$_HI_WORKDIR" TERM=dumb PATH="$PATH" _HI_HOME="$_HI_HOME" \
    _HI_CONFIG_DIR="$cfg" "$shell" -c "source \"\$_HI_HOME/say-hi/common/$rc\"; $probe" \
    </dev/null >"$cfg.out" 2>&1) &
  _hi_wait_pid $! 20
  [ "$_HI_WAIT_EXIT" != 124 ] && cat "$cfg.out"
}

function test_bash_rc_reentry_returns() {
  [ "$(_hi_rc_reentry bash bash.sh 'printf %s "${_hi_rc_loading-done}:${_HI_ROOT:+root}"')" = done:root ]
}

function test_zsh_rc_reentry_returns() {
  [ "$(_hi_rc_reentry zsh zsh.zsh 'printf %s "${_hi_rc_loading-done}:${_HI_ROOT:+root}"')" = done:root ]
}

function test_fish_rc_reentry_returns() {
  [ "$(_hi_rc_reentry fish config.fish 'set -q _hi_rc_loading; or printf done; test -n "$_HI_ROOT"; and printf :root')" = done:root ]
}

function test_fish_flag_completion_does_not_also_sweep_targets() {
  local out
  out="$(_hi_rc_shell xterm-256color fish \
    'source $_HI_HOME/say-hi/common/config.fish 2>/dev/null; complete -c hi')"
  # the bare-target line is guarded, and the flags line still is too
  printf '%s\n' "$out" | grep -qF 'not string match -q -- "-*"' &&
    printf '%s\n' "$out" | grep -qF '$_HI_TARGETS flags'
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
  bash) script='source "$_HI_HOME/say-hi/common/bash.sh" 2>/dev/null; ps1; printf %s "$PS1"' ;;
  zsh) script='source "$_HI_HOME/say-hi/common/zsh.zsh" 2>/dev/null; print -rn -- "$PS1"' ;;
  fish) script="source \$_HI_HOME/say-hi/common/config.fish 2>/dev/null; $root fish_prompt" ;;
  esac
  # _hi_strip_ansi takes the OSC 133 mark that closes every prompt; bash's
  # \[ \] and zsh's %{ %} around it come off here, before the tail is read
  _hi_strip_ansi "$(_hi_rc_shell xterm-256color "$shell" "$script" "$@")" |
    sed -e 's/\\\[//g' -e 's/\\\]//g' -e 's/%{%}//g'
}

# _hi_prompt_ends <as_root> <shell> <want> [NAME=VALUE ...] - does the prompt
# the shell builds with those pairs set end with <want>? The trailing space
# every separator carries comes off before the tail is compared. The one
# predicate behind every separator case; the scenarios live with their
# registrations.
function _hi_prompt_ends() {
  local as_root="$1" shell="$2" want="$3" out
  shift 3
  out="$(_HI_AS_ROOT="$as_root" _hi_prompt_tail "$shell" "$@")"
  case "${out% }" in
  *"$want") return 0 ;;
  esac
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

function run_rc_tests() {
  _hi_workdir rctest
  mkdir -p "$_HI_WORKDIR/cfg"

  _hi_suite_begin

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
  _hi_check "ps1 marks the prompt, status, and cwd (OSC 133/7)" test_bash_ps1_reports_status_and_cwd_marks
  _hi_check "_HI_DISABLE_MARKS silences every OSC" test_bash_disable_marks_emits_no_osc
  _hi_check "PS1 references the git segment (promptvars)" test_bash_ps1_references_git_info_under_promptvars
  _hi_check "...and inlines it marked as text without" test_bash_ps1_inlines_git_info_without_promptvars
  _hi_check "bash flag TAB completes hi's options, no sweep" test_bash_flag_completion_offers_hi_options_without_a_sweep
  _hi_check "bash target TAB reuses its names within the TTL" test_bash_target_names_are_held_for_the_ttl
  _hi_check "the first exa TAB clones eza's spec (124)" test_bash_exa_completion_clones_ezas_spec
  _hi_check "...and fails armed without an eza spec" test_bash_exa_completion_fails_without_an_eza_spec
  _hi_check "starship handoff installs no ps1 hook" test_bash_starship_handoff_installs_no_ps1_hook

  _hi_h2 "Testing: zsh and fish"
  _hi_check_requires zsh "zsh builds its prompt" test_zsh_prompt_is_built
  _hi_check_requires zsh "zsh flag TAB completes hi's options" test_zsh_flag_completion_offers_hi_options
  _hi_check_requires zsh "zsh completes the word after --preview" test_zsh_completes_the_word_after_preview

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

  _hi_h2 "Testing: the per-shell override files"
  local _hi_row _hi_sh
  for _hi_row in "${_HI_SHELL_OVERRIDE_ROWS[@]}"; do
    _hi_sh="${_hi_row%%|*}"
    _hi_check_requires "$_hi_sh" "[$_hi_sh] hi ships no preference of its own" \
      test_shell_ships_no_preference_default "$_hi_row"
    _hi_check_requires "$_hi_sh" "[$_hi_sh] the user's own file applies" \
      test_shell_user_file_applies "$_hi_row"
  done

  _hi_h2 "Testing: prompt handoff (_HI_PROMPT_TOOL=starship / oh-my-posh)"
  _hi_check "[bash] defers to starship when asked and present" test_defers_to_prompt_tool_when_asked bash starship
  _hi_check "[bash] defers to oh-my-posh when asked and present" test_defers_to_prompt_tool_when_asked bash oh-my-posh
  _hi_check "[bash] keeps hi's prompt without the setting" test_bash_keeps_hi_prompt_without_the_setting
  _hi_check "[bash] falls back silently when absent" test_bash_falls_back_when_starship_is_absent
  _hi_check "[bash] a target points the tool at the overlay's config" test_remote_session_exports_overlay_config bash starship.toml STARSHIP_CONFIG "$_HI_WORKDIR/cfg/starship.toml" PATH="$(_hi_prompt_stub_dir starship):$PATH" _HI_PROMPT_TOOL=starship
  _hi_check "[bash] a target points eza at the overlay's theme.yml" test_remote_session_exports_overlay_config bash theme.yml EZA_CONFIG_DIR "$_HI_WORKDIR/cfg"
  _hi_check "[bash] a target points bat at the overlay's bat.conf" test_remote_session_exports_overlay_config bash bat.conf BAT_CONFIG_PATH "$_HI_WORKDIR/cfg/bat.conf"
  _hi_check "[bash] zoxide init runs when zoxide is there" test_tool_init_wires_the_tool_in bash zoxide
  _hi_check "[bash] atuin init runs when atuin is there" test_tool_init_wires_the_tool_in bash atuin
  _hi_check "[bash] zoxide init stands down: toggle, or already wired" test_tool_init_stands_down bash zoxide __zoxide_z
  _hi_check "[bash] atuin init stands down: toggle, or already wired" test_tool_init_stands_down bash atuin __atuin_history
  _hi_check_requires zsh "[zsh] zoxide init runs when zoxide is there" test_tool_init_wires_the_tool_in zsh zoxide
  _hi_check_requires zsh "[zsh] atuin init stands down: toggle, or already wired" test_tool_init_stands_down zsh atuin _atuin_search
  _hi_check_requires zsh "[zsh] defers to starship when asked and present" test_defers_to_prompt_tool_when_asked zsh starship
  _hi_check_requires zsh "[zsh] defers to oh-my-posh when asked and present" test_defers_to_prompt_tool_when_asked zsh oh-my-posh
  _hi_check_requires fish "[fish] defers to starship when asked and present" test_defers_to_prompt_tool_when_asked fish starship
  _hi_check_requires fish "[fish] defers to oh-my-posh when asked and present" test_defers_to_prompt_tool_when_asked fish oh-my-posh
  _hi_check_requires fish "[fish] a target points the tool at the overlay's config" test_remote_session_exports_overlay_config fish starship.toml STARSHIP_CONFIG "$_HI_WORKDIR/cfg/starship.toml" PATH="$(_hi_prompt_stub_dir starship):$PATH" _HI_PROMPT_TOOL=starship
  _hi_check_requires fish "[fish] a target points eza at the overlay's theme.yml" test_remote_session_exports_overlay_config fish theme.yml EZA_CONFIG_DIR "$_HI_WORKDIR/cfg"
  _hi_check_requires fish "[fish] a target points bat at the overlay's bat.conf" test_remote_session_exports_overlay_config fish bat.conf BAT_CONFIG_PATH "$_HI_WORKDIR/cfg/bat.conf"
  _hi_check_requires fish "[fish] zoxide init runs when zoxide is there" test_tool_init_wires_the_tool_in fish zoxide
  _hi_check_requires fish "[fish] atuin init stands down: toggle, or already wired" test_tool_init_stands_down fish atuin _atuin_search
  _hi_check_requires fish "[fish] the sudo wrapper follows _HI_DISABLE_SUDO_ALIAS" test_fish_sudo_wrapper_follows_the_toggle
  _hi_check_requires fish "fish registers hi completion" test_fish_registers_hi_completion
  _hi_check_requires fish "fish flag TAB does not sweep the backends" test_fish_flag_completion_does_not_also_sweep_targets
  _hi_check_requires fish "fish flag TAB completes hi's options, described" test_fish_flag_completion_offers_hi_options
  _hi_check_requires fish "fish completes the word after --preview" test_fish_completes_the_word_after_preview
  _hi_check_requires fish "fish resolves \$_HI_CONFIG_DIR as bash does" test_fish_config_dir_matches_bash
  _hi_check_requires fish "fish honours an explicit \$_HI_CONFIG_DIR" test_fish_config_dir_explicit_value_wins
  _hi_check "[bash] an overlay re-entering hi's rc returns" test_bash_rc_reentry_returns
  _hi_check_requires zsh "[zsh] an overlay re-entering hi's rc returns" test_zsh_rc_reentry_returns
  _hi_check_requires zsh "[zsh] the target list is colored per backend" test_zsh_target_list_colors_per_backend
  _hi_check_requires zsh "[zsh] target completion carries the colored tag" test_zsh_target_completion_uses_the_colored_tag
  _hi_check_requires zsh "[zsh] completion covers the alias's launcher" test_zsh_completion_covers_the_alias_target
  _hi_check "[bash] target symbols only while listing" test_bash_target_symbols_only_when_listing
  _hi_check_requires fish "[fish] target rows carry their symbol" test_fish_target_symbols
  _hi_check "[bash] a local interactive shell prints the header" test_local_shell_prints_the_header bash
  _hi_check_requires zsh "[zsh] a local interactive shell prints the header" test_local_shell_prints_the_header zsh
  _hi_check_requires fish "[fish] an overlay re-entering hi's rc returns" test_fish_rc_reentry_returns

  _hi_h2 "Testing: the prompt separator"
  # The shells install.sh wires up locally, and their shipped defaults, both
  # read off core.sh's rosters rather than spelled again here. Per shell: the
  # shipped default lands, the shell-specific setting wins, and an empty value is
  # "unset", not "no separator" - a prompt ending in a bare space is never
  # what someone meant, and ' ' still expresses it.
  local shell upper var default
  for shell in $(_hi_shell_rows | cut -d'|' -f1); do
    upper="$(printf '%s' "$shell" | tr '[:lower:]' '[:upper:]')"
    var="_HI_PROMPT_END_$upper"
    # bash's default ships as the two characters `\$`, which bash renders as $
    # for a user and # for root; these cases run as a user, so the leading
    # backslash comes off before comparing against a rendered prompt.
    default="$(_hi_prompt_end_default "$upper")"
    default="${default#\\}"
    _hi_check_requires "$shell" "[$shell] default is '$default'" _hi_prompt_ends no "$shell" "$default"
    _hi_check_requires "$shell" "[$shell] $var wins" _hi_prompt_ends no "$shell" @@ "$var=@@"
    _hi_check_requires "$shell" "[$shell] empty falls back to '$default'" _hi_prompt_ends no "$shell" "$default" "$var="
  done
  # Root gets '#' - but as the *default* giving way, never as an override,
  # which is the rule bash's shipped `\$` follows (it renders as # for root,
  # and an explicit _HI_PROMPT_END_BASH still wins). fish is the only shell
  # where that decision is made in hi's own code rather than by the shell, so
  # it is the only one with a case. Run through the shadow, so it covers the
  # branch on a non-root box too.
  _hi_check_requires fish "[fish] root takes '#' over the default" _hi_prompt_ends yes fish '#'
  _hi_check_requires fish "[fish] root keeps an explicit one" _hi_prompt_ends yes fish @@ _HI_PROMPT_END_FISH=@@

  _hi_suite_end "rc"
}

run_rc_tests
