#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# common/core.sh on a target with nothing but a shell, the shell table, the
# small formatters, and the verdicts hi ships.
# A part of core_test.sh, a suite of its own so the Windows shards split them.
# The preamble's source line is core_test.sh's - it sources the harness, and
# holds the helpers the parts share (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329,SC2016
set -euo pipefail

_HI_CORE_PART=target
# shellcheck source=./core_test.sh
source "${BASH_SOURCE[0]%/*}/core_test.sh"

#
# hi is meant to reach a scratch or distroless container: bash and no
# coreutils at all, so `hostname`, `uname`, `whoami`, and `id` are none of them
# there. The identity helpers are read for the banner and the prompt on every
# connect, so what they do without their binaries is user-visible: unhandled,
# that is "uname: command not found" at the top of the session, and a colour
# hashed off an empty string.
#
# A child shell per case: the answers are memoized for the life of a shell, so
# this one's PATH has to be in place before the first call. 2>&1 into the
# assertion on purpose - a rung that leaked to stderr is the whole bug.
# shellcheck disable=SC2016 # the probe expands in the child bash, not here
function _hi_barebones() {
  _hi_bare_bash barebones bash \
    'source "$_HI_HOME/say-hi/common/core.sh"; printf "%s" "$(eval "$_HI_CASE_PROBE")"' "$@"
}

# a bash before 4.4, where _hi_prompt_escape has no ${x@P} to answer with and
# the binaries, then the variables, are the ladder
_HI_NO_ESCAPE='_hi_prompt_escape() { return 1; };'

# _hi_prompt_escape: the shell expands the escape itself - bash 4.4+'s
# ${x@P} - into the named variable, and an older bash says 1
function test_prompt_escape_answers_in_the_shell() {
  local got
  local out="" rc=0
  _hi_prompt_escape out '\u' || rc=$?
  if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4))); then
    got="$(id -un)"
    [ "$rc" = 0 ] && [ "$out" = "$got" ] || _hi_because "\\u: rc $rc, [$out]"
  else
    [ "$rc" = 1 ] || _hi_because "bash $BASH_VERSION: rc $rc"
  fi
}

# ...and zsh's (%) flag, any zsh
function test_zsh_prompt_escape_answers_in_the_shell() {
  local out got
  out="$(env _HI_HOME="$_HI_HOME" zsh -c 'source "$_HI_HOME/say-hi/common/core.sh"
    _hi_prompt_escape v "%n" && print -rn -- "$v"' 2>&1)"
  got="$(id -un)"
  [ "$out" = "$got" ] || _hi_because "%n: [$out]"
}

# the host's name is the kernel's, from bash's \H or the binaries: an
# exported $HOSTNAME from somewhere else cannot rename it (zsh forks for it)
function test_hostname_ignores_an_inherited_hostname() {
  local out got
  out="$(env -u _HI_HOSTNAME_CACHE _HI_HOME="$_HI_HOME" HOSTNAME=fake-inherited bash -c \
    'source "$_HI_HOME/say-hi/common/core.sh"; _hi_hostname' 2>&1)"
  got="$(uname -n)"
  [ "$out" = "$got" ] || _hi_because "_hi_hostname: [$out]"
}

# <shell>: the user is the passwd entry's, never an inherited $USER/$LOGNAME
function test_whoami_ignores_an_inherited_user() {
  local out got
  out="$(env -u _HI_WHOAMI_CACHE _HI_HOME="$_HI_HOME" USER=fake-inherited LOGNAME=fake-inherited "$1" -c \
    'source "$_HI_HOME/say-hi/common/core.sh"; _hi_whoami' 2>&1)"
  got="$(id -un)"
  [ "$out" = "$got" ] || _hi_because "$1 _hi_whoami: [$out]"
}

# $EPOCHREALTIME unset is bash 3.2 (macOS) as much as it is a stripped box:
# unsetting it drops the special attribute, so the date(1) rung is reachable
# from a bash 5 that would otherwise never fork.
function test_now_answers_without_date() {
  local out
  out="$(_hi_barebones _HI_CASE_PROBE='unset EPOCHREALTIME; _hi_now')"
  case "$out" in '' | *[!0-9.]*) _hi_why out || return 1 ;; esac
}

