#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Unit tests for the include scan over the config overlay stream: what a line naming a
# path costs an editor rc or a shell file on its way out (GLOSSARY: HI.57).
# A part of payload_test.sh, a suite of its own so the Windows shards split
# them. The preamble's source line is payload_test.sh's - it sources the
# harness and hi.sh, and holds the helpers the parts share (GLOSSARY: HI.34).
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329,SC2317,SC2016
set -euo pipefail

_HI_PAYLOAD_PART=scan
# shellcheck source=./payload_test.sh
source "${BASH_SOURCE[0]%/*}/payload_test.sh"

# The comment strip. Its correctness argument is "only full-line comments, and
# never inside a heredoc", so that is what these assert: the shipped shell is
# still shell, the code survives byte for byte, and the one heredoc a user can
# see - `hi --help` - is intact.
# The include scan. Every editor rc and shell file ships into a config/ of its
# own, so a line naming a path names something no target has and the editor
# or shell fails, not hi. pack_scan.sh's _hi_lint_awk reads every dialect; these pin
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
  local got got2
  local dir="$_HI_WORKDIR/lint-in-force" home="$_HI_WORKDIR/in-force-home" p
  mkdir -p "$dir" "$home"
  printf 'set number\n' >"$home/.vimrc"
  p="$(_hi_fake_path in-force-bins vim):$PATH"
  got="$(HOME="$home" PATH="$p" _HI_CONFIG_DIR="$dir" _hi_overlay_files vim/vimrc)"
  got2="$(HOME="$home" PATH="$p" _HI_CONFIG_DIR="$dir" _hi_overlay_tar vim/vimrc | _hi_tar_cat vim/vimrc)"
  [ "$got" = vim/vimrc ] && [ "$got2" = "set number" ] || _hi_why got got2 home p dir
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
    mkdir -p "${f%/*}" && printf 'x\n' >"$f" || _hi_why f || return 1
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
  ! HOME="$home" PATH="$none" _HI_CONFIG_DIR="$dir" _hi_overlay_src vim/vimrc || _hi_why home none dir || return 1
  ! HOME="$home" PATH="$none" _HI_CONFIG_DIR="$dir" _hi_overlay_src tmux/tmux.conf || _hi_why home none dir || return 1
  HOME="$home" PATH="$p" _HI_CONFIG_DIR="$dir" _hi_overlay_src vim/vimrc out && [ "$out" = "$home/.vimrc" ] || _hi_why home p dir out || return 1
  mkdir -p "$dir/vim"
  printf 'set ruler\n' >"$dir/vim/vimrc"
  HOME="$home" PATH="$none" _HI_CONFIG_DIR="$dir" _hi_overlay_src vim/vimrc out && [ "$out" = "$dir/vim/vimrc" ] || _hi_why home none dir out
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
  local dir got
  dir="$_HI_WORKDIR/lint-clean"
  mkdir -p "$dir"
  mkdir -p "$dir/vim" "$dir/emacs"
  printf 'set number\nruntime! plugin/sensible.vim\n' >"$dir/vim/vimrc"
  printf '(require (quote cl-lib))\n(setq tab-width 2)\n' >"$dir/emacs/init.el"
  got="$(_HI_CONFIG_DIR="$dir" _hi_include_lint)"
  [ -z "$got" ] || _hi_why got dir
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
  printf '%s\n' "$out" | bash -n || _hi_why out
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

# a multiplexer's default shell is a path on the client: dropped, a pane
# opens on the session's $SHELL; a line that only names the option stays
function test_a_multiplexers_default_shell_stays_home() {
  local dir out
  dir="$(_hi_lint_fixture muxshell tmux/tmux.conf 'set -g mouse on
set -g default-shell /usr/bin/fish
set-option -g -q default-shell /opt/zsh
set -g status-left "default-shell"
')"
  printf 'defscrollback 100\nshell /usr/bin/fish\ndefshell -fish\n' >"$dir/screenrc"
  mkdir -p "$dir/zellij"
  printf 'theme "x"\ndefault_shell "/usr/bin/fish"\n' >"$dir/zellij/config.kdl"
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat tmux/tmux.conf)"
  [ "$out" = 'set -g mouse on
set -g status-left "default-shell"' ] || _hi_because "tmux.conf arrived as: [$out]" || return 1
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat screenrc)"
  [ "$out" = 'defscrollback 100' ] || _hi_because "screenrc arrived as: [$out]" || return 1
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat zellij/config.kdl | grep -v '^// hi dropped: ')"
  [ "$out" = 'theme "x"' ] || _hi_because "config.kdl arrived as: [$out]"
}

