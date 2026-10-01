#!/usr/bin/env bash
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

# _hi_overlay_tar, wrapped so a failed build says why: on Windows arm64 the
# stage has left an empty stream with no word of its own (gzip then reports
# "unexpected end of file"), and a verdict needs the exit status and stderr
# the pipe into _hi_tar_cat would otherwise lose
eval "$(declare -f _hi_overlay_tar | sed '1s/_hi_overlay_tar/_hi_overlay_tar_unwrapped/')"
function _hi_overlay_tar() {
  local err rc=0
  err="$(mktemp "$_HI_WORKDIR/overlay.err.XXXXXX")"
  _hi_overlay_tar_unwrapped "$@" 2>"$err" || rc=$?
  if [ "$rc" != 0 ] || [ -s "$err" ]; then
    _hi_cecho " | _hi_overlay_tar exited $rc; its stderr:" "$YELLOW" >&2
    sed 's/^/ |   /' "$err" >&2
  fi
  rm -f "$err"
  return "$rc"
}

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
  case "$listing" in *say-hi/config/colors*) ;; *)
    _hi_cecho " | a default client did not ship config/colors" "$RED"
    return 1
    ;;
  esac
  case "$listing" in *say-hi/config/packages*) ;; *)
    _hi_cecho " | a default client did not ship config/packages" "$RED"
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
  case "$listing" in *say-hi/common/aliases.sh*) return 0 ;; esac
  _hi_cecho " | every toggle off dropped common/aliases.sh, which carries the whole alias set" "$RED"
  return 1
}

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
  local dir="$_HI_WORKDIR/packages-overlay" out
  mkdir -p "$dir"
  printf '# a note\n[core]\nbat = ["batcat"]\n\n  # indented\n[core.unwanted]\nsudo = ["doas"]\n[core.required]\n"g++" = []\n' >"$dir/packages"
  [ "$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf - | paste -sd, -)" = packages ] || return 1
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat packages)"
  [ "$(printf '%s\n' "$out" | grep -v '^$')" = "$(printf '[core]\nbat = ["batcat"]\n[core.unwanted]\nsudo = ["doas"]\n[core.required]\n"g++" = []')" ] || {
    _hi_cecho " | packages arrived as: [$out]" "$RED"
    return 1
  }
}

# an extension rides as extensions/<name>, comment-stripped, and only the
# ones _hi_dir_member_ok admits (GLOSSARY: HI.59)
function test_overlay_carries_extensions() {
  local dir out
  dir="$_HI_WORKDIR/plugins"
  mkdir -p "$dir/extensions"
  printf '#!/bin/sh\n# a comment\nexport _HI_SEGMENT="printf x"\n' >"$dir/extensions/10-x"
  printf 'export Y=1\n' >"$dir/extensions/10-x.orig"
  [ "$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf - | paste -sd, -)" = extensions/10-x ] || return 1
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat extensions/10-x)"
  [ "$out" = '#!/bin/sh
export _HI_SEGMENT="printf x"' ] || {
    _hi_cecho " | extensions/10-x arrived as: [$out]" "$RED"
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
    unset STARSHIP_CONFIG EZA_CONFIG_DIR BAT_CONFIG_PATH BAT_CONFIG_DIR MICRO_CONFIG_HOME POSH_CONFIG POSH_THEME INPUTRC \
      RIPGREP_CONFIG_PATH FZF_DEFAULT_OPTS_FILE LG_CONFIG_FILE
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
  [ "$(cd "$d" && printf '%s ' *)" = "bat colors eza starship.toml wiring.sh " ] &&
    [ "$(cat "$d/starship.toml" "$d/eza/theme.yml" "$d/bat/config")" = "$(printf 'format = "home"\nfilekinds: home\n--theme=home')" ]
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
  [ "$(cat "$d/starship.toml" "$d/eza/theme.yml" "$d/bat/config")" = "$(printf 'format = "var"\nfilekinds: var\n--theme=var')" ]
}

# ripgrep's and fzf's config is wherever their variable says, and nowhere
# without it; lazygit's is its variable's, else its XDG file. Each rides
# only with its tool here.
function test_overlay_home_configs_of_the_cli_tools() {
  local o="$_HI_WORKDIR/cli-vars" dir d stubs lg="$_HI_WORKDIR/tool-home/.config/lazygit/config.yml"
  mkdir -p "$o" "${lg%/*}"
  printf -- '--smart-case\n' >"$o/rg"
  printf -- '--height=40%%\n' >"$o/fzf"
  printf 'gui:\n  theme: xdg\n' >"$lg"
  printf 'gui:\n  theme: var\n' >"$o/lg.yml"
  stubs="$(_hi_stub_tools rg fzf lazygit)"
  dir="$(_hi_overlay_fixture cli-empty)"
  d="$(_hi_tool_home_unpacked "$dir" PATH="$stubs:$PATH" RIPGREP_CONFIG_PATH="$o/rg" \
    FZF_DEFAULT_OPTS_FILE="$o/fzf")" || return 1
  [ "$(cat "$d/ripgreprc" "$d/fzfrc" "$d/lazygit/config.yml")" = "$(printf -- '--smart-case\n--height=40%%\ngui:\n  theme: xdg')" ] ||
    _hi_because "home: $(cat "$d"/* 2>&1)" || return 1
  d="$(_hi_tool_home_unpacked "$dir" PATH="$stubs:$PATH" LG_CONFIG_FILE="$o/lg.yml")" || return 1
  [ ! -e "$d/ripgreprc" ] && [ ! -e "$d/fzfrc" ] && [ "$(cat "$d/lazygit/config.yml")" = "$(printf 'gui:\n  theme: var')" ] ||
    _hi_because "variable: $(ls "$d")" || return 1
  rm -f "$lg"
  ! PATH="$_HI_WORKDIR/no-such-dir" _hi_tool_here ripgreprc || _hi_because "rg found on an empty PATH" || return 1
  ! PATH="$_HI_WORKDIR/no-such-dir" _hi_tool_here lazygit/config.yml || _hi_because "lazygit found on an empty PATH"
}

# an overlay copy wins over home's - and starship's still rides only with
# starship in the list, which is the only thing that starts it
function test_overlay_copy_of_a_tool_config_wins() {
  local dir d
  _hi_tool_home_fixture
  dir="$(_hi_overlay_fixture tool-copy bat/config eza/theme.yml starship.toml)"
  d="$(_hi_tool_home_unpacked "$dir")" || return 1
  [ "$(cat "$d/bat/config" "$d/eza/theme.yml" "$d/starship.toml")" = "$(printf 'x\nx\nx')" ] || return 1
  d="$(_hi_tool_home_unpacked "$dir" _HI_PROMPT_TOOL=hi)" || return 1
  [ "$(cat "$d/bat/config" "$d/eza/theme.yml")" = "$(printf 'x\nx')" ] && [ ! -e "$d/starship.toml" ]
}

# the prompt frameworks' files the same way: an overlay copy of each rides over
# the one home has (tide's still down to its tide_ lines)
function test_overlay_copy_of_a_prompt_framework_file_wins() {
  local dir d h="$_HI_WORKDIR/fw-home"
  _hi_fw_home_fixture
  dir="$_HI_WORKDIR/fw-copy"
  mkdir -p "$dir"
  printf 'POWERLEVEL9K_MODE=overlay\n' >"$dir/p10k.zsh"
  printf 'PROMPT=overlay\n' >"$dir/oh-my-zsh.zsh-theme"
  printf 'PS1=overlay\n' >"$dir/oh-my-bash.theme.sh"
  printf 'SETUVAR secret:x\nSETUVAR tide_character_icon:overlay\n' >"$dir/tide.vars"
  d="$(_hi_tool_home_unpacked "$dir" HOME="$h" XDG_CONFIG_HOME="$h/.config" \
    _HI_PROMPT_TOOL="powerlevel10k oh-my-zsh oh-my-bash tide")" || return 1
  [ "$(cat "$d/p10k.zsh" "$d/oh-my-zsh.zsh-theme" "$d/oh-my-bash.theme.sh" "$d/tide.vars")" = \
    "$(printf 'POWERLEVEL9K_MODE=overlay\nPROMPT=overlay\nPS1=overlay\nSETUVAR tide_character_icon:overlay')" ] || {
    _hi_cecho " | the stream carried: [$(cat "$d"/* 2>&1)]" "$RED"
    return 1
  }
}

# oh-my-posh has no default file: home's is the one $POSH_CONFIG names, else
# the one an rc's `oh-my-posh init ... --config` names, riding under the
# member its extension picks, its wiring.sh line beside it (GLOSSARY: HI.62).
# Any overlay copy outranks both, and an
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
  [ "$(cd "$d" && printf '%s ' *)" = "oh-my-posh.json wiring.sh " ] &&
    [ "$(cat "$d/oh-my-posh.json")" = "$(printf '{\n  "extends": "",\n  "version": 3\n}')" ] || {
    _hi_cecho " | from \$POSH_CONFIG: [$(cd "$d" && printf '%s ' *)] $(cat "$d"/* 2>&1)" "$RED"
    return 1
  }
  d="$(_hi_tool_home_unpacked "$dir" "$@")" || return 1
  [ "$(cd "$d" && printf '%s ' *)" = "oh-my-posh.yaml wiring.sh " ] &&
    [ "$(cat "$d/oh-my-posh.yaml")" = "$(cat "$h/rc.omp.yaml")" ] || {
    _hi_cecho " | from the rc: [$(cd "$d" && printf '%s ' *)]" "$RED"
    return 1
  }
  printf 'version = 3\n' >"$dir/oh-my-posh.toml"
  d="$(_hi_tool_home_unpacked "$dir" "$@" POSH_CONFIG="$h/mine.omp.json")" || return 1
  [ "$(cd "$d" && printf '%s ' *)" = "oh-my-posh.toml wiring.sh " ]
}

# The prompt frameworks' home half, each only with its name in the list:
# powerlevel10k's config, the theme file the rc's last ZSH_THEME / OSH_THEME
# names (oh-my-zsh's custom one over its stock copy), and of fish's universal
# variables the tide_ lines alone - never the rest, which can hold secrets.
# The .zshrc here names agnoster and never loads powerlevel10k, so the
# ~/.p10k.zsh beside it is the stale one _hi_p10k_in_use exists to ignore:
# every case that wants p10k on the list names it in $_HI_PROMPT_TOOL.
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
  [ "$(cd "$d" && printf '%s ' *)" = "colors oh-my-bash.theme.sh oh-my-zsh.zsh-theme p10k.zsh tide.vars " ] &&
    [ "$(cat "$d/p10k.zsh" "$d/oh-my-zsh.zsh-theme" "$d/oh-my-bash.theme.sh" "$d/tide.vars")" = \
      "$(printf 'typeset -g POWERLEVEL9K_MODE=home\nPROMPT=custom\nPS1=font\nSETUVAR tide_character_icon:\\u276f')" ] || return 1
  # unnamed, nothing rides; and powerlevel10k as oh-my-zsh's theme is no theme file
  d="$(_hi_tool_home_unpacked "$dir" "$@" _HI_PROMPT_TOOL=hi)" || return 1
  [ "$(cd "$d" && printf '%s' *)" = colors ] || {
    _hi_cecho " | unnamed, the stream carried: $(cd "$d" && printf '%s ' *)" "$RED"
    return 1
  }
  printf 'ZSH_THEME="powerlevel10k/powerlevel10k"\n' >"$_HI_WORKDIR/fw-home/.zshrc"
  d="$(_hi_tool_home_unpacked "$dir" "$@" _HI_PROMPT_TOOL=oh-my-zsh)" || return 1
  [ ! -e "$d/oh-my-zsh.zsh-theme" ]
}

