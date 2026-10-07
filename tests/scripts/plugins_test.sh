#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Unit tests for scripts/plugins.sh - `hi --plugins`, which lists what rides
# to a target; `hi --plugin-off` and `--plugin-on`, which keep
# $_HI_PLUGINS_OFF in settings.sh; and `hi --add-plugin` and
# `--remove-plugin`, which write a table of ~/.config/say-hi/plugins.
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
# at a home of the case's own, with no toggle or list inherited. What it says
# goes through a file, so a run that wrote nothing is told on stderr from one
# whose words the caller's capture lost: Windows arm64 has shown an empty
# capture from a run that exited 0.
function _hi_plugins_run() {
  local cfg="$1" rc=0
  shift
  mkdir -p "$cfg.home"
  env -u _HI_PLUGINS_OFF -u _HI_DISABLE_LOCAL \
    HOME="$cfg.home" XDG_CONFIG_HOME="$cfg.home/.config" _HI_CONFIG_DIR="$cfg" \
    _HI_HOME="$_HI_PLUGINS_TREE" NO_COLOR=1 \
    "$_HI_PLUGINS_TREE/say-hi/hi.sh" "$@" >"$cfg.said" 2>&1 || rc=$?
  cat "$cfg.said"
  [ -s "$cfg.said" ] ||
    printf ' | hi %s wrote nothing and exited %s; its overlay holds: %s\n' "$*" "$rc" "$(printf '%s ' "$cfg"/*)" >&2
  return "$rc"
}

# _hi_plugins_cfg <name> - a fresh overlay directory's path; nothing is made.
# Numbered past what an earlier try of the case left, so a traced rerun
# starts as clean as the first.
function _hi_plugins_cfg() {
  local n=1
  while [ -e "$_HI_WORKDIR/$1-cfg.$n" ] || [ -e "$_HI_WORKDIR/$1-cfg.$n.home" ]; do n=$((n + 1)); done
  printf '%s' "$_HI_WORKDIR/$1-cfg.$n"
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
    "--add-plugin:Usage: hi --add-plugin <group> <name> <file>... [<key>=<value>...] [--dry-run]" \
    "--remove-plugin:Usage: hi --remove-plugin <name> [--dry-run]"; do
    out="$(_hi_plugins_run "$cfg" "${flag%%:*}" --help)" || return 1
    [[ "$out" == "${flag#*:}"* ]] || _hi_because "${flag%%:*} --help: $out" || return 1
  done
  [ ! -e "$cfg" ]
}

function test_plugins_refuse_what_they_cannot_take() {
  _hi_plugins_refused "$(_hi_plugins_cfg r1)" "takes no argument" --plugins vim &&
    _hi_plugins_refused "$(_hi_plugins_cfg r2)" "needs a plugin or a member" --plugin-off &&
    _hi_plugins_refused "$(_hi_plugins_cfg r3)" "not a plugin or a member: nosuch" --plugin-off nosuch &&
    _hi_plugins_refused "$(_hi_plugins_cfg r4)" "not a plugin or a member: colors" --plugin-off colors &&
    _hi_plugins_refused "$(_hi_plugins_cfg r4g)" "not a plugin or a member: editors" --plugin-off editors &&
    _hi_plugins_refused "$(_hi_plugins_cfg r4h)" "not a plugin or a member: hooks" --plugin-on hooks &&
    _hi_plugins_refused "$(_hi_plugins_cfg r5)" "unknown option --force" --plugin-on vim --force &&
    _hi_plugins_refused "$(_hi_plugins_cfg r6)" "needs a group, a name, and a file" --add-plugin cli task &&
    _hi_plugins_refused "$(_hi_plugins_cfg r9)" "needs a file for task to carry" --add-plugin cli task wire=env:TASKRC &&
    _hi_plugins_refused "$(_hi_plugins_cfg r8)" "not a group or a plugin's name: my group" --add-plugin "my group" task taskrc &&
    _hi_plugins_refused "$(_hi_plugins_cfg r10)" "not a group or a plugin's name: my.task" --add-plugin cli my.task taskrc &&
    _hi_plugins_refused "$(_hi_plugins_cfg r7)" "needs one plugin's name" --remove-plugin
}

# ---------------------------------------------------------------------------
# --plugin-off / --plugin-on
# ---------------------------------------------------------------------------

