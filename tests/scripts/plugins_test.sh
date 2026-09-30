#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Unit tests for scripts/plugins.sh - `hi --plugins`, which lists what rides
# to a target; `hi --plugin-off` and `--plugin-on`, which keep
# $_HI_PLUGINS_OFF in settings.sh; and `hi --add-plugin` and
# `--remove-plugin`, which write a line of ~/.config/say-hi/carry.
#
# Driven through `hi.sh --<flag>` rather than by calling the script directly,
# so the common/flags rows and _hi_dispatch_subcommand are covered with it,
# as set_color_test.sh drives --set-color. Each case gets its own
# $_HI_CONFIG_DIR and $HOME, so one case's files cannot bleed into another's.
#
# GLOSSARY: HI.34.
# shellcheck disable=SC2329,SC2317
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# one tree for every case: nothing here writes into it
_HI_PLUGINS_TREE=""

# _hi_plugins_run <config> <flag> <args...> - `hi <flag>` over that overlay,
# at a home of the case's own, with no toggle or list inherited
function _hi_plugins_run() {
  local cfg="$1"
  shift
  mkdir -p "$cfg.home"
  env -u _HI_PLUGINS_OFF -u _HI_DISABLE_LOCAL \
    HOME="$cfg.home" XDG_CONFIG_HOME="$cfg.home/.config" _HI_CONFIG_DIR="$cfg" \
    _HI_HOME="$_HI_PLUGINS_TREE" NO_COLOR=1 \
    "$_HI_PLUGINS_TREE/say-hi/hi.sh" "$@" 2>&1
}

# _hi_plugins_cfg <name> - a fresh overlay directory's path; nothing is made
function _hi_plugins_cfg() {
  printf '%s' "$_HI_WORKDIR/$1-cfg"
}

# _hi_plugins_off_line <list> - the line the list is kept on, as the wizard
# pads and tags its own
function _hi_plugins_off_line() {
  printf '%-45s %s' "export _HI_PLUGINS_OFF='$1'" "$_HI_MARKER"
}

# _hi_plugins_is <file> <body> - <file> holds exactly <body> (%b)
function _hi_plugins_is() {
  local want
  want="$(printf '%b' "$2")"
  [ "$(cat "$1")" = "$want" ] && return 0
  _hi_cecho " | got: [$(cat "$1" 2>&1)]" "$RED"
  return 1
}

# _hi_plugins_refused <config> <message> <flag> <args...> - the command
# fails, says <message>, and leaves the overlay as it was: not made
function _hi_plugins_refused() {
  local cfg="$1" msg="$2" out rc=0
  shift 2
  out="$(_hi_plugins_run "$cfg" "$@")" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"$msg"* ]] && [ ! -e "$cfg" ] && return 0
  _hi_cecho " | [$*] gave rc $rc: $out" "$RED"
  return 1
}

# ---------------------------------------------------------------------------
# arguments
# ---------------------------------------------------------------------------

function test_plugins_help_is_each_command_s_own() {
  local cfg out flag
  cfg="$(_hi_plugins_cfg help)"
  for flag in "--plugins:Usage: hi --plugins" "--plugin-off:Usage: hi --plugin-off <name>... [--dry-run]" \
    "--plugin-on:Usage: hi --plugin-on <name>... [--dry-run]" \
    "--add-plugin:Usage: hi --add-plugin <member> <tool> <wire> <home> [--dry-run]" \
    "--remove-plugin:Usage: hi --remove-plugin <member> [--dry-run]"; do
    out="$(_hi_plugins_run "$cfg" "${flag%%:*}" --help)" || return 1
    [[ "$out" == "${flag#*:}"* ]] || _hi_because "${flag%%:*} --help: $out" || return 1
  done
  [ ! -e "$cfg" ]
}

function test_plugins_refuse_what_they_cannot_take() {
  _hi_plugins_refused "$(_hi_plugins_cfg r1)" "takes no argument" --plugins vim &&
    _hi_plugins_refused "$(_hi_plugins_cfg r2)" "needs a plugin, a group, or a member" --plugin-off &&
    _hi_plugins_refused "$(_hi_plugins_cfg r3)" "not a plugin, a group, or a member: nosuch" --plugin-off nosuch &&
    _hi_plugins_refused "$(_hi_plugins_cfg r4)" "not a plugin, a group, or a member: colors" --plugin-off colors &&
    _hi_plugins_refused "$(_hi_plugins_cfg r5)" "unknown option --force" --plugin-on vim --force &&
    _hi_plugins_refused "$(_hi_plugins_cfg r6)" "needs a member, a tool, a wire, and a home" --add-plugin taskrc task &&
    _hi_plugins_refused "$(_hi_plugins_cfg r7)" "needs one member" --remove-plugin
}