# bash-it's theme is found where bash_it.sh's loader looks for a bare name:
# the custom themes dir ($BASH_IT_CUSTOM, else ~/.bash_it/custom) over the
# built-in one; oh-my-bash takes a .theme.bash where there is no .theme.sh
function test_overlay_carries_the_bash_it_theme_by_loader_order() {
  local h="$_HI_WORKDIR/bashit-home" dir d f
  mkdir -p "$h/.bash_it/themes/bobby" "$h/.bash_it/custom/themes/bobby" "$h/elsewhere/themes/bobby" "$h/.oh-my-bash/themes/font"
  printf 'export BASH_IT_THEME="bobby"\nOSH_THEME=font\n' >"$h/.bashrc"
  printf 'PS1=stock\n' >"$h/.bash_it/themes/bobby/bobby.theme.bash"
  printf 'PS1=custom\n' >"$h/.bash_it/custom/themes/bobby/bobby.theme.bash"
  printf 'PS1=elsewhere\n' >"$h/elsewhere/themes/bobby/bobby.theme.bash"
  printf 'PS1=font\n' >"$h/.oh-my-bash/themes/font/font.theme.bash"
  dir="$(_hi_overlay_fixture bashit-none colors)"
  d="$(_hi_tool_home_unpacked "$dir" HOME="$h" XDG_CONFIG_HOME="$h/.config" _HI_PROMPT_TOOL="bash-it oh-my-bash")" || return 1
  [ "$(cat "$d/bash-it.theme.bash" "$d/oh-my-bash.theme.sh")" = $'PS1=custom\nPS1=font' ] ||
    _hi_because "carried: $(cat "$d"/*.theme.* 2>&1)" || return 1
  f="$(unset BASH_IT_CUSTOM BASH_IT && HOME="$h" _hi_theme_home bash-it.theme.bash && echo)" || return 1
  [ "$f" = "$h/.bash_it/custom/themes/bobby/bobby.theme.bash" ] || _hi_because "default custom: [$f]" || return 1
  f="$(HOME="$h" BASH_IT_CUSTOM="$h/elsewhere" _hi_theme_home bash-it.theme.bash && echo)" || return 1
  [ "$f" = "$h/elsewhere/themes/bobby/bobby.theme.bash" ] || _hi_because "\$BASH_IT_CUSTOM: [$f]" || return 1
  rm -f "$h/.bash_it/custom/themes/bobby/bobby.theme.bash"
  f="$(unset BASH_IT_CUSTOM BASH_IT && HOME="$h" _hi_theme_home bash-it.theme.bash && echo)" || return 1
  [ "$f" = "$h/.bash_it/themes/bobby/bobby.theme.bash" ] || _hi_because "built-in: [$f]" || return 1
  rm -f "$h/.bash_it/themes/bobby/bobby.theme.bash"
  ! (unset BASH_IT_CUSTOM BASH_IT && HOME="$h" _hi_theme_home bash-it.theme.bash >/dev/null)
}

# Unset, a target is handed every prompt program this machine has, frameworks
# first - the list the members above are gated on, and what _hi_session_env
# ships; set, the setting as written; and a target passes its own along
# rather than looking. GLOSSARY: HI.32
function test_prompt_list_is_what_home_has() {
  local h="$_HI_WORKDIR/fw-home" p
  _hi_fw_home_fixture
  p="$(_hi_fake_path list-bins starship powerline-go)"
  # The fixture is the stale-config case: a ~/.p10k.zsh beside a .zshrc whose
  # ZSH_THEME is agnoster. p10k is not in use here, so it is not on the list -
  # each $( ) is its own subshell, so _hi_prompt_list's memo never carries
  # between these calls.
  # prefix assignments, not a subshell's exports: _hi_tool_home_unpacked's
  # own already are, and the linter tracks the two as one
  [ "$(HOME="$h" XDG_CONFIG_HOME="$h/.config" PATH="$p:$PATH" _HI_PROMPT_TOOL='' _hi_prompt_list)" = \
    "oh-my-zsh oh-my-bash starship powerline-go" ] &&
    [ "$(HOME="$h" _HI_PROMPT_TOOL="tide hi" _hi_prompt_list)" = "tide hi" ] &&
    [ "$(HOME="$h" _HI_PROMPT_TOOL="bash:starship hi" _hi_prompt_list)" = "bash:starship hi" ] &&
    [ "$(HOME="$h" XDG_CONFIG_HOME="$h/.config" PATH="$p:$PATH" _HI_PROMPT_TOOL="zsh:hi" _hi_prompt_list)" = \
      "zsh:hi oh-my-zsh oh-my-bash starship powerline-go" ] &&
    [ -z "$(HOME="$h" PATH="$p:$PATH" _HI_PROMPT_TOOL='' _HI_REMOTE_SESSION=1 _hi_prompt_list)" ] ||
    return 1
  # ...and it is, the moment the rc loads the theme rather than just its
  # config. Appended last: the fixture truncates .zshrc, so every other case
  # that calls it gets the unloaded rc back.
  printf 'source ~/powerlevel10k/powerlevel10k.zsh-theme\n' >>"$h/.zshrc"
  [ "$(HOME="$h" XDG_CONFIG_HOME="$h/.config" PATH="$p:$PATH" _HI_PROMPT_TOOL='' _hi_prompt_list)" = \
    "powerlevel10k oh-my-zsh oh-my-bash starship powerline-go" ]
}

# The payload is an allow list; this is its drift guard. Exact match on the
# list (so nothing sneaks on the wire unnoticed) plus an existence check on
# every member (so a rename can't quietly ship an empty payload).
function test_payload_ships_exactly_the_travelled_paths() {
  local m
  [ "${_HI_PAYLOAD[*]}" = "common config load.sh hi.sh" ] || {
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

# The payload only carries the *in-tree* config/, so once the user's real
# config/colors/packages live outside the tree they need their own stream or a
# target silently falls back to the shipped defaults. These assert the two
# halves that can be checked without a target: that nothing is sent when there
# is nothing to send, and that what is sent lands under the names paths.sh
# looks for.

function _hi_overlay_fixture() {
  local dir="$_HI_WORKDIR/$1"
  mkdir -p "$dir"
  shift
  for f in "$@"; do
    case "$f" in */*) mkdir -p "$dir/${f%/*}" ;; esac
    printf 'x\n' >"$dir/$f"
  done
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
  [ "$(_HI_PLUGINS_OFF=mux _HI_CONFIG_DIR="$dir" _hi_overlay_files | tr '\n' ' ')" = "vim/vimrc nvim/init.lua helix/config.toml helix/languages.toml " ] ||
    _hi_because "with mux off: $(_HI_PLUGINS_OFF=mux _HI_CONFIG_DIR="$dir" _hi_overlay_files | tr '\n' ' ')"
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
  d="$(_hi_tool_home_unpacked "$dir" PATH="$stubs:$PATH")" || return 1
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

# a plugin that is switched off sends nothing: $_HI_PLUGINS_OFF names it, its
# group, or the member, a row of the user's own by its own group too - and
# never one of hi's own files, which only their toggles switch (GLOSSARY:
# HI.64)
function test_plugin_off_keeps_its_members_home() {
  local dir
  dir="$(_hi_overlay_fixture plugins-off colors vim/vimrc nano/nanorc tmux/tmux.conf bat/config lazygit/config.yml mine.rc)"
  mkdir -p "$dir/micro"
  printf '{}\n' >"$dir/micro/settings.json"
  printf '[mine.mine]\ntool = "-"\nwire = "env:MINE"\nhome = "/etc/mine"\nfiles = "mine.rc"\n' >"$dir/plugins"
  [ "$(_HI_PLUGINS_OFF="lazygit editors" _HI_CONFIG_DIR="$dir" _hi_overlay_files | tr '\n' ' ')" = "colors bat/config tmux/tmux.conf mine.rc " ] ||
    _hi_because "a plugin and a group off: $(_HI_PLUGINS_OFF="lazygit editors" _HI_CONFIG_DIR="$dir" _hi_overlay_files | tr '\n' ' ')" || return 1
  [ "$(_HI_PLUGINS_OFF="mux,cli,mine,nano/nanorc" _HI_CONFIG_DIR="$dir" _hi_overlay_files | tr '\n' ' ')" = "colors vim/vimrc micro/settings.json " ] ||
    _hi_because "commas, a member, a group of the user's: $(_HI_PLUGINS_OFF="mux,cli,mine,nano/nanorc" _HI_CONFIG_DIR="$dir" _hi_overlay_files | tr '\n' ' ')" || return 1
  [ "$(_HI_PLUGINS_OFF="colors settings.sh" _HI_CONFIG_DIR="$dir" _hi_overlay_files | grep -c -x colors)" = 1 ] ||
    _hi_because "one of hi's own was switched off" || return 1
  # one file of a directory member, by its own name: the rest of it rides
  mkdir -p "$dir/extensions"
  printf 'export A=1\n' >"$dir/extensions/10-a"
  printf 'export B=1\n' >"$dir/extensions/20-b"
  [ "$(_HI_PLUGINS_OFF="extensions/10-a editors cli mux mine" _HI_CONFIG_DIR="$dir" _hi_overlay_files | tr '\n' ' ')" = "colors extensions/20-b " ] ||
    _hi_because "one extension off: $(_HI_PLUGINS_OFF="extensions/10-a editors cli mux mine" _HI_CONFIG_DIR="$dir" _hi_overlay_files | tr '\n' ' ')" || return 1
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
# or shell fails, not hi. pack.sh's _hi_lint_awk reads every dialect; these pin
# what it drops, what it deliberately leaves alone, that a lua or elisp
# finding takes its whole expression with it rather than leaving a stray
# brace, and that a shell finding leaves the file parseable.
# GLOSSARY: HI.57

# _hi_lint_fixture <name> <member> <body> - an overlay holding one editor rc.
function _hi_lint_fixture() {
  local dir="$_HI_WORKDIR/lint-$1"
  mkdir -p "$dir"
  case "$2" in */*) mkdir -p "$dir/${2%/*}" ;; esac
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
  dir="$(_hi_lint_fixture drop vim/vimrc "$_HI_LINT_VIMRC")"
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat vim/vimrc)"
  [ "$out" = 'set nocompatible
source $VIMRUNTIME/defaults.vim
runtime! plugin/sensible.vim
set number' ] || {
    _hi_cecho " | vim/vimrc arrived as: [$out]" "$RED"
    return 1
  }
}