# ...and a date(1) with no %N (old BSD) prints the N back: the whole
# seconds are the answer then, not a figure with an N in it
function test_now_takes_whole_seconds_from_a_date_without_nanoseconds() {
  local dir="$_HI_WORKDIR/bsd-date" out
  mkdir -p "$dir"
  printf '%s\n' '#!/bin/sh' 'case "$1" in +%s.%N) echo 1700000000.N ;; *) echo 1700000000 ;; esac' >"$dir/date"
  chmod +x "$dir/date"
  out="$(unset EPOCHREALTIME && PATH="$dir" _hi_now)"
  [ "$out" = 1700000000 ] || _hi_because "_hi_now: $out"
}

# Every row has all six fields and both rc paths are absolute. A row short a
# field silently hands install.sh an empty rc path, which is a `touch ""` at
# install time.
function test_shell_table_rows_are_wellformed() {
  local row shell label tree home check dialect rest
  for row in "${_HI_SHELL_TABLE[@]}"; do
    IFS='|' read -r shell label tree home check dialect rest <<<"$row"
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

# OSC 7's path: unreserved bytes pass, every other byte is %XX in upper case,
# a multi-byte character one escape per byte
function test_url_path_percent_encodes_byte_by_byte() {
  local u
  _hi_url_path u /plain/path_1.x~-
  [ "$u" = /plain/path_1.x~- ] || _hi_because "plain: [$u]" || return 1
  _hi_url_path u "/a b/n$(printf '\303\251')e/100%#?"
  [ "$u" = "/a%20b/n%C3%A9e/100%25%23%3F" ] || _hi_because "encoded: [$u]"
}

function test_repeat_makes_count_copies() {
  local out
  _hi_repeat out 4 '='
  [ "$out" = "====" ] || _hi_why out || return 1
  _hi_repeat out 0 '='
  [ -z "$out" ] || _hi_why out
}

function test_human_duration_formats() {
  local out got got2 got3
  _hi_human_duration 90000 out
  got="$(_hi_human_duration 5400)"
  got2="$(_hi_human_duration 179.9)"
  got3="$(_hi_human_duration 59)"
  [ "$out" = "1d 1h" ] && [ "$got" = "1h 30m" ] && [ "$got2" = "2m" ] && [ "$got3" = "0m" ] || _hi_why got got2 got3 out
}

function test_du_size_answers_for_a_real_path() {
  local dir="$_HI_WORKDIR/du.probe" out
  mkdir -p "$dir"
  printf '%2048s' '' >"$dir/two-k"
  out="$(_hi_du_size "$dir")"
  [ -n "$out" ] || _hi_why out || return 1
  case "$out" in [0-9]*) ;; *) _hi_why out || return 1 ;; esac
}

# the shipped verdicts win; the local binaries are only the fallback
function test_local_identity_prefers_the_shipped_verdict() {
  local got
  got="$(_HI_LOCAL_USER=shipped-user _hi_local_username)"
  [ "$got" = shipped-user ] || _hi_why got || return 1
  got="$(_HI_LOCAL_HOSTNAME=shipped-host _hi_local_hostname)"
  [ "$got" = shipped-host ] || _hi_why got || return 1
  (
    unset _HI_LOCAL_USER _HI_LOCAL_HOSTNAME
    [ "$(_hi_local_username)" = "$(_hi_whoami)" ] &&
      [ "$(_hi_local_hostname)" = "$(_hi_hostname)" ]
  ) || _hi_why
}

function test_ascii_flag_ships_the_verdict() {
  { (
    _HI_ASCII=1
    [ "$(_hi_ascii_flag)" = 1 ]
  ) && (
    _HI_ASCII=0
    [ "$(_hi_ascii_flag)" = 0 ]
  ); } || _hi_why
}

