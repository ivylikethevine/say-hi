#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# Unit tests for hi.sh: the ssh payload, the config overlay stream, and the size
# hi reports on connect. The payload is an allow list, so most of this file is
# its drift guard - what ships, whatever the overlay says.
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

# _hi_tar_cat <member> - one member of the gzipped archive on stdin, printed:
# unpacked and read back, since OpenBSD's tar has no -O to extract to stdout
function _hi_tar_cat() {
  local d
  d="$(mktemp -d "$_HI_WORKDIR/tarcat.XXXXXX")" || return 1
  tar -x -z -f - -C "$d" && cat "$d/$1"
}

# An unconfigured client ships everything - which is also what both size budgets
# are measuring, so this is the case that keeps those numbers meaning something.
function test_payload_ships_everything_by_default() {
  local dir="$_HI_WORKDIR/notrim" listing
  mkdir -p "$dir"
  listing="$(_HI_CONFIG_DIR="$dir" _hi_payload_tar | tar tzf - 2>/dev/null)"
  case "$listing" in *say-hi/settings/vim.rc*) ;; *)
    _hi_cecho " | a default client did not ship settings/vim.rc" "$RED"
    return 1
    ;;
  esac
  case "$listing" in *say-hi/settings/init.lua*) ;; *)
    _hi_cecho " | a default client did not ship settings/init.lua" "$RED"
    return 1
    ;;
  esac
  return 0
}

# No toggle changes what ships: every one of them on at once still ships the
# same tree as a default client - a toggle is read where it applies, never by
# the tar. Asserted against every toggle at once rather than one in
# particular.
function test_payload_always_ships_aliases() {
  local dir="$_HI_WORKDIR/alloff" listing t
  mkdir -p "$dir"
  printf '#!/bin/sh\n' >"$dir/settings.sh"
  for t in "${_HI_TOGGLES[@]}"; do
    printf "export %s='1'\n" "$t" >>"$dir/settings.sh"
  done
  listing="$(_HI_CONFIG_DIR="$dir" _hi_payload_tar | tar tzf - 2>/dev/null)"
  case "$listing" in *say-hi/settings/aliases.sh*) return 0 ;; esac
  _hi_cecho " | every toggle off dropped settings/aliases.sh, which carries the whole alias set" "$RED"
  return 1
}

# The three per-shell overrides, which take the shell file's own basename so a
# user reading common/bash.sh knows what ~/.config/say-hi/bash.sh extends.
function test_overlay_tar_carries_shell_files() {
  local dir
  dir="$(_hi_overlay_fixture withshells bash.sh zsh.zsh config.fish)"
  [ "$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf - | sort | tr '\n' ' ')" = "bash.sh config.fish zsh.zsh " ]
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
  mkdir -p "$dir/.git" "$dir/.chezmoitemplates" "$dir/packages.d/sub"
  printf 'export _HI_MAX_WIDTH=72\n' >"$dir/settings.sh"
  for f in .git/config .chezmoiignore README.md id_rsa settings.sh.bak .settings.sh.swp \
    packages.d/10-x packages.d/10-x.bak packages.d/.10-x.swp packages.d/10-x~ packages.d/sub/20-y; do
    printf 'x:3\n' >"$dir/$f"
  done
  while IFS= read -r f; do
    [ -n "$f" ] && [ "$f" != packages.d/10-x ] || continue
    case " ${_HI_OVERLAY_FILES[*]} " in
    *" $f "*) continue ;;
    esac
    _hi_cecho " | the overlay stream carried $f, which is not in _HI_OVERLAY_FILES" "$RED"
    return 1
  done <<<"$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf -)"
  return 0
}

# packages.d's members ride as packages.d/<name>, comment-stripped like any
# packages file, their color= line intact - and two of them cost the stream
# under 192 gzipped bytes over the same rows in one file (a tar header each,
# and the color= line: 84 measured under GNU tar, 143 under OpenBSD's), so
# splitting is nearly free.
function test_overlay_carries_package_groups() {
  local one="$_HI_WORKDIR/groups-one" split="$_HI_WORKDIR/groups-split" n out a b
  mkdir -p "$one" "$split/packages.d"
  cp "$_HI_ROOT/settings/packages" "$one/packages"
  n="$(grep -c . "$one/packages")"
  head -n $((n / 3)) "$one/packages" >"$split/packages"
  { printf 'color=orange\n' && sed -n "$((n / 3 + 1)),$((2 * n / 3))p" "$one/packages"; } >"$split/packages.d/10-lang"
  sed -n "$((2 * n / 3 + 1)),\$p" "$one/packages" >"$split/packages.d/20-box"
  [ "$(_HI_CONFIG_DIR="$split" _hi_overlay_tar | tar tzf - | paste -sd, -)" = packages,packages.d/10-lang,packages.d/20-box ] || return 1
  out="$(_HI_CONFIG_DIR="$split" _hi_overlay_tar | _hi_tar_cat packages.d/10-lang)"
  case "$out" in color=orange$'\n'*) ;; *) return 1 ;; esac
  case "$out" in *'#'*)
    _hi_cecho " | packages.d/10-lang kept a comment line through the strip" "$RED"
    return 1
    ;;
  esac
  a="$(_HI_CONFIG_DIR="$one" _hi_overlay_tar | wc -c)"
  b="$(_HI_CONFIG_DIR="$split" _hi_overlay_tar | wc -c)"
  [ $((b - a)) -lt 192 ] || {
    _hi_cecho " | two packages.d members cost $((b - a)) bytes over one file (budget 192)" "$RED"
    return 1
  }
}

# plugins.d's members ride as plugins.d/<name>, comment-stripped, and only the
# ones _hi_dir_member_ok admits (GLOSSARY: HI.59)
function test_overlay_carries_plugins() {
  local dir out
  dir="$_HI_WORKDIR/plugins"
  mkdir -p "$dir/plugins.d"
  printf '#!/bin/sh\n# a comment\nexport _HI_SEGMENT="printf x"\n' >"$dir/plugins.d/10-x"
  printf 'export Y=1\n' >"$dir/plugins.d/10-x.orig"
  [ "$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf - | paste -sd, -)" = plugins.d/10-x ] || return 1
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat plugins.d/10-x)"
  [ "$out" = '#!/bin/sh
export _HI_SEGMENT="printf x"' ] || {
    _hi_cecho " | plugins.d/10-x arrived as: [$out]" "$RED"
    return 1
  }
}

# starship's, eza's, and bat's configs ride from where each tool reads them
# here (_hi_overlay_src), under the overlay's name for them, so a target draws
# the config in force at home - unless the overlay has its own copy, which is
# how a target gets a different one.