# ---------------------------------------------------------------------------
# --plugin-off / --plugin-on
# ---------------------------------------------------------------------------

# the list is one line of settings.sh, made with its shebang when there is
# no file, a plugin, a group, and a member alike
function test_plugin_off_writes_the_list() {
  local cfg out
  cfg="$(_hi_plugins_cfg off)"
  out="$(_hi_plugins_run "$cfg" --plugin-off lazygit editors tmux/tmux.conf)" || return 1
  [[ "$out" == *" - lazygit"* && "$out" == *" - editors"* && "$out" == *"settings.sh updated"* ]] || _hi_because "said: $out" || return 1
  _hi_plugins_is "$cfg/settings.sh" "#!/bin/sh\n$(_hi_plugins_off_line 'lazygit editors tmux/tmux.conf')\n"
}

# every other line of a settings.sh stays where it was, and a second list
# line never joins the first
function test_plugin_off_keeps_the_other_settings() {
  local cfg
  cfg="$(_hi_plugins_cfg off-keeps)"
  mkdir -p "$cfg"
  printf '#!/bin/sh\nexport _HI_MAX_WIDTH=72\nexport _HI_PLUGINS_OFF="bat, rg"\nexport _HI_MUX=1\n' >"$cfg/settings.sh"
  _hi_plugins_run "$cfg" --plugin-off fzf >/dev/null || return 1
  _hi_plugins_is "$cfg/settings.sh" "#!/bin/sh\nexport _HI_MAX_WIDTH=72\nexport _HI_MUX=1\n$(_hi_plugins_off_line 'bat rg fzf')\n"
}

function test_plugin_off_twice_writes_nothing() {
  local cfg out
  cfg="$(_hi_plugins_cfg off-twice)"
  _hi_plugins_run "$cfg" --plugin-off bat >/dev/null || return 1
  out="$(_hi_plugins_run "$cfg" --plugin-off bat)" || return 1
  [[ "$out" == *"bat is off already"* && "$out" != *updated* ]] || _hi_because "said: $out" || return 1
  _hi_plugins_is "$cfg/settings.sh" "#!/bin/sh\n$(_hi_plugins_off_line 'bat')\n"
}

# switching the last one back on takes the line with it
function test_plugin_on_takes_a_word_back() {
  local cfg out
  cfg="$(_hi_plugins_cfg on)"
  _hi_plugins_run "$cfg" --plugin-off bat editors >/dev/null || return 1
  out="$(_hi_plugins_run "$cfg" --plugin-on editors)" || return 1
  [[ "$out" == *" + editors"* ]] || _hi_because "said: $out" || return 1
  _hi_plugins_is "$cfg/settings.sh" "#!/bin/sh\n$(_hi_plugins_off_line 'bat')\n" || return 1
  _hi_plugins_run "$cfg" --plugin-on bat >/dev/null || return 1
  _hi_plugins_is "$cfg/settings.sh" "#!/bin/sh\n"
}

# a word that is on says so, and nothing is written
function test_plugin_on_says_a_word_is_on() {
  local cfg out
  cfg="$(_hi_plugins_cfg on-already)"
  mkdir -p "$cfg"
  printf '#!/bin/sh\n' >"$cfg/settings.sh"
  out="$(_hi_plugins_run "$cfg" --plugin-on bat)" || return 1
  [[ "$out" == *"bat is not in the list"* ]] || _hi_because "said: $out" || return 1
  _hi_plugins_is "$cfg/settings.sh" "#!/bin/sh\n"
}

function test_plugin_off_dry_run_writes_nothing() {
  local cfg out
  cfg="$(_hi_plugins_cfg off-dry)"
  out="$(_hi_plugins_run "$cfg" --plugin-off bat --dry-run)" || return 1
  [[ "$out" == *"dry run"*"_HI_PLUGINS_OFF='bat'"* ]] && [ ! -e "$cfg" ]
}

# ---------------------------------------------------------------------------
# --add-plugin / --remove-plugin
# ---------------------------------------------------------------------------

