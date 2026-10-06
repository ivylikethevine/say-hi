#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Unit tests for what the config overlay stream takes from home: the tool configs in
# force here, the prompt frameworks' files, and ~/.ssh/config's tags.
# A part of payload_test.sh, a suite of its own so the Windows shards split
# them. The preamble's source line is payload_test.sh's - it sources the
# harness and hi.sh, and holds the helpers the parts share (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329,SC2317,SC2016
set -euo pipefail

_HI_PAYLOAD_PART=home
# shellcheck source=./payload_test.sh
source "${BASH_SOURCE[0]%/*}/payload_test.sh"

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

# p10k's wizard writes under $ZDOTDIR, which a ~/.zshenv sets for zsh alone:
# hi run from bash or fish finds that file, not a stale ~/.p10k.zsh
function test_p10k_rides_from_a_zshenv_zdotdir() {
  local dir d h="$_HI_WORKDIR/p10k-zshenv"
  mkdir -p "$h/zd"
  # shellcheck disable=SC2016 # zsh's to expand
  printf 'export ZDOTDIR="$HOME/zd"\n' >"$h/.zshenv"
  printf 'typeset -g POWERLEVEL9K_MODE=stale\n' >"$h/.p10k.zsh"
  printf 'typeset -g POWERLEVEL9K_MODE=zdotdir\n' >"$h/zd/.p10k.zsh"
  dir="$(_hi_overlay_fixture p10k-zshenv colors)"
  d="$(_hi_tool_home_unpacked "$dir" HOME="$h" XDG_CONFIG_HOME="$h/.config" _HI_PROMPT_TOOL=powerlevel10k)" || return 1
  [ "$(cat "$d/p10k.zsh")" = 'typeset -g POWERLEVEL9K_MODE=zdotdir' ] || _hi_because "p10k.zsh arrived as: [$(cat "$d/p10k.zsh" 2>&1)]"
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

# a cut that cannot be moved into place leaves no temp file beside it
function test_ssh_tags_leaves_no_temp_file_when_the_cut_fails() {
  local dir="$_HI_WORKDIR/tags-mv" out
  mkdir -p "$dir/rt"
  printf '# Tags: one\nHost a\n' >"$dir/config"
  out="$(
    mv() { return 1; }
    _hi_tags_at "$dir"
  )"
  [ "$out" = "rc 1" ] && [ -z "$(find "$dir/rt" -name 'hi.ssh_tags*')" ] || _hi_because "a failed mv: [$out] $(ls "$dir/rt")"
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

function run_hi_payload_home_tests() {
  _hi_payload_begin

  _hi_h1 "Testing hi.sh: what rides from home"

  _hi_h2 "Testing: home's configs in the overlay stream"
  _hi_check "The tool configs in force here ride along" test_overlay_carries_the_home_tool_configs
  _hi_check "...found through each tool's own variable" test_overlay_home_configs_follow_the_tools_variables
  _hi_check "...ripgrep's, fzf's, and lazygit's included" test_overlay_home_configs_of_the_cli_tools
  _hi_check "...and an overlay copy wins" test_overlay_copy_of_a_tool_config_wins
  _hi_check "An overlay copy of a prompt framework's file wins" test_overlay_copy_of_a_prompt_framework_file_wins
  _hi_check "oh-my-posh's config rides from \$POSH_CONFIG, the rc, or the overlay" test_oh_my_posh_config_rides_from_home_or_overlay
  _hi_check "The prompt frameworks' home files ride, tide's lines alone" test_overlay_carries_the_prompt_frameworks_home_files
  _hi_check "...p10k's from the ZDOTDIR a ~/.zshenv sets" test_p10k_rides_from_a_zshenv_zdotdir
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
  _hi_check "...and leaving no temp file when the cut cannot land" test_ssh_tags_leaves_no_temp_file_when_the_cut_fails
  _hi_suite_end "hi.sh (what rides from home)"
}

run_hi_payload_home_tests