# _hi_tool_home_unpacked <overlay> [NAME=value...] - _hi_overlay_tar's stream
# unpacked into a fresh directory, which is printed. HOME and XDG_CONFIG_HOME
# point at a fixture home and the tools' own variables start unset, so the
# developer's real configs never answer.
function _hi_tool_home_unpacked() {
  local dir="$1" d
  shift
  d="$(mktemp -d "$_HI_WORKDIR/toolhome.XXXXXX")" || return 1
  (
    unset STARSHIP_CONFIG EZA_CONFIG_DIR BAT_CONFIG_PATH BAT_CONFIG_DIR MICRO_CONFIG_HOME POSH_CONFIG POSH_THEME
    export HOME="$_HI_WORKDIR/tool-home" XDG_CONFIG_HOME="$_HI_WORKDIR/tool-home/.config" \
      _HI_PROMPT_TOOL=starship _HI_CONFIG_DIR="$dir" ${1+"$@"}
    _hi_overlay_tar | tar -x -z -f - -C "$d"
  ) || return 1
  printf '%s' "$d"
}

function _hi_tool_home_fixture() {
  local c="$_HI_WORKDIR/tool-home/.config"
  mkdir -p "$c/eza" "$c/bat"
  printf 'format = "home"\n' >"$c/starship.toml"
  printf 'filekinds: home\n' >"$c/eza/theme.yml"
  printf -- '--theme=home\n' >"$c/bat/config"
}

function test_overlay_carries_the_home_tool_configs() {
  local dir d
  _hi_tool_home_fixture
  dir="$(_hi_overlay_fixture tool-none colors)"
  d="$(_hi_tool_home_unpacked "$dir")" || return 1
  [ "$(cd "$d" && printf '%s ' *)" = "bat.conf colors starship.toml theme.yml " ] &&
    [ "$(cat "$d/starship.toml" "$d/theme.yml" "$d/bat.conf")" = "$(printf 'format = "home"\nfilekinds: home\n--theme=home')" ]
}

# each tool's own variable names the file, whatever it is called - here with
# no overlay member of its own, so nothing comes from the overlay directory
function test_overlay_home_configs_follow_the_tools_variables() {
  local o="$_HI_WORKDIR/tool-vars" dir d
  mkdir -p "$o/ezadir"
  printf 'format = "var"\n' >"$o/prompt.toml"
  printf 'filekinds: var\n' >"$o/ezadir/theme.yml"
  printf -- '--theme=var\n' >"$o/bat-flags"
  dir="$(_hi_overlay_fixture tool-empty)"
  d="$(_hi_tool_home_unpacked "$dir" STARSHIP_CONFIG="$o/prompt.toml" \
    EZA_CONFIG_DIR="$o/ezadir" BAT_CONFIG_PATH="$o/bat-flags")" || return 1
  [ "$(cat "$d/starship.toml" "$d/theme.yml" "$d/bat.conf")" = "$(printf 'format = "var"\nfilekinds: var\n--theme=var')" ]
}

# an overlay copy wins over home's - and starship's still rides only with
# starship in the list, which is the only thing that starts it
function test_overlay_copy_of_a_tool_config_wins() {
  local dir d
  _hi_tool_home_fixture
  dir="$(_hi_overlay_fixture tool-copy bat.conf theme.yml starship.toml)"
  d="$(_hi_tool_home_unpacked "$dir")" || return 1
  [ "$(cat "$d/bat.conf" "$d/theme.yml" "$d/starship.toml")" = "$(printf 'x\nx\nx')" ] || return 1
  d="$(_hi_tool_home_unpacked "$dir" _HI_PROMPT_TOOL=hi)" || return 1
  [ "$(cat "$d/bat.conf" "$d/theme.yml")" = "$(printf 'x\nx')" ] && [ ! -e "$d/starship.toml" ]
}

# the prompt frameworks' files the same way: an overlay copy of each rides over
# the one home has (tide's still down to its tide_ lines)
function test_overlay_copy_of_a_prompt_framework_file_wins() {
  local dir d h="$_HI_WORKDIR/fw-home"
  _hi_fw_home_fixture
  dir="$_HI_WORKDIR/fw-copy"
  mkdir -p "$dir"
  printf 'POWERLEVEL9K_MODE=overlay\n' >"$dir/p10k.zsh"
  printf 'PROMPT=overlay\n' >"$dir/omz-theme.zsh"
  printf 'PS1=overlay\n' >"$dir/omb-theme.sh"
  printf 'SETUVAR secret:x\nSETUVAR tide_character_icon:overlay\n' >"$dir/tide.vars"
  d="$(_hi_tool_home_unpacked "$dir" HOME="$h" XDG_CONFIG_HOME="$h/.config" \
    _HI_PROMPT_TOOL="powerlevel10k oh-my-zsh oh-my-bash tide")" || return 1
  [ "$(cat "$d/p10k.zsh" "$d/omz-theme.zsh" "$d/omb-theme.sh" "$d/tide.vars")" = \
    "$(printf 'POWERLEVEL9K_MODE=overlay\nPROMPT=overlay\nPS1=overlay\nSETUVAR tide_character_icon:overlay')" ] || {
    _hi_cecho " | the stream carried: [$(cat "$d"/* 2>&1)]" "$RED"
    return 1
  }
}

# oh-my-posh has no default file: home's is the one $POSH_CONFIG names, else
# the one an rc's `oh-my-posh init ... --config` names, riding under the
# member its extension picks. Any overlay copy outranks both, and an
# `extends` naming a local file goes out emptied - a URL or a theme name
# resolves on the target and stays.
function test_oh_my_posh_config_rides_from_home_or_overlay() {
  local h="$_HI_WORKDIR/omp-home" dir d
  mkdir -p "$h"
  printf '{\n  "extends": "~/base.omp.json",\n  "version": 3\n}\n' >"$h/mine.omp.json"
  printf 'extends: https://example.com/base.yaml\nversion: 3\n' >"$h/rc.omp.yaml"
  printf 'eval "$(oh-my-posh init bash --config ~/rc.omp.yaml)"\n' >"$h/.bashrc"
  dir="$(_hi_overlay_fixture omp-none)"
  set -- HOME="$h" XDG_CONFIG_HOME="$h/.config" _HI_PROMPT_TOOL=oh-my-posh
  d="$(_hi_tool_home_unpacked "$dir" "$@" POSH_CONFIG="$h/mine.omp.json")" || return 1
  [ "$(cd "$d" && printf '%s ' *)" = "oh-my-posh.json " ] &&
    [ "$(cat "$d/oh-my-posh.json")" = "$(printf '{\n  "extends": "",\n  "version": 3\n}')" ] || {
    _hi_cecho " | from \$POSH_CONFIG: [$(cd "$d" && printf '%s ' *)] $(cat "$d"/* 2>&1)" "$RED"
    return 1
  }
  d="$(_hi_tool_home_unpacked "$dir" "$@")" || return 1
  [ "$(cd "$d" && printf '%s ' *)" = "oh-my-posh.yaml " ] &&
    [ "$(cat "$d/oh-my-posh.yaml")" = "$(cat "$h/rc.omp.yaml")" ] || {
    _hi_cecho " | from the rc: [$(cd "$d" && printf '%s ' *)]" "$RED"
    return 1
  }
  printf 'version = 3\n' >"$dir/oh-my-posh.toml"
  d="$(_hi_tool_home_unpacked "$dir" "$@" POSH_CONFIG="$h/mine.omp.json")" || return 1
  [ "$(cd "$d" && printf '%s ' *)" = "oh-my-posh.toml " ]
}