# zellij names a plugin's .wasm in more places than a layout's location=: a
# key's LaunchOrFocusPlugin and load_plugins go the same way, each whole. A
# layout's borderless pane that loses its plugin was a bar, and an empty pane
# opens as a shell, so zellij's own bar stands in, a marker comment above
# the plugin or not; any other pane is left
function test_every_zellij_plugin_path_is_dropped() {
  local dir out
  dir="$(_hi_lint_fixture zjplug zellij/config.kdl 'keybinds {
  bind "s" {
    LaunchOrFocusPlugin "file:/home/me/zsm.wasm" {
      floating true
    }
    SwitchToMode "normal"
  }
}
load_plugins {
  "file:/home/me/auto.wasm"
}
theme "x"
')"
  mkdir -p "$dir/zellij/layouts"
  printf '%s\n' 'layout {' '  pane size=1 borderless=true {' '    // hi-quiet' '    plugin location="file:/home/me/bar.wasm" {' '      format "x"' '    }' '  }' \
    '  pane {' '    plugin location="file:/home/me/tree.wasm"' '  }' '  pane borderless=true {' '    plugin location="zellij:tab-bar"' '  }' '}' >"$dir/zellij/layouts/default.kdl"
  out="$(_HI_CONFIG_DIR="$dir" _hi_include_lint | cut -d'|' -f1-3 | paste -sd, -)"
  [ "$out" = "zellij/config.kdl|3|plugin,zellij/config.kdl|10|plugin,zellij/layouts/default.kdl|9|plugin" ] ||
    _hi_because "the scan reported: [$out]" || return 1
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat zellij/config.kdl | grep -v '^// hi dropped: ')"
  [ "$out" = 'keybinds {
  bind "s" {
    SwitchToMode "normal"
  }
}
load_plugins {
}
theme "x"' ] || _hi_because "config.kdl arrived as: [$out]" || return 1
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat zellij/layouts/default.kdl | grep -v '^// hi dropped: ')"
  [ "$out" = 'layout {
  pane size=1 borderless=true {
    // hi-quiet
    plugin location="zellij:compact-bar"
  }
  pane {
  }
  pane borderless=true {
    plugin location="zellij:tab-bar"
  }
}' ] || _hi_because "default.kdl arrived as: [$out]"
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
  local h d got
  h="$(_hi_carry_home rides)"
  d="$(mktemp -d "$_HI_WORKDIR/carry-unpacked.XXXXXX")" || _hi_why || return 1
  HOME="$h" XDG_CONFIG_HOME="$h/.config" _HI_CONFIG_DIR="$h/overlay" _hi_overlay_tar tmux/tmux.conf |
    tar -x -z -f - -C "$d" || _hi_why h d || return 1
  got="$(cat "$d/tmux/tmux.conf")"
  [ "$got" = "set -g mouse on
source-file $_HI_CARRY_TOKEN/tmux/theme.conf" ] || _hi_because "tmux.conf: [$got]" || return 1
  got="$(cat "$d/tmux/theme.conf")"
  [ "$got" = "set -g @theme HI
source-file \"$_HI_CARRY_TOKEN/tmux/parts/bar.conf\"" ] || _hi_because "theme.conf: [$got]" || return 1
  got="$(cat "$d/tmux/parts/bar.conf")"
  [ "$got" = 'set -g @bar HI' ] || _hi_why got d
}

