#!/bin/sh
# SPDX-License-Identifier: MIT
# Every path hi uses, in one place. Fish sources this too, so plain
# `export NAME=value` lines only (plus `[ ] && export` guards, and one `.` of
# more such lines) - no functions, no ${var:-...}. $_HI_HOME and $_HI_CONFIG_DIR must already be set.
# shellcheck disable=SC2139 # aliases are meant to expand $_HI_* now, not later
# shellcheck disable=SC2153 # $_HI_HOME is set by whoever sources this, not here

export _HI_ROOT="$_HI_HOME/say-hi"
export _HI_LAUNCHER="$_HI_ROOT/hi.sh"
export _HI_CORE="$_HI_ROOT/common/core.sh"
export _HI_HEADER="$_HI_ROOT/common/header.sh"
# a client with the header off sends no header.sh; no file, no header
[ -f "$_HI_HEADER" ] || export _HI_DISABLE_HEADER=1
export _HI_GIT_PROMPT="$_HI_ROOT/common/git_prompt.sh"
export _HI_ENV_PROMPT="$_HI_ROOT/common/env_prompt.sh"
export _HI_TARGETS="$_HI_ROOT/common/targets.sh"
export _HI_INSTALL="$_HI_ROOT/scripts/install.sh"
export _HI_PREVIEW="$_HI_ROOT/scripts/preview.sh"
export _HI_DOCTOR="$_HI_ROOT/scripts/doctor.sh"
export _HI_UPDATE="$_HI_ROOT/scripts/update.sh"
export _HI_ADD_PACKAGE="$_HI_ROOT/scripts/add_package.sh"
export _HI_ADD_TAG="$_HI_ROOT/scripts/add_tag.sh"
export _HI_COLOR_PIN="$_HI_ROOT/scripts/set_color.sh"
export _HI_PLUGINS_CMD="$_HI_ROOT/scripts/plugins.sh"

# tests - only the two entry points every session needs
export _HI_TEST_LIB="$_HI_ROOT/tests/test_lib.sh"
export _HI_TEST_RUN="$_HI_ROOT/tests/test_runner.sh"