# The prompt frameworks' home half, each only with its name in the list:
# powerlevel10k's config, the theme file the rc's last ZSH_THEME / OSH_THEME
# names (oh-my-zsh's custom one over its stock copy), and of fish's universal
# variables the tide_ lines alone - never the rest, which can hold secrets.
function _hi_fw_home_fixture() {
  local h="$_HI_WORKDIR/fw-home"
  mkdir -p "$h/.oh-my-zsh/custom/themes" "$h/.oh-my-zsh/themes" "$h/.oh-my-bash/themes/font" "$h/.config/fish"
  printf '# the wizard wrote this\ntypeset -g POWERLEVEL9K_MODE=home\n' >"$h/.p10k.zsh"
  printf 'ZSH_THEME="robbyrussell"\n# ZSH_THEME="commented"\n  ZSH_THEME='"'"'agnoster'"'"' # mine\n' >"$h/.zshrc"
  printf 'PROMPT=custom\n' >"$h/.oh-my-zsh/custom/themes/agnoster.zsh-theme"
  printf 'PROMPT=stock\n' >"$h/.oh-my-zsh/themes/agnoster.zsh-theme"
  printf 'export OSH_THEME="font"\n' >"$h/.bashrc"
  printf 'PS1=font\n' >"$h/.oh-my-bash/themes/font/font.theme.sh"
  printf '# VERSION: 3.0\nSETUVAR --export API_TOKEN:hunter2\nSETUVAR tide_character_icon:\\u276f\n' >"$h/.config/fish/fish_variables"
}

function test_overlay_carries_the_prompt_frameworks_home_files() {
  local dir d h="$_HI_WORKDIR/fw-home"
  set -- HOME="$h" XDG_CONFIG_HOME="$h/.config"
  _hi_fw_home_fixture
  dir="$(_hi_overlay_fixture fw-none colors)"
  d="$(_hi_tool_home_unpacked "$dir" "$@" _HI_PROMPT_TOOL="powerlevel10k oh-my-zsh oh-my-bash tide")" || return 1
  [ "$(cd "$d" && printf '%s ' *)" = "colors omb-theme.sh omz-theme.zsh p10k.zsh tide.vars " ] &&
    [ "$(cat "$d/p10k.zsh" "$d/omz-theme.zsh" "$d/omb-theme.sh" "$d/tide.vars")" = \
      "$(printf 'typeset -g POWERLEVEL9K_MODE=home\nPROMPT=custom\nPS1=font\nSETUVAR tide_character_icon:\\u276f')" ] || return 1
  # unnamed, nothing rides; and powerlevel10k as oh-my-zsh's theme is no theme file
  d="$(_hi_tool_home_unpacked "$dir" "$@" _HI_PROMPT_TOOL=hi)" || return 1
  [ "$(cd "$d" && printf '%s' *)" = colors ] || {
    _hi_cecho " | unnamed, the stream carried: $(cd "$d" && printf '%s ' *)" "$RED"
    return 1
  }
  printf 'ZSH_THEME="powerlevel10k/powerlevel10k"\n' >"$_HI_WORKDIR/fw-home/.zshrc"
  d="$(_hi_tool_home_unpacked "$dir" "$@" _HI_PROMPT_TOOL=oh-my-zsh)" || return 1
  [ ! -e "$d/omz-theme.zsh" ]
}

# Unset, a target is handed every prompt program this machine has, frameworks
# first - the list the members above are gated on, and what _hi_session_env
# ships; set, the setting as written; and a target passes its own along
# rather than looking. GLOSSARY: HI.32
function test_prompt_list_is_what_home_has() {
  local h="$_HI_WORKDIR/fw-home" p
  _hi_fw_home_fixture
  p="$(_hi_fake_path list-bins starship powerline-go)"
  # prefix assignments, not a subshell's exports: _hi_tool_home_unpacked's
  # own already are, and the linter tracks the two as one
  [ "$(HOME="$h" XDG_CONFIG_HOME="$h/.config" PATH="$p:$PATH" _HI_PROMPT_TOOL='' _hi_prompt_list)" = \
    "powerlevel10k oh-my-zsh oh-my-bash starship powerline-go" ] &&
    [ "$(HOME="$h" _HI_PROMPT_TOOL="tide hi" _hi_prompt_list)" = "tide hi" ] &&
    [ -z "$(HOME="$h" PATH="$p:$PATH" _HI_PROMPT_TOOL='' _HI_REMOTE_SESSION=1 _hi_prompt_list)" ]
}

# The payload is an allow list; this is its drift guard. Exact match on the
# list (so nothing sneaks on the wire unnoticed) plus an existence check on
# every member (so a rename can't quietly ship an empty payload).
function test_payload_ships_exactly_the_travelled_paths() {
  local m
  [ "${_HI_PAYLOAD[*]}" = "common settings load.sh hi.sh" ] || {
    _hi_cecho " | payload list changed: ${_HI_PAYLOAD[*]} - update this guard deliberately" "$RED"
    return 1
  }
  for m in "${_HI_PAYLOAD[@]}"; do
    [ -e "$_HI_ROOT/$m" ] || {
      _hi_cecho " | payload member missing from the tree: $m" "$RED"
      return 1
    }
  done
}

# The payload only carries the *in-tree* settings/, so once the user's real
# settings/colors/packages live outside the tree they need their own stream or a
# target silently falls back to the shipped defaults. These assert the two
# halves that can be checked without a target: that nothing is sent when there
# is nothing to send, and that what is sent lands under the names paths.sh
# looks for.

function _hi_overlay_fixture() {
  local dir="$_HI_WORKDIR/$1"
  mkdir -p "$dir"
  shift
  for f in "$@"; do printf 'x\n' >"$dir/$f"; done
  printf '%s' "$dir"
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
  dir="$(_hi_overlay_fixture members colors packages settings.sh)"
  listing="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf -)"
  [ "$(printf '%s\n' "$listing" | sort | paste -sd, -)" = "colors,packages,settings.sh" ]
}

# only what the user actually has - an overlay holding one file must not carry
# a placeholder for the other two, which would shadow the tree's defaults
function test_overlay_tar_carries_only_what_exists() {
  local dir
  dir="$(_hi_overlay_fixture partial colors)"
  [ "$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf -)" = "colors" ]
}

# The overlay stream ships comment-stripped the way the payload does (the
# same strip.awk): a copied-in default is mostly header, and every byte rides
# each connect. settings.sh keeps its shebang; vim.rc loses its `"` lines and
# init.lua its `--` ones.
function test_overlay_strip_removes_comments() {
  local dir="$_HI_WORKDIR/ovl-strip" out
  mkdir -p "$dir"
  printf '#!/bin/sh\n# a comment\nexport _HI_MAX_WIDTH=72\n' >"$dir/settings.sh"
  cp "$_HI_ROOT/settings/colors" "$dir/colors"
  cp "$_HI_ROOT/settings/vim.rc" "$dir/vim.rc"
  cp "$_HI_ROOT/settings/init.lua" "$dir/init.lua"
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
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat vim.rc)"
  case "$out" in '"'* | *$'\n"'*)
    _hi_cecho " | vim.rc kept a vim comment line through the strip" "$RED"
    return 1
    ;;
  esac
  out="$(_HI_NVIMRC="$dir/init.lua" _HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat init.lua)"
  case "$out" in '--'* | *$'\n--'*)
    _hi_cecho " | init.lua kept a lua comment line through the strip" "$RED"
    return 1
    ;;
  esac
  return 0
}