# never auto-detected: the setting and the program both have to say yes, the
# setting has to name a program hi knows how to start, and a list goes to its
# first entry that fits the shell - a framework through the shell's own
# _hi_prompt_fw
function test_prompt_tool_needs_setting_program_and_shell() {
  local got2
  local got="" p
  mkdir -p "$_HI_WORKDIR/empty.path"
  p="$(_hi_fake_path pgo powerline-go):$(_hi_fake_path posh oh-my-posh)"
  # unset, every program is in the list at home, and none on a target, which
  # hi.sh hands home's answer; `hi` is hi's own prompt, ending the walk
  (
    unset _HI_PROMPT_TOOL
    got2="$(PATH="$p" _hi_prompt_tool bash)"
    [ "$got2" = oh-my-posh ] || _hi_why got2 p || exit 1
    ! _HI_REMOTE_SESSION=1 PATH="$p" _hi_prompt_tool bash
  ) || _hi_why p || return 1
  ! _HI_PROMPT_TOOL="hi powerline-go" PATH="$p" _hi_prompt_tool bash || _hi_why p || return 1
  ! _HI_PROMPT_TOOL=starship PATH="$_HI_WORKDIR/empty.path" _hi_prompt_tool bash || _hi_why || return 1
  _HI_PROMPT_TOOL=starship PATH="$(_hi_fake_path star starship):$PATH" _hi_prompt_tool bash || _hi_why || return 1
  _HI_PROMPT_TOOL="starship  powerline-go oh-my-posh" PATH="$p" _hi_prompt_tool zsh got || _hi_why p || return 1
  [ "$got" = powerline-go ] || _hi_why got || return 1
  # a program hi has no start for is not handed the prompt, present or not
  ! _HI_PROMPT_TOOL=powerline PATH="$(_hi_fake_path pl powerline):$PATH" _hi_prompt_tool bash || _hi_why || return 1
  # a framework is asked about only in its own shell
  (
    function _hi_prompt_fw() { [ "$1" = oh-my-bash ] || [ "$1" = bash-it ]; }
    ! _HI_PROMPT_TOOL="tide powerlevel10k oh-my-zsh" _hi_prompt_tool zsh || _hi_why || exit 1
    got2="$(_HI_PROMPT_TOOL="tide oh-my-bash" _hi_prompt_tool bash)"
    [ "$got2" = oh-my-bash ] || _hi_why got2 || exit 1
    ! _HI_PROMPT_TOOL=oh-my-bash _hi_prompt_tool zsh || _hi_why || exit 1
    # two bash fw rows: the walk picks the first that fits, by $1, not either
    # answering for the other (common/bash.sh's _hi_prompt_fw once did)
    got2="$(_HI_PROMPT_TOOL="oh-my-bash bash-it" _hi_prompt_tool bash)"
    [ "$got2" = oh-my-bash ] || _hi_why got2 || exit 1
    [ "$(_HI_PROMPT_TOOL="bash-it oh-my-bash" _hi_prompt_tool bash)" = bash-it ]
  ) || _hi_why
}

# a <shell>:<program> entry is walked first, by its shell alone; with no plain
# entry the rest is the unset list (starship first of the two here) at home,
# and nothing more on a target. No framework is loaded, so the walk passes
# over them.
function test_prompt_tool_per_shell_entries() {
  local p got
  p="$(_hi_fake_path star2 starship):$(_hi_fake_path posh2 oh-my-posh)"
  (
    function _hi_prompt_fw() { return 1; }
    got="$(_HI_PROMPT_TOOL="hi bash:oh-my-posh" PATH="$p" _hi_prompt_tool bash)"
    [ "$got" = oh-my-posh ] || _hi_why got p || exit 1
    ! _HI_PROMPT_TOOL="bash:starship hi" PATH="$p" _hi_prompt_tool zsh || _hi_why p || exit 1
    got="$(_HI_PROMPT_TOOL="zsh:hi" PATH="$p" _hi_prompt_tool bash)"
    [ "$got" = starship ] || _hi_why got p || exit 1
    ! _HI_PROMPT_TOOL="zsh:hi" PATH="$p" _hi_prompt_tool zsh || _hi_why p || exit 1
    ! _HI_PROMPT_TOOL="zsh:starship" _HI_REMOTE_SESSION=1 PATH="$p" _hi_prompt_tool bash || _hi_why p || exit 1
    # a missing pick falls through to the rest
    [ "$(_HI_PROMPT_TOOL="bash:powerline-go oh-my-posh" PATH="$p" _hi_prompt_tool bash)" = oh-my-posh ]
  ) || _hi_why p || return 1
  { _HI_PROMPT_TOOL="zsh:hi" _hi_prompt_named_hi zsh && ! _HI_PROMPT_TOOL="zsh:hi" _hi_prompt_named_hi bash &&
    _HI_PROMPT_TOOL="bash:starship hi" _hi_prompt_named_hi fish; } || _hi_why
}

