#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Unit tests for the config overlay stream hi.sh sends beside the payload: what is a
# member, how a member is wired, and what the plugins rows carry.
# A part of payload_test.sh, a suite of its own so the Windows shards split
# them. The preamble's source line is payload_test.sh's - it sources the
# harness and hi.sh, and holds the helpers the parts share (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329,SC2317,SC2016
set -euo pipefail

_HI_PAYLOAD_PART=overlay
# shellcheck source=./payload_test.sh
source "${BASH_SOURCE[0]%/*}/payload_test.sh"

# The three per-shell overrides, which take the shell file's own basename so a
# user reading common/bash.sh knows what ~/.config/say-hi/bash.sh extends.
function test_overlay_tar_carries_shell_files() {
  local dir
  dir="$(_hi_overlay_fixture withshells bashrc zshrc config.fish)"
  [ "$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf - | sort | tr '\n' ' ')" = "bashrc config.fish zshrc " ]
}

#
# The overlay is a plain directory of plain files, which is the whole
# integration story for chezmoi, yadm, GNU Stow, and bare-repo setups
# (docs/SETTINGS.md says so). Two properties make that claim true rather
# than merely hopeful, and neither is obvious from reading _hi_overlay_tar.

# Stow does not copy, it symlinks - so a Stow user's overlay is a directory of
# links into their dotfiles repo. `_hi_tar_gz -h` is what dereferences them;
# without it the target would unpack dangling links pointing at a dotfiles path
# that does not exist there, and the session would silently fall back to
# defaults. Both shapes Stow produces are covered: a symlink per file, and the
# whole config directory as one link.
function test_overlay_dereferences_symlinks() {
  local real="$_HI_WORKDIR/stow-src" perfile="$_HI_WORKDIR/stow-perfile" whole="$_HI_WORKDIR/stow-whole"
  local shape dir out
  mkdir -p "$real" "$perfile"
  printf 'export _HI_MAX_WIDTH=72\n' >"$real/settings.sh"
  ln -sf "$real/settings.sh" "$perfile/settings.sh"
  ln -sfn "$real" "$whole"
  for shape in "$perfile" "$whole"; do
    out="$(_HI_CONFIG_DIR="$shape" _hi_overlay_tar | _hi_tar_cat settings.sh 2>/dev/null)"
    [ "$out" = "export _HI_MAX_WIDTH=72" ] || {
      _hi_cecho " | ${shape##*/}: symlinked overlay did not arrive as content: [$out]" "$RED"
      return 1
    }
    # and as a regular file, not a link the target cannot resolve
    _HI_CONFIG_DIR="$shape" _hi_overlay_tar | tar tvzf - 2>/dev/null | grep -q '^-' || {
      _hi_cecho " | ${shape##*/}: overlay member is not a regular file" "$RED"
      return 1
    }
  done
  return 0
}

# $_HI_OVERLAY_FILES is an allow list, and that is what makes pointing a dotfile
# manager at this directory safe: the manager's own metadata, the .git that
# you made there, an editor swap file or a key that has no business
# leaving the machine are all in the same directory and none of them travel.
# A denylist would have to keep guessing; this asserts the allow list holds -
# inside a `.d` member too, where only the plain names ride (HI.58).
function test_overlay_sends_nothing_outside_the_roster() {
  local dir="$_HI_WORKDIR/overlay-leak" f
  mkdir -p "$dir/.git" "$dir/.chezmoitemplates" "$dir/extensions/sub"
  printf 'export _HI_MAX_WIDTH=72\n' >"$dir/settings.sh"
  for f in .git/config .chezmoiignore README.md id_rsa settings.sh.bak .settings.sh.swp \
    extensions/10-x extensions/10-x.bak extensions/.10-x.swp extensions/10-x~ extensions/sub/20-y; do
    printf 'x:3\n' >"$dir/$f"
  done
  while IFS= read -r f; do
    [ -n "$f" ] && [ "$f" != extensions/10-x ] || continue
    case " ${_HI_OVERLAY_FILES[*]} " in
    *" $f "*) continue ;;
    esac
    _hi_cecho " | the overlay stream carried $f, which is not in _HI_OVERLAY_FILES" "$RED"
    return 1
  done <<<"$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf -)"
  return 0
}

# the overlay's packages file rides as packages, comment-stripped like the
# tree's, every table and row intact - a quoted key included
function test_overlay_carries_packages_stripped() {
  local dir="$_HI_WORKDIR/packages-overlay" got="$_HI_WORKDIR/packages-sent" out
  mkdir -p "$dir" "$got"
  printf '# a note\n[core]\nbat = ["batcat"]\n\n  # indented\n[core.unwanted]\nsudo = ["doas"]\n[core.required]\n"g++" = []\n' >"$dir/packages"
  _HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar -x -z -f - -C "$got" || return 1
  [ "$(cd "$got" && printf '%s,' *)" = packages, ] || return 1
  out="$(<"$got/packages")"
  [ "$(printf '%s\n' "$out" | grep -v '^$')" = "$(printf '[core]\nbat = ["batcat"]\n[core.unwanted]\nsudo = ["doas"]\n[core.required]\n"g++" = []')" ] || {
    _hi_cecho " | packages arrived as: [$out]" "$RED"
    return 1
  }
}