# the user's own aliases ride the same stream under their bare name,
# which is where settings/aliases.sh's tail line ($_HI_CONFIG_DIR/aliases.sh, the
# target's config/) looks - a separate file from the shipped one, on purpose
function test_overlay_tar_carries_aliases() {
  local dir
  dir="$(_hi_overlay_fixture withaliases aliases.sh)"
  [ "$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf -)" = "aliases.sh" ]
}

# Block padding, which is a bug in shipped behaviour on a supported client and
# not a size preference. `tar czf -` lets tar do the compressing, and the two
# userlands pad different things: GNU tar rounds the *uncompressed* archive up
# to the 10240-byte blocking factor and then gzips it, so the NULs compress away
# to about thirty bytes, while bsdtar - macOS's /usr/bin/tar - pads the
# *compressed stream*, so every payload a BSD client built was rounded up to a
# whole multiple of 10240. Measured on this tree: 40960 against 32286 for the
# payload, and 10240 against 140 for a one-file overlay.
#
# `_hi_tar_gz` (hi.sh) splits the two steps, which is what makes the userlands
# agree. The first two cases below hold under either tar; the bsdtar pair is the
# one that would actually have caught this, and is why they are worth having on
# a Linux runner at all - the padding is invisible under GNU tar, which is
# exactly how it survived. They skip rather than fail where bsdtar is absent.
_HI_BLOCK=10240

function test_payload_is_not_block_padded() {
  local n
  n="$(_hi_payload_tar | wc -c)"
  [ "$n" -gt 0 ] && [ "$((n % _HI_BLOCK))" -ne 0 ]
}

# a one-file overlay is a few hundred bytes of content; a whole block means the
# stream was padded, not that the file was big
function test_overlay_is_well_under_one_block() {
  local dir n
  dir="$(_hi_overlay_fixture blockcheck colors)"
  n="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | wc -c)"
  [ "$n" -gt 0 ] && [ "$n" -lt $((_HI_BLOCK / 4)) ]
}

# tar shimmed to bsdtar for the duration of one call: same libarchive macOS's
# /usr/bin/tar is built on, so this reproduces the client the bug belonged to
# without a macOS runner.
function _hi_bsdtar_shim() {
  local shim="$_HI_WORKDIR/bsdtar-shim" real
  real="$(command -v bsdtar 2>/dev/null)" || return 1
  mkdir -p "$shim"
  # a link where the filesystem makes them, an exec wrapper where it does not -
  # _hi_real_path's rule, for the same reason (tests/lib/fixtures.sh)
  ln -sf "$real" "$shim/tar" 2>/dev/null || :
  [ -e "$shim/tar" ] || {
    printf '%s\n' '#!/bin/sh' "exec \"$real\" \"\$@\"" >"$shim/tar"
    chmod +x "$shim/tar"
  }
  printf '%s' "$shim"
}

function test_payload_is_not_block_padded_under_bsdtar() {
  local shim n
  shim="$(_hi_bsdtar_shim)" || return 1
  n="$(PATH="$shim:$PATH" _hi_payload_tar | wc -c)"
  [ "$n" -gt 0 ] && [ "$((n % _HI_BLOCK))" -ne 0 ]
}

function test_overlay_is_not_block_padded_under_bsdtar() {
  local shim dir n
  shim="$(_hi_bsdtar_shim)" || return 1
  dir="$(_hi_overlay_fixture blockcheck_bsd colors)"
  n="$(PATH="$shim:$PATH" _HI_CONFIG_DIR="$dir" _hi_overlay_tar | wc -c)"
  [ "$n" -gt 0 ] && [ "$n" -lt $((_HI_BLOCK / 4)) ]
}

# Two numbers guarded here: the connect line must report the wire bytes, not
# `du` over the payload directories (the uncompressed tree, roughly double
# the truth), and the assembled script must not quietly double. The
# bootloader rides stdin, so no argv cap applies (GLOSSARY: HI.19); the
# ceiling is a tripwire on what every session pays, beside bench's budget.

function test_human_bytes_matches_du_shapes() {
  [ "$(_hi_human_bytes 0)" = 0B ] || return 1
  [ "$(_hi_human_bytes 1023)" = 1023B ] || return 1
  [ "$(_hi_human_bytes 1024)" = 1.0K ] || return 1
  [ "$(_hi_human_bytes 34559)" = 34K ] || return 1
  [ "$(_hi_human_bytes 5000000)" = 4.8M ]
}

# the reported number counts what is sent, not what is on disk: it must be
# nowhere near `du` over the payload
function test_wire_size_is_not_the_disk_size() {
  local wire disk
  wire="$(_hi_wire_estimate)"
  disk="$(_hi_size)"
  [ -n "$wire" ] && [ "$wire" != "$disk" ]
}

# The guard with teeth: the assembled script is what every session pays in
# bandwidth, so measure the thing that is sent rather than re-deriving it from
# the armored streams (which omits the boilerplate wrapping them).
function test_payload_stays_under_the_tripwire() {
  local bytes
  bytes="$(_hi_wire_bytes)"
  # 256KB: the "this has doubled, come and look" line
  [ "$bytes" -lt 262144 ]
}

# The comment strip. Its correctness argument is "only full-line comments, and
# never inside a heredoc", so that is what these assert: the shipped shell is
# still shell, the code survives byte for byte, and the one heredoc a user can
# see - `hi --help` - is intact.
# The include scan. Every editor rc and shell file ships into a config/ of its
# own, so a line naming a path names something no target has and the editor
# or shell fails, not hi. hi.sh's _hi_lint_awk reads every dialect; these pin
# what it drops, what it deliberately leaves alone, that a lua or elisp
# finding takes its whole expression with it rather than leaving a stray
# brace, and that a shell finding leaves the file parseable.
# GLOSSARY: HI.57

# _hi_lint_vars <dir> <cmd...> - <cmd> with every editor path variable
# pointed into <dir>. test_lib.sh pins the four at the tree's copies so a
# developer's own vimrc cannot answer, and _hi_overlay_src reads them rather
# than $_HI_CONFIG_DIR - so a fixture directory alone is not enough here.
function _hi_lint_vars() {
  local dir="$1"
  shift
  _HI_CONFIG_DIR="$dir" _HI_VIMRC="$dir/vim.rc" _HI_NVIMRC="$dir/init.lua" \
    _HI_NANORC="$dir/nano.rc" _HI_EMACSRC="$dir/emacs.el" _HI_TMUX_CONF="$dir/tmux.conf" "$@"
}

# _hi_lint_fixture <name> <member> <body> - an overlay holding one editor rc.
function _hi_lint_fixture() {
  local dir="$_HI_WORKDIR/lint-$1"
  mkdir -p "$dir"
  printf '%s' "$3" >"$dir/$2"
  printf '%s' "$dir"
}