# User config lives in $_HI_CONFIG_DIR, outside the tree; settings.sh has no
# in-tree half. Each variable below is its member's row of hi.sh's
# $_HI_OVERLAY_TABLE, the one order (GLOSSARY: HI.61), spelled out: the
# overlay's copy, else the tool's own config on this machine, else the
# tree's where there is one - re-derived on every source, so a child shell told
# `_HI_CONFIG_DIR=elsewhere` reads that overlay, and an exported path of your
# own does not survive. A line per candidate, lowest priority first, since
# this dialect has no if/elif and no ${var:-...} and the last assignment wins;
# paths_test.sh pins the lines to the table. The home tier is client-only: on
# a target $HOME is the *target's*, whose rcs are exactly what hi's
# `-u`/`--rcfile`/`-q -l` exist to keep out of the session, and the file the
# client picked is already unpacked at $_HI_CONFIG_DIR.
export _HI_SETTINGS="$_HI_CONFIG_DIR/settings.sh"
export _HI_COLORS="$_HI_ROOT/config/colors"
[ -f "$_HI_CONFIG_DIR/colors" ] && export _HI_COLORS="$_HI_CONFIG_DIR/colors"
# the package check; `hi --add-package` copies the tree's in before its
# first write, so a copy of your own starts with every stock row
export _HI_PACKAGES="$_HI_ROOT/config/packages"
[ -f "$_HI_CONFIG_DIR/packages" ] && export _HI_PACKAGES="$_HI_CONFIG_DIR/packages"
# drop-in plugins, sourced after the aliases; the same only home (HI.59)
export _HI_PLUGINS_D="$_HI_CONFIG_DIR/plugins.d"
# The editor rcs: within the home tier the editor's own precedence, reversed.
# No tree default: with no config anywhere the value is empty and
# common/aliases.sh leaves the editor alone.
export _HI_VIMRC=""
[ "$_HI_REMOTE_SESSION" != 1 ] && [ -f "$_HI_XDG_CONFIG/vim/vimrc" ] && export _HI_VIMRC="$_HI_XDG_CONFIG/vim/vimrc"
[ "$_HI_REMOTE_SESSION" != 1 ] && [ -f "$HOME/.vim/vimrc" ] && export _HI_VIMRC="$HOME/.vim/vimrc"
[ "$_HI_REMOTE_SESSION" != 1 ] && [ -f "$HOME/.vimrc" ] && export _HI_VIMRC="$HOME/.vimrc"
[ -f "$_HI_CONFIG_DIR/vimrc" ] && export _HI_VIMRC="$_HI_CONFIG_DIR/vimrc"
export _HI_NVIMRC=""
[ "$_HI_REMOTE_SESSION" != 1 ] && [ -f "$_HI_XDG_CONFIG/nvim/init.lua" ] && export _HI_NVIMRC="$_HI_XDG_CONFIG/nvim/init.lua"
[ -f "$_HI_CONFIG_DIR/init.lua" ] && export _HI_NVIMRC="$_HI_CONFIG_DIR/init.lua"
# helix has no dotfile fallback, XDG only - the same shape as nvim's, above
export _HI_HELIXRC=""
[ "$_HI_REMOTE_SESSION" != 1 ] && [ -f "$_HI_XDG_CONFIG/helix/config.toml" ] && export _HI_HELIXRC="$_HI_XDG_CONFIG/helix/config.toml"
[ -f "$_HI_CONFIG_DIR/config.toml" ] && export _HI_HELIXRC="$_HI_CONFIG_DIR/config.toml"
export _HI_NANORC=""
[ "$_HI_REMOTE_SESSION" != 1 ] && [ -f "$_HI_XDG_CONFIG/nano/nanorc" ] && export _HI_NANORC="$_HI_XDG_CONFIG/nano/nanorc"
[ "$_HI_REMOTE_SESSION" != 1 ] && [ -f "$HOME/.nanorc" ] && export _HI_NANORC="$HOME/.nanorc"
[ -f "$_HI_CONFIG_DIR/nanorc" ] && export _HI_NANORC="$_HI_CONFIG_DIR/nanorc"
export _HI_EMACSRC=""
[ "$_HI_REMOTE_SESSION" != 1 ] && [ -f "$_HI_XDG_CONFIG/emacs/init.el" ] && export _HI_EMACSRC="$_HI_XDG_CONFIG/emacs/init.el"
[ "$_HI_REMOTE_SESSION" != 1 ] && [ -f "$HOME/.emacs.d/init.el" ] && export _HI_EMACSRC="$HOME/.emacs.d/init.el"
[ "$_HI_REMOTE_SESSION" != 1 ] && [ -f "$HOME/.emacs" ] && export _HI_EMACSRC="$HOME/.emacs"
[ "$_HI_REMOTE_SESSION" != 1 ] && [ -f "$HOME/.emacs.el" ] && export _HI_EMACSRC="$HOME/.emacs.el"
[ -f "$_HI_CONFIG_DIR/init.el" ] && export _HI_EMACSRC="$_HI_CONFIG_DIR/init.el"
# tmux and screen the same
export _HI_TMUX_CONF=""
[ "$_HI_REMOTE_SESSION" != 1 ] && [ -f "$_HI_XDG_CONFIG/tmux/tmux.conf" ] && export _HI_TMUX_CONF="$_HI_XDG_CONFIG/tmux/tmux.conf"
[ "$_HI_REMOTE_SESSION" != 1 ] && [ -f "$HOME/.tmux.conf" ] && export _HI_TMUX_CONF="$HOME/.tmux.conf"
[ -f "$_HI_CONFIG_DIR/tmux.conf" ] && export _HI_TMUX_CONF="$_HI_CONFIG_DIR/tmux.conf"
export _HI_SCREENRC=""
[ "$_HI_REMOTE_SESSION" != 1 ] && [ -f "$_HI_SCREENRC_HOME" ] && export _HI_SCREENRC="$_HI_SCREENRC_HOME"
[ -f "$_HI_CONFIG_DIR/screenrc" ] && export _HI_SCREENRC="$_HI_CONFIG_DIR/screenrc"
# micro and zellij take a config *directory* with fixed file names, so their
# members ride in a micro/ and a zellij/ of their own, and the alias names
# the directory. $_HI_MICRO_HOME and $_HI_ZELLIJ_HOME are the tools' own
# (core.sh and config.fish spell the ${VAR:-} this dialect cannot).
export _HI_MICRO_DIR=""
[ "$_HI_REMOTE_SESSION" != 1 ] && [ -d "$_HI_MICRO_HOME" ] && export _HI_MICRO_DIR="$_HI_MICRO_HOME"
[ -d "$_HI_CONFIG_DIR/micro" ] && export _HI_MICRO_DIR="$_HI_CONFIG_DIR/micro"
export _HI_ZELLIJ_DIR=""
[ "$_HI_REMOTE_SESSION" != 1 ] && [ -d "$_HI_ZELLIJ_HOME" ] && export _HI_ZELLIJ_DIR="$_HI_ZELLIJ_HOME"
[ -d "$_HI_CONFIG_DIR/zellij" ] && export _HI_ZELLIJ_DIR="$_HI_CONFIG_DIR/zellij"
# The carried configs a variable points a tool at - a prompt program's, eza's,
# bat's, rg's, fzf's, lazygit's, readline's, kakoune's - on a target only: at
# home each tool's own config is already in force. A line each, written by
# hi.sh's _hi_overlay_wiring as the overlay is packed, for the members that
# rode. Only the tool named reads its variable, so none needs a gate but
# kakoune's, which sits behind the editor toggles.
# GLOSSARY: HI.62
# shellcheck source=/dev/null # written on the client, per connect
[ "$_HI_REMOTE_SESSION" = 1 ] && [ -f "$_HI_CONFIG_DIR/wiring.sh" ] && . "$_HI_CONFIG_DIR/wiring.sh"

