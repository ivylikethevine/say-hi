#!/usr/bin/env bash
# Unit tests for scripts/plugins.sh - `hi --plugins`, which lists what rides
# to a target; `hi --disable-plugin` and `--enable-plugin`, which keep
# $_HI_PLUGINS_OFF in settings.sh.
#
# Driven through `hi.sh --<flag>` rather than by calling the script directly,
# so the common/flags rows and _hi_dispatch_subcommand are covered with it,
# as set_color_test.sh drives --add-color. Each case gets its own
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

# _hi_plugins_cfg <name> - a fresh overlay directory's path; nothing is made
function _hi_plugins_cfg() { printf '%s' "$_HI_WORKDIR/$1-cfg"; }

# _hi_plugins_off_line <list> - the line the list is kept on, as the wizard
# pads and tags its own
function _hi_plugins_off_line() {
  printf '%-45s %s' "export _HI_PLUGINS_OFF='$1'" "$_HI_MARKER"
}

# _hi_plugins_fresh - the lines a settings.sh the script creates opens on:
# the shebang and the block's shape line, as the wizard writes them
function _hi_plugins_fresh() {
  local n
  n="$(sed -n 's/^_HI_SETTINGS_SHAPE=//p' "$_HI_ROOT/scripts/lib.sh")"
  printf '#!/bin/sh\\n%-45s %s\\n' "# say-hi settings $n" "$_HI_MARKER"
}

# _hi_plugins_refused <config> <message> <flag> <args...> - the command
# fails, says <message>, and leaves the overlay as it was: not made
function _hi_plugins_refused() {
  local cfg="$1" msg="$2" out rc=0
  shift 2
  out="$(_hi_plugins_run "$cfg" "$@")" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"$msg"* ]] && [ ! -e "$cfg" ] || _hi_because "[$*] gave rc $rc: $out"
}

# ---------------------------------------------------------------------------
# arguments
# ---------------------------------------------------------------------------

function test_plugins_help_is_each_command_s_own() {
  local cfg out flag
  cfg="$(_hi_plugins_cfg help)"
  for flag in "--plugins:Usage: hi --plugins" "--disable-plugin:Usage: hi --disable-plugin <name>... [--dry-run]" \
    "--enable-plugin:Usage: hi --enable-plugin <name>... [--dry-run]"; do
    out="$(_hi_plugins_run "$cfg" "${flag%%:*}" --help)" || _hi_why cfg flag || return 1
    [[ "$out" == "${flag#*:}"* ]] || _hi_because "${flag%%:*} --help: $out" || return 1
  done
  [ ! -e "$cfg" ] || _hi_why cfg
}

function test_plugins_refuse_what_they_cannot_take() {
  { _hi_plugins_refused "$(_hi_plugins_cfg r1)" "takes no argument" --plugins vim &&
    _hi_plugins_refused "$(_hi_plugins_cfg r2)" "needs a plugin or a member" --disable-plugin &&
    _hi_plugins_refused "$(_hi_plugins_cfg r3)" "not a plugin or a member: nosuch" --disable-plugin nosuch &&
    _hi_plugins_refused "$(_hi_plugins_cfg r4)" "not a plugin or a member: colors" --disable-plugin colors &&
    _hi_plugins_refused "$(_hi_plugins_cfg r4g)" "not a plugin or a member: editors" --disable-plugin editors &&
    _hi_plugins_refused "$(_hi_plugins_cfg r4h)" "not a plugin or a member: hooks" --enable-plugin hooks &&
    _hi_plugins_refused "$(_hi_plugins_cfg r5)" "unknown option --force" --enable-plugin vim --force; } || _hi_why
}

# ---------------------------------------------------------------------------
# --disable-plugin / --enable-plugin
# ---------------------------------------------------------------------------

# the list is one line of settings.sh, made with its shebang when there is
# no file, a plugin and a member alike
function test_plugin_off_writes_the_list() {
  local cfg out
  cfg="$(_hi_plugins_cfg off)"
  out="$(_hi_plugins_run "$cfg" --disable-plugin lazygit vim tmux/tmux.conf)" || _hi_why cfg || return 1
  [[ "$out" == *" - lazygit"* && "$out" == *" - vim"* && "$out" == *"settings.sh updated"* ]] || _hi_because "said: $out" || return 1
  _hi_file_is "$cfg/settings.sh" "$(_hi_plugins_fresh)$(_hi_plugins_off_line 'lazygit vim tmux/tmux.conf')\n" || _hi_why cfg
}