# lua and elisp are not line-oriented: commenting only the line that matched
# would leave `})` behind and the file would not parse at all, which is worse
# than the include it was fixing
function test_a_dropped_expression_goes_out_whole() {
  local dir out
  dir="$(_hi_lint_fixture whole nvim/init.lua 'vim.opt.number = true
require("lazy").setup({
  { "tpope/vim-surround" },
})
vim.opt.tabstop = 2
')"
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat nvim/init.lua)"
  [ "$out" = 'vim.opt.number = true
vim.opt.tabstop = 2' ] || {
    _hi_cecho " | nvim/init.lua arrived as: [$out]" "$RED"
    return 1
  }
}

# neovim 0.12's own manager clones into the target's data dir on the first
# start, and older nvims warn on every one: reported as a plugin and dropped
# whole, like lazy's setup above
function test_vim_pack_add_is_a_plugin_finding() {
  local dir out
  dir="$(_hi_lint_fixture pack nvim/init.lua 'vim.opt.number = true
vim.pack.add({
  "https://github.com/tpope/vim-surround",
  { src = "https://github.com/nvim-lua/plenary.nvim" },
})
vim.opt.tabstop = 2
')"
  out="$(_HI_CONFIG_DIR="$dir" _hi_include_lint | cut -d'|' -f1-3)"
  [ "$out" = 'nvim/init.lua|2|plugin' ] || {
    _hi_cecho " | reported: [$out]" "$RED"
    return 1
  }
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat nvim/init.lua)"
  [ "$out" = 'vim.opt.number = true
vim.opt.tabstop = 2' ] || {
    _hi_cecho " | nvim/init.lua arrived as: [$out]" "$RED"
    return 1
  }
}

# the editor rc in force on this machine rides the stream the way the tool
# configs above do, from where its row's home column finds it: there is one
# copy to edit and no duplicate in the overlay to keep in step
function test_the_editor_config_in_force_here_rides_the_stream() {
  local dir="$_HI_WORKDIR/lint-in-force" home="$_HI_WORKDIR/in-force-home" p
  mkdir -p "$dir" "$home"
  printf 'set number\n' >"$home/.vimrc"
  p="$(_hi_fake_path in-force-bins vim):$PATH"
  [ "$(HOME="$home" PATH="$p" _HI_CONFIG_DIR="$dir" _hi_overlay_files vim/vimrc)" = vim/vimrc ] &&
    [ "$(HOME="$home" PATH="$p" _HI_CONFIG_DIR="$dir" _hi_overlay_tar vim/vimrc | _hi_tar_cat vim/vimrc)" = "set number" ]
}

# ...in the tool's own order of precedence, each place answering once the
# ones before it are gone, screen's following $SCREENRC even to a file that
# is not there
function test_a_home_config_is_found_in_its_tools_order() {
  local home="$_HI_WORKDIR/order-home" dir="$_HI_WORKDIR/order-overlay" p f m out
  local places="vim/vimrc:.vimrc vim/vimrc:.vim/vimrc vim/vimrc:.config/vim/vimrc nvim/init.lua:.config/nvim/init.lua
    helix/config.toml:.config/helix/config.toml helix/languages.toml:.config/helix/languages.toml nano/nanorc:.nanorc nano/nanorc:.config/nano/nanorc
    emacs/init.el:.emacs.el emacs/init.el:.emacs emacs/init.el:.emacs.d/init.el emacs/init.el:.config/emacs/init.el
    tmux/tmux.conf:.tmux.conf tmux/tmux.conf:.config/tmux/tmux.conf screenrc:.screenrc"
  mkdir -p "$dir"
  p="$(_hi_fake_path order-bins vim nvim hx nano emacs tmux screen):$PATH"
  set -- HOME="$home" XDG_CONFIG_HOME="$home/.config" _HI_XDG_CONFIG="$home/.config" PATH="$p" _HI_CONFIG_DIR="$dir"
  for f in $places; do
    f="$home/${f#*:}"
    mkdir -p "${f%/*}" && printf 'x\n' >"$f" || return 1
  done
  for f in $places; do
    m="${f%%:*}" f="$home/${f#*:}"
    out="$(env "$@" bash -c 'm="$1" && set -- && source "$_HI_LAUNCHER" && _hi_overlay_src "$m" o && printf %s "$o"' _ "$m")"
    [ "$out" = "$f" ] || _hi_because "$m: [$out], wanted $f" || return 1
    rm -f "$f"
  done
  printf 'x\n' >"$home/.screenrc"
  printf 'x\n' >"$home/named"
  out="$(env "$@" SCREENRC="$home/named" bash -c 'set -- && source "$_HI_LAUNCHER" && _hi_overlay_src screenrc o && printf %s "$o"')"
  [ "$out" = "$home/named" ] || _hi_because "\$SCREENRC: [$out]" || return 1
  ! env "$@" SCREENRC="$home/missing" bash -c 'set -- && source "$_HI_LAUNCHER" && _hi_overlay_src screenrc' ||
    _hi_because "a \$SCREENRC naming no file fell back to ~/.screenrc"
}

# ...only with the editor here to read it: a ~/.vimrc on a box with no vim is
# not a config in force anywhere. A copy in the overlay is the user saying
# "targets get this", and rides whatever this machine has. $PATH is an empty
# directory, which _hi_overlay_src's builtins never notice.
function test_a_home_config_needs_its_tool_here() {
  local dir="$_HI_WORKDIR/gate-overlay" home="$_HI_WORKDIR/gate-home" none="$_HI_WORKDIR/gate-nopath" p out=""
  mkdir -p "$dir" "$home" "$none"
  printf 'set number\n' >"$home/.vimrc"
  printf 'set -g mouse on\n' >"$home/.tmux.conf"
  p="$(_hi_fake_path gate-bins vim)"
  ! HOME="$home" PATH="$none" _HI_CONFIG_DIR="$dir" _hi_overlay_src vim/vimrc || return 1
  ! HOME="$home" PATH="$none" _HI_CONFIG_DIR="$dir" _hi_overlay_src tmux/tmux.conf || return 1
  HOME="$home" PATH="$p" _HI_CONFIG_DIR="$dir" _hi_overlay_src vim/vimrc out && [ "$out" = "$home/.vimrc" ] || return 1
  mkdir -p "$dir/vim"
  printf 'set ruler\n' >"$dir/vim/vimrc"
  HOME="$home" PATH="$none" _HI_CONFIG_DIR="$dir" _hi_overlay_src vim/vimrc out && [ "$out" = "$dir/vim/vimrc" ]
}

# One copy of a file the overlay and the tree both hold: a member that
# shadows its tree default (common/paths.sh's cascade) cuts that default from
# the payload. aliases.sh is additive and cuts nothing, and a file still
# under a pre-1.0 name is no
# member, so the default it no longer overrides keeps riding.
function test_a_shadowed_tree_default_is_cut_from_the_payload() {
  # shellcheck disable=SC2153 # core.sh's derived roster, not a typo of the setting
  local dir="$_HI_WORKDIR/excl" listing _HI_PROMPT_TOOL="$_HI_PROMPT_TOOLS"
  local -a payload_excl=() members=()
  mkdir -p "$dir"
  printf '[hosttag]\nx = "red"\n' >"$dir/colors"
  printf '[core]\ngit = []\n' >"$dir/packages"
  printf 'alias a=b\n' >"$dir/aliases.sh"
  printf 'set ruler\n' >"$dir/nano.rc"
  _hi_read_lines members < <(_HI_CONFIG_DIR="$dir" _hi_overlay_files)
  _hi_payload_excl "${members[@]}"
  [ "${payload_excl[*]}" = "say-hi/config/colors say-hi/config/packages" ] || {
    _hi_cecho " | cut: [${payload_excl[*]}]" "$RED"
    return 1
  }
  listing="$(_hi_payload_tar | tar tzf -)"
  [[ "$listing" != *config/colors* && "$listing" != *config/packages* ]] &&
    [[ "$listing" == *common/aliases.sh* ]] || return 1
  [ "$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf - | grep -c '^colors$')" = 1 ]
}

# with the header off no target draws one, so header.sh, the tree's package
# list, and the overlay's copy of it all stay home; under _HI_DISABLE_LOCAL=1
# only a line of settings.sh's own says so
function test_header_off_keeps_the_header_home() {
  local dir="$_HI_WORKDIR/excl-header" listing _HI_PROMPT_TOOL="$_HI_PROMPT_TOOLS"
  local -a payload_excl=()
  mkdir -p "$dir"
  printf '[core]\ngit = []\n' >"$dir/packages"
  printf '#!/bin/sh\n' >"$dir/local.sh"
  printf '#!/bin/sh\nexport _HI_DISABLE_HEADER=1\n' >"$dir/local-off.sh"
  [ -z "$(_HI_DISABLE_HEADER=1 _HI_CONFIG_DIR="$dir" _hi_overlay_files)" ] ||
    _hi_because "the overlay's packages rode" || return 1
  _HI_DISABLE_HEADER=1 _hi_payload_excl
  [ "${payload_excl[*]}" = "say-hi/common/header.sh say-hi/config/packages" ] ||
    _hi_because "cut: [${payload_excl[*]}]" || return 1
  listing="$(_hi_payload_tar | tar tzf -)"
  [[ "$listing" != *common/header.sh* && "$listing" != *config/packages* && "$listing" == *common/core.sh* ]] ||
    _hi_because "the tree still carries the header" || return 1
  _HI_DISABLE_LOCAL=1 _HI_DISABLE_HEADER=1 _HI_SETTINGS="$dir/local.sh" _hi_payload_excl
  [ -z "${payload_excl[*]-}" ] || _hi_because "local only cut the header" || return 1
  _HI_DISABLE_LOCAL=1 _HI_DISABLE_HEADER=1 _HI_SETTINGS="$dir/local-off.sh" _hi_payload_excl
  [ "${payload_excl[*]}" = "say-hi/common/header.sh say-hi/config/packages" ] ||
    _hi_because "settings.sh's own line kept the header: [${payload_excl[*]-}]"
}

# ...and only there: _hi_wire_bytes and `hi --doctor` hold no $payload_excl,
# so the figure the badge tracks is the stock tree whatever overlay is present
function test_the_payload_is_whole_without_a_cut_list() {
  local dir="$_HI_WORKDIR/excl-none"
  mkdir -p "$dir"
  printf '[hosttag]\nx = "red"\n' >"$dir/colors"
  [[ "$(_HI_CONFIG_DIR="$dir" _hi_payload_tar | tar tzf -)" == *say-hi/config/colors* ]]
}