_HI_LINT_VIMRC='set nocompatible
source ~/.vim/extra.vim
source $VIMRUNTIME/defaults.vim
runtime! plugin/sensible.vim
call plug#begin()
Plug "tpope/vim-surround"
call plug#end()
set number
'

# the two vim lines that must survive are the point of the case: `runtime`
# searches the target vim'"'"'s own &runtimepath and $VIMRUNTIME names it, so
# neither is a dangler and dropping them would be a regression, not a fix
function test_editor_includes_are_dropped_on_the_way_out() {
  local dir out
  dir="$(_hi_lint_fixture drop vim.rc "$_HI_LINT_VIMRC")"
  out="$(_HI_VIMRC="$dir/vim.rc" _HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat vim.rc)"
  [ "$out" = 'set nocompatible
source $VIMRUNTIME/defaults.vim
runtime! plugin/sensible.vim
set number' ] || {
    _hi_cecho " | vim.rc arrived as: [$out]" "$RED"
    return 1
  }
}

# _HI_INCLUDES=keep is the escape hatch for a fleet that really does
# carry the file: nothing is touched and the line rides as written
function test_editor_includes_keep_sends_the_lines_as_written() {
  local dir out
  dir="$(_hi_lint_fixture keep vim.rc "$_HI_LINT_VIMRC")"
  out="$(_HI_INCLUDES=keep _HI_VIMRC="$dir/vim.rc" _HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat vim.rc)"
  case "$out" in *'source ~/.vim/extra.vim'*'Plug "tpope/vim-surround"'*) return 0 ;; esac
  _hi_cecho " | vim.rc arrived as: [$out]" "$RED"
  return 1
}

# lua and elisp are not line-oriented: commenting only the line that matched
# would leave `})` behind and the file would not parse at all, which is worse
# than the include it was fixing
function test_a_dropped_expression_goes_out_whole() {
  local dir out
  dir="$(_hi_lint_fixture whole init.lua 'vim.opt.number = true
require("lazy").setup({
  { "tpope/vim-surround" },
})
vim.opt.tabstop = 2
')"
  out="$(_HI_NVIMRC="$dir/init.lua" _HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat init.lua)"
  [ "$out" = 'vim.opt.number = true
vim.opt.tabstop = 2' ] || {
    _hi_cecho " | init.lua arrived as: [$out]" "$RED"
    return 1
  }
}

# the editor rc in force on this machine rides the stream the way the tool
# configs above do, through the path variable paths.sh resolved: there is one
# copy to edit and no duplicate in the overlay to keep in step
function test_the_editor_config_in_force_here_rides_the_stream() {
  local dir mine
  dir="$_HI_WORKDIR/lint-in-force"
  mkdir -p "$dir"
  mine="$_HI_WORKDIR/my.vimrc"
  printf 'set number\n' >"$mine"
  [ "$(_HI_VIMRC="$mine" _HI_CONFIG_DIR="$dir" _hi_overlay_files)" = vim.rc ] &&
    [ "$(_HI_VIMRC="$mine" _HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat vim.rc)" = "set number" ]
}

# ...and hi's own tree copy is not one: it rides in the payload already, so
# packing it again would be the same bytes twice on every connect
function test_the_trees_own_editor_rc_is_not_streamed() {
  local dir
  dir="$_HI_WORKDIR/lint-treecopy"
  mkdir -p "$dir"
  [ -z "$(_HI_VIMRC="$_HI_ROOT/settings/vim.rc" _HI_CONFIG_DIR="$dir" _hi_overlay_files)" ]
}

# the rows hi --doctor prints come from the same pass that does the dropping,
# so what the report names is exactly what went missing
function test_the_scan_reports_every_dialect() {
  local dir out
  dir="$_HI_WORKDIR/lint-report"
  mkdir -p "$dir"
  printf 'source ~/.vim/extra.vim\n' >"$dir/vim.rc"
  printf 'dofile("/tmp/x.lua")\n' >"$dir/init.lua"
  printf 'include "~/.nano/mine.nanorc"\n' >"$dir/nano.rc"
  printf '(load "~/.emacs.d/mine.el")\n' >"$dir/emacs.el"
  printf 'source-file ~/.tmux/theme.conf\n' >"$dir/tmux.conf"
  mkdir -p "$dir/micro"
  printf 'config.AddRuntimeFile("mine", config.RTPlugin, "mine.lua")\n' >"$dir/micro/init.lua"
  printf '. ~/.secrets\n' >"$dir/settings.sh"
  printf 'source ~/.aliases.local\n' >"$dir/aliases.sh"
  printf 'x=1\n[ -f ~/.bash_local ] && . ~/.bash_local\n' >"$dir/bash.sh"
  printf 'zinit light foo/bar\n' >"$dir/zsh.zsh"
  printf 'source ~/.config/fish/local.fish\n' >"$dir/config.fish"
  out="$(_hi_lint_vars "$dir" _hi_include_lint | cut -d'|' -f1,2,3 | paste -sd, -)"
  [ "$out" = "vim.rc|1|include,init.lua|1|include,nano.rc|1|include,emacs.el|1|include,tmux.conf|1|include,micro/init.lua|1|plugin,settings.sh|1|include,aliases.sh|1|include,bash.sh|2|include,zsh.zsh|1|plugin,config.fish|1|include" ] || {
    _hi_cecho " | the scan reported: [$out]" "$RED"
    return 1
  }
}

# a config with nothing to resolve is silent - the scan is a report of danglers,
# not an inventory of every include
function test_the_scan_is_silent_on_a_clean_config() {
  local dir
  dir="$_HI_WORKDIR/lint-clean"
  mkdir -p "$dir"
  printf 'set number\nruntime! plugin/sensible.vim\n' >"$dir/vim.rc"
  printf '(require (quote cl-lib))\n(setq tab-width 2)\n' >"$dir/emacs.el"
  [ -z "$(_hi_lint_vars "$dir" _hi_include_lint)" ]
}

# the dialect comes from the member, not the path: doctor reads ~/.vimrc under
# its own name, and a name that matched no dialect used to report nothing
function test_the_scan_reads_an_rc_under_its_own_name() {
  local dir out
  dir="$_HI_WORKDIR/lint-dotname"
  mkdir -p "$dir"
  printf 'source ~/.vim/extra.vim\n' >"$dir/.vimrc"
  out="$(_HI_CONFIG_DIR="$dir" _HI_VIMRC="$dir/.vimrc" _hi_include_lint | cut -d'|' -f1,2,3)"
  [ "$out" = "vim.rc|1|include" ] || {
    _hi_cecho " | the scan reported: [$out]" "$RED"
    return 1
  }
}