# one file of a directory member is a word too, there or not; a file of
# hi's own directory, a path further down, and a backup's name are not
function test_plugin_off_takes_one_file_of_a_directory() {
  local cfg out
  cfg="$(_hi_plugins_cfg off-file)"
  out="$(_hi_plugins_run "$cfg" --disable-plugin extensions/10-kube zellij/layouts/work.kdl)" || _hi_why cfg || return 1
  [[ "$out" == *" - extensions/10-kube"* ]] || _hi_because "said: $out" || return 1
  _hi_file_is "$cfg/settings.sh" "$(_hi_plugins_fresh)$(_hi_plugins_off_line 'extensions/10-kube zellij/layouts/work.kdl')\n" || _hi_why cfg || return 1
  _hi_plugins_run "$cfg" --enable-plugin extensions/10-kube zellij/layouts/work.kdl >/dev/null || _hi_why cfg || return 1
  _hi_file_is "$cfg/settings.sh" "$(_hi_plugins_fresh)" || _hi_why cfg || return 1
  { _hi_plugins_refused "$(_hi_plugins_cfg off-file-r1)" "not a plugin or a member: header/sky" --disable-plugin header/sky &&
    _hi_plugins_refused "$(_hi_plugins_cfg off-file-r2)" "not a plugin or a member: extensions/sub/x" --disable-plugin extensions/sub/x &&
    _hi_plugins_refused "$(_hi_plugins_cfg off-file-r3)" "not a plugin or a member: extensions/x.bak" --disable-plugin extensions/x.bak &&
    _hi_plugins_refused "$(_hi_plugins_cfg off-file-r4)" "not a plugin or a member: vim/other" --disable-plugin vim/other; } || _hi_why
}

# every other line of a settings.sh stays where it was, and a second list
# line never joins the first
function test_plugin_off_keeps_the_other_settings() {
  local cfg
  cfg="$(_hi_plugins_cfg off-keeps)"
  mkdir -p "$cfg"
  printf '#!/bin/sh\nexport _HI_MAX_WIDTH=72\nexport _HI_PLUGINS_OFF="bat, rg"\nexport _HI_KEEP=1\n' >"$cfg/settings.sh"
  _hi_plugins_run "$cfg" --disable-plugin fzf >/dev/null || _hi_why cfg || return 1
  _hi_file_is "$cfg/settings.sh" "#!/bin/sh\nexport _HI_MAX_WIDTH=72\nexport _HI_KEEP=1\n$(_hi_plugins_off_line 'bat rg fzf')\n" || _hi_why cfg
}

function test_plugin_off_twice_writes_nothing() {
  local cfg out
  cfg="$(_hi_plugins_cfg off-twice)"
  _hi_plugins_run "$cfg" --disable-plugin bat >/dev/null || _hi_why cfg || return 1
  out="$(_hi_plugins_run "$cfg" --disable-plugin bat)" || _hi_why cfg || return 1
  [[ "$out" == *"bat is off already"* && "$out" != *updated* ]] || _hi_because "said: $out" || return 1
  _hi_file_is "$cfg/settings.sh" "$(_hi_plugins_fresh)$(_hi_plugins_off_line 'bat')\n" || _hi_why cfg
}

# switching the last one back on takes the line with it
function test_plugin_on_takes_a_word_back() {
  local cfg out
  cfg="$(_hi_plugins_cfg on)"
  _hi_plugins_run "$cfg" --disable-plugin bat vim >/dev/null || _hi_why cfg || return 1
  out="$(_hi_plugins_run "$cfg" --enable-plugin vim)" || _hi_why cfg || return 1
  [[ "$out" == *" + vim"* ]] || _hi_because "said: $out" || return 1
  _hi_file_is "$cfg/settings.sh" "$(_hi_plugins_fresh)$(_hi_plugins_off_line 'bat')\n" || _hi_why cfg || return 1
  _hi_plugins_run "$cfg" --enable-plugin bat >/dev/null || _hi_why cfg || return 1
  _hi_file_is "$cfg/settings.sh" "$(_hi_plugins_fresh)" || _hi_why cfg
}