# _HI_PROMPT_TABLE is the one roster: a row answers to its program and to
# each overlay member it names, _HI_PROMPT_TOOLS is its first column in
# order, and config.fish's hand copy of the fish-fitting names matches it
function test_prompt_table_is_the_one_roster() {
  local row="" tools="" fish_have fish_want="" r
  _hi_prompt_row oh-my-posh row && [ "${row%%|*}" = oh-my-posh ] || _hi_why row || return 1
  _hi_prompt_row oh-my-posh.yaml row && [ "${row%%|*}" = oh-my-posh ] || _hi_why row || return 1
  _hi_prompt_row p10k.zsh row && [ "${row%%|*}" = powerlevel10k ] || _hi_why row || return 1
  ! _hi_prompt_row powerline row 2>/dev/null || _hi_why || return 1
  ! _hi_prompt_row zsh row 2>/dev/null || _hi_why || return 1
  for r in "${_HI_PROMPT_TABLE[@]}"; do
    tools="$tools${tools:+ }${r%%|*}"
    case "$r" in *'|'*fish*'|'*) fish_want="$fish_want${fish_want:+ }${r%%|*}" ;; esac
  done
  # shellcheck disable=SC2153 # core.sh's derived roster, not a typo of the setting
  [ "$tools" = "$_HI_PROMPT_TOOLS" ] || _hi_why tools _HI_PROMPT_TOOLS || return 1
  fish_have="$(sed -n 's/.*; and set _hi_plain \(.*\)$/\1/p' "$_HI_ROOT/common/config.fish")"
  [ "$fish_have" = "$fish_want" ] || {
    _hi_cecho " | config.fish: [$fish_have]  core.sh: [$fish_want]" "$RED"
    return 1
  }
}

# ...and after it, the prompt plugins the client handed over as
# _HI_PROMPT_PLUGINS rows, by name alone (GLOSSARY: HI.67)
function test_prompt_row_reads_the_plugin_rows() {
  local row=""
  _HI_PROMPT_PLUGINS="fancy|bash zsh|bin|-;plain|fish|bin|-" _hi_prompt_row plain row && [ "$row" = "plain|fish|bin|-" ] || _hi_why row || return 1
  _HI_PROMPT_PLUGINS="fancy|bash zsh|bin|-" _hi_prompt_row fancy row && [ "$row" = "fancy|bash zsh|bin|-" ] || _hi_why row || return 1
  _HI_PROMPT_PLUGINS="fancy|bash zsh|bin|-" _hi_prompt_row oh-my-posh row && [ "${row%%|*}" = oh-my-posh ] || _hi_why row || return 1
  ! _HI_PROMPT_PLUGINS="fancy|bash zsh|bin|-" _hi_prompt_row bin row 2>/dev/null || _hi_why
}

# _hi_hook_on: the off list wins by name, a plain name is on, and a name
# with a leading - (off by default) needs the on list to name it, commas or
# spaces apart; its group's word switches nothing in either
function test_hook_on_reads_both_lists() {
  { _hi_hook_on zoxide &&
    ! _HI_PLUGINS_OFF=zoxide _hi_hook_on zoxide &&
    ! _HI_PLUGINS_OFF="bat,zoxide" _hi_hook_on zoxide &&
    _HI_PLUGINS_OFF="cli,hooks" _hi_hook_on zoxide &&
    ! _hi_hook_on -zoxide &&
    _HI_PLUGINS_ON=zoxide _hi_hook_on -zoxide &&
    _HI_PLUGINS_ON="atuin zoxide" _hi_hook_on -zoxide &&
    ! _HI_PLUGINS_ON="cli,hooks" _hi_hook_on -zoxide &&
    ! _HI_PLUGINS_ON=zoxide _HI_PLUGINS_OFF=zoxide _hi_hook_on -zoxide; } || _hi_why
}