# the list is one line of settings.sh, made with its shebang when there is
# no file, a plugin and a member alike
function test_plugin_off_writes_the_list() {
  local cfg out
  cfg="$(_hi_plugins_cfg off)"
  out="$(_hi_plugins_run "$cfg" --plugin-off lazygit vim tmux/tmux.conf)" || return 1
  [[ "$out" == *" - lazygit"* && "$out" == *" - vim"* && "$out" == *"settings.sh updated"* ]] || _hi_because "said: $out" || return 1
  _hi_plugins_is "$cfg/settings.sh" "#!/bin/sh\n$(_hi_plugins_off_line 'lazygit vim tmux/tmux.conf')\n"
}

# one file of a directory member is a word too, there or not; a file of
# hi's own directory, a path further down, and a backup's name are not
function test_plugin_off_takes_one_file_of_a_directory() {
  local cfg out
  cfg="$(_hi_plugins_cfg off-file)"
  out="$(_hi_plugins_run "$cfg" --plugin-off extensions/10-kube zellij/layouts/work.kdl)" || return 1
  [[ "$out" == *" - extensions/10-kube"* ]] || _hi_because "said: $out" || return 1
  _hi_plugins_is "$cfg/settings.sh" "#!/bin/sh\n$(_hi_plugins_off_line 'extensions/10-kube zellij/layouts/work.kdl')\n" || return 1
  _hi_plugins_run "$cfg" --plugin-on extensions/10-kube zellij/layouts/work.kdl >/dev/null || return 1
  _hi_plugins_is "$cfg/settings.sh" "#!/bin/sh\n" || return 1
  _hi_plugins_refused "$(_hi_plugins_cfg off-file-r1)" "not a plugin or a member: header/sky" --plugin-off header/sky &&
    _hi_plugins_refused "$(_hi_plugins_cfg off-file-r2)" "not a plugin or a member: extensions/sub/x" --plugin-off extensions/sub/x &&
    _hi_plugins_refused "$(_hi_plugins_cfg off-file-r3)" "not a plugin or a member: extensions/x.bak" --plugin-off extensions/x.bak &&
    _hi_plugins_refused "$(_hi_plugins_cfg off-file-r4)" "not a plugin or a member: vim/other" --plugin-off vim/other
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
  _hi_plugins_run "$cfg" --plugin-off bat vim >/dev/null || return 1
  out="$(_hi_plugins_run "$cfg" --plugin-on vim)" || return 1
  [[ "$out" == *" + vim"* ]] || _hi_because "said: $out" || return 1
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

# a plugin off by default moves through _HI_PLUGINS_ON: on adds it, off
# takes it out, and neither touches _HI_PLUGINS_OFF
function test_plugin_on_moves_a_default_off_plugin() {
  local cfg out
  cfg="$(_hi_plugins_cfg on-default)"
  out="$(_hi_plugins_run "$cfg" --plugin-on zoxide)" || return 1
  [[ "$out" == *" + zoxide"* ]] || _hi_because "said: $out" || return 1
  _hi_plugins_is "$cfg/settings.sh" "#!/bin/sh\n$(printf '%-45s %s' "export _HI_PLUGINS_ON='zoxide'" "$_HI_MARKER")\n" || return 1
  out="$(_hi_plugins_run "$cfg" --plugin-on zoxide)" || return 1
  [[ "$out" == *"zoxide is on already"* ]] || _hi_because "said: $out" || return 1
  _hi_plugins_run "$cfg" --plugin-on mise >/dev/null && _hi_plugins_run "$cfg" --plugin-off zoxide >/dev/null || return 1
  _hi_plugins_is "$cfg/settings.sh" "#!/bin/sh\n$(printf '%-45s %s' "export _HI_PLUGINS_ON='mise'" "$_HI_MARKER")\n" || return 1
  out="$(_hi_plugins_run "$cfg" --plugin-off mise)" || return 1
  [[ "$out" == *" - mise"* ]] || _hi_because "said: $out" || return 1
  _hi_plugins_is "$cfg/settings.sh" "#!/bin/sh\n" || return 1
  out="$(_hi_plugins_run "$cfg" --plugin-off atuin)" || return 1
  [[ "$out" == *"atuin is off already (off by default)"* ]] || _hi_because "said: $out"
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

_HI_PLUGINS_HEAD='# a plugin of yours: a [<group>.<name>] table, its files and any of tool, wire, home, dialect\n'

# a table of its own, its keys in the tree's order whatever order they were
# typed in, the file made with a comment line when there is none
# shellcheck disable=SC2016,SC2088 # the home holds its $ and ~ unexpanded
function test_add_plugin_writes_a_carry_line() {
  local cfg out
  cfg="$(_hi_plugins_cfg add)"
  out="$(_hi_plugins_run "$cfg" --add-plugin cli task taskrc 'home=$TASKRC : ~/.taskrc' wire=env:TASKRC)" || return 1
  [[ "$out" == *' + [cli.task]'*'wire = "env:TASKRC"'*'home = "$TASKRC : ~/.taskrc"'*'files = "taskrc"'* ]] || _hi_because "said: $out" || return 1
  _hi_plugins_run "$cfg" --add-plugin cli btool b.rc b.d/ tool=- 'wire=flag:btool -C' >/dev/null || return 1
  _hi_plugins_run "$cfg" --add-plugin mine c c.rc home=/etc/c dialect=sh tool=- >/dev/null || return 1
  _hi_plugins_is "$cfg/plugins" "$_HI_PLUGINS_HEAD"'\n[cli.task]\nwire = "env:TASKRC"\nhome = "$TASKRC : ~/.taskrc"\nfiles = "taskrc"\n\n[cli.btool]\ntool = "-"\nwire = "flag:btool -C"\nfiles = "b.rc b.d/"\n\n[mine.c]\ntool = "-"\nhome = "/etc/c"\ndialect = "sh"\nfiles = "c.rc"\n'
}

# a table with an init needs no file; its keys lead the table in the tree's
# order, and an init the shell would read as more than words is refused
function test_add_plugin_writes_a_hook_table() {
  local cfg out
  cfg="$(_hi_plugins_cfg add-hook)"
  out="$(_hi_plugins_run "$cfg" --add-plugin hooks fnm default=off 'init=fnm env --use-on-cd --shell {shell}')" || return 1
  [[ "$out" == *' + [hooks.fnm]'*'init = "fnm env --use-on-cd --shell {shell}"'*'default = "off"'* ]] || _hi_because "said: $out" || return 1
  _hi_plugins_run "$cfg" --add-plugin prompt fancy 'init=fancy init {shell}' prompt=yes fancy.toml wire=env:FANCY_CONFIG >/dev/null || return 1
  _hi_plugins_is "$cfg/plugins" "$_HI_PLUGINS_HEAD"'\n[hooks.fnm]\ninit = "fnm env --use-on-cd --shell {shell}"\ndefault = "off"\n\n[prompt.fancy]\ninit = "fancy init {shell}"\nprompt = "yes"\nwire = "env:FANCY_CONFIG"\nfiles = "fancy.toml"\n' || return 1
  out="$(_hi_plugins_run "$cfg" --add-plugin hooks bad 'init=bad init {shell}; touch x')" && _hi_because "took: $out" && return 1
  [[ "$out" == *"init is a command and its words"* ]] || _hi_because "said: $out" || return 1
  out="$(_hi_plugins_run "$cfg" --add-plugin hooks nofile tool=-)" && _hi_because "took: $out" && return 1
  [[ "$out" == *"needs a file for nofile to carry, an init=, or an env="* ]] || _hi_because "said: $out"
}

# a file whose last line was never ended gets the new table on lines of its
# own, a blank one above it
function test_add_plugin_starts_its_own_line() {
  local cfg
  cfg="$(_hi_plugins_cfg add-unended)"
  mkdir -p "$cfg"
  printf '[mine.a]\ntool = "-"\nfiles = "a.rc"' >"$cfg/plugins"
  _hi_plugins_run "$cfg" --add-plugin mine b b.rc tool=- >/dev/null || return 1
  _hi_plugins_is "$cfg/plugins" '[mine.a]\ntool = "-"\nfiles = "a.rc"\n\n[mine.b]\ntool = "-"\nfiles = "b.rc"\n'
}

# a table hi's own reader would turn down is never written, and says why
# shellcheck disable=SC2088 # the ~ is the file's to read, not the shell's
function test_add_plugin_refuses_a_line_hi_cannot_read() {
  _hi_plugins_refused "$(_hi_plugins_cfg add-r1)" "'colors' is a member already" --add-plugin cli x colors tool=- &&
    _hi_plugins_refused "$(_hi_plugins_cfg add-r8)" "'vim/vimrc' is a member already" --add-plugin cli x vim/vimrc tool=- &&
    _hi_plugins_refused "$(_hi_plugins_cfg add-r2)" "'B' is not env:, envdir:, flag:, flagdir:, xdg:, or -" --add-plugin cli x x.rc tool=- 'wire=env:A;B' &&
    _hi_plugins_refused "$(_hi_plugins_cfg add-r6)" "'9x' is no list of variable names" --add-plugin cli x x.rc tool=- wire=env:9x &&
    _hi_plugins_refused "$(_hi_plugins_cfg add-r3)" "is no <name>, <dir>/<name>, or <dir>/" --add-plugin cli x ../x tool=- &&
    _hi_plugins_refused "$(_hi_plugins_cfg add-r4)" "'a;b' is no list of commands, or -" --add-plugin cli x x.rc 'tool=a;b' &&
    _hi_plugins_refused "$(_hi_plugins_cfg add-r7)" "has a dialect, 'y', that hi does not read" --add-plugin cli x x.rc tool=- dialect=y &&
    _hi_plugins_refused "$(_hi_plugins_cfg add-r9)" "has a home, '@_hi_posh_home', that is no list of paths" --add-plugin cli x x.rc tool=- home=@_hi_posh_home &&
    _hi_plugins_refused "$(_hi_plugins_cfg add-r5)" "cannot hold a quote or a backslash" --add-plugin cli x x.rc tool=- 'home=~/"x"'
}

# a plugin the file has already is replaced where it stands, its group the
# one named now; one of the tree's is replaced by a table of the file's own
# shellcheck disable=SC2088 # the ~ is the file's to read, not the shell's
function test_add_plugin_refuses_a_member_the_carry_has() {
  local cfg out
  cfg="$(_hi_plugins_cfg add-twice)"
  _hi_plugins_run "$cfg" --add-plugin cli task taskrc tool=- wire=env:TASKRC 'home=~/.taskrc' >/dev/null || return 1
  _hi_plugins_run "$cfg" --add-plugin cli other other.rc tool=- >/dev/null || return 1
  out="$(_hi_plugins_run "$cfg" --add-plugin cli task taskrc tool=- wire=env:TASKRC 'home=~/.taskrc')" || return 1
  [[ "$out" == *"that plugin is there already"* ]] || _hi_because "said: $out" || return 1
  out="$(_hi_plugins_run "$cfg" --add-plugin mine task taskrc tool=- wire=env:OTHER 'home=~/.other')" || return 1
  [[ "$out" == *" ~ [mine.task] (replacing [cli.task])"* ]] || _hi_because "said: $out" || return 1
  _hi_plugins_is "$cfg/plugins" "$_HI_PLUGINS_HEAD"'\n[mine.task]\ntool = "-"\nwire = "env:OTHER"\nhome = "~/.other"\nfiles = "taskrc"\n\n[cli.other]\ntool = "-"\nfiles = "other.rc"\n' || return 1
  out="$(_hi_plugins_run "$cfg" --add-plugin editors vim vim/vimrc 'home=~/.vimrc')" || return 1
  [[ "$out" == *' + [editors.vim]'* ]] || _hi_because "said: $out" || return 1
  out="$(_hi_strip_ansi "$(_hi_plugins_run "$cfg" --plugins)")" || return 1
  [[ "$out" == *" editors "*" vim/"* ]] && [ "$(printf '%s\n' "$out" | grep -c ' vim/')" = 1 ] ||
    _hi_because "listed: $out"
}

# shellcheck disable=SC2088 # the ~ is the file's to read, not the shell's
function test_add_plugin_dry_run_writes_nothing() {
  local cfg out
  cfg="$(_hi_plugins_cfg add-dry)"
  out="$(_hi_plugins_run "$cfg" --add-plugin cli task taskrc tool=- wire=env:TASKRC 'home=~/.taskrc' -n)" || return 1
  [[ "$out" == *"dry run"*"write $cfg/plugins"* ]] && [ ! -e "$cfg" ]
}

# the plugin's table goes, with the tables of its files and the comment
# right above it; its neighbours and their comments stay, one blank line
# between them
function test_remove_plugin_takes_the_line_out() {
  local cfg out
  cfg="$(_hi_plugins_cfg remove)"
  mkdir -p "$cfg"
  printf '# mine\n[cli.a]\ntool = "-"\nfiles = "a.rc"\n\n# about task\n[cli.task]\nfiles = "taskrc t.d/"\n[cli.task."t.d/"]\nwire = "-"\n\n# kept\n[cli.b]\ntool = "-"\nfiles = "b.rc"\n' >"$cfg/plugins"
  out="$(_hi_plugins_run "$cfg" --remove-plugin task)" || return 1
  [[ "$out" == *" - [cli.task]"* ]] || _hi_because "said: $out" || return 1
  _hi_plugins_is "$cfg/plugins" '# mine\n[cli.a]\ntool = "-"\nfiles = "a.rc"\n\n# kept\n[cli.b]\ntool = "-"\nfiles = "b.rc"\n' || return 1
  _hi_plugins_run "$cfg" --remove-plugin b >/dev/null || return 1
  _hi_plugins_is "$cfg/plugins" '# mine\n[cli.a]\ntool = "-"\nfiles = "a.rc"\n'
}

# one of hi's own has no table of the user's: the answer is --plugin-off. A
# name nothing has is a no-op.
function test_remove_plugin_knows_hi_s_own_from_nothing() {
  local cfg out rc=0
  cfg="$(_hi_plugins_cfg remove-own)"
  out="$(_hi_plugins_run "$cfg" --remove-plugin vim)" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"hi --plugin-off vim switches it off"* ]] || _hi_because "rc $rc: $out" || return 1
  out="$(_hi_plugins_run "$cfg" --remove-plugin nosuch)" || return 1
  [[ "$out" == *"has no plugin nosuch"* ]] && [ ! -e "$cfg" ]
}