# a word that is on says so, and nothing is written
function test_plugin_on_says_a_word_is_on() {
  local cfg out
  cfg="$(_hi_plugins_cfg on-already)"
  mkdir -p "$cfg"
  printf '#!/bin/sh\n' >"$cfg/settings.sh"
  out="$(_hi_plugins_run "$cfg" --enable-plugin bat)" || _hi_why cfg || return 1
  [[ "$out" == *"bat is not in the list"* ]] || _hi_because "said: $out" || return 1
  _hi_file_is "$cfg/settings.sh" "#!/bin/sh\n" || _hi_why cfg
}

# a plugin off by default moves through _HI_PLUGINS_ON: on adds it, off
# takes it out, and neither touches _HI_PLUGINS_OFF
function test_plugin_on_moves_a_default_off_plugin() {
  local cfg out
  cfg="$(_hi_plugins_cfg on-default)"
  out="$(_hi_plugins_run "$cfg" --enable-plugin zoxide)" || _hi_why cfg || return 1
  [[ "$out" == *" + zoxide"* ]] || _hi_because "said: $out" || return 1
  _hi_file_is "$cfg/settings.sh" "$(_hi_plugins_fresh)$(printf '%-45s %s' "export _HI_PLUGINS_ON='zoxide'" "$_HI_MARKER")\n" || _hi_why cfg _HI_MARKER || return 1
  out="$(_hi_plugins_run "$cfg" --enable-plugin zoxide)" || _hi_why cfg || return 1
  [[ "$out" == *"zoxide is on already"* ]] || _hi_because "said: $out" || return 1
  _hi_plugins_run "$cfg" --enable-plugin mise >/dev/null && _hi_plugins_run "$cfg" --disable-plugin zoxide >/dev/null || _hi_why cfg || return 1
  _hi_file_is "$cfg/settings.sh" "$(_hi_plugins_fresh)$(printf '%-45s %s' "export _HI_PLUGINS_ON='mise'" "$_HI_MARKER")\n" || _hi_why cfg _HI_MARKER || return 1
  out="$(_hi_plugins_run "$cfg" --disable-plugin mise)" || _hi_why cfg || return 1
  [[ "$out" == *" - mise"* ]] || _hi_because "said: $out" || return 1
  _hi_file_is "$cfg/settings.sh" "$(_hi_plugins_fresh)" || _hi_why cfg || return 1
  out="$(_hi_plugins_run "$cfg" --disable-plugin atuin)" || _hi_why cfg || return 1
  [[ "$out" == *"atuin is off already (off by default)"* ]] || _hi_because "said: $out"
}

function test_plugin_off_dry_run_writes_nothing() {
  local cfg out
  cfg="$(_hi_plugins_cfg off-dry)"
  out="$(_hi_plugins_run "$cfg" --disable-plugin bat --dry-run)" || _hi_why cfg || return 1
  [[ "$out" == *"dry run"*"_HI_PLUGINS_OFF='bat'"* ]] && [ ! -e "$cfg" ] || _hi_why out cfg
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
  out="$(_hi_strip_ansi "$(_hi_plugins_run "$cfg" --plugins)")" || _hi_why cfg || return 1
  [[ "$out" == *" cli "*"bat/config (bat)"*"used $cfg/bat/config"* ]] || _hi_because "bat: $out" || return 1
  [[ "$out" == *" editors "*"nano/nanorc (nano)"*"not sent: switched off (_HI_PLUGINS_OFF)"* ]] || _hi_because "nano: $out" || return 1
  [[ "$out" == *" mux "*"tmux/tmux.conf (tmux)"*"switched off (_HI_PLUGINS_OFF)"* ]] || _hi_because "tmux: $out" || return 1
  [[ "$out" == *" mine "*"taskrc (task)"*"used ~/.taskrc"* ]] || _hi_because "taskrc: $out" || return 1
  [[ "$out" == *" ignored "*"$cfg/plugins line 3"*"not a line of a plugin"* && "$out" != *" colors "* ]] || _hi_because "the rest: $out"
}