export _HI_ALIASES="$_HI_ROOT/common/aliases.sh"
export _HI_BASHRC="$_HI_ROOT/common/bash.sh"
export _HI_ZSHRC="$_HI_ROOT/common/zsh.zsh"
export _HI_FISH_CONFIG="$_HI_ROOT/common/config.fish"

# install.sh's line tag and managed symlink, so everything recognising hi's
# lines reads one string. The link is the user's own bin directory - no sudo
# in a first install; install.sh's --link system is /usr/bin/hi, and a
# package's link there is the package's, never this one.
export _HI_MARKER="# added by hi during install"
export _HI_LINK="$HOME/.local/bin/hi"

# host paths hi reads or appends to
export _HI_LINUX_RELEASE="/etc/os-release"
export _HI_SSH_DIR="$HOME/.ssh"
export _HI_SSH_CONFIG="$HOME/.ssh/config"
export _HI_SSH_AUTHORIZED_KEYS="$HOME/.ssh/authorized_keys"
export _HI_HOME_BASHRC="$HOME/.bashrc"
export _HI_HOME_ZSHRC="$HOME/.zshrc"
export _HI_HOME_FISH_CONFIG="$HOME/.config/fish/config.fish"

# GLOSSARY: HI.10. Self-contained strings - fish can't call a bash helper.
export _HI_HUMAN_CENTRIC_DATE="+%a %b %e %Y %H:%M:%S %Z"

# What hi.sh's local sub-commands say when they cannot run: the payload ships
# no scripts/, tests/, or .git. Exported from here so the wording has one home.
export _HI_NO_CHECKOUT="needs the full say-hi checkout (a package has it too) - a hi session carries only the payload; git clone https://github.com/ivylikethevine/say-hi has one"

# The flags that take a completable word of their own. Here because all four
# shells need it and this is the only file all four read - spelled per shell,
# a word-taking flag added to targets.sh would never complete. targets.sh keeps the words themselves - it owns the content, and stays
# standalone POSIX - so this is the membership test and that is the roster.
export _HI_WORD_FLAGS="--preview --use --update --link --preset --add-package --remove-package --add-tag --set-color --unset-color --plugin-off --plugin-on --add-plugin --remove-plugin"
alias hi="$_HI_LAUNCHER"
# The one hi_* alias (every other command is a `hi --flag`): a single echo that
# answers in all four shells, and the test harness's "the session is up" probe.
alias hi_info="echo ' | hi_home: $_HI_HOME | hi_root: $_HI_ROOT | script: $_HI_LAUNCHER'"