# _hi_run_init fills {shell} in, runs the command only where its first word
# is here, and runs what it prints in this shell; _hi_run_hooks walks the
# rows the lists leave on; _hi_prompt_init answers from _HI_PROMPT_INITS,
# else with the `<program> init {shell}` shape (GLOSSARY: HI.67)
function test_run_init_runs_what_the_tool_prints() {
  local p="$_HI_WORKDIR/init-bins" got=""
  mkdir -p "$p"
  printf '%s\n' '#!/bin/sh' 'printf "_hi_ri_got=\"%s\"\n" "$*"' >"$p/hi-init-tool"
  chmod +x "$p/hi-init-tool"
  unset _hi_ri_got
  PATH="$p:$PATH" _hi_run_init zsh hi-init-tool init "{shell}" --flag || _hi_why p || return 1
  [ "${_hi_ri_got:-}" = "init zsh --flag" ] || _hi_because "ran: ${_hi_ri_got:-}" || return 1
  ! PATH="$p" _hi_run_init bash hi-no-such-tool init "{shell}" || _hi_because "a tool not here ran" || return 1
  unset _hi_ri_got
  _HI_HOOKS="x.hi-init-tool=hi-init-tool init {shell};x.-off=hi-init-tool off {shell};x.gone=hi-no-such init {shell}" \
    PATH="$p:$PATH" _hi_run_hooks bash || _hi_why p || return 1
  [ "${_hi_ri_got:-}" = "init bash" ] || _hi_because "hooks ran: ${_hi_ri_got:-}" || return 1
  _HI_HOOKS="x.-off=hi-init-tool off {shell}" _HI_PLUGINS_ON=off PATH="$p:$PATH" _hi_run_hooks fish || _hi_why p || return 1
  [ "${_hi_ri_got:-}" = "off fish" ] || _hi_because "a default-off hook on: ${_hi_ri_got:-}" || return 1
  unset _hi_ri_got
  _HI_HOOKS="x.hi-init-tool=hi-init-tool init {shell}" _HI_PLUGINS_OFF=hi-init-tool PATH="$p:$PATH" _hi_run_hooks bash || _hi_why p || return 1
  [ -z "${_hi_ri_got:-}" ] || _hi_because "a hook off ran" || return 1
  # a :<shells> after the name keeps the hook to those
  _HI_HOOKS="x.hi-init-tool:zsh,fish=hi-init-tool init {shell}" PATH="$p:$PATH" _hi_run_hooks bash || _hi_why p || return 1
  [ -z "${_hi_ri_got:-}" ] || _hi_because "a zsh and fish hook ran in bash" || return 1
  _HI_HOOKS="x.-off:zsh,fish=hi-init-tool kept {shell}" _HI_PLUGINS_ON=off PATH="$p:$PATH" _hi_run_hooks zsh || _hi_why p || return 1
  [ "${_hi_ri_got:-}" = "kept zsh" ] || _hi_because "a zsh hook in zsh: ${_hi_ri_got:-}" || return 1
  _HI_PROMPT_INITS="a=a start {shell};omp=oh-my-posh init {shell} --config x" _hi_prompt_init omp got &&
    [ "$got" = "oh-my-posh init {shell} --config x" ] || _hi_because "init row: $got" || return 1
  _hi_prompt_init starship got && [ "$got" = "starship init {shell}" ] || _hi_why got
}

function test_colors_lookup_verdicts() {
  local got
  local colors="$_HI_WORKDIR/colors.lookup"
  printf '[username]\nalice = "red"\n[hostname]\nbox = "blue"\n' >"$colors"
  got="$(_HI_COLORS="$colors" _hi_colors_lookup hostname box)"
  [ "$got" = blue ] || _hi_why got colors || return 1
  ! _HI_COLORS="$colors" _hi_colors_lookup hostname nobox || _hi_why colors || return 1
  ! _HI_COLORS="$_HI_WORKDIR/colors.absent" _hi_colors_lookup hostname box || _hi_why
}

# the memo pair: a shipped _HI_TARGET_COLOR wins outright, and the escape is
# the escape of whatever the color half answered
function test_host_color_memo_and_escape_agree() {
  local got
  (
    unset _HI_HOST_COLOR _HI_HOST_ESC
    _HI_TARGET_COLOR=blue
    got="$(_hi_host_color)"
    [ "$got" = blue ] || _hi_why got || exit 1
    [ "$(_hi_host_escape)" = "$(_hi_color_escape blue)" ]
  ) || _hi_why
}