# ---------------------------------------------------------------------------
# --plugins
# ---------------------------------------------------------------------------

# a row a member: what rides and from where, what is off and by what, and
# a row of the user's own beside hi's
function test_plugins_lists_what_rides_and_what_is_off() {
  local cfg out
  cfg="$(_hi_plugins_cfg list)"
  mkdir -p "$cfg" "$cfg.home"
  mkdir -p "$cfg/bat" "$cfg/nano"
  printf 'x\n' >"$cfg/bat/config"
  printf 'x\n' >"$cfg/nano/nanorc"
  printf 'x\n' >"$cfg.home/.taskrc"
  printf '[mine.task]\ntool = "-"\nbad line\nwire = "env:TASKRC"\nhome = "~/.taskrc"\nfiles = "taskrc"\n' >"$cfg/plugins"
  printf '#!/bin/sh\nexport _HI_PLUGINS_OFF="tmux nano"\n' >"$cfg/settings.sh"
  out="$(_hi_strip_ansi "$(_hi_plugins_run "$cfg" --plugins)")" || return 1
  [[ "$out" == *" cli "*"bat/config (bat)"*"used $cfg/bat/config"* ]] || _hi_because "bat: $out" || return 1
  [[ "$out" == *" editors "*"nano/nanorc (nano)"*"not sent: switched off (_HI_PLUGINS_OFF)"* ]] || _hi_because "nano: $out" || return 1
  [[ "$out" == *" mux "*"tmux/tmux.conf (tmux)"*"switched off (_HI_PLUGINS_OFF)"* ]] || _hi_because "tmux: $out" || return 1
  [[ "$out" == *" mine "*"taskrc (task)"*"used ~/.taskrc"* ]] || _hi_because "taskrc: $out" || return 1
  [[ "$out" == *" ignored "*"$cfg/plugins line 3"*"not a line of a plugin"* && "$out" != *" colors "* ]] || _hi_because "the rest: $out"
}