# the plugins rows are the packer's alone to read, and it never rides: the
# tree's file is cut from every payload, and the overlay's is no member
function test_the_plugins_rows_stay_home() {
  local dir="$_HI_WORKDIR/rows-home" listing
  mkdir -p "$dir"
  printf '[mine.mine]\ntool = "-"\nwire = "env:MINE"\nhome = "/etc/mine"\nfiles = "mine.rc"\n' >"$dir/plugins"
  printf 'x\n' >"$dir/mine.rc"
  [ -f "$_HI_ROOT/config/plugins" ] || return 1
  listing="$(_hi_payload_tar | tar tzf -)"
  [[ "$listing" != *config/plugins* && "$listing" == *config/colors* ]] ||
    _hi_because "the tree's rows rode" || return 1
  [ "$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf - | sort | paste -sd, -)" = "mine.rc,wiring.sh" ] ||
    _hi_because "the overlay's rows rode: $(_HI_CONFIG_DIR="$dir" _hi_overlay_files | tr '\n' ' ')"
}

# a framework's prompt loader rides only to a target handed that framework:
# none with starship alone, the one named beside it, and each name the cut
# gives is a file of the tree
function test_a_prompt_loader_rides_only_where_handed() {
  local listing f
  local -a payload_excl=()
  _HI_PROMPT_TOOL=starship _hi_payload_excl
  [ "${payload_excl[*]}" = "say-hi/common/fw_powerlevel10k.zsh say-hi/common/fw_oh-my-zsh.zsh say-hi/common/fw_oh-my-bash.sh say-hi/common/fw_bash-it.sh say-hi/common/fw_tide.fish" ] ||
    _hi_because "cut: [${payload_excl[*]}]" || return 1
  for f in "${payload_excl[@]}"; do
    [ -f "$_HI_HOME/$f" ] || _hi_because "the cut names $f, which the tree lacks" || return 1
  done
  listing="$(_hi_payload_tar | tar tzf -)"
  [[ "$listing" != *common/fw_* && "$listing" == *common/bash.sh* ]] ||
    _hi_because "a loader rode with starship alone" || return 1
  _HI_PROMPT_TOOL="oh-my-zsh starship" _hi_payload_excl
  [[ ${#payload_excl[@]} = 4 && " ${payload_excl[*]} " != *" say-hi/common/fw_oh-my-zsh.zsh "* ]] ||
    _hi_because "handed oh-my-zsh, cut: [${payload_excl[*]}]"
}

# the cut list is the members paths.sh resolves overlay-over-tree, no more:
# each has a tree default and a $_HI_CONFIG_DIR guard there
function test_the_shadow_roster_matches_paths_sh() {
  local f
  for f in $_HI_OVERLAY_SHADOWS; do
    if ! [ -e "$_HI_ROOT/config/$f" ] || ! grep -q "^\[ -[fd] \"\$_HI_CONFIG_DIR/$f\" ] && export" "$_HI_ROOT/common/paths.sh"; then
      _hi_cecho " | $f is in _HI_OVERLAY_SHADOWS without a tree default and an overlay guard in paths.sh" "$RED"
      return 1
    fi
  done
  for f in "$_HI_ROOT"/config/*; do
    case "${f##*/}" in aliases.sh | plugins) continue ;; esac
    case "$_HI_OVERLAY_SHADOWS" in *" ${f##*/} "*) ;; *) return 1 ;; esac
  done
}

# The tag map a relayed hop colors by: the `# Tags:` lines of ~/.ssh/config
# and the files it Includes, with the Host or Match line each sits over, and
# none of the block - no HostName, no User, no untagged host.
function test_ssh_tags_is_cut_from_the_ssh_config() {
  local dir="$_HI_WORKDIR/tags" out
  mkdir -p "$dir/overlay" "$dir/rt" "$dir/.ssh/conf.d"
  printf '# Tags: inc\nHost included\n' >"$dir/.ssh/conf.d/01"
  printf '%s\n' '# Tags: prod, web' 'Host web1 web2' '  HostName 10.0.0.1' '  User deploy' '' \
    'Host plain' '  HostName 10.0.0.2' '# tags=lab' '# a note' 'Match host lab-* user x' \
    '# Tags: orphan' 'Include conf.d/*' 'Host after-include' >"$dir/config"
  out="$(HOME="$dir" XDG_RUNTIME_DIR="$dir/rt" _HI_SSH_CONFIG="$dir/config" _HI_CONFIG_DIR="$dir/overlay" _hi_overlay_tar | _hi_tar_cat ssh_tags)"
  [ "$out" = '# Tags: prod, web
Host web1 web2
# tags=lab
Match host lab-* user x
# Tags: inc
Host included' ] || {
    _hi_cecho " | ssh_tags arrived as: [$out]" "$RED"
    return 1
  }
  printf 'Host untagged\n' >"$dir/config"
  ! XDG_RUNTIME_DIR="$dir/rt" _HI_SSH_CONFIG="$dir/config" _HI_CONFIG_DIR="$dir/overlay" _hi_overlay_src ssh_tags
}

# _hi_tags_at <dir> - _hi_ssh_tags_file's answer against <dir>/config with
# <dir>/rt as the runtime dir: the cut's contents, or `rc <n>`
function _hi_tags_at() {
  local f="" rc=0
  XDG_RUNTIME_DIR="$1/rt" _HI_SSH_CONFIG="$1/config" _hi_ssh_tags_file ssh_tags f || rc=$?
  [ "$rc" = 0 ] && cat "$f" || printf 'rc %s' "$rc"
}

# the cut is kept in the runtime dir and reused while it is newer than the
# config; an older one is recut, and a config with an Include is recut every
# time, since the Included files have mtimes of their own
function test_ssh_tags_cut_is_reused_until_the_config_is_newer() {
  local dir="$_HI_WORKDIR/tags-cache" cut
  mkdir -p "$dir/rt" "$dir/.ssh"
  printf '# Tags: one\nHost a\n' >"$dir/config"
  touch -t 202001010000 "$dir/config"
  [ "$(_hi_tags_at "$dir")" = $'# Tags: one\nHost a' ] || return 1
  cut="$dir/rt/hi.ssh_tags"
  printf '# Tags: kept\nHost a\n' >"$cut"
  touch -t 202001020000 "$cut"
  [ "$(_hi_tags_at "$dir")" = $'# Tags: kept\nHost a' ] || _hi_because "a newer cut was not reused" || return 1
  touch -t 202001030000 "$dir/config"
  [ "$(_hi_tags_at "$dir")" = $'# Tags: one\nHost a' ] || _hi_because "an older cut was not recut" || return 1
  printf '# Tags: inc\nHost b\n' >"$dir/.ssh/extra"
  printf 'Include extra\n' >>"$dir/config"
  touch -t 202001030000 "$dir/config"
  touch -t 202001040000 "$cut"
  [ "$(HOME="$dir" _hi_tags_at "$dir")" = $'# Tags: one\nHost a\n# Tags: inc\nHost b' ] ||
    _hi_because "a config with an Include was not recut"
}

# a config with no tag makes no cut, and a runtime dir the cut cannot be
# written into fails cleanly, leaving no temp file behind
function test_ssh_tags_fails_cleanly_without_a_tag_or_a_writable_dir() {
  local dir="$_HI_WORKDIR/tags-fail" out
  mkdir -p "$dir/rt"
  printf 'Host untagged\n' >"$dir/config"
  [ "$(_hi_tags_at "$dir")" = "rc 1" ] || return 1
  rm -f "$dir/rt"/hi.ssh_tags*
  printf '# Tags: one\nHost a\n' >"$dir/config"
  chmod 555 "$dir/rt"
  out="$(_hi_tags_at "$dir" 2>/dev/null)"
  chmod 755 "$dir/rt"
  [ "$out" = "rc 1" ] && [ -z "$(find "$dir/rt" -name 'hi.ssh_tags*')" ] || _hi_because "read-only runtime dir: [$out]"
}

# the rows hi --doctor prints come from the same pass that does the dropping,
# so what the report names is exactly what went missing
function test_the_scan_reports_every_dialect() {
  local dir out
  dir="$_HI_WORKDIR/lint-report"
  mkdir -p "$dir"
  mkdir -p "$dir/vim" "$dir/nvim" "$dir/nano" "$dir/emacs" "$dir/kak" "$dir/tmux"
  printf 'source ~/.vim/extra.vim\n' >"$dir/vim/vimrc"
  printf 'dofile("/tmp/x.lua")\n' >"$dir/nvim/init.lua"
  printf 'include "~/.nano/mine.nanorc"\n' >"$dir/nano/nanorc"
  printf '(load "~/.emacs.d/mine.el")\n' >"$dir/emacs/init.el"
  printf 'source "%%val{runtime}/rc/x.kak"\nplug "andreyorst/fzf.kak"\nsource ~/mine.kak\n' >"$dir/kak/kakrc"
  printf 'source-file ~/.tmux/theme.conf\n' >"$dir/tmux/tmux.conf"
  mkdir -p "$dir/micro"
  printf 'config.AddRuntimeFile("mine", config.RTPlugin, "mine.lua")\n' >"$dir/micro/init.lua"
  printf '. ~/.secrets\n' >"$dir/settings.sh"
  printf 'source ~/.aliases.local\n' >"$dir/aliases.sh"
  printf 'x=1\n[ -f ~/.bash_local ] && . ~/.bash_local\n' >"$dir/bashrc"
  printf 'zinit light foo/bar\n' >"$dir/zshrc"
  printf 'source ~/.config/fish/local.fish\n' >"$dir/config.fish"
  out="$(_HI_CONFIG_DIR="$dir" _hi_include_lint | cut -d'|' -f1,2,3 | paste -sd, -)"
  # rows come in _HI_OVERLAY_FILES order: every member is scanned, and the
  # ones with no dialect (colors, packages) simply have nothing to say
  [ "$out" = "settings.sh|1|include,vim/vimrc|1|include,nvim/init.lua|1|include,nano/nanorc|1|include,emacs/init.el|1|include,kak/kakrc|2|plugin,kak/kakrc|3|include,micro/init.lua|1|plugin,aliases.sh|1|include,bashrc|2|include,zshrc|1|plugin,config.fish|1|include,tmux/tmux.conf|1|include" ] || {
    _hi_cecho " | the scan reported: [$out]" "$RED"
    return 1
  }
}

# /usr/share/nano is what the nano package itself ships, so an include
# directly under it resolves wherever nano does - a whole-directory glob or
# one stock syntax file. A *subdirectory* of it does not: /usr/share/nano/extra
# is a Debian split, and on Fedora, Alpine, or macOS nano answers the glob
# that matches nothing with "Mistakes in '<rcfile>'" and a bell, over the
# whole rcfile rather than that one line.
_HI_LINT_NANORC='include "/usr/share/nano/*.nanorc"
include "/usr/share/nano/sh.nanorc"
include "/usr/share/nano/extra/*.nanorc"
include "~/.nano/mine.nanorc"
# hi dropped: extendsyntax JSX linter eslint
set tabsize 4
'