# A shell finding cannot be commented out whole: that empties a then/do body,
# which does not parse. Only the verb and its file word become `:`, so the
# guard, the if, the case arm, and the `&& echo` all survive; a path that
# rides along ($_HI_CONFIG_DIR, $_HI_ROOT), a process substitution, a word
# that merely contains a dot, and a line under `# hi-allow` are left alone.
function test_shell_includes_are_neutralized_and_still_parse() {
  local dir out
  dir="$(_hi_lint_fixture sh bash.sh 'export A=1
[ -f ~/.secrets ] && . ~/.secrets
source "${_HI_CONFIG_DIR}/colors"
if [ -f /etc/bashrc ]; then
  . /etc/bashrc
fi
source "$(brew --prefix)/share/fzf/key-bindings.bash" && echo ok
case $x in a) . ~/a ;; esac
source <(kubectl completion bash)
find . -name foo
# hi-allow
source ~/.kept
zinit light zsh-users/zsh-autosuggestions
')"
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat bash.sh)"
  [ "$out" = 'export A=1
[ -f ~/.secrets ] && :
source "${_HI_CONFIG_DIR}/colors"
if [ -f /etc/bashrc ]; then
:
fi
: && echo ok
case $x in a) : ;; esac
source <(kubectl completion bash)
find . -name foo
source ~/.kept
: zinit light zsh-users/zsh-autosuggestions' ] || {
    _hi_cecho " | bash.sh arrived as: [$out]" "$RED"
    return 1
  }
  printf '%s\n' "$out" | bash -n
}

# fish has no `:`, so its stand-in is `true`
function test_fish_includes_become_true() {
  local dir out
  dir="$(_hi_lint_fixture fish config.fish 'source ~/.config/fish/local.fish
if test -f ~/x.fish; source ~/x.fish; end
status is-interactive; and source (starship init fish | psub)
fisher install jorgebucaran/nvm.fish
')"
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat config.fish)"
  [ "$out" = 'true
if test -f ~/x.fish; true; end
status is-interactive; and source (starship init fish | psub)
true fisher install jorgebucaran/nvm.fish' ] || {
    _hi_cecho " | config.fish arrived as: [$out]" "$RED"
    return 1
  }
}

# tmux is line-oriented like vim, except that a finding ending in `\` takes
# its continuation with it; a `source-file` inside an if-shell string counts,
# and TPM is a plugin manager whether it is the @plugin list or its `run`
function test_tmux_includes_are_dropped_on_the_way_out() {
  local dir out
  dir="$(_hi_lint_fixture tmux tmux.conf 'set -g mouse on
source-file ~/.tmux/theme.conf
if-shell "test -f ~/.tmux.local" "source-file ~/.tmux.local"
bind r source-file ~/.tmux.conf \; \
  display "reloaded"
set -g @plugin "tmux-plugins/tpm"
set -g status-left "#S "
# hi-allow
source-file -q ~/.tmux.kept
run "~/.tmux/plugins/tpm/tpm"
')"
  out="$(_HI_TMUX_CONF="$dir/tmux.conf" _HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat tmux.conf)"
  [ "$out" = 'set -g mouse on
set -g status-left "#S "
source-file -q ~/.tmux.kept' ] || {
    _hi_cecho " | tmux.conf arrived as: [$out]" "$RED"
    return 1
  }
}

# micro's files ride under micro/ - micro fixes their names, so -config-dir
# names the directory - each from the overlay when it has one and from micro's
# own directory here otherwise; init.lua loses its plugin load, and keeps the
# `import` of micro's own package
function test_micro_config_rides_in_a_directory_of_its_own() {
  local h="$_HI_WORKDIR/tool-home/.config/micro" dir d
  mkdir -p "$h"
  printf '{"tabsize": 7}\n' >"$h/settings.json"
  printf '{"Alt-h": "home"}\n' >"$h/bindings.json"
  printf 'local config = import("micro/config")\n-- a comment\nconfig.AddRuntimeFile("mine", config.RTPlugin, "mine.lua")\n' >"$h/init.lua"
  dir="$_HI_WORKDIR/micro-overlay"
  mkdir -p "$dir/micro"
  printf '{"Alt-h": "overlay"}\n' >"$dir/micro/bindings.json"
  d="$(_hi_tool_home_unpacked "$dir")" || return 1
  [ "$(cd "$d/micro" && printf '%s ' *)" = "bindings.json init.lua settings.json " ] &&
    [ "$(cat "$d/micro/settings.json" "$d/micro/bindings.json" "$d/micro/init.lua")" = '{"tabsize": 7}
{"Alt-h": "overlay"}
local config = import("micro/config")' ] || {
    _hi_cecho " | micro/ arrived as: [$(cat "$d"/micro/* 2>&1)]" "$RED"
    return 1
  }
}