# an extension rides as extensions/<name>, comment-stripped, and only the
# ones _hi_dir_member_ok admits (GLOSSARY: HI.59)
function test_overlay_carries_extensions() {
  local dir got="$_HI_WORKDIR/plugins-sent" out
  dir="$_HI_WORKDIR/plugins"
  mkdir -p "$dir/extensions" "$got"
  printf '#!/bin/sh\n# a comment\nexport _HI_SEGMENT="printf x"\n' >"$dir/extensions/10-x"
  printf 'export Y=1\n' >"$dir/extensions/10-x.orig"
  _HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar -x -z -f - -C "$got" || return 1
  [ "$(cd "$got" && printf '%s,' * */*)" = extensions,extensions/10-x, ] || return 1
  out="$(<"$got/extensions/10-x")"
  [ "$out" = '#!/bin/sh
export _HI_SEGMENT="printf x"' ] || {
    _hi_cecho " | extensions/10-x arrived as: [$out]" "$RED"
    return 1
  }
}

function test_overlay_is_empty_without_one() {
  local dir="$_HI_WORKDIR/no-overlay"
  mkdir -p "$dir"
  [ -z "$(_HI_CONFIG_DIR="$dir" _hi_overlay_files)" ] &&
    [ -z "$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar)" ]
}

function test_overlay_is_seen_when_present() {
  local dir
  dir="$(_hi_overlay_fixture some colors)"
  [ "$(_HI_CONFIG_DIR="$dir" _hi_overlay_files)" = colors ]
}

# members land at the archive's top level under their plain names, since it is
# unpacked straight into the target's config/ - a "colors" that arrived as
# "say-hi/colors" or "./config/colors" would be invisible to paths.sh
function test_overlay_tar_members_are_bare_names() {
  local dir listing
  dir="$(_hi_overlay_fixture members colors aliases.sh settings.sh)"
  listing="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf -)"
  [ "$(printf '%s\n' "$listing" | sort | paste -sd, -)" = "aliases.sh,colors,settings.sh" ]
}

# only what the user actually has - an overlay holding one file must not carry
# a placeholder for the other two, which would shadow the tree's defaults
function test_overlay_tar_carries_only_what_exists() {
  local dir
  dir="$(_hi_overlay_fixture partial colors)"
  [ "$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf -)" = "colors" ]
}

# a member a variable points its tool at rides with the line that does it:
# wiring.sh, one export per such member in the table's order, the paths left
# for the target to expand - the file for env:, the directory for envdir:
# (GLOSSARY: HI.62)
# shellcheck disable=SC2016 # the wanted lines hold $_HI_CONFIG_DIR unexpanded
function test_overlay_tar_wires_the_members_it_carries() {
  local dir d want
  dir="$(_hi_overlay_fixture wired colors inputrc bat/config eza/theme.yml oh-my-posh.toml kak/kakrc)"
  d="$(mktemp -d "$_HI_WORKDIR/wired-out.XXXXXX")" || return 1
  _HI_PROMPT_TOOL=oh-my-posh _HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar -x -z -f - -C "$d" || return 1
  want='export KAKOUNE_CONFIG_DIR="$_HI_CONFIG_DIR/kak"
export POSH_CONFIG="$_HI_CONFIG_DIR/oh-my-posh.toml" POSH_THEME="$_HI_CONFIG_DIR/oh-my-posh.toml"
export EZA_CONFIG_DIR="$_HI_CONFIG_DIR/eza"
export BAT_CONFIG_PATH="$_HI_CONFIG_DIR/bat/config"
export INPUTRC="$_HI_CONFIG_DIR/inputrc"'
  [ "$(cat "$d/wiring.sh")" = "$want" ] || _hi_because "wiring.sh: $(cat "$d/wiring.sh" 2>&1)" || return 1
  [ -f "$d/colors" ] && [ -f "$d/oh-my-posh.toml" ] || _hi_because "unpacked: $(ls "$d")"
}