function test_nano_keeps_the_stock_directory_and_drops_the_rest() {
  local dir out
  dir="$(_hi_lint_fixture nano nano/nanorc "$_HI_LINT_NANORC")"
  out="$(_HI_CONFIG_DIR="$dir" _hi_include_lint | cut -d'|' -f1,2,3 | paste -sd, -)"
  [ "$out" = "nano/nanorc|3|include,nano/nanorc|4|include" ] || {
    _hi_cecho " | the scan reported: [$out]" "$RED"
    return 1
  }
  # a dropped syntax include or extendsyntax keeps its comment through the
  # strip: load.sh's _hi_nano_fallback reads it on the target
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat nano/nanorc)"
  [ "$out" = 'include "/usr/share/nano/*.nanorc"
include "/usr/share/nano/sh.nanorc"
# hi dropped: include "/usr/share/nano/extra/*.nanorc"
# hi dropped: include "~/.nano/mine.nanorc"
# hi dropped: extendsyntax JSX linter eslint
set tabsize 4' ] || {
    _hi_cecho " | nano/nanorc arrived as: [$out]" "$RED"
    return 1
  }
}

# a config with nothing to resolve is silent - the scan is a report of danglers,
# not an inventory of every include
function test_the_scan_is_silent_on_a_clean_config() {
  local dir
  dir="$_HI_WORKDIR/lint-clean"
  mkdir -p "$dir"
  mkdir -p "$dir/vim" "$dir/emacs"
  printf 'set number\nruntime! plugin/sensible.vim\n' >"$dir/vim/vimrc"
  printf '(require (quote cl-lib))\n(setq tab-width 2)\n' >"$dir/emacs/init.el"
  [ -z "$(_HI_CONFIG_DIR="$dir" _hi_include_lint)" ]
}

# the dialect comes from the member, not the path: doctor reads ~/.vimrc under
# its own name, and a name that matched no dialect used to report nothing
function test_the_scan_reads_an_rc_under_its_own_name() {
  local dir out
  dir="$_HI_WORKDIR/lint-dotname"
  mkdir -p "$dir"
  printf 'source ~/.vim/extra.vim\n' >"$dir/.vimrc"
  out="$(HOME="$dir" PATH="$(_hi_fake_path dotname-bins vim):$PATH" _HI_CONFIG_DIR="$dir/overlay" _hi_include_lint | grep '^vim/vimrc|' | cut -d'|' -f1,2,3)"
  [ "$out" = "vim/vimrc|1|include" ] || {
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
  dir="$(_hi_lint_fixture sh bashrc 'export A=1
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
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat bashrc)"
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
    _hi_cecho " | bashrc arrived as: [$out]" "$RED"
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
  dir="$(_hi_lint_fixture tmux tmux/tmux.conf 'set -g mouse on
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
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat tmux/tmux.conf)"
  [ "$out" = 'set -g mouse on
set -g status-left "#S "
source-file -q ~/.tmux.kept' ] || {
    _hi_cecho " | tmux/tmux.conf arrived as: [$out]" "$RED"
    return 1
  }
}

# _hi_carry_home <name> - a home whose tmux directory holds a theme that
# sources a part of its own, and an overlay tmux.conf including both a file
# there and one that is not: the fixture of the carry cases below
function _hi_carry_home() {
  local h="$_HI_WORKDIR/carry-$1"
  mkdir -p "$h/.config/tmux/parts" "$h/overlay/tmux"
  printf 'set -g mouse on\nsource-file ~/.config/tmux/theme.conf\nsource-file $HOME/.config/tmux/gone.conf\n' >"$h/overlay/tmux/tmux.conf"
  printf '# the theme\nset -g @theme HI\nsource-file "${XDG_CONFIG_HOME}/tmux/parts/bar.conf"\n' >"$h/.config/tmux/theme.conf"
  printf 'set -g @bar HI\n' >"$h/.config/tmux/parts/bar.conf"
  printf '%s' "$h"
}

# an include naming a file under the tool's own directory rides beside the
# member, its path held for the target's overlay directory, and the file's
# own includes the same; one naming nothing there is dropped as ever
function test_an_include_under_the_tools_directory_rides() {
  local h d
  h="$(_hi_carry_home rides)"
  d="$(mktemp -d "$_HI_WORKDIR/carry-unpacked.XXXXXX")" || return 1
  HOME="$h" XDG_CONFIG_HOME="$h/.config" _HI_CONFIG_DIR="$h/overlay" _hi_overlay_tar tmux/tmux.conf |
    tar -x -z -f - -C "$d" || return 1
  [ "$(cat "$d/tmux/tmux.conf")" = "set -g mouse on
source-file $_HI_CARRY_TOKEN/tmux/theme.conf" ] || _hi_because "tmux.conf: [$(cat "$d/tmux/tmux.conf")]" || return 1
  [ "$(cat "$d/tmux/theme.conf")" = "set -g @theme HI
source-file \"$_HI_CARRY_TOKEN/tmux/parts/bar.conf\"" ] || _hi_because "theme.conf: [$(cat "$d/tmux/theme.conf")]" || return 1
  [ "$(cat "$d/tmux/parts/bar.conf")" = 'set -g @bar HI' ]
}

# the target's half: a real sh makes every held path the directory the
# overlay landed in
function test_a_carried_path_lands_on_the_target() {
  local d="$_HI_WORKDIR/carry-fixup/config"
  mkdir -p "$d/tmux"
  printf 'source-file %s/tmux/theme.conf\nset -g mouse on\n' "$_HI_CARRY_TOKEN" >"$d/tmux/tmux.conf"
  sh -c "$(_hi_overlay_fixup "'$d'")" || return 1
  [ "$(cat "$d/tmux/tmux.conf")" = "source-file $d/tmux/theme.conf
set -g mouse on" ] || _hi_because "after the fixup: [$(cat "$d/tmux/tmux.conf")]"
}

# hi --doctor names what is dropped and nothing the packer carries
function test_a_carried_include_is_no_finding() {
  local h out
  h="$(_hi_carry_home doctor)"
  out="$(HOME="$h" XDG_CONFIG_HOME="$h/.config" _HI_CONFIG_DIR="$h/overlay" _hi_include_lint)"
  [ "$out" = 'tmux/tmux.conf|3|include|source-file $HOME/.config/tmux/gone.conf' ] || _hi_because "rows: [$out]"
}

# the overlay cache keeps the carried files' list beside it, so an edit to
# one alone rebuilds it
function test_an_edit_to_a_carried_file_rebuilds_the_cache() {
  local h c1="" c2=""
  h="$(_hi_carry_home cache)"
  mkdir -p "$h/run"
  HOME="$h" XDG_CONFIG_HOME="$h/.config" _HI_CONFIG_DIR="$h/overlay" XDG_RUNTIME_DIR="$h/run" \
    _hi_overlay_cached c1 tmux/tmux.conf || return 1
  grep -qx "$h/.config/tmux/parts/bar.conf" "$c1.carry" || _hi_because "no carry list beside $c1" || return 1
  # dated ahead, so the edit is newer than the cache on any clock grain
  printf 'set -g @bar EDITED\n' >"$h/.config/tmux/parts/bar.conf"
  touch -t 203001010000 "$h/.config/tmux/parts/bar.conf"
  HOME="$h" XDG_CONFIG_HOME="$h/.config" _HI_CONFIG_DIR="$h/overlay" XDG_RUNTIME_DIR="$h/run" \
    _hi_overlay_cached c2 tmux/tmux.conf || return 1
  [ "$(_hi_tar_cat tmux/parts/bar.conf <"$c2")" = 'set -g @bar EDITED' ] || _hi_because "the cache kept the old carried file"
}

# micro's files ride under micro/ - micro fixes their names, so -config-dir
# names the directory - each from the overlay when it has one and from micro's
# own directory here otherwise; nvim/init.lua loses its plugin load, and keeps the
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

# the prompt frameworks' files and the extensions are shell like the
# overlay's rc files, so a source of a file hi does not carry is neutralized in
# them too - except one under $OSH or $ZSH, the framework's own tree, which is
# on any target the theme is for
function test_framework_and_extension_includes_are_neutralized() {
  local dir h="$_HI_WORKDIR/fw-home" out
  _hi_fw_home_fixture
  dir="$_HI_WORKDIR/lint-fw"
  mkdir -p "$dir/extensions"
  printf '. "$OSH/themes/base.theme.sh"\n. ~/.omb-mine\nPS1=x\n' >"$dir/oh-my-bash.theme.sh"
  printf 'source ~/.p10k-local.zsh\n' >"$dir/p10k.zsh"
  printf 'export Y=1\n[ -f ~/.kube-extra ] && . ~/.kube-extra\n' >"$dir/extensions/10-kube"
  out="$(HOME="$h" _HI_PROMPT_TOOL="powerlevel10k oh-my-bash" _HI_CONFIG_DIR="$dir" _hi_include_lint | cut -d'|' -f1,2,3 | paste -sd, -)"
  [ "$out" = "extensions/10-kube|2|include,p10k.zsh|1|include,oh-my-bash.theme.sh|2|include" ] || {
    _hi_cecho " | the scan reported: [$out]" "$RED"
    return 1
  }
  out="$(HOME="$h" _HI_PROMPT_TOOL="powerlevel10k oh-my-bash" _HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat extensions/10-kube)"
  [ "$out" = 'export Y=1
[ -f ~/.kube-extra ] && :' ] || {
    _hi_cecho " | extensions/10-kube arrived as: [$out]" "$RED"
    return 1
  }
  out="$(HOME="$h" _HI_PROMPT_TOOL="powerlevel10k oh-my-bash" _HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat oh-my-bash.theme.sh)"
  [ "$out" = '. "$OSH/themes/base.theme.sh"
:
PS1=x' ]
}

# ...and that pass is the theme's alone, for its own framework: an extension
# member runs on every target, $ZSH unset on most, and oh-my-zsh's theme has
# no business in $OSH - both are neutralized like any include
function test_a_framework_tree_passes_only_its_own_theme() {
  local dir h="$_HI_WORKDIR/fw-home" out
  _hi_fw_home_fixture
  dir="$_HI_WORKDIR/lint-fw-own"
  mkdir -p "$dir/extensions"
  printf 'source "$ZSH/lib/git.zsh"\nsource $OSH/lib/x.sh\n' >"$dir/oh-my-zsh.zsh-theme"
  printf 'source "$ZSH/lib/git.zsh"\n' >"$dir/extensions/10-omz"
  out="$(HOME="$h" _HI_PROMPT_TOOL=oh-my-zsh _HI_CONFIG_DIR="$dir" _hi_include_lint | cut -d'|' -f1,2,3 | paste -sd, -)"
  [ "$out" = "extensions/10-omz|1|include,oh-my-zsh.zsh-theme|2|include" ] || {
    _hi_cecho " | the scan reported: [$out]" "$RED"
    return 1
  }
}

# `hi-allow` in the file's own comment syntax keeps the next line as written
# and out of the report - for a file every target has
function test_hi_allow_keeps_the_next_line() {
  local dir out
  dir="$(_hi_lint_fixture allow vim/vimrc '" hi-allow
source ~/.vim/extra.vim
source ~/.vim/other.vim
')"
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat vim/vimrc)"
  [ "$out" = 'source ~/.vim/extra.vim' ] &&
    [ "$(_HI_CONFIG_DIR="$dir" _hi_include_lint | cut -d'|' -f1,2)" = "vim/vimrc|3" ] || {
    _hi_cecho " | vim/vimrc arrived as: [$out]" "$RED"
    return 1
  }
}

# `hi-quiet` is the other half: the next line is still dropped, only its
# report row goes - one directive under the other, so each is seen alone
function test_hi_quiet_drops_the_next_line_without_a_row() {
  local dir out
  dir="$(_hi_lint_fixture quiet vim/vimrc '" hi-quiet
source ~/.vim/extra.vim
" hi-allow
source ~/.vim/kept.vim
source ~/.vim/other.vim
')"
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat vim/vimrc)"
  [ "$out" = 'source ~/.vim/kept.vim' ] &&
    [ "$(_HI_CONFIG_DIR="$dir" _hi_include_lint | cut -d'|' -f1,2)" = "vim/vimrc|5" ] || {
    _hi_cecho " | vim/vimrc arrived as: [$out]" "$RED"
    return 1
  }
}

# `hi-quiet-start` to `hi-quiet-end` is `hi-quiet` over every line between
# them, so a guarded block of plugin lines takes one pair
function test_a_quiet_block_drops_its_lines_without_a_row() {
  local dir out
  dir="$(_hi_lint_fixture quiet-block vim/vimrc '" hi-quiet-start
source ~/.vim/extra.vim
call plug#begin()
packadd! matchit
call plug#end()
" hi-quiet-end
set number
source ~/.vim/other.vim
')"
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat vim/vimrc)"
  [ "$out" = 'set number' ] &&
    [ "$(_HI_CONFIG_DIR="$dir" _hi_include_lint | cut -d'|' -f1,2)" = "vim/vimrc|8" ] || {
    _hi_cecho " | vim/vimrc arrived as: [$out]" "$RED"
    return 1
  }
}