# the prompt frameworks' files and plugins.d's members are shell like the
# overlay's rc files, so a source of a file hi does not carry is neutralized in
# them too - except one under $OSH or $ZSH, the framework's own tree, which is
# on any target the theme is for
function test_framework_and_plugin_includes_are_neutralized() {
  local dir h="$_HI_WORKDIR/fw-home" out
  _hi_fw_home_fixture
  dir="$_HI_WORKDIR/lint-fw"
  mkdir -p "$dir/plugins.d"
  printf '. "$OSH/themes/base.theme.sh"\n. ~/.omb-mine\nPS1=x\n' >"$dir/omb-theme.sh"
  printf 'source ~/.p10k-local.zsh\n' >"$dir/p10k.zsh"
  printf 'export Y=1\n[ -f ~/.kube-extra ] && . ~/.kube-extra\n' >"$dir/plugins.d/10-kube"
  out="$(HOME="$h" _HI_PROMPT_TOOL="powerlevel10k oh-my-bash" _HI_CONFIG_DIR="$dir" _hi_include_lint | cut -d'|' -f1,2,3 | paste -sd, -)"
  [ "$out" = "p10k.zsh|1|include,omb-theme.sh|2|include,plugins.d/10-kube|2|include" ] || {
    _hi_cecho " | the scan reported: [$out]" "$RED"
    return 1
  }
  out="$(HOME="$h" _HI_PROMPT_TOOL="powerlevel10k oh-my-bash" _HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat plugins.d/10-kube)"
  [ "$out" = 'export Y=1
[ -f ~/.kube-extra ] && :' ] || {
    _hi_cecho " | plugins.d/10-kube arrived as: [$out]" "$RED"
    return 1
  }
  out="$(HOME="$h" _HI_PROMPT_TOOL="powerlevel10k oh-my-bash" _HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat omb-theme.sh)"
  [ "$out" = '. "$OSH/themes/base.theme.sh"
:
PS1=x' ]
}

# `hi-allow` in the file's own comment syntax keeps the next line as written
# and out of the report - the per-line answer to _HI_INCLUDES=keep
function test_hi_allow_keeps_the_next_line() {
  local dir out
  dir="$(_hi_lint_fixture allow vim.rc '" hi-allow
source ~/.vim/extra.vim
source ~/.vim/other.vim
')"
  out="$(_HI_VIMRC="$dir/vim.rc" _HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat vim.rc)"
  [ "$out" = 'source ~/.vim/extra.vim' ] &&
    [ "$(_hi_lint_vars "$dir" _hi_include_lint | cut -d'|' -f1,2)" = "vim.rc|3" ] || {
    _hi_cecho " | vim.rc arrived as: [$out]" "$RED"
    return 1
  }
}

function _hi_strip_unpack() {
  local dir="$_HI_WORKDIR/$1"
  [ -d "$dir" ] || {
    mkdir -p "$dir"
    _hi_payload_tar | tar -x -z -f - -C "$dir"
  }
  printf '%s' "$dir"
}

# Per file, skipping its own line 1: every shebang stays. Only hi.sh may have
# survivors, and only because its REMOTE heredocs are script the *target* runs -
# those bodies are deliberately not stripped.
function test_strip_leaves_no_full_line_comments() {
  local dir f rel n bad=0
  dir="$(_hi_strip_unpack stripped)"
  while IFS= read -r f; do
    rel="${f#"$dir/say-hi/"}"
    n="$(sed -n '2,$p' "$f" | grep -cE '^[[:space:]]*#' || true)"
    [ "$n" -eq 0 ] && continue
    if [ "$rel" = hi.sh ]; then
      # the heredoc bodies; a jump here means the strip started skipping files
      [ "$n" -le 8 ] && continue
    fi
    _hi_cecho " | $rel kept $n comment line(s) through the strip" "$RED"
    bad=1
  done < <(find "$dir/say-hi" -type f \( -name '*.sh' -o -name '*.zsh' -o -name '*.fish' \))
  [ "$bad" -eq 0 ]
}

# ...and stripping is all it does: every code line survives, its own leading
# whitespace aside (the strip takes indentation too - none of the four
# dialects reads it, and it is 3% of the payload), so both sides are compared
# with their indentation normalized away. That the *indented* lines a heredoc
# body owns are spared is the case below, not this one.
function test_strip_keeps_every_code_line() {
  local dir f rel bad=0
  dir="$(_hi_strip_unpack stripped)"
  while IFS= read -r f; do
    rel="${f#"$dir/say-hi/"}"
    [ -f "$_HI_ROOT/$rel" ] || continue
    diff <(grep -vE '^[[:space:]]*#|^$' "$_HI_ROOT/$rel" | sed 's/^[[:space:]]*//') \
      <(grep -vE '^[[:space:]]*#|^$' "$f" | sed 's/^[[:space:]]*//') >/dev/null || {
      _hi_cecho " | $rel lost or changed a code line" "$RED"
      bad=1
    }
  done < <(find "$dir/say-hi" -type f \( -name '*.sh' -o -name '*.zsh' -o -name '*.fish' \))
  [ "$bad" -eq 0 ]
}

# The two halves of the whitespace trim, on the file that has both: nothing
# blank and nothing indented survives *outside* a heredoc, and everything
# inside one is untouched - a target's `sh` reads those bodies as data, and
# `<<-` strips its own tabs there. hi.sh's own awk program is the fixture:
# its `  line = $0` sits inside `<<'"'"'AWK'"'"'` and is indented on purpose.
function test_strip_trims_whitespace_outside_heredocs() {
  local dir n
  dir="$(_hi_strip_unpack stripped)"
  n="$(grep -c '^[[:space:]]*$' "$dir/say-hi/common/core.sh" || true)"
  [ "$n" -eq 0 ] || {
    _hi_cecho " | core.sh kept $n blank line(s) through the strip" "$RED"
    return 1
  }
  n="$(grep -c '^[[:space:]]' "$dir/say-hi/common/core.sh" || true)"
  [ "$n" -eq 0 ] || {
    _hi_cecho " | core.sh kept $n indented line(s) through the strip" "$RED"
    return 1
  }
  grep -q '^  line = \$0$' "$dir/say-hi/hi.sh" || {
    _hi_cecho " | a heredoc body lost its indentation through the strip" "$RED"
    return 1
  }
}

function test_strip_leaves_valid_shell() {
  local dir f bad=0
  dir="$(_hi_strip_unpack stripped)"
  while IFS= read -r f; do
    bash -n "$f" 2>/dev/null || {
      _hi_cecho " | ${f##*/} does not parse after the strip" "$RED"
      bad=1
    }
  done < <(find "$dir/say-hi" -type f -name '*.sh')
  [ "$bad" -eq 0 ]
}

# a plain `mv` of the stripped copy would put mktemp's 0600 here, and the
# target's own probe tests `[ -x .../hi.sh ]` before it trusts a tree
function test_strip_keeps_hi_sh_executable() {
  local dir
  dir="$(_hi_strip_unpack stripped)"
  [ -x "$dir/say-hi/hi.sh" ]
}

function test_strip_spares_heredoc_bodies() {
  local dir
  dir="$(_hi_strip_unpack stripped)"
  grep -q 'passed to ssh unchanged' "$dir/say-hi/hi.sh"
}

# The data files' prose headers document the *installed* copies a user reads,
# so they ship stripped too: flags/colors/packages/nano.rc through the same
# `#` rule as the shell, vim.rc, emacs.el, and init.lua through their own
# rules for vim's `"`, elisp's `;`, and lua's `--`.
function test_strip_covers_the_data_files() {
  local dir f n bad=0
  dir="$(_hi_strip_unpack stripped)"
  for f in common/flags settings/colors settings/packages settings/nano.rc; do
    n="$(sed -n '2,$p' "$dir/say-hi/$f" | grep -cE '^[[:space:]]*#' || true)"
    [ "$n" -eq 0 ] || {
      _hi_cecho " | $f kept $n comment line(s) through the strip" "$RED"
      bad=1
    }
  done
  # the files with a comment character of their own: <file>:<char>
  for f in 'settings/vim.rc:"' 'settings/emacs.el:;' 'settings/init.lua:--'; do
    n="$(grep -cE "^[[:space:]]*${f#*:}" "$dir/say-hi/${f%%:*}" || true)"
    [ "$n" -eq 0 ] || {
      _hi_cecho " | ${f%%:*} kept $n comment line(s)" "$RED"
      bad=1
    }
  done
  [ "$bad" -eq 0 ]
}

# ...and stripping is all it does: every data line survives byte for byte
function test_strip_keeps_every_data_line() {
  local dir f bad=0
  dir="$(_hi_strip_unpack stripped)"
  for f in common/flags settings/colors settings/packages settings/nano.rc; do
    diff <(grep -vE '^[[:space:]]*#|^$' "$_HI_ROOT/$f" | sed 's/^[[:space:]]*//') \
      <(grep -vE '^[[:space:]]*#|^$' "$dir/say-hi/$f" | sed 's/^[[:space:]]*//') >/dev/null || {
      _hi_cecho " | $f lost or changed a data line" "$RED"
      bad=1
    }
  done
  for f in 'settings/vim.rc:"' 'settings/emacs.el:;' 'settings/init.lua:--'; do
    diff <(grep -vE "^[[:space:]]*${f#*:}|^$" "$_HI_ROOT/${f%%:*}" | sed 's/^[[:space:]]*//') \
      <(grep -vE "^[[:space:]]*${f#*:}|^$" "$dir/say-hi/${f%%:*}" | sed 's/^[[:space:]]*//') >/dev/null || {
      _hi_cecho " | ${f%%:*} lost or changed a line" "$RED"
      bad=1
    }
  done
  [ "$bad" -eq 0 ]
}

# _hi_tar_gz's fallback when gzip is absent: tar's own -z instead of piping
# through a second gzip process. A tar shim (rather than a real archive)
# isolates the branch choice from whether this box's tar can gzip on its own.
function test_tar_gz_falls_back_to_tars_own_z_without_gzip() {
  local bin="$_HI_WORKDIR/nogzip.bin" log="$_HI_WORKDIR/nogzip.tar.log"
  mkdir -p "$bin"
  cat >"$bin/tar" <<SHIM
#!/bin/sh
echo "\$*" >"$log"
exit 0
SHIM
  chmod +x "$bin/tar"
  PATH="$bin" _hi_tar_gz somefile >/dev/null 2>&1 || return 1
  case "$(cat "$log")" in '-c -z -f'*) ;; *) return 1 ;; esac
}