# an editor's or a multiplexer's config rides with its alias: the command
# and its flags, where the target has the command, under the path load.sh
# reads for $VIMINIT.
# vim and nvim keep their state in the session tree, nvim answers to vim
# too, helix under each of its names as itself, its languages.toml through
# the xdg wire, whose alias comes last and wins, and zellij's directory is
# aliased once for all its files
# shellcheck disable=SC2016 # the wanted lines hold their $ unexpanded
function test_overlay_tar_aliases_the_editors_and_multiplexers() {
  local dir d want
  dir="$(_hi_overlay_fixture aliased vim/vimrc nvim/init.lua helix/config.toml helix/languages.toml tmux/tmux.conf)"
  mkdir -p "$dir/zellij/themes"
  printf 'x\n' >"$dir/zellij/config.kdl"
  printf 'x\n' >"$dir/zellij/themes/dark.kdl"
  d="$(mktemp -d "$_HI_WORKDIR/aliased-out.XXXXXX")" || return 1
  _HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar -x -z -f - -C "$d" || return 1
  want='export _HI_VIMRC="$_HI_CONFIG_DIR/vim/vimrc"
command -v vim >/dev/null 2>&1 && alias vim="env XDG_STATE_HOME=$_HI_HOME/vim/state XDG_DATA_HOME=$_HI_HOME/vim/data XDG_CACHE_HOME=$_HI_HOME/vim/cache vim -i NONE -u $_HI_CONFIG_DIR/vim/vimrc" || true
export _HI_NVIMRC="$_HI_CONFIG_DIR/nvim/init.lua"
command -v nvim >/dev/null 2>&1 && alias nvim="env XDG_STATE_HOME=$_HI_HOME/nvim/state XDG_DATA_HOME=$_HI_HOME/nvim/data XDG_CACHE_HOME=$_HI_HOME/nvim/cache nvim -u $_HI_CONFIG_DIR/nvim/init.lua" && alias vim="env XDG_STATE_HOME=$_HI_HOME/nvim/state XDG_DATA_HOME=$_HI_HOME/nvim/data XDG_CACHE_HOME=$_HI_HOME/nvim/cache nvim -u $_HI_CONFIG_DIR/nvim/init.lua" || true
command -v hx >/dev/null 2>&1 && alias hx="hx -c $_HI_CONFIG_DIR/helix/config.toml" || true
command -v helix >/dev/null 2>&1 && alias helix="helix -c $_HI_CONFIG_DIR/helix/config.toml" || true
command -v hx >/dev/null 2>&1 && alias hx="env XDG_CONFIG_HOME=$_HI_CONFIG_DIR hx" || true
command -v helix >/dev/null 2>&1 && alias helix="env XDG_CONFIG_HOME=$_HI_CONFIG_DIR helix" || true
command -v tmux >/dev/null 2>&1 && alias tmux="tmux -f $_HI_CONFIG_DIR/tmux/tmux.conf" || true
command -v zellij >/dev/null 2>&1 && alias zellij="zellij --config-dir $_HI_CONFIG_DIR/zellij" || true'
  [ "$(cat "$d/wiring.sh")" = "$want" ] || _hi_because "wiring.sh: $(cat "$d/wiring.sh" 2>&1)" || return 1
  [ "$(_HI_PLUGINS_OFF="tmux zellij" _HI_CONFIG_DIR="$dir" _hi_overlay_files | tr '\n' ' ')" = "vim/vimrc nvim/init.lua helix/config.toml helix/languages.toml " ] ||
    _hi_because "with the multiplexers off: $(_HI_PLUGINS_OFF="tmux zellij" _HI_CONFIG_DIR="$dir" _hi_overlay_files | tr '\n' ' ')"
}

# ...and only with them: an overlay of members hi's own code reads has no
# wiring.sh, and one written into the overlay by hand is no member
function test_overlay_tar_has_no_wiring_without_a_wired_member() {
  local dir
  dir="$(_hi_overlay_fixture unwired colors bashrc aliases.sh wiring.sh)"
  [ "$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf - | sort | paste -sd, -)" = "aliases.sh,bashrc,colors" ]
}