# ...and `hi-allow-start` to `hi-allow-end` is `hi-allow`: the block rides as
# written
function test_an_allow_block_keeps_its_lines() {
  local dir out
  dir="$(_hi_lint_fixture allow-block vim/vimrc '" hi-allow-start
source ~/.vim/extra.vim
packadd! matchit
" hi-allow-end
source ~/.vim/other.vim
')"
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat vim/vimrc)"
  [ "$out" = 'source ~/.vim/extra.vim
packadd! matchit' ] &&
    [ "$(_HI_CONFIG_DIR="$dir" _hi_include_lint | cut -d'|' -f1,2)" = "vim/vimrc|5" ] || {
    _hi_cecho " | vim/vimrc arrived as: [$out]" "$RED"
    return 1
  }
}

# a pair is read in each dialect's own comment syntax, and a quiet one takes
# a lua or elisp finding's whole expression with it; the vim pairs are the
# two cases above
function test_a_block_is_read_in_every_dialect() {
  local dir out
  dir="$(_hi_lint_fixture block-dialects nvim/init.lua '-- hi-quiet-start
require("lazy").setup({
  { "tpope/vim-surround" },
})
-- hi-quiet-end
-- hi-allow-start
require("mine")
-- hi-allow-end
dofile("/tmp/x.lua")
')"
  _hi_lint_fixture block-dialects emacs/init.el ';; hi-quiet-start
(use-package magit
  :ensure t)
;; hi-quiet-end
;; hi-allow-start
(load "~/.emacs.d/mine.el")
;; hi-allow-end
(load "~/x.el")
' >/dev/null
  _hi_lint_fixture block-dialects tmux/tmux.conf '# hi-quiet-start
set -g @plugin "tmux-plugins/tpm"
run ~/.tmux/plugins/tpm/tpm
# hi-quiet-end
# hi-allow-start
source-file ~/.tmux/theme.conf
# hi-allow-end
source-file ~/.tmux/other.conf
' >/dev/null
  _hi_lint_fixture block-dialects bashrc '# hi-quiet-start
[ -f ~/.hushed ] && . ~/.hushed
# hi-quiet-end
# hi-allow-start
. ~/.kept
# hi-allow-end
. ~/.secrets
' >/dev/null
  mkdir -p "$dir/zellij"
  _hi_lint_fixture block-dialects zellij/config.kdl '// hi-quiet-start
layout_dir "/x"
// hi-quiet-end
// hi-allow-start
theme_dir "/y"
// hi-allow-end
theme_dir "/z"
' >/dev/null
  out="$(_HI_CONFIG_DIR="$dir" _hi_include_lint | cut -d'|' -f1,2,3 | paste -sd, -)"
  [ "$out" = "nvim/init.lua|9|include,emacs/init.el|8|include,bashrc|7|include,tmux/tmux.conf|8|include,zellij/config.kdl|7|include" ] ||
    _hi_because "the scan reported: [$out]" || return 1
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat nvim/init.lua)"
  [ "$out" = 'require("mine")' ] || _hi_because "nvim/init.lua arrived as: [$out]" || return 1
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat emacs/init.el)"
  [ "$out" = '(load "~/.emacs.d/mine.el")' ] || _hi_because "emacs/init.el arrived as: [$out]" || return 1
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat tmux/tmux.conf)"
  [ "$out" = 'source-file ~/.tmux/theme.conf' ] || _hi_because "tmux/tmux.conf arrived as: [$out]" || return 1
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat bashrc)"
  [ "$out" = '[ -f ~/.hushed ] && :
. ~/.kept
:' ] || _hi_because "bashrc arrived as: [$out]"
}

# a start with no end of its own word below it decides nothing and is a row
# of its own, whether the file ends first or a second start of that word
# comes first; an end with no start is ignored
function test_an_unclosed_start_decides_nothing_and_is_reported() {
  local dir out
  dir="$(_hi_lint_fixture unclosed vim/vimrc '" hi-allow-start
source ~/.vim/extra.vim
" hi-quiet-end
" hi-allow-start
source ~/.vim/kept.vim
" hi-allow-end
" hi-quiet-start
source ~/.vim/other.vim
')"
  out="$(_HI_CONFIG_DIR="$dir" _hi_include_lint | paste -sd, -)"
  [ "$out" = 'vim/vimrc|1|unclosed|" hi-allow-start,vim/vimrc|2|include|source ~/.vim/extra.vim,vim/vimrc|7|unclosed|" hi-quiet-start,vim/vimrc|8|include|source ~/.vim/other.vim' ] ||
    _hi_because "the scan reported: [$out]" || return 1
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat vim/vimrc)"
  [ "$out" = 'source ~/.vim/kept.vim' ] || _hi_because "vim/vimrc arrived as: [$out]"
}

# `hi-allow` and `hi-quiet` still decide the one line under them, inside a
# pair too, and a pair's own words are not read as them: the stray end here
# keeps nothing
function test_a_single_marker_still_decides_one_line() {
  local dir out
  dir="$(_hi_lint_fixture single vim/vimrc '" hi-quiet-start
" hi-allow
source ~/.vim/kept.vim
source ~/.vim/hushed.vim
" hi-quiet-end
" hi-allow-end
source ~/.vim/extra.vim
" hi-quiet
source ~/.vim/quiet.vim
source ~/.vim/other.vim
')"
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat vim/vimrc)"
  [ "$out" = 'source ~/.vim/kept.vim' ] &&
    [ "$(_HI_CONFIG_DIR="$dir" _hi_include_lint | cut -d'|' -f1,2 | paste -sd, -)" = "vim/vimrc|7,vim/vimrc|10" ] || {
    _hi_cecho " | vim/vimrc arrived as: [$out]" "$RED"
    return 1
  }
}

# a line the file's own comment marker opens is no finding in any dialect:
# lua's -- and elisp's ; were the two the scan read through
function test_the_scan_skips_a_commented_line() {
  local dir out
  dir="$(_hi_lint_fixture comment nvim/init.lua '-- require("lazy").setup({})
require("lazy").setup({})
')"
  _hi_lint_fixture comment emacs/init.el ';; (load "~/x.el")
(load "~/x.el")
' >/dev/null
  out="$(_HI_CONFIG_DIR="$dir" _hi_include_lint | cut -d'|' -f1,2)"
  [ "$out" = 'nvim/init.lua|2
emacs/init.el|2' ] || {
    _hi_cecho " | reported: [$out]" "$RED"
    return 1
  }
}