# ...and whether that fallback is worth taking is _hi_can_gzip's question:
# only libarchive's tar compresses in-process, GNU's and OpenBSD's run gzip
# off $PATH, so a shim answering each way is the whole predicate. gzip itself
# is checked first and never forks, which the third arm pins.
function test_can_gzip_reads_the_tar_it_has() {
  local bin="$_HI_WORKDIR/cangzip.bin" real
  real="$(type -P tar)"
  mkdir -p "$bin"
  printf '%s\n' '#!/bin/sh' 'exit 0' >"$bin/tar"
  chmod +x "$bin/tar"
  PATH="$bin" _hi_can_gzip || return 1
  printf '%s\n' '#!/bin/sh' 'exit 1' >"$bin/tar"
  PATH="$bin" _hi_can_gzip && return 1
  # gzip present: the answer is yes whatever that tar says
  printf '%s\n' '#!/bin/sh' 'exit 0' >"$bin/gzip"
  chmod +x "$bin/gzip"
  PATH="$bin" _hi_can_gzip || return 1
  [ -n "$real" ]
}

function run_hi_payload_tests() {
  _hi_workdir hipayloadtest

  _hi_suite_begin

  _hi_h1 "Testing hi.sh: the payload"

  _hi_h2 "Testing: the payload list"
  _hi_check "Ships exactly common/settings/load.sh" test_payload_ships_exactly_the_travelled_paths
  _hi_check "A default client ships everything" test_payload_ships_everything_by_default
  _hi_check "No toggle changes what ships" test_payload_always_ships_aliases

  _hi_h2 "Testing: the in-transit comment strip"
  _hi_check "No full-line comments survive" test_strip_leaves_no_full_line_comments
  _hi_check "Every code line survives" test_strip_keeps_every_code_line
  _hi_check "Blank lines and indentation go, heredoc bodies stay" test_strip_trims_whitespace_outside_heredocs
  _hi_check "The result is still valid shell" test_strip_leaves_valid_shell
  _hi_check "hi.sh stays executable" test_strip_keeps_hi_sh_executable
  _hi_check "Heredoc bodies are spared" test_strip_spares_heredoc_bodies
  _hi_check "The data-file headers strip too" test_strip_covers_the_data_files
  _hi_check "Every data line survives" test_strip_keeps_every_data_line

  _hi_h2 "Testing: the config overlay stream"
  _hi_check "Nothing sent without an overlay" test_overlay_is_empty_without_one
  _hi_check "Seen when present" test_overlay_is_seen_when_present
  _hi_check "Members are bare names" test_overlay_tar_members_are_bare_names
  _hi_check "Carries only what exists" test_overlay_tar_carries_only_what_exists
  _hi_check "aliases.sh rides the stream" test_overlay_tar_carries_aliases
  _hi_check "The stream is comment-stripped" test_overlay_strip_removes_comments
  _hi_check "the user's per-shell files ride the stream" test_overlay_tar_carries_shell_files
  _hi_check_capable symlink "Symlinked overlay files are dereferenced (Stow)" test_overlay_dereferences_symlinks
  _hi_check "Nothing outside the roster travels" test_overlay_sends_nothing_outside_the_roster
  _hi_check "packages.d members ride stripped, and nearly free" test_overlay_carries_package_groups
  _hi_check "plugins.d members ride stripped" test_overlay_carries_plugins
  _hi_check "The tool configs in force here ride along" test_overlay_carries_the_home_tool_configs
  _hi_check "...found through each tool's own variable" test_overlay_home_configs_follow_the_tools_variables
  _hi_check "...and an overlay copy wins" test_overlay_copy_of_a_tool_config_wins
  _hi_check "An overlay copy of a prompt framework's file wins" test_overlay_copy_of_a_prompt_framework_file_wins
  _hi_check "oh-my-posh's config rides from \$POSH_CONFIG, the rc, or the overlay" test_oh_my_posh_config_rides_from_home_or_overlay
  _hi_check "The prompt frameworks' home files ride, tide's lines alone" test_overlay_carries_the_prompt_frameworks_home_files
  _hi_check "micro's files ride under micro/, the overlay's copy first" test_micro_config_rides_in_a_directory_of_its_own
  _hi_check "Unset, the prompt programs are what home has" test_prompt_list_is_what_home_has

  _hi_h2 "Testing: the include scan"
  _hi_check "An unresolvable include is dropped" test_editor_includes_are_dropped_on_the_way_out
  _hi_check "...and =keep sends it as written" test_editor_includes_keep_sends_the_lines_as_written
  _hi_check "A lua finding takes its expression with it" test_a_dropped_expression_goes_out_whole
  _hi_check "A tmux finding takes its continuation with it" test_tmux_includes_are_dropped_on_the_way_out
  _hi_check "The editor config in force here rides along" test_the_editor_config_in_force_here_rides_the_stream
  _hi_check "...and hi's own tree copy does not" test_the_trees_own_editor_rc_is_not_streamed
  _hi_check "The scan reads every dialect" test_the_scan_reports_every_dialect
  _hi_check "A clean config is silent" test_the_scan_is_silent_on_a_clean_config
  _hi_check "An rc is read under its member name" test_the_scan_reads_an_rc_under_its_own_name
  _hi_check "A shell include becomes : and still parses" test_shell_includes_are_neutralized_and_still_parse
  _hi_check "A fish include becomes true" test_fish_includes_become_true
  _hi_check "Framework files and plugins.d are scanned as shell" test_framework_and_plugin_includes_are_neutralized
  _hi_check "hi-allow keeps the next line" test_hi_allow_keeps_the_next_line

  _hi_h2 "Testing: block padding (BSD tar)"
  _hi_check "The payload is not block-padded" test_payload_is_not_block_padded
  _hi_check "A small overlay is well under a block" test_overlay_is_well_under_one_block
  _hi_check_requires bsdtar "Payload unpadded under bsdtar" test_payload_is_not_block_padded_under_bsdtar
  _hi_check_requires bsdtar "Overlay unpadded under bsdtar" test_overlay_is_not_block_padded_under_bsdtar
  _hi_check "_hi_tar_gz falls back to tar's own -z without gzip" test_tar_gz_falls_back_to_tars_own_z_without_gzip
  _hi_check "_hi_can_gzip reads the tar it has" test_can_gzip_reads_the_tar_it_has

  _hi_h2 "Testing: the size hi reports"
  _hi_check "_hi_human_bytes matches du's shapes" test_human_bytes_matches_du_shapes
  _hi_check "The wire size isn't the disk size" test_wire_size_is_not_the_disk_size
  _hi_check "The payload stays under its 256KB tripwire" test_payload_stays_under_the_tripwire
  _hi_suite_end "hi.sh (the payload)"
}

run_hi_payload_tests