# shellcheck disable=SC2016,SC2088 # the home column holds its $ and ~ unexpanded
function test_add_plugin_writes_a_carry_line() {
  local cfg out
  cfg="$(_hi_plugins_cfg add)"
  out="$(_hi_plugins_run "$cfg" --add-plugin taskrc task env:TASKRC '$TASKRC : ~/.taskrc')" || return 1
  [[ "$out" == *' + taskrc | task | env:TASKRC | $TASKRC : ~/.taskrc'* ]] || _hi_because "said: $out" || return 1
  _hi_plugins_run "$cfg" --add-plugin b.rc - 'flag:btool -C' - >/dev/null || return 1
  _hi_plugins_is "$cfg/carry" '# member | tool | wire | home, best first\ntaskrc | task | env:TASKRC | $TASKRC : ~/.taskrc\nb.rc | - | flag:btool -C | -\n'
}

# a carry whose last line was never ended gets the new line on one of its own
function test_add_plugin_starts_its_own_line() {
  local cfg
  cfg="$(_hi_plugins_cfg add-unended)"
  mkdir -p "$cfg"
  printf 'a.rc | - | - | /etc/a' >"$cfg/carry"
  _hi_plugins_run "$cfg" --add-plugin b.rc - - /etc/b >/dev/null || return 1
  _hi_plugins_is "$cfg/carry" 'a.rc | - | - | /etc/a\nb.rc | - | - | /etc/b\n'
}

# a line hi's own reader would turn down is never written, and says why
# shellcheck disable=SC2088 # the ~ is the carry's to read, not the shell's
function test_add_plugin_refuses_a_line_hi_cannot_read() {
  _hi_plugins_refused "$(_hi_plugins_cfg add-r1)" "'vim' is a member already" --add-plugin vim vim - '~/.vimrc' &&
    _hi_plugins_refused "$(_hi_plugins_cfg add-r2)" "'A;B' is no list of variable names" --add-plugin x.rc - 'env:A;B' '~/x' &&
    _hi_plugins_refused "$(_hi_plugins_cfg add-r3)" "is no plain file name" --add-plugin ../x - - '~/x' &&
    _hi_plugins_refused "$(_hi_plugins_cfg add-r4)" "not four columns" --add-plugin x.rc - - '~/x | y'
}

# shellcheck disable=SC2088 # the ~ is the carry's to read, not the shell's
function test_add_plugin_refuses_a_member_the_carry_has() {
  local cfg out rc=0
  cfg="$(_hi_plugins_cfg add-twice)"
  _hi_plugins_run "$cfg" --add-plugin taskrc - env:TASKRC '~/.taskrc' >/dev/null || return 1
  out="$(_hi_plugins_run "$cfg" --add-plugin taskrc - env:OTHER '~/.other')" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"'taskrc' is a member already"* ]] || _hi_because "rc $rc: $out" || return 1
  _hi_plugins_is "$cfg/carry" '# member | tool | wire | home, best first\ntaskrc | - | env:TASKRC | ~/.taskrc\n'
}

# shellcheck disable=SC2088 # the ~ is the carry's to read, not the shell's
function test_add_plugin_dry_run_writes_nothing() {
  local cfg out
  cfg="$(_hi_plugins_cfg add-dry)"
  out="$(_hi_plugins_run "$cfg" --add-plugin taskrc - env:TASKRC '~/.taskrc' -n)" || return 1
  [[ "$out" == *"dry run"*"add that line to $cfg/carry"* ]] && [ ! -e "$cfg" ]
}

# the line goes, its comments and its neighbours stay
function test_remove_plugin_takes_the_line_out() {
  local cfg out
  cfg="$(_hi_plugins_cfg remove)"
  mkdir -p "$cfg"
  printf '# mine\n  taskrc | task | env:TASKRC | ~/.taskrc\n# kept\nb.rc | - | - | ~/b\n' >"$cfg/carry"
  out="$(_hi_plugins_run "$cfg" --remove-plugin taskrc)" || return 1
  [[ "$out" == *" - "*"taskrc | task"* ]] || _hi_because "said: $out" || return 1
  _hi_plugins_is "$cfg/carry" '# mine\n# kept\nb.rc | - | - | ~/b\n'
}