# a plugin of the user's is scanned and stripped in the dialect it names: its
# include goes out disabled and is reported; with no dialect the same file
# rides as written
function test_a_users_row_is_read_in_its_dialect() {
  local dir bare out
  dir="$(_hi_lint_fixture user-dialect mine.rc '# about it
. ~/.mine-extra
set_it=1
')"
  bare="$(_hi_lint_fixture user-no-dialect mine.rc "$(cat "$dir/mine.rc")")"
  printf '[mine.mine]\ntool = "-"\nwire = "env:MINERC"\ndialect = "sh"\nfiles = "mine.rc"\n' >"$dir/plugins"
  printf '[mine.mine]\ntool = "-"\nwire = "env:MINERC"\nfiles = "mine.rc"\n' >"$bare/plugins"
  out="$(_HI_CONFIG_DIR="$dir" _hi_include_lint | cut -d'|' -f1-3)"
  [ "$out" = 'mine.rc|2|include' ] || _hi_because "reported: [$out]" || return 1
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat mine.rc)"
  [ "$out" = ':
set_it=1' ] || _hi_because "arrived as: [$out]" || return 1
  [ -z "$(_HI_CONFIG_DIR="$bare" _hi_include_lint)" ] || _hi_because "reported with no dialect" || return 1
  out="$(_HI_CONFIG_DIR="$bare" _hi_overlay_tar | _hi_tar_cat mine.rc)"
  [ "$out" = '# about it
. ~/.mine-extra
set_it=1' ] || _hi_because "with no dialect arrived as: [$out]"
}

# aliases.sh rides from the ~/.aliases a bash or zsh rc here already sources
# when the overlay has none - nothing copied into ~/.config/say-hi - and an
# overlay copy wins over it
function test_home_aliases_ride_as_aliases_sh() {
  local dir="$_HI_WORKDIR/aliases-home" out=""
  mkdir -p "$dir/overlay"
  printf 'alias ll="ls -l"\n' >"$dir/.aliases"
  out="$(HOME="$dir" _HI_CONFIG_DIR="$dir/overlay" _hi_overlay_tar | _hi_tar_cat aliases.sh)"
  [ "$out" = 'alias ll="ls -l"' ] || {
    _hi_cecho " | aliases.sh arrived as: [$out]" "$RED"
    return 1
  }
  printf 'alias x=y\n' >"$dir/overlay/aliases.sh"
  HOME="$dir" _HI_CONFIG_DIR="$dir/overlay" _hi_overlay_src aliases.sh out &&
    [ "$out" = "$dir/overlay/aliases.sh" ]
}

# A shell's own rc never rides from home: a ~/.bashrc is where people export
# tokens, so only the overlay's copy - the user's say-so - packs
# (GLOSSARY: HI.61)
function test_shell_rcs_ride_only_from_the_overlay() {
  local dir="$_HI_WORKDIR/rc-home" out="" f
  mkdir -p "$dir/overlay" "$dir/.config/fish"
  printf 'echo mine\n' | tee "$dir/.bashrc" "$dir/.zshrc" "$dir/.config/fish/config.fish" >/dev/null
  for f in bashrc zshrc config.fish; do
    ! HOME="$dir" _HI_CONFIG_DIR="$dir/overlay" _hi_overlay_src "$f" || {
      _hi_cecho " | $f rode from home" "$RED"
      return 1
    }
  done
  printf 'echo overlay\n' >"$dir/overlay/bashrc"
  HOME="$dir" _HI_CONFIG_DIR="$dir/overlay" _hi_overlay_src bashrc out &&
    [ "$out" = "$dir/overlay/bashrc" ]
}

# screen and zellij ride like tmux: the overlay's copy, else home's -
# ~/.screenrc, and zellij's directory ($ZELLIJ_CONFIG_DIR), whose layouts/
# and themes/ files ride one by one, the overlay's winning name by name -
# with the tool here
function test_screen_and_zellij_ride_like_tmux() {
  local h="$_HI_WORKDIR/mux-home" o="$_HI_WORKDIR/mux-home/overlay" z p out
  z="$h/zj"
  mkdir -p "$o/zellij/layouts" "$z/layouts" "$z/themes"
  printf 'startup_message off\n' >"$h/.screenrc"
  printf 'theme "home"\n' >"$z/config.kdl"
  printf 'layout {}\n' >"$z/layouts/dev.kdl"
  printf 'layout { home }\n' >"$z/layouts/ops.kdl"
  printf 'themes {}\n' >"$z/themes/mine.kdl"
  printf 'layout { overlay }\n' >"$o/zellij/layouts/ops.kdl"
  p="$(_hi_fake_path mux-bins screen zellij)"
  set -- HOME="$h" ZELLIJ_CONFIG_DIR="$z" PATH="$p:$PATH" _HI_CONFIG_DIR="$o"
  [ "$(env "$@" bash -c 'set -- && source "$_HI_LAUNCHER" && _hi_overlay_files screenrc zellij/config.kdl zellij/layouts/ zellij/themes/' | tr '\n' ' ')" = \
    "screenrc zellij/config.kdl zellij/layouts/ops.kdl zellij/layouts/dev.kdl zellij/themes/mine.kdl " ] || return 1
  out="$(env "$@" bash -c 'set -- && source "$_HI_LAUNCHER" && _hi_overlay_src zellij/layouts/ops.kdl o && printf %s "$o"')"
  [ "$out" = "$o/zellij/layouts/ops.kdl" ] || return 1
  # no zellij here: nothing from home
  [ -z "$(env "$@" bash -c 'set -- && source "$_HI_LAUNCHER" && PATH=/nonexistent _hi_overlay_files zellij/config.kdl zellij/themes/')" ]
}

# kakoune's colors/ rides file by file from the directory kak reads, so the
# scheme a kakrc names is there on a target; it has no wire of its own - the
# kakrc's $KAKOUNE_CONFIG_DIR is what points kak at it
# shellcheck disable=SC2016 # the wanted line holds $_HI_CONFIG_DIR unexpanded
function test_kak_colors_ride_beside_the_kakrc() {
  local h="$_HI_WORKDIR/kak-home" k p w
  k="$h/kk"
  mkdir -p "$h/overlay" "$k/colors"
  printf 'colorscheme mine\n' >"$k/kakrc"
  printf 'face global Default red\n' >"$k/colors/mine.kak"
  p="$(_hi_fake_path kak-bins kak)"
  set -- HOME="$h" KAKOUNE_CONFIG_DIR="$k" PATH="$p:$PATH" _HI_CONFIG_DIR="$h/overlay"
  [ "$(env "$@" bash -c 'set -- && source "$_HI_LAUNCHER" && _hi_overlay_files kak/kakrc kak/colors/' | tr '\n' ' ')" = \
    "kak/kakrc kak/colors/mine.kak " ] || return 1
  w="$(env "$@" bash -c 'set -- && source "$_HI_LAUNCHER" && _hi_overlay_wiring w kak/kakrc kak/colors/mine.kak && printf %s "$w"')"
  [ "$w" = 'export KAKOUNE_CONFIG_DIR="$_HI_CONFIG_DIR/kak"' ] || _hi_because "wiring: $w" || return 1
  [ -z "$(env "$@" bash -c 'set -- && source "$_HI_LAUNCHER" && _hi_overlay_wiring w kak/colors/mine.kak && printf %s "$w"')" ]
}

# readline's inputrc rides like bat's config: the overlay's copy, else the file
# $INPUTRC names, else ~/.inputrc, stripped - and an $include of anything but
# /etc/inputrc names a file no target has, so it is dropped unless allowed
# shellcheck disable=SC2016 # readline's $include, not an expansion
function test_inputrc_rides_like_the_tool_configs() {
  local h="$_HI_WORKDIR/rl-home" dir d
  mkdir -p "$h"
  printf '$include /etc/inputrc\n# a comment\n$include ~/.inputrc.local\nset editing-mode vi\n# hi-allow\n$include ~/.inputrc.kept\n' >"$h/.inputrc"
  printf 'set bell-style none\n' >"$h/named"
  dir="$(_hi_overlay_fixture rl-none)"
  d="$(_hi_tool_home_unpacked "$dir" HOME="$h")" || return 1
  [ "$(cat "$d/inputrc")" = '$include /etc/inputrc
set editing-mode vi
$include ~/.inputrc.kept' ] || {
    _hi_cecho " | inputrc arrived as: [$(cat "$d/inputrc" 2>&1)]" "$RED"
    return 1
  }
  d="$(_hi_tool_home_unpacked "$dir" HOME="$h" INPUTRC="$h/named")" || return 1
  [ "$(cat "$d/inputrc")" = 'set bell-style none' ] || return 1
  dir="$(_hi_overlay_fixture rl-copy inputrc)"
  d="$(_hi_tool_home_unpacked "$dir" HOME="$h")" || return 1
  [ "$(cat "$d/inputrc")" = x ]
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

# common/_hi, zsh's completion function, is found by compinit off its first
# line: it ships, and that line with it - no strip name matches the file
function test_zsh_completion_ships_with_its_compdef_line() {
  local dir line=""
  dir="$(_hi_strip_unpack stripped)"
  [ -f "$dir/say-hi/common/_hi" ] && IFS= read -r line <"$dir/say-hi/common/_hi"
  [ "$line" = '#compdef hi hi.sh' ] || _hi_because "common/_hi line 1: [$line]"
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
# `<<-` strips its own tabs there. hi.sh's remote script is the fixture: its
# `      mkdir "\$_HI_ROOT"` sits inside `<<REMOTE`.
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
  grep -q '^      mkdir "\\\$_HI_ROOT"$' "$dir/say-hi/hi.sh" || {
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

# A session's tree is the payload unpacked: no scripts/, so no packer, and
# its hi.sh relays the tree as it stands. The fixture is one hop's tree, the
# way a session leaves it: the bootloader beside the payload, and an include
# the client carried, fixed up to this hop's path.
function _hi_session_tree() {
  local dir="$_HI_WORKDIR/session"
  [ -d "$dir" ] || {
    mkdir -p "$dir"
    _hi_payload_tar | tar -x -z -f - -C "$dir"
    mkdir -p "$dir/say-hi/config/vim"
    printf 'source %s/say-hi/config/vim/extra.vim\n' "$dir" >"$dir/say-hi/config/vim/vimrc"
    : >"$dir/say-hi/config/vim/extra.vim"
    : >"$dir/say-hi/hi.bashrc"
  }
  printf '%s' "$dir"
}

# _hi_in_session <tree> <config dir> <command...> - <command> in that tree's
# own hi.sh, with what a session exports to a child
function _hi_in_session() {
  env _HI_REMOTE_SESSION=1 _HI_HOME="$1" _HI_CONFIG_DIR="$2" \
    bash -c 'a=("${@:3}") && set -- && source "$_HI_HOME/say-hi/hi.sh" && "${a[@]}"' _ "$@"
}

function test_a_session_relays_its_tree_as_it_stands() {
  local dir out="$_HI_WORKDIR/relayed" m
  dir="$(_hi_session_tree)"
  [ ! -e "$dir/say-hi/scripts" ] || _hi_because "the payload carries scripts/" || return 1
  mkdir -p "$out"
  _hi_in_session "$dir" "$dir/say-hi/config" _hi_payload_tar | tar -x -z -f - -C "$out" || return 1
  for m in "${_HI_PAYLOAD[@]}"; do
    diff -r "$dir/say-hi/$m" "$out/say-hi/$m" >/dev/null || _hi_because "$m is not the session's own" || return 1
  done
  [ ! -e "$out/say-hi/hi.bashrc" ] || _hi_because "the hop's bootloader rode"
}

# ...and what an include of it names is the relaying hop's directory, which
# the next hop makes its own
function test_a_relay_hands_on_what_it_carried() {
  local dir next="$_HI_WORKDIR/nexthop/config" fix
  dir="$(_hi_session_tree)"
  mkdir -p "$next/vim"
  cp "$dir/say-hi/config/vim/vimrc" "$next/vim/vimrc"
  fix="$(_hi_in_session "$dir" "$dir/say-hi/config" _hi_overlay_fixup "'$next'")" || return 1
  sh -c "$fix" || return 1
  [ "$(cat "$next/vim/vimrc")" = "source $next/vim/extra.vim" ] ||
    _hi_because "the include on the next hop: $(cat "$next/vim/vimrc")" || return 1
  # a path no script can hold bare is no token: nothing is rewritten
  [ "$(_hi_in_session "$dir" "$dir/say hi/config" _hi_overlay_fixup "'$next'")" = : ]
}

# hi.sh reaches the packer through the five functions a session defines for
# itself, and four more that run only with an overlay to send or outside a
# session. The session's stripped copy is read, so a comment names nothing.
function test_hi_sh_reaches_the_packer_only_through_the_seam() {
  local dir have n
  dir="$(_hi_session_tree)"
  have=" $(_hi_in_session "$dir" "$dir/say-hi/config" declare -F | sed 's/^declare -f //' | tr '\n' ' ')"
  [[ "$have" == *" _hi_payload_tar "* ]] || _hi_because "a session's hi.sh defines no _hi_payload_tar" || return 1
  while IFS= read -r n; do
    grep -E "(^|[^A-Za-z0-9_])$n([^A-Za-z0-9_]|\$)" "$dir/say-hi/hi.sh" >/dev/null || continue
    case "$have _hi_overlay_cached _hi_overlay_stream _hi_overlay_bytes _hi_prompt_here " in *" $n "*) continue ;; esac
    _hi_because "hi.sh calls $n, which only scripts/pack.sh defines" || return 1
  done < <(sed -n 's/^function \(_hi_[a-z0-9_]*\)().*/\1/p' "$_HI_ROOT/scripts/pack.sh")
}

# only a session goes without the packer: anywhere else its absence is a
# broken install, said before anything is sent
function test_an_install_without_the_packer_refuses_to_connect() {
  local dir out rc=0
  dir="$(_hi_session_tree)"
  out="$(env _HI_REMOTE_SESSION=0 _HI_HOME="$dir" _HI_CONFIG_DIR="$dir/say-hi/config" \
    bash "$dir/say-hi/hi.sh" somehost 2>&1 </dev/null)" || rc=$?
  [ "$rc" -eq 1 ] && [[ "$out" == *"no scripts/pack.sh in $dir/say-hi"* ]] || _hi_because "exit $rc: $out"
}

# The data files' prose headers document the *installed* copies a user reads,
# so they ship stripped too: flags/colors/packages through the same `#` rule
# as the shell. An overlay vim/vimrc, emacs/init.el, and nvim/init.lua strip through their
# own rules for vim's `"`, elisp's `;`, and lua's `--`, keeping every other
# line.
function test_strip_covers_the_data_files() {
  local dir f n out ov="$_HI_WORKDIR/strip-overlay" bad=0
  dir="$(_hi_strip_unpack stripped)"
  for f in common/flags config/colors config/packages; do
    n="$(sed -n '2,$p' "$dir/say-hi/$f" | grep -cE '^[[:space:]]*#' || true)"
    [ "$n" -eq 0 ] || {
      _hi_cecho " | $f kept $n comment line(s) through the strip" "$RED"
      bad=1
    }
  done
  # the files with a comment character of their own: <file>:<char>
  mkdir -p "$ov"
  mkdir -p "$ov/vim" "$ov/emacs" "$ov/nvim"
  for f in 'vim/vimrc:"' 'emacs/init.el:;' 'nvim/init.lua:--'; do
    printf '%s a comment\nkept %s\n' "${f#*:}" "${f%%:*}" >"$ov/${f%%:*}"
  done
  for f in 'vim/vimrc:"' 'emacs/init.el:;' 'nvim/init.lua:--'; do
    out="$(_HI_CONFIG_DIR="$ov" \
      _hi_overlay_tar | _hi_tar_cat "${f%%:*}")"
    [ "$out" = "kept ${f%%:*}" ] || {
      _hi_cecho " | ${f%%:*} rode as [$out]" "$RED"
      bad=1
    }
  done
  [ "$bad" -eq 0 ]
}

# ...and stripping is all it does: every data line survives byte for byte
function test_strip_keeps_every_data_line() {
  local dir f bad=0
  dir="$(_hi_strip_unpack stripped)"
  for f in common/flags config/colors config/packages; do
    diff <(grep -vE '^[[:space:]]*#|^$' "$_HI_ROOT/$f" | sed 's/^[[:space:]]*//') \
      <(grep -vE '^[[:space:]]*#|^$' "$dir/say-hi/$f" | sed 's/^[[:space:]]*//') >/dev/null || {
      _hi_cecho " | $f lost or changed a data line" "$RED"
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
  # ~/.aliases and ~/.inputrc join the overlay stream with no variable to
  # pin them, so the developer's own would answer every case expecting none
  HOME="$_HI_WORKDIR/bare-home"
  mkdir -p "$HOME"
  # home's configs ride only with their tools on this machine (_hi_tool_here),
  # and no runner has all of them
  PATH="$(_hi_stub_tools vim nvim hx nano emacs tmux micro bat eza):$PATH"

  _hi_suite_begin

  _hi_h1 "Testing hi.sh: the payload"

  _hi_h2 "Testing: the payload list"
  _hi_check "Ships exactly common/config/load.sh" test_payload_ships_exactly_the_travelled_paths
  _hi_check "A default client ships everything" test_payload_ships_everything_by_default
  _hi_check "No toggle changes what ships" test_payload_always_ships_aliases
  _hi_check "A tree default the overlay shadows is cut" test_a_shadowed_tree_default_is_cut_from_the_payload
  _hi_check "With the header off, header.sh and the package list stay home" test_header_off_keeps_the_header_home
  _hi_check "...only for a caller holding a cut list" test_the_payload_is_whole_without_a_cut_list
  _hi_check "The plugins rows stay home" test_the_plugins_rows_stay_home
  _hi_check "A prompt framework's loader rides only where handed" test_a_prompt_loader_rides_only_where_handed
  _hi_check "The shadow roster is paths.sh's cascade" test_the_shadow_roster_matches_paths_sh

  _hi_h2 "Testing: the in-transit comment strip"
  _hi_check "No full-line comments survive" test_strip_leaves_no_full_line_comments
  _hi_check "Every code line survives" test_strip_keeps_every_code_line
  _hi_check "zsh's completion ships with its #compdef line" test_zsh_completion_ships_with_its_compdef_line
  _hi_check "Blank lines and indentation go, heredoc bodies stay" test_strip_trims_whitespace_outside_heredocs
  _hi_check "The result is still valid shell" test_strip_leaves_valid_shell
  _hi_check "hi.sh stays executable" test_strip_keeps_hi_sh_executable
  _hi_check "Heredoc bodies are spared" test_strip_spares_heredoc_bodies
  _hi_check "The data-file headers strip too" test_strip_covers_the_data_files
  _hi_check "Every data line survives" test_strip_keeps_every_data_line

  _hi_h2 "Testing: a session's relay"
  _hi_check "A session relays its tree as it stands" test_a_session_relays_its_tree_as_it_stands
  _hi_check "...and hands on what it carried, under its own path" test_a_relay_hands_on_what_it_carried
  _hi_check "hi.sh reaches the packer only through the seam" test_hi_sh_reaches_the_packer_only_through_the_seam
  _hi_check "An install without the packer refuses to connect" test_an_install_without_the_packer_refuses_to_connect

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
  _hi_check "...while local-only's toggles keep nothing home" test_local_only_toggles_keep_nothing_home
  _hi_check "The stream is comment-stripped" test_overlay_strip_removes_comments
  _hi_check "the user's per-shell files ride the stream" test_overlay_tar_carries_shell_files
  _hi_check_capable symlink "Symlinked overlay files are dereferenced (Stow)" test_overlay_dereferences_symlinks
  _hi_check "Nothing outside the roster travels" test_overlay_sends_nothing_outside_the_roster
  _hi_check "The overlay's packages rides stripped" test_overlay_carries_packages_stripped
  _hi_check "Extensions ride stripped" test_overlay_carries_extensions
  _hi_check "The tool configs in force here ride along" test_overlay_carries_the_home_tool_configs
  _hi_check "...found through each tool's own variable" test_overlay_home_configs_follow_the_tools_variables
  _hi_check "...ripgrep's, fzf's, and lazygit's included" test_overlay_home_configs_of_the_cli_tools
  _hi_check "...and an overlay copy wins" test_overlay_copy_of_a_tool_config_wins
  _hi_check "An overlay copy of a prompt framework's file wins" test_overlay_copy_of_a_prompt_framework_file_wins
  _hi_check "oh-my-posh's config rides from \$POSH_CONFIG, the rc, or the overlay" test_oh_my_posh_config_rides_from_home_or_overlay
  _hi_check "The prompt frameworks' home files ride, tide's lines alone" test_overlay_carries_the_prompt_frameworks_home_files
  _hi_check "bash-it's theme is found in its loader's order" test_overlay_carries_the_bash_it_theme_by_loader_order
  _hi_check "micro's files ride under micro/, the overlay's copy first" test_micro_config_rides_in_a_directory_of_its_own
  _hi_check "Unset, the prompt programs are what home has" test_prompt_list_is_what_home_has
  _hi_check "A home .aliases rides as aliases.sh" test_home_aliases_ride_as_aliases_sh
  _hi_check "A shell's own rc rides only from the overlay" test_shell_rcs_ride_only_from_the_overlay
  _hi_check "screen and zellij ride like tmux" test_screen_and_zellij_ride_like_tmux
  _hi_check "kakoune's colors/ rides beside its kakrc" test_kak_colors_ride_beside_the_kakrc
  _hi_check "inputrc rides like the tool configs, its includes dropped" test_inputrc_rides_like_the_tool_configs
  _hi_check "ssh_tags is the tagged Host lines of ~/.ssh/config" test_ssh_tags_is_cut_from_the_ssh_config
  _hi_check "...kept, and recut once the config is newer or Includes" test_ssh_tags_cut_is_reused_until_the_config_is_newer
  _hi_check_capable lockout "...and failing cleanly with no tag or no writable dir" test_ssh_tags_fails_cleanly_without_a_tag_or_a_writable_dir

  _hi_h2 "Testing: the include scan"
  _hi_check "An unresolvable include is dropped" test_editor_includes_are_dropped_on_the_way_out
  _hi_check "A lua finding takes its expression with it" test_a_dropped_expression_goes_out_whole
  _hi_check "...and so does neovim's own vim.pack.add" test_vim_pack_add_is_a_plugin_finding
  _hi_check "A tmux finding takes its continuation with it" test_tmux_includes_are_dropped_on_the_way_out
  _hi_check "An include under the tool's own directory rides" test_an_include_under_the_tools_directory_rides
  _hi_check "...its path lands on the target's overlay" test_a_carried_path_lands_on_the_target
  _hi_check "...it is no doctor finding" test_a_carried_include_is_no_finding
  _hi_check "An edit to a carried file rebuilds the cache" test_an_edit_to_a_carried_file_rebuilds_the_cache
  _hi_check "The editor config in force here rides along" test_the_editor_config_in_force_here_rides_the_stream
  _hi_check "...found in its tool's own order" test_a_home_config_is_found_in_its_tools_order
  _hi_check "...only with its tool on this machine" test_a_home_config_needs_its_tool_here
  _hi_check "The scan reads every dialect" test_the_scan_reports_every_dialect
  _hi_check "A clean config is silent" test_the_scan_is_silent_on_a_clean_config
  _hi_check "nano keeps /usr/share/nano, drops a subdirectory of it" test_nano_keeps_the_stock_directory_and_drops_the_rest
  _hi_check "An rc is read under its member name" test_the_scan_reads_an_rc_under_its_own_name
  _hi_check "A shell include becomes : and still parses" test_shell_includes_are_neutralized_and_still_parse
  _hi_check "A fish include becomes true" test_fish_includes_become_true
  _hi_check "Framework files and extensions are scanned as shell" test_framework_and_extension_includes_are_neutralized
  _hi_check "...a framework's tree passes only its own theme" test_a_framework_tree_passes_only_its_own_theme
  _hi_check "hi-allow keeps the next line" test_hi_allow_keeps_the_next_line
  _hi_check "hi-quiet drops the next line without a row" test_hi_quiet_drops_the_next_line_without_a_row
  _hi_check "A hi-quiet pair drops its block without a row" test_a_quiet_block_drops_its_lines_without_a_row
  _hi_check "A hi-allow pair keeps its block" test_an_allow_block_keeps_its_lines
  _hi_check "...in every dialect's comment syntax" test_a_block_is_read_in_every_dialect
  _hi_check "An unclosed start decides nothing and is a row" test_an_unclosed_start_decides_nothing_and_is_reported
  _hi_check "...and a lone marker still decides one line" test_a_single_marker_still_decides_one_line
  _hi_check "A commented line is no finding" test_the_scan_skips_a_commented_line
  _hi_check "A plugin of the user's is read in its dialect" test_a_users_row_is_read_in_its_dialect

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