# a plugin of the user's own, in the overlay's plugins: a file of it rides
# from the first of its places that is there, with its tool on this machine,
# beside its wiring.sh line, and the tables themselves stay home. The two
# tools are names no runner has, one stubbed and one never: the suite's stub
# directory is on $PATH for the whole run. (GLOSSARY: HI.63)
# shellcheck disable=SC2016 # the tables and the wanted lines hold their $ unexpanded
function test_carry_row_rides_from_home_with_its_wiring() {
  local dir d h="$_HI_WORKDIR/tool-home" stubs
  dir="$(_hi_overlay_fixture carry-rides)"
  mkdir -p "$h/.config/task" "$h/with space"
  printf 'data.location=~/.task\n' >"$h/.config/task/taskrc"
  printf 'second\n' >"$h/with space/b.conf"
  {
    printf '# mine\n[mine.hi-carry-here]\nwire = "env:TASKRC"\nfiles = "taskrc"\n'
    printf 'home = "$NOWHERE/taskrc : $XDG_CONFIG_HOME/task/taskrc : ~/.taskrc"\n'
    printf '[mine.b]\ntool = "-"\nhome = "~/with space/b.conf"\nwire = "envdir:B_DIR"\nfiles = "b.conf c.toml"\n'
    printf '[mine.b."c.toml"]\nwire = "flag:ctool --config="\n'
    printf '[mine.hi-carry-absent]\nwire = "env:GONERC"\nhome = "~/with space/b.conf"\nfiles = "gone.rc"\n'
  } >"$dir/plugins"
  stubs="$(_hi_stub_tools hi-carry-here)"
  # hi's own prompt: a prompt program on this machine would add its init line
  d="$(_hi_tool_home_unpacked "$dir" PATH="$stubs:$PATH" _HI_PROMPT_TOOL=hi)" || return 1
  # gone.rc stays home: its tool is nowhere on this machine
  [ "$(find "$d" -type f | sed 's|.*/||' | sort | paste -sd, -)" = "b.conf,c.toml,taskrc,wiring.sh" ] ||
    _hi_because "carried: $(ls "$d")" || return 1
  [ "$(cat "$d/taskrc" "$d/b.conf")" = "$(printf 'data.location=~/.task\nsecond')" ] ||
    _hi_because "members: $(cat "$d/taskrc" "$d/b.conf" 2>&1)" || return 1
  [ "$(cat "$d/wiring.sh")" = 'export TASKRC="$_HI_CONFIG_DIR/taskrc"
export B_DIR="$_HI_CONFIG_DIR"
command -v ctool >/dev/null 2>&1 && alias ctool="ctool --config=$_HI_CONFIG_DIR/c.toml" || true' ] ||
    _hi_because "wiring.sh: $(cat "$d/wiring.sh" 2>&1)"
}

# the home column is data: a candidate starts at /, at ~/, or at one
# variable's name, and nothing in it runs or expands further
# shellcheck disable=SC2016 # the candidates hold their $ unexpanded
function test_carry_home_list_expands_three_starts_and_runs_nothing() {
  local h="$_HI_WORKDIR/carry-paths" got
  local -a _hi_paths=()
  mkdir -p "$h"
  HOME="$h" CARRY_DIR="$h/set" CARRY_UNSET="" \
    _hi_path_list '$CARRY_UNSET/a : $CARRY_DIR/b:~/c d/e : /abs : rel/x : ~other/y : ${HOME}/z : $9X/q : $(touch "$HOME/RAN")/x : ~/f$(touch "$HOME/RAN")'
  got="$(printf '%s\n' ${_hi_paths[@]+"${_hi_paths[@]}"})"
  [ "$got" = "$h/set/b
$h/c d/e
/abs
$h/f"'$(touch "$HOME/RAN")' ] || _hi_because "expanded to: $got" || return 1
  [ ! -e "$h/RAN" ] || _hi_because "a command in a candidate ran"
}

# paths a , apart are one place: the first whose variable is set, the rest
# never looked at, as a tool reads its default only once its variable is unset
# shellcheck disable=SC2016 # the candidates hold their $ unexpanded
function test_home_list_takes_the_first_set_of_a_place() {
  local h="$_HI_WORKDIR/carry-places" got
  local -a _hi_paths=()
  HOME="$h" CARRY_DIR="$h/set" CARRY_UNSET="" \
    _hi_path_list '$CARRY_UNSET/a , $CARRY_DIR/b , ~/c : ~/d , /e : $CARRY_UNSET/x , rel/y'
  got="$(printf '%s\n' ${_hi_paths[@]+"${_hi_paths[@]}"})"
  [ "$got" = "$h/set/b
$h/d" ] || _hi_because "expanded to: $got"
}

# the table's own home columns are that grammar and nothing past it: every
# path of every row starts at /, ~/, or a variable's name
function test_table_home_columns_are_the_grammar() {
  local row h part
  for row in "${_HI_OVERLAY_TABLE[@]}"; do
    h="${row##*|}"
    case "$h" in - | @*) continue ;; esac
    h="${h//,/:}:"
    while [ -n "$h" ]; do
      part="${h%%:*}" h="${h#*:}"
      _hi_trim part
      case "$part" in /?* | \~/?* | '$'[A-Za-z_]*) ;; *) _hi_because "${row%%|*}: [$part]" || return 1 ;; esac
      case "$part" in *[\"\'\`\{\(]*) _hi_because "${row%%|*}: [$part] would need evaluating" || return 1 ;; esac
    done
  done
}

# what the table cannot hold is left out, its file, line and reason kept for
# hi --doctor: a key above the first table, a table of the rows before these
# or of no [<group>.<name>], a second plugin of a name, a file's table under
# no plugin or for a file it has not, a key hi does not read, a plugin of no
# files, a tool of another shape, and a file that is no member, is hi's own or
# the directory of one, the plugins file's, another plugin's, or has a wire, a
# dialect, or a home hi does not read. The rest of a plugin rides without the
# file that was turned down, and a plugin of a name the tree has replaces the
# tree's whole.
# shellcheck disable=SC2088 # the ~ is the file's to read, not the shell's
function test_carry_turns_down_a_row_the_table_cannot_hold() {
  local dir
  dir="$(_hi_overlay_fixture carry-bad)"
  {
    printf 'top = "x"\n'                                             # 1: no table above it
    printf '[mine]\nold = "- | - | ~/x"\n'                           # 2: the rows before the tables
    printf '[bad group.x]\nfiles = "x"\n'                            # 4: no [<group>.<name>]
    printf '[mine.sub."f"]\nwire = "-"\n'                            # 6: follows no [mine.sub]
    printf '[mine.good]\ntool = "-"\nhome = "~/x"\nfiles = "good"\n' # 8
    printf 'color = "red"\n'                                         # 12: no key of a plugin
    printf 'bare words\n'                                            # 13: no line of a plugin
    printf '[mine.good."other"]\nwire = "-"\n'                       # 14: no file of good
    printf '[mine.good."good"]\ntool = "x"\n'                        # 16, 17: no key of a file
    printf '[mine.good]\nfiles = "again"\n'                          # 18: a plugin already
    printf '[mine.empty]\ntool = "-"\n'                              # 20: no files
    printf '[mine.tools]\ntool = "a;b"\nfiles = "t1"\n'              # 22: a tool of another shape
    # 25: eight files turned down for the reason each has, two kept
    printf '[mine.files]\ntool = "-"\nhome = "~/x"\n'
    printf 'files = "../up wiring.sh plugins colors micro zellij/layouts/x good w1 d1 fn kept kept four"\n'
    printf '[mine.files."w1"]\nwire = "env:A;rm"\n'
    printf '[mine.files."d1"]\ndialect = "nodialect"\n'
    printf '[mine.files."fn"]\nhome = "@_hi_posh_home"\n'
    printf '[mine.files."four"]\nwire = "xdg:a,b=c;xdg:d"\ndialect = "sh"\n'
    # the tree's plugins of these names give way whole
    printf '[editors.vim]\nhome = "~/.vimrc"\nfiles = "vim/vimrc"\n'
    printf '[mux.zellij]\nhome = "~/x/"\nfiles = "zellij/layouts/"\n'
  } >"$dir/plugins"
  (
    _HI_CONFIG_DIR="$dir"
    _hi_plugins_load
    case " ${_HI_PLUGIN_FILES[*]} " in
    *" good kept four "*) ;;
    *) _hi_because "kept: ${_HI_PLUGIN_FILES[*]}" || exit 1 ;;
    esac
    [ "${#_HI_PLUGIN_BAD[@]}" = 22 ] || _hi_because "turned down ${#_HI_PLUGIN_BAD[@]}: $(printf '[%s] ' "${_HI_PLUGIN_BAD[@]}")" || exit 1
    case "${_HI_PLUGIN_BAD[0]}" in 'plugins:1|no [<group>.<name>] above it') ;; *) _hi_because "first: ${_HI_PLUGIN_BAD[0]}" || exit 1 ;; esac
    case "${_HI_PLUGIN_BAD[1]}" in 'plugins:2|'*'hi --configure converts') ;; *) _hi_because "second: ${_HI_PLUGIN_BAD[1]}" || exit 1 ;; esac
    local r="" tilde='~'
    _hi_overlay_row vim/vimrc r
    [ "${r##*|}" = "$tilde/.vimrc" ] || _hi_because "the tree's vim was not replaced: $r" || exit 1
    _hi_overlay_row zellij/layouts/x r
    [ "${r##*|}" = "$tilde/x/" ] || _hi_because "the tree's zellij was not replaced: $r" || exit 1
    ! _hi_overlay_row zellij/config.kdl r || _hi_because "a file of the tree's zellij outlived it: $r"
  )
}