# Local-only gate, reading settings each entry point sourced *ahead* of this
# file; _HI_REMOTE_SESSION tells local from remote.
export _HI_DISABLE_LOCAL
export _HI_REMOTE_SESSION

# core.sh's _HI_TOGGLES minus the gates' own three inputs, spelled out because
# this dialect can't loop; paths_test.sh pins the two lists together. One
# guarded line each: a `{ ... }` group is a block only from fish 4, and fish 3
# fails it at run time though `fish -n` passes it.
[ "$_HI_DISABLE_LOCAL" = 1 ] && [ "$_HI_REMOTE_SESSION" != 1 ] && export _HI_DISABLE_HEADER=1
[ "$_HI_DISABLE_LOCAL" = 1 ] && [ "$_HI_REMOTE_SESSION" != 1 ] && export _HI_DISABLE_PROMPT=1
[ "$_HI_DISABLE_LOCAL" = 1 ] && [ "$_HI_REMOTE_SESSION" != 1 ] && export _HI_DISABLE_GIT_STATUS=1
[ "$_HI_DISABLE_LOCAL" = 1 ] && [ "$_HI_REMOTE_SESSION" != 1 ] && export _HI_DISABLE_ENV_STATUS=1
[ "$_HI_DISABLE_LOCAL" = 1 ] && [ "$_HI_REMOTE_SESSION" != 1 ] && export _HI_DISABLE_EDITORS=1
[ "$_HI_DISABLE_LOCAL" = 1 ] && [ "$_HI_REMOTE_SESSION" != 1 ] && export _HI_DISABLE_VIM=1
[ "$_HI_DISABLE_LOCAL" = 1 ] && [ "$_HI_REMOTE_SESSION" != 1 ] && export _HI_DISABLE_NANO=1
[ "$_HI_DISABLE_LOCAL" = 1 ] && [ "$_HI_REMOTE_SESSION" != 1 ] && export _HI_DISABLE_EMACS=1
[ "$_HI_DISABLE_LOCAL" = 1 ] && [ "$_HI_REMOTE_SESSION" != 1 ] && export _HI_DISABLE_MICRO=1
[ "$_HI_DISABLE_LOCAL" = 1 ] && [ "$_HI_REMOTE_SESSION" != 1 ] && export _HI_DISABLE_HELIX=1
[ "$_HI_DISABLE_LOCAL" = 1 ] && [ "$_HI_REMOTE_SESSION" != 1 ] && export _HI_DISABLE_KAKOUNE=1
[ "$_HI_DISABLE_LOCAL" = 1 ] && [ "$_HI_REMOTE_SESSION" != 1 ] && export _HI_DISABLE_TMUX=1
[ "$_HI_DISABLE_LOCAL" = 1 ] && [ "$_HI_REMOTE_SESSION" != 1 ] && export _HI_DISABLE_SCREEN=1
[ "$_HI_DISABLE_LOCAL" = 1 ] && [ "$_HI_REMOTE_SESSION" != 1 ] && export _HI_DISABLE_ZELLIJ=1
[ "$_HI_DISABLE_LOCAL" = 1 ] && [ "$_HI_REMOTE_SESSION" != 1 ] && export _HI_TOOL_ALIASES=0
[ "$_HI_DISABLE_LOCAL" = 1 ] && [ "$_HI_REMOTE_SESSION" != 1 ] && export _HI_SUDO_ALIAS=0
[ "$_HI_DISABLE_LOCAL" = 1 ] && [ "$_HI_REMOTE_SESSION" != 1 ] && export _HI_DISABLE_BANNER=1
[ "$_HI_DISABLE_LOCAL" = 1 ] && [ "$_HI_REMOTE_SESSION" != 1 ] && export _HI_DISABLE_GREETING=1
true # the file's status, whichever way the last line went