function test_user_color_resolves_like_resolve_color() {
  (
    unset _HI_USER_COLOR _HI_TARGET_TAG
    [ "$(_hi_user_color)" = "$(_hi_resolve_color username "$(_hi_whoami)")" ]
  ) || _hi_why
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
  ) || _hi_why h u
}

# the version, unpresented: a packager's stamp wins outright, else git
# describe against $_HI_ROOT, else empty. header.sh's version cell and hi.sh's
# --version both go through this.
function test_release_or_describe_prefers_the_stamp() {
  (
    _HI_RELEASE=1.2.3
    [ "$(_hi_release_or_describe)" = 1.2.3 ]
  ) || _hi_why
}

function test_release_or_describe_falls_back_to_git() {
  (
    unset _HI_RELEASE
    [ -d "$_HI_ROOT/.git" ] || return 0 # nothing to fall back to in a tarball checkout
    [ -n "$(_hi_release_or_describe)" ]
  ) || _hi_why -6
}

# _hi_git_version against a scratch repo: on the tag, past it, dirty, and a
# snapshot-<sha> tag nearer than the v* one, which must not count
function test_git_version_names_commits_past_the_tag() {
  local dir g got
  dir="$(mktemp -d "$_HI_WORKDIR/gitversion.XXXXXX")"
  g=(git -C "$dir" -c commit.gpgsign=false -c tag.gpgsign=false -c user.name=t -c user.email=t@t)
  "${g[@]}" init -q && "${g[@]}" commit -q --allow-empty -m a && "${g[@]}" tag v1.2.3 || _hi_why g || return 1
  got="$(_hi_git_version "$dir")"
  [ "$got" = v1.2.3 ] || _hi_why got dir || return 1
  "${g[@]}" commit -q --allow-empty -m b && "${g[@]}" tag snapshot-abc1234 &&
    "${g[@]}" commit -q --allow-empty -m c || _hi_why g || return 1
  got="$(_hi_git_version "$dir")"
  [ "$got" = v1.2.3+2 ] || _hi_why got dir || return 1
  : >"$dir/f" && "${g[@]}" add f || _hi_why dir g || return 1
  got="$(_hi_git_version "$dir")"
  [ "$got" = v1.2.3+2-dirty ] || _hi_why got dir
}

function test_release_or_describe_empty_without_either() {
  local dir
  dir="$(mktemp -d "$_HI_WORKDIR/norelease.XXXXXX")"
  (
    unset _HI_RELEASE
    _HI_ROOT="$dir"
    [ -z "$(_hi_release_or_describe)" ]
  ) || _hi_why dir
}

# _hi_interactive_extras sets the debian_chroot label and nothing for less:
# no lesspipe, so no LESSOPEN or LESSCLOSE, whatever the box has installed
function test_interactive_extras_leaves_less_alone() {
  (
    unset LESSOPEN LESSCLOSE
    _hi_interactive_extras
    [ -z "${LESSOPEN+x}${LESSCLOSE+x}" ]
  ) || _hi_why LESSOPEN LESSCLOSE
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
    [ "${_HI_USER_COLOR+x}" = x ] || _hi_why _HI_HOSTNAME_CACHE _HI_WHOAMI_CACHE _HI_HOST_COLOR _HI_USER_COLOR
}