# the check and the writer take a wire apart through one function
# (_hi_wire_read), so what the check admits is what is written: a word after
# a `--flag=`, a = inside a later word, names and an environment ahead of
# the command - and no part that would run where a target sources the line
# shellcheck disable=SC2016 # the wires and the wanted lines hold their $ unexpanded
function test_a_wire_is_checked_as_it_is_written() {
  local dir w why
  dir="$(_hi_overlay_fixture wire-read a.rc b.rc)"
  {
    printf '[mine.a]\ntool = "-"\nwire = "flag:atool --config= extra"\nhome = "/etc/a"\nfiles = "a.rc"\n'
    printf '[mine.b]\ntool = "-"\nwire = "flag:b1,b2=X=$HOME/x btool -o k=v -f"\nhome = "/etc/b"\nfiles = "b.rc"\n'
  } >"$dir/plugins"
  [ "$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat wiring.sh)" = 'command -v atool >/dev/null 2>&1 && alias atool="atool --config= extra $_HI_CONFIG_DIR/a.rc" || true
command -v btool >/dev/null 2>&1 && alias b1="env X=$HOME/x btool -o k=v -f $_HI_CONFIG_DIR/b.rc" && alias b2="env X=$HOME/x btool -o k=v -f $_HI_CONFIG_DIR/b.rc" || true' ] ||
    _hi_because "wiring.sh: $(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat wiring.sh 2>&1)" || return 1
  for w in 'flag:$(x)=cmd -f' 'flag:v=X=$(rm) vim -u' 'flag:a,,b=c -f' 'flag:vim' 'flag:c -f;rm' 'xdg:$(x)=c' 'flag:c `x`' 'env:A=$(x)'; do
    ! _hi_plugin_wire_ok "$w" why || _hi_because "admitted: $w" || return 1
    [ -n "$why" ] || _hi_because "no reason for: $w" || return 1
  done
}

# ...the tree's own file is read by the same rules, and every row of it
# holds
function test_the_tree_plugins_file_holds() {
  local dir
  dir="$(_hi_overlay_fixture tree-plugins)"
  (
    _HI_CONFIG_DIR="$dir"
    _hi_plugins_load
    [ "${#_HI_PLUGIN_BAD[@]}" = 0 ] || _hi_because "turned down: $(printf '[%s] ' "${_HI_PLUGIN_BAD[@]}")" || exit 1
    [ "${#_HI_PLUGIN_ROWS[@]}" = "$(sed -n 's/^files = "\(.*\)"$/\1/p' "$_HI_ROOT/config/plugins" | wc -w | tr -d ' ')" ] ||
      _hi_because "rows: ${#_HI_PLUGIN_ROWS[@]}"
  )
}

# a plugin that is switched off sends nothing: $_HI_PLUGINS_OFF names it or
# the member, a row of the user's own too - never its group, and never one
# of hi's own files, which only their toggles switch (GLOSSARY: HI.64)
function test_plugin_off_keeps_its_members_home() {
  local dir
  dir="$(_hi_overlay_fixture plugins-off colors vim/vimrc nano/nanorc tmux/tmux.conf bat/config lazygit/config.yml mine.rc)"
  mkdir -p "$dir/micro"
  printf '{}\n' >"$dir/micro/settings.json"
  printf '[mine.mine]\ntool = "-"\nwire = "env:MINE"\nhome = "/etc/mine"\nfiles = "mine.rc"\n' >"$dir/plugins"
  [ "$(_HI_PLUGINS_OFF="lazygit vim nano micro" _HI_CONFIG_DIR="$dir" _hi_overlay_files | tr '\n' ' ')" = "colors bat/config tmux/tmux.conf mine.rc " ] ||
    _hi_because "four plugins off: $(_HI_PLUGINS_OFF="lazygit vim nano micro" _HI_CONFIG_DIR="$dir" _hi_overlay_files | tr '\n' ' ')" || return 1
  [ "$(_HI_PLUGINS_OFF="tmux,bat,lazygit,mine,nano/nanorc" _HI_CONFIG_DIR="$dir" _hi_overlay_files | tr '\n' ' ')" = "colors vim/vimrc micro/settings.json " ] ||
    _hi_because "commas, a member, a plugin of the user's: $(_HI_PLUGINS_OFF="tmux,bat,lazygit,mine,nano/nanorc" _HI_CONFIG_DIR="$dir" _hi_overlay_files | tr '\n' ' ')" || return 1
  [ "$(_HI_PLUGINS_OFF="editors mux cli" _HI_CONFIG_DIR="$dir" _hi_overlay_files | grep -c -x -e vim/vimrc -e tmux/tmux.conf -e bat/config)" = 3 ] ||
    _hi_because "a group's word kept a plugin home" || return 1
  [ "$(_HI_PLUGINS_OFF="colors settings.sh" _HI_CONFIG_DIR="$dir" _hi_overlay_files | grep -c -x colors)" = 1 ] ||
    _hi_because "one of hi's own was switched off" || return 1
  # one file of a directory member, by its own name: the rest of it rides
  mkdir -p "$dir/extensions"
  printf 'export A=1\n' >"$dir/extensions/10-a"
  printf 'export B=1\n' >"$dir/extensions/20-b"
  [ "$(_HI_PLUGINS_OFF="extensions/10-a vim nano micro bat lazygit tmux mine" _HI_CONFIG_DIR="$dir" _hi_overlay_files | tr '\n' ' ')" = "colors extensions/20-b " ] ||
    _hi_because "one extension off: $(_HI_PLUGINS_OFF="extensions/10-a vim nano micro bat lazygit tmux mine" _HI_CONFIG_DIR="$dir" _hi_overlay_files | tr '\n' ' ')" || return 1
  [ -z "$(_HI_PLUGINS_OFF="extensions" _HI_CONFIG_DIR="$dir" _hi_overlay_files extensions/)" ] ||
    _hi_because "the directory's plugin off left a file riding"
}

# ...nor its wiring line: what a tool is not to use has no business on the
# wire
function test_a_plugin_off_has_no_wiring_line() {
  local dir w=""
  dir="$(_hi_overlay_fixture wire-off vim/vimrc nvim/init.lua nano/nanorc kak/kakrc bat/config)"
  [ "$(_HI_PLUGINS_OFF=kak _HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf - | sort | paste -sd, -)" = "bat/config,nano/nanorc,nvim/init.lua,vim/vimrc,wiring.sh" ] || return 1
  _HI_PLUGINS_OFF=kak _HI_CONFIG_DIR="$dir" _hi_overlay_wiring w bat/config
  [[ "$w" != *KAKOUNE* ]]
}

# _hi_hooks_wiring <overlay> <stubs> [VAR=value...] - wiring.sh's text for an
# overlay with no member, the stubs on PATH and the lists as given
function _hi_hooks_wiring() {
  local dir="$1" stubs="$2"
  shift 2
  env PATH="$stubs:$PATH" _HI_CONFIG_DIR="$dir" _HI_PLUGINS_OFF= _HI_PLUGINS_ON= _HI_PROMPT_TOOL=hi ${1+"$@"} \
    bash -c 'set -- && source "$_HI_LAUNCHER" && _hi_overlay_wiring w && printf %s "$w"'
}

# a shell hook rides as a row of _HI_HOOKS, its tool here and its plugin on;
# one off by default rides with a leading - once _HI_PLUGINS_ON names it,
# and never when _HI_PLUGINS_OFF does, its group's word switching nothing in
# either; a prompt plugin's init
# rides as _HI_PROMPT_INITS and a _HI_PROMPT_PLUGINS row instead, only when
# a target is handed the program (GLOSSARY: HI.67)
function test_hook_plugins_ride_as_wiring_rows() {
  local dir stubs w
  dir="$(_hi_overlay_fixture hooks-wire)"
  {
    printf '[mine.hi-hook-here]\ninit = "hi-hook-here init {shell}"\n'
    printf '[mine.hi-hook-off]\ninit = "hi-hook-off hook {shell}"\ndefault = "off"\n'
    printf '[mine.hi-hook-gone]\ninit = "hi-hook-gone init {shell}"\n'
    printf '[mine.hi-prompt-here]\ninit = "hi-prompt-here init {shell}"\nprompt = "yes"\n'
  } >"$dir/plugins"
  stubs="$(_hi_stub_tools hi-hook-here hi-hook-off hi-prompt-here)"
  w="$(_hi_hooks_wiring "$dir" "$stubs")" || return 1
  [[ "$w" == *'export _HI_HOOKS="'*'mine.hi-hook-here=hi-hook-here init {shell}'*'"'* ]] || _hi_because "no hook row: $w" || return 1
  [[ "$w" != *hi-hook-off* && "$w" != *hi-hook-gone* && "$w" != *hi-prompt-here* && "$w" != *_HI_PROMPT_INITS* ]] ||
    _hi_because "rode unasked: $w" || return 1
  w="$(_hi_hooks_wiring "$dir" "$stubs" _HI_PLUGINS_ON=hi-hook-off)" || return 1
  [[ "$w" == *'mine.-hi-hook-off=hi-hook-off hook {shell}'* ]] || _hi_because "on by name: $w" || return 1
  w="$(_hi_hooks_wiring "$dir" "$stubs" _HI_PLUGINS_ON=mine)" || return 1
  [[ "$w" != *hi-hook-off* ]] || _hi_because "on by its group's word: $w" || return 1
  w="$(_hi_hooks_wiring "$dir" "$stubs" _HI_PLUGINS_ON=hi-hook-off _HI_PLUGINS_OFF=hi-hook-off)" || return 1
  [[ "$w" != *hi-hook-off* ]] || _hi_because "off list lost: $w" || return 1
  w="$(_hi_hooks_wiring "$dir" "$stubs" _HI_PLUGINS_OFF=mine)" || return 1
  [[ "$w" == *'mine.hi-hook-here='* ]] || _hi_because "off by its group's word: $w" || return 1
  w="$(_hi_hooks_wiring "$dir" "$stubs" _HI_PROMPT_TOOL="hi-prompt-here hi")" || return 1
  [[ "$w" == *'export _HI_PROMPT_INITS="hi-prompt-here=hi-prompt-here init {shell}"'*'export _HI_PROMPT_PLUGINS="hi-prompt-here|bash zsh fish|bin|-"'* ]] ||
    _hi_because "prompt plugin: $w" || return 1
  [[ "$w" != *'mine.hi-prompt-here'* ]] || _hi_because "a prompt plugin is no hook: $w"
}

# an init is a command and its words: one the shell would read as more, or
# a prompt = yes with no init, is a row turned down with its reason
function test_hook_plugin_rows_hold_a_command_alone() {
  local dir
  dir="$(_hi_overlay_fixture hooks-bad)"
  {
    printf '[mine.a]\ninit = "a init {shell}; touch x"\n'
    printf '[mine.b]\ninit = "b init $(x)"\n'
    printf '[mine.c]\nprompt = "yes"\nfiles = "c.rc"\n'
    printf '[mine.d]\ninit = "d-tool hook {shell} --flag"\n'
  } >"$dir/plugins"
  (
    _HI_CONFIG_DIR="$dir"
    _hi_plugins_load
    [ "${#_HI_PLUGIN_BAD[@]}" = 3 ] || _hi_because "turned down: $(printf '[%s] ' "${_HI_PLUGIN_BAD[@]}")" || exit 1
    [[ "${_HI_PLUGIN_BAD[0]}" == *"a: init is a command and its words"* && "${_HI_PLUGIN_BAD[1]}" == *"b: init is a command"* &&
      "${_HI_PLUGIN_BAD[2]}" == *"c: prompt = yes needs an init"* ]] || _hi_because "reasons: $(printf '[%s] ' "${_HI_PLUGIN_BAD[@]}")" || exit 1
    [[ " ${_HI_PLUGIN_HOOKS[*]} " == *" mine|d|d-tool|d-tool hook {shell} --flag|no "* ]] || _hi_because "rows: ${_HI_PLUGIN_HOOKS[*]}"
  )
}

# the init check is builtins alone, so a cut-down PATH turns the same rows
# away: each character the shell reads as more than a word, and no init
function test_plugin_init_check_runs_no_command() {
  local bad
  PATH=/nonexistent _hi_plugin_init_ok 'd-tool hook {shell} --flag' || _hi_because "a command and its words turned away" || return 1
  for bad in 'a; b' 'a | b' 'a & b' 'a $x' 'a `b`' 'a "b"' 'a (b' 'a b)' 'a <b' 'a >b' "a 'b'" ''; do
    ! PATH=/nonexistent _hi_plugin_init_ok "$bad" || _hi_because "passed: $bad" || return 1
  done
}

# one of hi's own files answers to its toggle alone, and under
# _HI_DISABLE_LOCAL=1 common/paths.sh has set every toggle on this machine:
# only a toggle settings.sh sets itself keeps the file home, its last line
# winning, quoted or not
function test_local_only_toggles_keep_nothing_home() {
  local dir
  dir="$(_hi_overlay_fixture local-only packages vim/vimrc)"
  printf '#!/bin/sh\nexport _HI_DISABLE_LOCAL=1\n' >"$dir/settings.sh"
  [ "$(_HI_DISABLE_LOCAL=1 _HI_DISABLE_HEADER=1 _HI_SETTINGS="$dir/settings.sh" _HI_CONFIG_DIR="$dir" _hi_overlay_files | tr '\n' ' ')" = "settings.sh packages vim/vimrc " ] ||
    _hi_because "local only kept the package list home" || return 1
  printf 'export _HI_DISABLE_HEADER=0\nexport _HI_DISABLE_HEADER="1"\n' >>"$dir/settings.sh"
  [ "$(_HI_DISABLE_LOCAL=1 _HI_DISABLE_HEADER=1 _HI_SETTINGS="$dir/settings.sh" _HI_CONFIG_DIR="$dir" _hi_overlay_files | tr '\n' ' ')" = "settings.sh vim/vimrc " ] ||
    _hi_because "settings.sh's own toggle did not keep the package list home"
}

# The overlay stream ships comment-stripped the way the payload does (the
# same strip.awk): a copied-in default is mostly header, and every byte rides
# each connect. settings.sh keeps its shebang; vim/vimrc loses its `"` lines and
# nvim/init.lua its `--` ones.
function test_overlay_strip_removes_comments() {
  local dir="$_HI_WORKDIR/ovl-strip" out
  mkdir -p "$dir"
  printf '#!/bin/sh\n# a comment\nexport _HI_MAX_WIDTH=72\n' >"$dir/settings.sh"
  cp "$_HI_ROOT/config/colors" "$dir/colors"
  mkdir -p "$dir/vim" "$dir/nvim"
  printf '" a comment\nset number\n' >"$dir/vim/vimrc"
  printf -- '-- a comment\nvim.opt.number = true\n' >"$dir/nvim/init.lua"
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat settings.sh)"
  [ "$out" = '#!/bin/sh
export _HI_MAX_WIDTH=72' ] || {
    _hi_cecho " | settings.sh arrived as: [$out]" "$RED"
    return 1
  }
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat colors)"
  [ -n "$out" ] || return 1
  case "$out" in *'#'*)
    _hi_cecho " | colors kept a comment line through the strip" "$RED"
    return 1
    ;;
  esac
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat vim/vimrc)"
  [ "$out" = "set number" ] || _hi_because "vim/vimrc arrived as: [$out]" || return 1
  case "$out" in '"'* | *$'\n"'*)
    _hi_cecho " | vim/vimrc kept a vim comment line through the strip" "$RED"
    return 1
    ;;
  esac
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat nvim/init.lua)"
  [ "$out" = "vim.opt.number = true" ] || _hi_because "nvim/init.lua arrived as: [$out]" || return 1
  case "$out" in '--'* | *$'\n--'*)
    _hi_cecho " | nvim/init.lua kept a lua comment line through the strip" "$RED"
    return 1
    ;;
  esac
  return 0
}