# the hooks section: a row a hook, saying whether a target gets it - the
# tool missing here, the plugin off (by default, or by the list), or on
function test_plugins_lists_the_hooks() {
  local cfg out stubs
  cfg="$(_hi_plugins_cfg hooks)"
  mkdir -p "$cfg"
  {
    printf '[mine.hi-hook-on]\ninit = "hi-hook-on init {shell}"\n'
    printf '[mine.hi-hook-dflt]\ninit = "hi-hook-dflt init {shell}"\ndefault = "off"\n'
    printf '[mine.hi-hook-gone]\ninit = "hi-hook-gone init {shell}"\n'
    printf '[mine.hi-hook-listed]\ninit = "hi-hook-listed init {shell}"\n'
  } >"$cfg/plugins"
  printf '#!/bin/sh\nexport _HI_PLUGINS_OFF="hi-hook-listed"\n' >"$cfg/settings.sh"
  stubs="$(_hi_stub_tools hi-hook-on hi-hook-dflt hi-hook-listed)"
  out="$(_hi_strip_ansi "$(PATH="$stubs:$PATH" _hi_plugins_run "$cfg" --plugins)")" || return 1
  [[ "$out" == *" hooks "*"hi-hook-on"*"hi-hook-on init {shell} - runs on a target that has it"* ]] || _hi_because "on: $out" || return 1
  [[ "$out" == *"hi-hook-dflt"*"- off by default (hi --plugin-on hi-hook-dflt)"* ]] || _hi_because "default off: $out" || return 1
  [[ "$out" == *"hi-hook-gone"*"- not installed here, so not sent"* ]] || _hi_because "gone: $out" || return 1
  [[ "$out" == *"hi-hook-listed"*"- switched off (_HI_PLUGINS_OFF)"* ]] || _hi_because "listed: $out" || return 1
  [[ "$out" == *"zoxide"*"zoxide init {shell} - "* ]] || _hi_because "the tree's: $out"
}