function run_core_target_tests() {
  _hi_core_begin

  _hi_h1 "Testing common/core.sh (a bare target)"

  _hi_h2 "Testing: a target with nothing but a shell"
  _hi_check_eq "Hostname falls back to the shell's own" probe-host _hi_barebones _HI_CASE_PROBE="$_HI_NO_ESCAPE _hi_hostname" HOSTNAME=probe-host
  _hi_check_eq "...and to \"unknown\" with nothing to ask" unknown _hi_barebones _HI_CASE_PROBE="$_HI_NO_ESCAPE _hi_hostname" HOSTNAME=
  _hi_check_eq "Whoami falls back to \$USER" probe-user _hi_barebones _HI_CASE_PROBE="$_HI_NO_ESCAPE _hi_whoami" USER=probe-user
  _hi_check_eq "...and to \$LOGNAME" probe-logname _hi_barebones _HI_CASE_PROBE="$_HI_NO_ESCAPE _hi_whoami" LOGNAME=probe-logname
  _hi_check_eq "...and to \"unknown\" with nothing to ask" unknown _hi_barebones _HI_CASE_PROBE="$_HI_NO_ESCAPE _hi_whoami"
  _hi_check "The shell's escape answers, no binary asked" test_prompt_escape_answers_in_the_shell
  _hi_check_requires zsh "...in zsh too" test_zsh_prompt_escape_answers_in_the_shell
  _hi_check "An inherited \$HOSTNAME does not steer _hi_hostname" test_hostname_ignores_an_inherited_hostname
  _hi_check "An inherited \$USER does not steer _hi_whoami" test_whoami_ignores_an_inherited_user bash
  _hi_check_requires zsh "...in zsh too" test_whoami_ignores_an_inherited_user zsh
  _hi_check "_hi_now answers without date(1)" test_now_answers_without_date
  _hi_check "...and in whole seconds from a date(1) with no %N" test_now_takes_whole_seconds_from_a_date_without_nanoseconds

  _hi_h2 "Testing: _HI_SHELL_TABLE"
  _hi_check "Every row is six well-formed fields" test_shell_table_rows_are_wellformed
  _hi_check "Every paths.sh rc var has a row" test_shell_table_covers_every_rc_path_var

  _hi_h2 "Testing: the small formatters"
  _hi_check "_hi_repeat makes count copies" test_repeat_makes_count_copies
  _hi_check "_hi_url_path percent-encodes byte by byte" test_url_path_percent_encodes_byte_by_byte
  _hi_check "_hi_human_duration's shapes, stdout and outvar" test_human_duration_formats
  _hi_check "_hi_du_size answers for a real path" test_du_size_answers_for_a_real_path

  _hi_h2 "Testing: the shipped verdicts"
  _hi_check "Local identity prefers the shipped verdict" test_local_identity_prefers_the_shipped_verdict
  _hi_check "_hi_ascii_flag ships the client's verdict" test_ascii_flag_ships_the_verdict
  _hi_check "_hi_prompt_tool needs the setting, the program, and its shell" test_prompt_tool_needs_setting_program_and_shell
  _hi_check "...and walks a shell's own entries first" test_prompt_tool_per_shell_entries
  _hi_check "the prompt table is the one roster, fish's copy included" test_prompt_table_is_the_one_roster
  _hi_check "...and the client's prompt plugin rows are read after it" test_prompt_row_reads_the_plugin_rows
  _hi_check "_hi_hook_on reads the off list, then the on list for a default-off hook" test_hook_on_reads_both_lists
  _hi_check "_hi_run_init runs what the tool prints, where the tool is here" test_run_init_runs_what_the_tool_prints

  _hi_h2 "Testing: the colors file readers and the identity memos"
  _hi_check "_hi_colors_lookup's three verdicts" test_colors_lookup_verdicts
  _hi_check "Host memo honors \$_HI_TARGET_COLOR; escape agrees" test_host_color_memo_and_escape_agree
  _hi_check "User color resolves like _hi_resolve_color" test_user_color_resolves_like_resolve_color
  _hi_check "The out-var escape forms fill the caller" test_escape_var_forms_fill_the_caller
  _hi_check "_hi_prime_identity fills every memo in the caller" test_prime_identity_fills_every_memo_in_the_caller

  _hi_h2 "Testing: _hi_release_or_describe"
  _hi_check "A shipped \$_HI_RELEASE wins outright" test_release_or_describe_prefers_the_stamp
  _hi_check "Falls back to git describe against \$_HI_ROOT" test_release_or_describe_falls_back_to_git
  _hi_check "_hi_git_version names commits past a v* tag as <tag>+N" test_git_version_names_commits_past_the_tag
  _hi_check "Empty with neither a stamp nor a .git" test_release_or_describe_empty_without_either
  _hi_check "_hi_interactive_extras sets nothing for less" test_interactive_extras_leaves_less_alone

  _hi_suite_end "core.sh (a bare target)"
}

run_core_target_tests