# --text: the same rows as `group / member: text`, a riding row with (ok),
# the ignored line by its file and number, and no rule, bar, or escape
function test_plugins_text_lists_a_row_a_line() {
  local cfg out rules
  cfg="$(_hi_plugins_cfg text)"
  mkdir -p "$cfg/bat" "$cfg.home"
  printf 'x\n' >"$cfg/bat/config"
  printf '[mine.task]\nbad line\nfiles = "taskrc"\n' >"$cfg/plugins"
  out="$(_hi_plugins_run "$cfg" --plugins --text)" || _hi_why cfg || return 1
  rules="$(printf '%s\n' "$out" | grep -c -E $'^[ ]*[+|]|^[ ]*-{3}|\e' || true)"
  [[ "$out" == *"cli / bat/config (bat): used $cfg/bat/config (ok)"* && "$out" == *"ignored / $cfg/plugins line 2: not a line of a plugin"* ]] &&
    [ "$rules" = 0 ] || _hi_why rules out || return 1
  out="$(_hi_plugins_run "$cfg" --disable-plugin bat --text)" && _hi_because "took --text: $out" && return 1
  [[ "$out" == *"--text is hi --plugins' switch"* ]] || _hi_why out
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
  out="$(_hi_strip_ansi "$(PATH="$stubs:$PATH" _hi_plugins_run "$cfg" --plugins)")" || _hi_why stubs cfg || return 1
  [[ "$out" == *" hooks "*"hi-hook-on"*"hi-hook-on init {shell} - runs on a target that has it"* ]] || _hi_because "on: $out" || return 1
  [[ "$out" == *"hi-hook-dflt"*"- off by default (hi --enable-plugin hi-hook-dflt)"* ]] || _hi_because "default off: $out" || return 1
  [[ "$out" == *"hi-hook-gone"*"- not installed here, so not sent"* ]] || _hi_because "gone: $out" || return 1
  [[ "$out" == *"hi-hook-listed"*"- switched off (_HI_PLUGINS_OFF)"* ]] || _hi_because "listed: $out" || return 1
  [[ "$out" == *"zoxide"*"zoxide init {shell} - "* ]] || _hi_because "the tree's: $out"
}

# ...and a hook whose init draws the prompt says so
function test_plugins_says_a_hook_draws_the_prompt() {
  local cfg out stubs
  cfg="$(_hi_plugins_cfg prompthook)"
  mkdir -p "$cfg"
  printf '[mine.hi-hook-prompt]\ninit = "hi-hook-prompt init {shell}"\nprompt = "yes"\n' >"$cfg/plugins"
  stubs="$(_hi_stub_tools hi-hook-prompt)"
  out="$(_hi_strip_ansi "$(PATH="$stubs:$PATH" _hi_plugins_run "$cfg" --plugins)")" || _hi_why stubs cfg || return 1
  [[ "$out" == *"hi-hook-prompt init {shell} - runs on a target that has it, and draws the prompt"* ]] || _hi_because "listed: $out"
}

# _hi_plugins_row_has <report> <label> <text> - one row holds both, in either
# cell: rows sharing a text fold into one, the text as its label
function _hi_plugins_row_has() {
  grep -F -- "$2" <<<"$1" | grep -qF -- "$3"
}

# the variables section: a row a variable an `env` names, saying whether a
# target gets its value - unset here, its plugin off (by the list, or by
# default), a value no line can hold, or riding
function test_plugins_lists_the_variables() {
  local cfg out
  cfg="$(_hi_plugins_cfg vars)"
  mkdir -p "$cfg"
  {
    printf '[mine.hi-env-on]\ntool = "-"\nenv = "HI_ENVT_SET HI_ENVT_UNSET HI_ENVT_QUOTED"\n'
    printf '[mine.hi-env-listed]\ntool = "-"\nenv = "HI_ENVT_LISTED"\n'
  } >"$cfg/plugins"
  printf '#!/bin/sh\nexport _HI_PLUGINS_OFF="hi-env-listed"\n' >"$cfg/settings.sh"
  out="$(_hi_strip_ansi "$(HI_ENVT_SET=1 HI_ENVT_QUOTED="it's" HI_ENVT_LISTED=1 LESS=-R _hi_plugins_run "$cfg" --plugins)")" ||
    _hi_why cfg || return 1
  [[ "$out" == *" variables "* ]] || _hi_because "no section: $out" || return 1
  _hi_plugins_row_has "$out" "HI_ENVT_SET (hi-env-on)" "its value here is exported on a target" || _hi_because "set: $out" || return 1
  _hi_plugins_row_has "$out" "HI_ENVT_UNSET (hi-env-on)" "not set here, so not sent" || _hi_because "unset: $out" || return 1
  _hi_plugins_row_has "$out" "HI_ENVT_QUOTED (hi-env-on)" "its value holds a quote, a backslash, or a line break - not sent" ||
    _hi_because "quoted: $out" || return 1
  _hi_plugins_row_has "$out" "HI_ENVT_LISTED (hi-env-listed)" "switched off (_HI_PLUGINS_OFF)" || _hi_because "listed: $out" || return 1
  _hi_plugins_row_has "$out" "LESS (env)" "off by default (hi --enable-plugin env)" || _hi_because "default off: $out"
}