# a line under hi-carry rides the files under $HOME it names, as written and
# beside the member (a member with no directory gets <member>.carried), with
# the path held for the target's overlay directory; a path outside $HOME is
# the target's own, and one that is no file is the scan's to name
function test_a_marked_line_rides_the_files_it_names() {
  local got got2
  local h="$_HI_WORKDIR/marked" d out
  mkdir -p "$h/.config/fd" "$h/.local/share" "$h/overlay/tmux"
  printf '# mine\n*.log\n' >"$h/.config/fd/ignore"
  printf 'Keys\n\n  ?  this sheet\n' >"$h/.local/share/keys.txt"
  printf -- '--smart-case\n# hi-carry\n--ignore-file=%s/.config/fd/ignore\n' "$h" >"$h/overlay/ripgreprc"
  printf '%s\n' 'set -g mouse on' '# hi-carry' 'bind ? display-popup "/usr/bin/less ~/.local/share/keys.txt"' \
    '# hi-carry' 'bind g display-popup "less ~/gone.txt"' >"$h/overlay/tmux/tmux.conf"
  set -- HOME="$h" XDG_CONFIG_HOME="$h/.config" _HI_CONFIG_DIR="$h/overlay" PATH="$(_hi_fake_path marked-bins rg tmux):$PATH"
  out="$(env "$@" bash -c 'set -- && source "$_HI_LAUNCHER" && _hi_include_lint' | paste -sd, -)"
  # shellcheck disable=SC2088 # the ~ the line wrote
  [ "$out" = 'tmux/tmux.conf|5|carry|~/gone.txt is no file here' ] || _hi_because "the scan reported: [$out]" || return 1
  d="$(mktemp -d "$_HI_WORKDIR/marked-unpacked.XXXXXX")" || _hi_why || return 1
  env "$@" bash -c 'set -- && source "$_HI_LAUNCHER" && _hi_overlay_tar ripgreprc tmux/tmux.conf' | tar -x -z -f - -C "$d" || _hi_why d || return 1
  got="$(cat "$d/ripgreprc")"
  [ "$got" = "--smart-case
--ignore-file=$_HI_CARRY_TOKEN/ripgreprc.carried/ignore" ] || _hi_because "ripgreprc: [$got]" || return 1
  got="$(cat "$d/ripgreprc.carried/ignore")"
  got2="$(cat "$h/.config/fd/ignore")"
  [ "$got" = "$got2" ] || _hi_because "the ignore file did not ride as written" || return 1
  got="$(cat "$d/tmux/tmux.conf")"
  [ "$got" = "set -g mouse on
bind ? display-popup \"/usr/bin/less $_HI_CARRY_TOKEN/tmux/carried/keys.txt\"
bind g display-popup \"less ~/gone.txt\"" ] || _hi_because "tmux.conf: [$got]" || return 1
  got="$(cat "$d/tmux/carried/keys.txt")"
  got2="$(cat "$h/.local/share/keys.txt")"
  [ "$got" = "$got2" ] || _hi_because "the sheet did not ride as written"
}

# the target's half: a real sh makes every held path the directory the
# overlay landed in
function test_a_carried_path_lands_on_the_target() {
  local got
  local d="$_HI_WORKDIR/carry-fixup/config"
  mkdir -p "$d/tmux"
  printf 'source-file %s/tmux/theme.conf\nset -g mouse on\n' "$_HI_CARRY_TOKEN" >"$d/tmux/tmux.conf"
  sh -c "$(_hi_overlay_fixup "'$d'")" || _hi_why || return 1
  got="$(cat "$d/tmux/tmux.conf")"
  [ "$got" = "source-file $d/tmux/theme.conf
set -g mouse on" ] || _hi_because "after the fixup: [$got]"
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
  local got
  local h c1="" c2=""
  h="$(_hi_carry_home cache)"
  mkdir -p "$h/run"
  HOME="$h" XDG_CONFIG_HOME="$h/.config" _HI_CONFIG_DIR="$h/overlay" XDG_RUNTIME_DIR="$h/run" \
    _hi_overlay_cached c1 tmux/tmux.conf || _hi_why h || return 1
  grep -qx "$h/.config/tmux/parts/bar.conf" "$c1.carry" || _hi_because "no carry list beside $c1" || return 1
  # dated ahead, so the edit is newer than the cache on any clock grain
  printf 'set -g @bar EDITED\n' >"$h/.config/tmux/parts/bar.conf"
  touch -t 203001010000 "$h/.config/tmux/parts/bar.conf"
  HOME="$h" XDG_CONFIG_HOME="$h/.config" _HI_CONFIG_DIR="$h/overlay" XDG_RUNTIME_DIR="$h/run" \
    _hi_overlay_cached c2 tmux/tmux.conf || _hi_why h || return 1
  got="$(_hi_tar_cat tmux/parts/bar.conf <"$c2")"
  [ "$got" = 'set -g @bar EDITED' ] || _hi_because "the cache kept the old carried file"
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
PS1=x' ] || _hi_why out
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
  local dir bare out got
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
  got="$(_HI_CONFIG_DIR="$bare" _hi_include_lint)"
  [ -z "$got" ] || _hi_because "reported with no dialect" || return 1
  out="$(_HI_CONFIG_DIR="$bare" _hi_overlay_tar | _hi_tar_cat mine.rc)"
  [ "$out" = '# about it
. ~/.mine-extra
set_it=1' ] || _hi_because "with no dialect arrived as: [$out]"
}

# a module neovim's init.lua requires from its lua/ rides, what that module
# requires with it, and the init puts their directory on the runtimepath; a
# require of nothing there is dropped as before, and a module nothing
# requires stays home
function test_a_required_neovim_module_rides() {
  local dir out listing
  dir="$(_hi_lint_fixture require nvim/init.lua 'vim.g.one = 1
require("mine.opts")
local keys = require '"'"'keys'"'"'
require("absent")
')"
  mkdir -p "$dir/nvim/lua/mine/deep"
  printf 'require("mine.deep")\n' >"$dir/nvim/lua/mine/opts.lua"
  printf 'vim.g.deep = 1\n' >"$dir/nvim/lua/mine/deep/init.lua"
  printf 'return {}\n' >"$dir/nvim/lua/keys.lua"
  printf 'return {}\n' >"$dir/nvim/lua/unused.lua"
  listing="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar -t -z -f - | sort | tr '\n' ' ')"
  [[ "$listing" == *"nvim/lua/keys.lua nvim/lua/mine/deep/init.lua nvim/lua/mine/opts.lua "* && "$listing" != *unused* ]] ||
    _hi_because "what rode: $listing" || return 1
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat nvim/init.lua)"
  [ "$out" = "vim.opt.rtp:prepend(\"$_HI_CARRY_TOKEN/nvim\")
vim.g.one = 1
require(\"mine.opts\")
local keys = require 'keys'" ] || _hi_because "nvim/init.lua arrived as: [$out]" || return 1
  out="$(_HI_CONFIG_DIR="$dir" _hi_include_lint)"
  [ "$out" = 'nvim/init.lua|4|include|require("absent")' ] || _hi_because "the findings: [$out]"
}

# _hi_real_nvim <outvar> - an nvim past the suite's stand-in on $PATH, or a
# path that is no command, for _hi_check_requires to skip by
function _hi_real_nvim() {
  local d
  local -a dirs
  printf -v "$1" '%s' /no/real/nvim
  IFS=: read -r -a dirs <<<"$PATH"
  for d in "${dirs[@]}"; do
    [ "$d" = "$_HI_WORKDIR/stubtools" ] || [ ! -x "$d/nvim" ] || {
      printf -v "$1" '%s' "$d/nvim"
      return 0
    }
  done
}

# ...and a real neovim, started on the init.lua as a target has it, loads
# each from the overlay
function test_neovim_loads_the_modules_that_rode() {
  local got2
  local dir got="$_HI_WORKDIR/nvim-got" out nvim
  _hi_real_nvim nvim
  dir="$(_hi_lint_fixture nvimrun nvim/init.lua 'require("one")
require("two.deep")
')"
  mkdir -p "$dir/nvim/lua/two" "$got"
  printf 'vim.g.hi_one = 1\n' >"$dir/nvim/lua/one.lua"
  printf 'vim.g.hi_two = 2\n' >"$dir/nvim/lua/two/deep.lua"
  _HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar -x -z -f - -C "$got" || _hi_why dir got || return 1
  sh -c "$(_hi_overlay_fixup "'$got'")" || _hi_why got || return 1
  out="$(HI_TEST_OUT="$got/loaded" XDG_CONFIG_HOME="$got/none" XDG_STATE_HOME="$got/state" XDG_DATA_HOME="$got/data" \
    XDG_CACHE_HOME="$got/cache" "$nvim" --headless -u "$got/nvim/init.lua" \
    -c 'lua vim.fn.writefile({ tostring(vim.g.hi_one) .. tostring(vim.g.hi_two) }, vim.env.HI_TEST_OUT)' -c 'qa!' 2>&1 </dev/null)" ||
    _hi_because "nvim failed: $out" || return 1
  got2="$(cat "$got/loaded" 2>/dev/null)"
  [ "$got2" = 12 ] || _hi_because "nvim said [$out] and loaded [$(cat "$got/loaded" 2>&1)]"
}

# an init.vim rides as a member of its own, read as vim script
function test_neovim_s_init_vim_rides_in_the_vim_dialect() {
  local dir out w
  dir="$(_hi_lint_fixture initvim nvim/init.vim 'set number
source ~/elsewhere.vim
')"
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat nvim/init.vim)"
  [ "$out" = 'set number' ] || _hi_because "nvim/init.vim arrived as: [$out]" || return 1
  _hi_overlay_wiring w nvim/init.vim
  [[ "$w" == *'export _HI_NVIMRC="$_HI_CONFIG_DIR/nvim/init.vim"'* && "$w" == *'nvim -u $_HI_CONFIG_DIR/nvim/init.vim"'* ]] ||
    _hi_because "its wiring: $w"
}

_HI_LINT_GITCONFIG='[user]
	name = A User
	email = a@example.com
	signingkey = ABCDEF
[alias]
	co = checkout
[commit]
	gpgSign = true
[credential "https://example.com"]
	helper = store
[url "git@example.com:"]
	insteadOf = https://example.com/
[core]
	sshCommand = ssh -i ~/.ssh/work
	# hi-allow
	sshCommand = ssh -o Compression=yes
[gpg "ssh"] allowedSignersFile = ~/.ssh/allowed
[includeIf "gitdir:~/work/"]
	path = ~/.gitconfig-work
[http]
	extraHeader = Authorization: x \
		y
	postBuffer = 1
'

# git's config rides only once switched on, and less what is private: a key,
# a credential, a signing setting, an includeIf, a url's insteadOf, each with
# the lines continuing it. The name and the email ride, a header stays, and a
# private line rides under a hi-allow alone, where it is listed.
function test_git_keeps_its_keys_and_credentials_home() {
  local dir out w
  dir="$(_hi_lint_fixture gitkeys git/config "$_HI_LINT_GITCONFIG")"
  out="$(_HI_CONFIG_DIR="$dir" _hi_overlay_files)"
  [ -z "$out" ] || _hi_because "git rode without being switched on: $out" || return 1
  out="$(_HI_PLUGINS_ON=git _HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat git/config)"
  [ "$out" = '[user]
name = A User
email = a@example.com
[alias]
co = checkout
[commit]
[credential "https://example.com"]
[url "git@example.com:"]
[core]
sshCommand = ssh -o Compression=yes
[gpg "ssh"]
[includeIf "gitdir:~/work/"]
[http]
postBuffer = 1' ] || _hi_because "git/config arrived as: [$out]" || return 1
  out="$(_HI_PLUGINS_ON=git _HI_CONFIG_DIR="$dir" _hi_include_lint)"
  [ -z "$out" ] || _hi_because "what stays home was a finding: $out" || return 1
  out="$(_HI_PLUGINS_ON=git _HI_CONFIG_DIR="$dir" _hi_allowed_lines)"
  [ "$out" = 'git/config|16|allowed|sshCommand = ssh -o Compression=yes' ] || _hi_because "the allowed lines: [$out]" || return 1
  _hi_overlay_wiring w git/config
  [[ "$w" == *'export GIT_CONFIG_COUNT="1" GIT_CONFIG_KEY_0="include.path" GIT_CONFIG_VALUE_0="$_HI_CONFIG_DIR/git/config"'* ]] ||
    _hi_because "its wiring: $w"
}

# ...and a real git reads what rode over a target's own config, which it
# still reads: the carried alias and the target's, and no key
function test_git_reads_what_rode_over_its_own_config() {
  local dir got="$_HI_WORKDIR/git-got" out
  dir="$(_hi_lint_fixture gitkeys git/config "$_HI_LINT_GITCONFIG")"
  mkdir -p "$got/home"
  printf '[alias]\n\ttheirs = status\n' >"$got/home/.gitconfig"
  _HI_PLUGINS_ON=git _HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar -x -z -f - -C "$got" || _hi_why dir got || return 1
  out="$(
    export HOME="$got/home" GIT_CONFIG_GLOBAL="$got/home/.gitconfig" GIT_CONFIG_NOSYSTEM=1
    export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=include.path GIT_CONFIG_VALUE_0="$got/git/config"
    for key in alias.co alias.theirs user.email user.signingkey commit.gpgsign core.sshcommand; do
      printf '%s=%s\n' "$key" "$(git config --get "$key" 2>&1)"
    done
  )"
  [ "$out" = 'alias.co=checkout
alias.theirs=status
user.email=a@example.com
user.signingkey=
commit.gpgsign=
core.sshcommand=ssh -o Compression=yes' ] || _hi_because "git answered: [$out]"
}

# ...and an include of it under git's own directory rides, read the same way
function test_a_git_include_rides_less_its_keys() {
  local dir home="$_HI_WORKDIR/githome" out
  mkdir -p "$home/.config/git"
  printf '[alias]\n\tst = status\n[user]\n\tsigningkey = ZZZ\n' >"$home/.config/git/extra"
  dir="$(_hi_lint_fixture gitinc git/config '[include]
	path = ~/.config/git/extra
')"
  out="$(HOME="$home" XDG_CONFIG_HOME="$home/.config" _HI_PLUGINS_ON=git _HI_CONFIG_DIR="$dir" _hi_overlay_tar | _hi_tar_cat git/extra)"
  [ "$out" = '[alias]
st = status
[user]' ] || _hi_because "git/extra arrived as: [$out]"
}

function run_hi_payload_scan_tests() {
  _hi_payload_begin

  _hi_h1 "Testing hi.sh: the include scan"

  _hi_h2 "Testing: the include scan"
  _hi_check "An unresolvable include is dropped" test_editor_includes_are_dropped_on_the_way_out
  _hi_check "A lua finding takes its expression with it" test_a_dropped_expression_goes_out_whole
  _hi_check "...and so does neovim's own vim.pack.add" test_vim_pack_add_is_a_plugin_finding
  _hi_check "A tmux finding takes its continuation with it" test_tmux_includes_are_dropped_on_the_way_out
  _hi_check "A multiplexer's default shell stays home" test_a_multiplexers_default_shell_stays_home
  _hi_check "Every zellij plugin path is dropped, a bar's pane keeps a bar" test_every_zellij_plugin_path_is_dropped
  _hi_check "An include under the tool's own directory rides" test_an_include_under_the_tools_directory_rides
  _hi_check "A line under hi-carry rides the files it names" test_a_marked_line_rides_the_files_it_names
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
  _hi_check "A module neovim's init.lua requires rides, on its runtimepath" test_a_required_neovim_module_rides
  local nvim
  _hi_real_nvim nvim
  _hi_check_requires "$nvim" "...which a real neovim loads from the overlay" test_neovim_loads_the_modules_that_rode
  _hi_check "neovim's init.vim rides, read as vim script" test_neovim_s_init_vim_rides_in_the_vim_dialect
  _hi_check "git's config rides less its keys and credentials" test_git_keeps_its_keys_and_credentials_home
  _hi_check_requires git "...read by a real git over a target's own config" test_git_reads_what_rode_over_its_own_config
  _hi_check "...and so does an include of it" test_a_git_include_rides_less_its_keys
  _hi_suite_end "hi.sh (the include scan)"
}

run_hi_payload_scan_tests