# a row of the tree's own config/plugins that hi turns down is named under
# the tree, not the overlay
function test_plugins_names_a_bad_tree_row_under_the_tree() {
  local tree cfg out n
  tree="$(_hi_scratch_tree plugins-badtree common config load.sh hi.sh link:scripts)"
  printf 'bad line\n' >>"$tree/say-hi/config/plugins"
  n=$(($(wc -l <"$tree/say-hi/config/plugins")))
  cfg="$(_hi_plugins_cfg badtree)"
  out="$(_hi_strip_ansi "$(_HI_PLUGINS_TREE="$tree" _hi_plugins_run "$cfg" --plugins)")" || return 1
  [[ "$out" == *" ignored "*"$tree/say-hi/config/plugins line $n"*"not a line of a plugin"* && "$out" != *"$cfg/"* ]] ||
    _hi_because "listed: $out"
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
  _hi_check "...one file of a directory member is a word too" test_plugin_off_takes_one_file_of_a_directory
  _hi_check "...and keeps every other line of it" test_plugin_off_keeps_the_other_settings
  _hi_check "...a word that is off already writes nothing" test_plugin_off_twice_writes_nothing
  _hi_check "--plugin-on takes a word back, and the line with the last" test_plugin_on_takes_a_word_back
  _hi_check "...and says so of a word that is on" test_plugin_on_says_a_word_is_on
  _hi_check "...a plugin off by default moves through _HI_PLUGINS_ON" test_plugin_on_moves_a_default_off_plugin
  _hi_check "--dry-run names the write and writes nothing" test_plugin_off_dry_run_writes_nothing

  _hi_h2 "Testing: --add-plugin and --remove-plugin"
  _hi_check "--add-plugin writes a table of its own" test_add_plugin_writes_a_carry_line
  _hi_check "...a hook's table, with an init and no file" test_add_plugin_writes_a_hook_table
  _hi_check "...on lines of its own after an unended one" test_add_plugin_starts_its_own_line
  _hi_check "...never one hi could not read" test_add_plugin_refuses_a_line_hi_cannot_read
  _hi_check "...a plugin the file has is replaced, and one of the tree's" test_add_plugin_refuses_a_member_the_carry_has
  _hi_check "...and nothing under --dry-run" test_add_plugin_dry_run_writes_nothing
  _hi_check "--remove-plugin takes the plugin's tables out" test_remove_plugin_takes_the_line_out
  _hi_check "...and tells hi's own from a name nothing has" test_remove_plugin_knows_hi_s_own_from_nothing

  _hi_h2 "Testing: --plugins"
  _hi_check "Lists what rides and what is off" test_plugins_lists_what_rides_and_what_is_off
  _hi_check "...and the hooks, with whether a target gets each" test_plugins_lists_the_hooks
  _hi_check "...and names a bad row of the tree's under the tree" test_plugins_names_a_bad_tree_row_under_the_tree

  _hi_suite_end "scripts/plugins.sh"
}

run_plugins_tests