# the allowed section: a private line of git's config that rides under a
# hi-allow is named, by its member and line
function test_plugins_lists_what_rides_under_a_hi_allow() {
  local cfg out
  cfg="$(_hi_plugins_cfg allowed)"
  mkdir -p "$cfg/git"
  printf '[core]\n# hi-allow\nsshCommand = ssh -o Compression=yes\n' >"$cfg/git/config"
  out="$(_hi_strip_ansi "$(_hi_plugins_run "$cfg" --plugins)")" || _hi_why cfg || return 1
  [[ "$out" != *" allowed "* ]] || _hi_because "git is off, and its line was listed: $out" || return 1
  printf '#!/bin/sh\nexport _HI_PLUGINS_ON="git"\n' >"$cfg/settings.sh"
  out="$(_hi_strip_ansi "$(_hi_plugins_run "$cfg" --plugins)")" || _hi_why cfg || return 1
  [[ "$out" == *" allowed "*"git/config:3"*"rides under its hi-allow: sshCommand = ssh -o Compression=yes"* ]] ||
    _hi_because "listed: $out"
}

# a row of the tree's own config/plugins that hi turns down is named under
# the tree, not the overlay
function test_plugins_names_a_bad_tree_row_under_the_tree() {
  local tree cfg out n
  tree="$(_hi_scratch_tree plugins-badtree common config load.sh hi.sh link:scripts)"
  printf 'bad line\n' >>"$tree/say-hi/config/plugins"
  n=$(($(wc -l <"$tree/say-hi/config/plugins")))
  cfg="$(_hi_plugins_cfg badtree)"
  out="$(_hi_strip_ansi "$(_HI_PLUGINS_TREE="$tree" _hi_plugins_run "$cfg" --plugins)")" || _hi_why tree cfg || return 1
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

  _hi_h2 "Testing: --disable-plugin and --enable-plugin"
  _hi_check "--disable-plugin writes the list to settings.sh" test_plugin_off_writes_the_list
  _hi_check "...one file of a directory member is a word too" test_plugin_off_takes_one_file_of_a_directory
  _hi_check "...and keeps every other line of it" test_plugin_off_keeps_the_other_settings
  _hi_check "...a word that is off already writes nothing" test_plugin_off_twice_writes_nothing
  _hi_check "--enable-plugin takes a word back, and the line with the last" test_plugin_on_takes_a_word_back
  _hi_check "...and says so of a word that is on" test_plugin_on_says_a_word_is_on
  _hi_check "...a plugin off by default moves through _HI_PLUGINS_ON" test_plugin_on_moves_a_default_off_plugin
  _hi_check "--dry-run names the write and writes nothing" test_plugin_off_dry_run_writes_nothing

  _hi_h2 "Testing: --plugins"
  _hi_check "Lists what rides and what is off" test_plugins_lists_what_rides_and_what_is_off
  _hi_check "...and under --text one row a line, no box, no color" test_plugins_text_lists_a_row_a_line
  _hi_check "...and the hooks, with whether a target gets each" test_plugins_lists_the_hooks
  _hi_check "...a hook that draws the prompt says so" test_plugins_says_a_hook_draws_the_prompt
  _hi_check "...and the variables, with whether a target gets each" test_plugins_lists_the_variables
  _hi_check "...and a private line riding under a hi-allow" test_plugins_lists_what_rides_under_a_hi_allow
  _hi_check "...and names a bad row of the tree's under the tree" test_plugins_names_a_bad_tree_row_under_the_tree

  _hi_suite_end "scripts/plugins.sh"
}

run_plugins_tests