# the user's own aliases ride the same stream under their bare name,
# which is where common/aliases.sh's tail line ($_HI_CONFIG_DIR/aliases.sh, the
# target's config/) looks - a separate file from the shipped one, on purpose
# Naming what the tar listed separates the three ways this fails - an empty
# archive, a second member riding along, and a member under another name - which
# a bare FAILED cannot.
function test_overlay_tar_carries_aliases() {
  local dir listed
  dir="$(_hi_overlay_fixture withaliases aliases.sh)"
  listed="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf -)"
  [ "$listed" = "aliases.sh" ] ||
    _hi_because "the overlay tar listed [$listed], wanted [aliases.sh]"
}

function run_hi_payload_overlay_tests() {
  _hi_payload_begin

  _hi_h1 "Testing hi.sh: the overlay stream"

  _hi_h2 "Testing: the config overlay stream"
  _hi_check "Nothing sent without an overlay" test_overlay_is_empty_without_one
  _hi_check "Seen when present" test_overlay_is_seen_when_present
  _hi_check "Members are bare names" test_overlay_tar_members_are_bare_names
  _hi_check "Carries only what exists" test_overlay_tar_carries_only_what_exists
  _hi_check "aliases.sh rides the stream" test_overlay_tar_carries_aliases
  _hi_check "A wired member rides with its wiring.sh line" test_overlay_tar_wires_the_members_it_carries
  _hi_check "...an editor's or a multiplexer's with its alias" test_overlay_tar_aliases_the_editors_and_multiplexers
  _hi_check "...and there is no wiring.sh without one" test_overlay_tar_has_no_wiring_without_a_wired_member
  _hi_check "A plugin of the user's rides from home, wired" test_carry_row_rides_from_home_with_its_wiring
  _hi_check "...its home list expands three starts and runs nothing" test_carry_home_list_expands_three_starts_and_runs_nothing
  _hi_check "...paths a , apart are one place, the first set" test_home_list_takes_the_first_set_of_a_place
  _hi_check "...and the table's own rows are that grammar" test_table_home_columns_are_the_grammar
  _hi_check "...what the table cannot hold is turned down" test_carry_turns_down_a_row_the_table_cannot_hold
  _hi_check "...a wire is checked as it is written" test_a_wire_is_checked_as_it_is_written
  _hi_check "...and the tree's own file holds whole" test_the_tree_plugins_file_holds
  _hi_check "A plugin that is off sends nothing" test_plugin_off_keeps_its_members_home
  _hi_check "...nor has it a wiring line" test_a_plugin_off_has_no_wiring_line
  _hi_check "A shell hook rides as a wiring row, by the lists and the tool here" test_hook_plugins_ride_as_wiring_rows
  _hi_check "...an init is a command and its words, or the row is turned down" test_hook_plugin_rows_hold_a_command_alone
  _hi_check "...checked with no command at all" test_plugin_init_check_runs_no_command
  _hi_check "...while local-only's toggles keep nothing home" test_local_only_toggles_keep_nothing_home
  _hi_check "The stream is comment-stripped" test_overlay_strip_removes_comments
  _hi_check "the user's per-shell files ride the stream" test_overlay_tar_carries_shell_files
  _hi_check_capable symlink "Symlinked overlay files are dereferenced (Stow)" test_overlay_dereferences_symlinks
  _hi_check "Nothing outside the roster travels" test_overlay_sends_nothing_outside_the_roster
  _hi_check "The overlay's packages rides stripped" test_overlay_carries_packages_stripped
  _hi_check "Extensions ride stripped" test_overlay_carries_extensions
  _hi_suite_end "hi.sh (the overlay stream)"
}

run_hi_payload_overlay_tests