# one of hi's own has no line: the answer is --plugin-off. A name nothing
# has is a no-op.
function test_remove_plugin_knows_hi_s_own_from_nothing() {
  local cfg out rc=0
  cfg="$(_hi_plugins_cfg remove-own)"
  out="$(_hi_plugins_run "$cfg" --remove-plugin vim/vimrc)" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"hi --plugin-off vim/vimrc switches it off"* ]] || _hi_because "rc $rc: $out" || return 1
  out="$(_hi_plugins_run "$cfg" --remove-plugin nosuch.rc)" || return 1
  [[ "$out" == *"has no line for nosuch.rc"* ]] && [ ! -e "$cfg" ]
}

# ---------------------------------------------------------------------------
# --plugins
# ---------------------------------------------------------------------------

# a row a member: what rides and from where, what is off and by what, and
# a line of the carry beside hi's own
function test_plugins_lists_what_rides_and_what_is_off() {
  local cfg out
  cfg="$(_hi_plugins_cfg list)"
  mkdir -p "$cfg" "$cfg.home"
  mkdir -p "$cfg/bat" "$cfg/nano"
  printf 'x\n' >"$cfg/bat/config"
  printf 'x\n' >"$cfg/nano/nanorc"
  printf 'x\n' >"$cfg.home/.taskrc"
  printf 'taskrc | - | env:TASKRC | ~/.taskrc\nbad line\n' >"$cfg/carry"
  printf '#!/bin/sh\nexport _HI_PLUGINS_OFF="mux nano"\n' >"$cfg/settings.sh"
  out="$(_hi_plugins_run "$cfg" --plugins)" || return 1
  [[ "$out" == *"bat "*"cli "*"bat/config "*"rides: $cfg/bat/config"* ]] || _hi_because "bat: $out" || return 1
  [[ "$out" == *"nano "*"editors "*"nano/nanorc "*"stays home: switched off (_HI_PLUGINS_OFF)"* ]] || _hi_because "nano: $out" || return 1
  [[ "$out" == *"tmux "*"mux "*"tmux/tmux.conf "*"stays home: switched off (_HI_PLUGINS_OFF)"* ]] || _hi_because "tmux: $out" || return 1
  [[ "$out" == *"taskrc "*"carry "*"taskrc "*"rides: ~/.taskrc"* ]] || _hi_because "taskrc: $out" || return 1
  [[ "$out" == *"line 2 is ignored"* && "$out" != *" colors "* ]] || _hi_because "the rest: $out"
}

function run_plugins_tests() {
  _hi_workdir plugins
  _hi_suite_begin
  _HI_PLUGINS_TREE="$(_hi_scratch_tree plugins-tree common config load.sh hi.sh link:scripts)"

  _hi_h2 "Testing: scripts/plugins.sh arguments"
  _hi_check "Each command's --help is its own" test_plugins_help_is_each_command_s_own
  _hi_check "What a command cannot take is refused" test_plugins_refuse_what_they_cannot_take

  _hi_h2 "Testing: --plugin-off and --plugin-on"
  _hi_check "--plugin-off writes the list to settings.sh" test_plugin_off_writes_the_list
  _hi_check "...and keeps every other line of it" test_plugin_off_keeps_the_other_settings
  _hi_check "...a word that is off already writes nothing" test_plugin_off_twice_writes_nothing
  _hi_check "--plugin-on takes a word back, and the line with the last" test_plugin_on_takes_a_word_back
  _hi_check "...and says so of a word that is on" test_plugin_on_says_a_word_is_on
  _hi_check "--dry-run names the write and writes nothing" test_plugin_off_dry_run_writes_nothing

  _hi_h2 "Testing: --add-plugin and --remove-plugin"
  _hi_check "--add-plugin writes a carry line" test_add_plugin_writes_a_carry_line
  _hi_check "...on a line of its own after an unended one" test_add_plugin_starts_its_own_line
  _hi_check "...never one hi could not read" test_add_plugin_refuses_a_line_hi_cannot_read
  _hi_check "...nor a member the carry has" test_add_plugin_refuses_a_member_the_carry_has
  _hi_check "...and nothing under --dry-run" test_add_plugin_dry_run_writes_nothing
  _hi_check "--remove-plugin takes the line out" test_remove_plugin_takes_the_line_out
  _hi_check "...and tells hi's own from a name nothing has" test_remove_plugin_knows_hi_s_own_from_nothing

  _hi_h2 "Testing: --plugins"
  _hi_check "Lists what rides and what is off" test_plugins_lists_what_rides_and_what_is_off

  _hi_suite_end "scripts/plugins.sh"
}

run_plugins_tests
